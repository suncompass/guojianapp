package core

import (
	"testing"
	"time"
)

// 大剧库保存不能占着引擎锁：编码与 fsync 最大要处理 32 MiB，
// 期间目录、播放等其他请求都必须照常拿得到锁。
func TestNativeCatalogSaveLeavesEngineLockFree(t *testing.T) {
	engine, err := newNativeEngine(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(engine.downloads.close)

	encoding := make(chan struct{})
	release := make(chan struct{})
	catalogSaveBeforeEncode = func() {
		close(encoding)
		<-release
	}
	t.Cleanup(func() { catalogSaveBeforeEncode = nil })

	// 任何一条失败路径都要放行保存协程，否则它会一直挂在钩子里。
	released := false
	releaseSave := func() {
		if !released {
			released = true
			close(release)
		}
	}
	defer releaseSave()

	source := nativeCatalogKey(sourceYaguo, "feed-lock")
	saved := make(chan struct{})
	var saveErr error
	go func() {
		defer close(saved)
		saveErr = engine.saveCatalogCache(source, &nativeCatalogResult{
			Page:  1,
			Items: []nativeDrama{{ID: source + ":1", Title: "样本", Source: sourceYaguo}},
		})
	}()

	select {
	case <-encoding:
	case <-time.After(10 * time.Second):
		t.Fatal("保存没有进入编码阶段")
	}

	// 此刻保存已经交出引擎锁：另一个请求应当立刻拿到锁，而不是等写盘结束。
	idle := make(chan struct{})
	go func() {
		defer close(idle)
		engine.nativeCached(sourceYaguo)
	}()
	select {
	case <-idle:
	case <-time.After(5 * time.Second):
		t.Fatal("编码期间引擎锁仍被保存占用")
	}

	releaseSave()
	<-saved
	if saveErr != nil {
		t.Fatalf("保存失败：%v", saveErr)
	}
}
