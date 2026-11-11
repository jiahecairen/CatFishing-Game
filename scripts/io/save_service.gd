class_name SaveService
extends RefCounted
# SAVE-001 实现：user:// 存档（不落源码树）、版本字段、原子替换、备份/恢复、事务幂等。
# 规则：写成功才发布为已确认；保存失败保持旧权威状态并报告恢复原因，崩溃重试不重复结算。
# 本票仅骨架，零实现；仅保留 GameState 中的 save_version / revision / processed_*_ids 字段形状。
