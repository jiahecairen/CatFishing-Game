# UI-001 Phase A 计划 — 临时素材 + 最小 UI/售鱼/拖动（AUTO-001 · Phase A 只读）
- **单 Agent 串行**：禁止启动子 Agent、fork、并行工作流、第二个大型模型。若标准预设仍暴露委派工具，**不要调用**。

> 第 2 行为 AGENTS.md 第 9 行原样引用。Phase A 的本地模型只生成计划，没有运行 Godot 测试或 git 写操作，也未读取/修改 `tasks/APPROVALS.md`。独立审查已修订本计划并将队列白名单与之对齐；审批账本与 runner 门禁未改。当前工单保持 `awaiting_approval`，尚未执行 Phase B。

## 0. Phase A 只读实测记录（真实命令 + 退出码）

| 检查 | 命令/工具 | 退出码 | 结果 |
|---|---|---|---|
| 目录结构 | `ls -la` 项目根/docs/tasks/evidence | 0 | `scripts/{config,core,economy,fishing,io,platform,presentation,save}`、`scenes/main.tscn`、`tests/unit/*` 均存在；`scripts/ui/` **不存在**（`ls scripts/ui` → 1） |
| Godot 版本 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Git 状态 | `git status --porcelain=v1 -b` | 0 | `## main...origin/main [ahead 3]`；脏文件仅调度器自有：`M tasks/evidence/_runner/runner.log`、`M tools/auto/queue.json`、`?? tasks/evidence/_runner/runner.lock`（本会话零触碰，与 SAVE-001 report §6 一致） |
| Git 近史 | `git log --oneline -12` | 0 | HEAD=`25d2a15 Record SAVE-001 automated review status`；SAVE-001 实现 `034c035`+加固 `6f77e5a` 已入库 |
| 工单 | 读 `tasks/TASKS.md` 全文 | — | Phase A 启动快照：UI-001 依赖 SAVE-001+SPIKE-001；队列当时 `status=ready`、`needs_human=true`、`test_cmd=""`；Phase A 完成后调度器将其转为 `awaiting_approval` |
| 证据目录 | `ls tasks/evidence/` | 0 | Phase A 启动快照：UI-001 目录为空；SPIKE/FSM/ECO/SAVE/CORE/CFG 证据齐全 |
| 接口源码 | 读 `scripts/{core,economy,fishing,save,config,platform,presentation}/*.gd`、`scripts/io/*.gd`、`tests/spike/overlay/**`、`tools/auto/runner.py`、`tests/unit/run_save001_checks.py` | 0 | 见 §2/§3 接口结论 |
| Skills | 本会话技能目录加载 `godot-overlay`/`fishing-state-and-save`/`godot-validation` | — | 3 个项目 Skills 均可发现并已加载（AGENTS §5 要求） |

## 1. 目标（Phase B 要交付什么）

在已冻结的 v0.1 边界（SDD V01-W01/W02/E02/S02、W03、SDD-175 及其 2026-11-11 拖动 60 FPS 例外）内，
用**允许范围内**的文件实现桌面 UI 层，完全复用已 Accepted 的 SPIKE-001/FSM-001/ECO-001/SAVE-001 接口：

1. **临时猫+船占位视觉**：占位图形（ColorRect/程序化简单形状），整数像素缩放与一致锚点；不引入正式 AI 美术。
2. **紧凑钓鱼状态**：金币、鱼篓 n/10、FSM 状态名（`FishingStateMachine.state_name`），全部只读自 GameState/服务，UI 不记账。
3. **鱼篓菜单**：最小面板，支持**出售所选**与**出售全部**；sale ID 由 UI 生成、一次意图一个 ID；金币/鱼变化仅在 SAVE-001 持久化门返回 true 后显示（SDD-173、INTERFACES §5/§6）。
4. **桌面拖动/点击**：沿用 GUI 已验收的 SPIKE 技术——polygon 鼠标穿透（多边形内=可交互，外=穿透）、原生拖动 B（`DisplayServer.window_start_drag`，OS 在按下时开始）+ 松手后按 6px 净位移分类点击、mouse-mask 轮询兜底；窗口位置经 GameState.desktop_window → `AtomicSaveService.persist_runtime_checkpoint()` 持久化并重启恢复，safe-area clamp 兜底。
5. **帧率策略**：可见 30 FPS（`project.godot run/max_fps=30` 保持不动）；仅拖动会话内 `Engine.max_fps=60`（运行时属性，无需改工程设置）；松手即恢复 30（DECISION 2026-11-11：即使原生拖动吞掉 release 也必须恢复）。
6. **隐藏/恢复**：窗口隐藏 = `fsm.pause("hidden")` + 立即 `persist_runtime_checkpoint()` + 停止推进有效时钟与绘制（`set_process(false)`）；重新显示 = `resume_if_safe()` + checkpoint 持久化 + 恢复处理。隐藏期间零渔获、零 RNG 消耗（FSM PAUSED tick 零推进已内建；OPEN-001 已裁定）。
7. **保存失败可见态**：任一 `PERSIST_FAILED`/`persist_runtime_checkpoint` 失败 → 常驻、非模态、无系统通知的「存档失败：经济已暂停」横幅；暂停新抛竿/售鱼（保留重试），重试成功才解除；绝不显示未提交收入（V01-S02/T-UI-01）。

