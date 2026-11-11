# SAVE-001 Phase A 计划 — 原子存档 + 版本 + 故障注入（AUTO-001，只读规划）
- 保存用版本字段、原子替换策略、备份/恢复与事务幂等；保存失败后禁止把未持久化收入显示成已确认。

- 工单：SAVE-001「原子存档、版本兼容与故障注入」，前置 ECO-001（Accepted，`29032fd`/`c0860a0`）+ FSM-001（Accepted，`9edd9a6`），最小验收 **T-SAVE-01～03 + ECO 事务集成**（`docs/ACCEPTANCE_TESTS.md` §2）。Phase A 启动时队列为 `ready`；完成后转为 `awaiting_approval`，须经独立审查批准和配置 `test_cmd` 后才可执行 Phase B。
- 允许文件范围（Phase B 强制，队列与本票 brief 一致）：`scripts/save/**`、`schemas/game-save.schema.json`、`examples/save_v01.json`、`tests/**`。本 Phase A 全程只读，唯一写入即本文件；未读取/未修改 `tasks/APPROVALS.md`；零 git 写操作。
- 依据：`docs/INTERFACES_AND_DATA.md` §3/§5/§6/§7/§8、`docs/ARCHITECTURE.md` §2/§5、`docs/SDD_v0.1.md` V01-S01/S02/T01 与 §4 时序 5–7、`docs/DECISION_REGISTER.md` SDD-143/155-156/157-158/172-173、`docs/ACCEPTANCE_TESTS.md` §2/§6、`docs/REQUIREMENTS_CHANGELOG.md`（2026-11-11 委托冻结）、FSM-001 移交项（`tasks/evidence/FSM-001/report.md` R-2：SAVE-001 须持久化 RNG/Clock continuation 与 pending candidate）、ECO-001 移交项（`tasks/evidence/ECO-001/acceptance.md` L22：ledger 与 GameState/FSM 快照/候选一同安全持久化 + 故障注入 + 迁移/损坏路径）、项目 Skills `fishing-state-and-save`、`save-systems`、`godot-validation`。

## 1. Phase A 只读实测记录（真实命令与退出码，2026-11-11 本会话）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 文件结构 | `find . -path ./.git -prune -o -type f -print` | 0 | `scripts/{config,core,economy,fishing,io,platform,presentation}`、`schemas/`、`examples/`、`data/`、`tests/{unit,spike}`、`tools/auto` 均存在；**`scripts/save/` 不存在**（`ls -d scripts/save` → 1，Phase B 在允许范围内新建） |
| Git 状态 | `git status --porcelain` / `git rev-parse --short HEAD` | 0 / 0 | HEAD=`c50b566 Queue SAVE-001 for read-only planning`；工作树仅 `M tasks/evidence/_runner/runner.log`、`?? tasks/evidence/_runner/runner.lock`（AUTO-001 调度器自身状态文件，非本代理改动） |
| 近期历史 | `git log --oneline -15` | 0 | ECO-001 验收 `c0860a0`/`29032fd`/`2cf0ada`；FSM-001 验收 `9edd9a6`；证据链完整 |
| Godot 可执行 | `/Applications/Godot.app/Contents/MacOS/Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf`（仅版本探测，未以 `--path` 触碰主工程） |
| SaveService 骨架 | 读 `scripts/io/save_service.gd`（5 行） | 0 | `class_name SaveService`，注释明示「本票仅骨架，零实现」；**该文件不在 Phase B 允许清单内，不得改/删**（缺口 G-1） |
| schema v1 | 读 `schemas/game-save.schema.json`（54 行） | 0 | `save_version const 1`，9 个顶层必需键；无 ledger、无 RNG/Clock 快照、无候选 payload（`$comment` 声明需 GDScript 侧语义复检） |
| v1 示例 | 读 `examples/save_v01.json`（22 行） | 0 | v1 完整形状：空 ledger ids、IDLE checkpoint、窗口 80/80/220/160 |
| 权威状态 | 读 `scripts/core/game_state.gd`（15 行） | 0 | 纯数据镜像 v1 九字段；`scripts/core/**` **不在 Phase B 允许范围**（缺口 G-2/G-4） |
| ECO 账本 | 读 `scripts/economy/economy_service.gd`（439 行） | 0 | `set_persistence_gate(callable)`：门收 `{next_state(完整 GameState 深拷贝), ledger(快照)}`，仅布尔 `true` 发布；`snapshot_ledger()/restore_ledger()` fail-closed（恰 2 键、逐指纹形状、与 processed ids 集合一致、已出售实例不得在篮 → `BAD_LEDGER`）；错误码稳定（PERSIST_FAILED/ALREADY_APPLIED/CONFLICT_*/GOLD_OVERFLOW…） |
| RNG/Clock | 读 `scripts/fishing/deterministic_rng.gd`、`virtual_clock.gd` | 0 | `DeterministicRng.snapshot_state()/restore_state()`＝`{version:1,seed,state}`（Lehmer LCG，seed/state∈[1,2^31-2]，非法零副作用）；`VirtualClock.snapshot_state()/restore_state()`＝`{version:1,now}`（非有限/负拒绝） |
| FSM 接口 | 读 `scripts/fishing/fishing_state_machine.gd`（490 行） | 0 | `snapshot_checkpoint()` 恰 4 键镜像 v1 `fishing_checkpoint`；`produce_catch_candidate()` 重试幂等重放同 payload（不重抽 RNG）；`initialize(...)` 可携 checkpoint 续跑并交叉校验；**无 restore-candidate API**（缺口 G-3）；文件注释明示 RNG/Clock/候选 payload 由 SAVE-001 持久化 |
| 测试基线 | 读 `tests/unit/run_eco001_checks.py`（196 行）+ `test_eco001_economy.gd` 等 | 0 | 既有约定：SceneTree 脚本 PASS→quit(0)/FAIL→quit(1)；runner 先复制工程到系统临时目录 + 隔离 HOME/XDG 再串行跑 Godot（导入→本票→ECO/CORE/CFG/FSM 回归），PASS 标记恰一次、禁 `SCRIPT ERROR`、value-lock（data==examples 与 20/60/30/10/鱼价）Python 复核；**禁止对主工程路径跑 Godot** |
| 队列 | `python3 -c json.load(tools/auto/queue.json)` SAVE-001 | 0 | `allowed_files=[scripts/save/**, schemas/game-save.schema.json, examples/save_v01.json, tests/**]`，与本计划 §3 清单一致 |
| 移交项 | grep `SAVE-001` `tasks/evidence/{ECO-001,FSM-001}/*.md` | 0 | ECO/FSM 两侧验收文档均确认落盘、崩溃注入、RNG/Clock/候选持久化归本票 |

