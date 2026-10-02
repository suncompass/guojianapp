package core

import (
	"context"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"testing"
)

func huangguoSearchFixture(title, id string) string {
	return `<div class="hg-search-suggest__guess"><div class="hg-drama-card" data-track-id="999" data-track-title="干扰推荐"><a href="/video/999/">干扰推荐</a></div></div>
<section class="hg-list-page hg-search-page"><div class="hg-search-results"><div class="hg-card-grid">
<div class="hg-drama-card" data-track-id="` + id + `" data-track-title="` + title + `" data-track-type-name="AI成人短剧">
<div class="hg-drama-card__cover"><a href="/video/` + id + `/"><img data-src="https://pic.example.test/` + id + `.jpg" alt="` + title + `"><span class="hg-drama-card__episode" data-ep-base="更新至5集">更新至5集</span></a></div>
<h3 class="hg-drama-card__title"><a href="/video/` + id + `/">` + title + `</a></h3>
</div></div></div></section><link rel="next" href="/search/video/sample/2/">`
}

func TestHuangguoDynamicRoutesAndSearchParsing(t *testing.T) {
	entryURL := huangguoAIBaseURL
	t.Cleanup(func() { huangguoAIBaseURL = entryURL })
	huangguoAIBaseURL = "https://huangguoai.ai"
	var requested []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		requested = append(requested, request.URL.String())
		switch request.URL.Host {
		case "huangguoai.ai":
			return sourceFixtureResponse(request, http.StatusOK, `<article data-url="https://line-a.kmexvuoz.cc"></article><a href="https://line-b.kmexvuoz.cc">备用</a><a href="https://huangguoai.com">旧域名</a>`), nil
		case "line-a.kmexvuoz.cc":
			if request.URL.EscapedPath() != "/search/video/AI%E6%9E%81%E5%93%81%E5%AE%B6%E4%B8%81/" {
				t.Fatalf("unexpected huangguo search path: %s", request.URL.String())
			}
			return sourceFixtureResponse(request, http.StatusOK, huangguoSearchFixture("AI极品家丁", "365")), nil
		default:
			t.Fatalf("unexpected host: %s", request.URL.Host)
		}
		return nil, nil
	})
	items, more, err := d.searchHuangguoAI(context.Background(), "AI极品家丁", 1)
	if err != nil || len(items) != 1 || !more {
		t.Fatalf("huangguo search failed: %+v more=%t err=%v requests=%v", items, more, err, requested)
	}
	if items[0].ID != "huangguoai:365" || items[0].DisplayTitle() != "AI极品家丁" || nativeText(items[0].EpisodeCount) != "5" {
		t.Fatalf("wrong search item: %+v", items[0])
	}
}

func TestHuangguoSearchRediscoversRouteAfterStaleRoute404(t *testing.T) {
	var requests []string
	d := sourceFixtureDownloader(t, func(request *http.Request) (*http.Response, error) {
		requests = append(requests, request.URL.Host+request.URL.Path)
		switch request.URL.Host {
		case "stale.kmexvuoz.cc":
			return sourceFixtureResponse(request, http.StatusNotFound, "missing"), nil
		case "huangguoai.ai":
			if request.URL.Path != "/" {
				t.Fatalf("unexpected navigation path: %s", request.URL.String())
			}
			return sourceFixtureResponse(request, http.StatusOK, `<a data-url="https://fresh.kmexvuoz.cc">当前线路</a>`), nil
		case "fresh.kmexvuoz.cc":
			if request.URL.Path != "/search/video/一个乖乖女/" {
				t.Fatalf("unexpected search path: %s", request.URL.String())
			}
			return sourceFixtureResponse(request, http.StatusOK, huangguoSearchFixture("一个乖乖女", "6139")), nil
		default:
			t.Fatalf("unexpected host: %s", request.URL.Host)
		}
		return nil, nil
	})
	d.huangguoAIRoutes = []string{"https://stale.kmexvuoz.cc"}
	d.huangguoAIRouteChecked = true
	d.providerHosts[sourceHuangguoAI] = "https://stale.kmexvuoz.cc"

	items, _, err := d.searchHuangguoAI(context.Background(), "一个乖乖女", 1)
	if err != nil || len(items) != 1 || items[0].ID != "huangguoai:6139" {
		t.Fatalf("stale route was not recovered: items=%+v err=%v requests=%v", items, err, requests)
	}
	if strings.Contains(strings.Join(requests, ","), "huangguoai.ai/search/video") {
		t.Fatalf("navigation page was used as content search: %v", requests)
	}
}

func TestHuangguoRouteRecognitionRejectsDeprecatedDomain(t *testing.T) {
	routes := parseHuangguoAIRoutes(`<a data-url="https://first.kmexvuoz.cc"></a><a href="https://second.hwqlgzvsk.cc"></a><a href="https://huangguoai.com"></a>`)
	if fmt.Sprint(routes) != "[https://first.kmexvuoz.cc https://second.hwqlgzvsk.cc]" {
		t.Fatalf("wrong dynamic routes: %v", routes)
	}
	for _, address := range []string{"https://first.kmexvuoz.cc", "https://second.hwqlgzvsk.cc/video/1/"} {
		if !huangguoAIIsContentRoute(address) || providerSourceForURL(address) != sourceHuangguoAI {
			t.Fatalf("current route was not accepted: %s", address)
		}
	}
	if huangguoAIIsContentRoute("https://huangguoai.com") || providerSourceForURL("https://huangguoai.com") == sourceHuangguoAI || strings.Contains(strings.Join(routes, ","), "huangguoai.com") {
		t.Fatal("deprecated huangguoai.com was accepted")
	}
	if detailIDFromString("https://first.kmexvuoz.cc/video/6139/ep-2/") != "6139" {
		t.Fatal("video detail id was not parsed")
	}
}

