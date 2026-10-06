package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/net/html"
)

const (
	chaoguoCatalogPageSize = 30
	chaoguoClassPrefix     = "class:"
	chaoguoTagPrefix       = "tag:"
	chaoguoDefaultSort     = "hot"
)

var (
	chaoguoSlugPattern         = regexp.MustCompile(`^[a-z0-9]{6,16}$`)
	chaoguoPlayCountPattern    = regexp.MustCompile(`^([0-9]+(?:\.[0-9]+)?[万亿]?)\s*播放$`)
	chaoguoScorePattern        = regexp.MustCompile(`^⭐?\s*([0-9]+(?:\.[0-9]+)?)$`)
	chaoguoPlayablePattern     = regexp.MustCompile(`^([0-9]+)\s*/\s*([0-9]+)\s*可播放$`)
	chaoguoEpisodeCountPattern = regexp.MustCompile(`^([0-9]+)\s*集$`)
)

var chaoguoClassNames = map[string]string{
	"mainstream": "主流剧情",
	"adult":      "成人向",
	"anime_ip":   "动漫风格",
	"unknown":    "其他",
}

var chaoguoCoverAttributes = []string{"data-original", "data-src", "src", "poster"}

func chaoguoCoverFromNodes(nodes []*html.Node, pageURL string) string {
	for _, node := range nodes {
		for _, attribute := range chaoguoCoverAttributes {
			if address := providerCoverAddress(providerHTMLAttr(node, attribute), pageURL); address != "" {
				return address
			}
		}
	}
	return ""
}

func validChaoguoCategory(category string) bool {
	category = strings.TrimSpace(category)
	if category == "" {
		return true
	}
	if len(category) > 64 {
		return false
	}
	switch {
	case strings.HasPrefix(category, chaoguoClassPrefix):
		_, found := chaoguoClassNames[strings.TrimPrefix(category, chaoguoClassPrefix)]
		return found
	case strings.HasPrefix(category, chaoguoTagPrefix):
		return validChaoguoTag(strings.TrimPrefix(category, chaoguoTagPrefix))
	default:
		return validChaoguoTag(category)
	}
}

func validChaoguoTag(tag string) bool {
	tag = strings.TrimSpace(tag)
	if tag == "" || len([]rune(tag)) > 16 {
		return false
	}
	for _, letter := range tag {
		switch {
		case letter >= 'a' && letter <= 'z',
			letter >= 'A' && letter <= 'Z',
			letter >= '0' && letter <= '9',
			letter >= 0x4E00 && letter <= 0x9FFF,
			letter == '-' || letter == '_':
			continue
		default:
			return false
		}
	}
	return true
}

func chaoguoCatalogAddress(base, category string, page int) string {
	if page < 1 {
		page = 1
	}
	base = strings.TrimRight(strings.TrimSpace(base), "/")
	category = strings.TrimSpace(category)
	switch {
	case strings.HasPrefix(category, chaoguoClassPrefix):
		class := strings.TrimPrefix(category, chaoguoClassPrefix)
		return fmt.Sprintf("%s/explore?class=%s&sort=%s&page=%d", base, url.QueryEscape(class), chaoguoDefaultSort, page)
	case strings.HasPrefix(category, chaoguoTagPrefix):
		tag := strings.TrimPrefix(category, chaoguoTagPrefix)
		return fmt.Sprintf("%s/tag/%s?page=%d", base, url.PathEscape(tag), page)
	case category != "":
		return fmt.Sprintf("%s/tag/%s?page=%d", base, url.PathEscape(category), page)
	default:
		return fmt.Sprintf("%s/explore?sort=%s&page=%d", base, chaoguoDefaultSort, page)
	}
}

func chaoguoSlugFromLink(link string) string {
	parsed, err := url.Parse(strings.TrimSpace(link))
	if err != nil {
		return ""
	}
	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
	if len(parts) < 2 || !strings.EqualFold(parts[len(parts)-2], "drama") {
		return ""
	}
	slug := strings.ToLower(strings.TrimSpace(parts[len(parts)-1]))
	if !chaoguoSlugPattern.MatchString(slug) {
		return ""
	}
	return slug
}

func chaoguoCardTitle(card *html.Node) string {
	if title := strings.TrimSpace(providerHTMLAttr(card, "title")); title != "" {
		return duanjuPlainText(title)
	}
	for _, name := range []string{"card-title", "rank-title"} {
		if node := providerHTMLFirstClass(card, name); node != nil {
			if title := providerHTMLText(node); title != "" {
				return title
			}
		}
	}
	return ""
}

