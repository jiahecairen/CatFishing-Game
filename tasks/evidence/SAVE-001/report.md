# SAVE-001 Phase B 执行报告（attempt 3）

工单：原子存档 + 版本 + 故障注入（AUTO-001 调度，Phase B 执行票，attempt 3 / max 3）。
上一轮失败：`test-2.log` 退出码 1。本轮按「先诊断再修，勿扩大范围」执行。
所有测试结果均来自下方真实命令的真实退出码；无任何伪造、无断言弱化。

## 1. attempt-2 失败诊断（先诊断）

`test-2.log` 首个失败：`SAVE001 SAVE FAIL: S0 BAD_DOC zero file writes`，stderr 伴
`Invalid call. Nonexistent function 'remove_recursive' in base 'DirAccess'`（test 第 714 行）。
在本会话隔离副本（`/tmp/save001_smoke_*`，AGENTS 合规：Godot 永不 `--path` 主工程）用最小探针
脚本实测，确认三层根因，均为 Godot 4.7.2 真实行为：

1. `DirAccess.remove_recursive()` 在 4.7.2 不存在；静态 `DirAccess.remove_absolute()` 对
   非空目录返回 FAILED 不递归 ⇒ 测试清理辅助 `_remove_dir` 从未删成功，残留临时目录污染
   文件集断言（S0 首失败即此）。
2. `JSON.parse_string` 把**所有** JSON 数字解析为 float（实测 `{"v":2}` → `is int`=false）。
   `SaveValidate`/加载链中 8 处严格 `x is int` 判据把磁盘上的合法 v2 文档误判为损坏
   （`save_version missing or not an integer`），连锁导致 S1 提交被分类为 corrupt、
   产生伪 `corrupt.N.json`。
3. `JSON.stringify` 数字形态不对称：`stringify(int 1)="1"` 而 `stringify(float 1.0)="1.0"`
   ⇒ 整数「1」落盘后回读再 stringify 变「1.0」，「重复加载逐字节同 JSON」不可能对原始
   parse 结果成立；只有「x.0」float 形态是 parse∘stringify 的字节不动点（探针实测）。

后续步骤逐段暴露的次级偏差（均先在副本复现再修）：
- rename 故障注入在 `.bak` 更新**之后**才触发 ⇒ 注定失败的提交仍改写了 `.bak` 字节
  （违背「失败零改动」合同，S2 实测复现）。
- 候选校验把目录指纹（CONFIG）排在 SETTLEMENT 生命周期位置（STATE）之前 ⇒ S7b 的
  IDLE+篡改候选组合返回码归类错误。
- 主坏+备坏组合返回 MAIN_CORRUPT 而非 plan §4.3 的 NO_VALID_SAVE。
- 测试 S6 参考侧 tick 编排与崩溃侧不同构（FSM `tick_effective` 每次调用至多推进**一**
  个 transition 是 FSM-001 已接受语义），导致事件条数天然不等——这是测试构造错误，
  修正为镜像崩溃侧调用序列，断言强度不降反升（4 事件逐字段+候选一致仍全断言）。

## 2. 本轮修复（均在允许文件范围内）

`scripts/save/save_validate.gd`
- 新增 `_is_integral()`（int 或二进制精确整数值的 float 均合法），替换 8 处严格
  `is int`：v2/v1 `save_version`、`classify_document`、rng `version/seed/state`、
  clock `version`、候选 `version`（数值域校验不变：rng 仍限 [1, 2^31-2]）。判据与
  项目既有先例 `FishInstance.price_valid` 的「JSON 数字双态」宽容一致，注释注明实测依据。
- `_validate_candidate` 校验次序改为：载荷形状 → 生命周期位置（SETTLEMENT+event 一致，
  CANDIDATE_STATE_MISMATCH）→ 目录指纹（CANDIDATE_CONFIG_MISMATCH）→ 账本指纹
  （CANDIDATE_LEDGER_MISMATCH）。

`scripts/save/save_service.gd`（AtomicSaveService）
- 新增 `_normalize_json_numbers()`：JSON→运行时边界归一（整数值 float→int），应用于
  载入出的 state 各域、rng/clock/候选快照 ⇒ 满足范围外严格 API（`DeterministicRng.
  restore_state`、`VirtualClock.restore_state`、`FishingStateMachine.initialize` 的
  严格 `is int`）而**不修改** `scripts/fishing/**`。
- 新增 `_float_normalized()`：写路径（`_commit` 落盘文本与 `export_document`）把全部
  数字归一为 float 形态落盘 ⇒ 磁盘文档是 parse∘stringify 字节不动点，S1「重复加载逐
  字节同 JSON」成立；校验层双态判据不受影响。
- `load_save` 不可用码规则：仅「主坏且备**缺失**」⇒ MAIN_CORRUPT；其余不可用组合
  （皆缺/皆坏/主缺备坏）⇒ NO_VALID_SAVE（plan §4.3）。
- rename 故障注入前移到 `.bak` 更新之前：注入 rename 的提交在写出 temp+校验后直接失败
  并清理 temp，不触碰 `.bak`/`legacy.*`/`corrupt.*` 任何保留文件。

