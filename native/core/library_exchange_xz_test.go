package core

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestNativeLibraryExchangeXZRoundTrip(t *testing.T) {
	payload, err := json.Marshal(nativeLibraryExchange{App: "guoguojuku", Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion, Count: 1, Dramas: []nativeLibraryExchangeDrama{{ID: "hongguo:1", Source: "hongguo", Title: "样本剧"}}})
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		t.Fatal(err)
	}
	if !nativeLibraryExchangeIsXZ(compressed) {
		t.Fatalf("output is not an xz stream: % x", compressed[:6])
	}
	restored, err := nativeLibraryExchangeDecompress(compressed)
	if err != nil {
		t.Fatal(err)
	}
	if string(restored) != string(payload) {
		t.Fatal("round trip changed the payload")
	}
}

func TestNativeLibraryImportXZValidatesInput(t *testing.T) {
	if _, err := nativeLibraryImportXZ("not base64"); err == nil {
		t.Fatal("invalid base64 should be rejected")
	}
	plain := base64.StdEncoding.EncodeToString([]byte(`{"kind":"library","version":1}`))
	if _, err := nativeLibraryImportXZ(plain); err == nil {
		t.Fatal("uncompressed payload should be rejected as xz")
	}
	valid, err := nativeLibraryExchangeCompress([]byte(`{"kind":"library","version":1}`))
	if err != nil {
		t.Fatal(err)
	}
	document, err := nativeLibraryImportXZ(base64.StdEncoding.EncodeToString(valid))
	if err != nil {
		t.Fatalf("a valid stream should decode: %v", err)
	}
	if document.Kind != "library" || document.Version != 1 {
		t.Fatalf("unexpected document: %+v", document)
	}
	damaged := append(append([]byte{}, valid[:len(valid)/2]...), 0xFF, 0xFF)
	if _, err := nativeLibraryImportXZ(base64.StdEncoding.EncodeToString(damaged)); err == nil {
		t.Fatal("a truncated stream should be rejected")
	}
	notJSON, err := nativeLibraryExchangeCompress([]byte("<html>nope</html>"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := nativeLibraryImportXZ(base64.StdEncoding.EncodeToString(notJSON)); err == nil {
		t.Fatal("an xz stream that is not a library document should be rejected")
	}
}

func TestNativeLibraryExchangeXZInteroperatesWithSystemXZ(t *testing.T) {
	if _, err := exec.LookPath("xz"); err != nil {
		t.Skip("system xz is not installed")
	}
	payload, err := json.Marshal(nativeLibraryExchange{Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion, Count: 1, Dramas: []nativeLibraryExchangeDrama{{ID: "hongguo:1", Source: "hongguo", Title: "系统 xz 互通样本"}}})
	if err != nil {
		t.Fatal(err)
	}
	mine, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	fromCore := filepath.Join(dir, "from-core.xz")
	if err := os.WriteFile(fromCore, mine, 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command("xz", "-dc", fromCore).Output()
	if err != nil {
		t.Fatalf("system xz could not read the native stream: %v", err)
	}
	if string(out) != string(payload) {
		t.Fatal("system xz produced different bytes")
	}
	source := filepath.Join(dir, "payload.json")
	if err := os.WriteFile(source, payload, 0o600); err != nil {
		t.Fatal(err)
	}
	fromSystem := filepath.Join(dir, "from-system.xz")
	file, err := os.Create(fromSystem)
	if err != nil {
		t.Fatal(err)
	}
	command := exec.Command("xz", "-c", source)
	command.Stdout = file
	runErr := command.Run()
	closeErr := file.Close()
	if runErr != nil {
		t.Fatalf("system xz compress failed: %v", runErr)
	}
	if closeErr != nil {
		t.Fatal(closeErr)
	}
	system, err := os.ReadFile(fromSystem)
	if err != nil {
		t.Fatal(err)
	}
	restored, err := nativeLibraryExchangeDecompress(system)
	if err != nil {
		t.Fatalf("the core could not read the system xz stream: %v", err)
	}
	if string(restored) != string(payload) {
		t.Fatal("restored bytes differ from the original payload")
	}
}

func TestNativeLibraryExchangeXZIsSmallerThanJSON(t *testing.T) {
	dramas := make([]nativeLibraryExchangeDrama, 0, 400)
	for index := 0; index < 400; index += 1 {
		dramas = append(dramas, nativeLibraryExchangeDrama{ID: "hongguo:" + strings.Repeat("9", 6) + string(rune('a'+index%26)), Source: "hongguo", Title: "重复标题样本", Description: strings.Repeat("这是一段用于验证压缩率的重复说明。", 4)})
	}
	payload, err := json.Marshal(nativeLibraryExchange{Kind: nativeLibraryExchangeKind, Version: nativeLibraryExchangeVersion, Count: len(dramas), Dramas: dramas})
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		t.Fatal(err)
	}
	if len(compressed)*2 >= len(payload) {
		t.Fatalf("xz should be far smaller than json: %d vs %d", len(compressed), len(payload))
	}
}

func TestNativeLibraryExchangeCompressPrefersHighestPreset(t *testing.T) {
	document := nativeLibraryExchange{}
	document.App, document.Kind, document.Version, document.Count = "guoguojuku", nativeLibraryExchangeKind, nativeLibraryExchangeVersion, 300
	for index := 0; index < 300; index++ {
		document.Dramas = append(document.Dramas, nativeLibraryExchangeDrama{
			ID:          "hongguo:" + strconv.Itoa(index),
			Source:      sourceHongguo,
			Title:       "都市逆袭第" + strconv.Itoa(index) + "部",
			Description: "这是一部都市逆袭题材的短剧，讲述主角在遭遇背叛之后逆风翻盘的故事。",
			Category:    "都市",
		})
	}
	payload, err := json.Marshal(document)
	if err != nil {
		t.Fatal(err)
	}
	preferred, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		t.Fatalf("compress failed: %v", err)
	}
	pure, err := nativeLibraryExchangeCompressPure(payload)
	if err != nil {
		t.Fatal(err)
	}
	if !nativeLibraryExchangeIsXZ(preferred) || !nativeLibraryExchangeIsXZ(pure) {
		t.Fatal("both encoders must emit an xz stream")
	}
	if restored, err := nativeLibraryExchangeDecompress(preferred); err != nil || !bytes.Equal(restored, payload) {
		t.Fatalf("preferred encoder round trip failed: %v", err)
	}
	if nativeLibraryExchangeXZBinary() != "" && len(preferred) >= len(pure) {
		t.Fatalf("preferred encoder must not be larger than the fallback: %d >= %d", len(preferred), len(pure))
	}

	binaries, path := nativeLibraryExchangeXZBinaries, os.Getenv("PATH")
	nativeLibraryExchangeXZBinaries = nil
	t.Setenv("PATH", filepath.Join(t.TempDir(), "empty"))
	t.Cleanup(func() { nativeLibraryExchangeXZBinaries = binaries })
	if nativeLibraryExchangeXZBinary() != "" {
		t.Fatal("expected no external xz to be discoverable")
	}
	fallback, err := nativeLibraryExchangeCompress(payload)
	if err != nil {
		t.Fatalf("fallback compress failed: %v", err)
	}
	if restored, err := nativeLibraryExchangeDecompress(fallback); err != nil || !bytes.Equal(restored, payload) {
		t.Fatalf("fallback round trip failed: %v", err)
	}
	t.Setenv("PATH", path)
}
