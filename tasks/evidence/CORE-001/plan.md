# CORE-001 Phase A 计划（AUTO-001 · 只读规划 · 2026-11-11）
- **单 Agent 串行**：禁止启动子 Agent、fork、并行工作流、第二个大型模型。若标准预设仍暴露委派工具，**不要调用**。

> 本行以上引自 `AGENTS.md` §0，作为已读取项目规则的证明。本票全程由本会话单 Agent 串行完成，未调用任何委派/子 Agent/后台任务工具；除本文件外零写入；未读取、未修改 `tasks/APPROVALS.md`；未执行任何 git 写操作。

## 1. 目标

建立 v0.1 最小 Godot 4 工程与分层模块骨架，并给出可重复的 headless 自动测试入口，满足工单最小验收「Godot 无语法/导入错误」：

1. 仓库根新建主 `project.godot`（Godot 4.7.2，可见 30 FPS 项目设置）与占位 `icon.svg`。
2. 按 `docs/ARCHITECTURE.md` §7 建议布局建立**最小骨架**：`scenes/main.tscn` 主场景 + `scripts/{core,io,platform,presentation}/` 模块骨架。骨架只含 `class_name`、字段与注释，**不实现** FSM 转移、经济事务、存档、日志逻辑（分属 FSM-001 / ECO-001 / SAVE-001 / LOG-001 / CFG-001）。
3. `tests/unit/test_core001_smoke.gd` headless 冒烟测试：加载全部骨架与主场景并实例化，断言 GameState 默认不变量，成功 `quit(0)`、失败 `quit(1)`。
4. 用 `.gdignore` 把已验收的 SPIKE-001 独立工程（`tests/spike/`）从根工程扫描中隔离（AUDIT-001 风险 R-02 的用户已批准方案），spike 本体零改动、仍可独立运行。

明确不做（防止范围蔓延）：不创建 `config/` 或 `data/` 配置文件（CFG-001 范围且不在本票允许清单）；不改 20–60s、30 FPS、容量 10、鱼价、售鱼规则；不实现窗口透明/穿透/拖动（UI-001）；不动 `tests/spike/overlay/**` 既有代码。

## 2. Phase A 只读实测记录（命令 · 退出码 · 事实）

| # | 命令 | 退出码 | 事实 |
|---|---|---|---|
| 1 | `ls -la /Users/rain/DevGame/Fishing` | 0 | 根目录**无** `project.godot`、`scenes/`、`scripts/`、`icon.svg`；有 `docs/ tasks/ tests/ tools/ .dsh/` |
| 2 | `git status --porcelain=v1` | 0 | **预先存在的未提交用户工作**：`M tests/spike/overlay/report/{capability,observed_state,variant_matrix}.json`（GUI 运行证据，diff --stat 共 +1597/-51）；未跟踪 `tasks/evidence/_runner/`（runner 自有，被调度器豁免） |
| 3 | `git log --oneline -15` | 0 | HEAD `2316ce0 Accept overlay spike and authorize CORE-001 planning`；SPIKE-001 系列已验收 |
| 4 | `find … -maxdepth 3`（排除 .git） | 0 | `tests/spike/overlay/` 为**独立 Godot 工程**（自带 project.godot/main.tscn/scripts）；`.dsh/skills/{godot-overlay,fishing-state-and-save,godot-validation}/SKILL.md` 均存在 |
| 5 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| 6 | `Godot --help`（查关键旗标） | 0 | 存在 `-s, --script`、`--check-only`（配合 --script 仅语法解析）、`--quit-after <int>`、`--import`；`--path <dir>` 要求含 project.godot |
| 7 | `head tests/spike/overlay/main.tscn` | 0 | 其 `ext_resource` 引用 `res://scripts/overlay_window.gd` 等**相对 spike 自身根**的路径 → 根工程建立后若不排除，依赖将解析到根 `scripts/` 的缺失文件（嵌套冲突，见风险 R-A） |
| 8 | `grep -c class_name tests/spike/overlay/scripts/*.gd` | 1（无匹配） | spike 脚本无 `class_name`，全局类名无冲突 |
| 9 | 读 `tasks/TASKS.md` `docs/{SDD_v0.1,DECISION_REGISTER,ARCHITECTURE,INTERFACES_AND_DATA,ACCEPTANCE_TESTS,TECH_SPIKE,DEV_LOG,HARNESS_LOCAL_SETUP,REQUIREMENTS_CHANGELOG}.md`、`tools/auto/{runner.py,queue.json}` | 0 | CORE-001 队列项：`status=ready`、`deps=[SPIKE-001(done)]`、`needs_human=false`、`allowed_files=[project.godot, icon.svg, scenes/**, scripts/**, tests/**]`、`test_cmd` 为空待本计划提出；runner `run_test` 以 `cwd=仓库根` shell 执行 test_cmd，**退出码 0 为通过**，`.godot/`、`tasks/evidence/**` 不计入越界 |
| 10 | 读 `examples/runtime_config.json` | 0 | `visible_fps=30, bite_wait 20–60, basket_capacity=10(候选)` |

