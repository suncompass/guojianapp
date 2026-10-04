package core

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const nativeCatalogTTL = 15 * time.Minute

type nativeCatalogState struct {
	UpdatedAt time.Time `json:"updatedAt"`
	Page      int       `json:"page"`
	HasMore   bool      `json:"hasMore"`
	Warning   string    `json:"warning,omitempty"`
}

type nativeCatalogDisk struct {
	Version         int                                  `json:"version"`
	Catalogs        map[string][]nativeDrama             `json:"catalogs"`
	States          map[string]nativeCatalogState        `json:"states"`
	Categories      map[string][]nativeCategory          `json:"categories,omitempty"`
	HongguoApp      *hongguoCatalogState                 `json:"hongguoApp,omitempty"`
	Recommendations map[string]nativeRecommendationState `json:"recommendations,omitempty"`
}

func (engine *nativeEngine) loadCatalogCache() {
	file, err := os.Open(filepath.Join(engine.directory, "catalogs.json"))
	if err != nil {
		return
	}
	defer file.Close()
	body, err := io.ReadAll(io.LimitReader(file, nativeCatalogMaxBytes+1))
	if err != nil || len(body) > nativeCatalogMaxBytes {
		return
	}
	var disk nativeCatalogDisk
	if json.Unmarshal(body, &disk) == nil && (disk.Version == 2 || disk.Version == 3) {
		if disk.Catalogs != nil {
			engine.catalogs = disk.Catalogs
			for _, items := range engine.catalogs {
				for index := range items {
					items[index] = migrateNativeDrama(items[index])
				}
			}
		}
		if disk.States != nil {
			engine.catalogStates = disk.States
		}
		engine.categoryOptions = disk.Categories
		engine.recommendations = make(map[string]nativeRecommendationState)
		for genre, state := range disk.Recommendations {
			if genre == state.Query.Genre && state.Query.validate() == nil && state.Page > 0 {
				engine.recommendations[genre] = state
			}
		}
		engine.hongguoCatalog = cloneHongguoCatalogState(disk.HongguoApp)
		if engine.downloader != nil {
			engine.downloader.restoreHongguoCatalog(disk.HongguoApp)
			if disk.HongguoApp != nil {
				engine.hongguoCatalog = engine.downloader.hongguoCatalogSnapshot()
			}
		}
		return
	}
	var legacy map[string][]nativeDrama
	if json.Unmarshal(body, &legacy) == nil && legacy != nil {
		engine.catalogs = legacy
		for _, items := range engine.catalogs {
			for index := range items {
				items[index] = migrateNativeDrama(items[index])
			}
		}
	}
}

func migrateNativeDrama(drama nativeDrama) nativeDrama {
	if drama.MetadataSchema == 0 && drama.Source == sourceHuangdou && drama.VIP != nil && !*drama.VIP {
		drama.VIP = nil
	}
	if strings.Contains(strings.ToLower(drama.Cover), "huangguoai.com") {
		drama.Cover = ""
	}
	drama = migrateDuanjuPayloadKey(drama)
	drama.MetadataSchema = 1
	return drama
}

func (engine *nativeEngine) nativeCached(source string) nativeCatalogResult {
	source = canonicalProviderSource(source)
	engine.mu.Lock()
	defer engine.mu.Unlock()
	items := append([]nativeDrama{}, engine.catalogs[source]...)
	for index := range items {
		items[index].Cover = repairLegacyCoverURL(items[index])
	}
	state, found := engine.catalogStates[source]
	age := time.Since(state.UpdatedAt)
	result := nativeCatalogResult{
		Items: items, Page: max(1, state.Page), HasMore: !found || state.HasMore,
		Fresh:   len(items) > 0 && state.Warning == "" && !state.UpdatedAt.IsZero() && age >= 0 && age < nativeCatalogTTL,
		Warning: state.Warning,
	}
	if engine.catalogSaveError != nil {
		result.Warning = joinNativeWarnings(result.Warning, engine.catalogSaveError.Error())
		result.saveError = engine.catalogSaveError
		result.Fresh, result.HasMore = false, true
	}
	return result
}