## 2. 目标 / 不做

**目标（Phase B 交付）：**

1. `scripts/save/` 新实现 `AtomicSaveService`：save **v2** 文档的原子提交（同目录临时文件 + 显式错误检查 + flush + 回读验证 + 备份 + 原子 rename）、fail-closed 加载（主档→备份→拒绝）、坏档保留（惰性隔离改名而非删除）、未来版本拒绝、v1 安全迁移（§4.4）。存档目录生产默认 `user://`（INTERFACES §8，不落源码树），测试注入显式临时目录。
2. **一份原子文档覆盖全部跨崩溃状态**：完整 GameState 九字段（v1 集）+ `economy_ledger`（= `EconomyService.snapshot_ledger()` 形状）+ `rng_snapshot`（= `DeterministicRng.snapshot_state()`）+ `clock_snapshot`（= `VirtualClock.snapshot_state()`）+ `pending_candidate`（FSM 候选 payload 或 null）。
3. **经济发布门**：把 SaveService 原子提交注入 `EconomyService.set_persistence_gate`；仅当整份文档同目录 rename 成功（应用级原子提交点）才返回布尔 `true`；任何失败 → `PERSIST_FAILED`、内存权威态与账本零副作用（INTERFACES §6 / ARCHITECTURE §5 顺序：校验 → 构造 next → 写盘 → 成功才发布）。`flush()+rename` 的保证边界不得描述为断电级 durable；报告注明目录元数据/硬件缓存的断电保证无法由本票证明。**禁止先发布金币/鱼篓再异步写盘。**
4. **无静默丢失的 v1→v2 迁移**：仅迁移可证明安全的 v1 状态；v1 已处理事务缺少指纹账本时**拒绝加载并保留原档**，绝不猜造幂等数据、绝不静默丢弃（§4.4）。
5. 故障注入 seam（仅 `scripts/save/` 内部）：tmp 写入 / flush / 备份 / rename / 隔离改名五个注入点 + 发布边界（rename 后、内存发布前「崩溃」）测试；恢复结果**只允许完整旧态或完整新态**。
6. headless GDScript 测试 + Python 标准库 runner（镜像 ECO/FSM 约定），回归 ECO/CORE/CFG/FSM；所有 Godot 仅在隔离临时副本 + 隔离 HOME 内运行。
7. schema v2 重写 `schemas/game-save.schema.json`（本票允许文件）；`examples/save_v01.json` **保持 v1 原样不动**（作为迁移测试的合同输入；v2 示例由测试运行时在临时目录生成——`examples/save_v02.json` 不在允许范围）。

**不做（越界即违规）：** UI/售鱼面板（UI-001）、日志文件与轮换（LOG-001）、经济参数/20–60s/30FPS/容量/鱼价任何改动、联网/云、SDD 产品范围变更；不修改 `scripts/core|economy|fishing|config|io|platform|presentation/**`、`data/**`、`scenes/**`、`project.godot`、`docs/**`、`tasks/TASKS.md`（状态记录按既定 AUTO-001 流程由调度器/审查执行，不由本票 Phase A 改写）。

## 3. Phase B 要改动的文件（严格限于允许范围）

