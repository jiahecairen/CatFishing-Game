# CFG-001 Phase A 计划 — 3 鱼种 JSON + 配置校验（AUTO-001，只读规划）
- 外部 JSON 配置必须验证；非法 species ID、负权重/价格、重复 ID、存档格式损坏都要有明确失败路径。

- 工单：CFG-001「3 鱼种 JSON + 配置校验」，前置 CORE-001（In Review，测试已通过并记录），最小验收 **T-CONF-01**，来源 `tasks/TASKS.md` 第 10 行与 `tools/auto/queue.json`（status=ready）。
- 允许文件范围（Phase B 强制）：`data/**`、`scripts/config/**`、`tests/**`。本 Phase A 全程只读，唯一写入即本文件。
- 依据：`docs/INTERFACES_AND_DATA.md` §1（配置契约）、`docs/DECISION_REGISTER.md` SDD-171/172/175/177、`docs/SDD_v0.1.md` V01-F01/V01-W03/§6 参数表、`schemas/fish-species.schema.json`、`schemas/runtime-config.schema.json`、`docs/ACCEPTANCE_TESTS.md` T-CONF-01、项目 Skills `fishing-state-and-save`、`godot-validation`。

## 1. 目标

1. 以 `examples/fish_species.json` 与 `examples/runtime_config.json` 的**原样占位值**落地正式配置到 `data/`（不改任何数值：权重 60/30/10、价格 8/16/32、20–60 s、30 FPS、容量 10 候选——这些是 SDD §6 已批准/候选值，任何调节须用户批准，本票禁止改动）。
2. 在 `scripts/config/` 实现纯数据校验器（无 Node 依赖，可 headless 测试），对非法数据返回**明确错误码**，绝不静默给默认值；提供"经济/FSM 可否启动"的门面查询，满足 T-CONF-01「非法配置阻止经济系统启动」的可测契约。
3. 新增 headless 单元测试：正例（正式配置合法、恰 3 鱼种）+ 全部 T-CONF-01 反例（重复 ID、非正权重、负价格、min>max、无效 JSON），退出码 0/1 语义与 CORE-001 冒烟一致。

## 2. Phase A 只读实测记录（真实命令与退出码）

| 检查 | 命令 | 退出码 | 结果 |
|---|---|---|---|
| 工作树 | `git status --porcelain` | 0 | 仅 `?? tasks/evidence/_runner/`（runner 自有，不触碰）；无用户未提交代码 |
| 近期历史 | `git log --oneline -15` | 0 | HEAD=`f8782a1 Queue CFG-001 for plan review`；CORE-001 In Review 证据链完整 |
| Godot | `test -x /Applications/Godot.app/Contents/MacOS/Godot && Godot --version --headless` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| 目录 | `ls -d config` | 1 | 仓库根**无 `config/`**（ARCHITECTURE §7 的 `config/` 仅为建议布局，queue 允许清单为 `data/**`，以 queue 为准，见 §6 偏差 D-1） |
| 骨架 | 读 `scripts/io/config_loader.gd` 等 9 个骨架 | 0 | 均为零实现骨架，注释声明的后续票归属；`scripts/io/**` **不在本票允许范围**，Phase B 不得改（偏差 D-2） |
| 冒烟基线 | 读 `tests/unit/test_core001_smoke.gd`、`project.godot`、`scenes/main.tscn` | 0 | CORE-001 测试以 `--script res://tests/unit/...` 运行，PASS→quit(0)/FAIL→quit(1) 约定 |
| schema/示例 | 读 `schemas/*.json`、`examples/*.json` | 0 | 人工比对一致；本机无 `jsonschema` 依赖（AUDIT 记录），校验逻辑改由 GDScript 在测试内实现 |
| Skills | `ls .dsh/skills` | 0 | `fishing-state-and-save`、`godot-overlay`、`godot-validation` 三件俱在，前两者已加载 |
| 忽略规则 | 读 `.gitignore` | 0 | `.godot/`、`*.uid` 被忽略 → headless 运行产生的 uid 缓存不会污染 git 状态 |

## 3. Phase B 要改动的文件（全部为**新增**，严格限于允许范围）