func chaoguoCardCover(card *html.Node, pageURL string) string {
	return chaoguoCoverFromNodes(providerHTMLNodes(card, func(node *html.Node) bool {
		return node.Data == "img" || node.Data == "video"
	}), pageURL)
}

func chaoguoLeadingSegment(text string) string {
	return strings.TrimSpace(strings.Split(strings.TrimSpace(text), "·")[0])
}

func chaoguoEpisodeCount(card *html.Node) int {
	for _, name := range []string{"card-eps", "rank-meta"} {
		container := providerHTMLFirstClass(card, name)
		if container == nil {
			continue
		}
		lead := chaoguoLeadingSegment(providerHTMLText(container))
		if matches := chaoguoEpisodeCountPattern.FindStringSubmatch(lead); len(matches) > 1 {
			if count, err := strconv.Atoi(matches[1]); err == nil && count > 0 {
				return count
			}
		}
		if count := episodeIndex(lead, 0); count > 0 {
			return count
		}
	}
	return 0
}

func chaoguoDramaFromCard(card *html.Node, pageURL, base string) Drama {
	slug := chaoguoSlugFromLink(providerHTMLAttr(card, "href"))
	if slug == "" {
		return Drama{}
	}
	title := chaoguoCardTitle(card)
	if title == "" {
		return Drama{}
	}
	episodes := chaoguoEpisodeCount(card)
	remark := ""
	if episodes > 0 {
		remark = fmt.Sprintf("%d 集", episodes)
	}
	brief := ""
	if node := providerHTMLFirstClass(card, "card-brief"); node != nil {
		brief = truncate(providerHTMLText(node), 200)
	}
	return Drama{
		ID:           providerDramaID(sourceChaoguo, slug),
		Source:       sourceChaoguo,
		SourceID:     slug,
		Title:        title,
		Intro:        brief,
		Cover:        chaoguoCardCover(card, duanjuAbsolute(base, providerHTMLAttr(card, "href"))),
		Remark:       remark,
		EpisodeCount: json.Number(strconv.Itoa(episodes)),
		ChannelName:  duanjuSourceName(sourceChaoguo),
	}
}

func chaoguoDramasFromDocument(document *html.Node, base string) []Drama {
	pageURL := base + "/"
	var items []Drama
	seen := map[string]bool{}
	for _, card := range providerHTMLNodes(document, func(node *html.Node) bool {
		return node.Data == "a" && providerHTMLClass(node, "card")
	}) {
		drama := chaoguoDramaFromCard(card, pageURL, base)
		if drama.ID == "" || seen[drama.SourceID] {
			continue
		}
		seen[drama.SourceID] = true
		items = append(items, drama)
	}
	return items
}

func (d *Downloader) fetchChaoguoCatalogPage(ctx context.Context, page int, category string) ([]Drama, bool, error) {
	if page < 1 {
		page = 1
	}
	category = strings.TrimSpace(category)
	if !validChaoguoCategory(category) {
		return nil, false, errors.New("内容分类无效")
	}
	base := d.duanjuBaseURL(sourceChaoguo)
	if base == "" {
		return nil, false, errors.New("站源地址不可用")
	}
	address := chaoguoCatalogAddress(base, category, page)
	document, _, err := d.fetchProviderPage(ctx, address, base+"/", duanjuUserAgent)
	if err != nil {
		return nil, false, err
	}
	items := chaoguoDramasFromDocument(document, base)
	return items, len(items) >= chaoguoCatalogPageSize, nil
}

func chaoguoEpisodeTitle(raw string, number int) string {
	title := strings.TrimSpace(raw)
	if cut, _, found := strings.Cut(title, "·"); found {
		title = strings.TrimSpace(cut)
	}
	if strings.HasPrefix(title, "第") && strings.HasSuffix(title, "集") && episodeIndex(title, 0) == number {
		return title
	}
	return fmt.Sprintf("第%d集", number)
}

