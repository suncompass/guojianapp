# 红果鉴

Flutter 多端独立短剧应用，原名“短剧库 APP”。站源请求、解析、播放、下载和合并在设备端完成，不依赖旧项目或自建服务。当前源码版本：**0.3.8+2119（开发快照）**。

唯一构建版本为红果鉴：红果，以及芽果、猫果、饭果、观果、河果、星果、花果、牛果、伍果、米果、爽果共 11 个绿色短剧站源。站源可见性只在 `native/core/app_build.go` 的 `nativeGreenSources` 白名单一处判定，Dart 侧 `SourceSite.values` 与该名单逐条对应；退役站源只在解析层保留常量，旧缓存与备份仍按 `retiredIds` 识别。

未完成集中验证和平台验收的功能一律标为开发快照，不代表已经可用。

## 版本记录

### 0.3.8：每次构建独立发布 tag

- 根因：分支推送与手动运行一律发布到滚动 tag `latest`，并用 PATCH 强行把 `refs/tags/latest` 移到最新提交，导致所有批次的安装包都累积在同一个 Release。
- 推分支或在分支上手动运行改为新建 `build-{runId}-{attempt}` tag（如 `build-123456789-1`），重跑也生成新 tag；显式 tag 仍发布到对应版本。
- 发布脚本不再移动任何已有 tag，只发布本 tag 自己的 Release；历史 Release（含旧 `latest`、`0.1`、`0.2`）及其附件一律保留。
- release job 的并发组与发布 tag 对齐，不同批次不再串在同一把锁上。
- 按 CI 输出的格式化补丁把 `lib/playback_preloader.dart` 的 `if` 条件合并回一行，修复 `dart format --set-exit-if-changed` 失败导致后续 `dart analyze` 与测试被跳过的连锁问题。
- 测试体里直接调用 `PlatformPlayer` 的 `playingController` / `bufferController` 会触发 4 条 `invalid_use_of_protected_member` warning（warning 致命，`dart analyze` 退出码 2），改为在 `ScriptedPlayer` 子类内封装 `emitDecoderPause` / `emitPlaybackStarted` / `emitStalePause` / `emitBuffer`，测试逻辑不变。
- 修复自动连播收尾回归：过渡标记在新一集真正推进前不会清除，最后一集片尾的暂停被误判成「等待自动连播」而不再取消长按；已装媒体是最后一集且已播完时立即恢复常速，兑现 0.3.7 的「最后一集结束仍取消临时倍速」。
- 修复发布脚本的首建失败：列表接口对刚创建的草稿有延迟，建完立刻回读写不到草稿导致 release job 失败；改为直接使用创建响应里的 Release 对象，草稿链路全程按 id 上传附件与公开发布。

### 0.3.7：长按倍速跨集保持与提示背景淡化

- 修复按住画面或键盘右键时自动进入下一集丢失临时倍速：自动连播不再取消长按，片尾与媒体打开阶段的暂停通知不会误判成松手，新媒体打开后重新应用本次长按的实际倍率。
- 下一集解析、打开期间或起播后松手，均恢复普通倍率，不跳进度、不误暂停；主动暂停、手动选集、切集失败、最后一集结束仍取消临时倍速。
- 长按提示的淡灰背景不透明度由约 22% 降至约 14%，圆角与文字样式不变。
- 新增触摸 / 键盘在解析、打开、起播三个阶段松手，以及暂停、手动切集、切集失败、末集结束的边界断言。

### 0.3.6：加宽全屏选集面板

- 横屏选集抽屉由约 25% 屏宽调整为约 45%，通常控制在 320–520 逻辑像素；844 宽手机横屏由 211 加宽到约 380，两位数集号由 2 列增加到 4 列。
- 仍是点击后贴右覆盖弹出，不恢复常驻侧栏、不压缩底层全屏视频；保留刘海 / 侧边系统栏与底部手势区避让。
- 补充五种横屏尺寸、安全区、当前集高亮、选集 / 关闭及视频区仍占满全屏的断言。

### 0.3.5：清晰视频标题与自定义长按倍速

- 全屏标题显式使用白色、16 号半粗字与暗色阴影，避免浅色主题下文字融进画面。
- 「倍速」菜单新增「长按倍速」设置：1.5 / 2 / 3 / 4 / 5 倍快捷档位，或输入 0.5–5 之间的小数。普通播放速度与长按速度分别持久化，旧设置默认沿用 2 倍；触摸长按与键盘长按右键共用该倍率。
- 画面顶部提示增加 25 圆角与淡灰背景，松手即消失；音量与错误提示不套用此背景。

### 0.3.3：手机横屏即全屏，选集改为贴右窄抽屉

- 根因：`_showFullscreen` 的自动全屏分支要求 `_aspectRatio >= 1`，竖屏短剧（9:16）在手机横屏时不满足，`_playbackLayout` 因此走并排侧栏分支渲染 `_episodePanel()`，右侧约 1/4 屏宽被选集占满；这也解释了此前「旋转快照」「弹窗竞态」修复为何不生效。
- 手机横屏一律全屏播放：去掉宽高比与自动全屏抑制两个条件，并排侧栏只保留给桌面 / 平板宽屏（`!_mobile && (宽 ≥ 840 或 宽 > 高 × 1.3)`）。
- 退出全屏的方向归还同步收紧：手机横屏退出全屏改为把设备转回竖屏。
- 选集弹窗横屏收成贴右窄抽屉，用 `constraints: BoxConstraints()` 覆盖 `Dialog` 默认 `minWidth: 280`；倍速 / 清晰度 / 播放设置保留原宽度。

### 0.3.2：弱化长按倍速提示，补全全屏黑边覆盖

- 长按提示改为画面顶部的「N 倍速」小字，字号 12、约 35% 白色不透明度、不带底色或阴影；松手直接清除并恢复原速。
- 手机进入全屏时先完成面板收起布局，再等待无面板帧后请求系统旋转；全屏视频区不由左右 SafeArea 留空，控制栏单独避让系统栏。
- `StableVideoViewport` 在原生视频上方显式绘制纯黑遮罩并裁剪视口，针对右侧黑边残留选集数字的情况补强覆盖。

### 0.3.1：移植纯绿站源与解析，站源收敛为 12 个绿色站源

- 对照纯绿源码把站源与解析移植到本仓库（排除直播与「在看」）：红果加芽果、猫果、饭果、观果、河果、星果、花果、牛果、伍果、米果、爽果。
- 新增米果（大米星球 · 网页目录）与爽果（短剧网 · 网页目录）；超果、皮果、网果、发果、黄豆、剧果、野果、帝果、黄果各入口与成人站源全部退役，只在原生解析层保留常量与分支。
- `native/core/provider_duanju_maccms.go` 补齐选集去重、分集归属两级筛选、占位地址剔除、`const source` 优先与标题清洗；`provider_duanju_dispatch.go` 改为按 `spec.Kind == "maccms"` 数据驱动分发。
- 红果搜索接入真分页；`app_runtime.go` 回填 `hasMore`，并修掉 `catalog_browser.dart` 里「`hasMore` 为真却不推进页码」导致「加载更多」原地打转的问题。
- 新增 `lib/network_exit.dart`：`_invokeNative` 在信封 `ok:false` 时对只读动作换出口重试，写入类动作不重复提交；Android 侧新增 `vpnActive` / `bindPhysicalNetwork`。
- 新增 `native/core/app_green_sources_test.go`，守住「白名单与注册表逐条一致」「名单外站源不可用」「每个站源三条分派链路已接通」与米果不分页 / 爽果分页。

### 0.3.0：只保留红果鉴单版本并删除「在看」榜单

- 「在看」整套实现（`feeds_screen.dart`、`recommendation_*`、`nostr_*`、`secret_store` 及测试）删除，底部导航回到「主页 / 追剧 / 历史 / 下载」，播放器不再上报观看进度。
- 真果鉴（全站源）变体下线，构建脚本不再有 `BuildVariant` 与 `--all-sources`；品牌资源与 Dart 常量统一为红果鉴。
- 旧站源移入 `retiredIds`（`isKnown` 仍为 `true`），避免升级后已有用户的历史、追剧与站源权限被判为无效配置。
- Release 附件名由 `{commit12}-{runId}-{attempt}` 改为 `{runId}-{attempt}`，不再暴露提交哈希。

### 0.2.99 – 0.2.87

