package core

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"testing"

	"golang.org/x/net/html"
)

const chaoguoCatalogFixture = `<html><body><main><div class="page">
<p class="result-line">共 <b>1268</b> 部</p>
<div class="grid">
<a class="card" href="/drama/ttarwbe2" title="长生录"><div class="card-poster"><img src="https://cover.example.cn/LPkLeOPdryZaUHs/320.webp" alt="长生录" width="176" height="264"/><span class="card-eps">43 集</span></div><div class="card-title">长生录</div><p class="card-brief">九十六岁寿元将尽才觉醒系统。</p></a>
<a class="card" href="/drama/1jsvz9qz" title="妻夜怪谈"><div class="card-poster"><img src="https://cover.example.cn/9morNCb3qfOp3B7L/320.webp" alt="妻夜怪谈"/><span class="card-eps">5 集</span></div><div class="card-title">妻夜怪谈</div><p class="card-brief">色迷维修员误入阴森公寓。</p></a>
</div></div></main></body></html>`

const chaoguoDetailFixture = `<html><body><main><div class="watch">
<div class="watch-stage"><div class="player-frame portrait"><video id="player" data-drama-id="37" controls="" playsinline="" poster="https://cover.example.cn/LPkLeOPdryZaUHs/640.webp"></video></div></div>
<aside class="watch-side"><h1 class="watch-title">长生录</h1>
<div class="hero-meta"><span>⭐ 4.5</span><span>43 集</span><span>627.39万 播放</span><span>主流剧情</span><span class="tag-orig">原创</span></div>
<div class="chips"><a class="chip" href="/tag/%E4%BB%99%E4%BE%A0">仙侠</a><a class="chip" href="/tag/%E7%A9%BF%E8%B6%8A">穿越</a></div>
<h2 class="side-h2">剧情简介</h2><p class="watch-desc">在合欢宗苦修九十六载却始终是资质平庸的废柴。</p>
<div class="ep-head"><h2 class="side-h2">选集</h2><span class="muted">2/2 可播放</span></div>
<div class="ep-grid scroll"><button class="ep-btn" type="button" data-src="https://stream.example.cn/m/aaa/playlist.m3u8" data-seq="1" title="第1集 · 5:16">1</button><button class="ep-btn" type="button" data-src="https://stream.example.cn/m/bbb/playlist.m3u8" data-seq="2" title="2 · 3:08">2</button></div>
</aside></div></main></body></html>`

const chaoguoRankFixture = `<html><body><main><div class="page"><h1 class="page-title">🔥 热播榜</h1><ol class="rank-list">
<li class="rank-item"><span class="rank-no top">1</span><a class="rank-cover" href="/drama/m6rzo36m"><img src="https://cover.example.cn/RO8eMl3XHymV1Z/320.webp" alt="秘密教学"/></a><div class="rank-info"><a class="rank-title" href="/drama/m6rzo36m">秘密教学</a><p class="rank-meta">11 集</p></div><span class="rank-plays">4.99万</span></li>
<li class="rank-item"><span class="rank-no ">2</span><a class="rank-cover" href="/drama/cgt4x1pl"><img src="https://cover.example.cn/wvjV04lfPQoWAg/320.webp" alt="艳福风流传"/></a><div class="rank-info"><a class="rank-title" href="/drama/cgt4x1pl">艳福风流传</a><p class="rank-meta">8 集 · ⭐ 4.3</p></div><span class="rank-plays">4.46万</span></li>
</ol></div></main></body></html>`

func TestChaoguoCategoryValidation(t *testing.T) {
	valid := []string{"", "class:mainstream", "class:anime_ip", "tag:都市", "tag:高颜值", "都市"}
	for _, category := range valid {
		if !validChaoguoCategory(category) {
			t.Fatalf("chaoguo rejected a valid category %q", category)
		}
	}
	invalid := []string{"class:unknown-class", "class:", "tag:../etc", "tag:a b", "tag:都市/../", strings.Repeat("都市", 20)}
	for _, category := range invalid {
		if validChaoguoCategory(category) {
			t.Fatalf("chaoguo accepted an invalid category %q", category)
		}
	}
	if validChaoguoCategory("tag:都市") == false {
		t.Fatal("chaoguo tag categories must stay accepted")
	}
}

