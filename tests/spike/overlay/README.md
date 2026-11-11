# SPIKE-001 · macOS 透明/穿透/拖动 GUI 探针

隔离工程（仅 `tests/spike/overlay/**`）。headless 只验证脚本/场景可无错加载与能力探测；
**透明/穿透/拖动必须按下述 GUI 人工流程验收，headless 结果不得当成 GUI 证据**（AGENTS.md §4、TECH_SPIKE §3）。

## 1. 自动部分（Agent/CI 可跑）

```bash
# C1 headless 加载 + 能力探测（脚本自行 quit，不依赖 --quit-after）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay
# C2 两渲染器可加载（headless 下实际 renderer 记为 dummy 属如实记录）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver opengl3
```

预期：exit 0，无 `SCRIPT ERROR`；生成 `report/capability.json`、`report/observed_state.json`、
`report/variant_matrix.json`（headless 下仅几何/属性探测，无 GUI 语义）。

## 2. GUI 人工验收（C3；in_review 后执行，验收通过才置 done）

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal
```

窗口：220×160 无边框置顶小窗；橙色矩形 = 临时“船”占位（不透明命中区）；其余区域全透明；顶部 Label 显示变体/FPS/位置。
**启动默认 = 变体 2（polygon 生产语义）**：透明区鼠标穿透 + 船体可点击/可拖动（SPIKE-001-FIX-001 修正 A）。

穿透语义（Godot `Window.mouse_passthrough_polygon` 实测语义，以 G-001c 人工判定为准）：
**多边形内部接收鼠标事件，多边形外部穿透**；`mouse_passthrough=true` 时多边形设置无效。
polygon 变体的多边形 = Ship 实际可交互矩形（运行时从 Ship 节点全局矩形取值），**不使用**“全窗减船体”的反向凹多边形。

### 键位

| 键 | 动作 |
|---|---|
| 1 | 变体 full：`mouse_passthrough=true` + 多边形清空 → 整窗鼠标穿透（对照组，船体也不应响应） |
| 2 | 变体 polygon（**启动默认**）：`mouse_passthrough=false` + 多边形=船体矩形 → 船体接收事件、其余透明区穿透（API 缺失时自动记 unsupported 并退回整窗拦截） |
| 3 | 变体 off：`mouse_passthrough=false` + 多边形清空 → 关闭穿透（对照，全窗可拦截） |
| 4 | 拖动模式 A（**启动默认**）：FIX-001 修正 B 手动拖动（按下冻结屏幕坐标基准 + 6px 阈值），行为不变 |
| 5 | 拖动模式 B（SPIKE-001-FIX-002）：macOS 原生拖动 `DisplayServer.window_start_drag()`，由 OS 窗口服务器跟踪移动，不受 30 FPS 帧循环限制；6px 为**事后判定**（见 G-002e 与 §4） |
| 6 | （§9.5 实验）切换 `Input.use_accumulated_input`（引擎默认 true＝motion 按帧合并 → A 模式窗口位移更新率被帧率封顶）；仅运行时实验 |
| 7 | （SPIKE-001-FIX-002）运行时 30↔60 FPS 对照热键；**正式默认与重启后恒为 30（SDD-175）**，60 只存在于单次 GUI 会话 |
| 9 | 引擎内自截图游戏窗口 → `evidence/spike_<utc>.png`（不截桌面） |
| Q / Esc | 退出（退出前写 `report/observed_state.json` 并保存窗口位置） |

### 人工验收矩阵（填 observed_state.json 的 human_observation 或另表回填）

| # | 步骤 | 判定标准 | 结果（人工填） |
|---|---|---|---|
| G-001a | 变体 3（off）下点透明区 | 窗口拦截点击（Label 不变，下方 App 收不到） | |
| G-001b | 变体 1（full）下点透明区与船体 | 两者都落到下方 App（整窗穿透成立，对照组） | |
| G-001c | 默认（polygon）下点透明区 vs 船体 | 透明区点击落到下方 App；船体响应（clicks+1）＝**穿透修复判定**；并如实记录本机实测语义（多边形内接收/外穿透） | |
| G-001d | 默认（polygon）按住船体连续拖动 ≥200px（含快速甩动与急停） | 窗口平滑跟手、无往复抖动、松手即停不漂移＝**抖动修复判定**；客观核对 `observed_state.json` 的 `last_drag_samples`（[t_ms, dx, dy] 轨迹，无往复折返） | |
| G-002a | 船体小幅点按（位移 <6px） | 计为点击（clicks+1），窗口不动 = 拖动阈值不误判 | |
| G-002b | 船体拖动 ≥6px 后松手，退出重启 | 窗口回原位；`cat "$HOME/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json"` 的 x/y 在安全区（松手即停、重启恢复） | |
| G-002c | 拖到屏幕边缘再重启 | 启动 clamp 回安全区，不丢失窗口 | |
| G-002d | （FIX-002）键 4/5 切换 A/B，各按住船体快速拖动并急停，直接对比手感 | B（原生拖动）应明显更跟手或如实记录差距；客观核对 `observed_state.json` 的 `native_drag_samples`（[t_ms,win_x,win_y,mouse_x,mouse_y]）窗口位置更新率是否 >30Hz（A 模式 GUI 实测 ≈26.8Hz 被帧率封顶） | |
| G-002e | （FIX-002）B 模式下船体轻点（<6px）与拖动分别判定点击/拖动语义 | 轻点：`ship_clicks+1`；**注意：B 模式 6px 为拖动结束后按窗口净位移的事后判定，非 A 模式「达 6px 才开始拖动」——语义差异已明示（§9.2），是否符合工单条目 4 由人工裁定** | |
| G-002f | （FIX-002）B 模式拖动 ≥6px 后松手，退出并重启 | 窗口回到拖动后位置（B 模式拖动结束同样走 `_save_position()`；OS 吞掉 release 时由 `_process` 左键 mask 轮询兜底） | |
| G-003a | 观察 Retina 屏上占位矩形 | 边缘锐利无错位、无整块不透明矩形盖住桌面 | |
| G-003b | 多屏切换 | **本机单内置屏 → NOT RUN（R-05），保持记录** | |
| G-004 | 观察 Label FPS 滑窗 | ≈30 FPS（Engine.max_fps=30）；隐藏窗口后不再产生 FPS 样本（隐藏≠退出） | |
| G-004b | （FIX-002）键 7 切到 60 对照观察后，退出并重启 | 重启后 Label 与 `observed_state.json` 的 `max_fps` 必须回到 30（SDD-175 硬约束；60 不得跨会话持久） | |
| 拖动桌面 | 变体 2/3 时拖动窗口标题区不存在（无边框）：仅船体可拖 | 桌面工作不被干扰 | |

## 3. 数据与回滚

- 运行时几何：`~/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json`
  （INTERFACES_AND_DATA §8：存档不进源码树；本文件是探针临时数据，非 v0.1 正式 save schema）。
- 回滚（破坏性，须人工批准）：删除本工程目录 + 上述 app_userdata 子目录。

## 4. 已知边界

- 穿透语义最终以真机 GUI 观察为准（macOS 26.6 + Godot 4.7.2 + Metal 未验证，R-06）；
  探针只记录事实，**任何需求级降级（放弃透明或穿透）必须另行报批**。
- headless 的 `rendering_method=dummy` 属如实记录，不得写成 Metal 实证。
- SPIKE-001-FIX-001：拖动位移一律用 `DisplayServer.mouse_get_position()` 屏幕绝对坐标差计算
  （按下瞬间冻结基准），**不用** `event.global_position`（随窗口移动自我反馈 → 抖动），
  **不用** `Input.capture_mouse`（非 Godot 4 API）。若 GUI 实测仍抖动或鼠标移出船体后事件丢失，
  备选方案为 `DisplayServer.window_start_drag()` 原生拖动（capability.json 已探测其存在性；启用前须人工批准）。
- 拖动轨迹样本见 `observed_state.json` 的 `last_drag_samples`（上限 400 点/次拖动），仅供人工 G-001d 客观核对，
  抖动是否消除仍以 GUI 人工判定为准。
- SPIKE-001-FIX-002 方案 B（原生拖动）语义与已知边界：
  - 按 §9.1（人工审核为准，优先于原计划默认）：脚本常量 `DRAG_B_MODE` 默认 `"on_press"`——在左键
    **按下事件**中调用 `window_start_drag()`（官方文档语义）；`"on_threshold"`（位移达 6px 后才调用）
    仅为**实验性时机**，不得假定一定有效，是否启用由 GUI 人工判定后经人工指示改常量。
  - **方案 B 无法保留与 A 完全相同的 6px 阈值语义（§9.2 明示义务，非静默变更）**：
    A＝位移达 6px 才开始拖动窗口；B＝按下即由 OS 接管拖动，6px 退化为**拖动结束后的净位移事后判定**
    （净位移 <6px 记为点击）。两模式常量 `DRAG_THRESHOLD_PX=6.0` 均不变；是否符合工单条目 4 由人工裁定。
  - OS 可能吞掉 release 事件 → `_process` 左键 mask 轮询兜底（记 `native_drag_end` 并保存位置/写报告）；
    崩溃时最后一次拖动位置可能未落盘，如实记录。
  - `window_start_drag` / `Window.get_window_id` / `Input.use_accumulated_input` 均先运行时探测；
    缺失记 `drag_b_unsupported` / `drag_b_window_id_fallback:0` / `accum_input_unsupported` 并如实报告，
    **不静默降级**。若 GUI 实测方案 B 不接管窗口或引发焦点/遮挡异常：键 4 恒可切回方案 A（A 不受 B 影响，
    §9.3），「原生拖动不兼容」结论交人工，不擅自降级穿透/透明需求。
  - §9.5 检查结论：`Input.use_accumulated_input=true`（引擎默认）会把两次派发间的 mouse motion 合并为一个
    事件，使 A 模式窗口位移每帧最多更新一次（30 FPS → GUI 实测 ≈26.8 Hz）；键 6 可运行时关闭做对照实验，
    **30 FPS 正式默认值不受任何影响**（键 7 的 60 也仅存在于单次会话）。
  - Headless exit=0 只证明脚本/场景无错加载；原生拖动是否更流畅、能否保持点击语义、位置是否正常保存，
    全部由上表 G-002d/e/f 人工 GUI 验收（§9.6）。
