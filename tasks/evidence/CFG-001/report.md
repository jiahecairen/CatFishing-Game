# CFG-001 Phase B 执行报告 — 3 鱼种 JSON + 配置校验

- 工单：CFG-001（queue `test_cmd`: `python3 -B tests/unit/run_cfg001_checks.py`，`needs_human: false`）
- 依据：`tasks/evidence/CFG-001/plan.md` + `review.md` + `tools/auto/queue.json` CFG-001 条目
- 环境：Godot `4.7.2.stable.official.ed1daf0bf`（`--version` 实测），macOS，HEAD=`29bdf20 Approve CFG-001 Phase B under delegation`
- 范围纪律：仅写 `data/**`、`scripts/config/**`、`tests/**` 与本证据目录；未读/未改 `tasks/APPROVALS.md`；无子代理、无后台任务、无 git commit/merge/push/stash/reset/clean；未动 `examples/**`、`schemas/**`、`docs/**`、`scripts/io/**`、`project.godot`、`tools/**`。

## 1. 改动文件清单（全部为新增，无已跟踪文件修改）

| 文件 | 说明 |
|---|---|
| `data/fish_species.json` | `cp examples/fish_species.json`，diff 为空（逐字节一致）：3 鱼种 river_carp/silver_perch/golden_trout，权重 60/30/10，价格 8/16/32 |
| `data/runtime_config.json` | `cp examples/runtime_config.json`，diff 为空：version=1, fps=30, 20/60s, 容量 10 |
| `scripts/config/fish_species_catalog.gd` | `FishSpeciesCatalog.load_catalog(path) -> {ok, error_code, species}`；两遍校验（字段→去重），12 个稳定错误码，失败零默认值 |
| `scripts/config/runtime_config.gd` | `RuntimeConfig.load_config(path) -> {ok, error_code, config}`；锁 version=1/fps=30/1..86400/min<=max/容量>=1（不锁 10 候选值） |
| `scripts/config/config_gate.gd` | `ConfigGate.can_start_economy(catalog, runtime)` 任一 !ok 即 false；`blocked_reasons()` 可枚举拒绝原因 |
| `tests/unit/fixtures/cfg001/*.json` | 12 个反例夹具（plan §3 清单）：dup_id, zero_weight, neg_weight, neg_price, bad_id, bad_rarity, missing_field, bad_version, invalid_json(截断), empty_species, min_gt_max, fps_not_30 |
| `tests/unit/test_cfg001_config.gd` | `extends SceneTree`：3 组正例 + 12 夹具反例 + 文件缺失路径；PASS→`CFG001 CONFIG PASS`+quit(0)，首败→`CFG001 CONFIG FAIL: <step>`+quit(1) |
| `tests/unit/run_cfg001_checks.py` | 标准库 runner：Python 独立值锁复核（data==examples）+ 夹具存在性 + 串行 Godot 导入/CFG-001/CORE-001 回归；按 queue 要求 HOME 指向本证据目录内临时目录（跑完即删）；要求 PASS 标记，拒绝 FAIL 标记、`SCRIPT ERROR`、非零退出 |

Godot 导入生成的 `*.gd.uid` 均落在上述允许目录内且被 `.gitignore` 忽略，不进 git 状态。

## 2. 执行命令与真实退出码（如实记录，含失败迭代）

| # | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 1 | `python3 -B tests/unit/run_cfg001_checks.py` | **1** | runner 正确拦截实现缺陷：test 脚本 `var path := FIXTURE_DIR + row[0]` 类型推断解析错误（step1=0, step2=FAIL/exit 0+SCRIPT ERROR, step3=0）|
| 2 | `python3 -B tests/unit/run_cfg001_checks.py` | **1** | 修复后仍失败：静态函数内 `fract()` 无法解析（step1=0, step2=FAIL/exit -15+SCRIPT ERROR, step3=0）|
| 3 | `python3 -B tests/unit/run_cfg001_checks.py`（最终） | **0** | `CFG001 RUNNER PASS`：step1-import=0, step2 `CFG001 CONFIG PASS`=0, step3 `CORE001 SMOKE PASS`=0，全部无 `SCRIPT ERROR` |
| 4 | `git status --porcelain` | 0 | 仅 `?? data/`、`?? scripts/config/`、`?? tests/unit/fixtures/`、`?? tests/unit/run_cfg001_checks.py`、`?? tests/unit/test_cfg001_config.gd`（既有 `?? tasks/evidence/_runner/` 为 runner 自有，未触碰）|
| 5 | `git diff --stat` | 0 | 空——零已跟踪文件改动（R-3 的 `icon.svg.import` 本次未被弄脏）|

## 3. 最终测试输出摘要（run 3，真实捕获）