明确**不做**（本票）：日志系统（LOG-001）、模拟（SIM-001）、经济/配置/schema 任何改动、正式美术；
多显示器补测、Windows 前移、GameState/FishingSystem/EconomyService/SaveService 骨架源码改动仍不在本票范围。
全屏应用共存纳入 GUI 验收（只观察窗口不遮挡、不抢焦点、不弹系统通知；不读取其他应用内容）。

## 2. 要改动的文件（Phase B 白名单；范围仅含下列文件/目录）

**新建：**

| 文件 | 内容 |
|---|---|
| `scripts/ui/fishing_session.gd` | `class_name FishingSession extends RefCounted`：纯可测运行会话，由 GameController 驱动并发布 UI 状态。启动先校验 `FishSpeciesCatalog.load_catalog(path)` 与 `RuntimeConfig.load_config(path)`，构造 `valid_species_by_id`/`catalog_by_id`，再调用 `AtomicSaveService.load_save(valid_species_by_id, fresh_seed)`。`fresh_seed` 来自 `Crypto.new().generate_random_bytes(16).hex_encode()` 的非身份随机值；不读取设备 ID。仅当失败码为 `NO_VALID_SAVE` 且 `report.main_status == "missing"`、`report.backup_status == "missing"` 时允许新游戏：创建默认 `GameState`、有效空 ledger、初始化 RNG/Clock/FSM/经济服务、安装持久化门并恢复空 ledger，最后 `persist_runtime_checkpoint()` 成功后才开放输入。其他损坏、未来版本、配置错误或初始化错误都保留存档原件并 fail closed，禁止悄悄重置。载入已有存档时按 SAVE-001 的恢复顺序恢复 RNG/Clock，初始化 Economy/FSM，`install_into(...)` 后 `restore_ledger(state, ledger)`，全部成功才开放输入。若返回 `pending_candidate`：校验其与 SETTLEMENT checkpoint/event 一致；从其字段重建 `{ok:true, code:"", catch_event_id, species_id, weight_snapshot, caught_at_clock}` FSM 成功 payload，并将原 `caught_at_utc` 作为独立参数，在安装 SaveService 后、重放前调用 `set_pending_candidate(payload, 原 caught_at_utc)` 恢复内存态；执行 `commit_catch`，仅正常成功或 `ALREADY_APPLIED` 可继续；然后 `ack_settlement(event_id, true)`、清除 pending candidate 并 checkpoint 持久化。此顺序覆盖“事务已落账、ack 前崩溃”，不重抽样。暴露有效时间推进、捕获/售鱼/隐藏恢复/持久化重试和只读 `status_view()`。售鱼 ID 使用 `Crypto.new().generate_random_bytes(16).hex_encode()` nonce 加单调计数器；每个用户意图只分配一次，失败重试复用同 ID。
| `scripts/ui/fishing_status_hud.gd` | 紧凑状态 Label/HBox：`gold`、`basket n/10`、FSM 状态名；存档错误横幅 Label（默认隐藏，非模态）；保存失败重试入口（单一按钮→session 重试 persist）。 |
| `scripts/ui/basket_menu.gd` | 鱼篓面板（默认隐藏，船体点击开合）：鱼种+快照价列表、逐行选中、「出售所选」「出售全部」；提交期间禁用按钮防连击竞态（INTERFACES §5 串行）；仅在结果 `ok && code==""` 或 `ALREADY_APPLIED` 后刷新显示。 |
| `scripts/ui/cat_boat_visual.gd` | 临时猫+船占位视觉（程序化形状/占位纹理，整数缩放）；提供船体全局矩形给穿透多边形与命中区；无任何业务。 |
| `scripts/core/game_controller.gd` | 实现已预留的主协调器：装配 `FishingSession`、连接 HUD/菜单、串行处理输入与服务结果；GameState 仍为唯一经济权威；headless 下禁止窗口副作用和真实 `user://` 写盘。 |
| `scripts/platform/platform_adapter.gd` | 实现平台 API 探测与 macOS 窗口/鼠标/屏幕边界适配，不让业务层直接碰 DisplayServer。 |
| `scripts/platform/desktop_window.gd` | 实现窗口透明/无边框/置顶、polygon 穿透、原生拖动和 release 轮询、拖动 60/恢复 30 FPS、geometry restore/save 和安全区回退。原生拖动在按下时由 OS 接管；6px 只用于拖动后的点击分类，与已验收 spike B 一致，不宣称是“超过 6px 才开始拖”。 |
| `scripts/presentation/cat_presenter.gd` | 实现占位猫船视觉和交互命中几何；素材仍为程序化占位形状。 |
| `scripts/ui/ui_root.gd` | `Control`/`CanvasLayer` 视图容器，只渲染状态和转发信号，不拥有金币、鱼篓或交易账本。 |
| `scenes/main.tscn`（修改） | 保持根 `Main`(Node2D)，根脚本仍为 `res://scripts/core/game_controller.gd`；新增视图节点，由 GameController 装配 HUD/鱼篓面板/猫船。 |
| `tests/unit/test_ui001_ui.gd` | `extends SceneTree` headless：装配/新档安全启动/损坏档拒绝/捕获/售鱼/幂等/待结算重放/隐藏恢复/保存故障/帧率策略/几何持久化矩阵（§5）；成功标记仅 `UI001 UI PASS`，失败标记 `UI001 UI FAIL` 并 quit(1)；IO 仅临时目录 + 故障注入 seam。 |
| `tests/unit/run_ui001_checks.py` | 隔离副本 runner（见 §5），镜像 `run_save001_checks.py`：value-lock、v1 示例锁、schema v2 锁、类名唯一锁（含 `FishingSession` 全局唯一、`SaveService` 仍在 scripts/io 骨架）+ 交付文件齐全 → 临时副本 + 隔离 HOME → 串行 Godot 7 步。 |
| `project.godot`（条件修改） | 仅当 Mac GUI 实测证明运行时透明设置无效时，追加与已验收 spike 相符的七个 `[display]` 窗口设置；第七项 `window/per_pixel_transparency/allowed=true` 已由项目所有者于 2026-11-11 明确批准。保留 `run/max_fps=30` 和现有 main scene；不得添加其它键。该精确文件已列入白名单，仅授权此条件改动。 |

