# SIM-001 多随机种子虚拟时间模拟报告 — 中文摘要

- 本摘要由 `tools/sim/run_sim001_checks.py` 在真实运行通过后自动生成；数值为 SIM001 真实执行结果，非示例。
- 生成时间（UTC）：2026-11-11T21:14:02Z；Godot：4.7.2-stable (official)；机器可读报告：`sim_report.json`（同目录）。
- 执行环境：headless（无 GUI/无网络）；项目临时副本 + 隔离 HOME；主工程从不作为 Godot --path/cwd。
- 产品数值零改动：20/60 秒、30 FPS、容量 10、权重 60/30/10、价格 8/16/32 均按 `data/` 现状只读加载（runner 前置数值锁把关）。

## 1. 执行矩阵

- 20 个固定种子 101..120 × 2 场景 × {1h, 4h, 8h} 虚拟时长 = **120 run**（每格独立干净态起跑）。
- 场景 A `hold_until_full`：从不售鱼，满篓后每 60 虚拟秒持续尝试点击抛竿（模拟用户），统计拒绝行为。
- 场景 B `periodic_sell_1800s`：每 1800 虚拟秒把篮内全部鱼按唯一 sale id 出售一次并继续抛竿（1800s 为模拟策略常量，非产品数值）。
- 另加 1 个故障注入 run：seed=101、场景 B、8h，经 `AtomicSaveService`（临时目录）注入 rename/tmp_write 故障。
- 完整周期 = `request_cast → CASTING → WAITING → HOOKED → REELING → SETTLEMENT → commit_catch → ack(IDLE)`；单步 1.0 虚拟秒，tick 至多 1 转换、过冲结转（T-TIME-02）。

## 2. 关键统计（真实执行）

| 指标 | 值 |
|---|---|
| 完整周期（全部 5800 个周期） | 均值 42.885s / 中位 42s / P10 27s / P90 59s |
| 满篓首次装满（场景 A，60 run；null=该时长内未满） | 均值 413.85s / 中位 400s / P10 357s / P90 473s |
| 鱼种捕获数（120 run 合计） | river_carp 3498 / silver_perch 1733 / golden_trout 569（共 5800） |
| 鱼种占比 | carp 60.3% / perch 29.9% / trout 9.8%（权重 60/30/10 一致） |
| 鱼种总价值（捕获快照价） | carp 27984 / perch 27728 / trout 18208 金币 |
| 每次售出金币（场景 B sale 事件） | mean 127.635 金币 / 460 笔 |
| 满篓后 request_cast 被 BASKET_FULL 拒绝次数 | 15162（全部拒绝，无一进入 CASTING） |

## 3. 硬门禁（全部必须为 0/true）

| 字段 | 实测 | 要求 |
|---|---|---|
| `duplicate_catch_transactions` | 0 | 0（硬门禁） |
| `duplicate_sale_transactions` | 0 | 0（硬门禁） |
| `casts_started_while_full` | 0 | 0（硬门禁） |
| `wait_seconds_out_of_range` | 0 | 0（硬门禁） |
| `fault_transactions_committed_before_recovery` | 0 | 0（硬门禁） |
| `deterministic_replay_identical` | true | 40 对 (seed, 场景) 1h 独立重放两次，逐字段事件序列一致 |

## 4. 故障注入（seed=101，场景 B，8h，临时目录；T-SAVE-02 侧翼）

| 注入点 | 阈值 | 注入时钟秒 | 事务 ID | 失败码 | 同 ID 重试 |
|---|---|---|---|---|---|
| rename | 3600 s | 3625 | catch-1746293397-152970896 | PERSIST_FAILED | 解除后同 ID 重试成功（code=""） |
| tmp_write | 7200 s | 7255 | catch-1421824363-1453951900 | PERSIST_FAILED | 解除后同 ID 重试成功（code=""） |

故障期间新增已提交事务数 = 0；权威状态（金币/鱼篓/已处理 ID/revision/账本/checkpoint）零变化；解除后同 ID 重试均恰好生效一次。SAVE-001 回归（step5）同轮重跑通过。

## 5. 每 run 明细（120 行，全部来自本次真实执行）