| 文件 | 内容 |
|---|---|
| `data/fish_species.json` | 与 `examples/fish_species.json` 逐值相同：`catalog_version=1`，3 鱼种 `river_carp/silver_perch/golden_trout`，权重 60/30/10，价格 8/16/32，rarity/asset_key 不变 |
| `data/runtime_config.json` | 与 `examples/runtime_config.json` 逐值相同：`config_version=1, visible_fps=30, bite_wait_min_sec=20, bite_wait_max_sec=60, basket_capacity=10` |
| `scripts/config/fish_species_catalog.gd` | `class_name FishSpeciesCatalog extends RefCounted`：`load_catalog(path: String) -> Dictionary` 返回 `{ok: bool, error_code: String, species: Array}` |
| `scripts/config/runtime_config.gd` | `class_name RuntimeConfig extends RefCounted`：`load_config(path: String) -> Dictionary` 返回 `{ok: bool, error_code: String, config: Dictionary}` |
| `scripts/config/config_gate.gd` | `class_name ConfigGate extends RefCounted`：`can_start_economy(catalog: Dictionary, runtime: Dictionary) -> bool`（任一 !ok 即 false，不吞错） |
| `tests/unit/fixtures/cfg001/*.json` | 反例夹具（提交入库，不放 data/）：`dup_id.json`、`zero_weight.json`、`neg_weight.json`、`neg_price.json`、`bad_id.json`、`bad_rarity.json`、`missing_field.json`、`bad_version.json`、`invalid_json.json`（截断/语法错）、`min_gt_max.json`、`fps_not_30.json`、`empty_species.json` |
| `tests/unit/test_cfg001_config.gd` | `extends SceneTree` 测试：全部 PASS → 打印 `CFG001 CONFIG PASS` 且 `quit(0)`；首败 → 打印 `CFG001 CONFIG FAIL: <step>` 且 `quit(1)`（沿用 CORE-001 约定） |

不改动（明确排除）：`scripts/io/config_loader.gd` 骨架（范围外，见 D-2）、`examples/**`、`schemas/**`、`docs/**`、`tasks/**`（证据目录由 runner 归档）、`project.godot`、`tools/auto/queue.json`（RUNNER_OWNED，test_cmd 由调度器回填，见 §5）。禁止新增第三方依赖或 JSON Schema 库。

## 4. 接口与不变量

**FishSpeciesCatalog.load_catalog(path)** 校验顺序（首个失败即返回 `ok=false` + 稳定 `error_code`，如 `FILE_MISSING / JSON_PARSE / BAD_VERSION / BAD_SHAPE / EMPTY_SPECIES / BAD_ID_PATTERN / DUP_ID / BAD_RARITY / BAD_WEIGHT / BAD_PRICE / BAD_ASSET`）：
1. `FileAccess.file_exists` + `FileAccess.get_open_error()`，打开失败 → `FILE_MISSING/FILE_OPEN`，不返回半成品。
2. `JSON.parse_string` 返回非 Dictionary / `parse_error != OK` → `JSON_PARSE`（无效 JSON 必须被拒，T-CONF-01）。
3. 形状：仅允许 `catalog_version`、`species` 两键（对齐 schema `additionalProperties:false`）；`catalog_version` 必须 `== 1` → `BAD_VERSION`（不静默兼容未来版本）。
4. 每元素 6 键齐全；`id` 匹配 `^[a-z][a-z0-9_]*$`；`rarity ∈ {common, uncommon, rare}`；`catch_weight` 数值且 > 0；`base_price` 为**非负整数**（Godot JSON 数字按 int/float 双态处理：float 须 `fract(v)==0` 才视为整数）；`asset_key`/`name_zh` 非空字符串。
5. ID 去重：两两比较，重复 → `DUP_ID`（schema `$comment` 明示由 ConfigLoader 层显式校验，本票落在 FishSpeciesCatalog）。
6. `species.size() >= 1`；正式 `data/fish_species.json` 由测试额外断言**恰好 3 种**（SDD V01-F01「约 3 种测试鱼」）。

**RuntimeConfig.load_config(path)**：同样先文件/JSON 失败路径；`config_version==1`、`visible_fps==30`（const，对齐 schema 与 SDD-175）、`1 <= bite_wait_min_sec <= 86400`、`1 <= bite_wait_max_sec <= 86400`、**`min <= max`**（违反 → `MIN_GT_MAX`，T-CONF-01）、`basket_capacity` 正整数。20/60 为已批准初值，10 为候选——校验器**不锁定 10**（schema `$comment`），由测试断言正式文件当前值即示例值。

**不变量（Phase B 必守）**：
- 校验器为纯 RefCounted 数据层：不 `Node`/`_process`、不读写 `user://`、不产生任何文件写入（夹具经 `res://tests/unit/fixtures/...` 只读加载）。
- 失败路径**零默认值**：`ok=false` 时不得回填 20/60/30/10 等任何"看起来能跑"的值（INTERFACES §1「不可静默制造默认价格」）。
- 错误码为稳定字符串常量，供 FSM-001/ECO-001 在启动前用 `ConfigGate.can_start_economy` 门禁（T-CONF-01「阻止经济系统启动」的机器可测形态：gate 返回 false 且原因可枚举）。
- **class_name 不得与现有全局类冲突**：`ConfigLoader`（scripts/io 骨架）已占用该名，故新类命名 `FishSpeciesCatalog` / `RuntimeConfig` / `ConfigGate`；Godot 重复 class_name 会导致全局类注册冲突并连累 CORE-001 冒烟回归。
- 不动业务：不实现 FSM 转移、不实现鱼篓/交易、不实现存档（分属 FSM/ECO/SAVE-001）。

## 5. 精确测试命令与预期退出码

主测试（Phase B 完成后依次执行；test_cmd 供调度器回填 `tools/auto/queue.json`，本票不自改 queue.json）：

