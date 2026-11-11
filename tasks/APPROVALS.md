# APPROVALS — 人工批准账本（AUTO-001）

本账本由项目所有者管理。2026-11-11，所有者通过当前持续执行授权，委托 Codex 为 Fishing v0.1
逐票审查计划、追加带明确范围的 Phase B 批准并推进验收；此委托仅限本地 v0.1 实施包，不扩大产品边界。
委托记录使用 `by: Codex` 并在 notes 中注明授权来源。编码模型和调度器仍不得读取或写入本账本；调度器只在
Phase B 前核验批准，并在会话期间比对哈希，发现变化立即 Blocked 并冻结队列。历史批准记录只追加、不改写。

## 如何批准一张工单
1. 项目所有者或其明确委托的审查者复制下方模板，填写并把 `BEGIN-EXAMPLE-ONLY` 改回真实标记 `BEGIN-APPROVAL`（示例注释不算批准）。
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

## 批准记录（仅追加；调度器验证对应工单与阶段）

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

BEGIN-APPROVAL ID=SPIKE-001-FIX-002 PHASE=B
APPROVED
by: rain
date: 2026-11-10
scope: tests/spike/overlay/**
notes: 人工批准 SPIKE-001-FIX-002 的已审查计划，仅允许修改所列范围。
END-APPROVAL

BEGIN-APPROVAL ID=CORE-001 PHASE=B
APPROVED
by: rain
date: 2026-11-11
scope: project.godot, icon.svg, scenes/**, scripts/**, tests/**
notes: 人工批准 CORE-001 的已审查计划，仅允许修改所列范围。
END-APPROVAL

BEGIN-APPROVAL ID=CORE-001 PHASE=B
APPROVED
by: Codex
date: 2026-11-11
scope: icon.svg.import
notes: 补充批准与既有允许的 icon.svg 配对的 Godot 导入元数据；项目所有者在当前持续执行授权中委托 Codex 审批，runner 仅在文件稳定且索引内容一致时提交。
END-APPROVAL