| 文件 | 动作 | 说明 |
|---|---|---|
| `scripts/save/save_service.gd` | 新建 | `class_name AtomicSaveService extends RefCounted`：路径管理（默认 `user://game_state.json`，测试显式注入目录）、`install_into(economy,state,rng,clock,fsm,valid_species_by_id)`（装配并注入门）、`set_pending_candidate(candidate,caught_at_utc)/clear_pending_candidate`、`persist_runtime_checkpoint()->{ok,code,report}`（经济事务外的完整检查点提交）、`atomic_commit(payload)->{ok,code,report}`、`load_save(valid_species_by_id,fresh_seed:=1)->{ok,code,report,state,ledger,rng_snapshot,clock_snapshot,pending_candidate}`、`set_fault_injection(stage,armed)`（仅测试）、`get_last_report()`；内部 `_gate(payload)->bool` 仅布尔 true 放行 |
| `scripts/save/save_validate.gd` | 新建 | `class_name SaveValidate`：v2 文档 + v1 旧形静态 fail-closed 校验（§4.3 全部语义不变量），单一实现被 commit/load/迁移三路复用；按已验证 catalog map 校验种类与候选快照；错误码常量表 |
| `scripts/save/save_faults.gd` | 新建 | `class_name SaveFaults`：测试专用故障注入登记表（`tmp_write/tmp_flush/backup/rename/quarantine/legacy_copy`），生产默认全关；不含任何产品行为 |
| `schemas/game-save.schema.json` | 重写 | v2 契约（§4.2）：`save_version const 2`、13 个顶层必需键、`additionalProperties:false`；`$comment` 记录 v1 为只读 legacy（由 SaveValidate 处理）与语义复检清单 |
| `examples/save_v01.json` | 不改（零 diff） | 保留为 v1 legacy 合同示例；runner 校验其仍为 `save_version:1` 且逐值不变 |
| `tests/unit/test_save001_save.gd` | 新建 | `extends SceneTree` 无头测试，S0–S8 矩阵（§5），PASS 标记 `SAVE001 SAVE PASS` 恰一次→quit(0)，任何失败 `SAVE001 SAVE FAIL`→quit(1) |
| `tests/unit/run_save001_checks.py` | 新建 | Python 标准库 runner，镜像 `run_eco001_checks.py`：前置检查（交付文件齐全、value-lock、schema v2 必需键、v1 示例未动、无 `scripts/io` 类名冲突回归）→ 复制工程到临时目录（排除 .git/.godot/tasks/evidence）→ 隔离 HOME/XDG → 串行 6 步 Godot（§5.3）→ 全步 exit 0 且标记齐全才退出 0，否则 1 |

**接口缺口清单（本票不越界；由 Phase B 前独立审查裁定，Phase B 内先用 §4.5 协议在自身范围内闭合）：**
- G-1 `scripts/io/save_service.gd` 骨架已占用全局类名 `SaveService` 且不在允许范围 → 新类名 `AtomicSaveService`，旧骨架成为零引用死代码；删除/迁移骨架另立审查。
- G-2 `GameController`（`scripts/core/`）不接线：本票交付「装配协议」（§4.5）并由测试装配复刻真实启动/崩溃/重启序列；正式接线归 UI-001 或审查另批。
- G-3 FSM 无 `restore_pending_candidate()`：恢复时直接把存档里的原 candidate payload 交给 `commit_catch`，不调用 `produce_catch_candidate()` 重新抽样；现有 FSM 在 SETTLEMENT 可按 event ID `ack_settlement(true)`。测试锁定该直接重放流程，不改 FSM。
- G-4 `GameState` 无 rng/clock/candidate 字段：三类 payload 由 v2 文档独立承载，load 后由调用方注入新 RNG/Clock 实例（与 FSM-001 review-followup #4「独立保存值恢复」一致），不改 GameState。

## 4. 接口与不变量

### 4.1 v2 文档（顶层恰 13 键，`additionalProperties:false`）

1–9 与 v1 完全同形同义：`save_version:2`、`revision`、`wallet_gold`、`basket_capacity`、`basket`（元素恰五键）、`processed_catch_ids`、`processed_sale_ids`、`fishing_checkpoint`（恰四键，schema v1 原枚举）、`desktop_window`（恰五键）。新增：

10. `economy_ledger`：恰 2 键，与 `EconomyService.snapshot_ledger()` 逐形状一致——`processed_catches: {catch_id: {species_id, caught_at_utc}}`、`processed_sales: {sale_id: 非空去重 instance_id 字符串数组}`。
11. `rng_snapshot`：恰 3 键 `{version:1, seed:int∈[1,2^31-2], state:int∈[1,2^31-2]}`（`DeterministicRng.snapshot_state()` 形状）。
12. `clock_snapshot`：恰 2 键 `{version:1, now:有限数≥0}`（`VirtualClock.snapshot_state()` 形状）。
13. `pending_candidate`：`null` 或恰 6 键 `{version:1, catch_event_id, species_id, weight_snapshot:{catch_weight>0, base_price 非负整数值, rarity}, caught_at_clock: 有限数≥0, caught_at_utc: 合法 UTC 秒级时间戳}`。这是 FSM 候选业务字段加上首次落盘前捕获的 UTC 时间与格式版本；`caught_at_clock` 只用于逻辑时间复现，`caught_at_utc` 供 `EconomyService.commit_catch`/`FishInstance` 使用，二者不可互相伪装；`ok/code` 信封键**不持久化**。