func mergeNativeCatalog(first, second []nativeDrama) []nativeDrama {
	items := append([]nativeDrama{}, first...)
	indices := make(map[string]int, len(items))
	for index, item := range items {
		indices[item.ID] = index
	}
	for _, item := range second {
		if index, found := indices[item.ID]; found {
			items[index] = mergeNativeDrama(items[index], item)
		} else {
			indices[item.ID] = len(items)
			items = append(items, item)
		}
	}
	return items
}

func mergeNativeDrama(previous, fresh nativeDrama) nativeDrama {
	previous, fresh = migrateNativeDrama(previous), migrateNativeDrama(fresh)
	if previous.ID != "" && fresh.ID != previous.ID {
		return fresh
	}
	if fresh.Source == "" {
		fresh.Source = previous.Source
	}
	if fresh.SourceID == "" {
		fresh.SourceID = previous.SourceID
	}
	if fresh.Title == "" || fresh.Title == "短剧" {
		fresh.Title = previous.Title
	}
	if fresh.Description == "" {
		fresh.Description = previous.Description
	}
	if fresh.Cover == "" {
		fresh.Cover = previous.Cover
	}
	if fresh.Category == "" || nativeGenericCategory(fresh.Category) && previous.Category != "" && !nativeGenericCategory(previous.Category) {
		fresh.Category = previous.Category
	}
	if fresh.Episodes == 0 {
		fresh.Episodes = previous.Episodes
	}
	if fresh.VIP == nil {
		fresh.VIP = previous.VIP
	}
	if fresh.Heat == "" {
		fresh.Heat = previous.Heat
	}
	if fresh.Views == "" {
		fresh.Views = previous.Views
	}
	if fresh.OnlineDate == "" {
		fresh.OnlineDate = previous.OnlineDate
	}
	if len(fresh.Tags) == 0 {
		fresh.Tags = previous.Tags
	}
	if fresh.ReleaseStatus == "" || fresh.ReleaseStatus == "unknown" {
		fresh.ReleaseStatus = previous.ReleaseStatus
	}
	return fresh
}

func nativeGenericCategory(category string) bool {
	switch category {
	case "短剧", "真人剧", "漫剧", "AI剧", "AI 剧", "AI短剧", "AI 短剧", "AI漫剧", "AI 漫剧":
		return true
	}
	return false
}

func (engine *nativeEngine) saveCatalogCache(source string, result *nativeCatalogResult) error {
	engine.mu.Lock()
	defer engine.mu.Unlock()
	previous := engine.catalogs[source]
	state := engine.catalogStates[source]
	var items []nativeDrama
	if result.Page == 1 {
		items = result.Items
		if len(previous) > 0 {
			old := make(map[string]nativeDrama, len(previous))
			for _, item := range previous {
				old[item.ID] = item
			}
			for index, item := range items {
				items[index] = mergeNativeDrama(old[item.ID], item)
			}
			fresh := make(map[string]bool, len(items))
			for _, item := range items {
				fresh[item.ID] = true
			}
			for _, item := range previous {
				if !fresh[item.ID] {
					items = append(items, item)
				}
			}
			result.Items = items
			result.Page = max(1, state.Page)
			if source != sourceHongguo && state.Page > 1 {
				result.HasMore = state.HasMore
			}
		}
	} else {
		items = mergeNativeCatalog(previous, result.Items)
		if result.Page < state.Page {
			result.Page, result.HasMore = state.Page, state.HasMore
		}
	}
	engine.catalogs[source] = items
	if result.hongguo != nil {
		engine.hongguoCatalog = cloneHongguoCatalogState(result.hongguo)
	}
	if result.Warning != "" {
		result.Page = max(1, state.Page)
		result.HasMore = true
	}
	state.Page, state.HasMore = result.Page, result.HasMore
	state.Warning = result.Warning
	if result.Warning == "" {
		state.UpdatedAt = time.Now()
		result.Fresh = true
	}
	engine.catalogStates[source] = state
	if base, _, categorized := strings.Cut(source, "|"); categorized {
		engine.catalogs[base] = mergeNativeCatalog(engine.catalogs[base], items)
	}
	err := engine.writeCatalogDiskLocked()
	result.saveError = err
	if err != nil {
		result.Warning = joinNativeWarnings(result.Warning, err.Error())
		result.Fresh, result.HasMore = false, true
	}
	return err
}

