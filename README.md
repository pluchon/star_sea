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

三颗可降落星球分别是「晨」的海岸草原、「烬」的赤色沙丘和「霜」的冰蓝高地。菜单提供渲染比例、视野、全屏、垂直同步、声音和鼠标灵敏度设置。旅程可手动保存，退出时自动保存；读取旅程恢复位置、朝向、飞行状态与太阳位置。

存档 `journey.cfg`、设置 `settings.cfg` 和截图位于 `%APPDATA%\Godot\app_userdata\StarSea\`。生成音频使用 `python tools/Generate-Audio.py`，运行游戏不依赖 Python。

## 验证

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

截图与性能测试固定使用 1920 × 1080、关闭垂直同步；输出位于 `test-output/p1/`，不进入 Git。测试脚本会检查引擎退出码和原始错误输出，同一时间只允许运行一个 Godot 实例。

当前为可运行原型，尚未通过试玩验收。三颗球面地形、气候植被、环境音、菜单和存档已经接入。「晨」新增林木、灌木、花草与地表光照调整；地貌、美术和声音仍需实际试玩评价，已知问题见试玩记录。自动验证只能说明对应检查通过。
