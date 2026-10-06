package core

import (
	"context"
	"errors"
	"strings"
)

type nativeCategory struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func nativeCatalogKey(source, category string) string {
	source = canonicalProviderSource(source)
	if category = strings.TrimSpace(category); category != "" {
		return source + "|" + category
	}
	return source
}

func validNativeCategory(source, category string) bool {
	if category == "" {
		return true
	}
	if len(category) > 128 || strings.ContainsAny(category, "|/\\\x00\r\n") {
		return false
	}
	if canonicalProviderSource(source) != sourceHongguo {
		return false
	}
	for _, genre := range hongguoAppGenres {
		if category == genre.key {
			return true
		}
	}
	return false
}

// nativeCategories 只服务红果：分类来自应用内置的固定列表，不请求站源，也不需要落盘缓存。
func (engine *nativeEngine) nativeCategories(ctx context.Context, source string, force bool) ([]nativeCategory, error) {
	if canonicalProviderSource(source) != sourceHongguo {
		return nil, errors.New("请选择有效站源")
	}
	all := []nativeCategory{{Name: "全部"}}
	for _, genre := range hongguoAppGenres {
		all = append(all, nativeCategory{ID: genre.key, Name: genre.name})
	}
	return all, nil
}