`tests/unit/test_save001_save.gd`
- `_remove_dir` 改为 open+list_dir 递归删除 + 静态 `DirAccess.remove_absolute` 收尾
  （4.7.2 实测唯一可行组合），失败时 push_warning 不静默。
- S6 参考运行镜像崩溃侧调用序列（cast→tick2→tick1000→tick1→tick1），断言仍为
  事件时间轴逐字段 `_deep_eq` + 候选三要素相等。

`tests/unit/run_save001_checks.py`、`scripts/save/save_faults.gd`、
`schemas/game-save.schema.json`、`examples/save_v01.json`：本轮无改动（后者保持冻结
v1，`git status` 可证）。

## 3. 改动文件清单（对 HEAD 811abf6 全量）

| 文件 | 状态 | 行数 |
|---|---|---|
| `scripts/save/save_service.gd` | 新增（AtomicSaveService） | 648 |
| `scripts/save/save_validate.gd` | 新增（SaveValidate） | 480 |
| `scripts/save/save_faults.gd` | 新增（SaveFaults，默认全关） | 43 |
| `schemas/game-save.schema.json` | 修改（v2 顶层 13 键、`save_version const 2`、additionalProperties:false；+73/−4） | 123 |
| `tests/unit/test_save001_save.gd` | 新增（S0–S8） | 807 |
| `tests/unit/run_save001_checks.py` | 新增（隔离副本 runner） | 293 |
| `tasks/evidence/SAVE-001/test-3.log` | 新增（本轮真实运行输出） | — |
| `tasks/evidence/SAVE-001/report.md` | 新增（本文件） | — |

范围核查：以上全部落在允许清单（`scripts/save/**`、`schemas/game-save.schema.json`、
`examples/save_v01.json`（未动）、`tests/**`、证据目录）。`examples/save_v01.json`
零改动；`scripts/fishing/**`、`scripts/economy/**`、`scripts/core/**`、`scripts/io/**`、
`data/**`、`tools/auto/queue.json`、`tasks/APPROVALS.md` 均未读改（APPROVALS.md 未读）。
未执行任何 git commit/merge/push/stash/reset/clean；未启动子代理/后台任务。

## 4. 执行的真实命令与退出码

| # | 命令（工作目录=项目根） | 退出码 | 结果 |
|---|---|---|---|
| 1 | `python3 -B tests/unit/run_save001_checks.py`（迭代中首跑） | **0** | `SAVE001 RUNNER PASS` |
| 2 | 同上，完整输出重定向 → `test-3.log`（复现性第二跑） | **0** | `SAVE001 RUNNER PASS` |
| 3 | `python3 -B tools/auto/runner.py selftest` | **0** | `ALL PASS`（/tmp 合成项目，不碰真实工单） |
| 4 | `git diff --check` | **0** | 无空白错误 |

runner 内各步（`test-3.log` 逐字记录，全部真实退出码）：

| 步骤 | 命令 | 退出码 | 标记 |
|---|---|---|---|
| step1-import | `Godot --headless --path <副本> --editor --quit` | 0 | — |
| step2-save001 | `Godot --headless --path <副本> --script res://tests/unit/test_save001_save.gd` | 0 | `SAVE001 SAVE PASS` 恰一次；FAIL 0 次；`SCRIPT ERROR` 0 次 |
| step3-eco001 | 同上 `test_eco001_economy.gd` | 0 | `ECO001 ECONOMY PASS` |
| step4-core001 | 同上 `test_core001_smoke.gd` | 0 | `CORE001 SMOKE PASS` |
| step5-cfg001 | 同上 `test_cfg001_config.gd` | 0 | `CFG001 CONFIG PASS` |
| step6-fsm001 | 同上 `test_fsm001_fsm.gd` | 0 | `FSM001 FSM PASS`（sample min=20 max=60 distinct=41） |

前置门禁（runner pre-flight，Python 标准库）全过：交付物齐备、value-lock 冻结值
（30 FPS / 20–60 s / 容量 10 / 鱼价权重逐值）、`examples/save_v01.json` 仍 `save_version:1`
逐值不变、schema v2 锁定（13 必需键 + const 2 + additionalProperties:false 与 GDScript
常量表一致）、三个新类名全局唯一、fixture 齐备。

## 5. 测试输出摘要

- step2 stderr 有 11 条 `ERROR: Parse JSON failed...` —— 这是 S3 **故意注入的坏档**
  （garbage/截断 JSON）被 fail-closed 分类为 corrupt 时的预期引擎噪声，非 SCRIPT ERROR；
  runner 的门禁（出现 `SCRIPT ERROR` 即失败）实测为 0。
- 全部测试 IO 只写 `OS.get_temp_dir()/save001_*` 与 runner 隔离副本；源码树与真实
  `user://` 零写入；runner `finally` 清理副本与隔离 HOME（日志 `cleaned isolated project and HOME`）。

## 6. 覆盖的验收条目（plan §7 映射，逐条落实）

