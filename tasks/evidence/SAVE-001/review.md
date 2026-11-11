# SAVE-001 Phase A 独立审查

日期：2026-11-11

## 审查结论

计划经过修订后满足 Phase B 开工条件。原始 Phase A 会话仅写计划；本文件和计划修订由独立审查者完成。范围仍限于 `scripts/save/**`、`schemas/game-save.schema.json`、`examples/save_v01.json`、`tests/**`；不要求修改 GameState、ECO、FSM、UI 或日志实现。

## 原计划发现的问题及处置

1. **运行时状态缺少经济事务之外的持久化入口。** 原计划只通过 EconomyService 持久化门保存快照，S6 却要求在 WAITING 中途保存。已增设 `persist_runtime_checkpoint()`：以完整副本保存 GameState、ECO ledger、FSM checkpoint、RNG、Clock 和 candidate；失败时不发布 revision/checkpoint/version；约定在状态转换、暂停/隐藏、候选产生/清除后保存，并在 WAITING 中按不超过 5 秒有效时间的间隔保存，不逐渲染帧写盘。S6/S7 覆盖该路径及失败边界。该频率是技术恢复精度，不改变捕鱼参数；Phase B 报告须量化 IO 成本。
2. **v1 迁移/坏档隔离可能先移走唯一主档。** 已改为先完整写好新 temp，再复制并校验 legacy/corrupt 原件；原 main 保持原位，直到 v2 temp 原子替换成功。失败或崩溃时可继续从原 main 迁移/恢复。测试须注入 legacy copy 与 rename 失败并断言原档字节未变。
3. **金币与售鱼 ID 的额外约束超出数据合同。** 删除 `wallet_gold > 0 => processed_sale_ids 非空`。只按现有 schema 验证金币是非负整数；正余额且无事务 ID 的合法 v1 状态必须保留。
4. **未知鱼种可能进入运行态。** `load_save`/`install_into` 现接收配置门通过的 `valid_species_by_id`，篮中实例、ledger 指纹和 pending candidate 的 species 均须在此集合内。
5. **重启后的候选恢复不能再次调用 FSM 抽样。** FSM 不恢复 `_candidate_issued`。计划现要求直接向 `commit_catch` 重放载入的原 payload；成功或 `ALREADY_APPLIED` 后再按 event ID ack。测试覆盖未提交 candidate 与已落账、ack 前崩溃两种窗口。
6. **文档字节长度与存档版本映射需精确。** temp 回读按 UTF-8 字节数验证；明确磁盘 v2 与内存 GameState 的版本发布只在 rename 成功后进行，且不改 `scripts/core/game_state.gd`。

## 本机 Godot 文件 API 探针

在 `TemporaryDirectory` 创建的独立临时 Godot 工程中，以 Godot `4.7.2.stable.official.ed1daf0bf` 实测：

- `DirAccess.copy_absolute(main, existing_backup)` 返回 `0`，已有 backup 被完整覆盖；
- `DirAccess.rename_absolute(temp, existing_main)` 返回 `0`，目标 main 内容变为完整的新内容；
- 探针真实退出码 `0`。临时工程与数据在测试结束时自动清理；未对 Fishing 主工程启动 Godot。

该探针只确认本机 API 成功码和内容替换，不证明断电级持久性或文件系统崩溃原子性；计划已将保证限定为应用级 rename 边界，并保留故障注入验证。

## 批准范围与 Phase B 门禁

Phase B 仅按队列列出的四项范围实现。批准的主验收命令为 `python3 -B tests/unit/run_save001_checks.py`；必须先在隔离工程导入，再串行运行 SAVE/ECO/CORE/CFG/FSM，逐步核验 exit code、唯一 PASS、无 FAIL 与 `SCRIPT ERROR`。测试数据限定临时目录和隔离 HOME；不能启动主工程 Godot、不能写真实用户存档、不能改价格/权重/等待时长/容量、不能触碰 UI/log。

v1 中存在已处理 ID、篮内鱼或非 IDLE 捕鱼 checkpoint 时，按计划拒绝迁移并保留原件；只有 IDLE、空篮、无 processed ID 的状态可补齐 v2 字段。该策略落实工单明确要求的 fail-closed/保留原则，不静默丢弃或伪造事务指纹。

## 再审查补充（2026-11-11）

在将队列转入 Phase B 前，独立核对真实 ECO/FSM API 后发现并修正以下遗漏：

7. **FSM 逻辑时间不是经济层 UTC 时间。** `produce_catch_candidate()` 返回 `caught_at_clock`（数值），而 `EconomyService.commit_catch()`/`FishInstance` 要求合法 UTC 字符串。Godot 4.7.2 临时工程探针确认 `Time.get_datetime_string_from_system(true)` 输出没有 `Z`；计划现要求先严格校验 UTC raw 格式，再补 `Z` 并调用 `FishInstance.timestamp_valid`，只取一次且把结果与候选一起持久化；重启后使用原 UTC 值。逻辑秒仍只用于 FSM，不会伪装成 UTC。
8. **pending candidate 的价格配置快照必须与实际经济 catalog 一致。** 现要求以配置门通过的 `valid_species_by_id` 校验 `catch_weight/base_price/rarity`；不一致即拒绝恢复/结算，防止 EconomyService 按不同价格目录落账。已经在鱼篓内的实例仍以自己的 `sale_price_at_catch` 为准。
9. **坏主档不能覆盖唯一有效备份。** 原顺序会先把坏 main 复制到 `.bak`，可能损坏从备份恢复出的唯一好状态。现改为仅从已验证 main 更新 `.bak`；坏/缺 main 从有效备份恢复时保持 `.bak` 原字节不变，先复制并校验坏档归档，再替换 main。测试增加 quarantine/rename 失败时坏 main 和好 `.bak` 均保留的断言。
10. **迁移原件复制需有独立故障点。** 故障矩阵从五个阶段扩至六个，新增 `legacy_copy`；迁移复制失败时必须保留 v1 main 原字节并拒绝覆盖。

UTC 探针在独立临时 Godot 工程中复测通过：raw 字符串严格匹配 `YYYY-MM-DDTHH:MM:SS`，仅补 `Z` 后匹配 `FishInstance` 所要求的秒级 UTC 形状；退出码 0。未对 Fishing 主工程启动 Godot。

复核结论：补充后的计划仍只允许 `scripts/save/**`、`schemas/game-save.schema.json`、`examples/save_v01.json`、`tests/**`；无 GameState/FSM/ECO/UI/日志/经济参数越界。主验收命令、隔离副本、隔离 HOME、导入先行、唯一 PASS 与无脚本错误要求未放宽。

**结论：Phase B 批准。** 项目所有者已委托 Codex 在本地 v0.1 范围内逐票独立审查与批准；本批准不扩展产品范围，也不授权改动本票允许清单之外的运行时代码。
