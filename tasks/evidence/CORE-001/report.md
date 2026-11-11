# CORE-001 Phase B 执行报告（AUTO-001 · 2026-11-11，本会话 attempt-3）

- 引擎实测版本：`Godot Engine v4.7.2.stable.official.ed1daf0bf`
- 单 Agent 串行完成：本会话未调用子 Agent / fork / 并行工作流 / 后台任务；未读取、未修改 `tasks/APPROVALS.md`；未执行任何 git commit / merge / push / stash / reset / clean。
- 人工批准门禁：调度器声明人工批准记录已核对（HEAD 含 `2086cf9 Human approve CORE-001 Phase B`、`95d4490 Resume CORE-001 under delegated approval`），本 Agent 未读写人工专属批准账本。
- 本报告取代旧 `report.md`（phaseB-2 尝试版）；旧尝试的 L-0/L-1 阻断项在本次已消除：`tools/auto/queue.json` 当前无未提交改动（`git diff --stat` 为空），`icon.svg.import` 已明确列入本票允许清单。

## 1. 改动文件清单（全部为**新建**，零改动任何已跟踪文件）

`git diff --stat` 实测输出为**空**（无任何已跟踪文件被修改）。`git status --porcelain` 中与本票相关的未跟踪新增：

| 文件 | 说明 |
|---|---|
| `project.godot` | 根工程：`config_version=5`、`config/name="Fishing"`、`run/main_scene="res://scenes/main.tscn"`、`config/features=PackedStringArray("4.7")`、`config/icon="res://icon.svg"`、`run/max_fps=30`（SDD-175 可见 30 FPS；无窗口透明/穿透设置，属 UI-001） |
| `icon.svg` | 最小合法占位 SVG（临时素材） |
| `icon.svg.import` | Godot 导入器生成的图标导入参数 |
| `scenes/main.tscn` | 根 `Main`(Node2D) 挂 `game_controller.gd` + 占位 Label |
| `scripts/core/game_controller.gd` | `class_name GameController extends Node`；`_ready` 仅建 GameState 并打印初始化行 |
| `scripts/core/game_state.gd` | `class_name GameState extends RefCounted`；唯一权威数据字段（save_version=1、wallet_gold=0、basket_capacity=10 候选、processed_*_ids 等），零事务逻辑 |
| `scripts/core/fishing_system.gd` | `class_name FishingSystem extends RefCounted`；仅 `enum State` + FSM-001 契约注释，无帧计数计时 |
| `scripts/io/config_loader.gd` / `save_service.gd` / `event_log.gd` | CFG-001/SAVE-001/LOG-001 空骨架 + 契约注释 |
| `scripts/platform/platform_adapter.gd` / `desktop_window.gd`、`scripts/presentation/cat_presenter.gd` | UI-001 空骨架 + 契约注释 |
| `tests/unit/test_core001_smoke.gd` | `extends SceneTree` 冒烟：逐文件 load、主场景实例化断言、GameState 默认值断言，PASS→quit(0)/FAIL→quit(1) |
| `tests/spike/.gdignore` | 空文件；根工程扫描器整目录跳过 `tests/spike/**`（R-02 用户已批准方案） |
| `scripts/**/*.gd.uid`、`tests/unit/*.uid` | Godot 4.7 生成的脚本 UID 伴生文件（位于允许目录内） |

未触碰：`tests/spike/overlay/**` 全部 8 个既有文件（含 3 个 GUI report JSON：`git diff --stat HEAD -- tests/spike/overlay` 为空，已提交且工作区干净）、`docs/`、`tasks/`（除证据目录）、`tools/`、`examples/`、`schemas/`、`.gitignore`、`AGENTS.md`。

## 2. 执行命令与真实退出码

| # | 命令（cwd=仓库根，除注明外） | 退出码 | 结果 |
|---|---|---|---|
| 1 | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_core001_smoke.gd` | **0** | stdout 含 `CORE001 SMOKE PASS` + `CORE001 GameController ready: wallet_gold=0 basket=0 basket_capacity=10`；stderr 仅 2 行引擎文件日志器 `user://logs` 写入失败（见 §2a），`grep -c "SCRIPT ERROR"` = 0。证据：`test-3-smoke.out/.err` |
| 2 | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --quit-after 2`（主场景真实加载 2 帧） | **0** | stdout 含 `CORE001 GameController ready: ...`；`SCRIPT ERROR` 计数 = 0。证据：`test-3-boot.out/.err` |
| 3 | 9× `… --headless --path … --check-only --script res://scripts/.../x.gd`（core×3、io×3、platform×2、presentation×1） | 全部 **0** | 逐脚本语法解析零错误。证据：`test-3-check-only.log`（`exit=0` 计数 = 9） |
| 4 | `HOME=<证据目录>/tmp-home … --headless --path … --script res://tests/unit/test_core001_smoke.gd`（对照复跑） | **0** | stdout 含 `CORE001 SMOKE PASS`；**stderr 为 0 字节**。证据：`test-3-smoke-cleanhome.out/.err` |

