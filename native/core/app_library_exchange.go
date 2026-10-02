package core

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"reflect"
	"sort"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	nativeLibraryExchangeKind    = "library"
	nativeLibraryExchangeVersion = 1
	nativeLibraryExchangeBytes   = 32 << 20
	nativeLibraryExchangeEntries = 200000
	nativeLibraryExchangeTagMax  = 64
)

type nativeLibraryExchangeDrama struct {
	ID            string   `json:"id"`
	Source        string   `json:"source,omitempty"`
	SourceID      string   `json:"sourceId,omitempty"`
	Title         string   `json:"title,omitempty"`
	Description   string   `json:"description,omitempty"`
	Cover         string   `json:"cover,omitempty"`
	Episodes      int      `json:"episodes,omitempty"`
	Category      string   `json:"category,omitempty"`
	VIP           *bool    `json:"vip,omitempty"`
	Heat          string   `json:"heat,omitempty"`
	Views         string   `json:"views,omitempty"`
	OnlineDate    string   `json:"onlineDate,omitempty"`
	Tags          []string `json:"tags,omitempty"`
	ReleaseStatus string   `json:"releaseStatus,omitempty"`
}

type nativeLibraryExchange struct {
	App        string                       `json:"app,omitempty"`
	Kind       string                       `json:"kind"`
	Version    int                          `json:"version"`
	ExportedAt time.Time                    `json:"exportedAt"`
	Count      int                          `json:"count"`
	Dramas     []nativeLibraryExchangeDrama `json:"dramas"`
}

type nativeLibraryImportResult struct {
	Imported int            `json:"imported"`
	Merged   int            `json:"merged"`
	Rejected int            `json:"rejected"`
	Denied   int            `json:"denied"`
	Total    int            `json:"total"`
	Sources  map[string]int `json:"sources"`
}

func nativeLibraryExchangeApp() string {
	if buildAllSources == "true" {
		return "zhenguojian"
	}
	return "hongguojian"
}

func nativeLibraryExchangeText(value string, limit int) string {
	value = strings.ToValidUTF8(strings.TrimSpace(value), "")
	if len(value) > limit {
		value = value[:limit]
		for !utf8.ValidString(value) {
			value = value[:len(value)-1]
		}
	}
	return value
}

func nativeLibraryExchangeTags(values []string) []string {
	var tags []string
	seen := map[string]bool{}
	for _, value := range values {
		value = nativeLibraryExchangeText(value, 128)
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		tags = append(tags, value)
		if len(tags) >= nativeLibraryExchangeTagMax {
			break
		}
	}
	return tags
}

func validNativeLibraryExchangeID(id string) bool {
	id = strings.TrimSpace(id)
	if id == "" || len(id) > 512 || strings.ContainsAny(id, ",\t\n\r") {
		return false
	}
	source, sourceID, valid := splitProviderDramaID(id)
	if !valid || len(sourceID) > 512 {
		return false
	}
	if source == sourceHongguo {
		return hongguoNumericID.MatchString(sourceID)
	}
	return true
}

func nativeLibraryExchangeFromDrama(drama nativeDrama) (nativeLibraryExchangeDrama, bool) {
	source, sourceID, valid := splitProviderDramaID(drama.ID)
	if !valid {
		return nativeLibraryExchangeDrama{}, false
	}
	entry := nativeLibraryExchangeDrama{
		ID:            providerDramaID(source, sourceID),
		Source:        source,
		SourceID:      sourceID,
		Title:         nativeLibraryExchangeText(drama.Title, 4096),
		Description:   nativeLibraryExchangeText(drama.Description, 20000),
		Cover:         nativeLibraryExchangeText(drama.Cover, 4096),
		Episodes:      drama.Episodes,
		Category:      nativeLibraryExchangeText(drama.Category, 512),
		Heat:          nativeLibraryExchangeText(drama.Heat, 256),
		Views:         nativeLibraryExchangeText(drama.Views, 256),
		OnlineDate:    nativeLibraryExchangeText(drama.OnlineDate, 256),
		Tags:          nativeLibraryExchangeTags(drama.Tags),
		ReleaseStatus: nativeLibraryExchangeText(drama.ReleaseStatus, 64),
	}
	if entry.Episodes < 0 || entry.Episodes > 100000 {
		entry.Episodes = 0
	}
	if drama.VIP != nil {
		value := *drama.VIP
		entry.VIP = &value
	}
	return entry, true
}

func nativeLibraryExchangeToDrama(entry nativeLibraryExchangeDrama) (nativeDrama, bool) {
	id := strings.TrimSpace(entry.ID)
	if !validNativeLibraryExchangeID(id) {
		return nativeDrama{}, false
	}
	source, sourceID, _ := splitProviderDramaID(id)
	id = providerDramaID(source, sourceID)
	drama := nativeDrama{
		MetadataSchema: 1,
		ID:             id,
		Source:         source,
		SourceID:       sourceID,
		Title:          nativeLibraryExchangeText(entry.Title, 4096),
		Description:    nativeLibraryExchangeText(entry.Description, 20000),
		Cover:          nativeLibraryExchangeText(entry.Cover, 4096),
		Category:       nativeLibraryExchangeText(entry.Category, 512),
		Heat:           nativeLibraryExchangeText(entry.Heat, 256),
		Views:          nativeLibraryExchangeText(entry.Views, 256),
		OnlineDate:     nativeLibraryExchangeText(entry.OnlineDate, 256),
		Tags:           nativeLibraryExchangeTags(entry.Tags),
		ReleaseStatus:  nativeLibraryExchangeText(entry.ReleaseStatus, 64),
	}
	if entry.Episodes > 0 && entry.Episodes <= 100000 {
		drama.Episodes = entry.Episodes
	}
	if entry.VIP != nil {
		value := *entry.VIP
		drama.VIP = &value
	}
	return drama, true
}

