# 历史检查与平台状态记录

0.2.79+85 按用户“打包一下最新app，安装给我手机”完成全站源 ARM64 Release 构建与真机覆盖安装，源码为 0.2.79 的未发布改动（榜单空数据、黄果入口风格、原生核心并发兜底），本轮未再改业务代码。

- 构建：`python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`，Go 核心以 `allSources=true` 重新编译（`libduanju_core.so` 由上轮的 `2bc9ad76…` 变为 `6551b129a509ee2b93421d3e3a10527bb755b0ae575179263c920312c4caea93`，因为榜单解析与并发 `recover` 改动落在原生核心），`flutter pub get --enforce-lockfile`、Flutter Release 与 `package_release.py` 通过，产出 `dist/android/zhenguojian-0.2.79+2085-arm64-v8a.apk`（31,711,716 字节）。Gradle `assembleRelease` 用时 428.4 秒，仅出现既有 KGP 与 SDK XML 版本警告。
- 包检查：`aapt2 dump badging` 得到包名 `com.duanju.duanju_app`、应用名「真果鉴」、versionName `0.2.79`、versionCode `4085`、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify --print-certs` 证书 SHA-256 `dafec6763f52df367b8b211ed0f0073f2a3ae7061173df4ebdc68996c56a7670`，与历史包同签名；`zipfile.testzip()` 无 CRC 错误；APK 内 `lib/arm64-v8a/libduanju_core.so` 与 `libduanju_core.build.json` 的 SHA-256 相同（`6551b129…`）且记录 `allSources=true`；必需原生库 `libduanju_core.so` / `libflutter.so` / `libapp.so` / `libmpv.so` / `libffmpegkit.so` 均在包内；包内 `libapp.so` 检出本轮新增的 `rankingBoards` 与既有 `sourceForID`、`ScreenAwake`、`duanjuPaged` 字符串，确认榜单授权映射修复已进包；APK SHA-256 为 `ce8877bf0fab95a9a980475533dffc919db3aa7a23f38746b8de20967e4a3c0c`。
- 安装：设备 vivo V2453A（`10CF6H1D2L0009S`，Android 15，arm64-v8a），安装前为 `0.2.78` / versionCode `4084`；`adb install -r` 返回 `Success`（Streamed Install，覆盖升级、未卸载），安装后 `versionName 0.2.79` / `versionCode 4085` / `lastUpdateTime 2026-10-01 17:50:06`，`firstInstallTime` 保持 2026-09-24 02:08:22，确认数据保留；设备内 `base.apk` 的 SHA-256 与分发包一致（`ce8877bf…`）。启动后 `pidof` 非空、`topResumedActivity` 为 `.MainActivity`，`adb logcat` 内 `FATAL EXCEPTION` 计数为 0，新原生核心能正常加载。
- 证据：`build/packages-0279/` 下的 `release-all-sources-arm64.log`、`apk-verification.json`、`install.log`、`device-installation.json`、`logcat-launch.txt`。
- 边界：只构建并安装 Android 全站源 ARM64 包，未构建 Windows / iOS / TV 包；未执行静态分析、自动化测试和真实站源播放回归，41 个榜单入口是否全部出数据、黄果三入口点击不退出、短剧站源分类收录与剧库 XZ 导入导出均待集中验证，安装成功不等于功能验收通过。

0.2.78+84 按用户“打包一下最新app，安装给我手机”完成全站源 ARM64 Release 构建与真机覆盖安装，源码为此前两条未发布改动（手机音量键导致暂停、短剧站源收录深度），本轮未再改业务代码。

- 构建：`python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`，Go 核心以 `allSources=true` 重新编译（`libduanju_core.so` 由上轮的 `6eb650c1…` 变为 `2bc9ad766d8ab3a9043da97f2592c6267446afb9306064f84a664f3fd60cf595`，因为收录深度改动落在原生核心），`flutter pub get --enforce-lockfile`、Flutter Release 与 `package_release.py` 通过，产出 `dist/android/zhenguojian-0.2.78+2084-arm64-v8a.apk`（31,710,124 字节）。Gradle `assembleRelease` 用时 362.4 秒，仅出现既有 KGP 与 SDK XML 版本警告。构建前把 `pubspec.yaml` 由 `0.2.77+2083` 递增为 `0.2.78+2084`。
- 包检查：`aapt2 dump badging` 得到包名 `com.duanju.duanju_app`、应用名「真果鉴」、versionName `0.2.78`、versionCode `4084`、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify --print-certs` 通过 APK Signature Scheme v2，证书 SHA-256 `dafec6763f52df367b8b211ed0f0073f2a3ae7061173df4ebdc68996c56a7670`，与历史包同签名；`zipfile.testzip()` 无 CRC 错误；APK 内 `lib/arm64-v8a/libduanju_core.so`、`jniLibs` 库文件与 `libduanju_core.build.json` 三者 SHA-256 相同（`2bc9ad76…`）且记录 `allSources=true`；必需原生库 `libduanju_core.so` / `libflutter.so` / `libapp.so` / `libmpv.so` / `libffmpegkit.so` 均在包内；包内 `libapp.so` 含 `ScreenAwake` 与 `duanjuPaged` 字符串，确认常亮修复与站源分页补齐都在包内；APK SHA-256 为 `972c8360327e6f64202e2b12bf7b756df019d763f4cb44ada0e116bca0a9691a`。
- 安装：设备 vivo V2453A（`10CF6H1D2L0009S`，Android 15，arm64-v8a），安装前为 `0.2.77` / versionCode `4083`；`adb install -r` 返回 `Success`（Streamed Install，覆盖升级、未卸载），安装后 `versionName 0.2.78` / `versionCode 4084` / `lastUpdateTime 2026-10-01 16:06:48`，`firstInstallTime` 保持 2026-09-24 02:08:22，确认数据保留；设备内 `base.apk` 的 SHA-256 与分发包一致。`adb shell am start -n com.duanju.duanju_app/.MainActivity` 后进程 `pidof` 非空、`topResumedActivity` 为 `.MainActivity`，`adb logcat` 800 行内 `FATAL EXCEPTION` 计数为 0，说明新原生核心能正常加载、未复现 0.2.61 的启动即崩。
- 证据：`build/packages-0278/` 下的 `release-all-sources-arm64.log`、`apk-verification.json`、`install.log`、`device-installation.json`。
- 边界：只构建并安装 Android 全站源 ARM64 包，未构建 Windows / iOS / TV 包；未执行静态分析、自动化测试和真实站源播放回归，音量键不暂停、短剧站源分类收录（猫果 / 饭果 / 河果 / 星果 / 牛果等）、剧库 XZ 导入导出均待集中验证，安装成功不等于功能验收通过。

0.2.77+83 按用户“打包一下最新app，安装给我手机”完成全站源 ARM64 Release 构建与真机覆盖安装，本轮不改源码。

