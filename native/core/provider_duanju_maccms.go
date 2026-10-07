package core

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"

	"golang.org/x/net/html"
)

var (
	maccmsPlayerData     = regexp.MustCompile(`(?s)player_aaaa\s*=\s*(\{.*?\})\s*</script>`)
	maccmsPlayerURLField = regexp.MustCompile(`(?i)"url"\s*:\s*"([^"]+)"`)
)

type maccmsSourceProfile struct {
	Source      string
	CategoryURL func(base, category string) string
	SearchURL   func(base, query string, page int) string
	PageURL     func(base, category string, page int) string
	Episodes    func(document *html.Node) []providerEpisode
}

var maccmsEpisodeLink = regexp.MustCompile(`(?i)/(?:vod/)?play/|/vodplay/|/drama-play|episode_id=`)

var maccmsDetailLink = regexp.MustCompile(`(?i)/(?:index\.php/vod/)?(?:voddetail|detail|vod|show|view|movie|drama|zywview|xzyxvd)/`)

// 分类、搜索、榜单等路由也含有 /vod/ 或 /show/，不能当成详情链接。
var maccmsCategoryLink = regexp.MustCompile(`(?i)/(?:[a-z]*type|search|vodshow|label|gbook|rss|map|topic|actor)/`)

func maccmsEpisodeNodes(document *html.Node, source string) []*html.Node {
	var nodes []*html.Node
	collect := func(match func(*html.Node) bool) {
		for _, list := range providerHTMLNodes(document, match) {
			nodes = append(nodes, providerHTMLNodes(list, func(node *html.Node) bool { return node.Data == "a" })...)
		}
	}
	for _, name := range []string{"content__playlist", "playlink", "pcDrama_catalogItem", "catalogItem", "playlist"} {
		collect(maccmsClassMatcher(name))
	}
	if len(nodes) == 0 {
		for _, name := range []string{"tab-pane", "playlist", "playList"} {
			collect(maccmsClassMatcher(name))
		}
	}
	if len(nodes) == 0 {
		nodes = providerHTMLNodes(document, func(node *html.Node) bool {
			return node.Data == "a" && maccmsEpisodeLink.MatchString(providerHTMLAttr(node, "href"))
		})
	}
	return nodes
}

// maccmsEpisodesOfSource 只留下链接指向指定剧号的分集；requirePlay 为真时
// 还要求链接本身是播放链接，用来剔除同一部剧的「详情」入口。
func maccmsEpisodesOfSource(episodes []providerEpisode, sourceID string, requirePlay bool) []providerEpisode {
	var matched []providerEpisode
	for _, episode := range episodes {
		if maccmsSourceIDFromURL(episode.URL) != sourceID {
			continue
		}
		if requirePlay && !maccmsEpisodeLink.MatchString(episode.URL) {
			continue
		}
		matched = append(matched, episode)
	}
	return matched
}

func maccmsEpisodesFromDocument(document *html.Node) []providerEpisode {
	return maccmsEpisodesFromSource(document, "")
}

func maccmsEpisodesFromSource(document *html.Node, source string) []providerEpisode {
	var episodes []providerEpisode
	seen := map[string]bool{}
	for index, anchor := range maccmsEpisodeNodes(document, source) {
		link := strings.TrimSpace(providerHTMLAttr(anchor, "href"))
		title := providerHTMLText(anchor)
		if link == "" {
			continue
		}
		if strings.Contains(title, "APP") || strings.Contains(title, "下载") {
			continue
		}
		key := link
		if seen[key] {
			continue
		}
		seen[key] = true
		episodes = append(episodes, providerEpisode{
			Key:   strconv.Itoa(index + 1),
			Title: title,
			URL:   link,
			Index: index + 1,
		})
	}
	return episodes
}

func maccmsCardCover(card *html.Node, pageURL string) string {
	for _, image := range providerHTMLNodes(card, func(node *html.Node) bool { return node.Data == "img" }) {
		for _, attribute := range []string{"data-original", "data-src", "src"} {
			if address := providerCoverAddress(providerHTMLAttr(image, attribute), pageURL); address != "" {
				return address
			}
		}
	}
	for _, anchor := range providerHTMLNodes(card, func(node *html.Node) bool { return node.Data == "a" }) {
		for _, attribute := range []string{"data-original", "data-src"} {
			if address := providerCoverAddress(providerHTMLAttr(anchor, attribute), pageURL); address != "" {
				return address
			}
		}
	}
	return ""
}

