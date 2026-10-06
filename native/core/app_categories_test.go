package core

import (
	"context"
	"testing"
)

func TestNativeCategoriesComeFromTheBuiltInHongguoGenres(t *testing.T) {
	engine := &nativeEngine{}
	for _, source := range []string{sourceHongguo, "hongguoduanju.com", "huangdou", "unknown"} {
		categories, err := engine.nativeCategories(context.Background(), source, false)
		if canonicalProviderSource(source) != sourceHongguo {
			if err == nil {
				t.Fatal("已下线或未知站源不应返回分类", source)
			}
			continue
		}
		if err != nil {
			t.Fatal(err)
		}
		if len(categories) != len(hongguoAppGenres)+1 || categories[0].Name != "全部" {
			t.Fatal("红果分类应由内置列表生成", categories)
		}
		for index, genre := range hongguoAppGenres {
			if categories[index+1].ID != genre.key || categories[index+1].Name != genre.name {
				t.Fatal("分类顺序与内置列表不一致", categories[index+1], genre)
			}
			if !validNativeCategory(sourceHongguo, genre.key) {
				t.Fatal("内置分类应通过校验", genre.key)
			}
		}
	}
}

func TestInvalidCategoryNeverEntersACacheNamespace(t *testing.T) {
	for _, source := range []string{sourceHongguo, sourceHuangdou, sourceHuangguoAI, sourceCloudFront} {
		if validNativeCategory(source, "../other|source") {
			t.Fatal("invalid category entered a cache namespace")
		}
		if err := nativeAuthorizeInput(nativeInput{Action: "categories", Source: source}); (err == nil) != nativeSourceAvailable(source) {
			t.Fatal("categories ignored edition permissions", source, err)
		}
	}
}
