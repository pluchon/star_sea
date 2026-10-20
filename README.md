# 星海尽头

一个人在星海里漂着，找颗荒凉但好看的星球落下去，看看远山、日落和满天星星。画面走塞尔达那种卡通风，明暗简单干净，整体是安静、有点孤独的感觉。

没有敌人，没有任务，也没有指路箭头。

## 现在能玩到什么

三颗能降落的星球，外加一颗挂在天上、带光环的气态巨星「渊」：

- **晨**：海岸和草原，地貌最丰富。从海边沙滩到草甸、干草地、阔叶林、针叶林、湿地，再往上是高山苔原和雪原。在地面附近探索时，会时不时响起一段很轻的原创配乐。
- **烬**：赤色沙丘和台地。
- **霜**：冰蓝色的高地和雪岭。

从太空飞到地面全程不读条，球慢慢变大，最后变成脚下的地。太阳会转，同一个地方能看到白天、黄昏和夜晚。

## 跑起来

```powershell
.\tools\Run-Game.ps1
```

打开后先到开始菜单，默认用桌面分辨率、无边框全屏、垂直同步。第一次落地要等一下附近的碰撞地形生成好。

不想装 Godot 的话，直接双击打包好的 `build/StarSea/StarSea.exe`，要分享给别人就发 `build/StarSea-Windows-x64.zip`。

### 操作

| 按键 | 作用 |
| --- | --- |
| WASD / 鼠标 | 移动 / 环顾 |
| Shift | 加速 |
| 空格 / Ctrl | 跳跃或上升 / 下降 |
| F | 切换飞行；在陆地上离地 2 米以内能切回步行 |
| V | 第一、第三人称切换 |
| M | 打开「晨」的全球地形图：滚轮缩放，拖动平移，点一下能查海拔 |
| T | 时间加速 |
| H / F3 | 帮助 / 性能面板 |
| F12 | 截图 |
| Esc | 暂停菜单 |

右上角的小地图会显示周围地势、所在群系、你的朝向和附近地点。大地图和小地图都是按真实地形高度画的，用分层设色、等高线和阴影表现高低起伏。

### 设置和存档

菜单里能调渲染比例、视野、全屏、垂直同步、总音量、音乐音量和鼠标灵敏度。

旅程可以手动存，退出时也会自动存一次。读档会恢复位置、朝向、是否在飞、第几人称，还有太阳的位置。

存档 `journey.cfg`、设置 `settings.cfg` 和截图都在 `%APPDATA%\Godot\app_userdata\StarSea\`。

## 开发方式

这个仓库两边一起开发：本地 Windows，加上 Claude Code 的云端会话，中间通过 GitHub 的 `main` 分支同步。

| | 本地 Windows | Claude 云端 |
| --- | --- | --- |
| 环境 | Godot 4.7.2、780M 核显、有声卡 | Linux 容器，开会话时自动装 Godot 4.7.2 和 CPU 软件渲染，没有显卡也没有声卡 |
| 适合干什么 | 试玩，看画面、听声音，测性能，跑 `tools/*.ps1` 验收，打 Windows 包 | 写代码、改文档，跑无界面检查，截太空和高空的画面 |
| 干不了 | — | 测性能、截地表画面、确认声音和手感 |

云端的改动提交在 `claude/` 开头的分支上，走 Pull Request 合进 `main`。所以本地开工前记得先拉一下 `main`。云端怎么跑检查、有哪些坑，写在 [CLAUDE.md](CLAUDE.md) 里。

画面好不好看、跑得流不流畅、声音对不对，最后都以本地实际玩的感受为准。

### 本地环境

- Windows 64 位，Godot **4.7.2** 标准版，装在 `D:\Godot\4.7.2\`。
- 机器是 Ryzen 7 8845H、Radeon 780M 核显、28 GB 内存，性能预算都是按这台机器定的。
- Visual Studio 2026 先留着，只有要用 C++ 扩展 Godot 的时候才用得上。
- 音效用 `python tools/Generate-Audio.py` 生成。游戏本身运行不需要 Python。

## 验证

一条命令跑完整套验收：

```powershell
.\tools\Test-Acceptance.ps1
```

它会依次做这些事：源码检查、重新打包、地图和视角专项、沿三颗星球各绕几圈、在多个地点降落、录环境音、22 个固定机位测性能，最后核对打包文件。结果放在 `test-output/acceptance/`。

只想单独跑某一项的话：

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

几点注意：

- 截图和测性能固定用 1920 × 1080，并关掉垂直同步。
- 同一时间只能开一个 Godot，测试脚本会检查引擎的退出码和原始错误输出。
- `test-output/` 里的东西不进 Git。

自动检查过了，不等于真的好玩。画面、声音和手感还得靠实际上手玩。

## 文档

想了解整体思路，先看[方案](docs/方案.md)。晨接下来怎么做，看[晨样板区方案](docs/晨样板区方案.md)。最近一轮做了什么，看[晨的光影与风](docs/晨的光影与风.md)。

其他都是各阶段的过程记录，按时间先后：

| 文档 | 讲什么 |
| --- | --- |
| [交接-第一阶段](docs/交接-第一阶段.md) | 第一阶段技术小样的分步实现说明 |
| [第一阶段开发记录](docs/第一阶段开发记录.md) | 第一阶段做到哪了，6 个机位的性能，已知问题 |
| [地形与完整体验](docs/地形与完整体验.md) | 三颗星球的原型，菜单、存档、声音和打包 |
| [类地星球完善记录](docs/类地星球完善记录.md) | 晨的地形、气候植被和光照 |
| [试玩问题记录](docs/试玩问题记录.md) | 试玩时发现的问题，以及修没修好 |
| [完整验收记录](docs/完整验收记录.md) | 需求逐条对照，完整验收命令和结果 |
| [卡通模型完善记录](docs/卡通模型完善记录.md) | 自绘纹理，树、石头和遗迹的细化 |
| [晨地图与第三人称](docs/晨地图与第三人称.md) | 全球地形图、小地图，第一／第三人称切换 |
| [晨生物群系与音乐](docs/晨生物群系与音乐.md) | 群系、近景画面、小地图位置和背景音乐 |
| [晨样板区方案](docs/晨样板区方案.md) | 把晨做成能玩的类地星球：样板区、分轮计划和验收标准 |
| [晨的光影与风](docs/晨的光影与风.md) | 按时间调色、云影、统一的风和探索者的围巾 |