// 搜索页会在 title/alt 属性里插入高亮标签（例如 alt="仁心<em>俱</em>乐部"），
// 属性值原样取出会把标签带进剧名。
var maccmsAttributeTag = regexp.MustCompile(`<[^>]*>`)

func maccmsCleanAttribute(value string) string {
	cleaned := maccmsAttributeTag.ReplaceAllString(value, "")
	cleaned = html.UnescapeString(cleaned)
	return strings.Join(strings.Fields(cleaned), " ")
}

func maccmsCardTitle(card *html.Node) string {
	for _, attribute := range []string{"title", "alt"} {
		for _, node := range providerHTMLNodes(card, func(node *html.Node) bool {
			return node.Data == "a" || node.Data == "img"
		}) {
			if text := maccmsCleanAttribute(providerHTMLAttr(node, attribute)); text != "" {
				return text
			}
		}
	}
	for _, node := range providerHTMLNodes(card, func(node *html.Node) bool { return node.Data == "a" }) {
		if text := providerHTMLText(node); text != "" {
			return text
		}
	}
	return ""
}

func maccmsCardLink(card *html.Node, base string) string {
	for _, anchor := range providerHTMLNodes(card, func(node *html.Node) bool { return node.Data == "a" }) {
		link := providerHTMLAttr(anchor, "href")
		if link == "" || strings.Contains(link, "javascript:") {
			continue
		}
		// 分类与搜索等导航链接不是详情链接；有些模板把分类标签放进与卡片
		// 完全相同的容器里，漏掉这一步会把它当成剧集。
		if maccmsCategoryLink.MatchString(link) {
			continue
		}
		if address := duanjuAbsolute(base, link); address != "" {
			return address
		}
	}
	return ""
}

func maccmsCardRemark(card *html.Node) string {
	for _, name := range []string{"meta-post-type2", "imagelabel", "module-item-note", "pic-text", "lastChapter", "SecondList_totalChapterNum", "SecondList_bookType"} {
		if node := providerHTMLFirstClass(card, name); node != nil {
			if text := providerHTMLText(node); text != "" {
				return text
			}
		}
	}
	return ""
}

func maccmsCards(document *html.Node, source, base string) []Drama {
	var cards []*html.Node
	seen := map[*html.Node]bool{}
	for _, name := range maccmsCardClasses {
		for _, node := range providerHTMLNodes(document, maccmsClassMatcher(name)) {
			if !seen[node] {
				seen[node] = true
				cards = append(cards, node)
			}
		}
	}
	if len(cards) == 0 {
		cards = maccmsAnchorCards(document)
	}
	var items []Drama
	ids := map[string]bool{}
	for _, card := range cards {
		link := maccmsCardLink(card, base)
		title := maccmsCardTitle(card)
		if link == "" || title == "" {
			continue
		}
		sourceID := maccmsSourceIDFromURL(link)
		if sourceID == "" || ids[sourceID] {
			continue
		}
		ids[sourceID] = true
		remark := maccmsCardRemark(card)
		items = append(items, Drama{
			ID:           providerDramaID(source, sourceID),
			Source:       source,
			SourceID:     sourceID,
			Title:        title,
			Cover:        maccmsCardCover(card, link),
			Remark:       remark,
			EpisodeCount: json.Number(strconv.Itoa(duanjuEpisodeNumber(remark, 0))),
			ChannelName:  duanjuSourceName(source),
		})
	}
	return items
}

func maccmsClassMatcher(name string) func(*html.Node) bool {
	return func(node *html.Node) bool {
		for _, value := range strings.Fields(providerHTMLAttr(node, "class")) {
			if value == name || strings.HasSuffix(value, "-"+name) {
				return true
			}
		}
		return false
	}
}

