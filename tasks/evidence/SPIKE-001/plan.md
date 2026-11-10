# SPIKE-001 · Phase A 计划 — macOS 透明/穿透/拖动探针（只读规划，未写码）
- **单 Agent 串行**：禁止启动子 Agent、fork、并行工作流、第二个大型模型。若标准预设仍暴露委派工具，**不要调用**。（原样引用 AGENTS.md 第 9 行，作为已读取规则证明）

- 工单：SPIKE-001（queue status=ready，deps=AUDIT-001 done，needs_human=true，allowed_files=`tests/spike/overlay/**`）
- 阶段：Phase A 只读规划。本会话**零代码改动**；本文件是 Phase A 唯一写入。
- 日期/环境：macOS 26.6.2 (25G83) · Apple M4 Max (Metal 4) · arm64 · Godot `4.7.2.stable.official.ed1daf0bf`

## 0. Phase A 只读实测记录（命令 · 退出码 · 结果）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 项目结构 | `ls -la`（根/docs/tasks/tests） | 0（tests 行为 1） | 无 `tests/` 目录，`tests/spike/overlay/**` 全部待新建；无 `project.godot`/`*.gd`/`*.tscn`（glob 零命中） |
| Skills 发现 | `ls .dsh/skills/*/SKILL.md` | 0 | 3 个项目 Skills 均在（godot-overlay / fishing-state-and-save / godot-validation）；个人 Skills 67 个可见 |
| Godot 在 PATH | `command -v godot godot4 godot4-headless` | 1 | 均不存在，须用 App 内绝对路径 |
| Godot 版本 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Godot 进程残留 | `pgrep -l Godot` | 1 | 当前无 Godot 进程（R-04 无残留复现） |
| Git 状态 | `git status --porcelain -b` | 0 | `## main`；唯一未跟踪 `?? tasks/evidence/`（含 `_runner/`，属 AUTO-001 自身） |
| Git 近期 log | `git log --oneline -n 20` | 0 | `f61b4e1 Authorize SPIKE-001 planning` / `f27d609` / `7f5317d` / `4d8ed4d`(baseline) |
| Git diff | `git diff --stat` | 0 | 空（无未提交改动） |
| 显示器 | `system_profiler SPDisplaysDataType` | 0 | 仅 1 块内置 Liquid Retina XDR 3456×2234，无外接屏 → G-003 多屏部分维持 NOT RUN（R-05） |
| 工程缓存 | `ls -d .godot` | 1 | 无 `.godot/`；根 `.gitignore` 已全局含 `.godot/`（任意深度命中） |
| user 数据目录 | `ls ~/Library/Application Support/Godot/app_userdata` | 0 | 仅 `Moon`、`Moon Star Collector`、`Snake Game`、`[unnamed project]`，无与 spike 工程名冲突 |
| 文档核对 | 读 AGENTS.md、TASKS.md、TECH_SPIKE、SDD_v0.1、DECISION_REGISTER、ACCEPTANCE_TESTS、DEV_LOG、HARNESS_LOCAL_SETUP、ARCHITECTURE、INTERFACES_AND_DATA、REQUIREMENTS_CHANGELOG、TICKET_TEMPLATE、queue.json、phaseA 模板 | 0 | 无与本计划冲突的新约束；未读 tasks/APPROVALS.md（禁止项，遵守） |

## 1. 目标

用 Godot 4.7.2 在**用户 Mac 真实 GUI** 下验证桌面叠加四项能力，产出可复核证据（命令+退出码+截图+人工矩阵），供 UI-001 决策：

1. 透明、无边框、小尺寸独立窗口（临时"船"为代码绘制的不透明占位矩形，非正式美术）。
2. 透明区鼠标真实穿透到下方 App；船体命中区可点击（区分 `mouse_passthrough` 与 `mouse_passthrough_polygon` 语义，透明视觉 ≠ 输入穿透）。
3. 拖动有阈值（防误点）、位置持久化、重启恢复、断屏/边缘安全回退。
4. 可见时固定 30 FPS（SDD-175），且逻辑计时不依赖帧计数。