**不修改**（超出范围，零 diff）：`scripts/core/game_state.gd`、`scripts/core/fishing_system.gd`、
`scripts/io/**`、`data/**`、`examples/**`、`schemas/**`、`tools/**`、
`tasks/APPROVALS.md`（Phase B 代码不直接改审批账本；授权记录只经现有审批服务写入）、既有 `scripts/{economy,fishing,save,config}/**`、`tests/spike/**`。

## 3. 接口充分性结论与最小范围变更清单（Phase A 审查结论）

**原始范围 `scenes/** + scripts/ui/** + tests/**` 不足以兑现仓库既有架构。** 主场景协调、平台窗口适配和猫船 Presenter 在现有骨架中已有明确归属；把这些职责复制到 UI 文件会产生重复实现。Phase B 白名单因此精确增加 `scripts/core/game_controller.gd`、`scripts/platform/desktop_window.gd`、`scripts/platform/platform_adapter.gd`、`scripts/presentation/cat_presenter.gd`，以及唯一条件设置文件 `project.godot`。GameState、经济、FSM、存档、配置、IO、schema 仍不可修改。

- GameState 已有 `desktop_window{x,y,width,height,display_hint}`，窗口位置经 `AtomicSaveService.persist_runtime_checkpoint()` 持久化；不需要修改 GameState 或存档服务。
- 捕获和出售走 `EconomyService.commit_catch/sell_fish`；sale ID 由调用方生成；不需要修改经济服务。
- 满篓停抛和隐藏暂停走 `FishingStateMachine` 的现有接口；不需要修改 FSM。
- `run/max_fps=30` 保持；拖动期间用运行时 `Engine.max_fps=60`。仅当 GUI 实测确认主工程透明设置不能生效时才改 `project.godot`。
- GameController、PlatformAdapter、DesktopWindow、CatPresenter 实现在各自已有骨架文件，不在 `scripts/ui/**` 复制职责。

