# 星海尽头

一个人在星海里漂着，找颗荒凉但好看的星球落下去，看看远山、日落和满天星星。画面走塞尔达那种卡通风，明暗简单干净，整体是安静、有点孤独的感觉。

没有敌人，没有任务，也没有指路箭头。

## 现在能玩到什么

三颗能降落的星球，外加一颗挂在天上、带光环的气态巨星「渊」：

- **晨**：海岸和草原，地貌最丰富。从海边沙滩到草甸、干草地、阔叶林、针叶林、湿地，再往上是高山苔原和雪原。出发地附近有一座带火山口湖的火山、从山上流进大海的河、大大小小的湖，海里立着海蚀柱和拱门；远处横着一条带雪峰的主山脉，侧面是一条深近一公里的大峡谷。一个已经消失的文明在这里留下了河畔古城、回声洞、翻过山口的烽火塔链和一座断裂的通天巨塔「天梯」，沿着它们可以走到这个星球的结局。草地上有鹿，天上有鸟，夜里有萤火、月亮，偶尔有极光；天气会在晴、多云和雨之间慢慢变化。在地面附近探索时，会按情境间歇播放轻音乐。
- **烬**：赤色沙丘和台地。
- **霜**：冰蓝色的高地和雪岭。

从太空飞到地面全程不读条，球慢慢变大，最后变成脚下的地。太阳会转，同一个地方能看到白天、黄昏和夜晚。

## 跑起来

```powershell
.\tools\Run-Game.ps1
```

打开后先到开始菜单，默认用桌面分辨率、无边框全屏、垂直同步。第一次落地要等一下附近的碰撞地形生成好。

直接双击 `build/StarSea/StarSea.exe` 即可试玩，压缩包位于 `build/StarSea-Windows-x64.zip`。当前包包含用户提供的音乐，只用于个人游玩，不商用、不公开分发。

### 操作

| 按键 | 作用 |
| --- | --- |
| WASD / 鼠标 | 移动 / 环顾 |
| Shift | 加速 |
| 空格 / Ctrl | 跳跃或上升 / 下降 |
| F | 降落／登船；远处长按 1.2 秒召唤飞船。降落要求离地不超过 40 米、速度低于 30 m/s，并有合适的落点 |
| V | 第一、第三人称切换 |
| M | 打开「晨」的全球地形图：滚轮缩放，拖动平移，点一下能查海拔；可切换立体地球仪，单击插旗、右键拔旗，旗子的方位会显示在屏幕上方 |
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

本地 Windows 与 Claude 云端统一通过 `ai/wanderer` 同步开发改动，是否合并 `main` 由用户决定。

| | 本地 Windows | Claude 云端 |
| --- | --- | --- |
| 环境 | Godot 4.7.2、780M 核显、有声卡 | Linux 容器，开会话时自动装 Godot 4.7.2 和 CPU 软件渲染，没有显卡也没有声卡 |
| 适合干什么 | 试玩，看画面、听声音，测性能，跑 `tools/*.ps1` 验收，打 Windows 包 | 写代码、改文档，跑无界面检查，截太空和高空的画面 |
| 干不了 | — | 测性能、截地表画面、确认声音和手感 |

本地与云端开工前先同步 `ai/wanderer`，不另建长期开发分支。环境和验证限制见 [CLAUDE.md](CLAUDE.md)。

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

它会依次完成源码检查、飞船与全球水系专项、地貌与遗迹构件检查、重新打包、打包素材加载、地图与视角专项、整球绕行、多地点降落、实际声音录制、当前范围内全部固定机位性能测量（`all` 共 56 个），最后核对打包文件。结果位于 `test-output/acceptance/`。默认只验收晨；第一版可玩及合并前使用 `-Scope all`，包含烬和霜。

只想单独跑某一项的话：

```powershell
.\tools\Measure-Shots.ps1
.\tools\Run-Game.ps1 -GameArgs @('--descent=res://../test-output/p1/descent.json')
.\tools\Run-Game.ps1 -GameArgs @('--walk=res://../test-output/p1/walk.json')
.\tools\Check-Godot.ps1 -GodotArgs @('--script','res://scripts/verify/completion_checks.gd','--','--check=completion') -LogPath 'test-output/p2/logs/completion.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--script','res://scripts/verify/surface_checks.gd','--','--check=surfaces') -LogPath 'test-output/p2/logs/surfaces.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--headless','--script','res://scripts/verify/ecology_checks.gd') -LogPath 'test-output/p4/logs/ecology.log'
.\tools\Check-Godot.ps1 -GodotArgs @('--headless','--script','res://scripts/verify/ecology_runtime_checks.gd','--','--check=ecology_runtime') -LogPath 'test-output/p4/logs/ecology-runtime.log'
.\tools\Build-Game.ps1
```

模型和世界数据可重复生成：

```powershell
.\tools\Build-Models.ps1
.\tools\Bake-World.ps1
```

模型工具需要 Blender 4.x；运行游戏不需要 Blender。修改基础地形、火山或水系烘焙规则后，需要重新烘焙水系。

几点注意：

- 截图和测性能固定用 1920 × 1080，并关掉垂直同步。
- 同一时间只能开一个 Godot，测试脚本会检查引擎的退出码和原始错误输出。
- `test-output/` 里的东西不进 Git。

自动检查过了，不等于真的好玩。画面、声音和手感还得靠实际上手玩。

## 文档

文档都在 `docs/`，从 [总览](docs/00-总览.md) 开始读。计划和规格由 Claude 编写，编码会话按 [版本计划](docs/版本计划.md) 实现并自己测试，做完一个大版本就发布给用户体验；当前做到哪里看 [进度](docs/进度.md)。已经做完的规格和记录会删除，需要时从 Git 历史里找。

| 文档 | 讲什么 |
| --- | --- |
| [00 总览](docs/00-总览.md) | 项目是什么、现在在哪里、已定的决定、工作方式 |
| [01 世界观与美术圣经](docs/01-世界观与美术圣经.md) | 故事、三种感觉、建筑语言、配色、尺度、界面与引导、不做的事 |
| [02 工程约定](docs/02-工程约定.md) | 代码结构、不能破坏的规则、自己验证、性能预算、存档、记录、渲染约定 |
| [03 现状与遗留](docs/03-现状与遗留.md) | 游戏里现在有什么、性能基线、已知问题由哪一步处理 |
| [版本计划](docs/版本计划.md) | 当前版本的步骤、范围和完成标准；之后的候选内容 |
| [进度](docs/进度.md) | 当前做到哪里 |
| [10 自动检查](docs/10-自动检查.md) | 卡住检测、摆放和模型检查、通关机器人等，替人先走一遍 |
| [11 地形重塑](docs/11-地形重塑.md) | 晨的侵蚀高度场和要修的问题 |
| [12 主线近景](docs/12-主线近景.md) | 建模标准；重要地点整体建模；卡人、描边、河口、石头 |
| [13 引导与界面](docs/13-引导与界面.md) | 不用箭头的引导；界面留白 |
| [20～23](docs/20-洞穴补全.md) | 洞穴补全、植被动物与飞船、地貌补充、晨的推广（以后的版本） |
