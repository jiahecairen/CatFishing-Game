# SPIKE-001-FIX-002 · Phase B 执行报告 — 修复 macOS 窗口拖动不跟手

- 工单：SPIKE-001-FIX-002（AUTO-001 Phase B 执行代理，单会话串行；无子 Agent/委派/fork/并行工作流/后台任务）
- 基线：`git rev-parse HEAD` = `d16e5a3511b5d90f75048977781cbc2e156da2a8`（"Human approve SPIKE-001-FIX-002 Phase B"）
- 依据：`tasks/evidence/SPIKE-001-FIX-002/plan.md`（含 §9 人工审核补充要求，优先于前文冲突细节）
- 本目录本票唯一写入 = 本文件；未读取 `tasks/APPROVALS.md`；无 git add/commit/merge/push/stash/reset/clean。

## 1. 改动文件清单（`git diff --stat` 真实输出，T6b，exit 0）

```
 tests/spike/overlay/README.md                   |  26 ++++
 tests/spike/overlay/report/capability.json      |  11 +-
 tests/spike/overlay/report/observed_state.json  |  35 ++++--
 tests/spike/overlay/report/variant_matrix.json  |  35 ++++--
 tests/spike/overlay/scripts/capability_probe.gd |  17 +++
 tests/spike/overlay/scripts/overlay_window.gd   | 160 +++++++++++++++++++++++-
 6 files changed, 253 insertions(+), 31 deletions(-)
```

全部在 allowed_files `tests/spike/overlay/**` 内；`tools/auto/queue.json`、正式游戏工程、审批账本零改动。
`report/*.json` 非手工编辑，由 Phase B headless 运行自动再生成（见 §3 证据保全说明）。

### 实现要点（与计划条目对应）

- **方案 A 逐行保留（§3.3-3 / §9.3）**：FIX-001 修正 B 逻辑（按下冻结 `DisplayServer.mouse_get_position()`
  屏幕坐标基准、一次性取整、`last_drag_samples`、6px=`DRAG_THRESHOLD_PX`）原样保留，仅在 B 分支前置守卫；
  A/B 在同会话独立可测，B 失败不影响 A（键 4 恒可切回）。
- **方案 B 原生拖动（§3.1/§3.2，§9.1 优先）**：常量 `DRAG_B_MODE` 默认 `"on_press"` —— 在左键**按下事件**中
  调用 `DisplayServer.window_start_drag(get_window().get_window_id())`，此后不再手动设置 `_win.position`；
  `"on_threshold"`（≥6px 后才调用，官方文档语境为按下时处理）作为实验性子模式保留，GUI 人工判定后可由人工指示改常量。
  窗口 ID 走运行时探测：`Window.get_window_id` 缺失时传 0 并记 `drag_b_window_id_fallback:0`。
  `window_start_drag` 缺失时记 `drag_b_unsupported:*` 并自动按方案 A 行为处理，不静默降级。
- **B 拖动结束（§3.2）**：`_process` 中 `Input.get_mouse_button_mask() & MOUSE_BUTTON_MASK_LEFT == 0` 轮询兜底
  （OS 可能吞 release）→ `native_drag_end` + `_save_position()` + `_write_reports()`；退出兜底沿用
  `_write_final_reports()` → `_save_position()`，重启恢复可用（`user://spike_window.json` 路径与 clamp 逻辑不变）。
- **6px 阈值语义（§9.2 明示义务）**：A ＝「位移达 6px 才开始拖动」；B ＝「按下即 OS 接管，结束后按窗口净位移
  事后判定：<6px 记 `ship_click`（ship_clicks+1），≥6px 记拖动」。差异已写入 README §2 矩阵 G-002e 与 §4，
  **非静默变更**；是否符合工单条目 4 由人工裁定。
- **热键（§3.1）**：4=A 模式、5=B 模式（切换瞬间复位 `_drag_pending/_dragging/_native_drag_active`，
  记 `drag_mode:a|b`）、7=`Engine.max_fps` 30↔60 运行时对照（记 `fps_cap_toggle:30|60`；启动恒 30，
  `project.godot` 无任何 60/新配置）、6=`Input.use_accumulated_input` 运行时切换实验（§9.5 额外检查，
  仅运行时，不影响 30 FPS 正式默认）；键 1/2/3/9/Q/Esc 行为零改动。
