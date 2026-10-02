package core

import (
	"testing"
	"time"
)

func libraryExchangeEngine(t *testing.T) *nativeEngine {
	t.Helper()
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	engine.catalogs = map[string][]nativeDrama{
		sourceHongguo: {
			{MetadataSchema: 1, ID: "hongguo:7000000000000000001", Source: sourceHongguo, SourceID: "7000000000000000001", Title: "红果样本", Description: "本地简介", Cover: "https://hongguo.example.test/a.jpg", Episodes: 22, Category: "都市", Heat: "23686927", OnlineDate: "2026-08-24", Tags: []string{"都市"}},
			{MetadataSchema: 1, ID: "hongguo:7000000000000000002", Source: sourceHongguo, SourceID: "7000000000000000002", Title: "红果样本二"},
		},
		"hongguo|recommendation:real": {
			{MetadataSchema: 1, ID: "hongguo:7000000000000000001", Source: sourceHongguo, SourceID: "7000000000000000001", Title: "红果样本"},
			{MetadataSchema: 1, ID: "hongguo:7000000000000000009", Source: sourceHongguo, SourceID: "7000000000000000009", Title: "推荐样本"},
		},
	}
	engine.catalogStates = map[string]nativeCatalogState{sourceHongguo: {UpdatedAt: time.Now(), Page: 3}}
	return engine
}

func TestNativeLibraryExportSkipsCategoryKeysAndDeduplicates(t *testing.T) {
	engine := libraryExchangeEngine(t)
	document := engine.nativeLibraryExport()
	if document.Kind != nativeLibraryExchangeKind || document.Version != nativeLibraryExchangeVersion || document.Count != 2 {
		t.Fatal("incorrect exchange header", document)
	}
	if !document.ExportedAt.After(time.Now().Add(-time.Minute)) {
		t.Fatal("missing export time")
	}
	if document.App != nativeLibraryExchangeApp() {
		t.Fatal("incorrect application marker", document.App)
	}
	seen := map[string]nativeLibraryExchangeDrama{}
	for _, entry := range document.Dramas {
		if _, found := seen[entry.ID]; found {
			t.Fatal("duplicated entry", entry.ID)
		}
		seen[entry.ID] = entry
	}
	first := seen["hongguo:7000000000000000001"]
	if first.Source != sourceHongguo || first.SourceID != "7000000000000000001" || first.Title != "红果样本" || first.Episodes != 22 || first.Cover != "https://hongguo.example.test/a.jpg" {
		t.Fatal("incorrect entry", first)
	}
	if _, found := seen["hongguo:7000000000000000009"]; found {
		t.Fatal("category key leaked into the export")
	}
	if _, found := seen["hongguo|recommendation:real"]; found {
		t.Fatal("recommendation key leaked into the export")
	}
}