func chaoguoChapters(document *html.Node, sourceID, pageURL, referer string) []Chapter {
	var chapters []Chapter
	seen := map[int]bool{}
	for _, node := range providerHTMLNodes(document, func(node *html.Node) bool {
		return node.Data == "button" && providerHTMLClass(node, "ep-btn")
	}) {
		address := strings.TrimSpace(providerHTMLAttr(node, "data-src"))
		if !isProviderHTTPMediaURL(address) || !duanjuLooksLikeMedia(address) {
			continue
		}
		number, _ := strconv.Atoi(strings.TrimSpace(providerHTMLAttr(node, "data-seq")))
		if number <= 0 {
			number = episodeIndex(providerHTMLAttr(node, "title"), 0)
		}
		if number <= 0 {
			number = len(chapters) + 1
		}
		number = nextUnusedEpisodeIndex(number, seen)
		seen[number] = true
		chapters = append(chapters, duanjuChapter(sourceChaoguo, sourceID, number,
			chaoguoEpisodeTitle(providerHTMLAttr(node, "title"), number), address, pageURL, referer))
	}
	return chapters
}

func chaoguoDetailMeta(document *html.Node) (episodes int, score, views, category string) {
	meta := providerHTMLFirstClass(document, "hero-meta")
	if meta == nil {
		return 0, "", "", ""
	}
	for _, node := range providerHTMLNodes(meta, func(node *html.Node) bool { return node.Data == "span" }) {
		if providerHTMLClass(node, "tag-orig") {
			continue
		}
		text := providerHTMLText(node)
		if text == "" {
			continue
		}
		if matches := chaoguoPlayCountPattern.FindStringSubmatch(text); len(matches) > 1 {
			views = text
			continue
		}
		if matches := chaoguoScorePattern.FindStringSubmatch(text); len(matches) > 1 {
			score = matches[1]
			continue
		}
		if matches := chaoguoEpisodeCountPattern.FindStringSubmatch(text); len(matches) > 1 {
			if count, err := strconv.Atoi(matches[1]); err == nil && count > 0 {
				episodes = count
			}
			continue
		}
		if category == "" {
			category = text
		}
	}
	return episodes, score, views, category
}

func chaoguoDetailDrama(document *html.Node, sourceID, pageURL string) Drama {
	title := ""
	if node := providerHTMLFirstClass(document, "watch-title"); node != nil {
		title = providerHTMLText(node)
	}
	if title == "" {
		if node := providerHTMLFirstClass(document, "rank-title"); node != nil {
			title = providerHTMLText(node)
		}
	}
	episodes, score, views, category := chaoguoDetailMeta(document)
	var tags []string
	if chips := providerHTMLFirstClass(document, "chips"); chips != nil {
		for _, anchor := range providerHTMLNodes(chips, func(node *html.Node) bool { return node.Data == "a" }) {
			if tag := providerHTMLText(anchor); tag != "" {
				tags = append(tags, tag)
			}
		}
	}
	status := ""
	if node := providerHTMLFirstClass(document, "muted"); node != nil {
		if matches := chaoguoPlayablePattern.FindStringSubmatch(providerHTMLText(node)); len(matches) > 2 {
			if playable, err := strconv.Atoi(matches[1]); err == nil && playable > 0 {
				if total, err := strconv.Atoi(matches[2]); err == nil && playable >= total {
					status = "finished"
					if episodes <= 0 {
						episodes = total
					}
				}
			}
		}
	}
	return Drama{
		ID:            providerDramaID(sourceChaoguo, sourceID),
		Source:        sourceChaoguo,
		SourceID:      sourceID,
		Title:         title,
		Intro:         truncate(providerHTMLText(providerHTMLFirstClass(document, "watch-desc")), 2000),
		Cover:         chaoguoCoverFromNodes(providerHTMLNodes(document, func(node *html.Node) bool { return node.Data == "video" }), pageURL),
		Category:      category,
		Tags:          tags,
		Score:         score,
		Views:         views,
		EpisodeCount:  json.Number(strconv.Itoa(episodes)),
		ChannelName:   duanjuSourceName(sourceChaoguo),
		ReleaseStatus: status,
	}
}

func (d *Downloader) fetchChaoguoDetail(ctx context.Context, sourceID string) (Drama, []Chapter, error) {
	slug := strings.ToLower(strings.TrimSpace(sourceID))
	if !chaoguoSlugPattern.MatchString(slug) {
		return Drama{}, nil, errors.New("剧集标识无效")
	}
	base := d.duanjuBaseURL(sourceChaoguo)
	if base == "" {
		return Drama{}, nil, errors.New("站源地址不可用")
	}
	pageURL := base + "/drama/" + url.PathEscape(slug)
	document, _, err := d.fetchProviderPage(ctx, pageURL, base+"/", duanjuUserAgent)
	if err != nil {
		return Drama{}, nil, err
	}
	drama := chaoguoDetailDrama(document, slug, pageURL)
	chapters := chaoguoChapters(document, slug, pageURL, base+"/")
	if len(chapters) == 0 {
		return drama, nil, errors.New("未解析到可播放分集")
	}
	sortDuanjuChapters(chapters)
	drama.EpisodeCount = json.Number(strconv.Itoa(len(chapters)))
	return drama, chapters, nil
}

