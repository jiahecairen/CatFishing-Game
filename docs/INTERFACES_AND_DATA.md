# v0.1 Data / API Contracts — Draft

本文件给出供编码 Agent 先行落地的**最小可测试接口约定**。当前尚未跑过 Godot，不应将示例 GDScript 方法名视为现有代码实现。具体签名可在 `SPIKE-001` 和 `CORE-001` 后记录，但语义及不变量不可擅改。

## 1. 配置

参考：`schemas/fish-species.schema.json`、`schemas/runtime-config.schema.json`、`examples/fish_species.json`、`examples/runtime_config.json`。

**鱼种集合**：`id` 唯一且稳定（snake_case）；`name_zh`、`rarity`、`catch_weight`（正数）、`base_price`（整数且 ≥0）、`asset_key`（可先占位）。不能直接用 fish species ID 充当单条鱼的实例 ID。

**运行配置**：`config_version`、`visible_fps=30`、`bite_wait_min_sec=20`、`bite_wait_max_sec=60`、`basket_capacity=10`（候选）。校验 min ≤ max、数值上界合理、种类至少 1。实际捕获概率为 `catch_weight / sum(catch_weight)`；稀有度仅显示/后续扩展，不擅自改变权重。

配置文件缺失或非法时：输出明确日志/用户状态，拒绝启动会产生交易的 FSM；不可静默制造默认价格并导致破坏性存档。

## 2. Catch / Fish Instance

一个**鱼实例**建议：

```json
{
  "instance_id": "stable-generated-unique-id",
  "species_id": "river_carp",
  "caught_at_utc": "2026-11-10T16:00:00Z",
  "source_event_id": "catch-event-uuid",
  "sale_price_at_catch": 8
}
```

- `sale_price_at_catch` 使用捕获时锁定的价格快照，避免后续配置更新改变已经拥有鱼的账面价格。此合同由项目所有者在 2026-11-11 的委托审查中批准用于 v0.1。
- `instance_id` 唯一；`source_event_id` 可用于重放/幂等。捕获时不得超过上限。

## 3. 游戏状态 / Save（建议 schema 见附件）

```json
{
  "save_version": 1,
  "revision": 0,
  "wallet_gold": 0,
  "basket_capacity": 10,
  "basket": [],
  "processed_catch_ids": [],
  "processed_sale_ids": [],
  "fishing_checkpoint": {"state": "IDLE", "event_id": null, "wait_seconds": null, "elapsed_effective_seconds": 0},
  "desktop_window": {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": null}
}
```

- `revision` 单调递增；coins 非负整数；篮元素不可重复。
- 持久化 `processed_*_ids`，事务成功后才能认定 `processed`。
- 运行期间短生命周期的 hover/bubble/frame counters 不存入该文件；v0.1 没有动画收藏或历史。
- 若 UI/存档写入失败，不能更新权威金额或声称交易成功。

## 4. FishingSystem 契约（伪接口）

```text
initialize(config, injected_rng, injected_clock, recovered_checkpoint)
can_cast(game_state) -> bool
tick_effective(seconds: float) -> Transition[]
request_cast(game_state) -> EventId or reason
produce_catch_candidate() -> {event_id, species_id, ...}
ack_settlement(event_id, committed: bool) -> next_state
pause(reason) / resume_if_safe()
snapshot_checkpoint() -> SerializableObject
```

严格单线程、按 ID 防重、状态非法迁移拒绝。`tick_effective` 使用虚拟时间秒数，单步跨越多个时间阈值时不能凭空多发捕获；应定义安全最多一次推进或显式分段调度。 `WAITING` 结束后不立即发钱，只提交候选事务。

## 5. 经济命令（建议）

```text
commit_catch(catch_event_id, fish_species_id, caught_at) -> CommittedResult | AlreadyApplied | Error
sell_fish(sale_event_id, list_of_instance_ids) -> CommittedResult | AlreadyApplied | Error
```

- catch：校验未处理、容量足够、species 有效，生成鱼实例，保存 ID，**原子保存**后发布结果。
- sell：校验实例存在、未出售、价格快照合法，按 ID 去重计算整数金币，**原子删除鱼 + 加金币 + 保存已处理 sale ID**，成功后恢复鱼篓容量。
- 相同 ID 重试必须返回 `AlreadyApplied`，不得再次发鱼、金币。
- 同一事件若参数与首次处理不同：返回冲突错误并记录，不以 `AlreadyApplied` 掩盖不一致请求。
- 捕获和出售操作必须串行排队；禁止 UI 多次点击造成竞态。

## 6. 事务与存档失败序列

```text
Player/Auto -> Controller -> validate -> derive next_state
                                          |
                                 SaveService.atomic_commit
                                     /          \
                                  success       failure
                                     |             |
                        update GameState/UI     keep last confirmed state
                        write event log         pause unsafe operations
```

重点故障注入：temp 文件无法创建、写盘只写一半、rename 失败、重启恢复主/备份、重复调用 sale ID、崩溃发生在写完临时文件但未 commit 之前、旧存档版本。

## 7. 兼容/迁移原则

- v0.1 不实施用户账号或 Steam Cloud；不要写入任何云地址。
- 版本迁移只在已识别旧版本且能完整验证时进行，优先对副本升级；非法或未知未来版本直接阻止加载并保留原始文件。
- Save schema 未来扩展 v0.2 猫咪创建、船舱等字段时走显式迁移，不能重新创建新存档覆盖金币/鱼实例。

## 8. 真实路径与可移植性

在 macOS 用 Godot 用户数据目录（如 `user://`）保存游戏存档，**不要**把存档硬编码在 `/Users/rain/DevGame/Fishing` 源码目录。项目路径仅用于开发代理工作区。
