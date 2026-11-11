# ECO-001 独立复核补丁与复测

日期：2026-11-11

## 范围与状态

- 真实工程路径已确认可读写：`/Users/rain/DevGame/Fishing`。
- 复核起点：`2cf0ada`；ECO-001 为 `in_review`，CORE-001 为 `done`。
- 仅修改经济实现与 ECO 测试/runner；不修改审批账本、冻结状态或需求数值。
- AUTO-001 的队列/日志运行时改动继续保留在工作树；本记录不清理这些文件。

## 复核发现与修正

1. `EconomyService.initialize()` 在一次成功初始化后再次遇到非法配置时，旧 `_initialized`、目录和幂等账本仍可能可用。`_init_reject()` 现会停用服务并清空旧目录及账本。E9 先建立有效服务、提交一条鱼，再执行非法重初始化，随后验证捕获/出售均为 `NOT_INITIALIZED`。
2. GDScript 浮点值 `2^63` 无法表示为有符号 64 位整数，但直接转为 `int` 可能饱和到 `INT64_MAX`。价格校验现在在转换前拒绝 `value >= 2^63`，E0 增加边界回归值。
3. ECO runner 现要求每个必需 PASS 标记在对应 stdout 中恰好出现一次，避免重复标记被当作有效通过。

## 实测

- `git diff --check -- scripts/economy/economy_service.gd scripts/economy/fish_instance.gd tests/unit/test_eco001_economy.gd tests/unit/run_eco001_checks.py tools/auto/queue.json`：退出码 0。
- `python3 -B tests/unit/run_eco001_checks.py`：退出码 0。隔离临时副本内导入、ECO-001、CORE-001、CFG-001、FSM-001 全部退出码 0；四个测试 PASS 标记各出现一次；无 FAIL 标记或 `SCRIPT ERROR`。
- `python3 -B tools/auto/runner.py selftest`：退出码 0，40/40 项通过，覆盖 tracked queue 状态豁免与篡改拦截、`tools/auto` 其他文件门禁、`icon.svg.import` 归属、先导入再测、PASS/脚本错误门禁、仅白名单提交及并发导入冻结保护。
- 自测中的模拟冻结/解冻运行于自测临时仓库。复测后真实队列仍为 `frozen=None`；CORE-001=`done`，ECO-001=`in_review`。

## 处理结论

上述三项修正及回归测试通过。ECO-001 仍保持 `in_review`，留待项目既定验收流程；本次没有改状态或审批记录，也没有推送远端。