- 构建：`python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`，Go 核心重新以 `allSources=true` 编译（`libduanju_core.so` 由上轮的 `67706618…` 变为 `6eb650c1e9ed92004a992307b1eec646813a8f7b8dcf297bff5ebd5a8cc25c2b`，因为 0.2.75～0.2.77 的剧库 XZ 导入导出改动落在原生核心），Flutter Release 与 `package_release.py` 通过，产出 `dist/android/zhenguojian-0.2.77+2083-arm64-v8a.apk`（31,667,340 字节）。Gradle `assembleRelease` 用时 264.6 秒，仅出现既有 KGP 与 SDK XML 版本警告。
- 包检查：`aapt2 dump badging` 得到包名 `com.duanju.duanju_app`、应用名「真果鉴」、versionName `0.2.77`、versionCode `4083`、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify --print-certs` 通过 APK Signature Scheme v2，证书 SHA-256 `dafec6763f52df367b8b211ed0f0073f2a3ae7061173df4ebdc68996c56a7670`，与历史包同签名；`zipfile.testzip()` 无 CRC 错误；包内 `lib/arm64-v8a/libduanju_core.so`、`jniLibs` 库文件与 `libduanju_core.build.json` 三者 SHA-256 相同且记录 `allSources=true`；包内 `libapp.so` 含 `ScreenAwake` 与 wakelock 字符串。
- 安装：设备 vivo V2453A（`10CF6H1D2L0009S`，Android 15，arm64-v8a），安装前为 `0.2.73` / versionCode `4079`；`adb install -r` 返回 `Success`，安装后 `versionName 0.2.77` / `versionCode 4083` / `lastUpdateTime 2026-10-01 09:38:08`，`firstInstallTime` 保持 2026-09-24 02:08:22，确认覆盖升级且未清除数据。`adb shell am start -n com.duanju.duanju_app/.MainActivity` 后进程 `pidof` 非空、`topResumedActivity` 为 `.MainActivity`，`adb logcat` 400 行内无 `FATAL EXCEPTION`，说明新原生核心能正常加载、未复现 0.2.61 的启动即崩。
- 证据：`build/packages-0277/` 下的 `release-all-sources-arm64.log`、`apk-verification.json`、`device-installation.json`。
- 边界：只构建并安装 Android 全站源 ARM64 包，未构建 Windows / iOS / TV 包；未执行静态分析、自动化测试和真实站源播放回归，播放、弹幕、下载、剧库导入导出（0.2.77 新增）均待集中验证，安装成功不等于功能验收通过。

0.2.74+80 定位并修复“少数用户播放约 40 秒后息屏”，只改动 Dart 侧与依赖声明，未触碰 Go 核心、原生工程和站源链路。

- 根因：media_kit_video 只在自身 `Video` 组件的 `initState` / `dispose` 里通过 `WakelockPlus` 申请和释放屏幕常亮（`media_kit_video-2.0.1/lib/src/video/video_texture.dart`），而 Android 生产路径在 `lib/player_screen.dart` 里 `_surfaceOutput` 为真时既不创建 `VideoController` 也不挂载 `Video`，改用 `lib/android_video_surface.dart` 的 `PlatformViewLink` 加 Kotlin `VideoSurfaceHost` 的裸 `SurfaceView` 直出。项目里此前没有任何一处直接调用 `WakelockPlus`，`android/app/src/main/AndroidManifest.xml` 的 `WAKE_LOCK` 权限只管 CPU 唤醒，`MainActivity` 没有 `FLAG_KEEP_SCREEN_ON`，`VideoSurfaceHost.kt` 的 `SurfaceView` 也没有 `keepScreenOn`。因此播放期间是否熄屏完全取决于系统「自动锁定」时间与厂商全屏视频启发式。
- 现象对应：锁屏时间设为 2 分钟以上、勾选“充电时屏幕不休眠”，或单集短且用户频繁点选集 / 拖进度的设备无感；锁屏 15 / 30 / 60 秒的设备在最后一次触摸后熄灭，先变暗再熄屏，与反馈中的“40 秒左右”一致。Android TV 没有锁屏超时，Windows 纹理路径由 media_kit_video 兜住，所以反馈集中在部分 Android 手机。
- 反证：原生 Surface 创建失败时 `_fallbackToTextureOutput` 会创建 `VideoController` 并挂载 `Video` 组件，那条路反而带常亮；覆盖与需求正好相反，与反馈零散的现象一致。
- 修复：新增 `lib/screen_awake.dart`，以静态引用计数统一持有常亮状态，避免多个播放页先后释放时误关；平台调用失败只记录日志，不抛给播放链路。`lib/player_screen.dart` 在 `_syncPlayback` 与 `_applyLifecycleVisibility` 中按 `!_closed && _foreground && _playIntent && _error == null && _player.state.playing` 同步开关，`dispose` 兜底释放，因此暂停、缓冲出错误、切后台、退出播放页和息屏后手动锁屏都会释放常亮（缓冲中仍保持，与 Android Media3 的 `KEEP_SCREEN_ON` 语义一致）。纹理路径的 `Video` 传入 `wakelock: false`，由本项目状态机单独决定，避免 media_kit_video 的全局开关与本项目开关互相关闭。
- 依赖：`pubspec.yaml` 增加 `wakelock_plus: ^1.8.0` 并递增版本到 `0.2.74+2080`；该包此前已作为 media_kit_video 的传递依赖锁定在 1.8.0，本次只把 `pubspec.lock` 的 `dependency` 改为 `direct main`，版本与 sha256 未变，构建时的 `flutter pub get --enforce-lockfile` 不需要重新解析。Android / iOS 由原生插件在 Activity 窗口上增删 `FLAG_KEEP_SCREEN_ON`，Windows / macOS / Linux 走 Dart 插件（Windows 为 `SetThreadExecutionState`），`.dart_tool/flutter_build/dart_plugin_registrant.dart` 中三端注册已由既有依赖生成，Windows 侧不需要改 `generated_plugin_registrant.cc`。
- 工具链与前检查：Flutter SDK 位于 `~/Library/Caches/duanju-build/flutter`（`flutter` / `dart` 不在默认 PATH，构建前显式加入）。`dart format --output=none --set-exit-if-changed lib/screen_awake.dart lib/player_screen.dart` 返回 0 变化；`dart analyze lib/screen_awake.dart lib/player_screen.dart` 输出 8 条 info，全部是 `curly_braces_in_flow_control_structures` 与 `prefer_interpolation_to_compose_strings` 的既有 lint，无 error、无 warning，新增代码未产生新问题；`flutter pub get --enforce-lockfile` 通过且 `pubspec.lock` 零变化，确认手工调整的 `dependency: "direct main"` 与 `pubspec.yaml` 一致。
- 打包：按用户“打包app”的要求执行 `python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`，Go 核心复用未改动的 `libduanju_core.so`，Flutter Release 构建通过，产出 `dist/android/zhenguojian-0.2.74+2080-arm64-v8a.apk`（31,560,628 字节，versionName `0.2.74`，versionCode `4080`，SHA-256 见“安装包与平台状态”）。已独立复核：`aapt dump badging` 得到包名 `com.duanju.duanju_app`、应用名「真果鉴」、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify --print-certs` 通过 APK Signature Scheme v2，证书 SHA-256 `dafec6763f52df367b8b211ed0f0073f2a3ae7061173df4ebdc68996c56a7670`（沿用本机 Android Debug 签名，与历史包一致，可覆盖升级）；`zipfile.testzip()` 无 CRC 错误；包内 `lib/arm64-v8a/libduanju_core.so`、`jniLibs` 中本次库文件与 `libduanju_core.build.json` 三者 SHA-256 同为 `67706618f7528328f4f9e1a9ed94cfff2913a8c7e9c855a127008ac11a8933eb`，`allSources=true`；并从包内 `libapp.so` 检出 `ScreenAwake` 与 wakelock 字符串，确认本次修复确实编译进该安装包而不只是落在源码里。原始记录见 `build/packages-0274/`（构建日志与 `apk-verification.json`）。
- 边界：只构建 Android 全站源 ARM64 Release 包，未构建 Windows / iOS / TV 包；构建时 `adb devices` 无设备连接，未安装、未启动、未做真机播放回归与自动化测试。待集中验证：30 秒锁屏设备上连续播放不熄屏、暂停 / 出错 / 切后台 / 画中画 / 退出播放页后常亮确实释放、Windows 桌面端屏幕保持，以及息屏后回前台仍需手动点播放的旧行为是否依旧存在。安装到设备后在播放中可用 `adb shell dumpsys window | grep -i KeepScreenOn` 取证。

0.2.73+79 定位红果部分剧集无法播放的根因，只调整 Go 核心 `native/core/app_stream.go` 中本机播放代理的扩展名嗅探逻辑，未改动 Dart 侧。