### 4.2 提交协议（`atomic_commit`，每步显式检查错误，任一失败即中止）

```text
0 注入故障（仅测试 seam）→ 对应稳定错误码
1 校验 payload 全量（SaveValidate v2 语义，fail-closed，零文件动作）
2 固定键序构造文档 → JSON.stringify（键序固定 ⇒ 字节确定，可断言）
3 同目录唯一临时文件（含本进程唯一后缀）：FileAccess.WRITE → store_string
  → get_error()==OK → flush() → close()；重新打开回读：可解析、save_version==2，
  `get_length() == json.to_utf8_buffer().size()`（不能用字符数代替 UTF-8 字节数）；TMP_VERIFY_FAILED 也算失败。
4 备份：先完整验证当前 main。仅当 main 是有效 v1/v2 时，才复制到同目录 backup-temp，校验字节相同，再 rename backup-temp → `.bak`；主档始终保留。若 main 缺失或损坏、当前状态是从有效 `.bak` 恢复出来，则**绝不**用缺失/损坏 main 覆盖 `.bak`；原有有效备份保持字节不变。备份替换失败即中止，旧 main 不变。
5 若当前主档是 v1，或 main 损坏/缺失而当前状态来自备份或安全初始态：在 main-temp 已完整验证后，将原件（若存在）**复制**到唯一 `.legacy.<n>.json` / `.corrupt.<n>.json`（临时副本校验后 rename 到保留名）；整个过程中 main 原件保持在场。任何保留副本失败即中止。main 损坏时保留原有 `.bak`，绝不能以坏 main 覆写它。
6 原子替换：DirAccess.rename_absolute(main-temp → main)；返回 OK 才算应用级提交成功（先发布金币/鱼篓被禁止）。Godot 4.7.2 本机临时工程探针验证了目标文件已存在时 copy 和 rename 均返回 OK，且 rename 后 main 内容完整替换；Phase B 仍须在隔离 runner 里回归该行为。
7 失败路径：尽力删除本次唯一临时文件；绝不删除或移走 main/.bak/legacy/corrupt 原件；返回 false + 稳定码。失败发生在 main rename 前，原 main 字节必须保持不变。
```

崩溃窗口分析：main rename 前任何阶段崩溃 ⇒ main 仍是完整旧态（bak/保留副本可能缺失或无效，加载时逐字节/语义校验且坏副本不阻断好 main）；rename 成功后崩溃 ⇒ main 是完整新态。任意时刻主档恢复结果**只可能是完整旧态或完整新态**（T-SAVE-02）；flush 不等于可证明的断电级 fsync。

### 4.3 加载/恢复协议（`load_save`，全链 fail-closed、坏档保留）

- 校验顺序：读 main → 解析 + SaveValidate v2 全量语义 ⇒ 采用（code `OK`）。
- main 缺/坏 ⇒ 读 bak 校验 ⇒ 采用（`RECOVERED_FROM_BACKUP`），坏 main **字节原样保留**；直到下一次**成功提交**前，先把坏 main 惰性复制并校验到 `game_state.corrupt.<seq>.json`（seq 递增取首个可用；原件不移动、不删除，可审计），隔离失败 ⇒ `QUARANTINE_FAILED` 且放弃本次提交（不覆盖任何文件），且原有有效 `.bak` 字节保持不变。
- main `save_version > 2` ⇒ `VERSION_NEWER`：拒绝加载、零写入、原档保留（T-SAVE-03「未知未来版本不悄悄覆盖」）。
- main `save_version == 1` ⇒ 迁移策略见 §4.4。`save_version` 非 int/缺键 ⇒ `MAIN_CORRUPT`。
- 主备皆坏/皆缺 ⇒ `NO_VALID_SAVE`：拒绝、零写入、全部原档保留；调用方据此创建干净初始态（不覆盖坏档，走同一惰性隔离路径）。
- **加载全量语义复检（SaveValidate，全部 fail-closed）**：v1 既有 `$comment` 清单（basket ≤ capacity；instance/source ID 唯一；鱼恰五键且 UTC 合法；processed ids 非空唯一）＋ 新增交叉一致性：
  - `economy_ledger` 两侧键集合 == `processed_catch_ids`/`processed_sale_ids` 集合（与 `restore_ledger` 同判据）；账本称已出售实例不得仍在篮；
  - 篮中每条鱼的 `source_event_id` ∈ `processed_catch_ids`，且其账本指纹 == `{species_id, caught_at_utc}`（捕获指纹可证）；
  - `wallet_gold` 只按 schema 校验为非负整数；不得额外要求它与 `processed_sale_ids` 非空相关联（现有 GameState/schema 没有此不变量，合法余额不可因该推断被拒绝）；
  - `basket`、catch ledger 指纹及 pending candidate 中的 `species_id` 必须属于调用方在配置门通过后传入的 `valid_species_by_id`；不匹配则拒绝加载，不能让未知鱼种进入运行状态；
  - pending candidate 的 `weight_snapshot` 必须与同一已验证目录中该鱼种的 `catch_weight/base_price/rarity` 逐值相同；不相同以 `CANDIDATE_CONFIG_MISMATCH` 拒绝恢复，避免 `EconomyService.commit_catch` 使用不同目录价格结算。篮内已有鱼仍以 `sale_price_at_catch` 为权威，不与当前目录价格比较；
  - pending candidate 的 `caught_at_utc` 必须通过 `FishInstance.timestamp_valid`；不合法则拒绝加载，不能把 FSM 逻辑秒数传给经济层伪装成 UTC；
  - `rng_snapshot`/`clock_snapshot` 形状与值域合法（另由调用方 `restore_state` 二次 fail-closed 验证）；
  - `pending_candidate != null` ⇒ `fishing_checkpoint.state == "SETTLEMENT"` 且 `checkpoint.event_id == candidate.catch_event_id`；若该 catch_id 已在 `processed_catches` ⇒ 指纹 `species_id` 必须 == candidate 的 `species_id`（已提交未 ack 的合法窗口，重启后重试得 `ALREADY_APPLIED`，不重复放鱼）；
  - checkpoint 形状四键合法（语义细校验由 `FishingStateMachine.initialize` 既有交叉校验兜底，双保险）。