Skills：`godot-validation`、`fishing-state-and-save` 两个技能已按 AGENTS.md §5 经 skill 工具实际加载并遵守；`godot-overlay` 面向窗口票（UI-001），本票无需。

## 3. Phase B 要改动的文件（全部为新建，严格限于允许清单）

| 文件 | 内容要点 |
|---|---|
| `project.godot` | `config_version=5`；`[application] config/name="Fishing"`、`run/main_scene="res://scenes/main.tscn"`、`config/features=PackedStringArray("4.7")`、`config/icon="res://icon.svg"`、`run/max_fps=30`（SDD-175 可见 30 FPS；拖动期 60 FPS 例外属 UI-001 后续实现，本票不动数值）。不设窗口透明/穿透（UI-001） |
| `icon.svg` | 最小合法占位 SVG（临时素材，AGENTS.md §4），不引入正式美术 |
| `scenes/main.tscn` | format=3；根 `Main`（Node2D）挂 `res://scripts/core/game_controller.gd`，子节点一个占位 Label/ColorRect；不含业务逻辑 |
| `scripts/core/game_controller.gd` | `class_name GameController extends Node`；`_ready` 仅创建 GameState 并打印初始化行；无经济操作 |
| `scripts/core/game_state.gd` | `class_name GameState extends RefCounted`；字段镜像 INTERFACES §3：`save_version=1, revision=0, wallet_gold=0, basket_capacity=10, basket=[], processed_catch_ids=[], processed_sale_ids=[], fishing_checkpoint, desktop_window`；纯数据+注释，事务逻辑归 ECO-001/SAVE-001 |
| `scripts/core/fishing_system.gd` | `class_name FishingSystem extends RefCounted`；仅 `enum State {IDLE,CASTING,WAITING,HOOKED,REELING,SETTLEMENT,PAUSED}` 与契约注释；转移/时钟/RNG 归 FSM-001 |
| `scripts/io/config_loader.gd` / `save_service.gd` / `event_log.gd` | RefCounted 空骨架 + 契约注释（CFG-001/SAVE-001/LOG-001 实现） |
| `scripts/platform/platform_adapter.gd` / `desktop_window.gd`、`scripts/presentation/cat_presenter.gd` | 空骨架 + 契约注释（UI-001 实现）；platform/presentation 不在 headless 自动证实范围（AGENTS.md §4） |
| `tests/spike/.gdignore` | 空文件；使根工程扫描器完全跳过 `tests/spike/**`（R-02 用户已批准方案）。spike 以 `--path tests/spike/overlay` 独立运行时该文件位于其工程根之外，不影响 spike |
| `tests/unit/test_core001_smoke.gd` | `extends SceneTree`，`_initialize()`：① 逐个 `load()` 全部 `.gd` 骨架与 `res://scenes/main.tscn`，任一失败打印 `CORE001 SMOKE FAIL: <step>` 且 `quit(1)`；② 实例化主场景，断言根为 Node2D 且名为 `Main` 并 `root.add_child`；③ 断言 GameState 默认值（`wallet_gold==0`、`basket` 空、`basket_capacity==10`、`save_version==1`）；④ 全部通过打印 `CORE001 SMOKE PASS` 并 `quit(0)` |

禁止改动：`tests/spike/overlay/**` 现有 8 个文件（含 3 个已修改 report JSON——**不得覆盖、不得回滚、不得改写**，属用户 GUI 证据）、`docs/`、`tasks/`、`tools/`、`examples/`、`schemas/`、`.gitignore`、`AGENTS.md`。

## 4. 接口与不变量（Phase B 必须保持）