## 2a. 关于 stderr 的 `user://logs` ERROR（如实说明，非伪造）

命令 1/2 的 stderr 各含 2 行：`ERROR: Failed to open 'user://logs/godot….log'` / `Failed to open log file for writing: user://logs/godot.log`。这是 DSH 会话沙箱（workspace-write）禁止引擎向工作区外的 `~/Library/Application Support/Godot/…` 写自身日志所致；命令 4 将 `user://` 重定向到证据目录内后 stderr 为 0 字节且退出码仍为 0，证实与工程内容无关。真实用户终端运行不受此沙箱限制。这 2 行是引擎 logger 错误，**不是** `SCRIPT ERROR`，不影响退出码与断言。

## 3. 测试输出摘要（真实输出见对应证据文件）

```
CORE001 SMOKE PASS
CORE001 GameController ready: wallet_gold=0 basket=0 basket_capacity=10
EXIT_CODE=0（smoke）  EXIT_CODE=0（boot --quit-after 2）  check-only 9/9 exit=0
```

## 4. 人工补充要求逐条核对（plan.md §9）

1. 仅骨架，无 FSM/经济/存档/完整 UI 实现——脚本仅 `class_name`+字段+注释 ✅
2. `tests/spike/overlay/**` 原样未动，GUI 报告零覆盖/零回滚（git diff 该路径为空）✅
3. 主工程 `run/max_fps=30`；本票不声称拖动期 60 FPS ✅
4. 真实执行主工程加载 + smoke：退出码 0 **且**输出含 `CORE001 SMOKE PASS` **且** `SCRIPT ERROR` 计数 0 ✅
5. `.gdignore` 隔离生效：本次全部测试日志 grep `spike|overlay_window` 零命中；`.godot/` 缓存零 spike 引用；`.gdignore` 位于 `tests/spike/`（spike 工程根之上），`tests/spike/overlay/project.godot`、`main.tscn` 完好，spike 以 `--path tests/spike/overlay` 独立运行不受影响 ✅
6. 人工批准门禁保留：未读写 `tasks/APPROVALS.md`，未新增任何批准记录；调度器已核对批准记录后才派发本票 ✅

## 5. 覆盖的验收条目

- TASKS.md CORE-001 最小验收「Godot 无语法/导入错误」：§2 命令 1–3 真实退出码 0 + smoke 逐文件 load ✅
- 交付「主场景」：`scenes/main.tscn` + `run/main_scene` 经命令 2 真实加载运行 ✅
- 交付「分层模块」：`scripts/{core,io,platform,presentation}/` 按 ARCHITECTURE §7 落位 ✅
- 交付「headless 自动测试基础」：`tests/unit/test_core001_smoke.gd` + 本 §2 可重复命令 ✅
- ACCEPTANCE_TESTS §1 静态/配置层（项目资源能加载）、§6（每票 headless 通过 + 命令/退出码/日志报告）✅
- SDD-175：`application/run/max_fps=30` 落位，逻辑时钟独立（骨架无帧计数计时）✅
- DEV_LOG R-02（用户裁定）：`.gdignore` 隔离 spike，spike 零改动 ✅
- **未覆盖（不宣称通过）**：T-CONF-01、T-FSM-01、T-TIME-01/02、T-ECO-01～04、T-SAVE-01～03、T-UI-01、T-LOG-01、G-001～005（分属 CFG/FSM/ECO/SAVE/LOG/UI-001）

## 6. 建议 test_cmd（供人工批准后填入 `tools/auto/queue.json`；本 Agent 未写 tools/**）

```text
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --quit-after 2 && /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing -s res://tests/unit/test_core001_smoke.gd
```

两子命令均已在本会话以真实退出码 0 实测（§2 命令 2、1）。

## 7. 遗留风险

- **L-1（环境，非工程）**：若调度器 runner 在 DSH 沙箱内执行 test_cmd，引擎自身 `user://logs` 日志写入会产生 §2a 的 2 行 ERROR（不影响退出码）；runner 若以 stderr 非空判失败会误判——建议 runner 仅按退出码（及 stdout 含 `CORE001 SMOKE PASS`）判定。
- **L-2（提交归属）**：本票全部新增文件未提交，按流程由调度器在检查通过后统一提交；`icon.svg.import`、`*.uid`、`.godot/`（.gitignore 已含）归属由调度器裁定。
- **L-3（骨架基类）**：`PlatformAdapter/DesktopWindow/CatPresenter` 暂继承 RefCounted 占位，UI-001 实现时按窗口/渲染需要再定基类（契约注释已声明）。
- **L-4（参数未变）**：`basket_capacity=10` 仅候选初值、bite_wait 20–60s 未落码（FSM/ECO 票），任何调节仍须用户批准。
- 证据文件：本目录 `test-3-smoke.out/.err`、`test-3-boot.out/.err`、`test-3-check-only.log`、`test-3-smoke-cleanhome.out/.err`、`tmp-home/`（对照复跑的引擎日志落点，4 KB）；旧尝试日志 `test-1.log`、`phaseB-2-test-run.log` 保留未改。

PHASE-B-DONE
