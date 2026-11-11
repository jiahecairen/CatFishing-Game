class_name FishingSystem
extends RefCounted
# 纯业务 FSM 骨架，可在 headless 环境测试（AGENTS.md §4）。
# 契约见 INTERFACES_AND_DATA §4：initialize(config, rng, clock, checkpoint) / can_cast /
# tick_effective(seconds) / request_cast / produce_catch_candidate / ack_settlement /
# pause / resume_if_safe / snapshot_checkpoint。
# FSM-001 实现：状态转移、注入 RNG + 独立虚拟时钟、上钩等待 20–60s（秒数，非帧数）。
# 禁止用 _process(delta) 帧计数做捕鱼等待；max_fps=30 只影响渲染，不参与业务计时。

enum State {IDLE, CASTING, WAITING, HOOKED, REELING, SETTLEMENT, PAUSED}
