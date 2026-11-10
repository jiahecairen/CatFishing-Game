# SPIKE-001-FIX-001 · Phase A 计划 — 修复鼠标穿透和窗口拖动抖动（只读规划，未写码）
- **单 Agent 串行**：禁止启动子 Agent、fork、并行工作流、第二个大型模型。若标准预设仍暴露委派工具，**不要调用**。（原样引用 AGENTS.md 第 9 行，作为已读取规则证明）

- 工单：SPIKE-001-FIX-001「修复鼠标穿透和窗口拖动抖动」（queue status=ready，deps=AUDIT-001，needs_human=true，allowed_files=`tests/spike/overlay/**`，test_cmd=headless 加载）
- 阶段：Phase A 只读规划。本会话零代码改动；**本文件是 Phase A 唯一写入**。未调用子 Agent/后台任务；未读取 `tasks/APPROVALS.md`；无任何 git 写操作。
- 日期/环境：macOS 26.6.2 (25G83) · Apple M4 Max (Metal 4) · Godot `4.7.2.stable.official.ed1daf0bf`（本会话实测，见 §0）

## 0. Phase A 只读实测记录（命令 · 退出码 · 结果）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 项目结构 | `ls -la`（根）+ `ls -R docs tasks` | 0 | docs 12 份、tasks/TASKS.md 存在；`tasks/evidence/SPIKE-001-FIX-001/` 已有旧 `BLOCK_REPORT.md` |
| spike 现状 | `find tests -type f` | 0 | SPIKE-001 已交付 8 文件：`project.godot`、`main.tscn`、`scripts/{overlay_window,capability_probe}.gd`、`README.md`、`report/{capability,observed_state,variant_matrix}.json`（后三者为运行时产物） |
| Git 状态 | `git status --porcelain -b` | 0 | `## main`；已跟踪文件零改动；未跟踪仅 `?? tasks/evidence/SPIKE-001-FIX-001/`、`?? tasks/evidence/_runner/`（AUTO-001 自身） |
| Git diff | `git diff --stat` | 0 | 空 |
| Git log | `git log --oneline -10` | 0 | HEAD=`e504324 Unblock SPIKE-001 GUI repair ticket`（21:23Z）；`a6c68d5 Add SPIKE-001 GUI repair ticket`；`1f01750` = SPIKE-001 探针 commit；无远端（AUDIT-001 R-01：未 push） |
| 旧阻断处置 | `git show e504324` + 读 `tools/auto/queue.json` | 0 | 旧 BLOCK_REPORT（21:15，`tools/auto/queue.json` 越界）已由人工提交该文件并 `unfrozen`（21:17）→ **上一轮 BLOCKED 已解除**；当前工单 status=ready，Phase B 前工作树对 `tests/spike/overlay/**` 无越界改动 |
| Godot 在 PATH | `command -v godot godot4` | 1 | 均不存在，须用 App 内绝对路径 `/Applications/Godot.app/Contents/MacOS/Godot` |
| Godot 版本 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Godot 残留 | `pgrep -l Godot` | 1 | 无进程残留（R-04 复现） |
| Skills 发现 | `ls .dsh/skills` | 0 | `fishing-state-and-save`、`godot-overlay`、`godot-validation` 三项目 Skills 均在；本会话已加载后两者 |
| 运行报告读回 | `python3 -m json.tool tests/spike/overlay/report/variant_matrix.json` | 0 | 本构建 API 面：`mouse_passthrough=true(存在)`、`mouse_passthrough_polygon=true(存在)`、**`mouse_passthrough_mode=false(不存在)`**；`max_fps=30`；headless 启动即 `variant:off` |
| 代码审查 | 读 `scripts/overlay_window.gd`（306 行）、`main.tscn`、`project.godot` | — | 两个缺陷的候选根因定位见 §1（静态阅读，未运行 GUI，不作 GUI 证据） |

## 1. 缺陷复现面与根因假设（待 Phase B 实现 + GUI 实证确认）

### 缺陷 A：鼠标穿透错误（G-001 不满足）

静态审查 `overlay_window.gd::_set_variant()`：

