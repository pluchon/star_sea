# 星海尽头

Godot 4.7.2（GDScript）单人星球漫游游戏。总体方案见 `docs/方案.md`，最新交付状态见 README 文档表中的最后一份记录。Godot 项目位于 `game/`。

## 开发规则

- 注释使用中文，一行只写一条语句。
- 不在代码里留调试残留、临时探针，或者从命令行覆盖画面参数的后门。
- `test-output/`、`build/` 与 `game/.godot/` 不进入 Git。

## 云端会话

主要开发环境是 Windows，`tools/*.ps1` 只能在 Windows 上使用。云端环境的启动脚本会安装 `godot`（4.7.2）与 Vulkan 软件渲染（llvmpipe），但没有 GPU 和声卡。

新克隆的仓库没有 `game/.godot/` 缓存，全局 `class_name` 尚未注册。运行任何检查之前先导入一次，否则会出现 `Identifier "DawnBiomes" not declared` 一类的误报：

```bash
godot --headless --path game --import
```

以下检查可在云端运行，报告写入 `test-output/`。是否通过以报告中的 `passed` 为准，不能只看退出码：

```bash
godot --headless --path game --script res://scripts/verify/ecology_checks.gd
godot --headless --path game --script res://scripts/verify/ecology_runtime_checks.gd -- --check=ecology_runtime
godot --headless --path game --script res://scripts/verify/surface_checks.gd -- --check=surfaces
```

截图需要虚拟显示器。太空和高空机位可以出图：

```bash
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game -- --shot=s1_space --out=<输出目录>
```

限制：

- 软件渲染一帧约 340 ms，云端得到的帧时间不能作为性能结论，性能预算只在用户的 780M 上验收。
- 地表机位会在 `verify.gd` 等待地形生成时超过 120 秒而失败，这是渲染太慢，不是代码错误。
- 没有声卡，音频退回空驱动；听感、手感和最终画面由用户在本机确认。