**唯一条件性设置：**

| 编号 | 触发条件 | 精确允许的改动 |
|---|---|---|
| SC-1 | Mac GUI 证实运行时透明设置在主工程不生效；headless 测试不能证明窗口透明 | 仅允许这七个 `[display]` 窗口键：`window/size/viewport_width=220`、`window/size/viewport_height=160`、`window/size/resizable=false`、`window/size/borderless=true`、`window/size/always_on_top=true`、`window/size/transparent=true`、`window/per_pixel_transparency/allowed=true`。第七项经项目所有者于 2026-11-11 明确批准，依据见 `transparency-approval-addendum.md`。保留 `run/max_fps=30` 与现有 main scene，不添加其他键。 |

除 SC-1 外不动态扩权；若实现需要任何额外路径，先停下并报告。队列白名单须与 §2 一致。Phase B 审批只能由现有审批服务写入账本并变更队列状态，不得手工绕过门禁。原 Phase A 审查记录中的“六键”描述反映当时边界；本次有记录的单项批准只扩展为以上第七键，没有扩展文件范围或其他设置。

## 4. 接口与不变量（Phase B 必须保持）

1. **单一权威**：金币/鱼篓/事务 ID 只在 `GameState`；UI/HUD/菜单只读。船体点击不改变任何数值。
2. **持久化后才可见**：金币增加、鱼入篓仅在服务发布（门 true 之后）后刷新；`PERSIST_FAILED`/非 bool 门一律不显示成功（T-UI-01）。
3. **幂等**：同 catch ID/同 sale ID 重试 = `ALREADY_APPLIED`，零重复；UI 连击在意图层去重 + 提交期禁用按钮（单命令串行语义）。sale ID 由随机 nonce 与单调计数器组成，不含设备或用户标识；失败重试复用原 ID。
4. **计时不依赖帧数**：有效秒 = `Time.get_ticks_msec()` 差值；20–60s 等待仍由 FSM 内 RNG 决定；隐藏/暂停/存档错误/满篓零推进零新抛竿（T-TIME-03）。
5. **checkpoint 契约**（SAVE-001 §4.5）：启动/抛竿后、每次 FSM 转换、隐藏/暂停前与恢复后、候选产生/清除后立即 `persist_runtime_checkpoint()`；WAITING 中最多每 5 有效秒一次，不逐帧写盘。
6. **UTC 单次取样**：结算时仅一次 `Time.get_datetime_string_from_system(true)`，校验 19 字符形状后补 `Z`；重启恢复用存档内原 `caught_at_utc`（SAVE-001 review #7）。恢复 pending candidate 时先重建 SaveService 内存态，再重放交易、ack 并清除候选，不得再次抽样。
7. **窗口不变量**：可见 30 FPS；仅拖动会话 60；松手/拖动结束立即回 30；使用 SPIKE B 原生拖动语义（按下时 OS 开始拖动，6px 只做松手后的点击分类）；透明区穿透、命中区（船体+展开面板）接收事件；位置重启恢复 + safe-area clamp；隐藏≠退出。
8. **类名唯一**：`scripts/ui/**` 新脚本不声明与骨架冲突的 class_name（`DesktopWindow/PlatformAdapter/CatPresenter/SaveService` 等保持唯一归属）；`FishingSession` 全局唯一。
9. **CORE smoke 兼容**：`scenes/main.tscn` 根保持 Node2D 且名为 `Main`；`ui_root._ready` 在 headless（`DisplayServer.get_name()=="headless"`）跳过窗口/写盘副作用，保证 `test_core001_smoke.gd` 实例化场景仍 PASS。
10. **数值锁**：20/60/30/10、鱼价/权重与 `data/`↔`examples/` 一致性由新 runner 逐值锁定；`schemas/game-save.schema.json` v2 与 v1 示例逐值不变。
11. 不写真实 `user://`：自动化测试仅隔离副本 + 隔离 HOME + 临时目录；GUI 验收按 §5.3 用显式隔离 HOME。