func maccmsAnchorCards(document *html.Node) []*html.Node {
	var cards []*html.Node
	seen := map[*html.Node]bool{}
	for _, anchor := range providerHTMLNodes(document, func(node *html.Node) bool {
		link := providerHTMLAttr(node, "href")
		return node.Data == "a" &&
			maccmsDetailLink.MatchString(link) &&
			!maccmsCategoryLink.MatchString(link)
	}) {
		for parent := anchor.Parent; parent != nil && parent.Type == html.ElementNode; parent = parent.Parent {
			if seen[parent] {
				break
			}
			if parent.Data != "li" && parent.Data != "div" {
				continue
			}
			seen[parent] = true
			cards = append(cards, parent)
		}
	}
	return cards
}

var maccmsCardClasses = []string{
	"col-lg-2", "col-xl-2", "module-item", "module-poster-item", "public-list-box",
	"videoBox", "detail-list-item", "col-md-6", "col-6", "listItem", "FeaturedList_featuredItem",
	"BrowseList_listItem", "SecondList_secondListItem", "vodlist__item", "v_list",
	"entry-wrapper", "TagBookList_tagItem", "video-item", "vodlist_item",
	"myui-vodlist__box", "thumbnail",
}

// 除常规详情路径外，还包含 /id/{id}/ 与 /vodplay/{id}-{线路}-{集}/ 两种形态。
// 少了它们会把 /play/id/123/sid/1/nid/1/ 里的 nid 当成剧集编号。
var maccmsDetailPath = regexp.MustCompile(`(?i)/(?:voddetail|vodplay|detail|show|vod|drama|movie|tv|id)/([0-9]+)(?:[-./]|$)`)

func maccmsSourceIDFromURL(link string) string {
	parsed, err := url.Parse(link)
	if err != nil {
		return ""
	}
	path := strings.TrimSuffix(parsed.Path, ".html")
	if matches := maccmsDetailPath.FindStringSubmatch(path + "/"); len(matches) > 1 {
		return matches[1]
	}
	cleaned := strings.Trim(path, "/")
	parts := strings.Split(cleaned, "/")
	for index := len(parts) - 1; index >= 0; index-- {
		candidate := strings.TrimSuffix(parts[index], ".html")
		if webProviderNumericID.MatchString(candidate) {
			return candidate
		}
		if _, tail, found := strings.Cut(candidate, "-"); found && webProviderNumericID.MatchString(tail) {
			return tail
		}
	}
	if id := parsed.Query().Get("id"); webProviderNumericID.MatchString(id) {
		return id
	}
	return ""
}

func (d *Downloader) fetchMaccmsCatalogPage(ctx context.Context, source string, page int, category string) ([]Drama, bool, error) {
	base := d.duanjuBaseURL(source)
	address := ""
	switch source {
	case sourceHuaguo:
		if page <= 1 && strings.TrimSpace(category) == "" {
			address = base + "/"
		} else {
			class := strings.TrimSpace(category)
			if class == "" {
				class = "27"
			}
			address = fmt.Sprintf("%s/search.html?page=%d&searchtype=5&tid=%s&year=", base, page, url.QueryEscape(class))
		}
	case sourceWuguo:
		class := strings.TrimSpace(category)
		if class == "" {
			class = duanjuStaticCategories[sourceWuguo][0].ID
		}
		address = fmt.Sprintf("%s/index.php/vod/search/class/%s/page/%d.html", base, url.PathEscape(class), page)
	case sourceMiguo:
		// 该站点分类页不分页：实测第 2、3 页与第 1 页返回同一批条目。
		class := strings.TrimSpace(category)
		if class == "" {
			class = duanjuStaticCategories[sourceMiguo][0].ID
		}
		if class == "netflix" {
			address = base + "/label/netflix.html"
		} else {
			address = fmt.Sprintf("%s/vodtype/%s.html", base, url.PathEscape(class))
		}
	case sourceShuangguo:
		// 分类地址形如 /show/26---题材--------.html；翻页把末尾的 ---.html
		// 换成 {页码}---.html，实测第 1、2 页各 24 条且不重复。
		class := strings.TrimSpace(category)
		path := "/show/26-----------.html"
		if class != "" && class != "all" {
			path = fmt.Sprintf("/show/26---%s--------.html", url.PathEscape(class))
		}
		if page > 1 {
			path = fmt.Sprintf("%s%d---.html", strings.TrimSuffix(path, "---.html"), page)
		}
		address = base + path
	default:
		return nil, false, errors.New("该站源没有网页目录")
	}
	document, finalURL, err := d.fetchProviderPage(ctx, address, base+"/", duanjuUserAgent)
	if err != nil {
		return nil, false, err
	}
	items := maccmsCards(document, source, base)
	_ = finalURL
	if source == sourceMiguo {
		// 分类页不分页，再请求后续页只会拿到同一批条目。
		return items, false, nil
	}
	return items, len(items) > 0, nil
}