func (engine *nativeEngine) nativeLibraryExport() nativeLibraryExchange {
	engine.mu.Lock()
	defer engine.mu.Unlock()
	document := nativeLibraryExchange{App: nativeLibraryExchangeApp(), Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion, ExportedAt: time.Now().UTC().Truncate(time.Second), Dramas: []nativeLibraryExchangeDrama{}}
	seen := map[string]bool{}
	keys := make([]string, 0, len(engine.catalogs))
	for key := range engine.catalogs {
		if !strings.Contains(key, "|") {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	for _, key := range keys {
		source := canonicalProviderSource(key)
		if !nativeSourceAvailable(source) {
			continue
		}
		for _, item := range engine.catalogs[key] {
			entry, valid := nativeLibraryExchangeFromDrama(item)
			if !valid || seen[entry.ID] {
				continue
			}
			seen[entry.ID] = true
			document.Dramas = append(document.Dramas, entry)
		}
	}
	sort.SliceStable(document.Dramas, func(left, right int) bool {
		if document.Dramas[left].Source != document.Dramas[right].Source {
			return document.Dramas[left].Source < document.Dramas[right].Source
		}
		return document.Dramas[left].ID < document.Dramas[right].ID
	})
	document.Count = len(document.Dramas)
	return document
}

func (engine *nativeEngine) nativeLibraryImport(document nativeLibraryExchange) (nativeLibraryImportResult, error) {
	result := nativeLibraryImportResult{Sources: map[string]int{}}
	incoming := map[string][]nativeDrama{}
	for _, entry := range document.Dramas {
		drama, valid := nativeLibraryExchangeToDrama(entry)
		if !valid {
			result.Rejected++
			continue
		}
		if !nativeSourceAvailable(drama.Source) {
			result.Denied++
			continue
		}
		incoming[drama.Source] = append(incoming[drama.Source], drama)
	}
	engine.mu.Lock()
	defer engine.mu.Unlock()
	changed := false
	sources := make([]string, 0, len(incoming))
	for source := range incoming {
		sources = append(sources, source)
	}
	sort.Strings(sources)
	for _, source := range sources {
		previous := engine.catalogs[source]
		positions := make(map[string]int, len(previous))
		for index, drama := range previous {
			positions[drama.ID] = index
		}
		for _, drama := range incoming[source] {
			position, found := positions[drama.ID]
			if !found {
				positions[drama.ID] = len(previous)
				previous = append(previous, drama)
				result.Imported++
				changed = true
				continue
			}
			before := previous[position]
			merged := mergeNativeDrama(drama, before)
			if !reflect.DeepEqual(merged, before) {
				previous[position] = merged
				changed = true
			}
			oldEntry, _ := nativeLibraryExchangeFromDrama(before)
			if entry, valid := nativeLibraryExchangeFromDrama(merged); valid && !reflect.DeepEqual(oldEntry, entry) {
				result.Merged++
			}
		}
		engine.catalogs[source] = previous
		state, found := engine.catalogStates[source]
		if !found || state.Page < 1 {
			state.Page = 1
		}
		if !found {
			state.HasMore = true
		}
		if state.UpdatedAt.IsZero() {
			state.UpdatedAt = time.Now()
		}
		engine.catalogStates[source] = state
	}
	counts, total := engine.nativeLibraryCountsLocked()
	for source, count := range counts {
		result.Sources[source] = count
	}
	result.Total = total
	var saveErr error
	if changed {
		saveErr = engine.writeCatalogDiskLocked()
	}
	return result, saveErr
}

func (engine *nativeEngine) nativeLibraryCountsLocked() (map[string]int, int) {
	counts := map[string]int{}
	total := 0
	for key, items := range engine.catalogs {
		if strings.Contains(key, "|") {
			continue
		}
		counts[canonicalProviderSource(key)] += len(items)
		total += len(items)
	}
	return counts, total
}

func (engine *nativeEngine) nativeLibraryExportXZ() (string, int, error) {
	document := engine.nativeLibraryExport()
	payload, err := json.Marshal(document)
	if err != nil {
		return "", 0, err
	}
	compressed, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		return "", 0, err
	}
	return base64.StdEncoding.EncodeToString(compressed), document.Count, nil
}

func nativeLibraryImportXZ(payload string) (nativeLibraryExchange, error) {
	var document nativeLibraryExchange
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(payload))
	if err != nil {
		return document, errors.New("剧库压缩包格式无效")
	}
	if !nativeLibraryExchangeIsXZ(raw) {
		return document, errors.New("剧库文件不是 XZ 压缩包")
	}
	decoded, err := nativeLibraryExchangeDecompress(raw)
	if err != nil {
		return document, errors.New("剧库文件解压失败，请确认文件完整")
	}
	if json.Unmarshal(decoded, &document) != nil {
		return document, errors.New("剧库文件格式无效")
	}
	return document, nil
}
