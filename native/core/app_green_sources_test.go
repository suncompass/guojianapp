package core

import (
	"context"
	"net/http"
	"strings"
	"testing"
)

// 单红果鉴版本只放行绿色站源：白名单里的站源必须已注册且可用，
// 名单外的站源（成人站源、已下线站源、未知标识）一律不可用。
func TestNativeGreenWhitelistMatchesRegistration(t *testing.T) {
	for source := range nativeGreenSources {
		if !isHuangguoProviderSource(source) {
			t.Fatalf("whitelisted source %q is not a registered provider source", source)
		}
		if !nativeSourceAvailable(source) {
			t.Fatalf("whitelisted source %q is unavailable in this build", source)
		}
	}
	for _, source := range []string{sourceChaoguo, sourceYanguo, sourceTaoguo, sourceHuangdou, sourceDSD, "unknown"} {
		if nativeSourceAvailable(source) {
			t.Fatalf("%q must not be available in the green-only build", source)
		}
	}
}

// 绿色站源必须恰好覆盖注册表里除成人站源外的条目，避免「注册了但没放行」或反过来。
func TestNativeGreenWhitelistCoversGreenCatalog(t *testing.T) {
	for _, spec := range duanjuProviderCatalog {
		want := nativeGreenSources[spec.ID]
		if spec.ID == sourceChaoguo {
			// 超果是成人站源，注册但不在白名单内。
			if want {
				t.Fatal("chaoguo must not be whitelisted")
			}
			continue
		}
		if !want {
			t.Fatalf("Registered green source %q is missing from the whitelist", spec.ID)
		}
	}
}

// 每个注册站源都必须接通目录、搜索、详情三条分派链路。0.2.101 曾出现
// “注册了但分发函数漏登记”导致点开即报错的缺陷，这里用离线夹具守住它。
func TestEveryRegisteredSourceIsWired(t *testing.T) {
	page := `<html><body><div class="module-item"><a href="/detail/9001.html" title="样本剧"><span class="pic-text">第2集</span></a></div></body></html>`
	d, server := duanjuFixtureDownloader(t, func(writer http.ResponseWriter, request *http.Request) {
		writer.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = writer.Write([]byte(page))
	})
	for _, spec := range duanjuProviderCatalog {
		d.providerHosts[spec.ID] = server.URL
		if _, _, err := d.fetchDuanjuCatalogPage(context.Background(), spec.ID, 1, ""); err != nil &&
			strings.Contains(err.Error(), "暂未接入目录") {
			t.Fatalf("%s catalog is not wired: %v", spec.ID, err)
		}
		if _, err := d.searchDuanju(context.Background(), spec.ID, "都市"); err != nil &&
			strings.Contains(err.Error(), "不支持在线搜索") {
			t.Fatalf("%s search is not wired: %v", spec.ID, err)
		}
		if _, _, err := d.fetchDuanjuDetail(context.Background(), spec.ID, "9001"); err != nil &&
			strings.Contains(err.Error(), "暂未接入详情") {
			t.Fatalf("%s detail is not wired: %v", spec.ID, err)
		}
	}
}

// 米果的分类页不分页，声明 Paged 会让「加载更多」反复取回同一批条目。
func TestMiguoDoesNotAdvertisePaging(t *testing.T) {
	if duanjuSupportsPaging(sourceMiguo) {
		t.Fatal("miguo must not advertise catalog paging")
	}
	if !duanjuSupportsPaging(sourceShuangguo) {
		t.Fatal("shuangguo pages its catalog by category")
	}
	if !duanjuSupportsSearch(sourceMiguo) || !duanjuSupportsSearch(sourceShuangguo) {
		t.Fatal("both new sources must support online search")
	}
}