- **报告字段（§3.4）**：`drag_mode`、`drag_b_mode`、`window_start_drag_supported`、`window_get_window_id_supported`、
  `native_drag_samples`（B 拖动期间每帧 `[t_ms, win_x, win_y, mouse_x, mouse_y]`，上限 400 点/次）、
  `native_drag_sample_count`、`fps_cap_default:30`、`input_accumulated_input_supported/value`；既有字段语义不变。
- **capability_probe.gd 最小化追加（§2 允许项）**：`window_methods.get_window_id` 与
  `input_properties.use_accumulated_input` + 当前值探测（§3.1/§9.5 证据的机读落点）。
- **§9.5 检查结论（真实探测）**：本构建 `Input.use_accumulated_input` 存在且默认 = **true**（motion 事件按帧合并），
  证实 §1.1 分析：30 FPS 下方案 A 窗口位移每帧最多更新一次（GUI 实测 ≈26.8 Hz 被帧率封顶）；键 6 可关闭做对照。
- **计划外必要修正（真实测试驱动，非扩权）**：首版用 `ClassDB.class_has_property()`，T1a/T1b 真实输出
  `SCRIPT ERROR: Parse Error: Static function "class_has_property()" not found in base "GDScriptNativeClass"`
  → 按「绝不调用未证实 API」约束改为 `Input.get_property_list()` 扫描 + `Input.get/set` 字符串访问
  （编译期不依赖属性存在性），复跑 T1 后无 SCRIPT ERROR。其余实现与已批计划一致。