**非目标（禁止）**：经济/FSM/正式存档/猫创建/正式美术/联机/天气/图鉴；不改 20–60s、30FPS、容量 10、鱼价、售鱼规则；不用 headless 冒充 GUI 证据；不修改 `project.godot`（根工程不存在，也不在根目录建入口——用户已裁定 spike 为独立工程，R-02 已处置）。

## 2. 要改动的文件（Phase B；全部在允许范围 `tests/spike/overlay/**` 内）

| 文件（新建） | 作用 |
|---|---|
| `tests/spike/overlay/project.godot` | 独立工程：`config/features=PackedStringArray("4.7")`；`transparent=true`、`borderless=true`、小尺寸 220×160、`application/name="Fishing Overlay Spike"`（避免 app_userdata 目录冲突） |
| `tests/spike/overlay/main.tscn` | 主场景：根 `Node2D` + 船体 `ColorRect`（不透明占位命中区）+ `Label` 状态文本 + 全屏透明区 |
| `tests/spike/overlay/scripts/capability_probe.gd` | `_ready()` 探测 `get_window().get_property_list()` 中 `mouse_passthrough`/`mouse_passthrough_polygon`/`unfocusable` 等属性存在性、`RenderingServer.get_current_rendering_method()`、`DisplayServer.get_display_count()`；headless 下写 `report/capability.json` 后 `get_tree().quit()` |
| `tests/spike/overlay/scripts/overlay_window.gd` | GUI 行为：变体开关（键 1=全窗穿透 / 2=穿透多边形 / 3=关穿透，多边形 API 缺失时该变体记 `unsupported` 并如实写报告）；船体拖动（按下位移 ≥6px 才判拖动）；位置写 `user://spike_window.json`；启动读回并 clamp 到 `DisplayServer.get_display_safe_area(0)` 安全矩形；`Engine.max_fps=30`；FPS 用 `Time.get_ticks_msec()` 滑窗统计（禁帧计数）；键 9=viewport 自截图存 `evidence/`；退出前写 `report/observed_state.json` |
| `tests/spike/overlay/report/`、`tests/spike/overlay/evidence/` | 运行时由 app 自身写入的机读报告与 viewport 自截图（只截游戏窗口，不截桌面隐私） |
| `tests/spike/overlay/README.md` | GUI 人工验收清单与操作说明（键位、变体、判定标准） |

运行时数据（仓库外，DEV_LOG 已批准）：`~/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json`（INTERFACES_AND_DATA §8：存档不进源码树）。

**不改动**：`tasks/TASKS.md`、`docs/DEV_LOG.md`、`.gitignore`、schemas/examples、根工程文件——状态回写由 AUTO-001 调度器/人工完成（本票 Phase B 范围不含它们）。

## 3. 接口与不变量

- 仅窗口能力 + 窗口几何持久化；无经济、无 FSM、无业务存档。
- `spike_window.json`（临时探针专用，非 v0.1 正式 save schema）：`{"x":int,"y":int,"width":220,"height":160,"display_hint":null,"ts_utc":"..."}`；读回失败/越界 → 回退安全默认位并记录，不崩溃。
- 不变量：可见 30 FPS（SDD-175）；逻辑计时只许 `Time.get_ticks_msec()`/`get_process_delta_time()`，禁 `get_frames_drawn()`/帧计数；透明区点击必须落到下方 App；船体区可交互；拖动阈值 6px；位置重启可恢复、边缘 clamp 不可丢失。
- 变体对比（用户已批准的自动对比授权）：Metal vs Compatibility 渲染器 × 三种穿透模式在 `report/variant_matrix.json` 记录"属性存在性 + 实际生效值 + 人工观察列"；**任何需求级降级（放弃透明或穿透）仍须单独报批，探针只记录不决策**。

## 4. 测试命令与预期退出码（Phase B 自动部分；`test_cmd` 由人工在批准时核定，建议取 C1）