| 版本 | 要点 |
| --- | --- |
| 0.2.99 | 超果完结判定由「分子=总集数」改为「分子=可播放、分母=页面标注集数」；首页预加载改为下一帧布局结束后判断并增加三项准入约束；电视端返回统一走 `_changeTab` |
| 0.2.98 | 接入第 11 个短剧站源超果（`shanekids.com`，服务端渲染 HTML 按页面语义解析）；短剧站源搜索入口改为 `searchDuanjuPage` |
| 0.2.97 | 合并源项目的首页懒加载预加载（`lib/catalog_prefetch.dart`）：停止滚动 320 ms 进入空闲后补页，单次空闲最多 3 轮，提前量小于 2 屏才补 |
| 0.2.96 | 手机播放页下方栏目可收起（头部常驻 48，面板占可用高度 .44），保留选集滚动位置、当前标签与下载勾选；修复 `create_draft` 建出草稿后按 tag 读回接口只返回已发布 Release 的缺陷 |
| 0.2.95 | 播放器生命周期收敛为五态 `PlaybackPhase { opening, ready, buffering, failed, closed }` 与显式迁移表，约 80 处读取点零改动 |
| 0.2.94 | 大剧库保存移出引擎锁：锁内取快照、锁外编码落盘，新增保存锁 `saveMu` 串行写盘；快照逐条复制元素避免数据竞争 |
| 0.2.93 | 修掉观果用例漏设 `providerHosts` 导致请求打到真实站点引发的随机红；`dart` 双变体测试均完整上报 |
| 0.2.92 | 复核 CI 并回退一处误改：普通 `test()` 文件加 mock 反而让全部用例在初始化阶段失败；`ALL_SOURCES` 变体补 `if: ${{ !cancelled() }}` |
| 0.2.91 | 首轮 CI 反馈：拆 job 后 Go 结果照常上报；修 `feeds_screen_test` 悬挂定时器、`secret_store_test` 预载与 4 条 analyzer info |
| 0.2.90 | 检查拆成 `scripts` / `dart` / `go` 三个独立 job；修复 `build_mirrors.py` 在 CRLF 锁文件上静默不改写；站源任务轮询离开前台即停 |
| 0.2.89 | 桥接调用在同一工作 isolate 内完成编码、原生调用与解码；错误按核心缺失 / 平台不支持 / 编码 / 协议分类；下载页按需轮询 |
| 0.2.88 | 推荐身份私钥改用系统安全存储（Android Keystore、Windows DPAPI），分两步迁移且解不开时不新建身份 |
| 0.2.87 | 「在看」生产接收入口先校验大小、类型、长度与时间窗，后台 isolate 核对事件 ID 与 BIP-340 签名；发布签名移到后台 isolate；新增 `scripts/publish_release.py` |

0.2.86 及更早版本的历史记录见下方「历史与平台验证记录」。

## 使用

| 功能 | 操作 |
| --- | --- |
| 浏览 | 标题栏依次提供排序与筛选、榜单图标、多选下载和展开搜索，窄屏常显榜单。分类独立一行，内容区左右滑动切类；支持默认、名称、自然季号、上线日期、热度、播放量排序及连载状态筛选，未知值置后。列表下滑接近底部自动加载下一页，底部「加载更多」兜底 |
| 搜索 | 红果合并官网与名称索引并补齐可识别的缺漏季，改走真分页入口；输入停顿 300 毫秒显示最多 10 条联想，正式名称查询用 50 条索引。11 个绿色短剧站源调用各自的在线搜索并继续加载（米果分类页不分页）；单独搜索这些站源不调用红果联想。部分失败保留有效结果，最近 20 次搜索按用户保存并可清空 |
| 推荐 | 仅红果站源分类栏在「全部」后显示「推荐」，可切换真人剧、漫剧、AI 剧并分别记住位置。其他站源与「全部站源」不显示此入口 |
| 详情 | 普通点剧直接进入播放，下载和兜底入口保留详情页。详情页浏览封面、资料、追剧状态与可展开简介，底部固定「立即播放 / 继续播放」和下载入口；选集默认折叠，每组 50 集，可切换范围、定位当前或输入集数跳转 |
| 追剧与历史 | 按想看 / 在看 / 已看 / 有更新筛选；红果已追剧发现新季后进入「有更新」。两者均可本地搜索；卡片菜单可设置状态、标记更新已读或删除单条历史。每用户独立保存，每 5 秒及退出播放时记录真实进度 |
| 卡片与批量下载 | 卡片「更多」提供收藏、状态和下载选集（电脑可右键、电视可用菜单键）。发现页长按卡片或点标题栏「多选下载」进入批量选择，一次最多 50 部 |
| 手机播放 | 画面上滑下一集、下滑上一集；长按 350 毫秒使用临时倍速（默认 2 倍），松开恢复，可在「倍速 → 长按倍速」调整。轻点切换控制层，双击或中央按钮播放 / 暂停；无操作时非全屏 3 秒、全屏 4 秒淡出，暂停、缓冲、拖动或菜单操作期间保留。视频下方为选集 / 简介 / 推荐 / 下载 Tab，推荐复用 20 分钟有效缓存 |
| 画中画 | Android 手机 / 平板播放器提供画中画入口；进入前先隐藏自绘控制层与弹幕并等待一帧，小窗只保留视频，转场使用视频区域 `sourceRectHint`。进入后保持播放与进度保存，退出恢复常规生命周期。Android TV、Windows 与 iOS 暂未接入 |
| 画质增强 | 仅 Windows 桌面端显示入口并运行增强链路，支持关闭 / 自动 / 省电增强 / 清晰优先，可点「原画对比」切换。Android 手机、Android TV 与 iOS 隐藏该功能且不初始化后端 |
| 弹幕 | 红果在线播放默认开启；播放器侧边圆形按钮可关闭、查看状态及失败重试。开关按本地用户保存并进入备份，本地播放不加载弹幕 |
| 横竖屏 | 电视模式统一保持横屏，竖屏视频按原比例居中；手机竖屏播放页无额外标题栏，视频下方紧贴 Tab 内容区；手机横屏一律全屏播放，选集为贴右覆盖抽屉。并排分栏只保留给桌面 / 平板宽屏 |
| Windows | 播放画面获焦时空格播放 / 暂停，左方向键后退 5 秒，右方向键轻按前进 5 秒、长按使用临时倍速，上下方向键调音量 5%，M 静音，F / F11 / Ctrl+F 全屏，Esc 退出全屏或返回 |
| 外观 | 「更多 → 设置与备份 → 外观主题」选择浅色、深色或跟随系统，默认跟随系统，配置备份包含主题 |
| 下载 | 播放页「下载」Tab 和详情页下载入口均可选择分集与画质；按剧分组搜索、筛选，标题栏进入多选 / 全选；支持批量暂停、继续、重试、删除及清理任务但保留视频。「更新本剧」补新增或缺失分集 |
| 更多 | 站源管理、用户管理、设置与备份、界面模式、关于；设置中提供下载偏好及管理员「网络与资源」 |

站源一览：

| 站源 | 浏览与播放 | 搜索 |
| --- | --- | --- |
| 红果 | 真人剧、漫剧、AI 剧及分集 | 联网搜索与官网搜索联想 |
| 芽果 | 星芽接口分类、目录、详情及分集，登录令牌缓存 | 站源在线搜索 |
| 猫果 | 七猫签名接口目录、详情及分集 | 站源在线搜索（签名串顺序为 `extend` → `read_preference` → `track_id` → 关键词 → 密钥，密钥位置错会返回验签失败） |
| 饭果 | 西饭搜索接口目录与详情，单页目录 | 站源在线搜索 |
| 观果 | 围观接口目录与分集；详情接口实测返回空数据 | 站源在线搜索 |
| 河果 | 河马网页 `__NEXT_DATA__` 目录、详情及分集 | `POST /seo/video/6007`，响应 `data.bookList`，带 `isMore` / `totalSize` 可翻页 |
| 星果 | 星星接口连载目录、详情及分集 | `GET /novel-api/basedata/book/searchBook`，关键词参数名为 `key`，响应 `data.datalist`，支持 `pageNum` 翻页 |
| 花果 | 网页分类、目录、详情及分集；详情多为单集全集 | 站源在线搜索 |
| 牛果 | 接口 AES 目录、详情及分集；密钥取自实际请求 URI 前 16 字节 | 站源在线搜索 |
| 伍果 | 网页分类、目录、详情及分集 | 站源在线搜索 |
| 米果 | 大米星球网页分类、目录、详情及分集，分类页不分页 | 站源在线搜索 |
| 爽果 | 短剧网网页分类、目录、详情及分集 | 站源在线搜索 |

网页族站源的搜索页卡片类名常与首页不同（部分为随机串），类名匹配失败时回退为按详情链接锚点收集卡片。站源可用性、清晰度和区域限制取决于源站及网络；应用不解除源站 VIP 或其他授权限制。受限用户需由管理员在用户管理中分配站源权限，已有用户不会自动获得。

### 缓存与播放恢复