- 复现：用真实红果 App 取流链路抽样《我都元婴期了，你跟我说开学第二季》（剧 ID `7690059679510055960`，911 集）的 25 集，逐集记录上游文件大小与本机代理返回码。修复前 4 MB 及以下的 8 集返回 200 / 206，超过 4 MB 的 17 集在无 Range 与 `Range: bytes=0-` 两种请求下均返回 502「读取媒体失败，请重试」。
- 根因：无扩展名上游路径会先执行 `io.ReadAll(io.LimitReader(response.Body, 4<<20+1))`，把响应读满 4 MB 就按读取失败处理并跳到下一条线路，因此所有大于 4 MB 的媒体都被拒绝。红果 App 媒体地址形如 `/video/tos/cn/.../<id>/?a=8662&...`，`path.Ext` 为空，必然进入该分支；`nativePlaybackChoices` 给出的 10 条线路共用同一上游形态，`PlaybackRecovery` 又在 3 次额度内优先耗尽备用线路，最终呈现为错误页的「暂时无法播放 / 自动恢复未成功」。
- 修复：嗅探上限改为 256 KB；读到上限且前缀不是 `#EXTM3U` 时判为媒体流，写出已缓冲前缀后用 `io.Copy` 继续转发剩余响应，上游的 `Content-Length`、`Content-Range`、`Accept-Ranges`、`ETag`、`Last-Modified` 照常转发；前缀确为 `#EXTM3U` 的响应才在 4 MB 上限内读完并交给播放列表改写。该分支同时是启动提速：以前任何无扩展名媒体都要先下载 4 MB 才向播放器返回首字节，现在最多 256 KB。
- 复验：修复后同样 25 集抽样 24 集可播放；19.0 MB 与 7.9 MB 的集在无 Range 下返回 200、在 `Range: bytes=0-` 下返回 206 且 `Content-Range` 覆盖完整文件；剩余 1 集为上游单次瞬时失败，对同一地址单独重试 3 次均返回 200。
- 测试：新增 `native/core/app_stream_test.go`，覆盖大文件无扩展名媒体完整转发、`Range` 请求透传和无扩展名播放列表改写，均通过；`go test -run 'Native|Media|Playback|Download|Preload|Stream'` 通过。`TestNativeCatalogMetadataSaveExcludesInFlightCursor`、`app_catalog_persistence_test.go` 与 `provider_rankings_test.go` 的失败在未改动的 `../guoapp` 镜像上同样存在，属既有问题，本轮未处理。
- 附带观察：红果 App 详情接口 `/novel/player/video_detail/v1/` 对 19 集、60 集、475 集和 911 集的剧目都返回 HTTP 200、正文 0 字节，红果详情实际一直走网页 `/detail?series_id=`；本轮没有改动这条链路，但大剧集的章节完整性依赖网页入口。
- 遗留：`PlaybackRecovery` 在可用线路不少于 3 条时会把 3 次自动恢复额度全部用在备用线路上，`refresh`（重新解析播放地址）在额度内到不了，已过期的签名地址只能靠手动重试恢复；`test/playback_recovery_test.dart` 把该顺序写成了预期，本轮未改，待确认后再调整。
- 打包：按用户“app 打包出来”的要求执行 `python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`，Go 核心与 Flutter Release 构建通过，产出 `dist/android/zhenguojian-0.2.73+2079-arm64-v8a.apk`（31,560,424 字节，versionName `0.2.73`，versionCode `4079`，SHA-256 见“安装包与平台状态”）。已独立复核：`aapt dump badging` 得到包名 `com.duanju.duanju_app`、应用名「真果鉴」、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify` 通过 APK Signature Scheme v2，签名证书与历史包一致（Android Debug），可覆盖升级；`zipfile.testzip()` 无 CRC 错误；包内 `lib/arm64-v8a/libduanju_core.so` 的 SHA-256 与 `jniLibs` 中本次新编译的库及 `libduanju_core.build.json` 记录三者相同。构建时 `adb devices` 无设备连接，本轮未安装、未启动、未做真机播放回归。
- 边界：只完成源码修复、设备外的 Go 定向验证与 Android 全站源 ARM64 Release 打包；未构建 Windows / iOS 包，未安装真机，未执行 Dart 静态分析或真机播放回归；红果在线播放需要在集中验证时复验。

0.2.65+71 调整非全屏控制层为无操作 3 秒后淡出，补齐缓冲 / 长按结束后的计时恢复、菜单与拖动期间的隐藏保护，并将轻点画面统一为切换控制层。完成 Dart 格式整理与源码收尾同步后，按用户追加的“打包 app，安装给我”要求执行 `python3 scripts/build_android.py --all-sources --abi arm64-v8a --cn-mirrors`：Go 核心与 Flutter Release 构建通过，APK 的应用名称、版本、ARM64 架构、CRC、对齐、v2 签名及包内全站源核心哈希核对通过，沿用本机 Android Debug 签名。安装至 vivo V2453A（`10CF6H1D2L0009S`）时 ADB 返回 `Success`，采用覆盖升级，未卸载或清除数据；设备随后断开 USB，未完成安装后版本 / 哈希复核，未启动应用。证据位于 `build/packages-0265/` 的构建日志、`apk-verification.json`、`install.log` 与 `device-installation.json`。未执行静态分析、自动化测试或播放回归；后续集中验证应覆盖首次播放、手动切集、超过 3 秒的缓冲后恢复、长按松开、进度拖动、菜单关闭、轻点呼出及自动连播，手机和 Windows 行为均待验收。

0.2.64+70 仅调整卡片三点菜单的背景、图标阴影、交互反馈和点击区域，完成 Dart 格式整理与源码收尾同步。按用户要求暂停测试，本轮未执行静态分析、自动化测试、平台构建或设备复验，属于开发快照。

0.2.63+69 追加用户指定图标、加载提示和播放按钮透明度调整，延续原生核心打包修复。

- 源码检查：`test/player_screen_test.dart` 与 `test/search_cache_test.dart` 共 18 项通过，覆盖浅色主题下准备提示可读、无橙色转圈、准备与缓冲期间不叠放播放按钮、就绪后恢复操作、入场布局和推荐缓存；测试夹具的缓冲事件调整后相关用例复验通过。7 个相关 Dart 文件分析无 error / warning，保留播放器中 8 条既有 info，更新后的设备用例单独分析通过。
- 打包保护：`scripts/test_app_build.py` 6 项、`scripts/test_sync_source.py` 4 项通过；缺失构建记录、站源开关不一致、核心被替换与 APK 内旧核心均会被拒绝。Go 已使用 `-s -w` 裁剪符号，Android 对该核心保留原始字节，避免打包过程再次修改后无法核对哈希。
- 原生启动：此前 0.2.62 的 `integration_test/startup_test.dart` 已在 vivo V2453A 通过，调用真实 `app.main`、`AppBootstrap` 和 `NativeRepository.initialize`，确认 `allSources=true` 且首页出现；使用独立调试包并禁用远程图片。日志与界面证据保存在 `build/device-test/startup-0262/`，与最终 0.2.63 包内 Go 核心的 SHA-256 相同。
- 图标与安装包：原始 PNG 与用户提供的 2880×2880 图片字节一致；Android 五档、Windows 七档 ICO、iOS 不透明 PNG 及两个电视横幅规格正确。0.2.63 全站源 ARM64 Release 构建、ZIP 完整性、版本、包内核心哈希与五档图标像素检查通过；安装包信息见“安装包与平台状态”。Windows、Android TV 和 iOS 本轮仅更新资源，没有平台运行验收。
- 正式包安装与启动：0.2.63 已通过 `adb install -r` 覆盖安装到 vivo V2453A，保留原应用数据；设备上的 APK SHA-256 与分发包完全一致，版本为 `0.2.63 / 2069`。暂时关闭 Wi-Fi 与移动数据后启动，UI XML 确认出现首页导航，未再出现站源版本不一致或原生核心加载失败；应用日志未发现崩溃。检查只读取界面结构，没有截取或处理缓存海报；结束后 Wi-Fi、移动数据与飞行模式恢复到原状态。证据保存在 `build/device-test/startup-0263/`。
- 收尾边界：按用户“测试可以了，需求收尾”的要求停止后续验证。更新后的 `integration_test/player_entry_test.dart` 调试包已构建，但没有安装运行；0.2.63 新加载提示、半透明按钮与桌面图标未再做设备视觉复验，不能将此前 0.2.61 的合成播放记录当作这些新增外观的验收结论。临时合成视频服务和 ADB 端口转发已关闭，独立调试包已清理；其他平台与未覆盖行为继续保留开发快照状态。

0.2.61+67 针对 2026-09-28 的手机反馈完成以下定向验证；整体验证仍暂停，以下结果仅覆盖本轮修复。

- 源码检查：本轮 8 个 Dart 文件的 `dart analyze` 无 error / warning，保留播放器中 8 条既有 info；`test/search_cache_test.dart` 与 `test/player_screen_test.dart` 共 17 项通过，补入搜索键盘开合场景后相关布局用例复验通过。使用 `DISABLE_REMOTE_IMAGES=true` 和合成剧目，覆盖 20 分钟缓存、相同数量结果的资料 / 有效期更新、空结果缓存、过期保留旧内容、重复请求合并、静默流式追加、反复切 Tab 与重新进入、视频尺寸变化和键盘高度变化。
- 手机：ADB 连接 vivo V2453A（设备标识 `10CF6H1D2L0009S`），安装独立验证包 `com.duanju.duanju_app.debug`，应用数据与原安装分开。`integration_test/player_entry_test.dart` 通过：两次从 981 像素高的展开键盘进入播放，视频区域始终为 `Rect(0, 0, 411.4, 485.1)`，Tab 顶部始终为 `497.62 dp`；原生 SurfaceFlinger 视频区域为 `[0 0 1079 1273]`，顶部边缘取样为纯黑。合成视频两次播放均有推进且画面像素发生变化；推荐加载横线数量为 0，三轮 Tab 往返及退出重进后搜索总次数仍为 1。
- 本地证据：`build/device-test/player-entry/fixed/` 保存 `entry.mp4`、入场逐帧图、两次播放与推荐截图、UI XML、窗口 / SurfaceFlinger 状态和 `logcat.txt`；修改前的定向记录在 `baseline/`。验证过程没有请求站源图片。旧验证脚本在第二次打开时仅等待 3 秒便检查播放进度，基线该断言失败；本轮按实际就绪状态在有界时间内等待，并同时核对画面像素，不将基线当成通过记录。
- 发布构建：已生成 Android ARM64 全站源 APK `dist/android/zhenguojian-0.2.61+67-arm64-v8a.apk`，31,458,604 字节，包名 `com.duanju.duanju_app`，versionName `0.2.61`，versionCode `2067`，SHA-256 为 `e077b04c38660243a6e7b6d0ac94b794abf6197897acff1ad1c39dc5476b7772`。该 APK 曾安装到手机，但用户在真实启动时发现站源版本不一致；原因是该次直接运行 Flutter 构建时复用了默认红果版的旧原生核心。此 APK 判定为无效，已移出 `dist/android`，仅在 `build/device-test/player-entry/baseline/invalid-0.2.61+67.apk` 留作故障证据；上述合成播放检查不等于原生核心启动验证。本轮未执行 Windows、Android TV、iOS 构建 / 设备验收，也未恢复真实站源和全部功能回归。未覆盖部分仍为开发快照。

0.2.51+57 按电视端遥控反馈重做焦点模型，只改电视分支。新增遥控列表 / 遥控行 / 统一遥控条目 / 遥控选项列表对话框与页面初始焦点兜底；`RemoteGrid` 增加上下左右越界出口和“回到当前焦点项”，首页、榜单、下载、设置、推荐与详情选集网格按区域串联；下载页电视模式增加遥控工具行与关键字搜索弹窗，榜单与下载合集的操作改写为遥控选项对话框。

本轮已恢复工具链并完成第一轮编译验证：Flutter SDK 3.47.4（Dart 3.13.3）重新安装到 `~/Library/Caches/duanju-build/flutter`，安装包对官方 releases 清单做 SHA-256 校验通过。`dart analyze lib` 输出 92 条问题，全部为既有 info 级 lint，无 error 与 warning。编译期发现并修复 2 个真实错误：`home_screen.dart` 与 `rankings_screen.dart` 把 `focusNode` 传给了 `PopupMenuButton`，而该类没有该参数；改为多选模式下分类栏按上聚焦标题栏“取消”按钮，其余情况交回默认方向遍历，标题栏“更多”仍按原生焦点参与遍历。同时清理 `settings_screen.dart` 中因新增 `app_layout.dart` 导入而变多余的 `app_build.dart` 导入。

已生成红果版 Android release 包：`dist/android/hongguojian-0.2.51+57-arm64-v8a.apk`，31,209,723 字节，SHA-256 为 `409106f06d2ede0caf780026340376f75219ac566a6a3fc49647c7ee2cb0a6d5`；`dist/android/hongguojian-0.2.51+57-armeabi-v7a.apk`，39,730,355 字节，SHA-256 为 `f2316398f27008364137e2ebc0cc13cb4c2ac6aca60e65fd8a508c3871bb7962`。包名 `com.duanju.duanju_app`，versionName `0.2.51`，versionCode `2057` / `1057`，targetSdk 36，沿用本机 Android Debug 签名，已核对版本信息、ABI 与内嵌原生库。

`flutter test test/television_test.dart` 结果为 4 通过 2 失败，失败是同一用例在两个屏幕尺寸下的 `start-play` 断言：0.2.32 起首页卡片普通点击已改为无中间页直达播放，`_openDrama` 仅在 `download: true` 时进入详情页，该断言仍按旧行为期待详情页按钮，属既有失败，与本次焦点改造无关。未安装设备、未执行实机遥控验收，电视端方向键与确认键行为仍需在 Android TV 实机确认。

0.2.44+50 更新野果默认入口为 `https://analyze.buxefaex.cc/`，并把 `https://ygdj7.com/` 作为线路发现页；新旧 `buxefaex` / `fzchosdi` 线路、`delta.ygrwdsgt.cc` 和 `yeguodj.com` 均归一为野果站源。0.2.47 起旧域名仅用于识别已有缓存和数据，不再作为运行时接口回退地址。0.2.48 将首页和推荐卡片普通点击改为无中间页直达播放：详情仍先读取，但不再 push “正在进入播放”页面，读取成功后直接打开播放器。剧果保留 `/play/<episode>` 返回的 CloudFront 三枚签名 Cookie，并让播放列表、分片、预加载和下载继续使用同来源凭证；帝果 vplayer 签名请求失败直接返回错误，不再静默交给播放器一个未签名地址。新增 Go 定向测试覆盖新域名识别、野果 50 页 POST 更新、目录页大小、三站源榜单、剧果签名 Cookie 和帝果签名错误传播；仅运行源码定向测试，未打包、未安装设备、未请求真实媒体或做真实播放验收。