1. **`polygon` 变体自相矛盾**：`enable := (variant != "off")`，当 `mouse_passthrough_mode` 枚举属性不存在（本构建实测不存在）时走 `_win.set("mouse_passthrough", true)` 分支——即键 2 时**整窗布尔穿透被同时打开**，随后又设置 `mouse_passthrough_polygon`。若 macOS 实现中布尔 `mouse_passthrough=true` 整窗忽略鼠标（优先级高于 polygon），则「顶条穿透、船体保留可交互」的 polygon 变体实际变成**整窗穿透**：船体点不动，表现为穿透语义错误。
2. **启动默认 `variant:off`**（`_ready()` 调 `_set_variant("off")`，实测 `variant_matrix.json` events 含 `variant:off`）：关闭穿透后整个 220×160 窗口（含全透明区）拦截点击，下方 App 收不到——与 V01-W02「透明区域鼠标穿透」相反；生产语义（透明区穿透 + 船体可交互）没有任何一个已批准启动态能表达。
3. polygon 语义（多边形**内**穿透还是**外**穿透）在本机 macOS 26.6 上仍未实测证实（R-06；SPIKE-001 report §5.2 已声明留待 GUI 矩阵 G-001c）。

**修复方向（Phase B，均在 `overlay_window.gd` 内）**：
- 变体语义解耦：`off` = `mouse_passthrough=false` + 清空 polygon（整窗拦截，对照组）；`full` = `mouse_passthrough=true` + 清空 polygon（整窗穿透，对照组）；`polygon`（生产语义，**启动默认**）= 显式 `mouse_passthrough=false` + 设置穿透多边形（透明区），船体/状态条保持可交互。
- 穿透多边形首版：按 Godot 4 文档语义「polygon 内为穿透区」取「全窗减去船体矩形的凹多边形（带缝切口）」；若 G-001c 实测语义相反则镜像取反（仅换顶点序/取补），并如实记录实际语义。若本构建 macOS 对凹多边形/穿透多边形支持不足：按 SPIKE-001 report §5.1 **停下报批双窗口替代方案，不自行降级需求**。
- `_variant_log` 每步记录 `effective_mouse_passthrough`、`effective_mouse_passthrough_polygon`（点数/顶点）供 GUI 回填人工列。

### 缺陷 B：窗口拖动抖动（G-002 不满足）

静态审查 `_on_ship_gui_input()`：拖动位移用 `event.global_position - _drag_start_mouse` 计算后立即 `_win.position = _drag_start_win + d`。窗口拖动场景下 `global_position` 是**窗口内容区坐标**——窗口一动，光标窗口内坐标反方向变化 → `d` 被窗口运动污染并自我反馈 → 窗口在目标位置两侧往复跳动（抖动），`d.round()` 的整数化进一步放大 ±1px 抖振。

**修复方向（Phase B，均在 `overlay_window.gd` 内）**：
- 拖动坐标改到**不随窗口移动**的坐标源：优先 `DisplayServer.mouse_get_position()`（屏幕绝对坐标；沿用 capability_probe 模式先用 `ClassDB.class_has_method("DisplayServer","mouse_get_position")` 探测，缺失则记 unsupported 并回退 `Input.capture_mouse(true)` + 累加 `event.relative`，松手 `Input.capture_mouse(false)`）。
- 拖动起点 `_drag_start_win/_drag_start_cursor` 只在越过 6px 阈值时冻结一次；此后每事件 `pos = start_win + (cur_abs - start_cursor)`，一次性取整；保留「位移 <6px 判点击」（G-002a）与松手落盘 `spike_window.json`。
- 保留 `Time.get_ticks_msec()` 滑窗 FPS 与 `Engine.max_fps=30`（SDD-175），不引入帧计数计时。

## 2. 要改动的文件（严格限于 allowed_files：`tests/spike/overlay/**`）

| 文件 | 改动 | 说明 |
|---|---|---|
| `tests/spike/overlay/scripts/overlay_window.gd` | 修改 | §1 两处修复：变体语义解耦 + 启动默认 polygon 生产态；拖动改绝对屏幕坐标源（探测式回退 capture_mouse）；事件日志记录拖动轨迹样本供抖动判定 |
| `tests/spike/overlay/scripts/capability_probe.gd` | 小改（可选） | 追加探测 `DisplayServer.mouse_get_position` 存在性并写入 capability.json（与既有属性探测同模式） |
| `tests/spike/overlay/README.md` | 修改 | 键位说明更新（启动默认=生产穿透态）；GUI 矩阵新增 G-001d「连续拖动 ≥200px 无往复抖动、松手即停不漂移」、G-001c 增补 polygon 语义人工判定列 |
| `tests/spike/overlay/report/*.json` | 运行时再生成 | headless/GUI 运行产物，位于允许目录内 |

**不改**：`project.godot`、`main.tscn`（透明/无边框/置顶设置与节点结构经 SPIKE-001 读回证实有效，本票无需动）；`tests/spike/overlay` 之外任何文件零改动（含 `tasks/`、`docs/`、`tools/`——状态回写由 AUTO-001 调度器执行，不由本代理写）。