// 测试钩子：快照完成、开始编码之前调用。生产路径为 nil。
var catalogSaveBeforeEncode func()

// 写盘前的完整快照，必须在引擎锁内调用。
//
// 序列化在锁外进行，期间别的路径会就地改这些切片（例如 saveCoverAddress 直接写
// items[index].Cover），所以这里逐条复制元素，不能让快照与内存共享底层数组。
func (engine *nativeEngine) catalogDiskSnapshotLocked() nativeCatalogDisk {
	catalogs := make(map[string][]nativeDrama, len(engine.catalogs))
	for source, items := range engine.catalogs {
		catalogs[source] = append([]nativeDrama(nil), items...)
	}
	states := make(map[string]nativeCatalogState, len(engine.catalogStates))
	for key, state := range engine.catalogStates {
		states[key] = state
	}
	categories := make(map[string][]nativeCategory, len(engine.categoryOptions))
	for source, items := range engine.categoryOptions {
		categories[source] = append([]nativeCategory(nil), items...)
	}
	recommendations := make(map[string]nativeRecommendationState, len(engine.recommendations))
	for genre, state := range engine.recommendations {
		state.Query.Seen = append([]string(nil), state.Query.Seen...)
		recommendations[genre] = state
	}
	return nativeCatalogDisk{
		Version:         3,
		Catalogs:        catalogs,
		States:          states,
		Categories:      categories,
		HongguoApp:      cloneHongguoCatalogState(engine.hongguoCatalog),
		Recommendations: recommendations,
	}
}

// 调用方按 ...Locked 约定持有引擎锁。这里先把锁交还、返回前再拿回来，于是编码与
// 落盘（最大 32 MiB 加 fsync）期间目录、播放等请求不会被挡住；保存锁则保证写盘
// 串行，磁盘不会因为旧快照晚到而回退。
func (engine *nativeEngine) writeCatalogDiskLocked() error {
	engine.mu.Unlock()
	defer engine.mu.Lock()

	engine.saveMu.Lock()
	defer engine.saveMu.Unlock()

	engine.mu.Lock()
	if engine.deferCatalogSave {
		engine.markCatalogSavePendingLocked()
		engine.mu.Unlock()
		return nil
	}
	disk := engine.catalogDiskSnapshotLocked()
	engine.mu.Unlock()

	if catalogSaveBeforeEncode != nil {
		catalogSaveBeforeEncode()
	}
	body, err := json.Marshal(disk)
	if err == nil && len(body) > nativeCatalogMaxBytes {
		err = errNativeCatalogLimit
	}
	if err == nil {
		err = writeNativeCacheFile(filepath.Join(engine.directory, "catalogs.json"), body)
	}

	engine.mu.Lock()
	engine.catalogSaveError = nativeSaveError("剧库", err)
	if err == nil {
		engine.finishCatalogSaveLocked()
	} else {
		engine.markCatalogSavePendingLocked()
	}
	saveError := engine.catalogSaveError
	engine.mu.Unlock()
	return saveError
}

func writeNativeCacheFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".cache-write-*")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	_, writeErr := temporary.Write(data)
	if writeErr == nil {
		writeErr = temporary.Sync()
	}
	closeErr := temporary.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(temporary.Name(), path)
}

func (engine *nativeEngine) saveDetailMetadata(drama nativeDrama) error {
	engine.mu.Lock()
	defer engine.mu.Unlock()
	changed := false
	for _, items := range engine.catalogs {
		for index := range items {
			if items[index].ID == drama.ID {
				items[index] = mergeNativeDrama(items[index], drama)
				changed = true
			}
		}
	}
	if changed {
		return engine.writeCatalogDiskLocked()
	}
	return nil
}