## 2. 执行命令与真实退出码

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| T0 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | **0** | `4.7.2.stable.official.ed1daf0bf`（与计划预期一致） |
| T1a⁽¹⁾ | `… --headless --path tests/spike/overlay --check-only --script res://scripts/overlay_window.gd` | 0⁽²⁾ | **首跑判据失败**：`SCRIPT ERROR: Parse Error: Static function "class_has_property()" not found`（脚本未加载）|
| T1a⁽¹⁾ | 同上（修复后复跑） | **0** | 无 `SCRIPT ERROR` |
| T1b⁽¹⁾ | `… --check-only --script res://scripts/capability_probe.gd` | 0⁽²⁾ | **首跑判据失败**：同类 `class_has_property` SCRIPT ERROR（3 处）|
| T1b⁽¹⁾ | 同上（修复后复跑） | **0** | 无 `SCRIPT ERROR` |
| T2 | 调度器 test_cmd：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay` | **0** | 脚本自行 quit；无 SCRIPT ERROR（perl alarm 180 包装未触发）|
| T3a | 同 T2 追加 `--rendering-driver metal` | **0** | 无 SCRIPT ERROR / 无 Failed to load |
| T3b | 同 T2 追加 `--rendering-driver opengl3` | **0** | 同上 |
| T4 | `pgrep -l Godot` | **1** | 1 = 无残留进程（预期内）|
| T5 | `python3 -m json.tool` × `report/capability.json` / `observed_state.json` / `variant_matrix.json` | **0 / 0 / 0** | JSON 合法，§3.4 新字段齐全（见 §3）|
| T6 | `git status --porcelain`；`git diff --stat` | **0 / 0** | 已跟踪改动仅 6 个 `tests/spike/overlay/**` 文件；不含 `tools/auto/queue.json`；未跟踪仅 `tasks/evidence/**`（AUTO-001 证据协议目录）|

⁽¹⁾ T1 判据 = 计划 §4「无 `SCRIPT ERROR`」；首跑虽 exit 0 但含 SCRIPT ERROR，判**失败**并修复后复跑，未伪造退出码。
⁽²⁾ 已知噪音（计划 §4 预判，非失败）：沙箱下 `Failed to open user://logs/…log` 与 `cannot write user://spike_window.json (err=12)`
告警照旧，不影响退出码；`user://spike_window.json` 为用户数据，本会话未删改。

## 3. 测试输出摘要与证据保全

- **T2/T3 运行产物**（headless，`display_server=headless`，`ts_utc≈2026-11-11 00:09`）：
  - `capability.json`：`window_start_drag=true`、`window_methods.get_window_id=true`、
    `input_properties.use_accumulated_input=true`、当前值 `true`。
  - `observed_state.json` / `variant_matrix.json`：`headless=true`、`max_fps=30`、`fps_cap_default=30`、
    `drag_mode=A`（启动默认 A ✓）、`drag_b_mode=on_press`、`window_start_drag_supported=true`、
    `window_get_window_id_supported=true`、§3.4 新字段 `missing=[]`、events=4（ready/variant:polygon/…）。
  - headless 仅证明脚本/场景可无错加载与属性探测，**不构成任何 GUI 语义通过证据**。
- **证据保全核对（计划 §6 风险 3 / §9.4）**：本会话未向 `tests/spike/overlay/report/` 手工写任何字节；覆盖发生且仅覆盖
  已提交的 headless 版本（HEAD 内 4 events 版）。用户 22:36–22:47 GUI 人工拖动证据（headless=false、74 事件、93 样本）
  已由调度器保全于备份提交 `d535e55 "On main: Preserve FIX-002 GUI reports"`（本会话只读验证其内容仍在）。
  若该备份缺失，headless 覆盖将销毁人工证据——实际未发生损失。

## 4. 覆盖的验收条目

| 条目 | 状态 | 依据 |
|---|---|---|
| 1 保留方案 A | 代码完成 | diff 中 A 路径逐行保留（仅 B 守卫前置）；T1a/T2 exit 0 |
| 2 新增方案 B（原生拖动） | 代码完成 | §9.1 on_press 主路径 + on_threshold 实验子模式；运行时探测兜底齐全 |
| 3 A/B 热键 | 代码完成 | 键 4/5，Label 显示 `drag=A/B`，事件 `drag_mode:a|b` |
| 4 6px 阈值兼容 | **语义差异如实报告，待人工裁定** | B 为事后净位移判定（非 A 的达阈才动）；README G-002e + §4 + 本报告明示 |
| 5 位置保存/重启恢复 | 代码完成 | B 结束与退出均走 `_save_position()`；路径/clamp 不变；GUI 判定 G-002f |
| 6/7 30 FPS 正式 + 60 对照 | 代码完成 | 启动恒 30（报告实测 `max_fps=30`、`fps_cap_default=30`）；键 7 仅运行时；project.godot 无 60 配置 |
| 8 headless 测试 | **通过（T0–T6 真实 exit 码）** | 本表 §2；仅证明可加载/语法/探测，不判定 GUI 手感 |
| 9 GUI 流畅性 | **未判定（本票不可自动判定）** | 待用户按 README 矩阵 C3-GUI 实测 G-002d/e/f、G-004b |
| G-001a/b/c 穿透回归 | 未回归 | 键 1/2/3 与 `_set_variant` 零改动（diff 可核对），待人工回归 |
| §9.5 use_accumulated_input 检查 | 完成 | 存在且默认 true（capability.json 机读证据）；键 6 运行时实验，30 FPS 默认未动 |

## 5. 遗留风险 / 人工待办

1. **方案 B 运行时语义未验证**：`window_start_drag` 在本构建存在（探测 true），但在 macOS 透明无边框
   always_on_top 窗口上是否平滑接管、是否改变焦点/遮挡、能否保持点击语义，仅能由 GUI 人工判定（G-002d/e/f）。
   若两种 B 子模式均无效：按已批计划处置 = 「原生拖动不兼容，保留方案 A + 60 FPS 对照数据交人工」，不静默降级需求。
2. **B 的 6px 语义差异**（事后判定 vs 达阈才动）是否满足工单条目 4，由人工裁定；如需改为「B 模式微移动也计点击」的
   更严格语义，须人工指示后再动。
3. **OS 吞 release**：已用 `_process` 左键 mask 轮询兜底；崩溃时最后一次拖动位置可能未落盘（README §4 已记录）。
4. 原生拖动 modal 会话期间 Godot 的 `_process` 采样可能暂停，`native_drag_samples` 的更新率下界待 GUI 实测核对。
5. 键 6 仅运行时实验；重启即回引擎默认（accum=true）与 30 FPS，不构成配置漂移。
6. headless 门禁不覆盖任何 GUI 语义（AGENTS.md §4）；`user://spike_window.json` 写入在代理沙箱下 err=12 属已知
   噪音，用户 GUI 运行不受影响。

## 6. 合规声明

Phase B 全程单会话串行；未调用子 Agent/委派/fork/并行工作流/后台任务；未读取或修改 `tasks/APPROVALS.md`；
未新增任何批准记录；无 git add/commit/merge/push/stash/reset/clean（提交由 AUTO-001 调度器按已批流程执行）；
写入仅 `tests/spike/overlay/**`（代码/README/自动再生 JSON）与本证据目录 `report.md`；全部测试结果来自上表真实命令输出。