### 4.4 v1 → v2 迁移（无静默丢失；禁止猜造幂等数据）

**可证安全判据（全部满足才迁移，code `MIGRATED_V1`）：** v1 文档全量合法 且 `processed_catch_ids == []` 且 `processed_sale_ids == []` 且 `basket == []` 且 `fishing_checkpoint.state == "IDLE"`。此时不存在任何需要指纹重建的已处理事务、不存在需要 RNG/Clock continuation 的活动周期、不存在候选——迁移是纯形状升级：字段 1–9 原样拷贝；`economy_ledger={"processed_catches":{},"processed_sales":{}}`；`rng_snapshot={"version":1,"seed":S,"state":S}`（S = `load_save(fresh_seed)` 显式入参，报告注明「新造种子，无历史连续性声明」——v1 从未持久化种子，声称续跑才是造假）；`clock_snapshot={"version":1,"now":0.0}`；`pending_candidate=null`。

**拒绝迁移（fail-closed，零写入，原档字节保留，code `VERSION_LEGACY_UNSAFE` + 原因）：**
- `processed_*_ids` 非空：v1 无指纹 ⇒ 出售清单与已捕获后售出的鱼种/时间戳不可重建；`restore_ledger` 要求键集合与指纹逐一对账，伪造空指纹或从残篮「猜」指纹都会破坏异参冲突检测（ECO review 条件 5）。唯一诚实处置＝拒绝 + 保留，等人工从原始来源重建或裁定降级方案（本计划不自行裁定）。
- `fishing_checkpoint.state != "IDLE"`：活动周期缺 RNG/Clock 快照 ⇒ 跨崩溃逐事件重放不可证（FSM-001 R-2），拒绝 + 保留。
- v1 部分迁移「篮子还能救」的混合方案被显式否决：半迁移即静默丢失，违反工单「不得猜造幂等数据/不得静默丢弃」。

迁移结果仅在**下一次成功提交**时按 §4.2 写入（load 本身不重写原 v1 文件）；首次覆盖前先复制并校验旧 v1 字节到唯一 `game_state.legacy.<seq>.json`，main 原件一直留在原路径，直到完整 v2 temp 和 legacy 副本都成功后才原子替换。rename 失败/进程崩溃仍可由 v1 main 重新迁移；不得先把 v1 main rename 移走。

### 4.5 装配协议（测试装配 = 未来 GameController 的蓝图）