func (d *Downloader) fetchMaccmsDetail(ctx context.Context, source, sourceID string) (Drama, []Chapter, error) {
	base := d.duanjuBaseURL(source)
	candidates := maccmsDetailCandidates(source, base, sourceID)
	var lastErr error
	for _, address := range candidates {
		document, finalURL, err := d.fetchProviderPage(ctx, address, base+"/", duanjuUserAgent)
		if err != nil {
			lastErr = err
			continue
		}
		drama := Drama{
			ID:          providerDramaID(source, sourceID),
			Source:      source,
			SourceID:    sourceID,
			Title:       maccmsDetailTitleFor(document, source),
			Intro:       maccmsDetailIntro(document),
			Cover:       maccmsDetailCover(document, finalURL),
			Category:    maccmsDetailCategory(document),
			ChannelName: duanjuSourceName(source),
		}
		if duanjuSourceIsSingle(source) {
			if drama.Title == "" {
				lastErr = errors.New("未解析到标题")
				continue
			}
			// 单片站的播放页里也会列出其它片子，直接当分集会张冠李戴，
			// 因此固定为一集并把播放页作为取流入口。
			chapters := []Chapter{duanjuChapter(source, sourceID, 1, drama.Title, address, address, base+"/")}
			drama.EpisodeCount = json.Number("1")
			return drama, chapters, nil
		}
		episodes := maccmsEpisodesFromSource(document, source)
		if len(episodes) == 0 {
			lastErr = errors.New("未解析到分集列表")
			continue
		}
		// 相关推荐与猜你喜欢同样以播放或详情链接出现在详情页里，直接把整页
		// 锚点当分集会张冠李戴（别的剧混进分集列表），因此按两级筛选收窄：
		// 先要「属于本剧且是播放链接」，其次「属于本剧」，都为空才保留原样，
		// 以免破坏分集链接不含剧号的站源。
		if playable := maccmsEpisodesOfSource(episodes, sourceID, true); len(playable) > 0 {
			episodes = playable
		} else if owned := maccmsEpisodesOfSource(episodes, sourceID, false); len(owned) > 0 {
			episodes = owned
		}
		var chapters []Chapter
		// 详情页会把该剧的每条播放线路都列一遍，同一集因此重复出现；不去重
		// 的话八条线路就把选集撑成八倍，界面上每个集号连着排八次。
		seen := map[int]bool{}
		for index, episode := range episodes {
			number := duanjuEpisodeNumber(firstNonEmpty(episode.Title, episode.Key), index+1)
			if number > 0 && seen[number] {
				continue
			}
			link := duanjuAbsolute(base, episode.URL)
			if link == "" {
				continue
			}
			if number > 0 {
				seen[number] = true
			}
			chapters = append(chapters, duanjuChapter(source, sourceID, number, episode.Title, link, link, base+"/"))
		}
		if len(chapters) == 0 {
			lastErr = errors.New("未解析到可播放分集")
			continue
		}
		sortDuanjuChapters(chapters)
		drama.EpisodeCount = json.Number(strconv.Itoa(len(chapters)))
		return drama, chapters, nil
	}
	if lastErr == nil {
		lastErr = errors.New("未找到该剧的详情页")
	}
	return Drama{}, nil, lastErr
}