0.2.42+48 继续按播放页与首页反馈收紧：追剧确认固定在播放页“简介”内容区，不作为 Tab；播放页下方 Tab 保持“选集 / 简介 / 下载”，下载选择器嵌入下载 Tab；播放器底部工具按钮改为少量靠右连续成组，超过阈值再拆成左右两组，避免平均分散在整行；首页在已有内容时不再于分类下显示异常提醒，目录滚动接近底部自动续页并保留“加载更多”兜底。已执行 `dart analyze lib/home_screen.dart lib/player_controls.dart lib/player_screen.dart lib/download_picker.dart lib/television_controls.dart test/player_screen_test.dart test/downloads_test.dart test/widget_test.dart test/danmaku_widget_test.dart`，仅剩既有 info 级 lint；`flutter analyze ...` 仍在中文路径下触发 analysis server LSP JSON 解析异常，未作为有效检查。已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`test/downloads_test.dart --plain-name "mobile player moves download and follow into tabs"`、`test/widget_test.dart --plain-name "fresh disk catalog skips the network and resumes pagination"`、`test/widget_test.dart --plain-name "stale disk catalog remains usable when refresh fails"`、`test/danmaku_widget_test.dart` 均通过；新增 `compact player tools stay clustered instead of evenly spread` 覆盖播放器底部按钮不再平均分散。完整 `test/downloads_test.dart` 仍有既有下载合集默认折叠 / 遥控导航断言未通过，未作为本轮验收结论。已执行默认红果版 `flutter build apk --debug --no-pub`，生成 `build/app/outputs/flutter-apk/app-debug.apk`，大小 162 MB，版本 `0.2.42+48`，SHA-256 为 `eeaea66b8df3fd4658e29b33d947f92ae41bc5551d7aed8adc72f7f8a8325205`。本轮未生成 Release APK、未安装设备、未执行真实播放视觉验收。

