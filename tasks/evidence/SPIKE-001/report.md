# SPIKE-001 · Phase B 执行报告 — macOS 透明/穿透/拖动探针

- 工单：SPIKE-001（Phase B 执行；plan 见同目录 `plan.md`）
- 日期/环境：macOS 26.6.2 · Apple M4 Max · Godot `4.7.2.stable.official.ed1daf0bf`（`--version` 实测）
- 执行方式：单会话串行；未用子 Agent/fork/工作流；未主动启动后台任务；未读写 `tasks/APPROVALS.md`；无任何 git 写操作（未 commit/merge/push/stash/reset/clean）
- 结论：**自动部分（C1/C2/C5）全部真实通过（exit 0、无 SCRIPT ERROR）；GUI 项（C3/C4 及 G-001～G-004 人工列）按 plan 移交人工验收，本票不置 done**

## 1. 改动文件清单（全部在允许范围内）

`tests/spike/overlay/**`（新建，8 文件）：

| 文件 | 类型 | 说明 |
|---|---|---|
| `project.godot` | 新建 | 独立工程 "Fishing Overlay Spike"；220×160、borderless/always_on_top/transparent 设置；设置项经探针读回证实有效（见 §3） |
| `main.tscn` | 新建 | 根 Node2D + 全屏透明 ColorRect（mouse_filter=IGNORE）+ 船体占位 ColorRect（不透明命中区，STOP）+ Status Label + CapabilityProbe 子节点 |
| `scripts/capability_probe.gd` | 新建 | 能力探测：Window 属性存在性/生效值、渲染器、project 设置读回；headless 写 `report/capability.json` 后 `quit()` |
| `scripts/overlay_window.gd` | 新建 | GUI 行为：键 1/2/3 穿透变体（API 缺失记 `unsupported`）、6px 拖动阈值、位置存 `user://spike_window.json`、启动 clamp 到安全区、`Engine.max_fps=30`、`Time.get_ticks_msec()` 滑窗 FPS（无帧计数计时）、键 9 自截图、退出写 observed_state/variant_matrix |
| `README.md` | 新建 | GUI 人工验收清单（键位、G-001～G-004 矩阵、C3/C4 命令） |
| `report/capability.json` | 运行时生成 | headless 能力探测报告 |
| `report/observed_state.json` | 运行时生成 | 状态/事件/FPS/变体日志 |
| `report/variant_matrix.json` | 运行时生成 | 变体矩阵（headless 仅记录 API 存在性与生效值，人工观察列空待 GUI） |

`tasks/evidence/SPIKE-001/`（证据，允许目录内）：本报告 + `raw/` 副本 8 份：
`c1_headless_full.log`、`c2_metal.log`、`c2_opengl3.log`、`capability_c1_headless.json`、`capability_c2_metal.json`、`capability_c2_opengl3.json`、`observed_state_headless.json`。

**范围外零改动**：`git diff --stat` 执行前后均为空；`git status --porcelain` 终态仅 `?? tasks/evidence/`（既有）与 `?? tests/`（本票新建目录，git 对未跟踪目录折叠显示；内容仅 `tests/spike/overlay/**`）。`.godot/`、`*.uid` 被根 `.gitignore` 全局忽略（实测 headless 运行后工作树亦无其踪影）。

## 2. 执行命令与真实退出码

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| C0 环境核验 | `Godot --version` / `git status --porcelain -b` / `git diff --stat` | 0 / 0 / 0 | 4.7.2.stable.official；`## main` `?? tasks/evidence/`；diff 空 |
| **C1 首次尝试（失败实录）** | `Godot --headless --path tests/spike/overlay` | **未取得（挂起 >180s，被执行器移至后台后由本会话 kill，pgrep 终态 1=无残留）** | 3 处解析错误致脚本未加载、`quit()` 未执行：① `Vector2i+Vector2` 混合类型；② `DisplayServer.get_display_safe_area(0)` 本引擎仅接受 0 参数；③ 静态类调用 `DisplayServer.get_display_count()` 在本引擎不存在。stderr 原文含 `SCRIPT ERROR: Parse Error` ×3 |
| C1 修复后 | 同上 | **0** | stdout/stderr 无 `SCRIPT ERROR`；`report/capability.json` 合法 JSON（`python3 -m json.tool` exit 0）；探针自行 quit |
| C2a metal | `Godot --headless --path tests/spike/overlay --rendering-driver metal` | **0** | 无 SCRIPT ERROR（`grep -c` 计数 0）；记录 `rendering_method=forward_plus`（headless 下如实记录，非 Metal GPU 实证） |
| C2b opengl3 | 同上 `--rendering-driver opengl3` | **0** | 无 SCRIPT ERROR；记录 `rendering_method=gl_compatibility` |
| C3 GUI 可见运行 | `Godot --path tests/spike/overlay --rendering-driver metal` | **NOT RUN（按 plan §5 由人工执行）** | 产出 `evidence/*.png`、人工矩阵列，README §2 |
| C4 位置持久化 | `cat "$HOME/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json"` | **1（本会话沙箱内预期缺失）** | 会话文件沙箱（workspace-write）拒绝写 app_userdata：运行时 stderr 如实记录 `ERROR: Could not create directory: '/Users/rain/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike'`（err=7）并降级为 `push_warning`，不影响 exit 0。人工终端 GUI 运行无此限制，C4 须在 GUI 验收时执行 |
| C5 范围核验 | `git status --porcelain` | **0** | 仅 `?? tasks/evidence/` + `?? tests/`，无已跟踪文件改动 |
| 残留核验 | `pgrep -l Godot` | 1（=无进程） | 每次运行后均无 Godot 进程残留（R-04） |