启动：读取配置门通过的 catalog 并构成 `valid_species_by_id` → `load_save(valid_species_by_id)` ⇒ 新 `GameState` + 新 `DeterministicRng/VirtualClock` 实例 `restore_state`（非 ok 即中止）+ `FishingStateMachine.initialize(..., recovered_checkpoint)` + `EconomyService.initialize` 后 `restore_ledger`（非 ok 即中止）。若有 `pending_candidate`，先确认其 species 与权重/价格快照和本次已验证 catalog 一致，再把**加载出的原 payload**直接提交给 EconomyService，并使用 payload 内稳定的 `caught_at_utc`；不要在重启后的 FSM 上调用 `produce_catch_candidate()` 来替代它（FSM 未恢复 `_candidate_issued`，会消耗下一 RNG 值并生成不同鱼）。现有 FSM 已可在 SETTLEMENT 对同 event_id `ack_settlement(true)`，无需改 FSM。
捕获结算：`fsm.produce_catch_candidate()` ⇒ 调用方仅取一次 `raw_utc = Time.get_datetime_string_from_system(true)`；Godot 4.7.2 实测 raw 形状为 `YYYY-MM-DDTHH:MM:SS`（无 `Z`），必须先严格验证这个 19 字符 UTC 形状，再构造 `caught_at_utc = raw_utc + "Z"` 并通过 `FishInstance.timestamp_valid`，任一步失败都暂停结算 ⇒ `save.set_pending_candidate(c,caught_at_utc)` 将 UTC 与 FSM 逻辑 `caught_at_clock` 一并固定到深拷贝候选 ⇒ `save.persist_runtime_checkpoint()`（先持久化未确认候选和 SETTLEMENT checkpoint；失败时禁止经济提交）⇒ `economy.commit_catch(state,id,species_id,pending_candidate.caught_at_utc)`（门内 `atomic_commit` 携 live rng/clock 快照 + 当前 checkpoint 与候选）⇒ 成功后 EconomyService 发布 ⇒ `fsm.ack_settlement(id,true)` ⇒ `save.clear_pending_candidate()` ⇒ `save.persist_runtime_checkpoint()` 持久化 IDLE/null-candidate；若这一步失败，磁盘仍保存已提交 catch + 原候选，重启走 ALREADY_APPLIED 后再 ack，不重复放鱼。UTC 字段只作鱼实例元数据，不参与有效捕鱼计时、RNG 或价格选择。
出售：`economy.sell_fish(...)`（门内同文档，含 live rng/clock/checkpoint；售鱼不抽样，RNG 快照仅为连续性载体）。
**经济事务以外的运行时 checkpoint**：`persist_runtime_checkpoint()` 从当前 bound `GameState`、`snapshot_ledger()`、RNG/Clock snapshots、`fsm.snapshot_checkpoint()`、pending candidate 构造完整副本；将副本 revision +1、存档版本归一为 2；成功 rename 后才发布 `state.fishing_checkpoint/revision/save_version`，失败三者保持原值。调用契约：启动/抛竿后、每次 FSM 状态转换、隐藏/暂停前及恢复后、pending candidate 产生/清除后立即调用；WAITING 中按**有效捕鱼时间最多每 5 秒**做一次有界 checkpoint，不逐渲染帧写盘。5 秒是存档恢复精度实现值，不改 20–60 秒捕鱼参数；在 Phase B 报告中量化 IO 成本。`_gate` 也必须把实际 `fsm.snapshot_checkpoint()` 覆盖到 next-state 副本，避免经济事务保存陈旧 checkpoint。

存档 `save_version` 是磁盘格式版本。新 GameState 默认仍为 v1 形状；首次成功提交时文档写 v2，且仅在 rename 成功后把 bound state.save_version 设为 2；失败不得预先改版号。载入 v2 后返回 state.save_version=2。该映射不改 `scripts/core/game_state.gd`。

不变量汇总：门只认布尔 true；发布只在 main rename 成功后；`revision` 随每次成功经济提交或运行时 checkpoint +1 单调；`wallet_gold` 非负整数；`basket ≤ capacity`；一 catch 事件 ≤1 鱼、一 sale 事件 ≤1 次加币跨崩溃成立（由文档内 processed ids + ledger 指纹共同保证）；坏档永不删除；本票全部新类为纯 RefCounted，不写源码树或依赖帧计数，不触碰 UI/日志。

## 5. 测试计划（精确命令与预期退出码）

### 5.1 测试文件

`tests/unit/test_save001_save.gd`（SceneTree 无头，逐用例断言，全部经 §5.2 断言后打印唯一 PASS 标记）与 `tests/unit/run_save001_checks.py`（隔离副本 runner）。测试 IO 全部写 `OS.get_temp_dir()/save001_test_<case>/` 显式目录；runner 另将 HOME/XDG 指入临时目录——双保险，源码树与真实用户目录零写入。

### 5.2 用例矩阵（标记 `SAVE001 SAVE PASS` 恰一次）