| # | 命令 | 预期 |
|---|---|---|
| C1 headless 加载+能力探测 | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay` | **exit 0**，stdout/stderr 无 `SCRIPT ERROR`；`report/capability.json` 生成且为合法 JSON（探测脚本自行 quit，不依赖未证实的 `--quit-after`/`--do-string`，R-03） |
| C2 两渲染器下可加载 | C1 分别追加 `--rendering-driver metal` 与 `--rendering-driver opengl3` | **各 exit 0**；报告如实记录 headless 下实际生效 renderer（可能为 `dummy`，不得写成 Metal 实证） |
| C3 GUI 可见运行（人工执行） | `/Applications/Godot.app/Contents/MacOS/Godot --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal` | 人工验收时运行；正常退出 **exit 0**；产生 `evidence/*.png` 与 `report/variant_matrix.json` |
| C4 位置持久化核验 | `cat "$HOME/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json"` | **exit 0** 且 JSON 内 x/y 落在安全区；重启 GUI 后窗口回原位（人工确认） |
| C5 范围核验 | `git -C /Users/rain/DevGame/Fishing status --porcelain` | **exit 0**；仅出现 `?? tests/spike/overlay/` 与既有 `?? tasks/evidence/`；`.godot/`、`*.uid` 被根 .gitignore 全局忽略 |

失败即如实记录非零退出码与日志并停（不伪造、不改断言）；GUI 项在 `in_review` 后由用户人工验收置 `done`。

## 5. 风险与回滚

| 风险 | 缓解 |
|---|---|
| macOS 26.6 + Godot 4.7.2 + Metal 透明/穿透未验证（R-06） | 探测先行；若透明或穿透不成立：记录证据 + 替代方案（如双窗口方案：全穿透底窗 + 独立船体小窗）**报批**，不得静默降级 |
| `mouse_passthrough_polygon` 属性缺失/语义差异 | `get_property_list()` 先探测，缺失记 `unsupported`，仅测已证实 API |
| Agent 启动 GUI 会闪现窗口且进程可能滞留（R-04 先例） | Phase B 自动化**只跑 headless**；GUI 由人工按 README 启动验收 |
| 拖动把窗口移出可恢复区域 | 启动/恢复时 clamp 到主屏安全区；`display_hint` 记录来源屏；断屏回退默认位 |
| `.godot/` 缓存污染版本库 | 根 `.gitignore` 已全局忽略 `.godot/` 与 `*.uid`（实测第 15–16 行）；无需越权改 .gitignore |
| 截图泄露桌面隐私 | 仅用引擎内 `get_viewport().get_texture().get_image().save_png()` 自截游戏窗口 |
| 回滚（**破坏性，须人工批准后才执行**） | 删除 `tests/spike/overlay/` 整目录 + `~/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/`；基线 `4d8ed4d` 起逐票 diff，失败代码不 commit、不 push |

## 6. 验收条目映射

| 验收 | 内容 | 证据形式 | 归属 |
|---|---|---|---|
| G-001 | 透明区点击落下方 App；船体区响应 | GUI 人工矩阵 + 自截图 + variant_matrix.json | 人工（in_review 后） |
| G-002 | 拖动阈值不误判；位置重启恢复 | C4 + 人工重启观察 | 半自动 + 人工 |
| G-003 | Retina 无错位/无整块不透明矩形；多屏切换 | Retina 部分人工观察；**多屏 NOT RUN（单内置屏，R-05）** | 人工 / 记录缺口 |
| G-004 | 可见 ≈30 FPS；隐藏停多余绘制 | 滑窗 FPS 统计入 report + 人工观察 | 半自动 + 人工 |
| V01-W01/W02/W03、SDD-175 | 透明无边框窗 / 拖动+穿透 / 固定 30FPS 与逻辑时钟解耦 | C1–C3 命令 + 退出码 + 报告 | 自动 + 人工 |
| headless 门禁（§6 CI 门禁） | 脚本/场景可无错加载 | C1、C2 exit 0 | 自动 |

## 7. 合规声明

Phase A 全程只读：未创建/修改/删除任何仓库文件（本 plan.md 为唯一允许写入）；未调用子 Agent/fork/工作流/后台任务；未读取 `tasks/APPROVALS.md`；无任何 git 写操作；未安装依赖、未访问网络服务。本票无需求变更与破坏性操作（回滚仅为文档化程序），不触发 BLOCKED。