## 5. 测试计划（精确命令 + 预期退出码）

### 5.1 主自动验收命令（建议调度器写入队列 `test_cmd`）

```bash
python3 -B tests/unit/run_ui001_checks.py        # 期望退出码 0
```

runner 在系统临时目录复制工程（排除 `.git/.godot/__pycache__/*.pyc/tasks/evidence`），HOME/XDG 入临时目录，
finally 清理；**所有 Godot `--path` 均指向副本，绝不在真实工程路径启动 Godot**。串行步骤：

| 步骤 | 命令（副本内） | 判据 | 预期退出码 |
|---|---|---|---|
| step1 导入先行 | `Godot --headless --path <副本> --editor --quit` | 无 `SCRIPT ERROR` | 0 |
| step2 UI | `Godot --headless --path <副本> --script res://tests/unit/test_ui001_ui.gd` | 退出码 0；stdout 恰含一次 `UI001 UI PASS`、不含 `UI001 UI FAIL`；无 `SCRIPT ERROR` | 0 |
| step3 SAVE 回归 | `... --script res://tests/unit/test_save001_save.gd` | 退出码 0；恰一次 `SAVE001 SAVE PASS`；无 `SCRIPT ERROR` | 0 |
| step4 ECO 回归 | `... --script res://tests/unit/test_eco001_economy.gd` | 退出码 0；恰一次 `ECO001 ECONOMY PASS`；无 `SCRIPT ERROR` | 0 |
| step5 FSM 回归 | `... --script res://tests/unit/test_fsm001_fsm.gd` | 退出码 0；恰一次 `FSM001 FSM PASS`；无 `SCRIPT ERROR` | 0 |
| step6 CORE 回归 | `... --script res://tests/unit/test_core001_smoke.gd` | 退出码 0；恰一次 `CORE001 SMOKE PASS`；无 `SCRIPT ERROR` | 0 |
| step7 CFG 回归 | `... --script res://tests/unit/test_cfg001_config.gd` | 退出码 0；恰一次 `CFG001 CONFIG PASS`；无 `SCRIPT ERROR` | 0 |

前置（Python 标准库，任一失败即整票红）：交付文件齐全；value-lock（data==examples、20/60/30/10、鱼价/权重）；
v1 示例逐值不变；schema v2 13 必需键 + `additionalProperties:false` + `const 2`；class_name 唯一锁。
每个子进程必须合并检查 stdout/stderr，并单独验证退出码、精确 PASS 标记（恰一次）、对应 FAIL 标记（必须不存在）及 `SCRIPT ERROR`（必须不存在）；不得靠后续成功进程覆盖前一步失败。导入步骤完整结束前不运行脚本。任一步失败 → runner 打印 `UI001 RUNNER FAIL` 并退出 1；禁止改断言造 pass（AGENTS/ACCEPTANCE §6）。

### 5.2 test_ui001_ui.gd 用例矩阵（headless，纯 session + seam）