0.2.40+46 针对用户反馈的 iOS IPA 播放闪退做源码排查与兜底：应用能启动、浏览和进入详情，说明 Flutter 壳与原生 Go 核心大概率已加载；崩溃发生在点击任意剧集进入播放后，最可疑点是 iOS 播放页创建 media_kit_video 的 libmpv 纹理输出。上游 iOS 插件在 `mpv_render_context_create` 失败时调用 `exit(1)`，不会回到 Flutter 错误页，因此外观看起来是点播放后 App 直接退出。已将 iOS `VideoController` 配置为禁用硬件纹理加速，改走软件纹理兜底；Android 和 Windows 保持原路径。本轮按要求未生成 IPA、未执行真机播放复验，需用 Xcode 设备日志确认是否仍有 `MPVHelpers`、`mpv_render_context_create` 或 `Mpv.framework` 相关崩溃。

0.2.39+45 继续按播放页 UI/UX 反馈优化：播放页下方 Tab 改为“选集 / 简介 / 下载”，原“相关”不再放在播放页；红果同系列相关推荐仍保留在详情页，避免播放页出现经常为空的内容区。追剧入口从播放器覆盖层移到简介内容区；下载入口从播放器覆盖层移到播放页下载 Tab，下载选择器支持嵌入式紧凑布局并复用连续选集网格。播放器覆盖层移除移动端音量、下载和追剧按钮，桌面端保留音量，电视端不再显示推送按钮；弹幕按钮改为圆形“弹”字样。首页目录滚动接近底部自动加载下一页，底部“加载更多”保留为兜底入口。已执行 `dart analyze lib/home_screen.dart lib/player_controls.dart lib/player_screen.dart lib/download_picker.dart test/player_screen_test.dart test/downloads_test.dart test/danmaku_widget_test.dart`，仅剩既有 info 级 lint；待执行播放器、下载、首页分页定向测试和 Android Debug 构建。未生成 Release APK，真实设备视觉验收仍待集中执行。

0.2.38+44 继续修正播放器实机截图反馈：非全屏点击画中画后，整个播放页在 PiP requested / active 状态下只渲染视频 Pane，不再把选集 / 简介 / 相关 Tab 内容缩进系统小窗；`sourceRectHint` 改为在纯视频布局重绘后一帧再计算，和实际进入小窗的画面一致。全屏播放器顶部显式使用 `viewPadding.top + 16` 且至少 40dp 避让，避免返回 / 标题与状态栏网络、电量、时间重叠；底部显式使用 `viewPadding.bottom + 24` 且至少 64dp，把进度条和底部工具整体抬高，避开虚拟导航栏；PiP 请求和激活期间连保存进度告警也不再绘制。已执行 `dart analyze lib/player_controls.dart lib/player_screen.dart test/player_screen_test.dart`，仅剩既有 info 级 lint；已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/danmaku_widget_test.dart`；已执行 `./gradlew :app:assembleDebug` 成功。未生成 Release APK，真实 Android 播放小窗和全屏控件截图仍待集中设备验收。

0.2.37+43 优化 Android 画中画小窗：参考 Android PiP 和 Apple 小窗播放最佳实践，进入画中画后 Flutter 自绘播放器控件、弹幕覆盖、进度条、标题、加载和错误覆盖层均不再绘制，小窗只保留视频画面，播放 / 暂停 / 返回应用 / 关闭等交互交给系统 PiP 控件；进入前先隐藏覆盖层并等待一帧，再调用原生 `enterPictureInPictureMode`，同时传入视频区域 `sourceRectHint`，避免系统截取到带按钮的旧界面并优化转场动画。已新增 `test/player_screen_test.dart` 用例覆盖“画中画隐藏 App 覆盖控制层”。已执行 `dart analyze lib/player_controls.dart lib/player_screen.dart test/player_screen_test.dart`，仅剩既有 info 级 lint；已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/danmaku_widget_test.dart`；已执行 `./gradlew :app:assembleDebug` 成功生成 162 MB Debug APK，并通过安装辅助脚本安装到 Android 15 / API 35 真机 V2453A，启动到首页且 logcat 未见 App 崩溃。自动点播进入真实 PiP 时设备会话被 vivo 系统 single-cleaner 强停，未完成真实小窗截图验收；Release APK 也未在本轮生成。

0.2.36+42 微调播放器布局：移除底部中间工具区的横向滚动容器，保留左侧倍速 / 清晰度、中间推送 / 下载 / 追剧、右侧音量 / 画中画 / 全屏或选集的稳定分布；红果弹幕按钮移到播放器右侧中段独立悬浮，避开中央播放按钮和底部进度条，弹幕开关和失败重试回调保持不变。已执行 `dart analyze lib/player_controls.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/danmaku_widget_test.dart`。本轮未打包 APK、未安装设备，真实站源和平台行为仍待集中验证。

0.2.35+41 修正播放器按钮布局继续反馈：按 Material / Android 触控目标规范和 Apple 自定义视频播放控件建议，把倍速、清晰度、推送、下载、追剧、弹幕、音量、画中画等入口统一为 36 高视觉工具按钮，外层保留更大的可点区域；移动和桌面底部控制层改为左侧倍速 / 清晰度、中间内容动作、右侧音量 / 画中画 / 全屏或选集分组，宽度不足时中间动作区可横向容纳，避免所有按钮堆到中间。音量不再打开居中大弹窗，改为右下角小型竖向滑动面板，支持拖动和一键静音 / 恢复。已执行 `dart analyze lib/player_controls.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/danmaku_widget_test.dart`。`flutter analyze lib/player_controls.dart lib/player_screen.dart lib/lan_controller.dart` 在中文项目路径下再次触发 analysis server LSP JSON 解析异常，未得到有效报告；本轮未打包 APK、未安装设备，真实站源和平台行为仍待集中验证。