## 3. 接口与不变量

- 仅窗口能力面：`Window.mouse_passthrough`（bool）、`mouse_passthrough_polygon`（PackedVector2Array）、`transparent/borderless/always_on_top`、`DisplayServer.get_display_safe_area()`（0 参）、`DisplayServer.mouse_get_position()`（探测式）。本构建**无** `mouse_passthrough_mode`，不得调用。
- 不变量：可见时 `Engine.max_fps=30`（SDD-175）；一切计时用 `Time.get_ticks_msec()`，禁止帧计数；透明区点击必须落到下方 App 而船体可交互；拖动阈值 6px 不变；退出/隐藏路径继续写 observed_state；`user://spike_window.json` 仅存窗口几何（探针临时数据，非业务存档，INTERFACES §8）。
- 不实现/不触碰：经济、FSM、正式存档、业务状态。
- API 缺失处理延续「探测→unsupported→如实记录」，不得假设未证实 API 存在（R-03）。

## 4. 精确测试命令与预期退出码（Phase B 执行并如实记录真实值）

```bash
# T0 环境
/Applications/Godot.app/Contents/MacOS/Godot --version                      # 预期 0
# T1 语法门禁（先于运行，防 SPIKE-001 首轮解析错误挂起复发）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay \
  --check-only --script res://scripts/overlay_window.gd                      # 预期 0；非 0 则先修语法再跑 T2
# T2 调度器 test_cmd（headless 加载 + 能力探测，脚本自行 quit）
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay
# 预期 0；stdout/stderr 无 "SCRIPT ERROR"；report/capability.json 为合法 JSON
# 执行器须对 T2/T3 加 ≤180s 超时 + 结束后 pgrep 回收（SPIKE-001 report §5.5 教训）
# T3 渲染器双跑
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal    # 预期 0
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver opengl3 # 预期 0
# T4 进程残留核验
pgrep -l Godot                                                               # 预期 1（=无残留）
# T5 范围核验
git -C /Users/rain/DevGame/Fishing status --porcelain; git -C /Users/rain/DevGame/Fishing diff --stat
# 预期 0；已跟踪文件改动仅允许 tests/spike/overlay/**；未跟踪仅 tasks/evidence/** 与 AUTO-001 自身目录
# T6 产物机检
python3 -m json.tool /Users/rain/DevGame/Fishing/tests/spike/overlay/report/capability.json > /dev/null   # 预期 0
```

任何非 0 退出码：如实记录 stderr 原文并修码重跑，禁止改断言/伪造通过（godot-validation §4/§7、ACCEPTANCE §6）。

## 5. GUI 人工验收（needs_human=true；自动检查通过后工单只到 in_review，不置 done）

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/rain/DevGame/Fishing/tests/spike/overlay --rendering-driver metal
```

人工矩阵（README 更新后执行；键 1/2/3/9/Q 不变）：

| # | 步骤 | 判定标准 |
|---|---|---|
| G-001c | 默认（生产）态点透明区 vs 船体 | 透明区点击落到下方 App；船体响应（clicks+1）——**穿透修复判定** |
| G-001b | 键 1 整窗穿透 | 船体也不响应（对照组） |
| G-001a | 键 3 全拦截 | 透明区也被拦截（对照组） |
| G-001d | 生产态按住船体连续拖动 ≥200px（含快速甩动与急停） | 窗口平滑跟手、无往复抖动、松手即停不漂移——**抖动修复判定** |
| G-002a/b/c | 小幅点按 <6px / 拖动重启恢复 / 拖到边缘重启 | 同 SPIKE-001 README §2（C4 命令 `cat "$HOME/Library/Application Support/Godot/app_userdata/Fishing Overlay Spike/spike_window.json"` 在人工终端跑，代理沙箱内 err=7 属预期） |
| G-003a / G-004 | Retina 边缘锐利 / Label ≈30 FPS、隐藏停采样 | 同 SPIKE-001；headless 值不得冒充 GUI 证据 |

G-003b 多屏维持 NOT RUN（R-05，本机单内置屏）。

## 6. 风险与回滚

| 风险 | 处置 |
|---|---|
| macOS 对穿透多边形（尤其凹多边形）支持不足或语义与文档相反 | G-001c 如实记录实测语义后仅在本票内调整顶点；若根本不可行，**停下报批**双窗口替代方案（SPIKE-001 report §5.1），不得静默降级透明/穿透需求 |
| `DisplayServer.mouse_get_position` 不存在 | 探测式回退 `Input.capture_mouse` + `relative` 累加；两者皆缺则记 unsupported 并停 GUI 项待批 |
| headless 解析错误挂起（SPIKE-001 首轮教训） | T1 `--check-only` 前置 + 执行器超时/回收 + 事后 `pgrep`=1 核验 |
| 代理沙箱不可写 `user://` | C4 位置恢复由人工终端 GUI 执行；探针保留读回失败回退路径 |
| 抖动「无抖动」难以纯自动判定 | observed_state 增记拖动轨迹样本（t, dx, dy）供人工矩阵 G-001d 客观核对；不伪造自动判定 |
| 回滚 | Phase B 开工前记录 `git rev-parse HEAD`（当前 `e504324`）；回滚 = `git checkout -- tests/spike/overlay/` + 删除本票新增未跟踪产物；无任何 push/远端操作 |