| 用例 | 覆盖 | 关键断言 |
|---|---|---|
| S0 前置 | — | 三个新类可构造；完整合法的默认 GameState + 空 ledger/RNG/Clock/IDLE 文档写到临时目录成功；main 文件存在；重复 install_into 幂等拒绝 |
| S1 重启一致（**T-SAVE-01**） | 完整文档 | 提交后 `load_save` 入全新 GameState/EconomyService/RNG/Clock/FSM：wallet、basket（逐鱼五键）、processed ids、checkpoint、`desktop_window` 窗口位置、ledger 双侧指纹、rng seed/state、clock now、candidate 逐字段 == 崩溃前；重复加载逐字节同 JSON |
| S2 故障注入（**T-SAVE-02**） | 六注入点 | `tmp_write/tmp_flush/backup/rename` 在有效旧 main 上逐项注入；`quarantine` 用坏 main + 好 bak；`legacy_copy` 用可安全迁移的 v1 main。各注入验证门拒绝、经济事务为 `PERSIST_FAILED`（迁移路径返回明确迁移错误）、GameState/ledger 零副作用、原 main 字节不变、已存在的好 `.bak` 不变且仍可恢复、重试可成功、无残留临时文件；`set_fault_injection` 关闭后行为与无 seam 相同 |
| S2b 发布边界崩溃（**T-SAVE-02/03**） | rename 后发布前崩溃 | rename 成功即丢弃内存发布（模拟崩溃、新建全部服务实例）⇒ 加载 == **新完整态**（磁盘权威，内存发布只是纯赋值不可能丢）；对崩溃前事件重试：catch/sale 均 `ALREADY_APPLIED`，鱼/金币零增量——不存在「半个出售」中间态可被加载 |
| S3 未来版本/损坏（**T-SAVE-03**） | 坏档保留 | `save_version:99` 主档 ⇒ `VERSION_NEWER` 拒绝且文件字节不变、无 tmp/bak 副作用；主备皆坏 ⇒ `NO_VALID_SAVE` 全保留；坏 main + 好 bak ⇒ `RECOVERED_FROM_BACKUP` == 旧完整态；提交前复制坏 main 到 `game_state.corrupt.1.json` 并校验，成功后新 main 是完整新态、原好 `.bak` 保持不变；注入 quarantine/rename 失败时原坏 main 与好 `.bak` 字节均不变且仍可从 `.bak` 恢复 |
| S4 v1 迁移（**T-SAVE-03** + 无静默丢失） | 迁移安全 | v1 示例（空 ids/IDLE/空篮）⇒ `MIGRATED_V1`，13 键逐值符合 §4.4（空 ledger、新造 seed 注明、clock 0、candidate null）；另外 v1 wallet_gold>0 但无 processed IDs 时余额原样保留；v1 带 processed ids ⇒ `VERSION_LEGACY_UNSAFE` + 文件字节不变（零写入、零伪造）；v1 带 WAITING ⇒ 同拒绝；畸形 v1 ⇒ `MAIN_CORRUPT` |
| S5 跨服务重启（**ECO 事务集成** + T-ECO-02/03 持久化侧） | 幂等跨崩溃 | catch 提交→模拟崩溃（全新服务 + `load_save` + `restore_ledger`）→ 同 ID 同参重试 `ALREADY_APPLIED` 且篮不增；同 ID 异参 `CONFLICT_CATCH_PARAMS`；sale 同构（金币不重复、`CONFLICT_SALE_PARAMS`）；账本篡改（缺键/多键/尺寸不符/已出售鱼仍在篮）⇒ `BAD_LEDGER` fail-closed 且内存账本不变 |
| S6 确定性续跑（FSM 集成，T-TIME-01/02 持久化侧） | RNG/Clock 续跑 | 固定 seed 跑到 WAITING 中途调用 `persist_runtime_checkpoint()`（另测每次 transition checkpoint）→模拟崩溃→新 RNG/Clock `restore_state` + FSM `initialize(checkpoint)` 续跑→事件时间轴（event_id、wait、species、at_clock）与从该已提交 checkpoint 开始的参考跑逐字段一致；检查 checkpoint 周期不超过 5 有效秒且不逐帧写盘 |
| S7 pending candidate（**T-SAVE-01/02**） | 候选载荷 | SETTLEMENT 产候选，按实测格式严格校验 Godot UTC raw 并补 `Z` 后通过 `FishInstance.timestamp_valid`→set→`persist_runtime_checkpoint()` 持久化未处理候选→崩溃→load 后核对 catalog 快照，再把**该持久化 payload**中的 `catch_event_id/species_id/caught_at_utc` 交给 `commit_catch`（不重新调用 FSM produce、不把逻辑秒数伪装成 UTC）→成功 1 鱼→`ack(true)`→clear→再 `persist_runtime_checkpoint()`→再崩溃→load：candidate null、checkpoint IDLE、ledger 含该 catch→重试 `ALREADY_APPLIED` 不重复放鱼；另测 commit 已成功但 ack 前崩溃：磁盘候选+processed catch 同存，重启同 payload retry == `ALREADY_APPLIED`，异参 == CONFLICT；候选配置快照不匹配时 fail-closed 且不提交 |
| S8 门契约回归（INTERFACES §6） | 发布门 | 门返回 false/非 bool/失效 Callable ⇒ `PERSIST_FAILED` 零副作用（ECO 既有语义在真实门下的回归）；门返回 true 仅当 rename OK（注入 rename 失败 ⇒ false）；成功路径发布一次且仅一次 |

### 5.3 命令与预期退出码（Phase B 验收；回填队列 `test_cmd`）

| 命令 | 预期 |
|---|---|
| `python3 -B tests/unit/run_save001_checks.py`（工作目录=项目根；runner 内部才复制隔离副本） | **0**（任何断言/标记/退出码不满足 → 1，打印 `SAVE001 RUNNER FAIL`，不伪造） |
| runner 内 step1 `Godot --headless --path <副本> --editor --quit` | 0（先导入再测） |
| step2 `Godot --headless --path <副本> --script res://tests/unit/test_save001_save.gd` | 0 且 stdout 恰含一次 `SAVE001 SAVE PASS`、无 FAIL/`SCRIPT ERROR` |
| step3–6 回归 `test_eco001_economy.gd` / `test_core001_smoke.gd` / `test_cfg001_config.gd` / `test_fsm001_fsm.gd` | 各 0，标记各恰一次（ECO/CORE/CFG/FSM 回归，前置红即整票红） |
| `python3 -B tools/auto/runner.py selftest` | 0（调度门禁自测） |
| `git diff --check` | 0 |
| runner 前置 value-lock（Python）：`data/*.json == examples/*.json` 逐值、20/60/30/10/鱼价权重锁、`examples/save_v01.json` 仍 `save_version:1` 逐值不变、schema `save_version const 2` 与 13 必需键、`scripts/save/` 三文件存在 | 全过才进入 Godot 步骤 |