func (d *Downloader) searchChaoguoPage(ctx context.Context, query string, page int) ([]Drama, bool, error) {
	keyword := strings.TrimSpace(query)
	if keyword == "" {
		return nil, false, errors.New("请输入搜索关键词")
	}
	if page < 1 {
		page = 1
	}
	base := d.duanjuBaseURL(sourceChaoguo)
	if base == "" {
		return nil, false, errors.New("站源地址不可用")
	}
	address := fmt.Sprintf("%s/explore?q=%s&page=%d", base, url.QueryEscape(keyword), page)
	document, _, err := d.fetchProviderPage(ctx, address, base+"/", duanjuUserAgent)
	if err != nil {
		return nil, false, err
	}
	items := chaoguoDramasFromDocument(document, base)
	if len(items) == 0 && page == 1 {
		return nil, false, errors.New("未搜索到相关剧集")
	}
	return items, len(items) >= chaoguoCatalogPageSize, nil
}

func chaoguoRankingItems(document *html.Node) []rankingItem {
	var items []rankingItem
	seen := map[string]bool{}
	for _, row := range providerHTMLNodes(document, func(node *html.Node) bool {
		return node.Data == "li" && providerHTMLClass(node, "rank-item")
	}) {
		slug := ""
		for _, anchor := range providerHTMLNodes(row, func(node *html.Node) bool {
			return node.Data == "a" && providerHTMLClass(node, "rank-title")
		}) {
			slug = chaoguoSlugFromLink(providerHTMLAttr(anchor, "href"))
			break
		}
		if slug == "" {
			for _, anchor := range providerHTMLNodes(row, func(node *html.Node) bool {
				return node.Data == "a" && providerHTMLClass(node, "rank-cover")
			}) {
				slug = chaoguoSlugFromLink(providerHTMLAttr(anchor, "href"))
				break
			}
		}
		if slug == "" || seen[slug] {
			continue
		}
		seen[slug] = true
		title := ""
		if node := providerHTMLFirstClass(row, "rank-title"); node != nil {
			title = providerHTMLText(node)
		}
		if title == "" {
			title = chaoguoCardTitle(row)
		}
		if title == "" {
			continue
		}
		episodes := chaoguoEpisodeCount(row)
		score := ""
		if node := providerHTMLFirstClass(row, "rank-meta"); node != nil {
			parts := strings.Split(providerHTMLText(node), "·")
			last := strings.TrimSpace(parts[len(parts)-1])
			if len(parts) > 1 {
				if matches := chaoguoScorePattern.FindStringSubmatch(last); len(matches) > 1 {
					score = matches[1]
				}
			}
		}
		metric := ""
		if node := providerHTMLFirstClass(row, "rank-plays"); node != nil {
			metric = providerHTMLText(node)
		}
		items = append(items, rankingItem{
			Rank: len(items) + 1,
			Drama: rankingDramaWithoutImages(Drama{
				ID:           providerDramaID(sourceChaoguo, slug),
				Source:       sourceChaoguo,
				SourceID:     slug,
				Title:        title,
				EpisodeCount: json.Number(strconv.Itoa(episodes)),
				Score:        score,
				Views:        metric,
				Heat:         metric,
				ChannelName:  duanjuSourceName(sourceChaoguo),
			}),
			Metric: metric,
		})
	}
	return items
}

func (d *Downloader) fetchChaoguoRankingPage(ctx context.Context, board rankingBoard, page int) (rankingPage, error) {
	if page != 1 {
		return rankingPage{}, errors.New("该榜单只有一页")
	}
	base := d.duanjuBaseURL(sourceChaoguo)
	if base == "" {
		return rankingPage{}, errors.New("站源地址不可用")
	}
	document, _, err := d.fetchProviderPage(ctx, base+"/rank", base+"/", duanjuUserAgent)
	if err != nil {
		return rankingPage{}, err
	}
	items := chaoguoRankingItems(document)
	if len(items) == 0 {
		return rankingPage{}, errors.New("超果未返回榜单数据")
	}
	return rankingPage{Items: items, Page: page, HasMore: false}, nil
}
