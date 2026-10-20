# 星海尽头

一个人在星海中漂流，降落到荒凉而美丽的星球上，看远山、日落和满天星辰。采用塞尔达式的卡通画风，有简单而好看的明暗，基调是寂寥感。

| 文档 | 内容 |
| --- | --- |
| [docs/方案.md](docs/方案.md) | 总体方案：体验目标、画风、世界结构、技术选型、阶段 |
| [docs/交接-第一阶段.md](docs/交接-第一阶段.md) | 第一阶段（技术小样）的逐步说明书 |
| [docs/第一阶段开发记录.md](docs/第一阶段开发记录.md) | 实现情况、六个机位、性能结果与已知问题 |
| [docs/地形与完整体验.md](docs/地形与完整体验.md) | 三颗星球原型、菜单存档、声音与打包验证 |
| [docs/类地星球完善记录.md](docs/类地星球完善记录.md) | 晨的地形、气候植被、光照与本轮验证 |
| [docs/试玩问题记录.md](docs/试玩问题记录.md) | 用户试玩反馈、已定位的错误与尚未完成的内容 |
| [docs/完整验收记录.md](docs/完整验收记录.md) | 文档需求对应、完整验收命令与交付结果 |
| [docs/卡通模型完善记录.md](docs/卡通模型完善记录.md) | 自绘纹理、树木岩石与遗迹细化、模型和性能检查 |
| [docs/晨地图与第三人称.md](docs/晨地图与第三人称.md) | 晨的全球地形图、小地图、第一／第三人称与地貌扩展 |
| [docs/晨生物群系与音乐.md](docs/晨生物群系与音乐.md) | 最新群系、近景画面、右上角小地图与轻量音乐 |

## 开发方式

本仓库同时在本地 Windows 和 Claude Code 云端会话中开发，两边通过 GitHub 上的 `main` 分支同步。

| | 本地 Windows | Claude 云端会话 |
| --- | --- | --- |
| 环境 | Godot 4.7.2、780M 核显、声卡 | Linux 容器，启动时安装 Godot 4.7.2 与 CPU 软件渲染，没有 GPU 和声卡 |
| 适合 | 试玩、画面与听感确认、性能测量、`tools/*.ps1` 验收与 Windows 打包 | 编写和修改代码、文档，运行无界面检查，截取太空和高空画面 |
| 不能做 | — | 性能结论、地表机位截图、声音与操控确认 |

云端会话在 `claude/` 开头的分支上提交，并通过 Pull Request 合并到 `main`；本地开始工作前先拉取 `main`。云端运行检查的步骤与限制见 [CLAUDE.md](CLAUDE.md)。画面、性能和听感以本地试玩为准。

## 环境要求

- Windows 64 位，Godot **4.7.2** 标准版，放在 `D:\Godot\4.7.2\`。
- 本机为 Ryzen 7 8845H、Radeon 780M 核显、28 GB 内存。
- Visual Studio 2026 保留，仅在需要用 C++ 扩展 Godot 时使用。

## 运行

```powershell
.\tools\Run-Game.ps1
```

默认进入开始菜单，使用桌面分辨率、无边框全屏和垂直同步。首次进入地表时会等待附近碰撞地形生成。Windows 打包版可直接双击 `build/StarSea/StarSea.exe`，无需安装 Godot；分发压缩包为 `build/StarSea-Windows-x64.zip`。

WASD 移动，鼠标环顾，Shift 加速，空格跳跃或上升，Ctrl 下降。F 切换飞行；陆地上离地 2 米以内可以切回步行。T 加速时间，H 显示帮助，F3 显示性能，F12 截图，Esc 打开暂停菜单。

V 切换第一、第三人称；M 展开「晨」的全球地形图，滚轮缩放、拖动平移、点击查询海拔。右上角小地图显示周围地势、群系、玩家朝向与地点。两种地图使用实际地形高度，通过分层设色、等高线和地形阴影表现起伏。

三颗可降落星球分别是「晨」的海岸草原、「烬」的赤色沙丘和「霜」的冰蓝高地。晨包含海岸、草甸、干草地、阔叶林、针叶林、湿地、高山苔原与雪原，并在近地探索时低音量间歇播放原创器乐。菜单提供渲染比例、视野、全屏、垂直同步、总音量、独立音乐音量和鼠标灵敏度设置。旅程可手动保存，退出时自动保存；读取旅程恢复位置、朝向、飞行状态、第一／第三人称与太阳位置。

存档 `journey.cfg`、设置 `settings.cfg` 和截图位于 `%APPDATA%\Godot\app_userdata\StarSea\`。生成音频使用 `python tools/Generate-Audio.py`，运行游戏不依赖 Python。

## 验证

```powershell
.\tools\Test-Acceptance.ps1
```

上述命令依次完成源代码检查、重新打包、地图与视角专项、整球绕行、多地点着陆、声音录制、二十二机位性能与文件一致性检查，结果位于 `test-output/acceptance/`。单项检查仍可分别执行：

```powershell
.\tools\Measure-Shots.ps1
.\tools\Run-Game.ps1 -GameArgs @('--descent=test-output/p1/descent.json')
.\tools\Run-Game.ps1 -GameArgs @('--walk=test-output/p1/walk.json')
.\tools\Check-Godot.ps1 -GodotArgs @('--script','res://scripts/verify/completion_checks.gd','--','--check=completion') -LogPath 'test-output/p2/logs/completion.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--script','res://scripts/verify/surface_checks.gd','--','--check=surfaces') -LogPath 'test-output/p2/logs/surfaces.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--headless','--script','res://scripts/verify/ecology_checks.gd') -LogPath 'test-output/p4/logs/ecology.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--headless','--script','res://scripts/verify/ecology_runtime_checks.gd','--','--check=ecology_runtime') -LogPath 'test-output/p4/logs/ecology-runtime.log'
.\tools\Build-Game.ps1
```

截图与性能测试固定使用 1920 × 1080、关闭垂直同步；验证材料位于 `test-output/`，不进入 Git。测试脚本会检查引擎退出码和原始错误输出，同一时间只允许运行一个 Godot 实例。

文档列出的三阶段功能已实现：三颗可降落星球、背景气态巨星、气候植被、昼夜光照、海面、环境音、菜单、设置、存档与 Windows 打包。本轮交付及自动检查结果见[晨生物群系与音乐](docs/晨生物群系与音乐.md)；画面、听感和手动操作仍以实际试玩确认为准。