func maccmsDetailCandidates(source, base, sourceID string) []string {
	switch source {
	case sourceWuguo:
		return []string{
			fmt.Sprintf("%s/index.php/vod/detail/id/%s.html", base, sourceID),
			fmt.Sprintf("%s/dramaDetail/%s.html", base, sourceID),
			fmt.Sprintf("%s/detail/%s.html", base, sourceID),
		}
	case sourceMiguo:
		return []string{
			fmt.Sprintf("%s/voddetail/%s.html", base, sourceID),
			fmt.Sprintf("%s/detail/%s.html", base, sourceID),
		}
	case sourceShuangguo:
		return []string{
			fmt.Sprintf("%s/vod/%s.html", base, sourceID),
			fmt.Sprintf("%s/detail/%s.html", base, sourceID),
		}
	case sourceHuaguo:
		return []string{
			fmt.Sprintf("%s/zywview/%s.html", base, sourceID),
			fmt.Sprintf("%s/zywdetail/%s.html", base, sourceID),
			fmt.Sprintf("%s/detail/%s.html", base, sourceID),
		}
	default:
		return nil
	}
}

func maccmsDetailTitle(document *html.Node) string {
	return maccmsDetailTitleFor(document, "")
}

func maccmsDetailTitleFor(document *html.Node, source string) string {
	for _, name := range []string{"module-info-heading", "detail-title", "video-info-title", "page-title"} {
		if node := providerHTMLFirstClass(document, name); node != nil {
			if text := providerHTMLText(node); text != "" {
				return maccmsCleanTitle(text)
			}
		}
	}
	// 部分模板把集数、站名直接拼进 <title>，而正文标题元素是干净的。
	// 正文里也存在「猜你喜欢」这类栏目标题，必须跳过。
	for _, tag := range []string{"h1", "h2"} {
		for _, node := range providerHTMLNodes(document, func(node *html.Node) bool { return node.Data == tag }) {
			text := maccmsCleanTitle(providerHTMLText(node))
			if text == "" || maccmsIsSectionHeading(text) {
				continue
			}
			return text
		}
	}
	if node := providerHTMLNodes(document, func(node *html.Node) bool { return node.Data == "title" }); len(node) > 0 {
		return maccmsCleanTitle(maccmsCleanAttribute(providerHTMLText(node[0])))
	}
	return ""
}

// 这些串一旦出现在标题中段，其后都是 SEO 拼接内容。
var maccmsTitleCutMarkers = []string{"详情介绍", "剧情介绍", "剧情简介", "在线播放", "在线观看", "免费观看"}

// 「剧名 2026 中国大陆 女频 / 甜宠 / ...」这类串由站点拼装，年份起就是说明文字。
// 要求年份前有空白，避免误伤「2001太空漫游」这类真实剧名。
var maccmsTitleYearMarker = regexp.MustCompile(`\s+20\d{2}(?:\s|$)`)

var maccmsTitleSuffixes = []string{"剧情介绍", "剧情简介", "在线观看", "免费观看", "高清完整版", "完整版", "全集", "在线播放", "已完结", "完结", "高清", "免费"}

// 更新状态常以「更新至第N集」这类形式贴在标题尾部。
var maccmsTitleUpdateTail = regexp.MustCompile(`\s*更新至(?:第)?\d+(?:集|话|期)?\s*$`)

// 章节序号用阿拉伯数字，中文数字（第二季）属于真实剧名，不能裁。
var maccmsTitlePartTail = regexp.MustCompile(`\s*第\s*\d+\s*[集话期部]\s*$`)

// 画质标记以空格分隔贴在标题尾部，要求有分隔空白才不会切坏剧名本身。
var maccmsTitleQualityTail = regexp.MustCompile(`\s+(?:HD|HDR|4K|1080P|720P|蓝光|超清|高清|HD中字|中字|国语|粤语|日语)\s*$`)