## 7. 验收条目映射

| 工单摘要条目 | 验收来源 | 本票覆盖方式 |
|---|---|---|
| 修复鼠标穿透 | V01-W02 / G-001 / TECH_SPIKE §3.3 / SDD U05 | §1-A 修复 + 启动默认生产态 + G-001a/b/c 人工矩阵；T1–T3 自动门禁 |
| 修复窗口拖动抖动 | V01-W02 / G-002 / TECH_SPIKE §3.5「观察拖动卡顿」 | §1-B 坐标源修复 + G-001d 新增矩阵行 + 轨迹样本 |
| 透明无边框最小窗 + 30FPS | V01-W01 / V01-W03 / SDD-175 | 不改已证实设置；T2–T3 回归 + G-004 人工 |
| GUI 项需人工验收 | ACCEPTANCE §3/§6、AGENTS §4 | 全部 GUI 判定仅由 §5 人工执行；本票自动部分通过也只置 in_review |

## 8. 合规声明

本 Phase A 仅执行上表只读命令与文件阅读；唯一写入为本文件。未改任何代码/文档/schema；未读未写 `tasks/APPROVALS.md`；无 git 写操作；无子 Agent/fork/并行工作流/后台任务；无安装、无网络访问。本票为已批准 spike 范围内的缺陷修复，不改变 v0.1 需求边界、经济参数或 30FPS/20–60s 约束，不属于需求变更或破坏性操作；若 Phase B 中穿透多边形被证实不可行需改双窗口方案，将按 §6 停下报批。

## 9. 人工审核修正（Phase B 必须遵守）

本节为用户在 Phase A 完成后追加的审核意见。
如本节与 §1、§2、§5 或 §6 存在冲突，以本节为准。
不得删除原始计划中的历史记录。

### 修正 A：多边形鼠标穿透

原计划中“polygon 内为穿透区域”的说法错误。

Godot Window.mouse_passthrough_polygon 的实际语义：

- 多边形内部：接收鼠标事件。
- 多边形外部：鼠标事件穿透窗口。
- mouse_passthrough=true 时，多边形设置无效。

必须按以下方式实现：

full：
mouse_passthrough=true
mouse_passthrough_polygon=空数组

polygon：
mouse_passthrough=false
mouse_passthrough_polygon=Ship 实际可交互区域

off：
mouse_passthrough=false
mouse_passthrough_polygon=空数组

polygon 不允许使用“全窗口减去船体”的反向凹多边形。

### 修正 B：拖动抖动

鼠标按下时记录：
1. DisplayServer.mouse_get_position() 屏幕坐标
2. Window.position 窗口起始坐标

鼠标移动超过 6px 时进入拖动状态。
拖动位移使用当前屏幕坐标减去按下时的屏幕坐标。
不能使用 event.global_position 计算窗口移动位移。

禁止使用 Input.capture_mouse(true)，因为它不是有效的 Godot 4 API。

如果拖动仍然抖动或鼠标事件在移出 Ship 区域后丢失，
可以测试 DisplayServer.window_start_drag() 的原生窗口拖动方式。
保留点击与拖动的区分、位置持久化及人工验收要求。

### 修正 C：必须真实验收

Headless 测试通过不等于 GUI 通过。

人工验证：
1. full：全部穿透。
2. polygon：Ship 可点击拖动，其余透明区域穿透。
3. off：整个窗口拦截点击。
4. 连续拖动至少 200px，平滑、不抖动。
5. 松开鼠标立即停止。
6. 重启后正确恢复窗口位置。

只允许修改 tests/spike/overlay/**。
若无法达到要求，报告问题，不得伪造通过。