- 目录条目及页码缓存 15 分钟；过期后先显示缓存再更新，失败保留原列表，手动刷新立即联网。红果总目录与各分类分别保存真实 offset、会话、设备标识及分页签名，续页按保存位置请求。已移除 6000 条和 500 页的静默截断；达到 32 MiB 保存上限或写入失败时保留内存内容并显示未保存。
- 正式搜索设 40 秒总时限，补漏季最多 32 次查询，前台在途请求最多 16 个；不使用网页 `totalCount` 虚构下一页。
- 海报在设备内处理并缓存，首页、详情、榜单和追剧共用；有效期 30 天，上限 256 MB / 2000 张，单张 20 MB。保留 AES / XOR 解码，HEIC 主图在本地提取后由随包媒体库转成 JPEG，兼容缓存另限 64 MB / 128 张。
- 正常播放与下载不转码、不降低清晰度；远程 MP4 与 HLS 统一接入设备内流服务处理请求头、密钥、预取缓存及应用代理，不经远程中转。
- 播放失败或前台连续 20 秒无进度时优先尝试备用地址：自动画质先试同画质备用地址及兼容编码再试较低画质，手选画质只切同画质线路；备用地址耗尽后最多重新解析一次，每轮最多自动恢复 3 次。

### 下一集预加载与缓冲反馈

前台正常播放至少 2 秒、缓冲余量至少 5 秒，且已进入本集后半段或最后 45 秒时低优先级预取下一集；不启动本地视频预取。解析时限 15 秒，预取最多 6 秒 / 4 MiB / 8 次请求，HLS 限前两段约 8 秒，MP4 只取开头；就绪计划最多保留 2 分钟，失败至少间隔 30 秒再试。自动连播与预加载默认始终开启，旧偏好中的关闭值被忽略。播放器缓冲进度在进度条二级轨道展示。

### 红果弹幕

仅显示通过当前分集 ID、源站状态和原始毫秒时间戳校验的弹幕文字，过滤重复与无效内容；普通评论不进入弹幕。暂停与缓冲时停止移动，倍速、跳转和切集按视频时间同步；关闭、切集、切换用户或离开播放器会清理旧内容并取消在途请求。弹幕使用独立低优先级请求、短超时与有限缓存。

### 追剧、更新提醒与历史

- 追剧可设为「想看 / 在看 / 已看」；开始实际观看后「想看」自动变为「在看」，最后一集播完后标为「已看」，发现更多分集时回到「在看」。
- 新集数量按已取得目录或详情中的集数增长计算，加追时记录已知集数，旧资料或临时变少的集数不会降低基准。
- 红果系列剧按标题末尾「第 N 季 / 第 N 部」识别，未带季号的同名剧可作为第一季参与匹配；已追剧发现后续季时显示「新季」提醒，点入或标记已读后清除，不自动加入追剧。
- 追剧与历史支持本地搜索剧名、简介和标签，不发起站源搜索。「继续观看」使用真实分集与进度，已看完的分集优先从后续可用集数开始。

### 用户与权限

「更多 → 用户管理」提供独立界面。初始用户为管理员，先设置至少 6 位管理员密码才能创建其他用户。管理员可勾选用户能访问的站源、设置「允许下载和本地媒体」及「启动时需要登录」。关闭后保留密码，仅在切换用户或手动锁定时验证；存在其他用户时不能取消管理员密码。

追剧与观看记录按用户隔离；下载文件在本机共享。备份可导出与恢复用户、密码校验信息、追剧、观看记录和偏好设置，不含视频、下载密钥或插件私有配置；密码使用随机盐与 PBKDF2-HMAC-SHA256 校验值。

**剧库导入导出**（`剧库-YYYY-MM-DD.xz` 标准 XZ 压缩包，上限 32 MB / 20 万条）不需要先登录，解锁页与设置页共用同一实现。文件只含剧库条目，不含观看记录、追剧清单、分页位置与配置备份。导入同时接受 `.xz` 与旧版 `.json`（按文件头识别），按剧集 ID 合并，只补全本机为空的字段，同一文件可重复导入；星果与饭果的 ID 约定已与网页版统一为 `基础 ID~base64url(载荷)`，旧格式在读取时自动改写。

### 下载、后台运行与空间

- 详情底部点击下载图标选择分集与画质；「设置与备份 → 下载偏好」按用户保存默认画质及是否包含 VIP，初始为自动高清、排除 VIP。选集每组 50 集，单次最多 500 集；VIP 集可能仅有试看，指定画质缺失时使用源站可用版本。
- 发现页支持多选批量下载，每次最多 50 部；预览先逐部读取分集，可单独保留失败剧为待重试。长剧自动分批加入，不截断超过 500 集的已选内容。
- 「下载」按剧分组，支持本地搜索、下载状态与连载状态筛选，可按整部或分集批量暂停、继续 / 重试、取消 / 删除。「清理任务，保留视频」只隐藏已完成任务，在「已保留视频」中仍可查看、恢复或本地播放。
- 「更新本剧」重新读取分集并更新资料，只添加新增、失败或文件缺失的分集，保留有效文件与手动暂停状态。
- 同时下载数量默认 2 集，管理员可在「网络与资源」设为 1–6，并选择新任务是否按站源分类保存；旧目录仍可读取。源站支持有效 Range 校验时续传，否则重新下载该文件，完整 HLS 分片可复用。
- Android 使用前台服务持续下载，通知提供「暂停下载」；Windows 下载时保持应用运行；iOS 当前为前台下载，进入后台暂停。「下载目录与空间」可查看占用、迁移视频并合并成品，迁移前检查下载索引，复制并保存新位置成功后才清理旧目录。
- 下载保存原始 MP4 / CENC MP4 及所需密钥；HLS 保存所选画质列表、分片、初始化片段、AES-128 密钥及默认音轨 / 字幕。暂不支持直播、未结束的 HLS 和需要额外授权的加密方式。

### 网络与资源设置

管理员从「设置与备份 → 网络与资源」选择自动、直连或手动代理，手动地址支持 HTTP、HTTPS、SOCKS5 / SOCKS5h；代理地址默认遮蔽、不进入用户配置备份，设备内播放服务始终绕过代理。自动模式读取系统静态代理与排除列表，恢复前台及每 30 秒更新；仅配置 PAC 而无可用静态代理时显示配置指引，本版不执行 PAC，也不关闭 TLS 校验。目录请求并发可设 1–6、间隔 0–5000 毫秒（默认 3 与 250），下载并发默认 2、可设 1–6。

### 局域网互联：追剧同步与推送播放（已接入，待验证）

「追剧 → 标题栏同步」或「设置与备份 → 设备互联」进入同步页。设备互联按本地用户保存、初始关闭；主动「选择设备」或播放器「推送」会开启本机互联，接收端先开启一次。服务类型为 `_zgj-link._tcp` DNS-SD / mDNS，发现信息只含设备名称、稳定设备 ID、端口、协议版本、证书指纹与能力；首次配对自动完成并记录证书，后续固定校验该指纹，证书改变不静默替换，可「忘记配对」后重连。

手动同步默认「双向合并」，另提供「覆盖对方」「覆盖本机」；底部先「查看预览」再执行，覆盖确认只在发起端进行。自动同步使用双向合并，首次连接交换版本摘要后仅发送改动条目与删除标记；正常播放期间约每 10 秒发送最新已保存进度，暂停、切集、退出播放器及推送交接时立即补发。

范围为追剧列表、想看 / 在看 / 已看及手动已看状态、新集已读基准与对应剧目的续播集数与时间；未追剧的全部观看历史不加入同步。独立记录以站源与原始剧集 ID 定位，用版本向量与删除标记判断先后，不依赖设备时钟或最大播放位置。同步记录含删除标记最多 25000 条、实际追剧最多 20000 部；单条不超过 512 KiB，接收暂存总量不超过 12 MiB。

播放器在常规、全屏与 TV 控制区提供投放图标。推送内容为站源、剧集 ID、分集 ID / 集数、播放位置与播放意图；接收端优先匹配自己已下载的同一分集，否则独立读取站源解析，不使用发起端的临时地址、密钥或路径。交接分准备与开始两步，接收端定位后实际播放、无缓冲、取得视频尺寸且位置继续前进才发开播回执，本机随后保存进度并暂停；失败、超时或取消时本机继续播放。

技术边界：锁定 Flutter `nsd 5.0.1` 做原生服务发现 / 发布，Go 提供独立局域网 HTTPS 端口（与仅绑定回环的媒体服务分开），使用 TLS 1.3、双端设备证书与精确指纹校验，只接受私有 / 链路本地地址，令牌不放入 URL；所有平台仅在前台接收，自动发现失败保留手动地址连接。

### 合并与本地成品