func maccmsCleanTitle(raw string) string {
	text := strings.TrimSpace(raw)
	if text == "" {
		return ""
	}
	for _, marker := range maccmsTitleCutMarkers {
		at := strings.Index(text, marker)
		if at < 0 {
			continue
		}
		if at == 0 {
			text = strings.TrimSpace(text[len(marker):])
		} else {
			text = strings.TrimSpace(text[:at])
		}
		break
	}
	// 站点常在标题末尾追加「--站点名」。单连字符会用于「第二季」这类
	// 真实后缀，双连字符也可能出现在剧名的季数连接处，因此只在尾部不像
	// 季数/篇章标记时才裁掉。
	if at := strings.LastIndex(text, "--"); at > 0 {
		if tail := strings.TrimSpace(text[at+2:]); maccmsTitleTailIsSiteName(tail) {
			text = strings.TrimSpace(text[:at])
		}
	}
	if cut, _, found := strings.Cut(text, " - "); found {
		text = strings.TrimSpace(cut)
	}
	if cut, _, found := strings.Cut(text, " _ "); found {
		text = strings.TrimSpace(cut)
	}
	for _, separator := range []string{"-", "_", "|"} {
		for {
			cut, _, found := strings.Cut(text, separator)
			if !found {
				break
			}
			head := strings.TrimSpace(cut)
			if !maccmsTitleTailIsSeo(text[len(cut)+len(separator):]) {
				break
			}
			text = head
		}
	}
	if at := maccmsTitleYearMarker.FindStringIndex(text); at != nil && at[0] > 0 {
		text = strings.TrimSpace(text[:at[0]])
	}
	for changed := true; changed; {
		changed = false
		for _, tail := range []*regexp.Regexp{maccmsTitleUpdateTail, maccmsTitlePartTail, maccmsTitleQualityTail} {
			if trimmed := tail.ReplaceAllString(text, ""); trimmed != text && trimmed != "" {
				text = strings.TrimSpace(trimmed)
				changed = true
			}
		}
		for _, suffix := range maccmsTitleSuffixes {
			if strings.HasSuffix(text, suffix) && len(text) > len(suffix) {
				text = strings.TrimSpace(strings.TrimSuffix(text, suffix))
				changed = true
			}
		}
	}
	text = strings.Trim(text, "-_|·— ")
	if text == "" {
		return strings.TrimSpace(raw)
	}
	return text
}

var maccmsSectionHeadings = []string{
	"猜你喜欢", "猜你想看", "相关推荐", "播放列表", "热门推荐",
	"最新推荐", "热门视频", "为你推荐", "网友评论", "影片评论",
	"在线播放", "立即播放", "在线观看", "播放", "下载",
	"猜你喜歡", "猜你想看", "相關推薦", "播放列表", "熱門推薦",
	"最新推薦", "熱門視頻", "為你推薦", "網友評論", "影片評論",
	"在線播放", "立即播放", "在線觀看", "下集",
}

func maccmsIsSectionHeading(text string) bool {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return true
	}
	// 「同分類熱門推薦」「名字類似影片」这类栏目名随模板变化，按结尾判定更稳。
	for _, suffix := range []string{"推薦", "推荐", "類似影片", "类似影片", "相關影片", "相关影片"} {
		if strings.HasSuffix(trimmed, suffix) {
			return true
		}
	}
	for _, heading := range maccmsSectionHeadings {
		if trimmed == heading {
			return true
		}
	}
	return false
}

func maccmsTitleTailIsSiteName(tail string) bool {
	if tail == "" || utf8.RuneCountInString(tail) > 16 {
		return false
	}
	if strings.HasPrefix(tail, "第") {
		return false
	}
	for _, marker := range []string{"季", "部", "集", "篇", "卷", "话", "章"} {
		if strings.HasSuffix(tail, marker) {
			return false
		}
	}
	return true
}

func maccmsTitleTailIsSeo(tail string) bool {
	tail = strings.TrimSpace(tail)
	if tail == "" {
		return true
	}
	for _, marker := range []string{"短剧", "全集", "在线观看", "免费", "高清", "完整版", "视频", "剧场", "影院", "网"} {
		if strings.Contains(tail, marker) {
			return true
		}
	}
	return false
}

