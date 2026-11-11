# SPIKE-001-FIX-002 · Phase A 计划 — 修复 macOS 窗口拖动不跟手（只读规划，未写码）
- **单 Agent 串行**：禁止启动子 Agent、fork、并行工作流、第二个大型模型。若标准预设仍暴露委派工具，**不要调用**。（原样引用 AGENTS.md §0 第 9 行，作为已读取规则证明）

- 工单：SPIKE-001-FIX-002「修复 macOS 窗口拖动不跟手问题」（queue status=ready，deps=AUDIT-001，needs_human=true，allowed_files=`tests/spike/overlay/**`，test_cmd=headless 加载）
- 阶段：Phase A 只读规划。本会话零代码改动；**本文件是 Phase A 唯一写入**。未调用子 Agent/委派/fork/并行工作流/后台任务；未读取 `tasks/APPROVALS.md`；无任何 git 写操作（add/commit/push/stash/reset/clean 均未执行）。
- 上游：SPIKE-001-FIX-001（in_review，commit `6729ca0`）已修复穿透语义（修正 A）与拖动抖动（修正 B：按下冻结 `DisplayServer.mouse_get_position()` 屏幕坐标基准）。本票**在其代码基础上优化，不重做项目**。

## 0. 已读规则与文档（AGENTS.md §1 清单）

已实际阅读并遵守：`AGENTS.md`、`docs/SDD_v0.1.md`（V01-W02 拖动/位置持久化、V01-W03 与 SDD-175 可见 30 FPS 硬约束、§5 拖动阈值）、`docs/DECISION_REGISTER.md`（076→175 FPS 覆盖）、`docs/ACCEPTANCE_TESTS.md`（G-001/G-002/G-004、§6 门禁）、`docs/TECH_SPIKE.md`、`docs/DEV_LOG.md`、`docs/HARNESS_LOCAL_SETUP.md`、`tasks/TASKS.md`（FIX-001 状态记录；TASKS.md 尚无 FIX-002 段落，工单以 `tools/auto/queue.json` brief 为准）、`tests/spike/overlay/README.md` 与全部源码、`tasks/evidence/SPIKE-001-FIX-001/report.md`、`tests/spike/overlay/report/*.json`。项目 Skills `godot-overlay`、`godot-validation` 已加载并遵循。

## 1. 目标

1. 保留现有屏幕坐标手动拖动**方案 A**（FIX-001 修正 B 逻辑），行为与默认值不变。
2. 新增 `DisplayServer.window_start_drag()` **方案 B**（macOS 原生窗口拖动），由窗口服务器以系统级跟踪移动窗口，摆脱引擎帧循环限制。
3. 提供 GUI 内 **A/B 拖动模式热键**（键 4=A，键 5=B，启动默认 A），同一会话内可直接对比手感。
4. 保留 **6px 点击/拖动阈值**：方案 A 语义不变；方案 B 按 §3.2 决策树尽量保留，若原生拖动无法兼容，如实报告并交人工裁定（工单条目 4）。
5. 保留窗口位置保存与重启恢复（`user://spike_window.json` 现有路径不变）。
6. 正式配置维持可见 30 FPS（SDD-175）；提供运行时临时 60 FPS 对照热键（键 7），默认与重启后恒为 30。
7. full/polygon/off 三种穿透变体（键 1/2/3）**零改动**，已通过 GUI 验收的行为不回归。
8. Phase B 运行 Godot headless 自动门禁并如实记录命令/退出码；GUI 流畅性仅能由用户实测判定，不自动宣布通过。

### 1.1 不跟手成因分析（只读证据支撑，供 Phase B 验证）

