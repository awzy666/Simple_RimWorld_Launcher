# RimWorld 启动器

使用 Flutter、Fluent UI 和 Rust 开发的简体中文 Windows x64 启动器。

## 使用

将发布 ZIP 完整解压到任意目录，运行同目录的 **rimworld_launcher.exe**。首页自动识别 Steam 和独立目录中的游戏。多份游戏可以通过「首页 → 安装管理」切换；下载任务记录开始时的目标目录。

界面采用标题栏主菜单、左侧子菜单、右侧内容区的布局。顶部切换首页、工坊、Mod 管理和设置，左侧切换当前页面的功能，并提供共享的任务中心。菜单使用无边框样式及选中指示线，操作按钮统一为 96×30 像素，图标操作为 30×30 像素。标题栏的最小化、关闭同样没有边框，标志和空白区域可拖动窗口。

菜单、按钮和 Mod 卡片没有鼠标悬停预选高亮。顶部与左侧子菜单的共享蓝条均先延伸到目标菜单，再收缩至目标长度；快速反向切换时从当前形状连续衔接，Windows 请求减少动画时直接切换。左侧任务中心同样参与蓝条动画。菜单选中背景即时更新，不使用按压闪烁、背景渐变或默认焦点动画；按钮也没有按压变色。键盘焦点保留静态标识。

菜单字体保持固定字重，操作按钮不自动缩放文字，主题也不会因切换页面而重新创建。排序箭头、刷新、详情、移除等图标操作使用无边框样式。

「设置 → 外观主题」可选择浅色、深色或跟随系统，重启后会恢复所选模式。「下载与工具」集中设置 SteamCMD 与游戏 ZIP 下载源，「扫描目录」提供指定目录扫描。

创意工坊与本地 Mod 均使用单列横向卡片，左侧为封面，中间为名称及摘要，右侧统一放置操作。本地卡片展示作者、兼容版本、包 ID 和工坊来源；工坊卡片展示简介、更新时间、工坊 ID 及安装状态。点击卡片信息区或详情按钮可查看完整信息；工坊详情的说明区独立滚动。

窗口外框固定为 900×550 逻辑像素，随 Windows DPI 缩放。标题栏提供最小化和关闭，窗口禁用缩放、最大化及全屏操作。官方 DLC 在加载顺序中显示金色「官方 DLC」标识，游戏本体显示「游戏本体」标识。

- 在「设置 → 下载与工具」选择已有 SteamCMD 目录，或选择空目录从 Valve 安装。
- 在「设置 → 下载与工具 → 游戏 ZIP 下载源」填写并保存直链，再选择空目录安装。安装管理的安装入口使用此处保存的下载源。发布者可在构建时预置游戏源。
- 在「创意工坊」搜索名称，或粘贴 Steam 条目链接／ID。安装和更新通过 SteamCMD 匿名会话下载，再复制到选定游戏的 Mods。
- 在「已安装 Mod」按名称、包 ID 或工坊 ID 搜索。可关联未知来源的本地 Mod、查看详情、更新和卸载。
- 在「已安装 Mod → 加载顺序」勾选启用项目，拖动或用箭头调整顺序，点击「自动排序」后保存。排序读取 About.xml 的依赖、先后关系、强制关系及版本专用规则。缺失依赖、重复包 ID、不兼容项目和规则循环会阻止保存。未声明兼容当前游戏版本的项目会显示提示。
- 任务面板显示目标路径、下载阶段、错误和重试入口。扫描任务支持取消。

应用设置位于 %LOCALAPPDATA%\RimWorldLauncher。Mod 来源记录保存在对应 Mod 的 .rimlauncher-source.json 中。卸载只移除该游戏内所选 Mod。工坊、详情与 SteamCMD 的联网状态分别反馈。

加载顺序写入默认存档目录下的 Config/ModsConfig.xml，使用默认存档目录的各份游戏共享此配置。保存前自动生成 ModsConfig.xml.rimlauncher.bak，并保留配置中的其他字段。关闭游戏后保存。如果配置已被其他程序修改，需要重新读取。自定义 -savedatafolder 的安装应在对应存档配置中管理。

## 构建与验证

开发环境需要 Flutter 3.50、Windows x64 MSVC Rust 工具链和包含桌面 C++、CMake 组件的 Visual Studio。生成的 flutter_rust_bridge 2.12.0 绑定随项目提供，常规构建可直接使用。

~~~powershell
flutter pub get
cargo test --manifest-path rust/Cargo.toml
flutter analyze
flutter test
.\tool\package.ps1
~~~

发布脚本在 dist 下生成可携带的 Windows x64 ZIP，含 Flutter 引擎、Rust DLL、VC++ 运行时和资源。可传入 -GameZipUrl 指定默认游戏源；未配置时由用户在设置中填写。

Rust 自动化测试使用临时目录、本地 HTTP 服务和模拟 Steam 库。两项显式的集成测试可按需单独运行。local_discovery 使用本次开发机的实际版本进行只读核对。live_workshop_lifecycle 会联网、在临时目录初始化全新 SteamCMD 并下载公开 Mod。

~~~powershell
cargo test --manifest-path rust/Cargo.toml local_discovery -- --ignored --nocapture
cargo test --manifest-path rust/Cargo.toml live_workshop_lifecycle -- --ignored --nocapture
~~~

修改 rust/src/api.rs 后，在工程根目录用 flutter_rust_bridge_codegen 2.12.0 的 generate 命令重新生成绑定。

## 首页配图

assets/colony.png 由内置 ImageGen 生成。提示描述为黄昏时的边境殖民地、蓝灰山脉与松林、右侧有暖光窗户和通信塔、天空中有浅色星球，左侧留出深青色空间，宽幅构图，无文字或标志。