「下载 → 本地媒体 → 合并成品」可一次选择最多 50 部已下载剧集加入队列，每部需有 2–10000 集不重复且连续的分集，允许合并连续的部分集数并记录实际范围。流程为先本地解密或换封装保留码流，相同格式直接合并，音轨不一致时在 AAC 目标下统一为 AAC LC，视频确需统一时以数量最多的格式为目标；无音轨分集按需补静音。一次处理一个媒体任务，编码线程限 2，成品需通过时长检查与完整解码校验。完整完成的分集准备与转换步骤保存恢复记录，重开应用后任务暂停、手动继续时核对下载版本与媒体签名。默认保留原分集，「产物校验成功后才清理原分集」为可选项。成品保存在下载目录的 `library`，进度单独保存。

### Emby 导出与海报

「下载 → 本地媒体 → Emby 导出」按剧或批量导出已下载分集，「设置与备份 → 下载完成后自动导出 Emby」可开启自动处理。导出保存在下载目录的 `exports`，无损解密 / 换封装，不重新编码：

~~~text
exports/
  剧名 [站源-标识]/
    tvshow.nfo
    Season 01/S01E001.mkv + S01E001.nfo
    Season 00/S00E001.mkv + S00E001.nfo
~~~

NFO 提供剧名、简介、季 / 集编号、唯一标识及海报 URL。0.2.12 起按剧集 ID 登记并复用导出目录，本地合并成品可「导出到 Emby 特别篇」写入 `Season 00`。默认只写海报 URL，需要时可开启「同时导出海报文件」。将 `exports` 加入 Emby 电视节目库并启用实时监控或定时扫描；本功能不运行媒体服务器。

### Android TV

手机与电视共用 APK，无需单独构建参数。默认自动识别，也可在「更多 → 界面模式」手选「电视 / 遥控器」或「手机 / 电脑」，手选结果优先并保存在本机。识别依据系统 TV 模式、Leanback、旧版电视特征与 Fire TV，未声明这些特征的盒子结合无触屏、遥控方向导航等特征保守判断；屏幕尺寸和横竖比例不参与识别。目标 SDK 36，Activity 按 Android 16 官方说明声明保留方向请求的兼容属性，升级到 SDK 37 时需重新处理大屏方向策略。

| 场景 | 遥控器操作 |
| --- | --- |
| 浏览、弹窗、下载队列 | 方向键移动、确认选择、返回关闭或返回 |
| 控制条隐藏 | 左右快退 / 快进 10 秒，上下或确认显示控制条 |
| 控制条显示 | 方向键选择播放、切集、选集、设置，确认执行 |
| 进度条 | 左右快退 / 快进，确认暂停 / 继续 |
| 选集 | 每组 50 集，可切换范围、定位当前及输入集数跳转，保留 VIP 标记 |
| 首页返回 | 先返回主页，再清空搜索；主页且无搜索词时退出 |

支持专用播放 / 暂停、上一集、下一集按键，播放中无操作 5 秒后隐藏控制条。0.2.51 重做电视端焦点模型：焦点区域之间改为显式越界接管，首页侧栏、分类栏、剧集网格、多选操作栏与标题栏入口互相连通；新增遥控列表 / 遥控横向工具行 / 统一遥控条目组件；下载页在电视模式用遥控按钮工具行替代搜索输入框；各管理页补齐进入时的初始焦点。电视专属布局与操作入口只在电视模式生效。

## 技术说明：播放性能与画质增强

<a id="mpv-playback-plan"></a>

### mpv 播放性能（2026-09-27 分析）

依赖基线为 `media_kit 1.2.6` / `media_kit_video 2.0.1` / Android 库包 `1.3.8`，Flutter `3.47.4`。原链路中视频是 Flutter 外部纹理：`VideoOutput.java` 创建 `SurfaceProducer`，`FlutterRenderer.java` 在 API 29+ 走 ImageReader 分支，队列上限 2 张、`MAX_IMAGES=7`，呈现依赖 Flutter 调度与 raster 处理，负载过高可能让视频跳帧。

已确认的放大路径：手机、Windows 与 TV 的控制层对 position / duration / buffer / playing / buffering / volume 统一 `setState`；弹幕在关闭、非红果或本地播放时仍可能发生空通知；5 秒一次的进度保存会连带全量编码历史、重新解析同步记录、编码完整用户快照，并通过 `store` 通知重建应用外壳。已有的 `cache-on-disk=no`、`cache-secs=20`、`demuxer-readahead-secs=1`、`framedrop=vo`、`hr-seek-framedrop=yes`、Android `ao=audiotrack,opensles` 属于既有设置，不是待补的默认优化；32 MiB 配置不代表播放器总内存或解码帧队列，扩大它不能治疗呈现卡顿。

已实施：

| 阶段 | 结论 |
| --- | --- |
| MPV-1 共享播放状态与绘制减负 | 控件层 position / buffer 改走 240 ms 前沿加单次尾随节流且仅在控制层可见时重建，关键状态仍即时更新；播放器 position 通知约 50 ms 合并；弹幕仅在重同步、可见性翻转或进出时间窗时通知 |
| MPV-2 拆分高频进度存储 | 进度键改为可复用的 `媒体标识:集数` 并增加 0.5 秒位移阈值；历史按记录维护已编码行缓存，保存改为内存增量应用；快照编码交给常驻 isolate；LAN 记录复用内存历史；新增 `libraryChanges` 独立通知通道，消除每 5 秒一次的全外壳重建尖峰 |
| MPV-3 Android 独立视频宿主 | 已实施并经 Android 真机以画面像素证据验证 |
| MPV-4 条件化直出 | 已完成设备评估，结论为本机不启用直出 |

关键约束：mpv 的 Android VO 把 `--wid` 当作 **Java `Surface` 对象的全局引用**，不是窗口句柄（`video/out/android_common.c` 中 `vo_android_init()` 断言 `WinID != 0` 后调用 `ANativeWindow_fromSurface`）。因此现有 `vo=gpu` + `gpu-context=android` 路线可以直接输出到独立 Surface。`media_kit_video 2.0.1` 本身没有 SurfaceView / PlatformView 支持（`VideoOutputManager` 只暴露 `Create` / `SetSurfaceSize` / `Dispose`），故宿主由本项目自建：`VideoSurfaceHost.kt` 注册平台视图 `duanju/video_surface`（内部为真实 `SurfaceView`，`setZOrderMediaOverlay(true)`），经反射调用 `MediaKitAndroidHelper.newGlobalObjectRef(Surface)` 取全局引用后按 `android-surface-size → wid → vo` 顺序交给 mpv；Flutter 侧用 `PlatformViewsService.initSurfaceAndroidView` 走 Hybrid Composition，依据是引擎静态字段 `PlatformViewsController.VIEW_TYPES_REQUIRE_NON_TLHC` 会把真实 `SurfaceView` 排除在 Texture Layer / Virtual Display 路线之外。`surfaceDestroyed` 先置 `vo=null` 再延迟 5 秒释放引用；失败时回退纹理后端，同一 `Player` 实例只由一个后端持有。

设备实测（vivo V2453A / Android 15，同一 1080×1920@30fps 素材，release 包）：`surfaceOutput = True`、`textureOutput = False`，超过 16 ms 的 build 为 `8/1349 = 0.59%`（改造前 0.2.56 为 2.0%，纯净 0.2.55 为 94.7%）。

两条必须遵守的结论：

- **呈现判据**：mpv 的属性观测（`videoParams`、`state.width`、`state.position`）只反映已解码元数据，零像素呈现也会照常上报，不能作为画面呈现证据；本机 `dumpsys SurfaceFlinger --latency` 对包括桌面在内的图层返回全零时间戳，该方式整体失效。现改用画面像素判据（单帧色数、相邻样本 `diffbbox` 变化）。修复前同一监视器在整个 45 秒内只测得 `distinct = 1`（纯黑），即黑屏的量化症状。
- **不得恢复的两个尝试**：`holder.lockCanvas()` 画黑会与 mpv 争抢同一 buffer queue（`connect: already connected` 与 `eglCreateWindowSurface … failed`）；给宿主设不透明背景会在 AOSP `SurfaceView.draw()` 打洞后用背景 drawable 盖住视频（实测 45 秒 `distinct = 1`）。正确的黑色底衬是 AOSP 在 `mSubLayer < 0` 时自动显示的 SurfaceControl background 图层；当前缓解方式是过渡动画完成前不挂载视频宿主，由 Dart 侧先铺 `ColoredBox(Colors.black)`。

MPV-4 评估（同素材同实例 A/B，每轮切换前 `seek(0)` 并固定观测窗口，读播放位置推进量）：

| VO | hwdec | 播放位置推进 | 结论 |
| --- | --- | --- | --- |
| `gpu` | `auto-safe` | 约 4.0 s / 4 s | 正常出画（现网配置） |
| `mediacodec_embed` | `auto-safe` / `mediacodec` / `mediacodec-copy` | 0 s | 停滞，无帧（`mediacodec` 下解码器未上报、宽高为 0） |
| `mediacodec` | `auto-safe` | 0 s | 停滞 |