- 方案 A 的窗口位移由 `Ship` Control 的 `_on_ship_gui_input(InputEventMouseMotion)` 驱动。Godot 按**帧**派发输入事件，`Engine.max_fps=30` 下窗口位置每帧最多更新一次（≈33 ms 台阶），而光标由 macOS 以远高于 30 Hz 的速率移动 → 视觉延迟。
- GUI 实测数据佐证：`observed_state.json`（用户 22:36–22:47 人工运行）最后一次拖动 `last_drag_samples` 共 93 点 / 3.437 s ≈ **26.8 Hz** 更新率，与 30 FPS 上限一致。
- 快速甩动时若光标 33 ms 内移出 Ship 100×60 命中矩形，Control 停止收到 motion 事件，窗口暂停跟随直至光标重入 →「不跟手/被拖住」感。
- 方案 B 把窗口移动交给 macOS 窗口服务器（等效标题栏拖动），不受 Godot 帧率与 Control 命中区限制，预期消除以上两个瓶颈；60 FPS 对照热键用于分离「帧率上限」这一因素的贡献。

## 2. 要改动的文件（全部在 allowed_files `tests/spike/overlay/**` 内）

| 文件 | 改动 |
|---|---|
| `tests/spike/overlay/scripts/overlay_window.gd` | 主要改动：新增拖动模式状态与键 4/5/7；方案 B 分支（§3.2）；B 模式拖动结束兜底与轨迹采样；报告字段扩展（§3.4）。方案 A 与键 1/2/3/9/Q 逻辑不改 |
| `tests/spike/overlay/README.md` | 键位表补 4/5/7；GUI 人工验收矩阵新增 G-002d（A/B 平滑对比）、G-002e（B 模式点击/阈值语义判定）、G-002f（B 拖动后重启位置恢复）、G-004b（60 FPS 对照后必须恢复 30）；§4 记录 B 语义实测结果 |
| `tests/spike/overlay/scripts/capability_probe.gd` | 仅当需要：把 `window_start_drag` 探测值写入 `capability.json` 的改动已存在（FIX-001 已加），本票原则上不改；如 Phase B 需补探测 `Window.get_window_id` 存在性则最小化追加 |
| `tests/spike/overlay/report/*.json` | 不手工编辑；由 Phase B headless 运行自动再生成（覆盖前须先归档现有 GUI 证据，见 §6 风险 3） |
| `project.godot` / `main.tscn` | **不改**：新键全在代码 `_unhandled_input` 处理；30 FPS 由代码 `Engine.max_fps=30` 保持，不新增 max_fps 项目设置 |

禁止：修改 `tools/auto/queue.json`、`tasks/**`（除 AUTO-001 协议规定的本票证据目录写入）、正式游戏代码、审批账本（FIX-001 曾因 queue.json 越界被 FROZEN，教训沿用）。

## 3. 接口与不变量

### 3.1 接口（GDScript 内部，无对外契约）

- `_drag_mode: String`，取值 `"A"`（默认）/ `"B"`；键 4/5 切换，切换瞬间复位 `_drag_pending/_dragging/_native_drag_active`，并 `_log_event("drag_mode:a|b")` + `_update_status()`。
- 键 7：`Engine.max_fps` 在 30↔60 间运行时切换，`_log_event("fps_cap_toggle:30|60")`；启动恒 `Engine.max_fps = 30`；`project.godot` 不写入任何 60 相关配置。
- 方案 B 调用前运行时探测 `ClassDB.class_has_method("DisplayServer", "window_start_drag")`（本机 GUI 实测 capability.json 已证实为 true）；缺失时 `_log_event("drag_b_unsupported")` 并自动按方案 A 行为处理，不静默降级。
- 窗口 ID：优先 `DisplayServer.window_start_drag(get_window().get_window_id())`；若 `Window.get_window_id` 运行时缺失则传 0 并记事件（探测式，与 R-03 一致）。

### 3.2 方案 B 拖动流程（6px 阈值兼容决策树）

- **B-default（先测）**：按下 → `_drag_pending=true`，冻结 `_drag_start_cursor/_drag_start_win`；motion 中位移 ≥6px 时（左键仍按住，符合官方文档「Call this method when handling a mouse button being pressed」的按下处理语境）调用一次 `window_start_drag()`，置 `_native_drag_active=true`，此后**不再**手动设置 `_win.position`（交给 OS）。
- **B-fallback（若 B-default GUI 实测无效果：窗口不跟或跳变）**：按下瞬间立即调用 `window_start_drag()`（OS 接管最平滑），6px 退化为**事后判定**——拖动结束时若窗口净位移 `<6px` 记为点击（`ship_clicks+1`）。此语义差异必须写入 README 矩阵与本票 report 并向人工明确报告（工单条目 4）。
- **B 拖动结束检测**（OS 可能吞掉 release 事件）：`_process` 中当 `_native_drag_active` 且 `Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT == 0` → 记 `native_drag_end`、`_save_position()`、`_write_reports()`；退出兜底沿用既有 `_write_final_reports()` → `_save_position()` 路径，保证重启恢复可用。
- 两子模式由脚本内常量 `DRAG_B_MODE`（"on_threshold" / "on_press"）控制，Phase B 默认 `on_threshold`，GUI 判定后可由人工指示改常量，不改键位。