- step1-import `--headless --editor --quit`：exit 0，全局类注册成功（`update_scripts_classes`: ConfigGate/FishSpeciesCatalog/RuntimeConfig，无 class_name 冲突）。
- step2 `--script res://tests/unit/test_cfg001_config.gd`：exit 0，stdout 含 `CFG001 CONFIG PASS`；覆盖正例 P1（catalog ok、恰 3 种、ids 顺序、与 examples 深度相等）、P2（runtime ok、与 examples 逐值相等、字面量 1/30/20/60/10）、P3（gate 放行且原因空）；反例 N1×10（catalog 夹具 error_code 精确匹配 + 空 species 零默认值 + gate 拒绝 + 原因恰 1 条）、N2×2（min_gt_max→`MIN_GT_MAX`、fps_not_30→`BAD_FPS`，config 空 + gate 拒绝）、N3（缺失文件→`FILE_MISSING`，gate 拒绝）。
- step3 `--script res://tests/unit/test_core001_smoke.gd`：exit 0，stdout 含 `CORE001 SMOKE PASS`（CORE-001 无回归，R-1 兜底成立）。
- 失败语义实证：run 1/2 中 runner 对 FAIL 标记、`SCRIPT ERROR`、非零退出（含 -15）真实判 1，门禁未伪造通过。

## 4. 覆盖的验收条目

| 验收条目 | 证据 |
|---|---|
| T-CONF-01 重复 species ID 拒绝 | `dup_id.json`→`DUP_ID`，gate=false |
| T-CONF-01 非正权重 | `zero_weight.json`/`neg_weight.json`→`BAD_WEIGHT` |
| T-CONF-01 负价格 | `neg_price.json`→`BAD_PRICE` |
| T-CONF-01 上钩 min>max | `min_gt_max.json`→`MIN_GT_MAX` |
| T-CONF-01 无效 JSON | `invalid_json.json`→`JSON_PARSE`（`JSON.new().parse()` Error 码，不崩溃、零默认值）|
| T-CONF-01 阻止经济启动 | `ConfigGate.can_start_economy` 对全部 13 个失败输入返回 false，`blocked_reasons` 可枚举 |
| V01-F01 约 3 鱼种 | `data/fish_species.json` 恰 3 种，测试断言 ids/权重/价格与 examples 深度相等 |
| V01-W03 / SDD-175 30 FPS | runtime 锁 `visible_fps==30`（`BAD_FPS` 反例通过）|
| SDD-177 20–60s 初值 | 正式文件 20/60 原样，范围 1..86400 + `MIN_GT_MAX` 校验 |
| SDD-172 容量 10 候选 | 只锁 `>=1` 整数，不锁 10；文件保留 10 |
| AGENTS §4 外部 JSON 必须验证/明确失败路径 | 21 个稳定错误码（catalog 12 + runtime 9 去重后），失败零默认值不变量 + 文件缺失 `FILE_MISSING` |
| CORE-001 不回归 | step3 exit 0 + `CORE001 SMOKE PASS` |
| R-4 经济参数防误改 | 字节级 cp + GDScript 深度相等 + Python runner 独立复核，三层值锁 |

## 5. 遗留风险 / 移交事项

- **L-1（plan D-2 既有偏差）**：`scripts/io/config_loader.gd` 骨架注释声称 CFG-001 实现它，但 `scripts/io/**` 不在允许范围；本票按 plan 在 `scripts/config/` 另立实现类，未触碰骨架。后续由 runner/人工决定 io 骨架薄转发或删除。
- **L-2（本机引擎行为）**：该 4.7.2 构建的 GDScript **静态函数内无法解析 `fract()`/`is_finite()` 等全局数学内建**（"not found in base self"），已用纯运算（`v - v == 0.0` 有限性 + `float(int(v)) == v` 整数性）替代。后续票在静态函数中用数学内建需注意。
- **L-3（runner 设计结论）**：Godot `-s` 脚本加载/编译失败时**退出码可能为 0**（run 1 step2），单靠退出码不可靠；必须同时校验 PASS 标记并拒绝 `SCRIPT ERROR`/FAIL 标记——runner 已内置，后续票沿用。
- **L-4（如实记录）**：run 2 step2 出现 exit **-15 (SIGTERM)**（脚本错误后 Godot 进程被终止，来源未定位）；run 3 未复现，全部退出码 0，不掩盖。
- **L-5（经济参数）**：60/30/10、8/16/32、20–60s、30FPS、容量 10 均为已批准初值/候选值，本票零改动；任何调节须用户批准。
- **L-6（范围外待办）**：`basket_capacity` 未锁 10（按 plan 属候选值）；GUI/桌面类验收不适用本票，留待 UI-001/G 系列人工验收。
- **L-7（可复现性）**：runner 默认 Godot 路径 `/Applications/Godot.app/Contents/MacOS/Godot`，可用 `GODOT_BIN` 覆盖；隔离 HOME 临时目录建在本证据目录内且跑完即删（当前已删，目录仅存 phaseA.out/plan.md/review.md/本报告）。
- 按调度约束未做任何 git 写操作，等待调度器统一提交。

PHASE-B-DONE