func maccmsDetailIntro(document *html.Node) string {
	for _, name := range []string{"module-info-introduction-content", "detail-content", "video-info-content", "introduction_introEllipsis"} {
		if node := providerHTMLFirstClass(document, name); node != nil {
			if text := providerHTMLText(node); text != "" {
				return truncate(text, 2000)
			}
		}
	}
	for _, meta := range providerHTMLNodes(document, func(node *html.Node) bool { return node.Data == "meta" }) {
		if strings.EqualFold(providerHTMLAttr(meta, "name"), "description") {
			if content := strings.TrimSpace(providerHTMLAttr(meta, "content")); content != "" {
				return truncate(content, 2000)
			}
		}
	}
	return ""
}

func maccmsDetailCover(document *html.Node, pageURL string) string {
	for _, name := range []string{"module-item-pic", "detail-pic", "video-info-pic", "pic"} {
		for _, node := range providerHTMLNodes(document, func(node *html.Node) bool { return providerHTMLClass(node, name) }) {
			if address := maccmsCardCover(node, pageURL); address != "" {
				return address
			}
		}
	}
	for _, image := range providerHTMLNodes(document, func(node *html.Node) bool { return node.Data == "img" }) {
		for _, attribute := range []string{"data-original", "data-src", "src"} {
			if address := providerCoverAddress(providerHTMLAttr(image, attribute), pageURL); address != "" {
				return address
			}
		}
	}
	return ""
}

func maccmsDetailCategory(document *html.Node) string {
	for _, name := range []string{"module-info-tag-link", "detail-tag", "video-info-actor"} {
		nodes := providerHTMLNodes(document, func(node *html.Node) bool { return providerHTMLClass(node, name) })
		if len(nodes) > 0 {
			var parts []string
			for _, anchor := range providerHTMLNodes(nodes[0], func(node *html.Node) bool { return node.Data == "a" }) {
				if text := providerHTMLText(anchor); text != "" {
					parts = append(parts, text)
				}
			}
			if len(parts) > 0 {
				return duanjuCSV(parts)
			}
		}
	}
	return ""
}

// 部分 Maccms 站的 HTML 搜索页在服务端报错，但框架自带的 suggest
// JSON 接口仍然正常，因此为这类站点保留一条独立搜索通道。
const maccmsSuggestLimit = 30

type maccmsSuggestItem struct {
	ID   json.RawMessage `json:"id"`
	Name string          `json:"name"`
	Pic  string          `json:"pic"`
}

func (d *Downloader) searchMaccmsSuggest(ctx context.Context, source, query string) ([]Drama, error) {
	base := d.duanjuBaseURL(source)
	address := fmt.Sprintf("%s/index.php/ajax/suggest?mid=1&wd=%s&limit=%d",
		base, url.QueryEscape(query), maccmsSuggestLimit)
	body, err := d.duanjuDo(ctx, duanjuRequest{
		Source:  source,
		Method:  http.MethodGet,
		Address: address,
		Referer: base + "/",
		Agent:   duanjuUserAgent,
		Headers: map[string]string{"X-Requested-With": "XMLHttpRequest"},
	})
	if err != nil {
		return nil, err
	}
	var payload struct {
		List []maccmsSuggestItem `json:"list"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	var items []Drama
	seen := map[string]bool{}
	for _, entry := range payload.List {
		sourceID := strings.Trim(strings.TrimSpace(string(entry.ID)), `"`)
		title := strings.TrimSpace(entry.Name)
		if sourceID == "" || title == "" || seen[sourceID] {
			continue
		}
		seen[sourceID] = true
		items = append(items, Drama{
			ID:           providerDramaID(source, sourceID),
			Source:       source,
			SourceID:     sourceID,
			Title:        truncate(title, 256),
			Cover:        providerCoverAddress(entry.Pic, base+"/"),
			EpisodeCount: json.Number("1"),
			ChannelName:  duanjuSourceName(source),
		})
	}
	if len(items) == 0 {
		return nil, errors.New("该站源没有搜索到结果")
	}
	return items, nil
}