1. 配置单测：
   `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_cfg001_config.gd`
   预期退出码 **0**，stdout 含 `CFG001 CONFIG PASS`；任一断言失败为 **1** 且含 `CFG001 CONFIG FAIL: <step>`。
2. CORE-001 回归（证明新全局类未破坏工程加载）：
   `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/rain/DevGame/Fishing --script res://tests/unit/test_core001_smoke.gd`
   预期退出码 **0**，stdout 含 `CORE001 SMOKE PASS`。
3. 范围自检：`git status --porcelain`
   预期退出码 **0**，且新增行仅落在 `data/**`、`scripts/config/**`、`tests/**`（`.godot/`、`*.uid` 被 .gitignore 覆盖，不出现）。
4. 测试内容覆盖矩阵（test_cfg001_config.gd 内）：正例 2（正式 catalog+runtime `ok=true` 且值与示例逐值相等、恰 3 种、gate=true）；反例 ≥ 10（§3 每个夹具 `ok=false` 且 error_code 精确匹配；gate=false）；无效 JSON 夹具断言 `JSON_PARSE` 而非崩溃（Godot 解析失败返回 null，须显式处理）。

## 6. 风险与回滚

- **D-1 偏差**：`docs/ARCHITECTURE.md` §7 建议 `config/fish_species.json`，但 queue 允许清单是 `data/**`。ARCHITECTURE §7 自述"布局是建议、实际文件命名必须记录在工单"——故落 `data/` 并在此记录，非需求变更。
- **D-2 偏差**：`scripts/io/config_loader.gd` 骨架注释称"CFG-001 实现：加载并校验 config/*.json"，但 `scripts/io/**` 不在本票允许范围。处置：本票在 `scripts/config/` 另立实现类，不触碰 io 骨架；由 runner/人工在后续票决定 io 骨架是否改为薄转发或删除。**不**把此偏差扩成越权改文件；如 runner 判违规即按 BLOCKED 流程上报。
- **R-1 class_name 冲突**：见 §4 不变量；回归测试 2 兜底。
- **R-2 JSON 数值类型**：Godot 4 对 `8` 与 `8.5` 分别给 int/float，`base_price` 整数校验用双态判断，勿用 `is int` 单一断言误杀/误放。
- **R-3 runner 门禁误报**：CORE-001 曾因 `icon.svg.import`（用户常驻编辑器 PID 27116 重建）与 queue.json 被判越界。Phase B 若 headless 运行致 `icon.svg.import` 变脏：如实记录于 report，**不得** git restore/commit/杀进程，交 runner 豁免逻辑处理。
- **R-4 经济参数误改**：data/ 两文件与 examples 逐值 diff 必须为空（仅键序/空白可不同）；测试断言逐值相等，防止"顺手调平衡"。
- **回滚**：Phase B 全部为新增未跟踪文件，回滚 = 删除 `data/`、`scripts/config/`、本票新增的 `tests/unit/test_cfg001_config.gd` 与 `tests/unit/fixtures/cfg001/`（仅限这些路径），或 `git checkout -- .` 不适用（无已跟踪文件修改）；基线 commit `f8782a1` 可逐票 diff。禁止 `git clean -fdx`（会波及其他证据目录）。
- 无需求变更、无破坏性操作、无经济参数调节 → 本票**无需**额外人工批准（queue `needs_human: false` 一致）。

## 7. 验收条目映射

| 验收条目 | 来源 | Phase B 证据 |
|---|---|---|
| T-CONF-01 重复 species ID | ACCEPTANCE_TESTS §2 | `dup_id.json` 夹具 → `error_code=DUP_ID`，gate=false |
| T-CONF-01 非正权重 | 同上 | `zero_weight.json`/`neg_weight.json` → `BAD_WEIGHT` |
| T-CONF-01 负价格 | 同上 | `neg_price.json` → `BAD_PRICE` |
| T-CONF-01 上钩 min>max | 同上 | `min_gt_max.json` → `MIN_GT_MAX` |
| T-CONF-01 无效 JSON | 同上 | `invalid_json.json` → `JSON_PARSE`，不崩溃、无默认值 |
| T-CONF-01 阻止经济启动 | 同上 | `ConfigGate.can_start_economy` 对任一失败配置返回 false |
| V01-F01 约 3 鱼种 JSON 配置 | SDD §2 | `data/fish_species.json` 恰 3 种，测试断言 |
| V01-W03 / SDD-175 30 FPS | SDD / DECISION | runtime 校验 `visible_fps==30`，正式文件值=30 |
| SDD-177 20–60s 初值 | DECISION | 正式文件 20/60 原样保留，min<=max 校验 |
| SDD-172 容量 10 候选 | DECISION | `basket_capacity>=1` 校验，不锁 10；文件保留 10 |
| AGENTS §4 外部 JSON 必须验证 + 失败路径 | AGENTS.md | §4 错误码全集 + 反例矩阵，零默认值不变量 |
| CORE-001 不回归 | queue deps | 回归命令 2 退出码 0 |