| 验收 | 载体 | 实测 |
|---|---|---|
| T-SAVE-01 重启金币/鱼篓/已处理事务/窗口位置一致 | S1、S7、S5；step2 | 过：逐字段 `_deep_eq` + 重复加载逐字节同 JSON（float 形态不动点保证，见 §2） |
| T-SAVE-02 写入/rename/发布前注入 ⇒ 只出现旧完整态或新完整态 | S2 六注入点、S2b 发布边界 | 过：`tmp_write/tmp_flush/backup/rename/quarantine/legacy_copy` 逐项：门拒绝、`PERSIST_FAILED`、GameState/ledger/rng/clock/fsm 零副作用、main/.bak 字节不变、解除后重试成功、无 temp 残留；rename 后崩溃 ⇒ 磁盘新完整态、同参重试 `ALREADY_APPLIED` |
| T-SAVE-03 未来版本/坏档不覆盖、原件与恢复方案可检查 | S3、S4 | 过：v99 ⇒ `VERSION_NEWER` 零副作用；皆坏 ⇒ `NO_VALID_SAVE` 全保留；坏主+好备 ⇒ `RECOVERED_FROM_BACKUP`；坏 main 惰性复制到 `game_state.corrupt.1.json` 字节不变；v1 安全 ⇒ `MIGRATED_V1` 13 键逐值、`legacy.1.json` 与 `.bak` 均字节=v1 原档；v1 带 ids/WAITING ⇒ `VERSION_LEGACY_UNSAFE` 零写入；畸形 v1 ⇒ `MAIN_CORRUPT` |
| ECO 事务集成（跨崩溃 catch/sale 重试、ledger 冲突） | S5；step3 | 过：`ALREADY_APPLIED`/`CONFLICT_CATCH_PARAMS`/`CONFLICT_SALE_PARAMS`/`BAD_LEDGER` fail-closed 内存账本不变 |
| RNG/Clock/候选精确续跑 | S6、S7；step6 | 过：恢复侧与镜像序列参考跑事件时间轴逐字段一致；候选事件 ID/species/clock 全等；越界快照 `BAD_SNAPSHOT` |
| T-ECO-02/03 持久化侧（重试 ≤1 鱼/≤1 次加币） | S5、S7 | 过 |
| T-TIME-01/02 可复现序列 | S6 + step6 | 过（20–60 s、distinct=41） |
| T-TIME-03 存档错误不新增捕鱼事件 | S2 + step6 | 过（注入下 rng/clock/fsm 状态逐值不变） |
| T-CONF-01 经济启动门禁 | step5 | 过（CFG 回归） |
| SDD V01-S01/S02（原子写/备份/异常路径；失败不显示未持久化收入） | §4.2/§4.3/§4.5、S2、S8 | 过：门只认 rename 后的真布尔 true；false/非 bool/失效 Callable ⇒ `PERSIST_FAILED` 零发布 |
| INTERFACES §6 故障序列（temp 失败/半写/rename 失败/主备恢复/重复 sale/旧版本） | S2、S3、S5、S4 | 过（逐码断言，见 test 文件） |
| INTERFACES §7/§8（无云地址、user:// 不落源码树、未来版本拒绝、优先副本升级） | runner 隔离、S3/S4 | 过 |
| ACCEPTANCE §6 门禁（真实退出码、不删改断言、可回滚） | 本报告 §4 | 过：两次完整跑 0/0；`git diff --check` 0 |

## 7. 残余风险（如实声明）

1. **断电级持久性（plan R-3）**：`FileAccess.flush()` 只证明 API 级刷盘；真断电持久性
   无法在本机以测试证明。故障注入覆盖 API 失败面（tmp_write/tmp_flush/rename）。
2. **JSON 数字双态（plan R-2 已兑现为实测）**：Godot 4.7.2 parse 全 float、stringify
   int/float 形态不同 ⇒ 本实现以「写路径全 float 形态 + 校验层双态判据 + 载入运行时
   归一」三层保证字节与语义一致。若未来 Godot 改动数值输出形态，需回归 S1 字节断言。
3. **真实 GameController 未接线（plan R-5）**：S2 装配蓝图即 G-2 接线契约；UI-001 票
   必须回归 `test_save001_save.gd` 的 §4.5 装配协议。
4. **`.uid` 旁车**：主工程 `scripts/save/` 内三个 `.uid`（mtime 2026-11-11 11:10:44）
   为 attempt 2 时段遗留，早于本轮任何命令，本轮未新增；本会话未对主工程运行任何
   Godot 进程（冒烟全部在 `/tmp` 隔离副本），runner 在副本内生成的旁车随 `finally`
   清理一并消失。
5. 回滚：Phase B 单一提交即可整体回滚（`git revert`）；v0.1 无生产存档存量，无数据迁移风险。
6. 工作树中 `tasks/evidence/_runner/runner.log`、`tools/auto/queue.json`、
   `tasks/evidence/_runner/runner.lock` 为调度器自有脏文件，本票全程未触碰。

PHASE-B-DONE