- `GameState` 是金币/鱼篓/事务 ID 的**唯一权威**；骨架阶段仅默认值，UI/其他模块不得另立第二份账本（ARCHITECTURE §2）。
- `FishingSystem` 纯逻辑、时钟与 RNG 注入（FSM-001 落实）；**禁止**用 `_process(delta)` 帧计数做捕鱼等待；`Engine.max_fps`/`application/run/max_fps=30` 只影响渲染，不参与业务计时。
- 固定业务参数不变：`bite_wait 20–60s`、`visible_fps=30`、`basket_capacity=10`（候选值）、约 3 鱼种；任何调节须用户批准。
- 存档属 SAVE-001：版本字段、原子替换、幂等事务、写成功才发布；本票只留 `save_version/revision/processed_*_ids` 字段形状，不写任何存档实现；存档路径将来必须用 `user://`，不落源码树。
- 非法配置/损坏存档等失败路径属 CFG-001/SAVE-001，本票不得顺手实现或发明默认值。
- 全局类名 `GameController/GameState/FishingSystem/ConfigLoader/SaveService/EventLog/PlatformAdapter/DesktopWindow/CatPresenter` 唯一；spike 无 class_name，隔离后无冲突。

## 5. 精确测试命令与预期退出码

写入 `tools/auto/queue.json` 的 CORE-001 `test_cmd`（runner 以仓库根为 cwd 执行；仅人工在批准时可改队列，本 Agent 不写）：

```text
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --quit-after 2 && /Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing -s res://tests/unit/test_core001_smoke.gd
```

| 步骤 | 命令 | 预期退出码 | 含义 |
|---|---|---|---|
| 1 | `… --headless --path /Users/rain/DevGame/Fishing --quit-after 2` | **0** | 根工程真实启动并跑主场景 2 帧即退出（首次运行自动建 `.godot/` 导入缓存，已被 .gitignore/runner 豁免）；主场景/入口脚本无加载错误 |
| 2 | `… --headless --path /Users/rain/DevGame/Fishing -s res://tests/unit/test_core001_smoke.gd` | **0** | 冒烟断言全过（脚本自身解析失败时 `-s` 无法执行 → 非 0） |
| 任一失败 | 同上 | 非 0（脚本内 FAIL 为 1） | runner 判失败并按其重试策略处理；证据在 `tasks/evidence/CORE-001/test-*.log` |

可选加强（Phase B 若可行则一并执行并记录，不作为门禁）：对每个骨架脚本 `… --headless --path /Users/rain/DevGame/Fishing --check-only --script res://scripts/.../x.gd`（`--check-only` 已在 4.7.2 `--help` 实测存在），预期逐个退出码 0。

Phase B 审查要求（AGENTS.md §3）：报告 `git diff --stat`、新增文件清单、每条命令与退出码、`CORE001 SMOKE PASS` 日志片段、预先存在的 3 个 report JSON 未被触碰的确认；不得伪造测试结果。

## 6. 风险与回滚

| ID | 风险 | 缓解 |
|---|---|---|
| R-A | 根 `scripts/` 建立后，根工程扫描 spike 的 `main.tscn`，其 `res://scripts/overlay_window.gd` 依赖解析到根工程缺失文件 → 导入/加载错误 | `tests/spike/.gdignore` 整目录排除（实测 #7 证实冲突源；R-02 已获用户批准）。步骤 1/2 的 headless 运行会直接暴露该问题（失败即非 0，不静默） |
| R-B | 3 个 report JSON 为用户未提交 GUI 证据且落在 `tests/**` 允许清单内：runner 自动 commit 时可能一并收编 | 不视为主 Agent 改动、不回滚、不覆盖；本计划如实上报，请人工在把工单转 `exec_ready` 前自行先 commit 这 3 个文件或确认随本票收编。Phase B 不得改写其内容 |
| R-C | `.gdignore` 语义依赖：Godot 4 以「含 .gdignore 的目录及其子目录」不扫描；本票把该文件放在 `tests/spike/`（而非 spike 工程根），保证 spike 独立运行时自身扫描不受影响 | spike 复跑属 UI-001/REL-001，本票不重跑 spike（避免其 headless 运行重写 report JSON，即 B 的另一种污染） |
| R-D | 首次 headless 运行在项目根生成 `.godot/` 导入缓存 | `.gitignore` 已含 `.godot/`，runner `ignored()` 亦豁免，无版本库污染 |
| R-E | `-s`/`--quit-after`/`--check-only` 行为与假设不符（4.7.2 较文档更新） | 旗标均已对 4.7.2 `--help` 实测存在（实测 #6）；Phase B 首跑即用真实 test_cmd，失败日志留证据，由 runner 重试或转 blocked，不猜成功 |
| R-F | 骨架过多导致语法错误概率上升（小模型实现） | 每文件 ≤20 行、纯 `class_name`+字段+注释；smoke 逐文件 `load()` 精确定位 FAIL 步骤 |