**禁止**：对主工程路径（`/Users/rain/DevGame/Fishing`）启动任何 Godot `--path`（用户常驻编辑器在跑）；测试失败后擅改断言或伪造 `pass:true`；写入真实 `user://` 或源码树。

## 6. 风险与回滚

| # | 风险 | 处置 |
|---|---|---|
| R-1 | `class_name SaveService` 被骨架占用，重名类 = 全局类冲突 SCRIPT ERROR | 新类名 `AtomicSaveService` 等三个新类名先 grep 确认未占用；骨架留死代码，删除走 G-1 审查 |
| R-2 | JSON 浮点往返（`elapsed_effective_seconds`/`now`）精度漂移 | 测试断言 double 精确往返（FSM 用二进制精确步长）；若 Godot 4.7.2 stringify 不精确，记录实测并按 SDD 记风险，不放宽语义断言 |
| R-3 | `flush()` 只保 API 级完成，断电级持久性无法在本机测试证明（ARCHITECTURE §5 明示） | 故障注入覆盖 API 失败面；报告如实声明保障边界 |
| R-4 | 跨卷 rename 非原子 | tmp 强制同目录（断言 dirname 相同）；macOS APFS 同卷 rename 原子 |
| R-5 | 真实 GameController 未接线，装配协议漂移（G-2） | 测试按 §4.5 蓝图装配并锁协议；UI-001 接线票必须以本文件 §4.5 为契约回归 |
| R-6 | schema 重写 vs 无 jsonschema 模块 | GDScript `SaveValidate` 是唯一执行器；runner 用 Python 比对 schema 必需键常量与 GDScript 常量表一致 |
| R-7 | 备份 copy 半份窗口或坏 main 覆盖好 bak | 仅从已校验 main 更新 bak；main 损坏/缺失且从 bak 恢复时不动好 bak，先复制校验坏档/legacy，再替换 main；故障注入后验证 main 与好 bak 字节仍可恢复 |
| R-8 | 与 runner 门禁冲突（越界文件/import 副作用） | 改动严格 §3 清单；`.uid` 旁车仅由 Godot 导入在隔离副本生成，主工程不跑 Godot 即无新旁车 |

**回滚**：Phase B 单一 commit；回滚 = `git revert <commit>`（新增文件即消失；schema 恢复 v1）。无生产存档数据迁移（v0.1 未发布，真实 `user://` 无存量档；v1 兼容路径仅覆盖示例/测试数据）。测试临时目录由 runner `finally` 清理；不涉任何用户文件/网络/远端。

## 7. 验收条目映射

| 验收 | 载体 |
|---|---|
| T-SAVE-01 重启金币/鱼篓/已处理事务/窗口位置一致 | S1、S7（+S5）；step2 |
| T-SAVE-02 写入/rename/发布前注入 ⇒ 只出现旧完整态或新完整态 | S2（六注入点）、S2b（发布边界） |
| T-SAVE-03 未来版本/坏档不覆盖、原件与恢复方案可检查 | S3、S4；惰性隔离 `corrupt.*/legacy.*` 改名保留 |
| ECO 事务集成（跨崩溃 catch/sale 重试、ledger 冲突识别） | S5；step3 ECO 回归 |
| RNG/Clock/候选精确续跑（FSM-001 R-2 移交） | S6、S7；step6 FSM 回归 |
| T-ECO-02/03 持久化侧（重试 ≤1 鱼/≤1 次加币） | S5、S7 |
| T-TIME-01/02 可复现序列 | S6 + step6 FSM 回归 |
| T-TIME-03 存档错误不新增捕鱼事件 | S2（PERSIST_FAILED 零副作用）+ step6 |
| T-CONF-01 经济启动门禁 | step5 CFG 回归（EconomyService.initialize 复用 ConfigGate） |
| SDD V01-S01/S02（原子写/备份/异常路径；失败暂停不安全交易） | §4.2/§4.3/§4.5、S2、S8 |
| SDD-143/155-156/157-158/172-173 | S5–S8 + §4.1 不变量 |
| INTERFACES §6 故障序列（temp 创建失败/半写/rename 失败/重启主备恢复/重复 sale/旧版本） | S2（前四类）、S3（主备/未来版本）、S5（重复 sale）、S4（旧版本） |
| INTERFACES §7/§8（无云地址、`user://` 不落源码树、未来版本拒绝、优先副本升级） | §3/§5.1 路径策略、S3、runner 隔离设计 |
| ACCEPTANCE §6 门禁（真实退出码、不删改断言、可回滚小提交） | §5.3、§6 回滚 |

**Phase A 声明**：本会话只读；除本文件外零写入；未读/未改 `tasks/APPROVALS.md`；零 git 写操作；未对主工程启动 Godot（仅 `--version` 探测）。迁移拒绝策略（§4.4）严格落在工单 brief 预授权的「安全拒绝并保留原档或仅迁移可证明安全的状态」二选一之内，未扩张 v0.1 产品范围，不构成需求变更。