| 用例 | 断言要点 | 验收映射 |
|---|---|---|
| U-0 | 新档与已有档启动：仅 main/backup 都 missing 才初始化空 GameState/ledger；首次 checkpoint 成功前不开放输入；损坏/未来版本/config 错误 fail closed 且原文件不变；逐字段断言 SAVE-001 §4.5 初始化顺序 | SAVE-001 R-5、V01-S02 |
| U-1 | 固定 seed + 虚拟秒推进：CASTING→…→SETTLEMENT→候选→`commit_catch` 成功 → 磁盘文档含鱼实例、内存 basket=1；重复 settle 重试 = `ALREADY_APPLIED` 不双鱼 | V01-F01/F02、T-ECO-02 |
| U-1R | 从含 pending candidate 的 SETTLEMENT 存档重启；断言先重建 `set_pending_candidate`，再 replay/ack/clear/checkpoint；覆盖事务已提交但 ack 前崩溃，不重复加鱼、不重抽样 | SAVE-001 pending-candidate crash recovery |
| U-2 | 售所选：选 2 实例同 `sale_id` 提交 → 金币=两次快照价和、basket 减 2；重试同 ID → `ALREADY_APPLIED`、金币再不变；售全部 → 清空且容量恢复 | V01-E02、T-ECO-01/03/04 |
| U-3 | 满篓：basket=10 → `request_cast` 返回 BASKET_FULL、RNG 态不变、`status_view()` 显示满篓提示 | V01-E01、T-ECO-01 |
| U-4 | 保存故障：武装 `rename` 故障 → 售鱼返回 `PERSIST_FAILED`、`save_error=true`、横幅状态、金币不变、新抛竿被 session 暂停；解除+重试成功 → 横幅清除、状态完整 | V01-S02、T-SAVE-02、T-UI-01 |
| U-5 | 隐藏/恢复：计时态 hide → `pause` + checkpoint 落盘（checkpoint=暂停前活动态，schema 4 键）；隐藏期间 `tick_real_seconds` 零推进零 RNG；show → `resume_if_safe` 续跑；重启从 checkpoint 续 | OPEN-001、T-TIME-03 |
| U-6 | 帧率策略：session 状态机断言 idle→30、dragging→60、drag_end→30（即使模拟 release 事件丢失路径也回 30）；`Engine.max_fps` 读取与设置分离 | SDD-175 + 2026-11-11 例外 |
| U-7 | 窗口几何：拖动结束更新 `state.desktop_window` → `persist_runtime_checkpoint` → 重载 save → 几何逐字段一致；坏几何值走 clamp 默认（spike 语义） | V01-W02、T-SAVE-01 |
| U-8 | 价格快照：目录价不变时实例显示 `sale_price_at_catch`；售鱼金额与快照和一致 | 委托裁定 `sale_price_at_catch` |

### 5.3 Mac GUI 人工验收清单（`needs_human=true`；队列记录 + `tasks/evidence/UI-001/` 留存截图/日志）

启动（隔离存档 HOME，避免动真实 user://）：

```bash
HOME="$(mktemp -d)/ui001-gui-home" /Applications/Godot.app/Contents/MacOS/Godot --path /Users/rain/DevGame/Fishing
# 期望：正常启动 GUI 进程；记录退出码（人工退出应为 0，崩溃判红）
```

| 编号 | 步骤 | 通过判据（人工记录） | 映射 |
|---|---|---|---|
| G-UI-1 | 窗口后置一 Finder/浏览器 | 透明区点击落到下方应用；船体/面板可点击 | G-001、V01-W01 |
| G-UI-2 | 轻点船体 vs 原生拖动 | 轻点开合菜单；原生拖动在按下时由 OS 开始；6px 只用于松手后的点击分类，不代表拖动启动阈值；松手即停、位置重启恢复 | G-002、V01-W02、SPIKE B |
| G-UI-3 | 面板售所选/售全部 | 金币仅在提交后增加；重复点击不双币；满篓提示轻量不轰炸 | V01-E02、G-005 |
| G-UI-4 | 隐藏窗口 60s 再显示 | 隐藏期无渔获增长；显示后从 checkpoint 继续；横幅/状态恢复 | OPEN-001、G-004 |
| G-UI-5 | 可见时观察/记录 FPS | 常态 ≈30（允许系统调度误差，记录滑窗样本）；仅拖动期间 60；松手回 30 | SDD-175 例外 |
| G-UI-6 | 保存失败注入（GUI 会话临时把 GUI 运行 HOME 的存档目录设为只读一次） | 非模态红色横幅持续可见、无系统通知；售鱼暂停；恢复权限后重试成功清除 | T-UI-01 |
| G-UI-7 | Retina 缩放检查 | 无错位/整块不透明矩形 | G-003（多显示器仍 NOT RUN，如实记录） |
| G-UI-8 | 打开全屏应用并观察 | 游戏窗口不遮挡全屏内容、不抢焦点、不触发系统通知；不读取其他应用内容 | SDD v0.1 桌面共存要求 |

GUI 未测项一律记 NOT RUN，禁止记 PASS（godot-overlay §7）。

## 6. 风险与回滚