func TestChaoguoCatalogAddressKeepsItsCategory(t *testing.T) {
	base := "https://www.shanekids.com"
	cases := map[string]string{
		"":                 base + "/explore?sort=hot&page=1",
		"class:mainstream": base + "/explore?class=mainstream&sort=hot&page=2",
		"tag:都市":           base + "/tag/" + url.PathEscape("都市") + "?page=3",
	}
	for category, want := range cases {
		page := 1
		if category != "" {
			page = 2
		}
		if category == "tag:都市" {
			page = 3
		}
		if got := chaoguoCatalogAddress(base, category, page); got != want {
			t.Fatalf("category %q => %q, want %q", category, got, want)
		}
	}
}

func TestChaoguoParsesCatalogDetailSearchAndRanking(t *testing.T) {
	requested := map[string]string{}
	d, server := duanjuFixtureDownloader(t, func(writer http.ResponseWriter, request *http.Request) {
		requested[request.URL.Path] = request.URL.RequestURI()
		if request.Header.Get("Referer") == "" {
			t.Errorf("chaoguo request %s did not send a referer", request.URL.Path)
		}
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
		switch {
		case strings.HasPrefix(request.URL.Path, "/drama/"):
			_, _ = writer.Write([]byte(chaoguoDetailFixture))
		case request.URL.Path == "/rank":
			_, _ = writer.Write([]byte(chaoguoRankFixture))
		case request.URL.Query().Get("q") == "空搜索":
			_, _ = writer.Write([]byte(`<html><body><main><div class="page"><p class="result-line">共 <b>0</b> 部</p><div class="grid"></div></div></main></body></html>`))
		default:
			_, _ = writer.Write([]byte(chaoguoCatalogFixture))
		}
	})
	d.providerHosts[sourceChaoguo] = server.URL

	items, more, err := d.fetchChaoguoCatalogPage(context.Background(), 1, "class:mainstream")
	if err != nil || len(items) != 2 || more {
		t.Fatalf("chaoguo catalog failed: %+v %v %v", items, more, err)
	}
	if items[0].ID != "chaoguo:ttarwbe2" || items[0].Source != sourceChaoguo || items[0].EpisodeCount != json.Number("43") {
		t.Fatalf("chaoguo catalog card parsed incorrectly: %+v", items[0])
	}
	if items[0].Title != "长生录" || items[0].ChannelName != "超果" {
		t.Fatalf("chaoguo catalog card metadata is wrong: %+v", items[0])
	}
	if !strings.Contains(requested["/explore"], "class=mainstream") {
		t.Fatalf("chaoguo catalog did not request its category: %s", requested["/explore"])
	}

	drama, chapters, err := d.fetchChaoguoDetail(context.Background(), "ttarwbe2")
	if err != nil || len(chapters) != 2 {
		t.Fatalf("chaoguo detail failed: %+v %v", chapters, err)
	}
	if drama.Title != "长生录" || drama.Score != "4.5" || drama.Views != "627.39万 播放" || drama.Category != "主流剧情" {
		t.Fatalf("chaoguo detail metadata is wrong: %+v", drama)
	}
	if drama.ReleaseStatus != "finished" || drama.EpisodeCount != json.Number("2") {
		t.Fatalf("chaoguo detail status is wrong: %+v", drama)
	}
	if len(drama.Tags) != 2 || drama.Tags[0] != "仙侠" {
		t.Fatalf("chaoguo detail tags are wrong: %+v", drama.Tags)
	}
	if drama.Cover != "https://cover.example.cn/LPkLeOPdryZaUHs/640.webp" {
		t.Fatalf("chaoguo detail cover is wrong: %q", drama.Cover)
	}
	if chapters[0].VideoURL != "https://stream.example.cn/m/aaa/playlist.m3u8" || chapters[0].Referer != server.URL+"/" {
		t.Fatalf("chaoguo chapter media is wrong: %+v", chapters[0])
	}
	if chapters[1].Title != "第2集" {
		t.Fatalf("chaoguo chapter title is wrong: %+v", chapters[1])
	}
	if chapters[0].CurrentEpisode == nil || string(chapters[0].CurrentEpisode) != "1" {
		t.Fatalf("chaoguo chapter number is wrong: %+v", chapters[0])
	}

	results, more, err := d.searchChaoguoPage(context.Background(), "长生 & 录", 2)
	if err != nil || len(results) != 2 || more {
		t.Fatalf("chaoguo search failed: %+v %v %v", results, more, err)
	}
	if !strings.Contains(requested["/explore"], url.QueryEscape("长生 & 录")) || !strings.Contains(requested["/explore"], "page=2") {
		t.Fatalf("chaoguo search did not page its keyword: %s", requested["/explore"])
	}
	if _, _, err := d.searchChaoguoPage(context.Background(), "空搜索", 1); err == nil {
		t.Fatal("chaoguo must report an empty first search page")
	}
	if items, _, err := d.searchChaoguoPage(context.Background(), "空搜索", 2); err != nil || len(items) != 0 {
		t.Fatalf("chaoguo empty later search page must stay silent: %+v %v", items, err)
	}

	page, err := d.fetchRankingPage(context.Background(), rankingBoard{ID: "chaoguo-hot", Source: sourceChaoguo}, 1)
	if err != nil || len(page.Items) != 2 {
		t.Fatalf("chaoguo ranking failed: %+v %v", page.Items, err)
	}
	if page.Items[0].Drama.ID != "chaoguo:m6rzo36m" || page.Items[0].Rank != 1 || page.Items[0].Metric != "4.99万" {
		t.Fatalf("chaoguo ranking item is wrong: %+v", page.Items[0])
	}
	if page.Items[0].Drama.Cover != nil || page.Items[1].Drama.Score != "4.3" {
		t.Fatalf("chaoguo ranking item metadata is wrong: %+v", page.Items)
	}
	if _, err := d.fetchRankingPage(context.Background(), rankingBoard{ID: "chaoguo-hot", Source: sourceChaoguo}, 2); err == nil {
		t.Fatal("chaoguo hot ranking must stay single page")
	}
}