0.2.34+40 修复移动播放器继续反馈：选集 Tab 的连续网格顶部恢复区间选择器，可快速定位每 50 集开头；播放器底部改为工具按钮一行、时间与进度条同一行，移动端去掉底部重复旋转按钮，顶部返回 / 旋转按钮增加安全间距，音量按钮在手机播放器始终显示；局域网投屏按钮尺寸与其他播放器工具按钮统一。红果相关推荐新增本地剧库系列候选缓存，详情和播放页相关不再只依赖追剧 / 历史 / 新季提醒，支持聚宝仙盆这类多季剧展示同系列。已执行 `dart analyze lib/player_controls.dart lib/episode_browser.dart lib/local_store.dart lib/local_snapshot.dart lib/player_screen.dart lib/detail_screen.dart lib/lan_screen.dart test/follow_state_test.dart test/library_features_widget_test.dart test/player_screen_test.dart test/danmaku_widget_test.dart`，仅剩既有 info 级 lint；已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/follow_state_test.dart`、`test/library_features_widget_test.dart --plain-name "detail related series can use refreshed catalog candidates"`、`test/player_screen_test.dart`、`test/danmaku_widget_test.dart`、`test/downloads_test.dart --plain-name "detail download picker handles VIP, quality and added=2"`。本轮未打包 APK、未安装设备，真实站源和平台行为仍待集中验证。

0.2.33+39 继续优化播放器控制层与移动播放页：手机和桌面播放器覆盖层移除“播放设置”按钮，倍速、清晰度、推送、下载、追剧、弹幕、音量、画中画和旋转直接可用；自动连播和下一集预加载默认始终开启；上一集 / 播放暂停 / 下一集只保留居中一组，非全屏不再在播放器层重复显示选集按钮。移动端 Tab 增大点击区域，选集改为带边框的连续滚动紧凑网格，简介保留封面，相关列表显示红果同系列封面；选集按钮区分焦点和当前集，避免看起来多集同时激活。播放器缓冲进度改用进度条二级轨道，不再显示“已缓冲至”文字；下载选集页提供“取消全选”。已执行 `dart analyze lib/player_controls.dart lib/player_screen.dart lib/episode_browser.dart lib/remote_widgets.dart lib/download_picker.dart lib/playback_buffer.dart test/danmaku_widget_test.dart test/player_screen_test.dart test/downloads_test.dart`，仅剩既有 info 级 lint；已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart`、`test/danmaku_widget_test.dart`、`test/downloads_test.dart --plain-name "detail download picker handles VIP, quality and added=2"` 和 `added=0`。本轮未打包 APK、未安装设备，真实站源和平台行为仍待集中验证。

0.2.32+38 优化播放入口与移动播放页：普通点剧先读取详情后直接进入播放器，下载入口仍走详情页；手机播放器下方用“选集 / 简介 / 相关”Tab 承接原详情内容，红果同系列剧在相关 Tab 中打开；手机播放页移除额外顶部标题栏，返回和旋转放入视频控制层，倍速、清晰度、推送、上一集、下一集、选集和设置不再在视频下方重复出现；移动端选集改为 30 集一组紧凑方格，分组、当前集和跳转合并在同一行；首页移除分类下方的更新状态提示，保留刷新任务；详情页选集默认折叠且只高亮当前播放集；下载选集页显式提供“全选 / 清空 / 仅非 VIP”与已选数量。已执行 `dart analyze lib/player_screen.dart lib/player_controls.dart lib/episode_browser.dart lib/remote_widgets.dart lib/player_menu.dart test/player_screen_test.dart test/theme_test.dart`，仅剩既有 info 级 lint；已执行 `flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/player_screen_test.dart` 和 `test/theme_test.dart --plain-name "player shell follows light theme while video controls stay dark"`。此前本轮还执行过 `test/library_features_widget.dart` 和下载选择定向测试。未打包 APK、未安装设备，真实站源和平台行为仍待集中验证；完整 `test/downloads_test.dart` 仍有既有下载合集默认折叠导致的旧断言失败，未作为本轮通过项。

0.2.31+37 仅针对红果接入系列剧与本机新季提醒：详情选集区显示本地已知同系列季；追剧刷新发现后续季时显示“新季”提醒并进入“有更新”筛选；点入新季或标记更新已读后清除提醒，不自动加入追剧。系统级通知因 Android 13+ 需要运行时通知权限且打扰等级更高，暂不接入。已执行 `flutter test test/follow_state_test.dart test/library_features_widget_test.dart`，覆盖红果季号识别、无后缀第一季、非红果忽略、提醒持久化 / 已读、追剧筛选和详情切换。`dart analyze` 可运行，仅报告既有 info 级 lint；`flutter analyze` 在中文项目路径下触发 analysis server LSP JSON 解析异常，未得到有效静态分析报告。本轮未打包 APK、未安装设备，真实站源和平台行为仍待集中验证。

0.2.30+36 优化全屏自动连播的控制栏显示：自动切换到下一集时不把播放开始事件当作用户操作，控制栏保持隐藏；首次进入、手动切集、暂停、缓冲和用户点击 / 键盘 / 遥控操作仍可显示控制栏。手机、Windows 与 Android TV 共用该状态边界。随后生成全站源版 Android ARM64 Release 包 `dist/android/zhenguojian-0.2.30+36-arm64-v8a.apk`，SHA-256 为 `272f344a2d7976811c214180414965ed316a3bcdbd4b7335ec9ce8220c436f15`；已完成 ARM64 原生库、版本信息和 APK v2 签名检查，未安装到设备，播放行为仍待实机验收。

0.2.29+35 完成电视自动识别与横屏方向管理源码：启动前识别设备，返回前台重新查询，失败保留既有结果；应用统一处理电视模式、手机全屏和播放器退出时的方向归还，Android Activity 对电视模式拦截竖屏请求并在恢复时重申横屏。随后生成全站源版 Android ARM64 Release 包 `dist/android/zhenguojian-0.2.29+35-arm64-v8a.apk`，SHA-256 为 `ef8f971afc6119b8573c1adc2b64d736d27c9b400304bec75926dadd24a35ffc`；包签名为本机 Android Debug 签名，已完成 ARM64 原生库、版本信息和 APK v2 签名检查，未安装到设备，Android 手机、电视 / 盒子及其它平台行为仍未完成本轮验收。

以下保留历史版本的实施与检查记录。

0.2.24+30 按移动端和电视端画质增强卡死反馈，将画质增强功能收窄为仅 Windows 桌面端可见和可运行；Android 手机、Android TV 与 iOS 均不再显示画质增强、画面类型和原画对比入口，也不初始化 mpv 增强后端，已保存偏好保留给 Windows 使用。本轮已生成全站源版 Android arm64 release 包 `dist/android/zhenguojian-0.2.24+30-arm64-v8a.apk`，SHA-256 为 `c0a7d3c4469042d9a0cfcf0d6b01ed865db5e7580d552b7e3a27b1f582dfe9b7`；未安装到设备，未执行完整回归。

以下保留历史版本的实施与检查记录。

0.2.23+29 修正全屏播放器控制层级：顶部只保留返回与标题，中央只保留大播放控制，底部统一承载播放、进度、时间、选集、倍速 / 画质、推送、原画对比、设置、画中画和全屏切换；普通小视频控制层也不再把设置、画中画和原画对比堆到顶部。全屏播放器的设置与选集弹窗、电视播放器的设置与分集弹窗均强制使用播放器暗色主题，不受浅色应用主题影响。随后使用 Flutter SDK 完成全站源版 Android arm64 release 构建，产物为 `dist/android/zhenguojian-0.2.23+29-arm64-v8a.apk`，SHA-256 为 `81c673ecac5526dd46a517ced32bbf8d2b298125f80b7eaca7fa330075958778`；未安装到设备，未执行完整回归。

以下保留历史版本的实施与检查记录。

0.2.22+28 修正手机竖屏播放页结构：视频下方只保留紧凑播放面板，当前集、上一集 / 下一集、倍速、画质、推送与“选集”入口可直接操作；完整选集仍通过折叠入口打开原选集面板，不再常驻铺满页面。本轮仅做源码实现、格式整理、窄范围静态检查与收尾同步；未生成新 APK，未做设备安装复验、平台构建或完整回归。

以下保留历史版本的实施与检查记录。

0.2.21+27 修正播放器页面外壳跟随浅色 / 深色主题，视频画布与覆盖控制保持深色；画质增强关闭时隐藏画面类型和原画对比，开启后展开配置；原画对比不再等待渲染确认成功才可用；Android 自动档先保流畅使用高质量缩放，清晰优先才尝试更高负载增强。本轮通过 ADB 确认当前前台 App 为 `com.duanju.duanju_app/.MainActivity`、进程 `29688`，并按 `logcat --pid=29688` 定位当前 App 日志；当时该进程没有可读历史日志行。清理本项目可再生成的 `build` / `.dart_tool` 缓存后，窄范围 `dart analyze lib/player_screen.dart lib/player_menu.dart lib/video_enhancement_settings.dart lib/video_enhancement.dart lib/video_enhancement_policy.dart test/theme_test.dart` 完成，仅剩既有 info 级 lint；新增播放器主题用例 `flutter test test/theme_test.dart --plain-name "player shell follows light theme while video controls stay dark"` 通过。整份 `test/theme_test.dart` 仍有既有导航断言 `settings changes open routes without losing the active tab` 未通过，未作为本轮验收结论；本轮没有平台构建、设备复验、新 APK、Windows 完整包或 iOS 应用。30 项已实现待验证仍保持未勾选。

