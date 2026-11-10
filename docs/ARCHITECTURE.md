# v0.1 Architecture — Godot 4 / GDScript

**原则**：先最小可测、按职责解耦，不为 v0.3 NPC、v0.4 跨模式或未来多人提前制造空模块。当前模块名是**建议契约**，如与已有代码相冲突，先报告再调整。

## 1. 组件和依赖方向

```text
Main / Bootstrap
 ├── PlatformAdapter (macOS window / mouse / monitor APIs)
 ├── DesktopWindow (presentation / drag / click / status)
 │    └── CatPresenter (placeholder sprite + basic animation)
 └── GameController (coordinates actions, NO independent balances)
      ├── FishingSystem (pure FSM; Clock + RNG injected)
      ├── GameState (authoritative coins/inventory/event ledger)
      ├── ConfigLoader (fish JSON + runtime config validation)
      ├── SaveService (atomic persisted state / recovery)
      └── EventLog (structured, bounded, privacy-safe local logging)

Headless Tests ──> FishingSystem, GameState, SaveService, ConfigLoader
GUI Spike ──> PlatformAdapter + DesktopWindow
```

**边界**：Godot `Node`/`Control` 不直接决定鱼种、金币及库存；渲染、输入、音效永远是状态的消费者。应用进程允许状态机按游戏逻辑时钟工作，但**不把进程隐藏当作真实离线收入**。

## 2. 状态和经济所有权

- `GameState` 存储：`save_version`、wallet、basket inventory、processed catch/sale IDs、fishing runtime checkpoint、window geometry。它是唯一可确认经济数值的数据源。
- `FishingSystem` 只发出待结算命令（catch candidate event）。**不能直接修改金币**或视图存储。
- `GameController` 串行执行命令，先验证、计算 next_state、进行持久化提交，再向 UI 发布已确认状态。
- `SaveService` 负责可靠提交/备份/版本验证/安全加载。若写盘失败，旧已提交状态保留，不产生“成功”反馈。
- 对捕获和出售的重试以 `event_id` / `sale_id` 为幂等键；进程重启不得重发。

## 3. 捕鱼 FSM（最小原型）

`IDLE`（无任务、满篓或暂停）→ `CASTING` → `WAITING` → `HOOKED` → `REELING` → `SETTLEMENT` → `IDLE/CASTING`。

| 状态 | 触发 / 不变量 |
|---|---|
| CASTING | 鱼篓尚有空格、存档可写、无正在结算的冲突事件；为当前抛竿生成稳定 event ID |
| WAITING | RNG 按 `min=20,max=60` 分配等待秒数；仅根据**有效捕鱼时钟**推进，不按帧计数 |
| HOOKED | 记录上钩，避免重复触发，等待最小动画/事件阶段结束 |
| REELING | 完成可见收竿阶段；若图形未渲染，业务转换仍须按已获批准的时钟规则 |
| SETTLEMENT | 选择已验证鱼种、创建 fish instance ID、幂等持久化；成功后才展示获得鱼 |
| IDLE / PAUSED | 满篓、故障、用户动作冲突或暂停，不得新开 cast；明确原因与恢复条件 |

### 随机可重放

- 生产：可配置随机种子初始化策略；种子持久化或为当前事件记录已抽样 `bite_wait`、fish species，以便崩溃后重建相同结果。
- 测试：`Clock` 和 `RNG` 可注入，使用固定 seed、虚拟时间，不允许 `Engine.get_frames_drawn()` / `_process(delta)` 代替真实秒数。
- 要验证“有效时间”的定义，尤其隐藏/全屏/程序彻底退出，不得混淆；未裁决部分见 `SDD_v0.1.md` OPEN-001。

## 4. 像素表现与平台层

- `PlatformAdapter` 封装 `Window` 属性、坐标、缩放、屏幕边界、失焦隐藏等。不要让业务层调用原生系统 API。
- 透明/无边框/鼠标穿透、`Window.mouse_passthrough` 和 `mouse_passthrough_polygon` 按真实 Godot 版本测试；如果平台或渲染器有限制，技术探针必须证实，不盲写。
- 默认保守窗口层级：不能抢焦点、遮挡主要工作；是否置顶应遵守已确定的桌面用户设置，但 v0.1 只实现达到验收所必需的最小入口。
- 拖动定义阈值，防止误把点击当拖动；窗口位置保存，失去显示器时回退安全屏幕区域。
- 视觉层遵守可见时 30 FPS；隐藏仅停用不必要绘制，避免以隐藏触发“完全退出的离线挂机”。
- 素材只用临时 sprite 与一致锚点/逻辑像素缩放；不要造正式角色骨骼、服饰系统或大型精灵流水线。

## 5. 持久化方案（推荐）

建议 JSON 版本化存档（v0.1），没有云服务/数据库；可以有 `game_state.json`、`game_state.bak.json` 和临时文件。提交顺序：

1. 从已确认 state 复制待更新 state（不要在原 state 上先乐观发钱）。
2. 校验不可变约束（非负 coins、库存 ≤ cap、ID 不重复）。
3. 将新状态完整写到**同目录的 temp 文件**，显式检查写入错误并 flush；根据 OS/文件系统支持的方式原子改名替换主存档；保留可恢复备份（避免多个读写竞争）。
4. **仅提交成功后**更新内存的已确认 state 并通知 UI。
5. 崩溃恢复选择有效主/备份，检查 `save_version` 与事务记录；绝不同时重复执行已结算 ID。

可维护轻量事务记录 `processed_catch_ids` / `processed_sale_ids`（v0.1 数据量小），未来版本扩展之前明确迁移策略。**不能仅根据“文件已写入”假定崩溃时电源断开也绝对不丢数据**；通过故障注入测试并在报告中说明保障边界。

## 6. 事件与日志

建议字段：`timestamp_utc`、`severity`、`event`、`event_id`、`save_version`、`result`、`error_code`、`elapsed_ms`；捕获/出售、保存失败要可追踪。生产版最小化日志，避免绝对路径/隐私/屏幕内容/按键记录；本地轮换、绝不静默上传。

## 7. 项目目录（落地时优先保留既有结构）

```text
Fishing/
  project.godot                  # 若不存在，由批准后的技术票创建
  AGENTS.md
  docs/...
  tasks/...
  config/fish_species.json       # 由实现票写入，经 schema 校验
  config/runtime_config.json    # 初始可基于 examples/
  scenes/main.tscn
  scenes/desktop_overlay.tscn
  scripts/core/{game_controller,game_state,fishing_system}.gd
  scripts/io/{config_loader,save_service,event_log}.gd
  scripts/platform/{platform_adapter,desktop_window}.gd
  scripts/presentation/cat_presenter.gd
  tests/{unit,integration,spike}/
```

上面的布局是**建议**；不要只为贴合目录树而重构已有项目。实际文件命名必须记录在工单或 ADR。

## 8. 开发运行门禁

- `SPIKE-001` 是第一项：macOS 透明 / 穿透 / 拖动有明确 GUI 与 Godot headless 的分工。
- 紧接着锁定 JSON 契约、FSM 和经济事务；每个模块的单元测试可 headless 运行。
- 发现重大依赖、架构冲突或影响存档兼容，暂停并上报 Owner；普通不影响契约的小实现细节可自主决策并写开发记录。
