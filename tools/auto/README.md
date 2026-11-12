# AUTO-001 串行工单调度器（tools/auto）

DeepSeek Harness **headless CLI** + 本机 **llama.cpp Qwen3.8-Flash-Next**（唯一模型）驱动的
单 Agent 串行工单执行器。**默认不自动执行任何真实工单**（队列全 `held`，SPIKE-001 亦 `held`）。

## 文件
- `runner.py` — 调度器主程序（stdlib only，无第三方依赖）。
- `selftest.py` — 门禁确定性回归（T1–T7，用 `/tmp` 合成工程 + dsh stub，不碰真实模型）。
- `headless-local-qwen.patch.yml` — 已实测：让 headless 走本机 `:9931` 的 Qwen Flash（`--patch` 注入，不改任何 profile）。
- `queue.json` — 工单队列（状态机见文件内 `note`）。**所有票初始 `held`**。
- `prompts/phaseA.txt.tmpl` / `phaseB.txt.tmpl` — 只读规划 / 写码执行提示词（含禁子 Agent、禁后台、禁改 APPROVALS、禁伪造退出码）。

## 命令（先 `cd /Users/rain/DevGame/Fishing`）
| 目的 | 命令 |
|---|---|
| 跑门禁自检（不启动会话） | `python3 tools/auto/runner.py check` |
| 查看队列/锁/冻结/暂停 | `python3 tools/auto/runner.py status` |
| 跑调度器回归 | `python3 tools/auto/runner.py selftest` |
| 处理队首可执行票 | `python3 tools/auto/runner.py start` |
| 只跑指定票 | `python3 tools/auto/runner.py start --id CORE-001` |
| 暂停（下张票前停） | `python3 tools/auto/runner.py pause` |
| 恢复 | `python3 tools/auto/runner.py resume` |
| 看最近日志 | `python3 tools/auto/runner.py log -n 40` |
| 人工解冻 | `python3 tools/auto/runner.py unfreeze --reason "已复核"` |
| 复核历史 blocked 票（不解冻、不标记 done） | `python3 tools/auto/runner.py reconcile-review --id UI-001 --reason "已复核修复提交和验收证据"` |

## 一张票的生命周期
```
held ──(人工改 ready)──▶ Phase A 只读计划 ──▶ awaiting_approval
   ──(人工写 APPROVALS.md + 填 test_cmd + 改 exec_ready)──▶ Phase B 写码/测试
   ──(通过: 范围✓ 测试✓ 批准✓)──▶ 自动 git commit + in_review（不 push）
   失败/越权/BLOCKED/篡改 ──▶ blocked + 冻结整个队列（保留日志与 diff，绝不提交失败代码）
```

## 自动 vs 人工
**自动**：单实例锁、模型门禁（health + `/v1/models` 含目标模型，否则不启动任何会话）、批准账本只读校验与哈希防篡改、范围检查、测试、成功即 commit。

**必须人工**（调度器一律停下并冻结、等待，不自行放行）：
1. `held → ready` 决定何时开工。
2. 审阅 `tasks/evidence/<ID>/plan.md` 后，在 `tasks/APPROVALS.md` **亲自**写批准记录，并填 `test_cmd`、改 `exec_ready`。
3. 需求变更 / 破坏性操作（删档、批量重构、push、装依赖）/ 高风险决策 —— Agent 报 `BLOCKED:` 即冻结。
4. GUI/真机验收（SPIKE-001 的 G-001/G-002、UI、8h 稳定性）：`in_review` 后需你人工验收，再手工置 `done`。
5. `unfreeze` 解冻。

`reconcile-review` 是受限恢复入口：仅接受已有 Phase B 批准、依赖均为 `in_review/done`、当前未冻结且 fresh `test_cmd` 通过的 `blocked` 票。它记录执行者、原因、旧阻塞原因和测试尝试，将票推进到 `in_review`，保留 `needs_human`；不会清除冻结、写审批账本或标记 `done`。失败仍按原门禁冻结并保留证据。

## 安全保证（代码级 + selftest T1–T7）
- 每个 headless 会话必带 `--patch`，绝不回落云默认模型；模型不在 `:9931` 列表即 exit 60 + 冻结。
- 每票每次尝试都是全新会话，从不 `--resume`；上下文仅 AGENTS.md + 工单 + 相关代码 + 上轮失败摘要。
- 无子 Agent / 无并行 / 无后台任务：单实例锁 + 提示词显式禁止 + headless 无委派插件（三重）。
- 每票最多重试 **2 次**（含首跑共 3 次）；超限即 Blocked + 冻结 + 不提交。
- `tasks/APPROVALS.md` 调度器与 Agent 均不得写：会话前后哈希比对，被改即 Blocked + 冻结（防伪造批准）。
- 只有测试+范围+批准三查全过才 `git commit`（`--no-verify`，绝不 `push`）。