以下保留历史版本的实施与检查记录。

0.2.20+26 接入 Android 手机 / 平板播放器画中画源码：Activity 声明 PiP 能力，播放器查询系统支持后显示入口，并在进入画中画时保持播放生命周期；未执行静态分析、自动化、平台构建或设备复验，也没有该轮新 APK、Windows 完整包或 iOS 应用。0.2.19+25 统一该站源的用户可见名称为剧果，保留内部 `huangju` 标识以兼容已有数据。启动诊断只读取了设备已有崩溃日志，启动修复、榜单、画质增强和画中画尚未执行平台验收；帝果公开播放路径检查另行记录，仍不实现绕过 VIP / 试看限制。

以下保留历史版本的实施与检查记录。

0.2.17+23 接入野果与帝果，包含分类、目录与搜索分页、详情、真实分集、媒体解析和来源请求头；新增站源纳入既有权限、下载、资料回写及局域网互联范围。野果的接口配置在设备内动态取得；帝果兼容用户参考脚本的同站媒体路径规则。

本轮为实现需要读取了两站的 HTML、JavaScript 和 JSON 接口文本，完成变更 Dart / Go 源码格式整理与源码镜像同步；未执行新增源码、静态分析、构建、自动化测试、回归、设备 / 模拟器、播放、下载或双端验证，未请求站源图片、播放列表、密钥或媒体文件。该轮记录的两份 Android APK 为 0.2.15+21，后来已有用户使用 0.2.17+23 并报告启动问题。该轮 28 项已实现待验证的状态保持未勾选，Android 手机、Windows、Android TV 与 iOS 的实际运行结论等待集中验证。

以下保留历史版本的实施与检查记录。

0.2.16+22 接入剧果访客授权、动态分类、热门 / 最新、目录与搜索分页、详情和签名 Cookie 媒体链路；榜单移至顶部标题栏“排序与筛选”后面。该轮仅整理源码格式并同步，没有运行静态分析、构建、自动化、设备、真实站源或双端验证。

0.2.15+21 根据首页截图调整多选与导航入口：移除首页全选，展开后显示文字“清空 / 取消”，底部固定已选数量及“下一步”；仅红果分类在“全部”后提供内嵌推荐，当时将“榜单”放在分类栏右侧，位置已在 0.2.16 调整。

变更 Dart / Go 源码完成格式整理，两版 Android ARM64 Release 构建与包检查通过。版本码为 2021，签名与 0.2.10 / 0.2.14 一致；每份 17 个 ARM64 原生库采用 ZIP DEFLATE，安装时解压、CRC、ZIP 对齐、应用名称 / 包名、对应原生核心及两份 APK 的 SHA256 均已核对。构建与包检查记录保存在 `build/packages-0215/`。

0.2.15 未执行静态分析、自动化测试、回归、设备 / 模拟器或真实局域网验证，也未请求站源图片；该版布局、切换推荐与多选操作的实际运行效果待用户安装确认。

0.2.14+20 根据用户提供的“正在打开红果鉴”截图修复启动导航。0.2.13 为接收播放加入固定导航 key 后，初始化前后改变了 `MaterialApp` 的父节点层级，保留下来的根路由继续引用旧应用状态。现在初始化前后都使用同一层 `AnimatedBuilder`，保持应用与导航状态连续，使首页能够接替初始化页，并保留推送接收导航。定位依据为截图与源码，尚未在设备上确认启动效果。

打包同时补齐 `lan_screen.dart` 对 `LocalStoreSync` 扩展的导入，解决 Release 编译失败。0.2.14 执行结果：

| 检查 | 结果与范围 |
| --- | --- |
| 源码格式 | 变更 Dart / Go 文件完成格式整理 |
| Android Release 构建 | 默认红果版、`--all-sources` 全站源版均通过，ARM64，版本 0.2.14+20 |
| 安装与升级信息 | 应用名称、包名、版本码 2020、最低 Android 8.0 和非调试标记正确；签名有效，且与 0.2.10 / 0.2.13 一致 |
| 包完整性 | 每份 17 个原生库均为 ARM64 ELF、ZIP DEFLATE；包 CRC、ZIP 对齐和安装时解压配置通过 |
| 编译配置与校验值 | 两版各自的原生核心与构建记录一致，Dart 与原生二进制分别区分两版；两份 APK 与 `SHA256SUMS.txt` 一致 |

构建和包检查记录在 `build/packages-0214/`，包括两版 `release-*-arm64.log`、`apk-*-verification.log` 和 `apk-verification.json`。0.2.14 没有运行静态分析、自动化测试、回归、设备 / 模拟器或真实局域网验证，没有请求站源图片；包检查不代表启动、同步、推送或其他运行行为已经验收。

0.2.13+19 接入 P3-2 / P3-3：局域网自动连接、追剧与对应续播进度的增量同步 / 手动覆盖、冲突处理和播放推送。功能实施阶段暂停验证，当时只执行：

- `flutter pub get`：取得 `nsd 5.0.1` 及平台依赖，更新 `pubspec.lock`。
- Dart / Go 源码格式整理。
- 收尾同步、创建本地 `v0.2.13-unverified` 快照及源码镜像一致性确认。

该功能实施阶段没有运行 Dart 静态分析、Go 编译、自动化测试、回归、完整平台构建、真实局域网通信或设备 / 模拟器操作，也没有请求站源图片。后续按用户要求打包，并在收到启动问题反馈后交付上述 0.2.14 修复包。Android / Windows / TV / iOS 的设备发现、权限、并发同步、取消与回执恢复、推送定位和控件布局仍待集中验证。

以下历史版本的检查结果不能作为后续新增功能的验证结论。

0.2.12+18 完成界面调整及 P2-4 / P2-5 / P2-6 / P2-7 / P2-9 / P3-1 的源码接入，当时的检查结果：

| 检查 | 结果与范围 |
| --- | --- |
| 源码格式 | Dart `lib` 与变更 Go 文件完成格式整理 |
| Dart 静态分析 | `dart analyze --fatal-infos lib` 通过，无问题 |
| 本机 Go 核心编译 | 在 `native` 执行 `go build ./core` 通过 |
| Android ARM64 核心编译 | `GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build ./core` 通过 |
| Windows x64 核心编译 | `GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build ./core` 通过 |

0.2.12 没有执行自动化测试、回归、真实媒体播放或设备 / 模拟器验证，也没有构建新 APK、Windows 完整包或 iOS 应用。上述 Go 检查只覆盖核心源码编译，不代表平台桥接、随包媒体库、界面或合并输出已验收。当时黄果 AI 仅做入口与目录的只读连接诊断，结果超时；未请求站源图片。

以下 0.2.11 及更早版本的检查和安装包记录，也不作为后续新增功能的验证结论。

0.2.11+17 完成 P2-3 红果弹幕的源码接入，Go / Dart 格式与 Dart 静态检查通过。默认红果版和全站源版各通过 **6 项 Go 定向测试（含竞态检测）及 18 项 Flutter 定向测试**。原生检查使用内存文字响应，覆盖原始时间戳、分集身份、异常时间窗口、缓存去重、取消和播放会话隔离；Flutter 使用合成数据，覆盖分页与有界缓存、失败重试、迟到结果、暂停 / 缓冲 / 倍速 / 跳转、连续动画、开关持久化与备份兼容、用户切换、窄屏大字及 TV 设置。

0.2.11 只运行以下弹幕测试，Go 命令在 `native` 目录执行，Flutter 命令在项目根目录执行：