func TestHuangguoRouteRecognitionFollowsRotatedDomains(t *testing.T) {
	fixture := `<article class="route-card" data-url="https://ux90.rurhvbhx.cc"></article>
<article class="route-card" data-url="https://vtzi.rurhvbhx.cc"></article>
<article class="route-card" data-url="https://jukn.rurhvbhx.cc"></article>
<a href="https://huangguoai.com/compliance-2257/">合规声明</a>
<a href="https://t.me/huangguofans">频道</a>
<a href="https://www.googletagmanager.com/gtag/js">统计</a>
<img src="https://pic.wirqed.cn/cover.jpg">`
	routes := parseHuangguoAIRoutes(fixture)
	if fmt.Sprint(routes) != "[https://ux90.rurhvbhx.cc https://vtzi.rurhvbhx.cc https://jukn.rurhvbhx.cc]" {
		t.Fatalf("rotated routes were not discovered in order: %v", routes)
	}
	for _, address := range []string{"https://ux90.rurhvbhx.cc/video/6139/", "https://vtzi.rurhvbhx.cc/api/videos/category/ai-mogai"} {
		if !huangguoAIIsContentRoute(address) || providerSourceForURL(address) != sourceHuangguoAI {
			t.Fatalf("discovered rotated route was rejected: %s", address)
		}
	}
	for _, rejected := range []string{"https://huangguoai.ai", "https://huangguoai.ai/video/6139/", "https://huangguoai.com", "https://t.me/huangguofans", "https://www.googletagmanager.com/gtag/js", "https://pic.wirqed.cn/cover.jpg"} {
		if huangguoAIIsContentRoute(rejected) {
			t.Fatalf("non content host was accepted: %s", rejected)
		}
	}
}

func TestHuangguoRotatedDomainServesCategoryRequests(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.Host == "huangguoai.ai" {
			return sourceFixtureResponse(request, http.StatusOK, `<article class="route-card" data-url="https://ux90.rurhvbhx.cc"></article>`), nil
		}
		if request.URL.Host == "ux90.rurhvbhx.cc" {
			return sourceFixtureResponse(request, http.StatusOK, `{"data":{"list":[{"id":6139,"title":"合成短剧","totalEpisode":2}]}}`), nil
		}
		return sourceFixtureResponse(request, http.StatusBadGateway, "unexpected host "+request.URL.Host), nil
	})
	var requested []string
	engine.downloader.client.Transport = sourceFixtureTransport(func(request *http.Request) (*http.Response, error) {
		requested = append(requested, request.URL.Host+request.URL.Path)
		if request.URL.Host == "huangguoai.ai" {
			return sourceFixtureResponse(request, http.StatusOK, `<article class="route-card" data-url="https://ux90.rurhvbhx.cc"></article>`), nil
		}
		if request.URL.Host == "ux90.rurhvbhx.cc" {
			return sourceFixtureResponse(request, http.StatusOK, `{"data":{"list":[{"id":6139,"title":"合成短剧","totalEpisode":2}]}}`), nil
		}
		return sourceFixtureResponse(request, http.StatusBadGateway, "unexpected"), nil
	})
	engine.downloader.cfg.HuangguoAIURL = ""
	base := engine.downloader.huangguoAIContentBaseURL(context.Background())
	if !strings.HasPrefix(base, "https://ux90.rurhvbhx.cc") {
		t.Fatalf("content base %q did not follow the rotated content host (requests=%v)", base, requested)
	}
	for _, path := range requested {
		if strings.HasPrefix(path, "huangguoai.ai/api/") || strings.HasPrefix(path, "huangguoai.ai/video/") {
			t.Fatalf("content request was sent to the navigation page: %v", requested)
		}
	}
}

func TestHuangguoNativeCatalogUsesOnlineSearch(t *testing.T) {
	engine := sourceFixtureEngine(t, func(request *http.Request) (*http.Response, error) {
		if request.URL.Host == "huangguoai.ai" {
			return sourceFixtureResponse(request, http.StatusOK, `<a data-url="https://search.kmexvuoz.cc"></a>`), nil
		}
		if request.URL.Host != "search.kmexvuoz.cc" || !strings.HasPrefix(request.URL.Path, "/search/video/") {
			t.Fatalf("unexpected request: %s", request.URL.String())
		}
		query, _ := url.PathUnescape(strings.Trim(strings.TrimPrefix(request.URL.Path, "/search/video/"), "/"))
		if query != "一个乖乖女" {
			t.Fatalf("search keyword was not encoded in path: %q", query)
		}
		return sourceFixtureResponse(request, http.StatusOK, huangguoSearchFixture("一个乖乖女", "6139")), nil
	})
	page, err := engine.nativeCatalog(context.Background(), nativeInput{Source: sourceHuangguoAI, Query: "一个乖乖女", Page: 1})
	if err != nil || len(page.Items) != 1 || page.LocalSearch {
		t.Fatalf("native catalog did not use huangguo online search: %+v err=%v", page, err)
	}
	if page.Items[0].ID != "huangguoai:6139" || page.Items[0].Title != "一个乖乖女" {
		t.Fatalf("wrong native search result: %+v", page.Items[0])
	}
}
