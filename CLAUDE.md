# 星海尽头

Godot 4.7.2（GDScript）单人星球漫游游戏。Godot 项目位于 `game/`。文档都在 `docs/`：入口是 `docs/00-总览.md`，当前进度在 `docs/进度.md`，接下来做什么在 `docs/版本计划.md`。

分工：Claude 负责写计划和规格，并在每个大版本体验后根据反馈写下一版的计划、清理文档；编码交给 GPT 或 Grok（Cursor 命令行 `agent -p` 或 xAI 的 Grok Build `grok -p`），按 `docs/版本计划.md` 写代码、自己测试、自己跑，按 `docs/02-工程约定.md` 第四节自己验证；用户只在大版本发布后体验。云端会话里如果被要求改代码，同样先对照这些文档，不和文档冲突。

文档保持少而集中：规格做完后由 Claude 把长期规则并进 01、02、03 再删除；每一步的记录写在 `docs/记录/`，大版本体验之后清理（见 `docs/02-工程约定.md` 第六节）。不要在 `docs/` 下新建其他文档。

## 开发规则

- 拿不准的做法、业内已有通行做法的东西，先上网检索行业做法和成熟实现，不自己造轮子（见 `docs/02-工程约定.md` 第三节）。
- 注释使用中文，一行只写一条语句。
- 不在代码里留调试残留、临时探针，或者从命令行覆盖画面参数的后门。
- `test-output/`、`build/` 与 `game/.godot/` 不进入 Git。
- 分支只有两个：`main`，以及 AI 开发分支 `ai/wanderer`。所有 AI 都在 `ai/wanderer` 上提交；这个分支不存在时从 `main` 新建。云端会话即使被分配了别的分支名，也先拉取 `ai/wanderer`，改完推回 `ai/wanderer`，不另建长期分支。合并进 `main` 由用户决定。
- 创建 Pull Request 后不要订阅关注它的动态，也不要设定时检查。仓库没有 CI，评审由用户本人完成，订阅只会带来消耗 token 的状态通知。

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
