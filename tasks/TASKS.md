# v0.1 原子开发工单 / Backlog

**状态：Planned / 全部未执行。** 必须由 Harness 读取本机真实工程和用户批准后更新状态。**严格串行**，只有一个本地 Flash。若前置测试失败，不得将依赖工单标记完成。

| ID | 标题 | 前置 | 主要交付 | 最小验收 |
|---|---|---|---|---|
| AUDIT-001 | 只读项目、环境、Skills、旧文档审计 | 无 | 文件清单、Godot/Git 状态、冲突/风险报告 | 真实命令证据；不修改工作树 |
| SPIKE-001 | macOS 透明/穿透/拖动探针 | AUDIT-001 + 人工批准 | 最小隔离窗口场景 + 结果报告 | GUI 实证 + headless 加载；G-001/002 |
| CORE-001 | 最小 Godot 工程/模块及测试入口 | SPIKE-001 | 主场景、分层模块、headless 自动测试基础 | Godot 无语法/导入错误 |
| CFG-001 | 3 鱼种 JSON + 配置校验 | CORE-001 | 配置加载和非法数据拒绝 | T-CONF-01 |
| FSM-001 | 捕鱼 FSM、随机时间、可控 RNG/时钟 | CFG-001 | 20–60s 等待、30 FPS 脱钩的业务状态机 | T-FSM-01、T-TIME-01/02 |
| ECO-001 | 唯一鱼实例/有限鱼篓/出售与金币模型 | FSM-001 | `GameState`、幂等命令、满篮阻断 | T-ECO-01～04（内存测试） |
| SAVE-001 | 原子存档、版本与故障注入 | ECO-001 | SaveService、崩溃恢复、状态提交 | T-SAVE-01～03、ECO 事务集成 |
| UI-001 | 临时猫/船+最小状态/售鱼/拖动 UI | SAVE-001 + SPIKE-001 | 桌面交互、简单鱼篮菜单 | G-001～005 和售鱼流程 |
| LOG-001 | 本地有限日志+错误提示 | SAVE-001 + UI-001 | 结构化事件、轮换、持久化警告 | T-LOG-01、T-UI-01 |
| SIM-001 | 多随机种子虚拟时间报告 | FSM-001 + ECO-001 + SAVE-001 | 1/4/8h 捕获、占比、篮满、价值统计 | SDD-178；重复交易/满篮新抛竿=0 |
| REL-001 | 全部回归+候选8h稳定性+人工验收 | 前述全部 | 测试报告、资源基线、问题清单 | `docs/ACCEPTANCE_TESTS.md` 放行门禁 |

## AUDIT-001（现在执行，只读）

**目标**：检查 `/Users/rain/DevGame/Fishing` 真实工作树、Git diff、是否已有 `project.godot`、Godot 4 版本和 headless、现有 SDD、项目和个人 Skills；比对本包并记录冲突。`Plan Mode` 中不得创建或修改文件。**验收**：清晰打印命令和退出状态，工作树没有由本工单引起的新增改动。

## SPIKE-001（第一张编码票；先获用户批准）

**允许位置**：`tests/spike/overlay/**` 或经审查同等隔离路径。不要覆盖已有场景与 `project.godot`。

**目标**：用 Godot 4 创建透明、无边框、临时船 sprite 的最小窗口；非交互透明处穿透鼠标，船身可点击/拖动；窗口位置可恢复，固定 30 FPS。**验收**：Mac 实际运行成功与失败截图/日志、Godot 命令、Retina/多显示器适配检查、headless 可加载；必须区分 GUI 与 headless 的证据。失败时记录技术阻断并请求替代方案审批。

## FSM-001（完整捕鱼时间与随机事件）

**范围**：`CASTING→WAITING→HOOKED→REELING→SETTLEMENT`，外加安全 `IDLE/PAUSED`；固定种子 RNG；虚拟 `Clock`；初始 20–60s 等待，每次配置采样。**不得**以 30 FPS 的帧数计算等待、不允许未完成结算就进下一次抛竿。**验收**：同一 seed/虚拟时间序列逐事件可复现、非法转换拒绝、暂停不生成额外交易。

## ECO-001 + SAVE-001（不可拆开的核心安全要求）

- 单一 GameState 权威，鱼实例/事件 UUID；10 格是候选容量，满篮暂停下一抛竿。
- 出售由人工通过最小 UI 调用，唯一 sale ID；若相同 ID 被重试，库存和金币绝不重复变化。
- 捕获/售鱼后写入版本化原子存档，**写入成功后**再通知视图已成功。
- 故障注入：临时文件写失败、重命名失败、崩溃、旧版本/损坏存档；保存失败须暂停不安全经济操作，不可删除坏档掩盖。
- 对同时接近结算的捕获与售鱼按单一命令队列串行处理，不允许超容量、双发、丢事件。

## SIM-001（平衡统计，不可自行改数值）

- 至少多组固定种子（建议首次 20 组）、虚拟时间模拟 1h、4h、8h，区分不售直到满篮、定期出售循环。
- 统计完整捕鱼周期、鱼篮首次装满时间分布、三鱼种占比及价值、重复事务与篮满后新抛竿次数。输出 JSON + 中文摘要。
- 20–60s、鱼价和容量的调节**必须由用户**批准，不得 Agent 为追求某个虚构 KPI 擅改。

## REL-001（最终放行）

Mac 上连续候选 8 小时运行；记录系统/Godot 版本、内存/CPU/FPS基线、出错事件、恢复行为。自动测试 100% 通过核心用例；用户明确批准后将 v0.1 标记 `Accepted`，才继续 v0.2。

## 工单状态格式

```text
ID: FSM-001
Status: Planned | In Progress | Review | Blocked | Accepted
Owner: Local Flash + DeepSeek Harness (serial)
Scope / Dependencies / Allowed files:
Interface & invariants:
Executed commands + exit codes:
Test result & evidence:
Git diff / commit (if approved):
Risks & unresolved decisions:
Owner approval where required:
```
