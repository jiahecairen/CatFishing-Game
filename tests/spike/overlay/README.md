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

### 键位

| 键 | 动作 |
|---|---|
| 1 | 变体 full：整窗鼠标穿透（对照组，船体也不应响应） |
| 2 | 变体 polygon：`mouse_passthrough_polygon` 顶部条穿透、船体保留可交互（API 缺失时自动记 unsupported） |
| 3 | 关闭穿透（对照，全窗可拦截） |
| 9 | 引擎内自截图游戏窗口 → `evidence/spike_<utc>.png`（不截桌面） |
| Q / Esc | 退出（退出前写 `report/observed_state.json` 并保存窗口位置） |

### 人工验收矩阵（填 observed_state.json 的 human_observation 或另表回填）

| # | 步骤 | 判定标准 | 结果（人工填） |
|---|---|---|---|
| G-001a | 变体 3 下点透明区 | 窗口拦截点击（Label 不变，下方 App 收不到） | |
| G-001b | 变体 1 下点透明区与船体 | 两者都落到下方 App（整窗穿透成立） | |
| G-001c | 变体 2 下点顶部条 vs 船体 | 顶条落下方 App；船体被船体区响应（区分两 API 语义；如实记录实际语义） | |
| G-002a | 船体小幅点按（位移 <6px） | 计为点击（clicks+1），窗口不动 = 拖动阈值不误判 | |
| G-002b | 船体拖动 ≥6px 后松手，退出重启 | 窗口回原位；`cat "$HOME/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json"` 的 x/y 在安全区 | |
| G-002c | 拖到屏幕边缘再重启 | 启动 clamp 回安全区，不丢失窗口 | |
| G-003a | 观察 Retina 屏上占位矩形 | 边缘锐利无错位、无整块不透明矩形盖住桌面 | |
| G-003b | 多屏切换 | **本机单内置屏 → NOT RUN（R-05），保持记录** | |
| G-004 | 观察 Label FPS 滑窗 | ≈30 FPS（Engine.max_fps=30）；隐藏窗口后不再产生 FPS 样本（隐藏≠退出） | |
| 拖动桌面 | 变体 2/3 时拖动窗口标题区不存在（无边框）：仅船体可拖 | 桌面工作不被干扰 | |

## 3. 数据与回滚

- 运行时几何：`~/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json`
  （INTERFACES_AND_DATA §8：存档不进源码树；本文件是探针临时数据，非 v0.1 正式 save schema）。
- 回滚（破坏性，须人工批准）：删除本工程目录 + 上述 app_userdata 子目录。

## 4. 已知边界

- 穿透语义最终以真机 GUI 观察为准（macOS 26.6 + Godot 4.7.2 + Metal 未验证，R-06）；
  探针只记录事实，**任何需求级降级（放弃透明或穿透）必须另行报批**。
- headless 的 `rendering_method=dummy` 属如实记录，不得写成 Metal 实证。