| seed | 场景 | 时长 | 完成周期 | 首次装满 (虚拟秒, null=右删失) | 鱼种×数量(价值金) |
|---|---|---|---|---|---|
| 101 | hold_until_full | 1 h | 10 | 431 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 101 | hold_until_full | 4 h | 10 | 431 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 101 | hold_until_full | 8 h | 10 | 431 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 101 | periodic_sell_1800s | 1 h | 20 | 431 | golden_trout×1(32金) / river_carp×9(72金) / silver_perch×10(160金) |
| 101 | periodic_sell_1800s | 4 h | 80 | 431 | golden_trout×6(192金) / river_carp×49(392金) / silver_perch×25(400金) |
| 101 | periodic_sell_1800s | 8 h | 160 | 431 | golden_trout×16(512金) / river_carp×98(784金) / silver_perch×46(736金) |
| 102 | hold_until_full | 1 h | 10 | 395 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 102 | hold_until_full | 4 h | 10 | 395 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 102 | hold_until_full | 8 h | 10 | 395 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 102 | periodic_sell_1800s | 1 h | 20 | 395 | golden_trout×1(32金) / river_carp×14(112金) / silver_perch×5(80金) |
| 102 | periodic_sell_1800s | 4 h | 80 | 395 | golden_trout×9(288金) / river_carp×42(336金) / silver_perch×29(464金) |
| 102 | periodic_sell_1800s | 8 h | 160 | 395 | golden_trout×17(544金) / river_carp×87(696金) / silver_perch×56(896金) |
| 103 | hold_until_full | 1 h | 10 | 391 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 103 | hold_until_full | 4 h | 10 | 391 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 103 | hold_until_full | 8 h | 10 | 391 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 103 | periodic_sell_1800s | 1 h | 20 | 391 | golden_trout×2(64金) / river_carp×10(80金) / silver_perch×8(128金) |
| 103 | periodic_sell_1800s | 4 h | 80 | 391 | golden_trout×6(192金) / river_carp×42(336金) / silver_perch×32(512金) |
| 103 | periodic_sell_1800s | 8 h | 160 | 391 | golden_trout×13(416金) / river_carp×86(688金) / silver_perch×61(976金) |
| 104 | hold_until_full | 1 h | 10 | 478 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 104 | hold_until_full | 4 h | 10 | 478 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 104 | hold_until_full | 8 h | 10 | 478 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 104 | periodic_sell_1800s | 1 h | 20 | 478 | golden_trout×3(96金) / river_carp×10(80金) / silver_perch×7(112金) |
| 104 | periodic_sell_1800s | 4 h | 80 | 478 | golden_trout×7(224金) / river_carp×54(432金) / silver_perch×19(304金) |
| 104 | periodic_sell_1800s | 8 h | 160 | 478 | golden_trout×15(480金) / river_carp×98(784金) / silver_perch×47(752金) |
| 105 | hold_until_full | 1 h | 10 | 360 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 105 | hold_until_full | 4 h | 10 | 360 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 105 | hold_until_full | 8 h | 10 | 360 | golden_trout×1(32金) / river_carp×4(32金) / silver_perch×5(80金) |
| 105 | periodic_sell_1800s | 1 h | 20 | 360 | golden_trout×2(64金) / river_carp×12(96金) / silver_perch×6(96金) |
| 105 | periodic_sell_1800s | 4 h | 80 | 360 | golden_trout×10(320金) / river_carp×48(384金) / silver_perch×22(352金) |
| 105 | periodic_sell_1800s | 8 h | 160 | 360 | golden_trout×19(608金) / river_carp×97(776金) / silver_perch×44(704金) |
| 106 | hold_until_full | 1 h | 10 | 473 | golden_trout×3(96金) / river_carp×6(48金) / silver_perch×1(16金) |
| 106 | hold_until_full | 4 h | 10 | 473 | golden_trout×3(96金) / river_carp×6(48金) / silver_perch×1(16金) |
| 106 | hold_until_full | 8 h | 10 | 473 | golden_trout×3(96金) / river_carp×6(48金) / silver_perch×1(16金) |
| 106 | periodic_sell_1800s | 1 h | 20 | 473 | golden_trout×3(96金) / river_carp×16(128金) / silver_perch×1(16金) |
| 106 | periodic_sell_1800s | 4 h | 80 | 473 | golden_trout×12(384金) / river_carp×50(400金) / silver_perch×18(288金) |
| 106 | periodic_sell_1800s | 8 h | 160 | 473 | golden_trout×17(544金) / river_carp×99(792金) / silver_perch×44(704金) |
| 107 | hold_until_full | 1 h | 10 | 399 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 107 | hold_until_full | 4 h | 10 | 399 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 107 | hold_until_full | 8 h | 10 | 399 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 107 | periodic_sell_1800s | 1 h | 20 | 399 | golden_trout×1(32金) / river_carp×12(96金) / silver_perch×7(112金) |
| 107 | periodic_sell_1800s | 4 h | 80 | 399 | golden_trout×7(224金) / river_carp×46(368金) / silver_perch×27(432金) |
| 107 | periodic_sell_1800s | 8 h | 160 | 399 | golden_trout×13(416金) / river_carp×97(776金) / silver_perch×50(800金) |
| 108 | hold_until_full | 1 h | 10 | 351 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 108 | hold_until_full | 4 h | 10 | 351 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 108 | hold_until_full | 8 h | 10 | 351 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 108 | periodic_sell_1800s | 1 h | 20 | 351 | golden_trout×2(64金) / river_carp×13(104金) / silver_perch×5(80金) |
| 108 | periodic_sell_1800s | 4 h | 80 | 351 | golden_trout×7(224金) / river_carp×52(416金) / silver_perch×21(336金) |
| 108 | periodic_sell_1800s | 8 h | 160 | 351 | golden_trout×18(576金) / river_carp×103(824金) / silver_perch×39(624金) |
| 109 | hold_until_full | 1 h | 10 | 400 | river_carp×9(72金) / silver_perch×1(16金) |
| 109 | hold_until_full | 4 h | 10 | 400 | river_carp×9(72金) / silver_perch×1(16金) |
| 109 | hold_until_full | 8 h | 10 | 400 | river_carp×9(72金) / silver_perch×1(16金) |
| 109 | periodic_sell_1800s | 1 h | 20 | 400 | golden_trout×2(64金) / river_carp×16(128金) / silver_perch×2(32金) |
| 109 | periodic_sell_1800s | 4 h | 80 | 400 | golden_trout×11(352金) / river_carp×55(440金) / silver_perch×14(224金) |
| 109 | periodic_sell_1800s | 8 h | 160 | 400 | golden_trout×18(576金) / river_carp×108(864金) / silver_perch×34(544金) |
| 110 | hold_until_full | 1 h | 10 | 396 | river_carp×5(40金) / silver_perch×5(80金) |
| 110 | hold_until_full | 4 h | 10 | 396 | river_carp×5(40金) / silver_perch×5(80金) |
| 110 | hold_until_full | 8 h | 10 | 396 | river_carp×5(40金) / silver_perch×5(80金) |
| 110 | periodic_sell_1800s | 1 h | 20 | 396 | golden_trout×2(64金) / river_carp×12(96金) / silver_perch×6(96金) |
| 110 | periodic_sell_1800s | 4 h | 80 | 396 | golden_trout×7(224金) / river_carp×49(392金) / silver_perch×24(384金) |
| 110 | periodic_sell_1800s | 8 h | 160 | 396 | golden_trout×14(448金) / river_carp×88(704金) / silver_perch×58(928金) |
| 111 | hold_until_full | 1 h | 10 | 474 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 111 | hold_until_full | 4 h | 10 | 474 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 111 | hold_until_full | 8 h | 10 | 474 | golden_trout×1(32金) / river_carp×7(56金) / silver_perch×2(32金) |
| 111 | periodic_sell_1800s | 1 h | 20 | 474 | golden_trout×1(32金) / river_carp×14(112金) / silver_perch×5(80金) |
| 111 | periodic_sell_1800s | 4 h | 80 | 474 | golden_trout×7(224金) / river_carp×48(384金) / silver_perch×25(400金) |
| 111 | periodic_sell_1800s | 8 h | 160 | 474 | golden_trout×14(448金) / river_carp×103(824金) / silver_perch×43(688金) |
| 112 | hold_until_full | 1 h | 10 | 441 | river_carp×8(64金) / silver_perch×2(32金) |
| 112 | hold_until_full | 4 h | 10 | 441 | river_carp×8(64金) / silver_perch×2(32金) |
| 112 | hold_until_full | 8 h | 10 | 441 | river_carp×8(64金) / silver_perch×2(32金) |
| 112 | periodic_sell_1800s | 1 h | 20 | 441 | river_carp×17(136金) / silver_perch×3(48金) |
| 112 | periodic_sell_1800s | 4 h | 80 | 441 | golden_trout×4(128金) / river_carp×51(408金) / silver_perch×25(400金) |
| 112 | periodic_sell_1800s | 8 h | 160 | 441 | golden_trout×19(608金) / river_carp×94(752金) / silver_perch×47(752金) |
| 113 | hold_until_full | 1 h | 10 | 437 | golden_trout×2(64金) / river_carp×4(32金) / silver_perch×4(64金) |
| 113 | hold_until_full | 4 h | 10 | 437 | golden_trout×2(64金) / river_carp×4(32金) / silver_perch×4(64金) |
| 113 | hold_until_full | 8 h | 10 | 437 | golden_trout×2(64金) / river_carp×4(32金) / silver_perch×4(64金) |
| 113 | periodic_sell_1800s | 1 h | 20 | 437 | golden_trout×2(64金) / river_carp×9(72金) / silver_perch×9(144金) |
| 113 | periodic_sell_1800s | 4 h | 80 | 437 | golden_trout×9(288金) / river_carp×45(360金) / silver_perch×26(416金) |
| 113 | periodic_sell_1800s | 8 h | 160 | 437 | golden_trout×17(544金) / river_carp×90(720金) / silver_perch×53(848金) |
| 114 | hold_until_full | 1 h | 10 | 357 | river_carp×6(48金) / silver_perch×4(64金) |
| 114 | hold_until_full | 4 h | 10 | 357 | river_carp×6(48金) / silver_perch×4(64金) |
| 114 | hold_until_full | 8 h | 10 | 357 | river_carp×6(48金) / silver_perch×4(64金) |
| 114 | periodic_sell_1800s | 1 h | 20 | 357 | river_carp×10(80金) / silver_perch×10(160金) |
| 114 | periodic_sell_1800s | 4 h | 80 | 357 | golden_trout×10(320金) / river_carp×38(304金) / silver_perch×32(512金) |
| 114 | periodic_sell_1800s | 8 h | 160 | 357 | golden_trout×16(512金) / river_carp×84(672金) / silver_perch×60(960金) |
| 115 | hold_until_full | 1 h | 10 | 403 | river_carp×4(32金) / silver_perch×6(96金) |
| 115 | hold_until_full | 4 h | 10 | 403 | river_carp×4(32金) / silver_perch×6(96金) |
| 115 | hold_until_full | 8 h | 10 | 403 | river_carp×4(32金) / silver_perch×6(96金) |
| 115 | periodic_sell_1800s | 1 h | 20 | 403 | river_carp×11(88金) / silver_perch×9(144金) |
| 115 | periodic_sell_1800s | 4 h | 80 | 403 | golden_trout×5(160金) / river_carp×51(408金) / silver_perch×24(384金) |
| 115 | periodic_sell_1800s | 8 h | 160 | 403 | golden_trout×16(512金) / river_carp×95(760金) / silver_perch×49(784金) |
| 116 | hold_until_full | 1 h | 10 | 399 | river_carp×7(56金) / silver_perch×3(48金) |
| 116 | hold_until_full | 4 h | 10 | 399 | river_carp×7(56金) / silver_perch×3(48金) |
| 116 | hold_until_full | 8 h | 10 | 399 | river_carp×7(56金) / silver_perch×3(48金) |
| 116 | periodic_sell_1800s | 1 h | 20 | 399 | river_carp×15(120金) / silver_perch×5(80金) |
| 116 | periodic_sell_1800s | 4 h | 80 | 399 | golden_trout×8(256金) / river_carp×51(408金) / silver_perch×21(336金) |
| 116 | periodic_sell_1800s | 8 h | 160 | 399 | golden_trout×15(480金) / river_carp×109(872金) / silver_perch×36(576金) |
| 117 | hold_until_full | 1 h | 10 | 445 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 117 | hold_until_full | 4 h | 10 | 445 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 117 | hold_until_full | 8 h | 10 | 445 | golden_trout×1(32金) / river_carp×8(64金) / silver_perch×1(16金) |
| 117 | periodic_sell_1800s | 1 h | 20 | 445 | golden_trout×1(32金) / river_carp×14(112金) / silver_perch×5(80金) |
| 117 | periodic_sell_1800s | 4 h | 80 | 445 | golden_trout×5(160金) / river_carp×52(416金) / silver_perch×23(368金) |
| 117 | periodic_sell_1800s | 8 h | 160 | 445 | golden_trout×10(320金) / river_carp×104(832金) / silver_perch×46(736金) |
| 118 | hold_until_full | 1 h | 10 | 397 | golden_trout×2(64金) / river_carp×8(64金) |
| 118 | hold_until_full | 4 h | 10 | 397 | golden_trout×2(64金) / river_carp×8(64金) |
| 118 | hold_until_full | 8 h | 10 | 397 | golden_trout×2(64金) / river_carp×8(64金) |
| 118 | periodic_sell_1800s | 1 h | 20 | 397 | golden_trout×2(64金) / river_carp×15(120金) / silver_perch×3(48金) |
| 118 | periodic_sell_1800s | 4 h | 80 | 397 | golden_trout×7(224金) / river_carp×44(352金) / silver_perch×29(464金) |
| 118 | periodic_sell_1800s | 8 h | 160 | 397 | golden_trout×16(512金) / river_carp×85(680金) / silver_perch×59(944金) |
| 119 | hold_until_full | 1 h | 10 | 446 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 119 | hold_until_full | 4 h | 10 | 446 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 119 | hold_until_full | 8 h | 10 | 446 | golden_trout×1(32金) / river_carp×6(48金) / silver_perch×3(48金) |
| 119 | periodic_sell_1800s | 1 h | 20 | 446 | golden_trout×2(64金) / river_carp×10(80金) / silver_perch×8(128金) |
| 119 | periodic_sell_1800s | 4 h | 80 | 446 | golden_trout×10(320金) / river_carp×43(344金) / silver_perch×27(432金) |
| 119 | periodic_sell_1800s | 8 h | 160 | 446 | golden_trout×24(768金) / river_carp×93(744金) / silver_perch×43(688金) |
| 120 | hold_until_full | 1 h | 10 | 404 | golden_trout×3(96金) / river_carp×4(32金) / silver_perch×3(48金) |
| 120 | hold_until_full | 4 h | 10 | 404 | golden_trout×3(96金) / river_carp×4(32金) / silver_perch×3(48金) |
| 120 | hold_until_full | 8 h | 10 | 404 | golden_trout×3(96金) / river_carp×4(32金) / silver_perch×3(48金) |
| 120 | periodic_sell_1800s | 1 h | 20 | 404 | golden_trout×4(128金) / river_carp×10(80金) / silver_perch×6(96金) |
| 120 | periodic_sell_1800s | 4 h | 80 | 404 | golden_trout×9(288金) / river_carp×54(432金) / silver_perch×17(272金) |
| 120 | periodic_sell_1800s | 8 h | 160 | 404 | golden_trout×15(480金) / river_carp×101(808金) / silver_perch×44(704金) |

