# RimWorld 启动器

用于发现和启动 RimWorld、浏览创意工坊、安装与管理 Mod 的简体中文 Windows 桌面应用。

[用户指南](#用户指南) · [开发者文档](#开发者文档)

## 用户指南

### 快速开始

1. 获取 Windows x64 发布压缩包，**完整解压**到一个文件夹。
2. 双击文件夹中的 **rimworld_launcher.exe**。使用发布版不需要安装 Rust 或 Flutter。
3. 在「首页 → 安装管理」选中要使用的游戏。没有自动找到时，点击「添加目录」手动登记。
4. 回到「游戏概览」启动游戏；需要管理 Mod 时，进入「已安装 Mod」。

请保留程序旁的 DLL 和 data 文件夹，不要单独移动 EXE。

### 游戏安装与启动

启动器会自动检查 Steam 游戏库、常见安装位置和之前使用过的目录，支持同时登记多份游戏。「Steam 安装」与「独立目录」表示安装方式。

- **已有游戏**：在「首页 → 安装管理」添加或选中游戏目录。目录中应包含游戏程序和 Data/Core。
- **没有找到游戏**：进入「设置 → 扫描目录」，选择上级目录重新扫描。
- **从网址安装**：在「设置 → 下载与工具」填写并保存游戏 ZIP 下载源，再点击「下载并安装」，选择一个空目录。
- **启动游戏**：在「游戏概览」核对当前版本和路径，点击「启动游戏」。Steam 安装交由 Steam 启动，独立目录直接运行游戏。

下载源需要是 HTTP 或 HTTPS 的 ZIP 文件直链。未预置下载源时，需要先填写地址。安装目标已有游戏时可以登记现有安装，避免覆盖已有文件。

### 配置 SteamCMD

创意工坊的 Mod 安装与更新需要可用的 SteamCMD。

- **已经安装**：在「设置 → 下载与工具」的 SteamCMD 区域点击「选择目录」，选择 steamcmd.exe 所在的目录。
- **需要下载**：保留默认的「SteamCMD ZIP 下载源」，点击「下载并安装」，选择一个空目录。下载后会自动解压、验证，执行 steamcmd.exe 并完成初始化。
- **默认下载源**：[SteamCMD ZIP](https://client-update.steamstatic.com/installer/steamcmd.zip)。已有自定义地址会继续保留，也可以在设置中更换；清空并保存后恢复默认源。

游戏和 SteamCMD 使用独立的下载源。SteamCMD 下载源应指向包含 steamcmd.exe 的 ZIP 安装包。

初始化与 Mod 获取均固定使用 login anonymous 匿名会话，不需要输入 Steam 账号或密码。

### 浏览与管理 Mod

| 入口 | 可以做什么 |
| --- | --- |
| 创意工坊 → 浏览与搜索 | 按关键词搜索、翻页，或输入工坊链接／数字 ID |
| Mod 卡片或详情按钮 | 查看完整名称、来源、版本信息与说明 |
| 工坊中的安装／更新 | 将 Mod 安装到当前选中的游戏 |
| 已安装 Mod → 本地 Mod | 按名称、作者、包 ID 或工坊 ID 筛选 |
| 本地 Mod 的更新／关联 ID | 更新已有 Mod，或关联其工坊来源 |
| 本地 Mod 的删除图标 | 确认目标游戏和实际目录后卸载 |

工坊卡片展示简介、更新时间和安装状态；本地卡片展示作者、支持版本和来源。工坊说明会合并多余空行，长内容可以滚动阅读。

创建下载任务时就会绑定目标游戏。下载途中切换游戏，不会改变该任务的安装位置。卸载只移除对应游戏 Mods 下所选的 Mod，保留 SteamCMD 缓存和游戏存档。

### 启用 Mod 与调整加载顺序

1. 先关闭游戏，进入「已安装 Mod → 加载顺序」。
2. 勾选需要启用的项目。
3. 点击「自动排序」，或使用拖动和上下箭头调整顺序。
4. 查看依赖及兼容性提示，确认后点击「保存顺序」。

游戏本体带有蓝色标识，官方 DLC 带有金色标识。缺失依赖、重复包 ID、不兼容项目和规则循环会阻止保存，需要先处理对应问题。

保存前会自动备份原配置。**使用默认存档目录的多份游戏共享启用清单**；自定义 -savedatafolder 的游戏需要在对应存档配置中管理。配置被其他程序修改后，请重新读取再保存。

### 外观与任务

- 「设置 → 外观主题」可选择浅色、深色或跟随系统，并记住选择。
- 顶部主菜单切换页面，左侧菜单切换当前页面的功能。
- 左侧底部的「任务中心」显示目标路径、进度和错误，失败任务可重试，扫描任务可取消。
- 窗口固定为 900×550 逻辑像素，随 Windows 显示缩放调整；支持最小化和关闭。

### 常见问题

| 问题 | 处理方法 |
| --- | --- |
| 没有找到游戏 | 手动添加包含游戏程序与 Data/Core 的目录，或扫描上级目录 |
| 提示先配置下载源 | 到「下载与工具」填写对应组件的 ZIP 直链并保存 |
| 工坊无法安装或更新 | 检查当前游戏、SteamCMD 路径及网络；查看任务中心的具体错误 |
| 部分工坊条目拒绝访问 | 当前下载使用匿名会话，受权限限制的条目可能无法下载 |
| 搜索失败 | 可尝试输入完整工坊链接或数字 ID |
| 更新或卸载提示文件占用 | 关闭游戏及占用文件的程序后重试 |
| 无法保存加载顺序 | 处理页面列出的依赖问题；若配置已变化，先重新读取 |

应用设置保存在 %LOCALAPPDATA%\RimWorldLauncher。游戏本体、Mod、SteamCMD 缓存和存档并不保存在启动器的程序目录中。

---

## 开发者文档

以下内容面向需要修改源码、运行测试或构建发布包的开发者。

### 技术栈与目录

| 路径 | 职责 |
| --- | --- |
| lib/main.dart | 应用状态、导航、游戏与下载源设置、任务展示 |
| lib/src/ | 主题、菜单动效、工坊、本地 Mod、详情与加载顺序界面 |
| lib/src/rust/ | flutter_rust_bridge 生成的 Dart 绑定 |
| rust/src/ | 游戏发现、配置持久化、下载安装、工坊查询与 Mod 排序 |
| windows/runner/ | Windows 窗口、固定尺寸、拖动及窗口控制通道 |
| test/ | Flutter 界面与交互回归测试 |
| tool/package.ps1 | Windows Release 构建与压缩包校验 |

Flutter 使用 Fluent UI，原生核心由 Rust 实现，通过 flutter_rust_bridge 异步接口和任务事件流连接。SteamCMD 下载串行执行，安装任务携带固定的目标游戏与来源。

### 开发环境

当前使用 Flutter 3.50.0、Dart 3.14.0 和 flutter_rust_bridge 2.12.0。Windows 构建还需要：

- Rust 的 Windows x64 MSVC 工具链；
- 包含桌面 C++、CMake 和 Windows SDK 组件的 Visual Studio；
- 可从终端调用的 flutter 和 cargo。

生成的桥接代码已包含在源码中。常规构建不需要重新生成绑定。

### 本地运行与验证

在项目根目录执行：

~~~powershell
flutter pub get
flutter run -d windows
~~~

Windows CMake 会同时构建并复制 Rust DLL。检查改动时执行：

~~~powershell
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
~~~

Rust 常规测试使用临时目录、本地 HTTP 服务和模拟 Steam 库。Flutter 测试覆盖固定窗口、主题、菜单动效、下载源设置与 Mod 管理交互。

以下集成测试默认跳过，按需单独运行：

~~~powershell
cargo test --manifest-path rust/Cargo.toml local_discovery -- --ignored --nocapture
cargo test --manifest-path rust/Cargo.toml live_workshop_lifecycle -- --ignored --nocapture
~~~

local_discovery 只读核对开发机上的特定游戏和 Mod；live_workshop_lifecycle 会联网，默认从内置地址在临时目录中安装 SteamCMD，再通过匿名会话验证公开 Mod 的下载、更新与卸载。可通过 RIMWORLD_STEAMCMD_ZIP_URL 覆盖测试下载源。

### 构建发布包与默认下载源

~~~powershell
.\tool\package.ps1
~~~

脚本在 dist 下生成 Windows x64 ZIP，包含 Flutter 引擎、Rust DLL、VC++ 运行时、资源及本说明文件。发布时应分发整个压缩包。

可通过参数预置两种组件的默认 ZIP 直链：

~~~powershell
.\tool\package.ps1 -GameZipUrl 'https://example.com/rimworld.zip' -SteamcmdZipUrl 'https://example.com/steamcmd.zip'
~~~

以上为地址格式示例，需要替换为实际下载源。对应构建环境变量为 RIMWORLD_GAME_ZIP_URL 和 RIMWORLD_STEAMCMD_ZIP_URL。用户保存的地址优先于发布预设；SteamCMD 未配置地址或发布预设为空时使用内置的 steamstatic 下载地址。游戏 ZIP 源未配置时保留填写入口。

### 修改 Rust 接口

修改 rust/src/api.rs 后，使用 2.12.0 版本的生成器同步两端绑定：

~~~powershell
cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
flutter_rust_bridge_codegen generate
~~~

生成配置位于 flutter_rust_bridge.yaml。接口、生成的 Rust／Dart 文件和对应 DLL 应同步构建，避免版本不匹配。

### 数据与文件边界

- library.json 和 appearance.json 位于 %LOCALAPPDATA%\RimWorldLauncher；开发时可通过 RIMLAUNCHER_DATA 覆盖设置目录。
- Mod 工坊关联记录位于对应 Mod 的 .rimlauncher-source.json。
- Mod 增删改仅作用于目标游戏的 Mods 子目录；更新使用暂存与替换流程，失败保留旧文件。
- 启用与排序写入默认存档目录的 Config/ModsConfig.xml，保留其他字段，并生成 ModsConfig.xml.rimlauncher.bak。
- 排序读取 About.xml 中的依赖、先后关系、强制关系和版本专用规则。
- 设置与下载安装的 ZIP 地址仅接受 HTTP／HTTPS；组件解压后必须通过目录结构验证。

### 界面约束与资源

窗口保持 900×550 逻辑像素，禁用调整大小、最大化和全屏。文字操作按钮为 96×30，图标操作为 30×30，无边框；菜单动画只改变蓝条形状，不缩放文字，也不添加按压或悬停闪烁。

首页配图 assets/colony.png 由 ImageGen 生成，内容为黄昏的边境殖民地、山脉与松林、暖光窗户、通信塔和天空中的星球，无文字或标志。
