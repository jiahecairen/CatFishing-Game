# SAVE-001 安全复核跟进

日期：2026-11-11

基线：`034c035`（SAVE-001 主实现）

## 复核发现与修复

- `_archive_copy()` 在复制、字节校验或改名失败时清理本次临时副本；调用方不再删除归档目标路径，避免并发时误删并非本事务创建的文件。
- 将 `legacy_copy` 故障注入移至临时归档副本创建之后。回归用例验证旧存档与备份逐字节保留、临时文件清除、绑定状态不变。
- `set_pending_candidate()` 在强制转换前检查 `weight_snapshot` 类型；畸形输入稳定返回 `BAD_PAYLOAD`。
- `_read_document()` 使用 `JSON.parse()` 返回解析状态，将损坏 JSON 归类为 `corrupt`，不再由预期坏档用例产生 Godot `ERROR: Parse JSON failed` 噪声。
- S2b 回归断言 quarantine 注入失败时没有留下归档文件；S7 增加畸形 `weight_snapshot` 输入用例。

## 验收结果

执行：`python3 -B tests/unit/run_save001_checks.py`

- 隔离副本的 Godot editor import：退出码 0。
- SAVE、ECO、CORE、CFG、FSM：全部退出码 0，分别得到唯一 PASS 标记。
- 整体结果：`SAVE001 RUNNER PASS`；本次输出无 `SCRIPT ERROR`，也无 `ERROR:` 解析噪声。
- `git diff --check -- scripts/save/save_service.gd tests/unit/test_save001_save.gd`：通过。

## 范围与状态

只涉及 `scripts/save/**`、`tests/**` 和本证据文件。未修改队列、审批账本或冻结设置；SAVE-001 仍为 `in_review`，其他 held 工单不变。本次没有执行解冻或远端推送。