## 6. 提请用户审核的参数建议（仅建议，本票未改任何数值）

以下观察仅依据上表真实统计；任何调节（20–60s 等待、30 FPS、容量 10、鱼价/权重、模拟策略外的一切产品参数）都必须由用户批准并另开工单后才能实施（AGENTS.md §6、SDD §6、ACCEPTANCE §4）。

1. 满篓节奏：现状参数下场景 A 首次装满中位约 400 秒（约 6.7 分钟），1h 档 60 个 run 全部会装满；若希望挂机 1h 内不长期满篓停抛，可考虑调小容量或缩短等待区间——但会同时改变游戏节奏，需用户裁定。
2. 周期节奏：完整周期均值 42.885 秒（≈20–60s 等待 + 3s 阶段），P10/P90 = 27/59 秒；等待区间 20–60 均匀抽样与权重无关，如需不同节奏应调整 `bite_wait_min/max_sec`（须批准）。
3. 鱼种分布：实测占比与权重 60/30/10 目测一致（确定性 RNG，全周期 5800 条），稀有鱼价值占比 9.8%；如要更陡的价值曲线应改 `base_price`（须批准）。
4. 场景 B 售出均值 127.635 金币/笔（1800 模拟秒周期）；如需把「定期出售」做成产品自动功能属范围扩张（v0.1 仅手动出售，AGENTS §2），本票不做。