### 3.3 不变量（不得破坏）

1. 可见 30 FPS 为默认与重启后状态（SDD-175）；60 只存在于单次 GUI 会话运行时对照。
2. full/polygon/off 穿透变体语义、启动默认 polygon、键 1/2/3 行为完全不变（已 GUI 验收）。
3. 方案 A 拖动逻辑（冻结屏幕坐标基准、一次性取整、`last_drag_samples` 采样）逐行保留。
4. 6px 阈值常量 `DRAG_THRESHOLD_PX=6` 不变；A 模式语义不变。
5. 位置持久化路径 `user://spike_window.json`、启动 clamp 安全区逻辑不变；任何拖动模式最终都走 `_save_position()`。
6. 计时一律 `Time.get_ticks_msec()`，禁止帧计数计时；不引入经济/FSM/业务存档。
7. 不触碰正式游戏工程与其他目录；不新增依赖。

### 3.4 报告字段（observed_state/variant_matrix JSON 追加）

`drag_mode`、`window_start_drag_supported`（运行时 ClassDB）、`drag_b_mode`（常量值）、`native_drag_samples`（B 模式期间每帧 `[t_ms, win_x, win_y, mouse_x, mouse_y]`，上限同 400 点）、`fps_cap_default:30`。既有字段语义不变，供 GUI 人工客观核对（自动不判定流畅性）。

## 4. 精确测试命令与预期退出码（Phase B 执行并逐条记录）

