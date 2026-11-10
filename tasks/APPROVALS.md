# APPROVALS — 人工批准账本（AUTO-001）

本账本**只能由人类追加记录**。AI Agent 与调度器（`tools/auto/runner.py`）只允许读取本文件，
禁止新增或修改任何记录。调度器在 Phase B 写码**之前**校验批准记录；无记录则拒绝启动任何写码会话
（exit 65）。调度器还会在会话结束后比对本文件哈希，若会话期间被改动，立即 Blocked 并冻结整个队列。

## 如何批准一张工单
1. 复制下方模板，填好并把 `BEGIN-EXAMPLE-ONLY` 改回真实标记 `BEGIN-APPROVAL`（示例注释不算批准）。
2. 把记录追加到本文件"批准记录"一节，`git commit`（账本变更本身可审计）。
3. 在 `tools/auto/queue.json` 把该票 `"status"` 从 `awaiting_approval` 改为 `"exec_ready"`，
   并填写 `"test_cmd"`（调度器会真实执行它，非零退出即触发重试/冻结）。

## 模板（注释内示例，调度器不会匹配）

BEGIN-EXAMPLE-ONLY ID=<票号> PHASE=B
APPROVED
by: <人名>
date: <YYYY-MM-DD>
scope: <批准的文件范围>
notes: <可选备注>
END-EXAMPLE-ONLY

## 批准记录（仅人类可在下方追加；当前无有效批准记录）

BEGIN-APPROVAL ID=SPIKE-001 PHASE=B
APPROVED
by: rain
date: 2026-11-10
scope: tests/spike/overlay/**
notes: 人工批准 SPIKE-001 的已审查计划，仅允许修改所列范围。
END-APPROVAL

BEGIN-APPROVAL ID=SPIKE-001-FIX-001 PHASE=B
APPROVED
by: rain
date: 2026-11-10
scope: tests/spike/overlay/**
notes: 人工批准 SPIKE-001-FIX-001 的已审查计划，仅允许修改所列范围。
END-APPROVAL
