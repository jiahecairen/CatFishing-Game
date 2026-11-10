# DEV_LOG — Fishing v0.1 开发记录

> 只记事实：命令、退出码、可复核证据、未决风险。禁止把未执行的测试写成通过。
> 工作区：`/Users/rain/DevGame/Fishing` · 单 Agent 串行 · 无子 Agent / 无并行工作流。

---

## 2026-11-10 · AUDIT-001（只读审计）→ Review

### 执行环境与命令证据

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 工作树 | `find . -type f \| wc -l` | 0 | 审计前后均 **25** 个文件，无新增/删除/修改 |
| Git（审计时） | `git status --porcelain -b`、`git rev-parse --is-inside-work-tree` | **128** | `fatal: not a git repository`；父级目录亦无 `.git` |
| Git 可用性 | `git --version` | 0 | `git 2.50.1 (Apple Git-155)` |
| Godot 在 PATH | `command -v godot / godot4 / godot4-headless` | 1 | 三者均不存在（无 CLI 软链） |
| Godot 版本 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Godot CLI | 同上 `--help` | 0 | 可用：`--headless`、`--path`、`--scene`、`--max-fps`、`--rendering-driver`；macOS 驱动 `vulkan/metal/opengl3/opengl3_angle/dummy`；**无 `--do-string`** |
| Godot 工程 | `find -name project.godot -o -name '*.gd' -o -name '*.tscn'` | 0 | **不存在任何 Godot 工程/脚本/场景** |
| 导出模板 | `ls ~/Library/Application Support/Godot/export_templates` | 0 | 空目录（未装模板，不阻断 SPIKE-001） |
| 本机 Godot 状态 | `ls ~/Library/Application Support/Godot/app_userdata` | 0 | 另有 `Moon`、`Moon Star Collector`、`Snake Game`、`[unnamed project]`，与本工程无路径冲突 |
| 主机 | `uname -m -r`、`sw_vers`、`sysctl hw.memsize` | 0 | macOS **26.6.2 (25G83)**、Apple **M4 Max** (40 核 GPU, Metal 4)、**128 GB** |
| 显示器 | `system_profiler SPDisplaysDataType` | 0 | 仅 **1 块内置 Liquid Retina XDR 3456×2234**；无外接屏 |
| 模型服务存活 | `lsof -nP -iTCP:9931 -sTCP:LISTEN` | 0 | `llama` PID **9924** 监听 `127.0.0.1:9931` |
| 模型服务健康 | `curl -s --max-time 5 http://127.0.0.1:9931/health`（用户批准，仅本机回环） | 0 | `{"status":"ok"}` |
| 模型 ID/上下文 | `curl -s http://127.0.0.1:9931/v1/models`、`/props`（同上） | 0 | 见下方「模型环境结论」 |
| JSON 契约机检 | `python3` + `jsonschema` | — | **NOT RUN**：本机 Python 3.15.2 无 `jsonschema` 模块（`ModuleNotFoundError`）；未安装任何依赖。示例与 schema 仅做人工比对，一致 |
| 模型进程 RSS | `ps Ax -o pid,rss,comm` | 1 | `/bin/ps: Operation not permitted`（沙箱拒绝）→ RSS **未获得** |

### Skills 发现（当前 Standard 会话实测，非推断）

- 项目 3 个 Skills 全部**已发现并成功加载**：`godot-overlay`、`fishing-state-and-save`、`godot-validation`（`.dsh/skills/<name>/SKILL.md`，frontmatter 合法）。
- 用户个人 Skills：`~/.agents/skills/` 下 **67 个目录，全部 67 个出现在本会话技能目录**（含 `godot-gdscript`、`godot-nodes-scenes`、`save-systems`、`router` 等）。
- 另有 7 个 `office*` 技能存在于会话但不属于上述两个磁盘根（来自 Harness 内置提供者）。
- `~/.dsh/skills/` **不存在**；无 `.git` 时 Skill 项目根回退为工作目录，发现仍成功（现已有 `.git`，根仍为本目录，不受影响）。

### 模型环境结论（OPEN-005 部分关闭）

- `llama.cpp 0.9.0`（`/opt/homebrew/Cellar/llama.cpp/0.9.0/bin/llama`），router 模式 `max_instances: 1`、`--sleep-idle-seconds 300`。
- **唯一 `status: loaded` 的模型正是 `ggml-org/Qwen3.8-Flash-Next-GGUF:IQ4_NL`**，与本会话运行时模型 ID 完全一致 → AGENTS.md §0「单模型 + 单推理实例」要求**已满足**（其余 5 个 alias 处于 unloaded，未加载）。
- 该实例服务端 `--ctx-size 262144`、`n_ctx 262144`、`n_ctx_train 262144`、`ubatch_size 2048`、带 dflash 投机解码 draft 模型 → **256K 在服务端确实生效**。
- **仍未验证**：Harness 侧「单次最大输出 65536」是否被有效应用，以及长上下文下的实际资源占用/工具调用稳定性。OPEN-005 保持 **OPEN**。

