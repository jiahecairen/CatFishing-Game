# Fishing AUTO-002 · 本地人工审批网页（最小可用版）

本工具是 **AUTO-001 的本地人类操作界面**，不是新的 Agent、任务调度器或模型服务。它只在 `127.0.0.1` 监听，不连接云端，不调用模型。`runner.py` 仍然是唯一执行工单的组件。

## 安装

将 `Fishing_AUTO002_Approval_Web.zip` 在 **Fishing 项目根目录**解压。不要将整个 ZIP 放进 `tools/auto/` 内，因为 ZIP 内已有完整路径。

```bash
cd /Users/rain/DevGame/Fishing
unzip -n ~/Downloads/Fishing_AUTO002_Approval_Web.zip -d .
python3 -m unittest discover -s tools/auto/ui -p 'test_*.py' -v
```

检查新增文件后，建议将 **仅 AUTO-002 文件**提交为本地 Git 基线，防止 Runner 对未跟踪文件报警：

```bash
git add tools/auto/ui/
git diff --cached --stat
git commit -m "Add local human approval dashboard AUTO-002"
```

以上是明确列出的本地操作，不会 `git push`。若目录已经存在同名文件，`unzip -n` 会跳过，不覆盖。

## 启动

```bash
cd /Users/rain/DevGame/Fishing
python3 tools/auto/ui/server.py --project /Users/rain/DevGame/Fishing
```

程序会打开浏览器。若没有自动打开，复制启动终端显示的 **带 token 的本地 URL** 到浏览器。默认端口 `8765`，占用时可以增加 `--port 8766`。不要将登录 URL 发给其他人，或把它保存进 Git。

也可在 Finder 中双击 `tools/auto/ui/start.command`（如缺执行权限，先执行 `chmod +x tools/auto/ui/start.command`）。关闭面板：在启动它的终端按 `Ctrl+C`。

## 使用

1. 左侧选择工单，如 `SPIKE-001`；查看 `plan.md`、允许改动文件范围、已有测试命令。
2. 只有工单为 `awaiting_approval`、计划确实存在、队列包含 `allowed_files`/`scope` 与 `test_cmd` 字段时，才可点击 **人工批准编码**。
3. 输入审批人、真实测试命令、备注，以及工单 ID 二次确认，点击批准。此操作会尝试按照用户之前提供的账本模板写入 `tasks/APPROVALS.md`，设为 `exec_ready`，运行 `runner.py check`，成功后仅提交上述两个文件的 Git 变更。
4. 批准操作 **不启动模型**。检查结果后再点击 **启动已批准工单**，它才执行 `runner.py start`。运行日志和状态可在网页中查看。
5. **暂停** 调用 `runner.py pause`，通常只影响下一张工单，不保证终止当前模型生成。**恢复**调用 `runner.py resume`。
6. 当 Runner 返回 `in_review`，需真人验证 GUI、测试和证据。当前版本不包含点一下就跳过人工验收的功能。

## 必须说明的兼容性约束

本 ZIP 在当前聊天环境生成，**无法直接访问你 Mac 的真实 `runner.py`、`queue.json` 和账本源文件**。所以已内置“遇到不认识的字段就禁止审批”的 **fail-closed** 机制，绝不静默猜测改动：

- 工单数据支持 JSON 列表，或 `tasks`/`tickets`/`queue`/`items`/`jobs`/`work_items` 列表字段；ID 支持 `id`/`task_id`/`ticket_id`。
- 允许文件字段支持 `allowed_files`/`allow_files`/`allowed_paths`/`scope`；无显式范围就不准审批。
- 预期账本使用 `BEGIN-APPROVAL ID=... PHASE=B`、`APPROVED`、`by:`、`date:`、`scope:`、`notes:`、`END-APPROVAL`（依据用户截图）。
- 测试命令必须是单条 Godot 或 Python 命令，不接受 shell 链接符或任意命令。如果你的现有计划需要组合命令，应当在项目内创建受审核的测试脚本，再在 UI 指向该脚本。
- 如果账本格式、文件字段、Runner 的 `check` 逻辑不同，会显示错误、拒绝执行；这时提供实际**脱敏**后的 `queue.json` 某条记录、APPROVALS 模板和 Runner 相关校验函数，以便有针对性修改适配器。不要绕开 AUTO-001 的门禁。
- 未经验证不要把网页暴露到局域网；软件只绑定 `127.0.0.1`，具有随机会话令牌、SameSite/HttpOnly cookie、Origin 检查和 CSRF 令牌。只提供预定义 Runner 命令，没有执行任意 Shell 的 API。

## 自动测试

`python3 -m unittest discover -s tools/auto/ui -p 'test_*.py' -v` — 7 个测试使用合成 Git 项目，覆盖审批成功、无计划拒绝、错误确认拒绝、未知格式拒绝、命令限制和两种常见队列结构。它们**不等于真实 Fishing 调度器兼容性已通过**。

## 反馈 / 排查

- 网页显示“队列结构不兼容”：请先查看 `tools/auto/queue.json` 的结构（不要直接修改）。
- 审批提示 Runner `check` 失败：网页会尝试回滚审批文件和队列；请核查 Git diff、Runner 状态和报错。
- 审批完成但 Git 提交失败：**不要立即重复批准**，检查 `git status`；已写入的账本和队列还在，先修复 Git 后再继续。
- 启动 Runner 失败：确认 `tasks/APPROVALS.md` 中有真实人工批准、模型本地 `9931` 可用、任务为 `exec_ready`、项目 Git 工作树不存在未知改动。
- AUTO-002 不修改 llama.cpp 的模型、256K 上下文或 `65536` 最大生成预算；全由已有 AUTO-001/Headless patch 控制。

## 不包含

不包含自由网页 Shell、自动批准、批量绕过审批、自动冻结解除、云端访问、LLM 聊天界面或对 Godot 源码的直接修改功能。