func TestNativeLibraryImportMergesCompletesAndKeepsLocalValues(t *testing.T) {
	engine := libraryExchangeEngine(t)
	document := nativeLibraryExchange{
		App: "juku", Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion,
		Dramas: []nativeLibraryExchangeDrama{
			{ID: "hongguo:7000000000000000001", Title: "红果样本", Description: "来自网页版的简介", Cover: "https://hongguo.example.test/b.jpg", Episodes: 30, Category: "古装仙侠", Heat: "覆盖热度", Views: "覆盖播放量", OnlineDate: "2026-09-09", ReleaseStatus: "finished", Tags: []string{"都市", "古装"}},
			{ID: "hongguo:7000000000000000003", Title: "红果新样本", Description: "新条目", Episodes: 12, OnlineDate: "2026-09-01"},
			{ID: "", Title: "缺少 ID"},
			{ID: "not-a-provider-id", Title: "无法识别的 ID"},
			{ID: "hongguo:不是数字", Title: "红果 ID 非数字"},
			{ID: "1#2"},
		},
	}
	result, err := engine.nativeLibraryImport(document)
	if err != nil {
		t.Fatal(err)
	}
	if result.Imported != 1 || result.Rejected != 4 {
		t.Fatalf("incorrect totals %+v", result)
	}
	if result.Total != 3 || result.Sources[sourceHongguo] != 3 {
		t.Fatalf("incorrect counters %+v", result)
	}
	items := engine.catalogs[sourceHongguo]
	if len(items) != 3 {
		t.Fatal("local entries were lost", items)
	}
	if len(engine.catalogs["hongguo|recommendation:real"]) != 2 {
		t.Fatal("category keys must not be written by an import")
	}
	first := items[0]
	if first.Title != "红果样本" || first.Description != "本地简介" || first.Category != "都市" || first.Episodes != 22 {
		t.Fatal("existing values were overwritten", first)
	}
	if first.Heat != "23686927" || first.OnlineDate != "2026-08-24" {
		t.Fatal("existing metadata was overwritten", first.Heat, first.OnlineDate)
	}
	if first.Cover != "https://hongguo.example.test/a.jpg" {
		t.Fatal("existing cover was replaced", first.Cover)
	}
	if len(first.Tags) != 1 || first.Tags[0] != "都市" {
		t.Fatal("local tags were replaced", first.Tags)
	}
	if engine.catalogStates[sourceHongguo].Page != 3 {
		t.Fatal("pagination state was reset", engine.catalogStates[sourceHongguo])
	}
}

func TestNativeLibraryImportIsRepeatableAndPersists(t *testing.T) {
	engine := libraryExchangeEngine(t)
	document := nativeLibraryExchange{Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion, Dramas: []nativeLibraryExchangeDrama{{ID: "hongguo:7000000000000000003", Title: "红果新样本"}}}
	for round := 0; round < 2; round++ {
		if _, err := engine.nativeLibraryImport(document); err != nil {
			t.Fatal(err)
		}
	}
	if len(engine.catalogs[sourceHongguo]) != 3 {
		t.Fatal("repeated import duplicated entries", engine.catalogs[sourceHongguo])
	}
	reopened, err := newNativeEngine(engine.directory)
	if err != nil {
		t.Fatal(err)
	}
	reopened.loadCatalogCache()
	if len(reopened.catalogs[sourceHongguo]) != 3 {
		t.Fatal("imported entries did not survive a restart", reopened.catalogs[sourceHongguo])
	}
	found := false
	for _, drama := range reopened.catalogs[sourceHongguo] {
		if drama.ID == "hongguo:7000000000000000003" && drama.Title == "红果新样本" && drama.SourceID == "7000000000000000003" {
			found = true
		}
	}
	if !found {
		t.Fatal("imported entry was not persisted", reopened.catalogs[sourceHongguo])
	}
}

func TestNativeLibraryImportRejectsForeignVersions(t *testing.T) {
	directory := t.TempDir()
	if response := NativeRequest(`{"action":"initialize","directory":"` + directory + `"}`); !containsText(response, `"ok":true`) {
		t.Fatal("engine did not start", response)
	}
	defer NativeRequest(`{"action":"release"}`)
	raw := `{"action":"libraryImport","library":{"kind":"library","version":2,"dramas":[{"id":"hongguo:1"}]}}`
	response := NativeRequest(raw)
	if !containsText(response, "版本不兼容") {
		t.Fatal("incompatible version was accepted", response)
	}
	raw = `{"action":"libraryImport","library":{"kind":"library","version":1,"dramas":[{"id":"hongguo:7000000000000000001","title":"红果样本"}]}}`
	if response := NativeRequest(raw); !containsText(response, `"ok":true`) {
		t.Fatal("valid import was rejected", response)
	}
	if response := NativeRequest(`{"action":"libraryExport"}`); !containsText(response, `"kind":"library"`) || !containsText(response, `"count":1`) {
		t.Fatal("export did not return the exchanged document", response)
	}
}

func containsText(body, needle string) bool {
	return len(body) >= len(needle) && (func() bool {
		for index := 0; index+len(needle) <= len(body); index++ {
			if body[index:index+len(needle)] == needle {
				return true
			}
		}
		return false
	})()
}
