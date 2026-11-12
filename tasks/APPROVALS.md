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

BEGIN-APPROVAL ID=CFG-001 PHASE=B
APPROVED
by: Codex
date: 2026-11-11
scope: data/**, scripts/config/**, tests/**
notes: 项目所有者在持续执行授权中明确委托 Codex 审查并批准本地 v0.1。按 tasks/evidence/CFG-001/review.md 实施：不改任何配置平衡值；畸形 JSON 使用 JSON.new().parse(text) 并检查返回错误码；tests/unit/run_cfg001_checks.py 必须先执行 Godot 导入，再依次验证 CFG001 CONFIG PASS 和 CORE001 SMOKE PASS，任一 SCRIPT ERROR/FAIL/非零退出即失败。不得修改 examples/**、schemas/**、docs/**、tasks/APPROVALS.md 或范围外文件。
END-APPROVAL


BEGIN-APPROVAL ID=FSM-001 PHASE=B
APPROVED
by: Codex
date: 2026-11-11
scope: scripts/fishing/**, tests/**
notes: 项目所有者在持续执行授权中委托 Codex 自动审批本地 v0.1。仅按 tasks/evidence/FSM-001/plan.md 与 review.md 实施；review.md 的五项条件均为强制项，特别是满篓拒绝、精确步长不变时间轴、可重放待结算候选、隔离副本串行测试。不得修改 GameState/schema、经济值或 GUI。
END-APPROVAL

BEGIN-APPROVAL ID=ECO-001 PHASE=B
APPROVED
by: Codex
date: 2026-11-11
scope: scripts/economy/**, tests/**
notes: 项目所有者在持续执行授权中委托 Codex 审查并批准本地 v0.1。仅按 tasks/evidence/ECO-001/plan.md 与 review.md 实施；强制满足重复实例 ID 去重、事务重试幂等与异参冲突、捕获价格快照、失败零副作用、金币溢出防护、持久化门只收深拷贝且仅 bool true 可发布、ledger snapshot/restore fail-closed，以及隔离副本先导入再串行回归。不得改 GameState 源码、schema、配置数值、SaveService、UI 或文档；ECO 不写盘、不触碰 user://。
END-APPROVAL


BEGIN-APPROVAL ID=SAVE-001 PHASE=B
APPROVED
by: Codex
date: 2026-11-11
scope: scripts/save/**, schemas/game-save.schema.json, examples/save_v01.json, tests/**
notes: 项目所有者在持续执行授权中委托 Codex 审查并批准本地 v0.1。仅按 tasks/evidence/SAVE-001/plan.md 与 review.md 实施；强制完整持久化 GameState、ECO ledger、RNG/Clock、checkpoint 和 pending candidate；pending candidate 必须固定合法 UTC 时间并与已验证鱼种快照一致；坏 main 不得覆盖唯一有效 .bak；故障注入含 legacy_copy。仅限 scope 列出的路径，临时副本先导入后串行运行 SAVE/ECO/CORE/CFG/FSM，PASS 恰一次、无 FAIL/SCRIPT ERROR、真实退出码为 0。不得改经济参数、GameState/FSM/ECO/UI/日志、审批账本或 SDD 范围。
END-APPROVAL

BEGIN-APPROVAL ID=UI-001 PHASE=B
APPROVED
by: Codex delegated reviewer
date: 2026-11-11
scope: scenes/**, scripts/ui/**, scripts/core/game_controller.gd, scripts/platform/desktop_window.gd, scripts/platform/platform_adapter.gd, scripts/presentation/cat_presenter.gd, project.godot, tests/**
notes: 委托目标授权自动审批；计划独立审查通过，范围与隔离验收命令已核对；GUI验收保留人工证据。
END-APPROVAL

BEGIN-APPROVAL ID=SIM-001 PHASE=B
APPROVED
by: Codex delegated reviewer
date: 2026-11-11
scope: tools/sim/**, tasks/evidence/SIM-001/**
notes: 项目所有者在持续执行目标中明确委托自动审批并完成本地 v0.1。按 tasks/evidence/SIM-001/plan.md 与 review.md 实施；复用既有 FSM/RNG/Clock/ECO/Save 故障注入接口，生成 20 seeds × 两场景 × 1/4/8 小时虚拟报告；固定 20–60s、30 FPS、鱼种权重/价格与候选容量，任何产品数值不得更改。Godot 仅在临时工程副本和隔离 HOME 运行，报表记录 120 个独立 run 与真实故障注入结果。Phase B 不得修改 scripts/**、data/**、tests/**、queue/runner、产品文档或审批账本。
END-APPROVAL


BEGIN-APPROVAL ID=LOG-001 PHASE=B
APPROVED
by: Codex delegated reviewer
date: 2026-11-12
scope: scripts/io/event_log.gd, scripts/ui/fishing_session.gd, tests/**
notes: 项目所有者持续执行授权并在当前目标中明确委托自动审批。已审查 tasks/evidence/LOG-001/plan.md 与第 9 节修订；日志限于 user://logs，字段白名单、UTC 日/字节轮换、跨重启序号恢复、严格清理匹配、fail-soft 事务接入与隔离导入测试均为强制条件。不改冻结的 v0.1 经济/存档/范围参数。
END-APPROVAL

BEGIN-APPROVAL ID=REL-001 PHASE=B
APPROVED
by: Codex delegated reviewer
date: 2026-11-12
scope: tests/**
notes: 项目所有者持续执行授权并要求自动完成本地 v0.1。批准仅新增 tests/unit/run_rel001_checks.py 串行调用既有隔离回归器并校验已完成的 SIM-001 报告；不得改产品代码/参数。最终接受仍必须等真实可见 Mac 8 小时候选运行、GUI 证据与全部回归完成；队列冻结/暂停和审批账本保持有效。
END-APPROVAL