## 7. 范围与遗留

- 本票仅新增 `tools/sim/`（本 runner + `sim001_economy_sim.gd`）与本证据目录文件；未改 `scripts/**`、`data/**`、`examples/**`、`schemas/**`、`tests/**`、`tools/auto/**`、`project.godot`、`docs/**`；无 GUI、无网络、无安装。
- 8h 为**虚拟时间**模拟（SDD §4 虚拟时钟设计使然，1 秒虚拟步长事件驱动）；真实 8 小时稳定性属 REL-001。
- 右删失处理：某 run 在时长内从未装满时输出 `first_fill_seconds=null` + `never_full_reason=cycles_exhausted_by_horizon`，本次 0 例；跨时长汇总按未删失样本计。
- 模拟不写真实 `user://`：故障注入唯一持久化状态位于 OS 临时目录，run 结束即清理（step5 SAVE 回归同口径）。

## 8. Phase B 执行记录（AUTO-001 Phase B · SIM-001；本段由同一次真实运行生成）

### 8.1 改动文件清单（全部新增，严格限于允许范围 `tools/sim/**`、`tasks/evidence/SIM-001/**`）

| 文件 | 类型 |
|---|---|
| `tools/sim/sim001_economy_sim.gd` | 新增：`extends SceneTree` headless 模拟驱动（无 class_name；不写任何 res:///user:// 字面路径） |
| `tools/sim/run_sim001_checks.py` | 新增：Python 标准库 runner（数值锁→隔离副本→串行 Godot→解析 JSON→写证据） |
| `tasks/evidence/SIM-001/sim_report.json` | runner 本次真实运行写出的机器可读报告（120 run + 2 故障注入） |
| `tasks/evidence/SIM-001/report.md` | 本文件（runner 自动生成：统计 + 硬门禁 + 本执行记录） |