### 冲突与风险（含用户裁定）

| ID | 发现 | 处置 |
|---|---|---|
| R-01 | 审计时无 Git 仓库，无法产出 diff 与回滚基线 | **已处置**：用户批准后 `git init -b main` + `.gitignore` + baseline commit `4d8ed4d`；**未配置远端、未推送** |
| R-02 | **文档冲突**：SPIKE-001 允许位置写 `tests/spike/overlay/**` 且「不要覆盖已有 `project.godot`」，但工程中**根本没有** `project.godot`（Godot 运行必需） | **用户裁定**：SPIKE-001 在 `tests/spike/overlay/` 内建立**独立 Godot 工程**（自带 `project.godot`），根目录不建入口；CORE-001 时再以 `.gdignore` 隔离或迁移为正式场景 |
| R-03 | 本机为 Godot **4.7.2**（比文档「4.x」更具体）；CLI **无 `--do-string`** | 能力探测改为在 spike 脚本内用 `get_property_list()` 打印，不预设 `mouse_passthrough_polygon` 等 API 存在 |
| R-04 | **审计副作用**：为探测 `--do-string` 曾启动一次 Godot 进程，未退出，60 s 后由 `job_kill` 终止（期间可能闪现编辑器/项目管理器）。`pgrep -l Godot` 复查无残留；工作树仍 25 文件、**无 `.godot/` 缓存** | 已如实记录，无文件污染 |
| R-05 | 仅单块内置屏 → 验收 **G-003**（主屏↔外接屏）当前**无法实测** | 后续接外接屏补测；本轮 SPIKE-001 报告记 **NOT RUN** |
| R-06 | macOS 26.6 + Godot 4.7.2 + Metal 下透明/`mouse_passthrough`/`mouse_passthrough_polygon` **均未验证** | SPIKE-001 的核心待验证项；**用户批准**在 spike 内自动对比渲染器与穿透变体并记录优劣，但**不得修改 v0.1 需求边界** |
| R-07 | OPEN-005 未完全关闭（65536 输出上限与长上下文稳定性未实测）；模型 RSS 因 `ps` 被沙箱拒绝而未取得 | 保持 OPEN；需要时改用活动监视器人工读数或另行批准采样方式 |
| R-08 | SDD **尚未冻结**（`REQUIREMENTS_CHANGELOG` 冻结清单 6 项全未勾选）；**OPEN-001**（窗口隐藏是否计入有效捕鱼时间）未裁定 | 不阻断 SPIKE-001；**必须在 FSM-001 之前**由用户一次性裁定，Agent 不得自行决定 |
| R-09 | `sale_price_at_catch`（捕获时价格快照）仅为建议合同；`basket_capacity=10` 为候选值 | ECO-001 开工前需用户确认 |
| R-10 | 导出模板未安装 | 不阻断 SPIKE/CORE；发行相关票前另行批准 |
| R-11 | `.DS_Store` 会污染版本库 | **已处置**：`.gitignore` 忽略（**文件保留未删除**，`git status --ignored` 可见） |

### 放行判定

- AUDIT-001 最小验收「真实命令证据；不修改工作树」：**PASS**（审计阶段零改动；`git status` 干净；无 `.godot/`）。
- 版本控制、SPIKE-001 落点与降级授权已获用户批准 → 进入 SPIKE-001。
- 尚未取得任何 GUI/自动化测试通过证据；SPIKE-001 结果须另行以「命令 + 退出码 + 截图 + 人工矩阵」记录。

---

## 2026-11-10 · SPIKE-001 → In Progress（仅计划批准，尚未写码）

- 批准范围：`tests/spike/overlay/**` 内**独立 Godot 工程**（含其自身 `project.godot`）＋ 用户数据目录 `user://spike_window.json`（不写入源码目录，见 `docs/INTERFACES_AND_DATA.md` §8）。
- 允许：在 spike 内自动对比渲染器（Metal / Compatibility）与鼠标穿透变体（全窗口穿透 / 穿透多边形 / 关闭穿透）并记录优劣。
- 禁止：修改 20–60 s、30 FPS、鱼篓容量、鱼价、售鱼规则；引入正式美术、猫创建、船舱、NPC、天气、图鉴、联机、付费；用 headless 结果冒充 GUI 证据。
- 回滚面：`tests/spike/overlay/` 整目录 + `user://spike_window.json`；版本控制基线 `4d8ed4d` 已就绪，可逐票 diff。
- 已知不可测项：**G-003（多显示器）NOT RUN**。
