package core

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestNativeCatalogDeferredSaveWritesOnce(t *testing.T) {
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)
	path := filepath.Join(engine.directory, "catalogs.json")
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	engine.mu.Lock()
	engine.deferCatalogSave = true
	engine.mu.Unlock()

	for index := 0; index < 3; index++ {
		source := nativeCatalogKey(sourceYaguo, "feed"+string(rune('a'+index)))
		engine.saveCatalogCache(source, &nativeCatalogResult{Page: 1, Items: []nativeDrama{{ID: source + ":1", Title: "样本", Source: sourceYaguo}}})
		if _, err := os.Stat(path); !os.IsNotExist(err) {
			t.Fatal("deferred save must not touch the disk")
		}
	}

	engine.mu.Lock()
	engine.deferCatalogSave = false
	saveErr := engine.writeCatalogDiskLocked()
	engine.mu.Unlock()
	if saveErr != nil {
		t.Fatalf("final flush failed: %v", saveErr)
	}
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("final flush did not write the catalog: %v", err)
	}
	var disk nativeCatalogDisk
	if err := json.Unmarshal(body, &disk); err != nil {
		t.Fatal(err)
	}
	for index := 0; index < 3; index++ {
		key := nativeCatalogKey(sourceYaguo, "feed"+string(rune('a'+index)))
		if len(disk.Catalogs[key]) != 1 {
			t.Fatalf("category %s was not persisted", key)
		}
	}
	if len(disk.Catalogs[sourceYaguo]) != 3 {
		t.Fatalf("base aggregate was not persisted: %d", len(disk.Catalogs[sourceYaguo]))
	}
}