func TestChaoguoRankingBoardUsesTheSourceCatalog(t *testing.T) {
	requested := ""
	d, server := duanjuFixtureDownloader(t, func(writer http.ResponseWriter, request *http.Request) {
		requested = request.URL.RequestURI()
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = writer.Write([]byte(chaoguoCatalogFixture))
	})
	d.providerHosts[sourceChaoguo] = server.URL
	board, found := findRankingBoard("chaoguo-urban")
	if !found {
		t.Fatal("chaoguo-urban board is missing")
	}
	page, err := d.fetchRankingPage(context.Background(), board, 1)
	if err != nil || len(page.Items) != 2 {
		t.Fatalf("chaoguo catalog ranking failed: %+v %v", page.Items, err)
	}
	if !strings.Contains(requested, url.PathEscape("都市")) {
		t.Fatalf("chaoguo ranking did not request its tag: %s", requested)
	}
	for _, item := range page.Items {
		if item.Drama.Source != sourceChaoguo || item.Drama.Cover != nil {
			t.Fatalf("chaoguo ranking exposed a foreign item: %+v", item.Drama)
		}
	}
}

func TestChaoguoDetailCompletionFollowsThePlayableRatio(t *testing.T) {
	cases := []struct {
		ratio    string
		finished bool
	}{
		{"43/43 可播放", true},
		{"2/2 可播放", true},
		{"2/43 可播放", false},
		{"0/43 可播放", false},
	}
	for _, testCase := range cases {
		page := strings.Replace(chaoguoDetailFixture, "2/2 可播放", testCase.ratio, 1)
		document, err := html.Parse(strings.NewReader(page))
		if err != nil {
			t.Fatal(err)
		}
		drama := chaoguoDetailDrama(document, "ttarwbe2", "https://www.shanekids.com/drama/ttarwbe2")
		if finished := drama.ReleaseStatus == "finished"; finished != testCase.finished {
			t.Fatalf("playable ratio %q => finished=%t, want %t", testCase.ratio, finished, testCase.finished)
		}
	}
}

func TestChaoguoDetailSeparatesDeclaredAndPlayableEpisodes(t *testing.T) {
	document, err := html.Parse(strings.NewReader(chaoguoDetailFixture))
	if err != nil {
		t.Fatal(err)
	}
	episodes, score, views, category := chaoguoDetailMeta(document)
	if episodes != 43 || score != "4.5" || views != "627.39万 播放" || category != "主流剧情" {
		t.Fatalf("chaoguo detail meta is wrong: episodes=%d score=%q views=%q category=%q",
			episodes, score, views, category)
	}
	chapters := chaoguoChapters(document, "ttarwbe2", "https://www.shanekids.com/drama/ttarwbe2", "https://www.shanekids.com/")
	if len(chapters) != 2 {
		t.Fatalf("chaoguo detail should expose 2 playable chapters, got %d", len(chapters))
	}
}