随包 `libmpv.so` 中存在 `mediacodec` 与 `mediacodec_embed` 两个 VO 驱动，属运行期无法出画，不是功能缺失。早前一次未做进度归零的长时观测显示部分组合“推进约 3.7–4.0 s”，复查后判定为素材跑到结尾造成的假象。因此直出不纳入默认路径，`VideoSurfaceHost` 保持 `vo=gpu` + `gpu-context=android`；更换设备或上游 mpv 版本时可用同一 A/B 方法重新评估。

回退按阶段独立保留：共享 UI 调度可切回旧实现，存储迁移保留已校验的恢复快照，Android 先回退到独立 Surface 的 GPU 路线，再回退旧纹理后端。

### 视频画质增强与超分（2026-09-22 调研，0.2.18 已接入源码）

0.2.18 曾在现有 media_kit / libmpv 播放器上接入实时画质增强，覆盖通用／真人短剧与动漫／AI 动漫；**0.2.24 因手机和电视端卡死反馈，把实际入口与运行链路收窄为仅 Windows 桌面端**。Android 手机、Android TV 与 iOS 不显示入口也不初始化后端。Windows 仍包含 FSRCNNX 与按实际运行条件选择的 NVIDIA / Intel VPP。

已接入范围：档位为关闭 / 自动 / 省电增强 / 清晰优先，内容跟随分类 / 通用／真人 / 动漫／AI 动漫（自动判断只使用明确动漫分类或标签）；通用增强用 `spline36` 兜底、有效 LUMA 用 RAVU-Lite-AR、硬解 RGB 用 RAVU RGB、清晰优先可用 FSRCNNX `x2_8-0-4-1`，同一时刻只装载一种主算法；动漫档选用 Anime4K Upscale+Denoise CNN x2 S，不使用强 Restore 或人脸生成模块。输出尺寸按视频区域物理像素、源宽高比和旋转计算，Windows 上限 8294400 像素。未知色彩与 HDR / 10-bit 保持原处理；MediaCodec 不公开像素格式时只有明确 8-bit 的 H.264 / HEVC profile 且为 SDR 才尝试 RGB 增强。

关键实施约束：

- **输出尺寸必须先做对**。只换 Shader 可能仍让 Flutter 把原尺寸纹理放大，甚至让按放大比例触发的 Shader 一次都不执行。`720×1280` 竖屏短剧在 `1920×1080` 横屏桌面上完整显示时内容约 `608×1080`，属于缩小、无需超分；`720×1280` 的 2 倍中间图已是 `1440×2560`，需单独预算。
- **硬解纹理路径的 Hook 不一定存在**。Android 当前 `vo=gpu` + OpenGL ES + `hwdec=auto-safe`，mpv 的 AImageReader 硬解映射产生 `RGB0 / external OES` 纹理，LUMA Shader 不一定触发，优先提供作用于 `MAIN` 的 RGB 路线，不能以关闭硬解或逐帧读回 CPU 为代价。
- **Windows 不是独立 mpv 原生 D3D11 VO**。当前为 `vo=libmpv` 的 OpenGL Render API，经 ANGLE 与 D3D11 纹理交互，不能直接套用 `vo=gpu-next` / `gpu-api=d3d11` 配置；优先验证 `hwdec_d3d11egl` 复用路径。硬件超分（`d3d11vpp`）必须更新并固定原生库，不能只改 Dart 参数，且需检查混合显卡笔记本上解码、处理、显示的适配器是否一致。
- **生效判定不能只看配置**。`glsl-shaders` 已写入但没有可用 LUMA 或未满足 `WHEN` 时标为未生效；驱动日志提示 enabled 不代表画面变化。核对目标尺寸、输入格式、驱动活动与受控对比，失败时撤回本功能配置并恢复基础播放，不能把增强错误送入网络解析重试流程。
- **降级策略**。过滤切集、seek、网络缓冲与正常倍速调度后，连续约 10 秒出现明显超时 / 新增丢帧，或温控恶化时逐级降低；同一播放会话只自动降级，新分集或用户主动重选时才重新评估。显存预算含中间特征图与纹理池，`1080×1920` 的一张 RGBA16F 纹理约 15.8 MiB。
- **许可证**。已核对 RAVU Shader 为 LGPLv3，FSRCNNX 1.1 发布 Shader 文件头为 LGPLv3+（训练仓库根许可证不同），ArtCNN / Anime4K 为 MIT，Kazumi 代码为 GPL-3.0；权重与 SDK 的再分发条件不能从仓库代码许可证自动推导。

论文数字与社区经验不能直接当作本 App 实测成绩：Mobile AI 2021 的 `320×180 → 1280×720` 约 80 FPS 是骁龙 865 双三次退化条件；FlashVSR 的约 17 FPS 是单张 A100、`768×1408`、约 11.1 GB 峰值显存且仍有 8 帧前视；NTIRE 竞赛测速为小图单帧。这些都不能推导普通手机在真实压缩域下的实时帧率。

移动端后续优先评估单 pass、低带宽的空间上采样 / 锐化路线（SGSR / FSR1 类思路），再看是否接入紧凑 CNN 或原生推理后端。

参考来源（外部文档访问日期 2026-09-27 / 2026-09-22）：