| ID | 风险 | 缓解/处置 |
|---|---|---|
| R-U1 | 运行时置透明/无边框对**主窗口**是否生效未经 GUI 证实（spike 验收基于其工程 `[display]` 设置） | Phase B 先 GUI 早检；失败即停并提 SC-1 最小 `project.godot` 扩权（§3），**不静默降级**（godot-overlay §7） |
| R-U2 | 原生拖动 B 吞 release → 60 FPS 无法经事件恢复 | 沿用 spike mouse-mask 轮询兜底；U-6 锁定该路径 |
| R-U3 | 鱼篓面板展开区在穿透多边形外 → 点击穿透丢事件 | 面板开合动态更新 `mouse_passthrough_polygon`（面板矩形并入多边形）；G-UI-1/3 实测 |
| R-U4 | 修改 `scenes/main.tscn` 破坏 CORE smoke（根须 Node2D "Main"）| 根节点类型/名保持；`ui_root._ready` headless 短路；step6 回归把关 |
| R-U5 | UI 写盘触碰真实 `user://` | 测试全隔离副本/临时目录；GUI 验收用 `mktemp` HOME；真实存档零触碰 |
| R-U6 | 用户常驻 Godot 编辑器占用主工程（历史 CORE-001 记录） | 自动化绝不以真实工程为 `--path`（step 全在副本）；GUI 验收属人工授权的一次性可见运行 |
| R-U7 | SAVE-001 目前 `in_review`（队列），其 API 若被验收回炉，UI 接线漂移 | UI 测试按 SAVE-001 §4.5 蓝图装配并逐步断言；SAVE-001 返修则重跑 step3 与 U-0；不在 UI 票内改存档层 |
| R-U8 | sale ID 竞态/双击双意图 | 意图层去重 + 提交期禁用按钮 + 会话计数器 ID；U-2 重试断言 |
| R-U9 | 5s checkpoint IO | WAITING 有界写盘（≤1 次/5 有效秒）；Phase B 报告量化 IO 次数 |
| R-U10 | 范围误扩（骨架文件"顺手"实现） | Phase B 按 `git diff --name-only` 对照 §2 清单逐文件核对；越界即 BLOCKED 上报 |

**回滚**：Phase B 单一 commit；`git revert <UI-001 commit>` 即整体撤销（全部为新增文件 + `scenes/main.tscn`
还原）。无 schema/数据/经济改动 ⇒ 无数据迁移风险。测试临时目录由 runner `finally` 清理；不涉及网络/远端/用户文件。

## 7. 验收条目映射（工单摘要 → 本计划）

| 工单要求 | 计划条目 |
|---|---|
| 临时猫+船视觉 | §1.1 + `cat_boat_visual.gd`（§2） |
| 紧凑状态（金币/篓/FSM 态） | §1.2 + `fishing_status_hud.gd` |
| 鱼篓菜单售所选/全部 | §1.3、U-2、G-UI-3 |
| 桌面拖动/点击 | §1.4、§4.7、G-UI-2（SPIKE B 原生拖动，6px 用于点击分类） |
| GameState 唯一权威；durable commit 后才显示经济成功 | §4.1/§4.2、U-1/U-2/U-4 |
| 新档 fail-closed 与待结算崩溃恢复 | §2、U-0/U-1R |
| 可见 30 FPS / 仅拖动 60 FPS | §4.7、U-6、G-UI-5 |
| polygon 穿透、窗口位置持久化 | §1.4、G-UI-1/2、U-7、R-U3 |
| 隐藏/恢复 checkpoint；可见非模态保存失败态 | §1.6/1.7、U-4/U-5、G-UI-4/6 |
| 全屏共存检查 | §1 明确范围、G-UI-8 |
| 占位素材；不改经济、配置、schema；不做日志与模拟 | §1、§2 零 diff 清单、§5 前置锁 |
| 最小路径白名单与唯一条件设置 | §2、§3 |
| 隔离副本 runner：先导入、精确 PASS 标记、无脚本错误和相关回归 | §5.1 |
| Mac GUI 验收：透明/穿透/拖动/售鱼/隐藏显示/FPS | §5.3 G-UI-1…8 |
| 保留审批账本与 runner 门禁 | Phase B 实现不改账本或 runner；授权记录由现有审批服务提交；`needs_human=true` 保持 |

## 8. Phase B 交接（供审查者）

1. 独立审查已核对白名单与 SC-1；由既有审批服务记录批准及测试命令，禁止直接改审批账本或绕过 Runner check。
2. 批准命令为 `python3 -B tests/unit/run_ui001_checks.py`（`needs_human=true` 保持，GUI 项需证据）。
3. 实现顺序建议：`fishing_session.gd`+`test_ui001_ui.gd`（headless 先绿）→ UI 场景/控制器 → `run_ui001_checks.py` → GUI 清单。
4. 证据归档至 `tasks/evidence/UI-001/`（plan/review/report/测试日志/GUI 截图与验收矩阵）。

PHASE-A-DONE