回滚：本票全部为**新建文件**、零改动现有文件。未 commit 时删除 `project.godot`、`icon.svg`、`scenes/`、`scripts/`、`tests/unit/`、`tests/spike/.gdignore`、`.godot/` 即完全复原；已 commit 时 `git revert` 单提交即可（由用户按其 Git 流程执行；本 Agent 不 commit、不 push）。

## 7. 验收条目映射

| 验收来源 | 条目 | 本票如何满足 |
|---|---|---|
| TASKS.md 行 CORE-001 | 最小验收「Godot 无语法/导入错误」 | §5 两条 headless 命令退出码 0 + 脚本逐文件 load 断言 |
| TASKS.md CORE-001 交付 | 主场景 | `scenes/main.tscn` + 根工程 `run/main_scene` + 步骤 1 真实加载运行 |
| TASKS.md CORE-001 交付 | 分层模块 | `scripts/{core,io,platform,presentation}/` 骨架按 ARCHITECTURE §1/§7 布局落位，契约注释指向后续票 |
| TASKS.md CORE-001 交付 | headless 自动测试基础 | `tests/unit/test_core001_smoke.gd` + queue `test_cmd`；后续票在 `tests/**` 扩展 |
| ACCEPTANCE_TESTS §1 | 静态/配置层（项目资源能加载） | smoke 加载全部脚本与场景；GUI 层不在本票（G-001～005 → UI-001/REL-001） |
| ACCEPTANCE_TESTS §6 | 每张票至少 headless 通过；报告命令/退出码/日志 | §5 精确命令与退出码；Phase B 按 AGENTS.md §3 留证据 |
| SDD V01-W03 / SDD-175 | 可见 30 FPS、逻辑时钟独立 | `application/run/max_fps=30`（不改批准值）；骨架禁止帧计数（§4 不变量） |
| DEV_LOG R-02（用户裁定） | CORE-001 时以 `.gdignore` 隔离 spike | `tests/spike/.gdignore`，spike 零改动 |
| AGENTS.md §2/§6 | 不越 v0.1 范围、不擅改批准参数 | 本票仅骨架；无 config/经济/存档/UI 实现，20–60s/30FPS/10 格不动 |
| 未覆盖（如实声明） | T-CONF-01、T-FSM-01、T-TIME-01/02、T-ECO-01～04、T-SAVE-01～03、T-UI-01、T-LOG-01、G-001～005 | 分属 CFG-001/FSM-001/ECO-001/SAVE-001/LOG-001/UI-001，本票不宣称通过 |

## 8. 状态

Phase A 只读规划完成；建议人工审查后将队列 CORE-001 由 `awaiting_approval` 转 `exec_ready` 并填入 §5 的 `test_cmd`（同时裁定 R-B 的 3 个 report JSON 归属）。无需求变更、无破坏性操作、无高风险决策需上报：spike 隔离方案与主工程落点均有既往用户批准（DEV_LOG R-02、commit `2316ce0`）。

PHASE-A-DONE

## 9. 人工审核补充要求（Phase B 必须遵守）

1. CORE-001 只建立正式 Godot 工程骨架，不得提前实现 FSM、经济、存档及完整桌面 UI。
2. tests/spike/overlay/** 已经人工验收，必须保持原样。不得覆盖此前的 GUI 测试报告。
3. Godot 主工程默认 30 FPS。拖动时动态 60 FPS 属后续 UI 阶段，本票不得声称已实现。
4. 必须真实执行主工程加载和 smoke test。不仅要求退出码为 0，还应确认输出包含 CORE001 SMOKE PASS，并检查无 SCRIPT ERROR。
5. 新建 tests/spike/.gdignore 后，必须确认主工程不会误扫描独立探针，不得破坏探针作为独立 Godot 工程的结构。
6. 保留当前 AUTO-001 人工批准门禁。若 needs_human=false 与实际审批流程冲突，应先报告，不得跳过审批。
