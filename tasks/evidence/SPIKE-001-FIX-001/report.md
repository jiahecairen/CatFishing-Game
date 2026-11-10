# SPIKE-001-FIX-001 · Phase B 执行报告 — 修复鼠标穿透和窗口拖动抖动

- 工单：SPIKE-001-FIX-001（allowed_files=`tests/spike/overlay/**`，needs_human=true）
- 执行：AUTO-001 Phase B 单会话串行；无子 Agent/委派/fork/并行工作流/后台任务；无 git commit/merge/push/stash/reset/clean；未读取 `tasks/APPROVALS.md`；本票未新增任何批准记录。
- 开工基线（真实命令输出）：`git rev-parse HEAD` = `00ee38f537585bf62959cdb198d3610f75777684`；`git status --porcelain -b` = `## main`，已跟踪文件零改动，未跟踪仅 `tasks/evidence/SPIKE-001-FIX-001/`、`tasks/evidence/_runner/`。
- 环境：macOS · Godot `4.7.2.stable.official.ed1daf0bf`（本会话 T0 实测）。
- 实现依据：`plan.md` §1/§2，其中 §9 人工审核修正 A/B/C 优先（穿透多边形语义、拖动坐标源、禁用 capture_mouse）。

## 1. 改动文件清单（git diff --stat 实测，全部在 allowed_files 内）

| 文件 | 类型 | 改动 |
|---|---|---|
| `tests/spike/overlay/scripts/overlay_window.gd` | 修改（+101/−~30） | 修正 A：变体语义解耦 full/polygon/off（bool+polygon 表达，本构建无 `mouse_passthrough_mode`，删除 mode 分支）；启动默认 `polygon` 生产态；polygon=Ship 实际全局矩形（运行时 `get_global_rect()` 取值，非反向凹多边形）；full/off 显式清空多边形。修正 B：按下冻结 `DisplayServer.mouse_get_position()` 屏幕坐标 + `Window.position` 各一次，位移=屏幕坐标差，一次性取整；删除 `event.global_position` 位移与 capture_mouse 回退（探测缺失→记 unsupported 事件，不降级）；G-001d 拖动轨迹样本（≤400 点/次）。`_variant_log` 记录 `effective_mouse_passthrough`、`effective_mouse_passthrough_polygon`（顶点+点数）供 GUI 回填 |
| `tests/spike/overlay/scripts/capability_probe.gd` | 小改（+11） | 新增 `display_server_methods` 探测（`mouse_get_position` / `window_start_drag` / `get_display_safe_area`，ClassDB 探测式）；GUI 下记录 `mouse_get_position_value` 真实值 |
| `tests/spike/overlay/README.md` | 修改（+26/−12） | 键位说明更新（启动默认=变体 2 生产穿透态）；修正 A 语义（多边形内接收/外穿透）写入；新增 G-001d 抖动矩阵行；G-001c 改生产态判定+实测语义回填列；§4 增拖动坐标源与 window_start_drag 备选（启用须人工批准） |
| `tests/spike/overlay/report/capability.json` | 运行时再生成 | T2/T3 headless 产物 |
| `tests/spike/overlay/report/observed_state.json` | 运行时再生成 | 同上 |
| `tests/spike/overlay/report/variant_matrix.json` | 运行时再生成 | 同上 |

`project.godot`、`main.tscn` 未改（计划 §2 约定）；`tests/spike/overlay` 之外零改动（本文件与证据目录除外）。

## 2. 执行命令与真实退出码