## 3. 测试输出摘要（关键事实，均来自真实产物）

来自 `raw/capability_c1_headless.json`（探针 `get_property_list()` 实测，本构建真实 API 面）：

- Window 属性**存在**：`mouse_passthrough` ✓、`mouse_passthrough_polygon` ✓、`transparent` ✓、`borderless` ✓、`always_on_top` ✓、`unfocusable` ✓
- Window 属性**不存在**：`mouse_passthrough_mode` = **false** → 本 4.7.2 构建无该枚举属性；脚本已按探测结果自动改用布尔 `mouse_passthrough`，变体矩阵 `applied=true, effective_mouse_passthrough_mode=null` 如实记录
- `project_display_settings` 读回：`viewport 220×160`、`transparent/borderless/always_on_top = true` 全部有效 → 设置名正确；headless 报告 `window_size=[64,64]` 属 dummy 窗口行为，**不得**当作 GUI 尺寸证据
- `max_fps: 30` 已写入 observed_state（SDD-175 设置面成立；真实帧率待 GUI）
- 事件日志含 `position_restored_from_default`、`variant:off`、`ready`、`position_saved`（headless 走通启动→探测→落盘→quit 全链路；`position_saved` 在沙箱内被拒绝并有 WARNING 实录）

## 4. 覆盖的验收条目

| 验收 | 状态 | 依据 |
|---|---|---|
| headless 门禁（§6 CI 门禁） | **已覆盖（自动）** | C1/C2a/C2b 均 exit 0、无 SCRIPT ERROR、报告 JSON 合法 |
| V01-W01 透明无边框窗（设置与 API 面） | 自动部分已覆盖 | 设置读回 + 属性存在性；**真实透明渲染待 GUI** |
| V01-W02 拖动+穿透（实现与探测面） | 自动部分已覆盖 | 阈值 6px/clamp/持久化已实现并跑通 headless 链路；**穿透语义与点击行为待 GUI（G-001/G-002）** |
| V01-W03 / SDD-175 固定 30FPS 与逻辑时钟解耦 | 自动部分已覆盖 | `Engine.max_fps=30` 写入报告；全部计时用 `Time.get_ticks_msec()`，无帧计数；**实测帧率待 GUI（G-004）** |
| G-001 透明区穿透/船体可点 | **NOT RUN（人工 GUI）** | README §2 矩阵 G-001a/b/c |
| G-002 拖动阈值与重启恢复 | **NOT RUN（人工 GUI；C4 本会话沙箱内不可测）** | README §2 + C4 |
| G-003 Retina/多屏 | **NOT RUN**；多屏维持 R-05 缺口记录 | README §2；本机单内置屏 |
| G-004 可见≈30FPS、隐藏停多余绘制 | **NOT RUN（人工 GUI）** | 隐藏停采样已实现（`_on_visibility_changed`） |

## 5. 遗留风险

1. **R-06 主风险未闭环**：macOS 26.6 + Godot 4.7.2 + Metal 的透明/穿透"真实生效"仍未证实——本票只证明了设置与 API 存在性；GUI 人工验收（C3）前不得声称穿透成立。若 GUI 失败：按 plan §5 记录证据并**报批**双窗口等替代方案，禁止静默降级。
2. **本构建无 `mouse_passthrough_mode` 枚举**：变体语义完全依赖布尔 `mouse_passthrough` + `mouse_passthrough_polygon`；polygon 语义（区域内穿透还是区域外穿透）将由 GUI 矩阵 G-001c 实测确定，脚本已把实际语义列留空给人工。
3. **headless 窗口 64×64 为 dummy 行为**：GUI 实际 220×160 待人工确认（G-003a）。
4. **`user://` 在代理会话沙箱内不可写**：C4 与位置重启恢复必须在人工终端 GUI 运行中验证；探针的读回失败回退路径已有代码但未经真实损坏数据注入。
5. **首次 C1 挂起教训**：脚本解析失败会绕过 `quit()` 导致进程滞留（本次已即时 kill，终态无残留）。建议调度器/未来 CI 对本命令加超时与进程回收，本票不改 CI 之外文件，故仅记录于此。
6. `evidence/*.png` 仅在 GUI 按 9 生成；本次未运行 GUI，无截图属预期，不是省略。

## 6. 合规声明

仅改动 `tests/spike/overlay/**` 与证据目录 `tasks/evidence/SPIKE-001/**`；未读取/改动 `tasks/APPROVALS.md`；未创建任何批准记录；无 git 写操作；无子 Agent/fork/并行工作流；未主动调用后台任务（唯一一次后台化系执行器对挂起命令的自动搬运，已在发现后立即 kill 并核验 `pgrep` 无残留）；所有退出码均为真实命令输出；无需求变更、无破坏性操作、无需求降级。