func (d *Downloader) searchMaccms(ctx context.Context, source, query string) ([]Drama, error) {
	if spec, found := duanjuSourceSpecFor(source); found && spec.Suggest {
		return d.searchMaccmsSuggest(ctx, source, query)
	}
	base := d.duanjuBaseURL(source)
	var address string
	switch source {
	case sourceHuaguo:
		address = fmt.Sprintf("%s/search.html?searchword=%s", base, url.QueryEscape(query))
	case sourceWuguo:
		address = fmt.Sprintf("%s/index.php/vod/search/page/1/wd/%s.html", base, url.PathEscape(query))
	case sourceMiguo:
		address = fmt.Sprintf("%s/vodsearch/%s-------------.html", base, url.PathEscape(query))
	case sourceShuangguo:
		address = fmt.Sprintf("%s/search/%s----------1---.html", base, url.PathEscape(query))
	default:
		return nil, errors.New("该站源不支持在线搜索")
	}
	document, _, err := d.fetchProviderPage(ctx, address, base+"/", duanjuUserAgent)
	if err != nil {
		return nil, err
	}
	return maccmsCards(document, source, base), nil
}

func maccmsPlayerURL(body string) string {
	if matches := maccmsPlayerData.FindStringSubmatch(body); len(matches) > 1 {
		if inner := maccmsPlayerURLField.FindStringSubmatch(matches[1]); len(inner) > 1 {
			return strings.ReplaceAll(inner[1], `\/`, `/`)
		}
	}
	for _, pattern := range []*regexp.Regexp{
		regexp.MustCompile(`(?i)\$\.url\s*=\s*"([^"]+)"`),
		// 部分站点的播放页把正片地址写成 const source = '...'，同一页面还会
		// 混入播放器自带的示例片地址（例如 artplayer 的 sample/test1.mp4），
		// 必须比通用兜底正则先匹配，否则会取到示例片而不是正片。
		regexp.MustCompile(`(?i)const\s+source\s*=\s*'([^']+)'`),
		regexp.MustCompile(`(?i)"url"\s*:\s*"([^"]+\.(?:m3u8|mp4)[^"]*)"`),
		regexp.MustCompile(`(?i)(https?://[^\s"'<>]+\.(?:m3u8|mp4)[^\s"'<>]*)`),
	} {
		for _, matches := range pattern.FindAllStringSubmatch(body, -1) {
			if len(matches) <= 1 {
				continue
			}
			candidate := strings.ReplaceAll(matches[1], `\/`, `/`)
			if maccmsIsPlaceholderAddress(candidate) {
				continue
			}
			return candidate
		}
	}
	return ""
}

// 站点会把未替换的模板串当地址输出（例如下载按钮写成
// https://mp4.#.mp4），这类串看着像媒体地址但不可播，必须剔除。
func maccmsIsPlaceholderAddress(address string) bool {
	trimmed := strings.TrimSpace(address)
	if !isProviderHTTPMediaURL(trimmed) {
		return true
	}
	if strings.ContainsAny(trimmed, "#{}") {
		return true
	}
	parsed, err := url.Parse(trimmed)
	if err != nil || parsed.Host == "" {
		return true
	}
	host := parsed.Hostname()
	if !strings.Contains(host, ".") {
		return true
	}
	parts := strings.Split(host, ".")
	return len(parts[len(parts)-1]) < 2
}

func maccmsNormalizePlaybackURL(raw string) string {
	raw = strings.TrimSpace(strings.ReplaceAll(raw, `\/`, `/`))
	raw = strings.Trim(raw, ",\\。，;；")
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if strings.Contains(raw, "p.") || strings.Contains(raw, "c1.") {
		parts := strings.Split(raw, "/")
		if len(parts) >= 3 {
			base := strings.Join(parts[:len(parts)-2], "/")
			folder := parts[len(parts)-2]
			if decoded := maccmsDecodeUnicode(folder); decoded != folder {
				return base + "/" + url.PathEscape(decoded) + "/index.m3u8"
			}
		}
	}
	return raw
}

var maccmsUnicodeEscape = regexp.MustCompile(`\\?u([0-9a-fA-F]{4})`)

func maccmsDecodeUnicode(value string) string {
	return maccmsUnicodeEscape.ReplaceAllStringFunc(value, func(match string) string {
		hex := match[len(match)-4:]
		if number, err := strconv.ParseInt(hex, 16, 32); err == nil {
			return string(rune(number))
		}
		return match
	})
}