超时无 `timeout`/`gtimeout`（仅 `/usr/bin/perl` 可用），用 `perl -e 'alarm shift @ARGV; exec @ARGV or die $!' 180 …` 实现 ≤180s 同步超时。

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| T0 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| T1a | `… --headless --path tests/spike/overlay --check-only --script res://scripts/overlay_window.gd` | 0 | 无 SCRIPT ERROR |
| T1b | 同上 `--script res://scripts/capability_probe.gd` | 0 | 无 SCRIPT ERROR |
| T2 | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing/tests/spike/overlay`（调度器 test_cmd） | 0 | 脚本自行 quit；无 SCRIPT ERROR |
| T3a | 同 T2 `--rendering-driver metal` | 0 | 同上 |
| T3b | 同 T2 `--rendering-driver opengl3` | 0 | 同上 |
| T4 | `pgrep -l Godot` | 1 | 1=无进程残留（符合预期） |
| T5 | `git status --porcelain` / `git diff --stat` | 0 / 0 | 已跟踪改动仅 `tests/spike/overlay/**` 6 文件；未跟踪仅 `tasks/evidence/**` 两目录 |
| T6 | `python3 -m json.tool report/{capability,observed_state,variant_matrix}.json` | 0 / 0 / 0 | 三份 JSON 均合法 |

## 3. 测试输出摘要（真实产物读回）

- `capability.json`：`display_server_methods = {mouse_get_position: true, window_start_drag: true, get_display_safe_area: true}`；`window_properties` 证实 `mouse_passthrough=true`、`mouse_passthrough_polygon=true`、**`mouse_passthrough_mode=false`（本构建无此属性，未调用）**。
- `observed_state.json` / `variant_matrix.json`：启动默认 `variant=polygon`，`variant_log` 含 `supported=true, applied=true, effective_mouse_passthrough=false, effective_mouse_passthrough_polygon=[[60,50],[160,50],[160,110],[60,110]] (4 点 = Ship 全局矩形)`；`max_fps=30`（SDD-175）；`drag_threshold_px=6`；events=`[position_restored_from_saved, variant:polygon, ready, position_saved]`。
- 已知噪音（预期内）：`user://logs/*.log` 与 `user://spike_window.json (err=12)` 写失败 = 代理沙箱不可写 `user://`（plan §6 风险表），退出码仍为 0；GUI 人工运行时由真实用户环境落盘。

## 4. 覆盖的验收条目

| 条目 | 状态 |
|---|---|
| 修复鼠标穿透（缺陷 A） | 代码修复完成（修正 A 语义解耦 + 启动默认生产态）；T1–T3 自动门禁通过；**穿透行为本身须 G-001a/b/c GUI 人工判定** |
| 修复窗口拖动抖动（缺陷 B） | 代码修复完成（修正 B 屏幕绝对坐标源，未用 global_position 位移、未用 capture_mouse）；T1–T3 通过；**无抖动须 G-001d GUI 人工判定**（`last_drag_samples` 供客观核对） |
| 透明无边框 + 30FPS 回归（V01-W01/W03/SDD-175） | 已证实设置未改动；T2/T3 回归通过，`max_fps=30` 读回 |
| 点击/拖动区分（G-002a）、位置持久化（修正 C-6） | 逻辑保留（6px 阈值、松手与退出写 `spike_window.json`、启动 clamp 安全区）；headless 已验证代码路径无错；实际恢复行为待 GUI G-002a/b/c |
| GUI 六项人工验证（修正 C：full 全穿透 / polygon 船体可交互其余穿透 / off 全拦截 / ≥200px 平滑拖动 / 松手即停 / 重启恢复位置） | **未执行，待人工**（headless ≠ GUI，AGENTS §4、godot-validation §2；README §2 矩阵已就绪） |

## 5. 遗留风险

1. **穿透/拖动语义为静态修复 + headless 语法/加载级验证**：macOS 26.6 + Metal 下 polygon 实际表现（含鼠标移出船体后事件是否丢失）与拖动平滑度只能由 GUI 人工矩阵（README §2）判定；工单按流程只到 in_review。
2. 若 GUI 实测仍抖动或移出船体事件丢失：备选 `DisplayServer.window_start_drag()` 原生拖动（capability.json 证实该方法在本构建存在）；属计划内已批准备选，启用前仍须人工批准，不静默换方案。
3. `user://` 在代理沙箱不可写（err=12）：位置持久化的真实往返（G-002b）须在人工终端 GUI 验证。
4. 拖动「无抖动」无纯自动判据：`last_drag_samples` 仅提供轨迹样本，最终判定归人工（不伪造自动判定）。
5. G-003b 多屏维持 NOT RUN（R-05，本机单内置屏）。

## 6. 回滚

回滚 = `git checkout -- tests/spike/overlay/` + 删除本票未跟踪产物（本证据目录新增文件由调度器处置）；基线 HEAD=`00ee38f537585bf62959cdb198d3610f75777684`；本会话无任何 git 写操作、无 push/远端操作。

## 7. 合规声明

本 Phase B 仅修改 `tests/spike/overlay/**` 6 文件（3 源 + 3 运行时产物）并在证据目录写本文件；未读未写 `tasks/APPROVALS.md`；未调用子 Agent/fork/并行工作流/后台任务；所有退出码来自真实命令输出；未改 `tasks/TASKS.md`/`docs/DEV_LOG.md`（状态回写归 AUTO-001 调度器）。未发现需停下报批的计划外需求变更或破坏性操作。