~~~sh
go test -race ./core -run '^(TestHongguoDanmaku|TestNativeDanmaku)' -count=1 -timeout=60s
go test -race ./core -ldflags='-X duanjuapp/native/core.buildAllSources=true' -run '^(TestHongguoDanmaku|TestNativeDanmaku)' -count=1 -timeout=60s
flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/danmaku_test.dart test/danmaku_widget_test.dart
flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=ALL_SOURCES=true test/danmaku_test.dart test/danmaku_widget_test.dart
~~~

Flutter 记录在 `build/danmaku-0211/flutter-default.log` 与 `flutter-all-sources.log`。0.2.11 未进行回归、真实站源弹幕请求、设备或模拟器验证，也未请求站源图片；Android、Windows 与 TV 的实际播放效果待平台验收。0.2.11 当时未单独打包，弹幕实现已包含在新版 APK 中。

0.2.10+16 完成 P2-1 与 P2-2 的源码接入，Dart 格式与静态检查通过。默认红果版和全站源版各通过 **26 项新增功能针对性测试**，使用合成文字与分集数据，禁用远程图片；覆盖追剧记录与实际播放进度分离、已读基准、备份兼容与失败保留、用户隔离、共享更新任务与缓存续页、批量下载重试 / 停止，以及 360×640 和 1100×720 的大字布局。

0.2.10 功能实施阶段执行了以下三份测试文件：

~~~sh
flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true test/follow_state_test.dart test/library_workflow_test.dart test/library_features_widget_test.dart
flutter test --no-pub --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=ALL_SOURCES=true test/follow_state_test.dart test/library_workflow_test.dart test/library_features_widget_test.dart
~~~

0.2.10 打包时移除了 `app_cover_metadata.go` 中遗留的 `parseHuangguoSortDetail` 重复定义，统一复用详情元数据解析实现；Go 格式整理和 `TestNativeCoverMetadataRejectsOtherDramaAndKeepsCurrentHost` 定向测试通过，测试只解析合成元数据，不请求图片。

0.2.10 的红果鉴 / 真果鉴两份 ARM64 Release 构建和安装包检查已通过。每份 APK 的 17 个原生库均为 ARM64 ELF 并使用 ZIP DEFLATE 压缩，清单启用安装时解压；签名与 0.2.8 一致，包 CRC、ZIP 对齐、应用名称、包名、版本 `0.2.10`、ARM64 分包版本码 `2016` 和对应原生核心均正确。两份包及 `SHA256SUMS.txt` 已校验，构建与检查记录在 `build/packages-0210/`，对应 `release-default-arm64.log`、`release-all-sources-arm64.log`、`apk-default-verification.log` 和 `apk-all-sources-verification.log`。

0.2.10 打包没有执行全量 Flutter / Go 回归、设备或模拟器测试，也没有请求站源图片。构建成功不代表新增功能已经完成平台验收。

0.2.9 接入的播放器交互、分页 / 保存 / 本地用户恢复、红果推荐、资料模型、排序、全部站源和完整搜索等，仍按各待办行保留原有验收状态。0.2.10 / 0.2.11 的针对性测试不代表这些功能已完成集中验证；Android、Windows 原生行为与新增 TV 操作仍待平台验收。

黄果 AI 的实际密钥连接与播放仍未恢复。0.2.13 已接入原清单中可独立实施的功能以及新增 P3-2 / P3-3；AI 待可通的入口后继续处理连接与播放问题，集中验证继续按用户安排执行。

0.2.8 已通过 Dart 格式与静态检查，默认红果版和全站源版各通过 5 项站源界面定向检查。使用合成数据覆盖历史详情默认收起、两种主动检测展开、手动收起后跨请求返回 / 轮询 / 检测完成保持状态、完成后再次展开与收起，以及窄屏大字的失败诊断。记录在 `build/sources-028/`。

0.2.7 已通过 Dart 格式与静态检查、相关 Go 定向检查（含竞态检测），另验证默认红果版的权限、分类和合成 HEIC。Flutter 定向检查默认版通过 14 项、全站源版通过 15 项；覆盖紧凑布局、大字体、展开搜索、黄果聚合 / 分类去重、独立分页与失败页重试、过期响应隔离、真实榜单名次、VIP 筛选及海报尺寸。合成 HEIC 还经过真实原生准备接口与开发机 FFmpeg 转成 JPEG，验证旋转后尺寸由 64×96 变为 96×64；此项不等同于 Android 原生插件实机验收。检查记录在 `build/sources-027/`。

0.2.7 / 0.2.8 按当时要求没有运行整套回归、启动设备或模拟器，也未请求任何站源图片；各平台实际显示与播放效果仍需安装验证。0.2.6 的待办审查与边界问题证据保留在上文，以下保留历史版本验证结论。

0.2.6 已完成红果鉴 / 真果鉴两份 ARM64 Release 构建。每份 APK 的 17 个原生库均采用 ZIP DEFLATE 压缩，最终清单已启用安装时解压；包 CRC、ZIP 对齐、应用名称、版本、签名和内置核心对比均通过。两份签名与 0.2.5 一致。全站源包由 67.4 MB 缩小到 30.1 MB，减少约 55.3%；第三方原生库解压后的内容与 0.2.5 一致。记录在 `build/sources-026/`。

0.2.5 已通过 Dart 格式与静态检查、5 项定向 Go 检查（含竞态检测）和 1 项分类界面检查，覆盖分类分页 / 缓存隔离、旧 API 单剧 404、封面地址与合成解码、密钥 EOF 后备用 DNS 连接，以及分组切换和过期分类响应隔离。按用户要求不运行整套回归，记录在 `build/sources-025/`。

0.2.5 线上文本检查取得黄果视频和旧版的实际分类；旧版独立更新成功，返回 100 部剧，全部封面 URL 已避免误用视频 CDN。仅核对地址元数据，封面解码只用合成图片，未请求站源图片。记录在 `build/sources-025/live-fixes.log`。

黄果 AI 截图同剧《神瞳觉醒 第一季》的目录、21 集分集与 M3U8 均正常，但密钥请求仍在 TLS 握手时断开；换用备用公网地址及浏览器兼容连接后仍失败，没有证明媒体可播放。诊断记录在 `build/sources-025/key-probe.log`、`asset-probe.log` 和 `alias-probe.log`。此前 0.2.4 黄果视频“母女日常”的目录、分集、播放列表、密钥和媒体连接抽样通过，记录在 `build/sources-024/live-huangguo.log`；该结果不能代表黄果 AI 或 Android 实机播放。

0.2.8 已生成两份 ARM64 Release 安装包，可覆盖升级。每份的 17 个原生库均使用 ZIP DEFLATE，清单启用安装时解压；签名与 0.2.7 一致，包 CRC、ZIP 对齐、应用名称、版本和内置核心对比均通过，记录在 `build/sources-028/apk-verification.log` 与 `apk-default-verification.log`：

| 版本 | 安装包 | 大小 |
| --- | --- | --- |
| 红果鉴，仅红果 | `dist/android/hongguojian-0.2.8+14-arm64-v8a.apk` | 30.2 MB |
| 真果鉴，全部站源 | `dist/android/zhenguojian-0.2.8+14-arm64-v8a.apk` | 30.2 MB |

构建日志为 `build/sources-028/release-default-arm64.log` 和 `release-arm64.log`，包校验记录为同目录的 `apk-default-verification.log` 和 `apk-verification.log`。其他架构的构建开关和脚本保留，0.2.8 未生成其他架构安装包。

按用户要求，由用户自行安装体验，不执行手机 / 电视实机测试或启动模拟器。Windows 完整包需 Windows / Actions；本机缺少 iPhoneOS SDK，iOS 尚未完成 Xcode 构建，也没有已签名 IPA。本轮不运行远程 Actions，不请求或处理站源图片。

此前的合成 CENC 换封装、少数分集合并转码和 Emby 成品独立解码检查已通过。平台状态单独记录，不将待验收项目混入上面的功能移植顺序。
