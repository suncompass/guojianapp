package core

import (
	"context"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

const (
	hongguoSearchSeasonLimit              = 200
	hongguoSearchSeasonQueries            = 2
	hongguoSearchSeasonTimeout            = 25 * time.Second
	hongguoSearchSeasonExtensionQueries   = 64
	hongguoSearchSeasonExtensionPerSeries = 12
	hongguoSearchSeasonExtensionMisses    = 3
	hongguoSearchContinuationQueries      = 4
)

// hongguoSearchSeasonCursor 记录一次搜索已经试过的补齐查询，让「加载更多」
// 从上次停下的位置继续，而不是把同一批查询重跑一遍。
type hongguoSearchSeasonCursor struct {
	Grouped   []*hongguoSearchSeries
	Attempted map[string]bool
	Done      bool
}

var hongguoSearchSeasonSuffix = regexp.MustCompile(`第\s*([0-9零〇一二两兩三四五六七八九十百]+)\s*([季部])[\p{P}\s]*$`)

type hongguoSearchSeries struct {
	title   string
	key     string
	unit    string
	maximum int
	known   map[int]bool
	labels  map[int]string
}

func hongguoSearchSeason(title string) (string, int, string, string) {
	title = norm.NFKC.String(strings.TrimSpace(title))
	match := hongguoSearchSeasonSuffix.FindStringSubmatchIndex(title)
	if match == nil {
		return "", 0, "", ""
	}
	base := strings.TrimRightFunc(title[:match[0]], func(r rune) bool { return unicode.IsSpace(r) || unicode.IsPunct(r) })
	label, unit := title[match[2]:match[3]], title[match[4]:match[5]]
	number, err := strconv.Atoi(label)
	if err != nil {
		number = 0
		digits := map[rune]int{'零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '兩': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9}
		if !strings.ContainsAny(label, "十百") {
			for _, r := range label {
				value, ok := digits[r]
				if !ok {
					return "", 0, "", ""
				}
				number = number*10 + value
				if number > hongguoSearchSeasonLimit {
					return "", 0, "", ""
				}
			}
		} else {
			digit, previous := 0, 1000
			for _, r := range label {
				if value, ok := digits[r]; ok {
					digit = digit*10 + value
					continue
				}
				value := 10
				if r == '百' {
					value = 100
				}
				if value >= previous || digit > 9 {
					return "", 0, "", ""
				}
				number += max(digit, 1) * value
				digit, previous = 0, value
			}
			number += digit
		}
	}
	if base == "" || number < 1 || number > hongguoSearchSeasonLimit {
		return "", 0, "", ""
	}
	return base, number, unit, label
}

func hongguoSearchChineseSeason(number int) string {
	digits := []rune("零一二三四五六七八九")
	if number < 10 {
		return string(digits[number])
	}
	if number < 100 {
		prefix := ""
		if number >= 20 {
			prefix = string(digits[number/10])
		}
		prefix += "十"
		if number%10 != 0 {
			prefix += string(digits[number%10])
		}
		return prefix
	}
	prefix, rest := string(digits[number/100])+"百", number%100
	if rest == 0 {
		return prefix
	}
	if rest < 10 {
		prefix += "零"
	} else if rest < 20 {
		prefix += "一"
	}
	return prefix + hongguoSearchChineseSeason(rest)
}

func (series *hongguoSearchSeries) add(drama Drama) bool {
	base, season, unit, label := hongguoSearchSeason(drama.DisplayTitle())
	if season == 0 && hongguoSearchText(drama.DisplayTitle()) == series.key {
		season = 1
	} else if season == 0 || unit != series.unit || hongguoSearchText(base) != series.key {
		return false
	}
	series.known[season] = true
	series.maximum = max(series.maximum, season)
	if label != "" {
		series.labels[season] = label
	}
	return true
}

func hongguoSearchSeriesGroups(keyword string, dramas []Drama) []*hongguoSearchSeries {
	if _, season, _, _ := hongguoSearchSeason(keyword); season > 0 {
		return nil
	}
	query := hongguoSearchText(keyword)
	var groups []*hongguoSearchSeries
	byKey := map[string]*hongguoSearchSeries{}
	for _, drama := range dramas {
		base, season, unit, _ := hongguoSearchSeason(drama.DisplayTitle())
		key := hongguoSearchText(base)
		if season == 0 || !strings.Contains(key, query) {
			continue
		}
		groupKey := key + ":" + unit
		if byKey[groupKey] == nil {
			series := &hongguoSearchSeries{title: base, key: key, unit: unit, known: map[int]bool{}, labels: map[int]string{}}
			byKey[groupKey] = series
			groups = append(groups, series)
		}
	}
	var incomplete []*hongguoSearchSeries
	for _, group := range groups {
		for _, drama := range dramas {
			group.add(drama)
		}
		if len(group.known) >= 1 {
			incomplete = append(incomplete, group)
		}
	}
	sort.SliceStable(incomplete, func(left, right int) bool {
		l, r := incomplete[left], incomplete[right]
		lr, rr := hongguoTitleSearchRank(l.title, query), hongguoTitleSearchRank(r.title, query)
		if lr != rr {
			return lr < rr
		}
		return len(l.known) > len(r.known)
	})
	return incomplete
}

func (series *hongguoSearchSeries) nextQuery(attempted map[string]bool) string {
	for season := 1; season <= series.maximum; season++ {
		if series.known[season] {
			continue
		}
		nearest, distance := 0, hongguoSearchSeasonLimit+1
		for known := 1; known <= series.maximum; known++ {
			delta := max(known-season, season-known)
			if series.labels[known] != "" && delta < distance {
				nearest, distance = known, delta
			}
		}
		labels := []string{hongguoSearchChineseSeason(season), strconv.Itoa(season)}
		if _, err := strconv.Atoi(series.labels[nearest]); err == nil {
			labels[0], labels[1] = labels[1], labels[0]
		}
		var queries []string
		if season == 1 {
			queries = append(queries, series.title)
		}
		for _, label := range labels {
			queries = append(queries, series.title+"第"+label+series.unit)
		}
		for _, query := range queries {
			if _, err := hongguoSearchKeyword(query); err == nil && !attempted[query] {
				return query
			}
		}
	}
	return ""
}

func (series *hongguoSearchSeries) extensionQuery(from int, attempted map[string]bool) string {
	if _, err := hongguoSearchKeyword(series.title); err == nil && !attempted[series.title] {
		return series.title
	}
	for season := from; season <= hongguoSearchSeasonLimit; season++ {
		nearest, distance := 0, hongguoSearchSeasonLimit+1
		for known := 1; known <= series.maximum; known++ {
			delta := max(known-season, season-known)
			if series.labels[known] != "" && delta < distance {
				nearest, distance = known, delta
			}
		}
		labels := []string{hongguoSearchChineseSeason(season), strconv.Itoa(season)}
		if _, err := strconv.Atoi(series.labels[nearest]); err == nil {
			labels[0], labels[1] = labels[1], labels[0]
		}
		for _, label := range labels {
			query := series.title + "第" + label + series.unit
			if _, err := hongguoSearchKeyword(query); err == nil && !attempted[query] {
				return query
			}
		}
	}
	return ""
}

func (downloader *Downloader) completeHongguoSearchSeasons(ctx context.Context, keyword string, entry *hongguoSearchEntry) bool {
	groups := hongguoSearchSeriesGroups(keyword, entry.Dramas)
	if len(groups) == 0 {
		return false
	}
	client := downloader.hongguoClient()
	client.mu.Lock()
	client.searchSeasons[keyword] = &hongguoSearchSeasonCursor{Grouped: groups, Attempted: map[string]bool{keyword: true}}
	if len(client.searchSeasons) > 64 {
		client.searchSeasons = map[string]*hongguoSearchSeasonCursor{keyword: {Grouped: groups, Attempted: map[string]bool{keyword: true}}}
	}
	client.mu.Unlock()
	// 第 1 页只跑一小批探测，剩下的交给用户点「加载更多」逐页补齐。
	return downloader.runHongguoSearchSeasons(ctx, keyword, entry, hongguoSearchSeasonQueries)
}

func (downloader *Downloader) extendHongguoSearchSeasons(
	ctx context.Context,
	group *hongguoSearchSeries,
	entry *hongguoSearchEntry,
	attempted map[string]bool,
	requests *int,
	budget int,
) bool {
	misses := 0
	used := 0
	from := group.maximum + 1
	for used < hongguoSearchSeasonExtensionPerSeries {
		if *requests >= budget {
			return false
		}
		query := group.extensionQuery(from, attempted)
		if query == "" {
			return true
		}
		attempted[query] = true
		(*requests)++
		used++
		var matches []Drama
		for _, drama := range downloader.hongguoSearchProbe(ctx, query) {
			if group.add(drama) {
				matches = append(matches, drama)
			}
		}
		if len(matches) > 0 {
			misses = 0
			entry.Dramas = mergeHongguoSearchDramas(entry.Dramas, matches)
			reportHongguoSearchProgress(ctx, *entry)
			from = group.maximum + 1
			continue
		}
		misses++
		if misses >= hongguoSearchSeasonExtensionMisses {
			return true
		}
		from++
	}
	return false
}

// runHongguoSearchSeasons 跑一批受数量约束的季数探测。每批都从游标处继续，
// 因此分页的每一页都会带出上一页没覆盖到的季数，跑完一批没有可试的查询即收口。
func (downloader *Downloader) runHongguoSearchSeasons(ctx context.Context, keyword string, entry *hongguoSearchEntry, budget int) bool {
	client := downloader.hongguoClient()
	client.mu.Lock()
	cursor := client.searchSeasons[keyword]
	client.mu.Unlock()
	if cursor == nil || cursor.Done || len(cursor.Grouped) == 0 {
		return false
	}
	attempted := cursor.Attempted
	if attempted == nil {
		attempted = map[string]bool{keyword: true}
		cursor.Attempted = attempted
	}
	budget = max(1, budget)
	deadline := hongguoSearchSeasonTimeout
	if limit, ok := ctx.Deadline(); ok {
		deadline = min(deadline, time.Until(limit)-100*time.Millisecond)
	}
	if deadline <= 0 {
		return true
	}
	ctx, cancel := context.WithTimeout(ctx, deadline)
	defer cancel()
	grouped := cursor.Grouped
	before := len(entry.Dramas)
	requests := 0
	for _, group := range grouped {
		for requests < budget {
			query := group.nextQuery(attempted)
			if query == "" {
				break
			}
			attempted[query] = true
			requests++
			var matches []Drama
			for _, drama := range downloader.hongguoSearchProbe(ctx, query) {
				if group.add(drama) {
					matches = append(matches, drama)
				}
			}
			if len(matches) > 0 {
				entry.Dramas = mergeHongguoSearchDramas(entry.Dramas, matches)
				reportHongguoSearchProgress(ctx, *entry)
			}
		}
	}
	limited := requests >= budget
	for _, group := range grouped {
		if budget <= requests {
			limited = true
			break
		}
		if !downloader.extendHongguoSearchSeasons(ctx, group, entry, attempted, &requests, budget) {
			limited = true
		}
	}
	// 一整批探测都没带回新剧集，说明这个词已经捞干，收口停止再提示加载更多。
	if requests == 0 || len(entry.Dramas) <= before {
		client.mu.Lock()
		cursor.Done = true
		client.mu.Unlock()
		return false
	}
	return limited
}

// hongguoSearchContinuationPending 判断游标里是否还留着没试过的补齐查询。
func (downloader *Downloader) hongguoSearchContinuationPending(keyword string) bool {
	client := downloader.hongguoClient()
	client.mu.Lock()
	cursor := client.searchSeasons[keyword]
	client.mu.Unlock()
	if cursor == nil || cursor.Done || len(cursor.Grouped) == 0 {
		return false
	}
	attempted := cursor.Attempted
	if attempted == nil {
		attempted = map[string]bool{keyword: true}
	}
	for _, group := range cursor.Grouped {
		if group.nextQuery(attempted) != "" {
			return true
		}
		if group.extensionQuery(group.maximum+1, attempted) != "" {
			return true
		}
	}
	return false
}