未改动：`scripts/**`、`data/**`、`examples/**`、`schemas/**`、`tests/**`、`tools/auto/**`、`project.godot`、`docs/**`、`tasks/TASKS.md`、`tasks/APPROVALS.md`（未读未改）；无 git 写操作；无子 Agent/并行/后台任务；零数值调节（20/60s、30 FPS、容量 10、权重 60/30/10、价格 8/16/32 按现状只读）。

### 8.2 执行命令与真实退出码（本次运行，非示例）

测试命令（项目根）：`python3 -B tools/sim/run_sim001_checks.py`

| step | 命令 | 真实退出码 |
|---|---|---|
| `step1-import` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --editor --quit` | 0 |
| `step2-sim001` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tools/sim/sim001_economy_sim.gd` | 0 |
| `step3-fsm001-regression` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tests/unit/test_fsm001_fsm.gd` | 0 |
| `step4-eco001-regression` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tests/unit/test_eco001_economy.gd` | 0 |
| `step5-save001-regression` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tests/unit/test_save001_save.gd` | 0 |
| `step6-core001-regression` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tests/unit/test_core001_smoke.gd` | 0 |
| `step7-cfg001-regression` | `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /var/folders/5m/p8k4z26d7sn0v2zxhvnddfn80000gn/T/run_sim001_2fyfz_lw/project --script res://tests/unit/test_cfg001_config.gd` | 0 |