- [media-kit](https://github.com/media-kit/media-kit)、[mpv GLSL 文档](https://mpv.io/manual/master/#options-glsl-shader)、[libmpv Render API](https://github.com/mpv-player/mpv/blob/c6c4c38d7f4aa82ad2a29a4c3b142f19123f5b9e/include/mpv/render.h)、[mpv AImageReader 源码](https://github.com/mpv-player/mpv/blob/c6c4c38d7f4aa82ad2a29a4c3b142f19123f5b9e/video/out/hwdec/hwdec_aimagereader.c)、[mpv hwdec_d3d11egl](https://github.com/mpv-player/mpv/blob/c6c4c38d7f4aa82ad2a29a4c3b142f19123f5b9e/video/out/opengl/hwdec_d3d11egl.c)
- [mpv PR #14698（VPP 缩放）](https://github.com/mpv-player/mpv/pull/14698)、[mpv #14758](https://github.com/mpv-player/mpv/issues/14758)、[mpv #15700](https://github.com/mpv-player/mpv/issues/15700)、[mpv PR #18301](https://github.com/mpv-player/mpv/pull/18301)、[mpv-android #824](https://github.com/mpv-android/mpv-android/issues/824)、[mpv 属性文档](https://mpv.io/manual/master/#property-list)、[libplacebo custom shaders](https://libplacebo.org/custom-shaders/)
- [Android Media3：选择 Surface 类型](https://developer.android.com/media/media3/ui/surface)、[Flutter Android Platform Views](https://docs.flutter.dev/platform-integration/android/platform-views)、[Flutter CustomPainter](https://api.flutter.dev/flutter/rendering/CustomPainter-class.html)、[Android Thermal API](https://developer.android.com/games/optimize/adpf/thermal)
- [mpv-prescalers / RAVU](https://github.com/bjin/mpv-prescalers)、[FSRCNNX 1.1](https://github.com/igv/FSRCNN-TensorFlow/releases/tag/1.1)、[ArtCNN](https://github.com/Artoriuz/ArtCNN)、[Anime4K](https://github.com/bloc97/Anime4K)、[Artoriuz mpv upscaling](https://artoriuz.github.io/blog/mpv_upscaling.html)、[Kazumi 播放控制源码](https://github.com/Predidit/Kazumi/blob/4fed48b527768782d66b127f171d96babd7c427b/lib/pages/player/controller/player_playback_controller.dart)
- [Real-ESRGAN](https://arxiv.org/abs/2107.10833)、[RealBasicVSR](https://arxiv.org/abs/2111.12704)、[FlashVSR](https://arxiv.org/abs/2510.12747)、[PLKSR-Rep](https://openaccess.thecvf.com/content/CVPR2026W/NTIRE/html/Deng_PLKSR-Rep_A_Compact_Large-Kernel_CNN_for_Mobile_Real-World_Image_Super-Resolution_CVPRW_2026_paper.html)、[Microsoft Edge VSR](https://blogs.windows.com/msedgedev/2023/03/08/video-super-resolution-in-microsoft-edge/)、[Snapdragon GSR](https://github.com/SnapdragonGameStudios/snapdragon-gsr)、[Video2X](https://github.com/k4yt3x/video2x)
- [LocalSend 协议](https://github.com/localsend/protocol)、[nsd](https://github.com/sebastianhaberey/nsd/tree/main/nsd)、[Syncthing BEP 协议](https://github.com/syncthing/docs/blob/main/specs/bep-v1.rst)、[Android 边到边布局](https://developer.android.com/develop/ui/views/layout/edge-to-edge)、[Android 16 方向兼容属性](https://developer.android.com/about/versions/16/behavior-changes-16#temporary-opt-out)

## 安装包与平台状态

0.3.0 起唯一构建版本为红果鉴，不再产出真果鉴 / 全站源包；下列安装包与设备记录是当时的全站源构建，作为历史验证记录保留。

| 平台 | 状态 |
| --- | --- |
| Android 8.0+ 手机 | 最后实测为 `0.2.78+2084` ARM64 Release（全站源构建）：包检查、`adb install -r` 覆盖安装与启动均通过（vivo V2453A / Android 15，数据保留、`logcat` 无 `FATAL EXCEPTION`），包内核心哈希与构建记录一致；真实站源播放、熄屏、下载与音量键行为仍待真机验收 |
| Windows 10/11 x64 | 完整 ZIP 解压后运行 `hongguojian.exe`，需保留所有 DLL 和 `data`；局域网原生发现依赖 Windows 10 1903+。0.2.74 起播放常亮由应用内统一管理（纹理路径关闭 media_kit_video 自带 wakelock），桌面端屏幕保持与完整包运行未验证 |
| Android TV | 与手机共用 Android 源码，未验证；自动识别与电视模式横屏、选集 / 设置及设备互联待实机验收 |
| iOS 15.1+ | 未验证。已加入工程、Go 核心链接、媒体依赖、文件管理、系统代理桥接、Bonjour / 局域网权限和构建脚本；0.2.40 起 iOS 播放页禁用 media_kit_video 硬件纹理加速以规避 libmpv OpenGL ES 渲染上下文失败直接退出。没有已签名 IPA |

更早的历史安装包记录不再逐条罗列，需要时从 Releases 或 `dist/android/SHA256SUMS.txt` 核对。从 0.2.6 起 Android APK 默认压缩原生 `.so` 库，安装时解压后加载；`INSTALL_FAILED_NO_MATCHING_ABIS` 表示 APK 与设备架构不匹配，请更换对应架构安装包。

### GitHub Actions

将源码发布到仓库根目录，保留 `.github`、锁文件、`native` 和平台工程；不上传 SDK、依赖目录、SO、DLL 或缓存。

推送 `main` / `master`、推送任意标签、提交 PR，或在 **Actions → Build app packages → Run workflow** 手动启动，都会独立执行检查与构建；checks 失败不阻塞出包：

| Artifact | 内容 |
| --- | --- |
| `hongguojian-android` | 三种架构 APK 和 SHA256 |
| `hongguojian-windows` | Windows job 暂时注释，当前 CI 不出 Windows 包；构建脚本保留 |
| `hongguojian-ios-unsigned` | 未签名 `.app` ZIP 和 SHA256，不能直接当已签名 IPA 安装 |

流水线只构建红果鉴一个版本，Flutter 与 Go 回归覆盖同一份编译配置。工作流不指定 7 / 14 天的 Artifact 保留期，临时产物遵循仓库 Settings → Actions → General 的保留策略，GitHub 仍会按期清理；需要长期下载请用 Releases 附件。PR 不发布 Release；推分支、打标签和手动运行在 Android 构建成功且 iOS job 结束后发布。推分支或在分支上手动运行时，每次使用独立的 `build-{runId}-{attempt}` tag（例如 `build-123456789-1`），重跑也生成新 tag，不再把不同批次的资源累积到 `latest`；显式指定 tag 时仍发布到对应版本。同一轮 Android 与 iOS 包归入同一个 Release，iOS 允许失败，仅收录已上传的 iOS 包。

发布由 `scripts/publish_release.py` 执行，同一 tag 串行发布。自动生成的 tag 指向本次构建提交，由 `GITHUB_TOKEN` 创建，不会再次触发工作流；每次发布只写自己的 Release，不移动也不重建已有 tag，GitHub 会把最新发布的 Release 标为 Latest。安装包文件名追加运行编号与尝试次数（0.3.0 起不再含提交哈希），附构建清单和 `SHA256SUMS`。全部新附件通过大小和服务端 SHA-256 核对后才公开发布；历史 Release（含旧 `latest`、`0.1`、`0.2` 等滚动或版本 tag）及其安装包、清单和校验文件原样保留，不自动迁移或删除。显式 tag 重跑时只追加新附件，同名且校验一致的附件直接复用，冲突则中止而不覆盖。上传、校验或发布失败也不会清理旧资源。构建成功不代表 checks 或设备验收通过。

Android 正式发布持续使用同一签名并递增构建号，在仓库 Secrets 配置 `ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。未配置时生成预览 APK，不同构建机的预览签名可能无法相互覆盖。创建签名文件并保存到项目外：

~~~sh
keytool -genkeypair -v -keystore zhenguojian-release.jks -storetype JKS -alias zhenguojian -keyalg RSA -keysize 2048 -validity 10000
~~~

本地不入库的 `android/key.properties` 填写 `storeFile` / `storePassword` / `keyAlias` / `keyPassword`。

## 开发与构建

Flutter `3.47.4`、Dart `3.12+`、Go `1.24.1+`、Python `3.10+`。Android 需要 JDK 17、SDK 36、NDK `28.2.13676358`；Windows 需要 Visual Studio 的 C++ 桌面组件及 MinGW-w64 x64；iOS 需要 macOS、完整 Xcode 和 CocoaPods。将 Flutter、Go、Python 加入 PATH，Android 设置 `ANDROID_HOME`；构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，不改全局配置。

~~~sh
python3 scripts/build_android.py
python3 scripts/build_android.py --abi arm64-v8a
python3 scripts/build_android.py --cn-mirrors
python3 scripts/build_ios.py
python3 scripts/build_ios.py --core-only
python3 scripts/build_ios.py --export-options /path/to/ExportOptions.plist
~~~

`--abi`、`--cn-mirrors` 可与默认参数组合。国内镜像开关让 Flutter/pub 使用 `storage.flutter-io.cn` / `pub.flutter-io.cn`、Android 依赖优先使用阿里云镜像并保留官方仓库；仅在本次构建生效，结束后恢复原锁文件并清理临时 Gradle 配置。镜像可能有同步延迟，缺失或异常时去掉开关重试；该开关不替代 Flutter SDK 与 Gradle 发行包的初次安装。

Windows 运行 `.\scripts\build_windows.ps1`（或 `python scripts/build_windows.py`，无站源开关参数），可加 `-ChinaMirrors`。产物在 `dist/android`、`dist/windows`、`dist/ios`，文件名以 `hongguojian-` 开头。

首次调试先编译对应架构核心再运行：

~~~sh
python3 scripts/build_native.py --platform android --abi arm64-v8a
flutter pub get --enforce-lockfile
flutter run
~~~

Windows 对应 `--platform windows` 和 `flutter run -d windows`。0.2.62 起 Android 打包要求原生库旁存在 `libduanju_core.build.json`，校验站源配置、平台、架构和 SHA-256；分发时复核 APK 内核心哈希。构建记录由 `build_native.py` 生成，不纳入源码镜像。

播放器使用 [media_kit](https://github.com/media-kit/media-kit) / libmpv，合并与导出使用 [FFmpegKit min-gpl](https://github.com/sk3llo/ffmpeg_kit_flutter)，含 FFmpeg、x264 / x265 等 GPL 媒体组件，各组件适用上游许可证。FFmpegKit 不参与正常播放或下载的转码；系统 FFmpeg 只用于开发验证。

### 集中检查与真机回归

整体验证仍暂停；以下命令用于后续集中验证，不表示未覆盖的功能和平台已通过检查：

~~~sh
python3 -m unittest discover -s scripts -p 'test_*.py'
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
dart analyze --fatal-infos lib test integration_test test_driver
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=ALL_SOURCES=true
cd native
go test -race ./...
go test -race -ldflags="-X duanjuapp/native/core.buildAllSources=true" ./...
~~~

合成媒体验证需要开发机安装 `ffmpeg` / `ffprobe`。测试覆盖权限隔离、备份校验、搜索防抖与旧结果、少数分集转码、CENC 解密换封装、Emby 元数据及删除原文件后的完整解码，不请求站源图片。

Android 回归使用独立 `.debug` 包，连接并授权 USB 调试、保持设备解锁：

~~~sh
python3 scripts/create_test_media.py
python3 scripts/serve_test_media.py
adb reverse tcp:38473 tcp:38473
flutter drive --driver=test_driver/playback.dart --target=integration_test/playback_test.dart --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=FIXTURE_BASE_URL=http://127.0.0.1:38473
~~~

多设备时指定序列号，可加 `--dart-define=CHECK_LIVE_CATALOG=true`。用例覆盖 MP4 / AES HLS / CENC、切线、切集、横屏、离线下载、合并 / 导出及后台下载。结果在 `build/device-test/results/`；结束后停服务并执行 `adb reverse --remove tcp:38473`。

### 源码同步与恢复

每次完成任务并通过必要检查后执行：

~~~sh
python3 scripts/finish_task.py --message "本次实际完成的变更"
python3 scripts/sync_source.py --check
~~~

脚本只同步纯源码到同级 `../guoapp`，不要求目标存在 `.git`，不执行提交、tag、分支、推送或其他 Git 操作，并在同级生成 `真果·鉴-YYYYMMDDHHMM.zip` 源码压缩包；同一分钟内重复收尾会追加序号。在 `guoapp` 内工作时跳过向自身同步。目标若已有 `.git`，同步时原样保留但不触碰。

从源码压缩包恢复：

~~~sh
mkdir -p ../restore
unzip ../真果·鉴-YYYYMMDDHHMM.zip -d ../restore
~~~

| 目录 | 内容 |
| --- | --- |
| `lib` | 页面、播放器、本地用户、FFI、下载与媒体处理 |
| `native/core`、`native/bridge` | 独立站源核心、缓存、下载、目录迁移及 C ABI |
| `android`、`windows`、`ios` | 平台工程与必要资源 |
| `assets/video_enhancement`、`packages/media_kit_libs_windows_video` | 增强 Shader 与许可、固定 Windows 媒体依赖插件 |
| `scripts`、`.github/workflows` | 构建、签名、验证、同步与版本快照 |
| `test`、`integration_test` | 自动化与设备回归 |

## 功能 TODO

条目状态以各行为准。未完成集中验证与平台验收的项目保持未勾选，并标明实际实施与检查范围；不对未验证的行为给结论。0.3.0 起「在看」榜单（P3-6）已删除、黄果 AI（P1-4）随站源收敛移除，相关行保留为历史记录。

### 优先修复

| 编号 | 范围 | 状态与内容 |
| --- | --- | --- |
| P1-R1 | 目录分页 | 已实现，待验证：总目录与分类分别保存 offset、会话、设备标识、分页签名与最后 ID，同一快照落盘；会话过期重新申请，重复 / 不前进的页保留旧位置 |
| P1-R2 | 保存上限 | 已实现，待验证：移除 6000 条与 500 页静默上限，按 ID 合并并持久保存；达到 32 MiB 明确报错并暂停继续请求，保留待保存数据 |
| P1-R3 | 资料回写 | 0.2.7：详情与补齐按 ID 更新目录和分类副本，写盘保留 Categories，分类菜单与本机细分类合并 |
| P1-R4 | 资料字段 | 已实现，待验证：贯通详情字段到 Dart 侧，详情与播放动作通知同 ID 列表及失败海报，按 ID 合并收藏 / 历史 |
| P1-R5 | 黄豆解码 | 已实现，待验证：优先识别合法明文 JSON 再走 AES 解码，保留 gzip 兼容并用 `UseNumber` 保留长 ID |
| P1-R6 | 海报来源 | 0.2.7：海报 Referer 跟随 API 当前实际入口 |
| P1-R7 | 索引保护 | 已实现，待验证：索引加载失败时禁止迁移与重写，先检查普通文件、大小、条目、重复 ID 与状态，拒绝 null 索引 |
| P1-R8 | 写入失败 | 已实现，待验证：目录与站源记录的写入失败传回页面 / 任务并标明未保存，保留内存数据、提供重试，未保存前不推进游标 |
| P1-R9 | 配置损坏 | 已实现，待验证：区分首次启动与配置损坏，异常用户记录或不完整快照锁定访问，提供原始配置导出与管理员密码校验后的恢复，不降级管理员保护 |
| P1-R10 | 保存语义 | 已实现，待验证：所有设置与记录检查保存结果并串行提交完整快照，失败重读并回滚，无法确认时锁定 |

### 功能完善

| 编号 | 功能 | 状态与内容 |
| --- | --- | --- |
| P1-5 | 榜单 | 0.2.7：红果总热播 / 真人剧 / 漫剧 / AI 剧四榜，保留源站名次与顺序，支持分页、刷新、详情播放；缓存 5 分钟内复用，失败回退 24 小时内旧榜单并提示未更新 |
| P1-6 | 红果分类推荐 | 已实现，待验证：真人剧 / 漫剧 / AI 剧三档推荐，独立保存游标、会话与去重记录；入口位于分类「全部」之后并内嵌当前页显示，不把推荐选择当作分类 ID 发往目录接口 |
| P1-7 | 排序与完整资料 | 已实现，待验证：透传并持久保存热度、播放量、日期、标签与连载状态；支持名称、自然季号、日期、热度、播放量排序及状态筛选，未知置后 |
| P1-8 | 搜索完整性 | 已实现，待验证：红果合并官网与名称索引，按 ID 去重并保留同名不同 ID，补识别到的漏季；加入归一化、分词匹配、相关度与自然季号排序、最近 20 次搜索 |
| P2-1 | 追剧与历史 | 已实现，待集中验证：状态筛选、独立手动已看、新集数量与已读基准、直接续播、本地搜索与单条删除，按用户保存并纳入兼容旧格式的备份 |
| P2-2 | 剧库管理 | 已实现，待集中验证：首页复用站源 update 任务（查新、历史续载、最多 8 部资料补齐、阶段提示与停止）；卡片提供收藏 / 状态 / 下载操作；发现页支持最多 50 部多选与部分失败重试 |
| P2-3 | 红果弹幕 | 已实现，待集中验证：设备端独立请求、分集与毫秒时间校验、有界分页缓存与线性渲染，同步暂停、缓冲、倍速、跳转、切集与后台状态 |
| P2-4 | 预加载与缓冲反馈 | 已实现，待验证：低优先级解析、最多 6 秒 / 4 MiB / 8 次请求的预取、HLS 前两段与 MP4 前缀复用；自动连播与预加载默认始终开启 |
| P2-5 | 下载合集 | 已实现，待验证：按剧分组与多选暂停、继续、删除、重试及部分失败重试；「更新本剧」补新增 / 缺失分集并保留有效文件与暂停状态 |
| P2-6 | 下载偏好 | 已实现，待验证：按用户保存默认画质 / VIP 选择并纳入备份，管理员可设并发 1–6 与按站源分类保存，兼容原扁平目录 |
| P2-7 | 合并流程 | 已实现，待验证：音轨签名含 AAC profile / extradata，不兼容音轨统一到 LC，成品完整解码通过后才登记；支持检查点恢复与可选清理原分集 |
| P2-8 | VIP 资料补齐 | 已实现，待验证：贯通未知 / 免费 / VIP 三态，未知不覆盖已知，旧缓存中不可区分的 false 恢复为未知，站源管理显示待识别数量 |
| P2-9 | Emby 导出 | 已实现，待验证：按剧集 ID 持久保存稳定目录，合并成品导出到 `Season 00` 并记录实际范围，删除最后一个导出条目不递归删除剧目目录 |
| P2-10 | 播放偏好与全屏交互 | 已实现，待验证：保存画质、倍速与自动连播并按用户隔离；临时倍速在松手、切集、菜单、后台与失焦时复原（0.3.7 起自动连播期间保持） |
| P2-11 | 资料失败后继续推进 | 已实现，待验证：保存失败重试时间与扫描位置，单剧 404 冷却 24 小时、其他失败 5 分钟，每批最多 8 部，连续失败后从后续条目推进 |
| P3-1 | 网络与资源设置 | 已实现，待验证：管理员面板、本机原子保存、直连 / 自动 / 手动代理、目录并发 1–6 与间隔 0–5000 毫秒；系统静态代理支持三平台桥接及定时刷新，PAC 需手动配置 |
| P3-2 | 局域网追剧同步 | 已实现，待验证：DNS-SD / mDNS 发现、固定证书 HTTPS 直连、单设备自动连接与多设备选择；版本向量、删除标记、冲突选择、原子保存、回执与断线补齐已接入 |
| P3-3 | 局域网推送播放 | 已实现，待验证：常规、全屏与 TV 控制区接入推送，接收端优先使用自己的完整下载，否则独立解析；准备完成后接收最新位置，实际播放后发起端暂停 |
| P3-4 | 画质增强与超分 | 已实现，待验证：输出尺寸适配、高质量缩放、RAVU、动漫 CNN、Windows FSRCNNX 与有条件 VPP；0.2.24 起收窄为仅 Windows 桌面端 |
| P3-5 | Android 画中画 | 已实现，待验证：Activity 声明 PiP 能力，进入前隐藏覆盖层并传 `sourceRectHint`；Android 手机 / 平板显示入口，退出恢复常规生命周期 |
| P3-6 | 在看推荐榜单 | 已删除：0.2.80 接入、0.2.84 定稿，0.3.0 随「在看」整体删除，保留为历史记录 |
| P1-4 | 黄果 AI | 随站源收敛移除；历史记录为 0.2.12 只读诊断时目录与三个入口均超时，此前截图同剧的密钥连接在 TLS 握手断开，未恢复 |

旧项目的 Docker / HTTP 服务、浏览器注册与远程账号、跨设备服务端记录、在线 STRM 签名网关和远程 Emby 定时同步依赖常驻服务器，不直接照搬为缺失功能；当前对应能力是设备内用户与备份、原生播放器、本地媒体和 Emby 文件导出。普通评论在旧项目中也未接入，不列为遗漏。

### 对照证据与验收边界

2026-09-21 对真实 Go 核心做过 9 项定向行为对照（临时 overlay 注入、内存文字响应隔离网络），复现的预期差距包括：分页推进到 offset=18 后重启仍请求 `[0, 0]`；第 201 页返回第 6001 条但重启后新 ID 不在缓存；资料更新后分类副本未更新且写盘丢失 Categories；详情新标题未回写目录；明文 JSON 误入 AES 分支；海报 Referer 主机与实际 API 入口不同；五类资料字段丢失；未知 VIP 覆盖已知值；官网与名称索引的季度合并不完整。续核另用 3 项 Go 文字 / 文件夹具与 3 项 Flutter 内存偏好夹具，复现损坏索引被清空、同名目录阻止写入仍报成功、无效访客条目旁管理员未锁定、偏好保存失败后数据不一致、备份恢复中断留下混合状态、前两部 404 时后续批次请求次数异常。

这些检查只用于定位差距，不代表全量回归失败，也未加入正式测试集；实施修复时应将对应夹具整理为可通过的回归。0.3.0 起只有单一红果鉴构建，保留设备本地文件、FFI 与原生播放器的实现方式，不整目录覆盖旧项目。

## 历史与平台验证记录

0.2.86 及更早版本按时间倒序保留要点；整体验证自 2026-09-21 起暂停，只有用户明确授权时执行定向检查。

| 版本 | 要点 |
| --- | --- |
| 0.2.86 | 去掉 0.2.85 中自行添加的顶部提示行，多选删除只保留卡片菜单入口 |
| 0.2.85 | 「删除我发布的记录」改为多选，服务层新增 `removeMany`，只对勾选的剧重置观看累计 |
| 0.2.84 | 「在看」界面与筛选定稿：导航改为「主页 / 在看 / 历史」，站源筛选默认只选红果并可多选，分类可取消；修掉设置页底部被虚拟导航键遮挡 |
| 0.2.80 | 「用户推荐」做成内置动态榜单：导航新增「动态」，身份为本机生成的 32 字节密钥，事件用纯 Dart 实现 secp256k1 与 BIP-340 Schnorr，按不同身份数聚合 |
| 0.2.79 | 榜单空数据根因是 `RankingBoard.sourceForID` 只认六个站源；改按榜单 ID 前缀解析并记住 `rankingBoards` 权威映射；黄果入口不再折叠成特例；原生核心四处并发扇出加 `recover` |
| 0.2.78 | 音量键导致暂停的根因是 `inactive` 被当作不在前台，改为只在 `paused` / `hidden` 暂停；补齐猫果 / 饭果 / 河果 / 星果分页标记与牛果 `type_id`、星果按 `resourceId` 巡游 |
| 0.2.77 | 剧库导出改为标准 XZ 压缩包（2000 条约 1017 KB → 24 KB），导入按文件头识别 XZ 或 JSON，且不再需要先登录 |
| 0.2.76 | 为短剧站源补 25 个榜单入口，修好黄果 AI 从 `data-url` 动态识别内容主机；新增 `lib/error_boundary.dart` 收敛无界错误卡片；下线长期不可用的网果与发果 |
| 0.2.74 | 修复播放约 40 秒后自动息屏：新增 `lib/screen_awake.dart` 以引用计数统一持有常亮，纹理路径 `Video` 传 `wakelock: false`；`wakelock_plus` 由传递依赖改为直接依赖 |
| 0.2.73 | 红果大文件剧集无法播放的根因是无扩展名媒体地址先读满 4 MB 判为失败；嗅探上限降至 256 KB，读到上限且前缀不是 `#EXTM3U` 时边转发边判断 |
| 0.2.72 | 修黄果 AI 详情集数：按当前剧集 ID 合并 `/video/{id}/ep-{n}/` 完整分集链接，避免推荐剧污染 |
| 0.2.65 | 非全屏控制层改为无操作 3 秒后以 180 毫秒淡出，缓冲 / 长按结束后的计时恢复，轻点统一为切换控制层 |
| 0.2.63 | 替换应用图标为绿底金色果形播放图；播放器准备与缓冲改用浅色静态文字，取消橙色转圈 |
| 0.2.62 | 修复 0.2.61 发布 APK 混入旧原生核心导致无法启动：构建记录校验站源开关、平台、架构与 SHA-256，分发前再次核对 APK 内核心字节 |
| 0.2.61 | 修复播放页顶部、推荐缓存（20 分钟有效期与进行中请求合并）、后台切回黑屏（`surfaceDestroyed` 未通知 mpv 释放 `ANativeWindow`） |
| 0.2.53 | 接入十二个短剧站源（芽果 / 猫果 / 饭果 / 观果 / 河果 / 星果 / 花果 / 牛果 / 网果 / 发果 / 皮果 / 伍果），全部在 Go 原生核心内请求与解析 |
| 0.2.51 | 重做电视端焦点模型，修复部分列表无法用遥控器选择与首页下翻后回不到上方两类问题 |
| 0.2.44 | 更新野果默认入口与线路发现页；首页与推荐卡片普通点击改为无中间页直达播放；帝果签名失败不再静默回退 |
| 0.2.40 | 针对 iOS IPA 点击剧集后闪退：iOS `VideoController` 禁用硬件纹理加速，改走软件纹理兜底 |
| 0.2.39 | 播放页 Tab 改为选集 / 简介 / 下载，追剧移入简介、下载移入下载 Tab；播放器层移除移动端音量、下载与追剧按钮 |
| 0.2.37 | 画中画进入前隐藏自绘控制层与弹幕并等待一帧，传入视频区域 `sourceRectHint` |
| 0.2.33 | 手机与桌面播放器覆盖层移除「播放设置」按钮，常用项直接可用；自动连播与预加载固定开启 |
| 0.2.31 | 红果系列剧按标题末尾季号识别，已追剧发现后续季时显示「新季」提醒，不自动加入追剧 |
| 0.2.29 | 补强电视自动识别（系统 TV 模式、Leanback、Fire TV 等）与统一横屏方向管理 |
| 0.2.24 | 按手机与电视端卡死反馈，画质增强入口与运行链路收窄为仅 Windows 桌面端 |
| 0.2.20 | Android 手机 / 平板播放器接入画中画源码 |
| 0.2.18 | 接入实时画质增强源码；修复野果解析在包初始化时用 `{1,2400}` 导致加载核心 panic 的启动问题 |
| 0.2.17 | 接入野果与帝果，含分类、目录与搜索分页、详情、真实分集与媒体解析 |
| 0.2.16 | 接入剧果访客授权、动态分类、目录与搜索分页、详情及 CloudFront 签名 Cookie 媒体链路 |
| 0.2.13 | 接入 P3-2 / P3-3：局域网自动连接、追剧与续播增量同步、手动覆盖、冲突处理与播放推送 |
| 0.2.12 | 接入 P2-4 至 P2-7、P2-9 与 P3-1，并把排序 / 筛选、下载多选移入标题栏；接入下一集预加载 |
| 0.2.11 | 接入红果弹幕：分集与毫秒时间校验、有界分页缓存、线性渲染，同步暂停 / 缓冲 / 倍速 / 跳转 |
| 0.2.10 | 接入 P2-1 与 P2-2：追剧与历史完善、剧库管理与统一更新、批量下载 |
| 0.2.9 | 接入播放器交互、分页与保存恢复、本地用户完整性、红果推荐、资料模型、排序、完整搜索 |
| 0.2.4 至 0.2.8 | 站源管理与逐站任务、健康检测与 CF 诊断、黄果各入口修复、HEIC 转 JPEG、检测详情展开状态记忆 |

安装包与设备验证方面，0.2.74 与 0.2.78 两轮做过完整取证：`aapt2 dump badging` 核对包名 `com.duanju.duanju_app`、应用名、versionName / versionCode、`native-code: arm64-v8a`、minSdk 26 / targetSdk 36；`apksigner verify --print-certs` 通过 APK Signature Scheme v2 且证书 SHA-256 与历史包一致；`zipfile.testzip()` 无 CRC 错误；APK 内 `libduanju_core.so` 与 `libduanju_core.build.json` 的 SHA-256 相同。原始记录在 `build/packages-XXXX/` 下的构建日志、`apk-verification.json`、`install.log` 与 `device-installation.json`。这些取证只覆盖构建与安装，不代表真实站源播放已经验收。
