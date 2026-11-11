class_name GameState
extends RefCounted
# 金币 / 鱼篓 / 事务 ID 的唯一权威数据（ARCHITECTURE §2）；UI 与其他模块不得另立第二份账本。
# 纯数据骨架：字段镜像 INTERFACES_AND_DATA §3 schema v1。
# 事务、持久化与失败恢复逻辑属 ECO-001 / SAVE-001，本票禁止实现。

var save_version: int = 1
var revision: int = 0
var wallet_gold: int = 0
var basket_capacity: int = 10  # 10 仅为候选初值，任何调节须用户批准
var basket: Array = []  # 元素含唯一 instance_id（ECO-001 落实）
var processed_catch_ids: Array = []
var processed_sale_ids: Array = []
var fishing_checkpoint: Dictionary = {"state": "IDLE", "event_id": null, "wait_seconds": null, "elapsed_effective_seconds": 0}
var desktop_window: Dictionary = {"x": 80, "y": 80, "width": 220, "height": 160, "display_hint": null}