前置 pre-flight（交付齐全 + 数值锁 + 模拟卫生检查）：全部通过后才进入 Godot 步骤；以上 7 步全部 exit_code=0 且报告硬门禁全过时 runner 才打印 `SIM001 RUNNER PASS` 并退出 0。本次 Godot 步骤串行总墙钟 10.52 秒。

### 8.3 测试输出摘要（真实）

- pre-flight：`deliverables present, value-lock frozen, sim hygiene clean`；
- step2：stdout 恰含一次 `SIM001 SIM PASS`、无 FAIL/`SCRIPT ERROR`/TIMEOUT；`SIM001_REPORT_BEGIN/END` 间 JSON 可解析，`pass=true`，三个硬门禁字段 + `wait_seconds_out_of_range` + `fault_transactions_committed_before_recovery` 全为 0，`deterministic_replay_identical=true`（40 对重放），`per_run` 恰 120 行，`fault_injection` 恰 2 条（rename/tmp_write 各一，`PERSIST_FAILED` → 解除同 ID 重试成功）；
- step3–step7：`FSM001 FSM PASS`、`ECO001 ECONOMY PASS`、`SAVE001 SAVE PASS`、`CORE001 SMOKE PASS`、`CFG001 CONFIG PASS` 各恰一次，退出码全 0；
- 完整 stdout/stderr 由 AUTO-001 调度器归档于本证据目录 `test-*.log`（attempt-1 的 `test-1.log` 同样以 `SIM001 RUNNER PASS`/EXIT=0 结束——上次失败为调度器会话级 TIMEOUT，非测试失败；本次 runner 全 suite 墙钟 10.52 秒）。