| # | 命令 | 预期退出码 | 判据 |
|---|---|---|---|
| T0 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf`（本会话已复核） |
| T1a | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay --check-only --script res://scripts/overlay_window.gd` | 0 | 无 `SCRIPT ERROR` |
| T1b | 同上 `--script res://scripts/capability_probe.gd` | 0 | 同上 |
| T2 | 调度器 test_cmd：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay` | 0 | 脚本自行 quit；无 SCRIPT ERROR |
| T3a/T3b | 同 T2 追加 `--rendering-driver metal` / `--rendering-driver opengl3` | 0 / 0 | 两渲染器可加载 |
| T4 | `pgrep -l Godot` | 1 | 1=无残留进程（预期内） |
| T5 | `python3 -m json.tool` 逐一校验 `report/capability.json`、`report/observed_state.json`、`report/variant_matrix.json` | 0/0/0 | JSON 合法且含 §3.4 新字段 |
| T6 | `git status --porcelain` + `git diff --stat` | 0/0 | 已跟踪改动仅 `tests/spike/overlay/**`；不含 `tools/auto/queue.json` |
| C3-GUI | `/Applications/Godot.app/Contents/MacOS/Godot --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal`（用户人工） | 由用户观察 | README 矩阵：A/B 对比、B 阈值语义、B 后重启恢复、60 对照后恢复 30；**不得自动宣布通过** |

已知噪音（非失败）：代理沙箱下 `user://` 不可写（err=12）与 `user://logs` 告警照旧，退出码不受影响；无 `timeout`/`gtimeout`，需要超时用 FIX-001 已验证的 `perl -e 'alarm shift @ARGV; exec @ARGV or die $!' 180 …` 包装。

## 5. 验收条目映射

| 工单/验收条目 | 计划落点 | 判定方式 |
|---|---|---|
| 条目 1 保留方案 A | §3.3-3 逐行保留 | T1a 语法 + G-001d/G-002a 人工回归 |
| 条目 2 新增方案 B | §3.1/§3.2 | T1a + G-002d 人工 |
| 条目 3 A/B 热键 | 键 4/5，label 显示 `drag=A/B` | G-002d 人工对比 |
| 条目 4 6px 阈值兼容 | §3.2 决策树；不兼容→README/report 明示并交人工 | G-002e 人工 |
| 条目 5 位置保存/恢复 | 现有 `_save_position`/`_restore_position` 不动；B 结束兜底 §3.2 | G-002b/G-002f 人工（`cat ~/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json`） |
| 条目 6/7 30 FPS 正式 + 临时 60 对照 | 默认 30 写死代码；键 7 运行时切换；report 恒含 `max_fps` | T5 读回 30；G-004/G-004b 人工 |
| 条目 8 headless 测试 | §4 T1–T6 真实退出码 | report.md 记录 |
| 条目 9 GUI 流畅性人工 | C3-GUI 矩阵，不自动判定 | 用户实测 |
| G-001a/b/c 穿透回归 | 键 1/2/3 零改动 | 人工回归（已通过，防回归） |
| V01-W02 / SDD-175 | §3.3 不变量 | 代码 diff + T5 + GUI |

## 6. 风险与回滚

| # | 风险 | 处置 |
|---|---|---|
| 1 | `window_start_drag` 在本构建存在（GUI capability.json 已证实），但其在**透明无边框 always_on_top** 窗口上的 macOS 运行时语义未验证：可能不接管、可能引起焦点/遮挡行为变化 | 运行时 ClassDB 探测 + GUI 人工判定；B-default 无效→B-fallback；均无效→按工单条目 4 报告不兼容，保留 A，不静默换方案 |
| 2 | B 模式 release 被 OS 吞掉 → 松手即停/中途保存缺失 | §3.2 mask 轮询兜底 + 退出保存兜底；崩溃时最后一次拖动位置可能不落盘，如实写入 README |
| 3 | T2/T3 headless 运行会**覆盖** `report/*.json`，毁掉工作树中未提交的用户 GUI 证据（22:36–22:47 拖动样本） | Phase B 第一步：把现有 3 份 report JSON 原样归档到 `tasks/evidence/SPIKE-001-FIX-002/pre_phaseB_snapshot/`（AUTO-001 Phase B 证据协议，同 FIX-001 先例），再跑测试 |
| 4 | 忘切回 30 FPS 违反 SDD-175 | 默认 30 写死代码；60 仅运行时热键；report 恒记录 `max_fps`；diff 中不可能出现 60 配置；G-004b 提醒人工确认 |
| 5 | 误改穿透变体或 queue.json 越界 | §2 禁改清单 + T6 范围检查（FIX-001 曾被 FROZEN 的同类风险） |
| 6 | B 模式 OS 拖动把窗口的 click 语义改变（微点击也移动 1–2px） | B-fallback 事后 6px 判定 + 事件流区分 `ship_click` / `native_drag_end`；判定权归人工 |

**回滚**：`git checkout -- tests/spike/overlay/`（HEAD=`417f74d`，含 FIX-001 全部成果，本票改动全部可弃）；本票证据目录由调度器处置；`user://spike_window.json` 为用户数据不删。本会话及 Phase B 均不 commit/push（提交由 AUTO-001 按已批流程执行）。

## 7. Phase A 只读实测记录（真实命令 + 退出码，本会话执行）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| Git 基线 | `git rev-parse HEAD` | 0 | `417f74d70c7bcf76d1274cb56022d4fc555a300d`（"Add SPIKE-001-FIX-002 native drag optimization"，仅改 `tools/auto/queue.json`） |
| 工作树 | `git status --porcelain -b` | 0 | `## main`；已跟踪改动仅 3 个 `tests/spike/overlay/report/*.json`（用户 22:36–22:47 GUI 人工运行证据）；未跟踪仅 `tasks/evidence/_runner/` |
| 近期历史 | `git log --oneline -15` | 0 | `417f74d`→`be73469`（FIX-001 状态）→`6729ca0`（FIX-001 代码）→`00ee38f`（人工批准 FIX-001）→…→`4d8ed4d` 基线；无远端推送记录 |
| 范围核对 | `git diff --stat` | 0 | 仅 `report/capability.json`(+26/−29 区段)、`observed_state.json`、`variant_matrix.json`（各约 +1493 行），全部在 allowed_files 内 |
| 工单 | `tools/auto/queue.json` 读取 FIX-002 条目 | 0 | status=ready；allowed_files=`tests/spike/overlay/**`；test_cmd=headless；needs_human=true；brief 与本计划工单摘要一致 |
| 代码存在性 | 列目录 + 全文读取 `overlay_window.gd`(357 行)、`capability_probe.gd`、`main.tscn`、`project.godot`、`README.md` | 0 | FIX-001 修正 A/B 在位；`window_start_drag` 探测已在 probe 中 |
| GUI 实测证据 | 解析 `observed_state.json`（display_server=macOS, headless=false） | 0 | 74 事件：变体切换 full/polygon/off 多次、17 次拖动、2 次点击、`max_fps=30`；末次拖动 93 样本/3.437 s ≈ **26.8 Hz**（§1.1 延迟证据） |
| 能力探测 | 读取 `capability.json`（GUI 运行产物） | 0 | `display_server_methods.window_start_drag=true`；`mouse_passthrough_mode=false`（不存在，不假设）；safe_area=[0,78,4112,2404] |
| Godot | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| 进程残留 | `pgrep -l Godot` | 1 | 1=无残留（预期） |
| 规则行核对 | `sed -n '9p' AGENTS.md` | 0 | 与本文件第 2 行引用逐字一致 |
| 官方语义 | 抓取 godot master `doc/classes/DisplayServer.xml` 检索 `window_start_drag` | 0 | 「Starts an interactive drag operation … using the current mouse position. Call this method when handling a mouse button being pressed … Implemented on Linux (X11/Wayland), macOS, and Windows.」（https://raw.githubusercontent.com/godotengine/godot/master/doc/classes/DisplayServer.xml） |
| 文件计数 | `find . -type f -not -path './.git/*' \| wc -l` | 0 | 78（Phase A 前后一致，本会话未改仓库任何文件） |

**合规声明**：Phase A 全程只读；除本文件外未创建/修改/删除/移动任何仓库文件（计划文档为工单唯一允许写入）；未调用任何子 Agent/委派/并行工作流/后台任务工具；未读取 `tasks/APPROVALS.md`；无任何 git 写操作；headless 运行刻意**不在 Phase A 执行**——其会覆盖 §6 风险 3 所述未提交人工证据，且属 Phase B 范围。

## 8. 人工批准请求（本计划待批事项）

1. 批准 Phase B 按 §2/§3 实施：键 4/5 A/B 切换、键 7 临时 60 FPS 对照、方案 B 决策树（B-default→B-fallback→如实报告不兼容）。
2. 确认 §6 风险 3 处置：headless 前先把当前 3 份 report JSON 归档到本票证据目录再运行测试。
3. 明确：若两种 B 子模式在 macOS 透明窗口上均不生效，处理为「原生拖动不兼容，保留方案 A + 60 FPS 对照数据交人工」，而非擅自降级穿透/透明需求。

## 9. 人工审核补充要求（Phase B 必须遵守）

以下要求优先于前文存在冲突的实现细节。

1. DisplayServer.window_start_drag() 应优先在 InputEventMouseButton 按下事件中调用。超过 6px 后才调用的实现只能视为实验，不得假定该时机一定有效。
2. 方案 A 保留原有 6px 点击/拖动阈值。方案 B 如果不能保留完全相同的阈值，必须在 README 和测试报告中明确说明，不得静默改变交互语义。
3. 不得因方案 B 测试失败而覆盖或删除方案 A。A/B 模式必须能够独立进行 GUI 测试。
4. Phase B 编码 Agent 不得自行修改 tasks/evidence/**。历史 GUI 报告由用户或已授权调度器备份。代码修改仍严格限于 tests/spike/overlay/**。
5. 额外检查 Input.use_accumulated_input 是否影响方案 A 的拖动响应频率。如需实验，必须保留 30 FPS 正式默认值。
6. 原生拖动是否更流畅、能否保持点击语义、是否正常保存窗口位置，均由人工 GUI 验收。Headless exit=0 不代表这些功能通过。