### 8.4 覆盖的验收条目（plan §7 映射，真实执行背书）

| 验收条目 | 本票覆盖方式（本次实测） | 证据 |
|---|---|---|
| SDD-178 / SDD V01-T02（多种子 1h/4h/8h 统计） | 20 seeds × 2 场景 × 3 时长 = 120 run；周期/满篓分布/鱼种占比与价值 | `sim_report.json` + 本文件 §2/§5 |
| 工单最小验收「重复交易/满篮新抛竿=0」 | `duplicate_catch/sale_transactions=0`、`casts_started_while_full=0` | §3 硬门禁表 + test log step2 |
| T-TIME-01（wait∈[20,60]、可复现） | `wait_seconds_out_of_range=0`；40 对独立重放逐字段一致 | §3 |
| T-TIME-02（步长/渲染无关） | 1.0s 虚拟步长 + FSM 单步单转换契约；FSM 回归重跑 | test log step2/step3 退出码 0 |
| T-ECO-01（满篓停抛、售后可续） | 场景 A 拒绝 15162 次全拒绝；场景 B 售出后持续抛竿 | §2/§5 |
| T-ECO-02/03（ID 重试不重复结算） | 每种子 ≥2 catch + ≥2 sale 抽样重试 ≤100 次，全部幂等拒绝 | §3 + ECO 回归 |
| T-SAVE-02 侧翼（故障不产生半提交/新事务） | rename/tmp_write 注入→`PERSIST_FAILED`→解除重试成功；恢复前新事务=0 | §4 + SAVE 回归 |
| T-CONF-01 边界（非法配置阻断经济） | FSM.initialize 内联 ConfigGate 加载真实配置；runner 数值锁 | pre-flight |
| 「数值调节必须人工批准」（AGENTS §6） | 零数值改动；建议仅成文于 §6「提请用户审核」段 | 数值锁 + §6 |

### 8.5 遗留风险（plan §6 摘要 + 现状）

| # | 风险 | 处置/现状 |
|---|---|---|
| R-1 | 误改数值污染冻结参数 | runner 前置数值锁令任何漂移即红；本票全部改动为新增，回滚=删 `tools/sim/` 与本证据目录新增文件 |
| R-2 | 大循环拖慢 CI | 本次全 suite 墙钟 10.52 秒（每步上限 600s 未逼近）；超时按 FAIL 处理，不放宽断言 |
| R-3/R-4 | 浮点/时区致跨机不可复现 | 事件字段整数化 + 逐字段哈希重放 + 自实现整数历法；本次 40 对重放全一致 |
| R-5 | 故障注入污染真实存档 | 仅写 OS 临时目录且 runner finally 清理；主工程从不作为 --path/cwd |
| R-6 | 报告被误读成「已批准调节」 | §6 固定声明参数未改动，调节须用户批准另票（AGENTS §6） |
| 遗留 | 8h 为虚拟时间非真实稳定性 | 真实 8 小时稳定性属 REL-001；UI-001 GUI 阻塞与本票无关且未触碰 |
