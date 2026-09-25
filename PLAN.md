# 魔方教学软件方案（v6：P1.5~P4 全功能详设，三轮审查修订）

环境：Godot 4.7.2 stable，GDScript。目标目录即本仓库根。
测试经验复用 `EXPERIENCE.md`（headless 自测 + X 会话 opengl3 截图）。

**产品定位：魔方教学软件**（3D 模拟器为地基，层先法分步教学为差异化核心）。
MVP 仍是 3 阶模拟器；架构参数化保证 NxN 只加不改；异形魔方明确不支持（§11）。

## 0. 产品路线图（源自市场调研 sess_d4ad023e）

| 期 | 内容 | 对标 | 状态 |
|---|---|---|---|
| P1（本方案 MVP） | 3D 模拟器 + 公式播放器 + 54 面导出 + 步数 + **MCP 外部控制** | 魔方栈（转动/演示内核）+ 外部 AI 可驱动的魔方（GAN 生态思路的软件版） | 已实现（§1~§9） |
| P1.5 | 鼠标拖层（raycast 命中面 + 拖动方向推断转层） | 魔方栈/Cube Solver 3D | 详设见 §13 |
| P2 | 层先法（LBL）分步教学：逐块教学引擎 + 阶段侧栏 + 逐步提示 + LBL 求解器 | 魔方学院/魔方小白（痛点：看不懂教程、记不住公式） | 详设见 §14；MCP 已就绪 = 外部 AI 教练可直接驱动魔方演示 |
| P3 | 计时器 + WCA 级打乱（kociemba 均匀随机状态）+ AO5/12 统计 | csTimer/Twisty Timer | 详设见 §15 |
| P4 | CFOP 案例训练（OLL/PLL/F2L，数据取自 lukejacksonn/cube） | CFOP Trainer/SpeedCubeDB | 原则级详设见 §16（case 表开工前再补） |

**明确不做（调研依据）**：拍照识别真实魔方、蓝牙智能魔方硬件协议、自研最优解求解器（LBL 教学引擎除外，见 §14）、AI 教练内置、在线对战。
最优解不自研：桥侧 optional `kociemba`（§6.3/H4）；MVP 已备好输入格式（§1 决策 1 的 to_facelets）。

## 1. MVP 技术路线

**视觉即状态：cubie 节点，不写贴纸置换表**（v1~v4 三轮验证，保持不变）。

调研与 MCP 驱动的裁决与增量：

1. **54 面数组冲突裁决**：核心模型不变，**单向导出** `to_facelets() -> PackedByteArray`（标准 URFDLB 54 序）。不做双向同步。P2 阶段匹配、P3+ 求解器、MCP get_state 均以此为源。
2. **公式播放器 `play_alg(alg)`**：解析 WCA 记号（`U D L R F B` + `'` + `2`）→ 展开为三元组入转层队列。教学/公式演示/MCP 的基础设施。
3. **步数统计**：手动转 +1、撤销 -1、打乱/播放/还原回放不计。
4. **全量日志 `full_log`（v5 新增，MCP 还原的根基）**：撤销栈之外再记一份**一切状态变更**的顺序日志（玩家步、undo 步、alg 播放步、打乱步均追加；reset 清空）。**不变式（v5.1）：full_log 恒为"初始态→当前态"的路径**。`restore()` = 逆序逐条取反入动画队列，**每执行一条回放步即从 full_log 尾部 pop 一条**——无求解器也能动画还原任意可达状态（回放语义，非最优解），且任意时刻被打断，剩余 full_log 自动就是剩余路径，再 restore 依然成立（v5.1，取代 v5 的"入口快照+清空"，该方案在中断后 restore 永久失效）。

其余不变：转层动画纯演出、状态精确回写（§4）、视角只动相机、还原判定按面查同色。
队列上限修订（v5 二审 F1）：**上限 8 只约束键盘手动输入**（防狂按积压，队满丢弃仅发生在键盘入口）；`play_alg`/`restore` 程序化批量入队不受限（否则长公式与回放丢步、状态错乱）。

## 2. NxN 兼容性设计（已确定后续要做，实现必须遵守）

1. **坐标约定**：`grid_pos: Vector3i` 各分量 ∈ `{-(n-1), ..., n-1}` 步长 2。n=3 → {-2,0,2}；n=4 → {-3,-1,1,3}。全整数 ⇒ 90°/180° 旋转矩阵元素恒 0/±1 ⇒ 浮点零误差。
2. **转层请求三元组**：`(axis: Vector3, layers: Array[int], angle: float)`。宽转 = layers 多值一次动画，键位后置。
3. **全参数化**：n、层集合、贴色、相机距离由 n 推导，禁止字面量 `-1/1/27/9`。
4. **架构保障**：自测以 N=4 再跑全绿（§7.2）。
5. **后置**：宽转键位、阶数选择 UI、NxN 视觉测试。
6. `play_alg`/`to_facelets` 为 3 阶语义，NxN 接入时仅作用于外层，无需改动（v6 修订：小写宽转记号是唯一例外，解析随 n 生效，见 §17.2）；MCP 命令层对 n 透明（state 返回 n）。

## 3. 常量与数值（实现直接抄；`n` 出现处均为变量）

### 3.1 面定义表

| 记号 | normal | 外层条件（`E := n-1`） | 色 | RGB (0-1) | facelet 序基准 |
|---|---|---|---|---|---|
| U | `UP` (0,1,0) | `y == +E` | 白 | .95,.95,.95 | 0-8 |
| R | `RIGHT` (1,0,0) | `x == +E` | 红 | .85,.12,.12 | 9-17 |
| F | `BACK` (0,0,1) | `z == +E` | 绿 | .10,.70,.25 | 18-26 |
| D | `DOWN` | `y == -E` | 黄 | .95,.85,.10 | 27-35 |
| L | `LEFT` | `x == -E` | 橙 | .95,.50,.05 | 36-44 |
| B | `FORWARD` | `z == -E` | 蓝 | .15,.35,.90 | 45-53 |

- 顺时针 = `Basis(normal, -PI/2)`（Godot 右手系）。坐标系 x=+R, y=+U, z=+F。
- **facelet 行列序（明确定义）**——每面 9 格行主序，与 Kociemba URFDLB 标准一致：

| 面 | 行方向（上→下） | 列方向（左→右） | 首格 r0c0 | 末格 r2c2 |
|---|---|---|---|---|
| U | z: B→F | x: L→R | ULB (-E,E,-E) | URF (E,E,E) |
| R | y: U→D | z: F→B | URF (E,E,E) | DRB (E,-E,-E) |
| F | y: U→D | x: L→R | UFL (-E,E,E) | DFR (E,-E,E) |
| D | z: F→B | x: L→R | DLF (-E,-E,E) | DBL (-E,-E,-E) |
| L | y: U→D | z: B→F | ULB (-E,E,-E) | DLF (-E,-E,E) |
| B | y: U→D | x: R→L | UBR (E,E,-E) | DBL (-E,-E,-E) |

  正确性锚点（Kociemba cornerFacelet 标准表，自测断言用）：URF=(U9,R1,F3)、ULB=(U1,L1,B3)、DFR=(D3,F9,R7)、DBL=(D7,B9,L7)。

### 3.2 几何与动画

| 参数 | 值 | 说明 |
|---|---|---|
| 间距 | 1.0 | `position = grid_pos * 0.5` |
| cubie 边长 | 0.94 | BoxMesh 留缝 |
| 贴纸 | 0.82²，偏移 0.471，`look_at` 对齐 | 防 z-fighting |
| 动画 | 0.18s 线性；双转（`2`）单次 180° | 仅手动/播放/回放时 |
| 相机 | (1,1,1) 方向，距离 `1.7n + 2.0`，FOV 45 | v6.2：轨迹球四元数姿态（`_view_quat`）替代欧拉 yaw/pitch，全向无极点（roll 歪斜按裁决保留）；up 取相机自身；滚轮缩放 `0.5~2.0 ×` 基准距离，单步 ×1.1；Home/顶栏「回正」复位 |
| 灯光 | DirLight (-45°,30°,0) + 环境光 0.6 | 纯 albedo |
| cubie 数 | `n³ − (n−2)³`（n=3→26），跳过纯内部块 | 内部块永不被选层 |

## 4. 转层核心算法

```gdscript
# 双入口：
#   apply_turn(axis, layers, angle) —— 瞬时：按 layers 直接选块 bake，不经 pivot、
#       无 reparent 无动画。打乱与全部自测走此入口；bake 数学（步骤 3）与动画路径共用。
#   enqueue_turn(...) —— 动画：入队，队列驱动 _do_turn（reparent + tween 演出）。
#       用户键盘、播放 alg、restore 回放走此入口。
func _do_turn(axis: Vector3, layers: Array, angle: float) -> void:
    var R := Basis(axis, angle)                    # 90°/180° 时元素仅 0/±1
    for cubie in cubies:                           # 1. 选层 reparent
        if layers.has(axis 分量 of cubie.grid_pos):
            cubie.reparent(pivot, true)
    var tw := create_tween()                       # 2. 动画（纯演出）
    tw.tween_method(func(t): pivot.basis = Basis(axis, angle * t), 0.0, 1.0, 0.18)
    await tw.finished
    for cubie in pivot.get_children():             # 3. bake：精确值覆盖
        cubie.reparent(self, true)
        cubie.basis = R * cubie.basis
        cubie.position = (R * cubie.position).snapped(Vector3.ONE * 0.5)
        cubie.grid_pos = Vector3i((R * Vector3(cubie.grid_pos)).round())
    pivot.basis = Basis()                          # 4. 复位，发下一发

func play_alg(alg: String) -> void:
    for token in alg.split(" ", false):
        var face := 记号表[token[0]]                # → (axis, 外层 layer)
        var inv := "'" in token
        var angle := PI if "2" in token else (-PI/2 if not inv else PI/2)
        enqueue(face.axis, [face.layer], angle)     # R2' 等价 R2："2" 优先于 "'"

func to_facelets() -> PackedByteArray:             # 54 字节 URFDLB
    for face in 6 面法线:                           # 行/列枚举按 §3.1 表
        for p in 面上全部格:
            out[i] = sticker_color_id(lookup(p), lookup(p).basis.inverse() * normal)
# 输出映射：color_id 0-5 在 solved 态恰为面序 URFDLB，逐字节映射面名字符
# 即得 Kociemba 标准 54 字符串。
```

- **瞬时模式**（打乱/自测）：`apply_turn` 直接选层 bake，不经 pivot 与 tween。
- **撤销**：历史栈记 `(axis, layers, angle)`，撤销 = angle 取反。**原子性**：先验队未满，满则整个 undo 拒绝；可入才"弹栈 + 入队"。`play_alg` 不入撤销栈（教学演示非玩家操作），步数不计。
- **full_log（v5）**：玩家步、undo 步、alg 步、打乱步**全部追加**（undo 也是状态变更，必须记，否则 restore 回放错乱）；reset 清空。回放步不追加而是从尾部 pop（不变式见 §1 决策 4），故任意中断后 log 自动收敛为剩余路径。
- **restore()（v5.1 修订）**：入口 kill tween + 清队列 + **清空撤销栈**（F2），**不快照不清空 full_log**；逆序逐条取反 `enqueue_turn`（走"不计步"通道，批量入队不受上限），**每条回放步 bake 完成即 pop full_log 尾部一条**。回放中被打断或二次 restore 天然安全：剩余 log 即剩余路径，restore 幂等。完成时 full_log 空、moves 归 0（与 reset 一致）。
- **打乱（v6.3）**：random-move 混合层——3 阶恒外层单层（键盘可复原、LBL 假设中心定色不可引入中央层转动），N≥4 每步随机取"单层（任意层，含奇数阶中央层）/ 2~3 层连续宽转"之一，过滤同 axis 连续，宽层永不覆盖全部 n 层；步数对齐 WCA 官方（2 阶 11，3 阶 25，4 阶 40，5 阶 60，6 阶 80，7 阶 100），显式 steps（测试/MCP）优先。策略对齐 WCA 官方 TNoodle 的 NxN random-move（调研 2026-09-25：NxN 官方打乱非随机状态而是随机步序列）。完成清空撤销栈与步数。P3 的 WCA 均匀打乱走桥侧 kociemba（§15.2，仍限 3 阶）。
- **打断/追加矩阵（v5.1，取代"入口一律 kill+清队列"）**：

| 入口 | 播放期间行为 |
|---|---|
| `scramble` / `reset` / `restore` | **打断**：kill tween + 清队列（重置类意图；pop 不变式保证打断后状态与 log 自洽） |
| `play_alg` / MCP `apply_alg` | **追加**：不清队列，顺序播放（教学演示连续下发不丢步） |
| 键盘转层 / 拖层 / UndoBtn | **忽略**（程序化批次播放中，bool 标志判定；UndoBtn 置 disable；拖层要求队列空才可起手） |
| 拖层手势进行中 | **命令暂停**：`_dragging` 标志挡住分发器与队列推进，一切外部命令忽略，松手 snap 后恢复（手势原子，§13） |
| PlayBtn / Esc | 照常（PlayBtn 走 play_alg 追加通道） |
- **还原判定**（队列空且非动画中；不依赖中心块，NxN 通用）：

```gdscript
func is_solved() -> bool:
    for normal in 6 面法线:
        var ref := 面上第一格颜色
        for p in 面上全部格:                        # normal 分量 == ±E
            if lookup(p).stickers[lookup(p).basis.inverse() * normal] != ref: return false
    return true
```

### P1.5 / P2 详设（v6 已补全，正文见 §13/§14）

- **拖层**：命中即拖/未命中 orbit、实时预览+松手 snap、手势原子——完整规格见 §13。
- **P2 教学引擎**：逐块算法（非阶段级固定公式），引擎即 LBL 求解器，`solve`/`hint` 白送——完整规格见 §14；MCP 工具 `cube_solve`/`cube_hint` 已定（§6.3）。

## 5. 场景与文件结构

```
project.godot            # 主场景 scenes/main.tscn，1152x648
scenes/main.tscn
# Main (Node3D, main.gd)
# ├─ WorldEnvironment / DirectionalLight3D / Camera3D
# ├─ CubeRoot (Node3D, cube.gd)      ← cubie 与 Pivot 动态生成
# ├─ CubeServer (Node, cube_server.gd) ← TCP NDJSON 服务器（§6）
# └─ UI (CanvasLayer)
#    ├─ TopBar: ScrambleBtn / UndoBtn / ResetBtn (+ AlgEdit LineEdit + PlayBtn)
#    ├─ StatusLabel: "已还原 ✓ / 自由模式 · 步数 N"
#    └─ HelpLabel: "U D L R F B 转层 · Shift 反向 · 左键拖拽转视角 · Esc 退出"
scripts/cube.gd          # setup(n)、转层队列、play_alg、to_facelets、full_log、restore、判定
scripts/cube_server.gd   # TCP NDJSON 服务器：_process 轮询收发，命令分发到 cube 公开 API
scripts/main.gd          # 输入、orbit、UI
tools/mcp_bridge.py      # 零依赖 Python stdio MCP 桥（§6）
tests/self_test.gd       # extends SceneTree，阶数参数
tests/visual_test.gd     # opengl3 截图，仅 N=3
```

- 输入：`_unhandled_key_input`（UDLRFB + Shift 反向 + Esc + Home 复位视角）；左键命中拖层 / 未命中 orbit（v6.2：轨迹球四元数全向，滚轮缩放）。

## 6. MCP 外部控制服务（v5 新增）

### 6.1 架构裁决

**游戏内 TCP NDJSON 服务器 + 外部 stdio MCP 桥**，两层职责分离：

- 游戏侧只实现最小协议：一行 JSON 请求 → 一行 JSON 响应（NDJSON）。`TCPServer` 仅监听 `127.0.0.1:8788`（端口可改：`godot ... -- --cube-port=N`，经 `--` 分隔的用户参数读 `OS.get_cmdline_user_args()`）；`_process` 中 `poll/take_connection`，主线程分发 → 与动画/队列天然无竞态。
- MCP 协议（initialize 握手、tools/list、tools/call、JSON-RPC 2.0）由 `tools/mcp_bridge.py` 承担：零依赖（仅标准库），stdin 逐行读请求、stdout 写响应、日志走 stderr（**stdout 纯 JSON-RPC，任何引擎杂音不经过此进程**）；每个 tools/call 连一次 TCP 发一行收一行。

**否决的替代**：① Godot 直接做 stdio MCP server——MCP 客户端要拥有进程生命周期（spawn/kill），但游戏是用户启动的窗口应用，且 Godot 引擎自身输出会污染 stdout JSON-RPC 流；② Godot 内直接实现 Streamable HTTP MCP——需在 GDScript 手写 HTTP 解析 + MCP 握手，复杂度远超桥脚本且难测试。

### 6.2 NDJSON 命令表（游戏侧）

请求 `{"id": 1, "cmd": "...", ...参数}` → 响应 `{"id": 1, "ok": true, "data": {...}}` 或 `{"id": 1, "ok": false, "error": "..."}`。

| cmd | 参数 | 语义 | data 返回 |
|---|---|---|---|
| `state` | 无 | **实时**读当前状态。facelets/solved 反映**已 bake 状态**，pending 队列不含在内；客户端以 `animating`/`queue_len` 判稳定，轮询至两者清零再读（v5.1） | `{n, facelets(54 字符 URFDLB 串), solved, moves, animating, queue_len}` |
| `scramble` | `steps=25`（可选） | 瞬时打乱（同按钮） | `{facelets, solved: false, moves: 0}` |
| `restore` | 无 | 动画回放 full_log 逆序回到初始态 | `{queued: K}`（立即返回；用 `state` 轮询进度） |
| `reset` | 无 | 瞬时重置（重建 cubie） | `{facelets, solved: true}` |
| `apply_alg` | `alg: String` | play_alg 入队播放（不计步） | `{queued: K}` |
| `solve` | 无 | **LBL 解（纯计算不执行，3 阶专用，N≠3 时 ok:false）**：按 7 阶段分段 | `{alg, stages:[{name, alg}]}` |
| `hint` | 无 | 教学状态：当前阶段/进度/下一步建议（3 阶专用，§14） | `{stage, progress, suggestion:{piece, alg, text}}` |

未知 cmd → ok:false。命令分发函数与 socket 层解耦（分发器收/返 Dictionary），自测直测分发器。

**参数校验（v5.1，信任边界）**：分发器入口统一校验，越界/非法一律 ok:false，且**校验先于入队**（全有或全无，不存在半执行）：`steps ∈ [1,100]`；`alg` 非空、≤2000 字符、≤300 token、每 token 须为合法 WCA 记号（v6:NxN 下含小写宽转 `udlrfb`，3 阶下小写非法，§17.2）。UI AlgEdit 共用同一校验函数。`hint`/`solve` 与 `state` 同口径：facelets 反映已 bake 状态，播放中调用返回的是当前已 bake 态的建议（引擎纯函数，天然如此）。

### 6.3 MCP 工具表（桥侧，均映射一个 NDJSON cmd）

`cube_get_state` / `cube_scramble` / `cube_restore` / `cube_reset` / `cube_apply_alg`（参数 alg）+ v6 增量：`cube_solve`（LBL 转发）/ `cube_hint`（教学状态转发）/ `cube_solve_optimal`（桥侧 kociemba，≤22 步）/ `cube_scramble_wca`（桥侧均匀随机状态打乱并**代为执行**：随机合法状态 → kociemba.solve → 解取逆 → 经 NDJSON `apply_alg` 打上，返回值带打乱序列；`kociemba` 未安装时后两工具仍列于 tools/list，调用返回 isError + `pip install kociemba` 指引）。工具结果以 `{content:[{type:"text", text: JSON}], isError: false}` 返回；TCP 连不上（游戏未运行）→ `isError: true` + 提示信息。

MCP 客户端接入配置（ZCode / Claude Desktop 等）：
```json
{ "mcpServers": { "cube": { "command": "python3", "args": ["/abs/path/to/tools/mcp_bridge.py"] } } }
```

### 6.4 边界与安全

- 仅绑 127.0.0.1，无鉴权（本地教学工具，接受；见 §10）。**同一时刻仅服务一个连接**：新连接 accept 后立即断开（v5.1）；`listen` 失败（端口被占，含 `--cube-port` 指定端口）仅 `push_warning`，游戏照常运行（v5.1）。
- restore 是回放语义（步数 ≈ full_log 长度），非最优解；最优解经桥侧 optional `kociemba` 的 `cube_solve_optimal` 提供（§6.3）。
- 桥手写 JSON-RPC 保留 MCP 版本回显规则（echo 客户端 protocolVersion，缺省 "2025-06-18"）；若实测客户端不兼容，升级路径 = 换官方 `mcp` Python SDK（接口不变，只改桥内部）。

## 7. 自测清单（self_test.gd，exit code 判定）

自测执行路径：全部走 `apply_turn` 瞬时入口（bake 数学与动画路径共用）；动画演出由 visual_test 覆盖。

### 7.1 N=3 主断言
1. `(R U R' U') × 6` → solved 且 grid_pos 集合还原（方向写反金标准）。
2. 100 步随机 → 坐标集合 == 外露块全集；basis 元素偏差 < 1e-6。
3. 打乱 25 → 逆序撤销 → solved。
4. 单步 R → 非 solved，撤销 → solved。
5. **`to_facelets()` 标准符合性**：solved 时输出恰为 URFDLB 复原序；**4 角环断言**（URF=(U9,R1,F3)、ULB=(U1,L1,B3)、DFR=(D3,F9,R7)、DBL=(D7,B9,L7)）；`apply_turn(R)` 后 facelet 变化符合 U→B→D→F 环。
6. **`play_alg` 与键盘等价**：`play_alg("R U R' U'")` 与逐键触发产生相同 facelets，步数不计。

### 7.2 N=4 参数化冒烟
7. `setup(4)`：cubie 数 == 56；坐标集合 {±3,±1}³ 外露块。
8. `R × 4`、`U × 4` → solved 且集合不变。
9. 打乱 25 → 撤销 → solved。

### 7.3 MCP/full_log（v5）
10. **NDJSON 分发器直测**（不起 socket）：`state` 返回结构完整（facelets 长 54）；`scramble` 后 solved=false 且 facelets 变化；`reset` 后 solved=true 且 full_log 清空。
11. **restore 数学**：随机 30 步（混入 undo）后，按 full_log 逆序取反逐条 apply → solved 且坐标全集不变——验证"undo 也入 log"与逆序回放正确性。
12. **socket 冒烟**：headless 起 CubeServer，测试内用 `StreamPeerTCP` 连 127.0.0.1 发 `{"id":1,"cmd":"state"}` 一行，收到合法 JSON 响应。

### 7.4 打断/追加与参数校验（v5.1）

13. **追加语义**：连续两次 apply_alg（第二条到达时第一条仍在播）→ 两条全部执行，终态 facelets == 两条依次独立 apply 的预期。
14. **参数校验**：steps=0 / steps=101 / alg 含非法 token / alg 超长 / alg 空串 → 全部 ok:false 且状态零变化（facelets 不变）。

## 8. 视觉验收（visual_test.gd，仅 N=3）

- 初始：U 白 / R 红 / F 绿三面、黑缝均匀、无 z-fighting。
- 转层中间帧（t≈0.5）：该层 45° 倾斜，其余不动。
- 播放 alg 终帧与 facelets 预期一致；MCP `restore` 验收**全自动**（v5.1）：socket 触发 → 轮询 `state` 至 `queue_len==0 && !animating` → 断言 facelets == 复原序；中间帧截图存档，不作验收门。

## 9. 实施步骤与验收（MVP 预计 3~4 小时，v5.1 含 MCP 增量）

| 步骤 | 内容 | 验收 |
|---|---|---|
| 1 | project.godot + main.tscn | headless --quit 退出码 0 |
| 2 | cube.gd setup(n) 生成贴色 | N=3 截图 6 色三面 |
| 3 | 转层队列 + 动画 + 键盘 | U 顺时针、Shift 反向 |
| 4 | 打乱/撤销/重置/判定 + full_log + UI | 三按钮 + StatusLabel 正确 |
| 5 | play_alg + to_facelets + AlgEdit | 自测 5/6 绿；界面播放可见 |
| 6 | cube_server.gd + mcp_bridge.py | 自测 10-14 绿；`python3 -m py_compile tools/mcp_bridge.py` 过；`echo '{"id":1,"cmd":"state"}' \| timeout 3 nc -N 127.0.0.1 8788` 收到 JSON（本机 OpenBSD nc 无 `-q`，用 `-N`：stdin EOF 后关连接；timeout 兜底防挂） |
| 7 | self_test §7 全绿 + visual_test | exit 0 + 截图过验收 |

## 10. 已知风险与对策

- reparent 全局变换 + §4 bake 顺序——自测 2 兜底。
- 内部块跳过条件写错 → 查块失败——自测 2/7 全集断言兜底。
- facelet 行列序错位——4 角环断言（自测 5）钉死。
- **undo 与 full_log 语义漏记**（undo 不入 log 则 restore 错乱）——自测 11 专项兜底。
- **restore 中断/双重触发**——pop 不变式（§1 决策 4）天然自愈；v5 的"快照+清空"方案已废弃（中断后 restore 永久失效的漏洞）。
- 多次合法 apply_alg 追加可积压长动画（单条 ≤300 token 已防爆炸）——MVP 接受；重置类命令可随时打断止损。
- TCP 服务无鉴权：仅 127.0.0.1，本地工具接受；若发布公网再谈鉴权（升级路径：token 参数）。
- 桥手写 MCP 握手版本兼容风险——echo protocolVersion；不兼容则换官方 SDK（§6.4）。
- 队列满丢弃无提示：MVP 接受（上限 8 ≈ 1.4s 缓冲）。
- BoxMesh 单材质 ⇒ 黑盒 + PlaneMesh。

## 11. 明确边界

- **支持**：任意 NxN 自由模式（数据层参数化完成）；MCP 外部控制（读状态/打乱/回放还原/重置/公式播放/LBL 解/教学提示/最优解/WCA 均匀打乱，后四者 v6 增量）。
- **3 阶专用面**：教学模式、计时模式、`solve`/`hint`、`cube_solve_optimal`、`cube_scramble_wca`——N≠3 时教学/计时入口禁用（灰），相关命令 ok:false。
- **不支持**：异形魔方（需"轴-深度"模型，届时重写坐标层，动画/贴纸/面判定四件套保留）；拖层宽层手势（小写宽转键位有，手势无）；竞速级计时细节（空格起表/触屏，YAGNI）。
- **调研后明确不做**：拍照识别、蓝牙硬件、AI 教练内置、在线对战（§0 依据；外部 AI 可经 MCP 驱动，恰是不内置的理由）。

## 12. 方案演进记录

- v1：3 阶初版。自审：打乱瞬时、bake 不读动画末态、orbit 只动相机、清撤销栈、队列上限、恒等式测试。
- v2：补实现细节；二轮审出 scramble/reset 与动画竞态，补 kill tween。
- v3：NxN 参数化——步长 2 整数网格、转层三元组、全参数化、N=4 冒烟；判定去中心块化；三轮收敛。
- v4：融入市场调研——定位教学软件；54 面冲突裁决（视觉即状态 + 单向导出）；play_alg；P1.5/P2 预设计；路线图四期。
- v4.1 自评修订：E1 facelet 行列序明确 6 面定义表 + 4 角环断言；E2 双入口 apply_turn/enqueue_turn；E3 undo 原子性；E4 Kociemba 字符串映射；E5 R2' 记号。
- v5：新增 MCP 外部控制——架构裁决（游戏内 TCP NDJSON + 零依赖 Python stdio 桥，否决 Godot 直接 stdio/HTTP 两案）；full_log 全量日志 + restore 逆序回放（免求解器还原，undo 也入 log、restore 入口快照清空防双重回放、回放不计步）；NDJSON 命令表 5 条 + MCP 工具表 5 个；自测 +3（分发器直测、restore 数学、socket 冒烟）；步骤表 +1。
- v5 二审修正：F1 队列上限只约束键盘入口，alg/restore 批量入队豁免（否则回放丢步状态错乱）；F2 restore 入口清空撤销栈；F3 `--cube-port` 经 `--` 分隔用户参数传入；F4 nc 验收命令加 `-q1`/timeout 防挂住。
- v5.1 三审（grilling 共识 9 项）：G1 restore 改 pop 语义（full_log 恒为"初始态→当前态"路径，中断自愈，废弃快照+清空，完成时 moves 归 0）；G2 state.facelets/solved 反映已 bake 状态（§6.2 注明）；G3 打断/追加矩阵（play_alg/apply_alg 追加不丢步；播放期忽略键盘/UndoBtn）；G4 TCP 单连接 + listen 失败降级；G5 MCP 参数校验（steps∈[1,100]、alg 边界与记号合法性，校验先于入队，UI 共用）；G6 restore 验收全自动；G7 nc `-q1`→`-N`（本机 OpenBSD nc 实测无 `-q`）；G8 工时 3~4h；G9 自测 +2（§7.4）。环境查证：Godot 4.7.2 stable 在位（~/.local/bin/godot）、EXPERIENCE.md 测试路径有效（X 会话 opengl3 截图/headless 逻辑）、仓库零代码从零建。
- v6（grilling 两轮共识 + 事实修正）：P1.5~P4 与 NxN 后置项全部补成可实施详设（§13~§18）。关键裁决：H1 教学粒度=逐块引擎（"阶段级固定公式对任意状态会转错"，引擎即 LBL 求解器，solve 白送）；H2 公式表按标准白底记法存储 + 翻转映射运行时转换；H3 拖层=命中即拖/未命中 orbit、实时预览+松手 snap（最近 90° 倍数、<15° 回弹、手势原子挡分发器）；H4 求解器分层——LBL 游戏内纯 GDScript，最优解/WCA 均匀打乱=桥侧 optional `kociemba`（min2phase 无可靠 Python 包，实测 kociemba 0.01s/次；均匀打乱=随机合法状态→solve→取逆，并代为执行）；H5 计时=首操作起表/is_solved 停表/ConfigFile 存 AO5-AO12/计时中切模式作废；H6 CFOP 数据源=lukejacksonn/cube algorithms.ts 静态打包（AlgDB/CubeDB 均已死站，实测可拉取）；H7 三态模式切换（自由/教学/计时，状态跨模式保持）；H8 教学/计时/solve/hint 限 N=3；H9 阶段侧栏+「演示下一步」「自动完成本阶段」两按钮，不锁操作、阶段可回退。矩阵补拖层两行（§4）；NDJSON +solve/hint、MCP +4 工具（§6.2/6.3）；§11 边界同步。
- v6.1（2026-09-25 体验修订，grilling 五问共识）：J1 orbit 俯仰放开至全向 ±89.9°（原 5°~85°；教学需看 D 面）；J2 加滚轮缩放（0.5~2.0× 基准 `1.7n+2.0`，步长 ×1.1，`main.gd` 顶层事件链）；J3 UI 随窗口缩放——stretch `canvas_items + expand`（原 disabled，窗口拉伸 UI 不变）；J4 按钮加大——顶栏 36→52px、按钮 min 宽统一 72px、顶栏字号 18、小字 13→14（原 56/64px 宽、16px 默认字号）；J5 抗锯齿——MSAA 4× + FXAA（原无任何 AA，魔方斜边轮廓锯齿）。实现注记：`var base := 1.7 * cube.n + 2.0` 因 `cube`（`@onready var cube = $CubeRoot`）无类型标注致 Variant 推断失败、main.gd parse error、场景实例退化为无脚本 Node3D——已改显式 `: float`；headless 回归曾被测试退出码统一判定模式掩盖（SCRIPT ERROR 中断断言但 exit 0 假绿），回归须同时校验 exit code 与日志无 SCRIPT ERROR。
- v6.3（2026-09-25 打乱修订，grilling 四问共识）：K1 症状=NxN 打乱恒只转最外层单层（`_outer_layer` 恒返 E），N≥4 内层/中心区域纹丝不动、观感"没打乱"（数学层实测 N=3~7 守恒/可逆全绿，排除坏档）；K2 层覆盖=外层/内层/宽层混合随机（内层复原靠拖层——拖层手势支持任意层，键盘维持无内层键）；K3 步数随阶对齐 WCA 官方（25/40/60/80/100，2 阶 11）；K4 调研结论=TNoodle 对 NxN 即 random-move（含宽转/内层+冗余过滤），无需外部库，实现即对齐业界。3 阶行为完全不变（金标准 T15/计时不受影响）。新增 tests/test_scramble.gd（37 断言：各阶守恒/步数/层组约束/内层参与/数学复原/显式 steps 优先）。
- v6 审计修订（双审计员并行，19 项发现全部成立）：**A1 高危——x2 映射撇号系统性错误**（x2 纯旋转 det=+1，共轭保定向，记号重写不产生撇；v6 初稿 U↔D' 会使每步方向反），改为无撇双表并钉死源教程姿态（白底蓝前红右=x2 型 U↔D/F↔B/R-L 不变；白底绿前右橙=z2 型 U↔D/R↔L/F-B 恒等），触发条件同经映射；A2 阶段表编号对齐（7=D 层棱位，完成即复原，与 solve 分段同口径）；A3 §6.4/§4/§0 陈旧 min2phase 表述清除，"自研求解器"改为"自研最优解求解器（LBL 引擎除外）"；A4 §4 末 P1.5/P2 预设计旧表述（阶段级固定公式，与 H1 矛盾）替换为指向 §13/§14；B 级——拖层 snap 改为新 finish 路径（非零量化角 PLAYER 记账）+8px 起手阈值+轴锁定细则；拖层中 Esc=回弹不退出；白十字改单层 F2+护棱分支（防自拆已归位棱）；公式表补"U 预对位"前提与三角换摆位 T15 实证；计时边角钉死（WCA 打乱走标记入口、restore/reset/切模式/二次打乱=作废、running 禁 PlayBtn、UndoBtn 不起表、成绩 key 毫秒+序号）；C 级——小写宽转校验感知 n（static 改带参）、文案方位词不经 remap、§18 补 N=4 截图与非 WCA 提示验收、§0 决策引用修正、§2.6 小写记号例外注记。
- v6.2（2026-09-25，grilling 两问裁决）：K1 轨迹球四元数相机（`_view_quat` + `_apply_orbit_delta`，dx 绕局部 up / dy 绕局部 right 世界系左乘，灵敏度沿用 0.4°/px）替代欧拉 yaw/pitch，万向无极点，代价 roll 歪斜按裁决保留不加自动水平；初始四元数经 `Basis.looking_at(-(1,1,1))` 复现原构图（visual_test 7 图不依赖改动）；K2 复位双入口 = Home 键 + 顶栏「回正」按钮（ViewResetBtn），复位 = 初始三视图姿态 + 基准距离（`_reset_view`，幂等）；自测 +1（tests/test_view.gd：初始构图/越极无 NaN/2000 次随机增量 basis 正交/复位幂等/右拖方向同旧模型）。
- v6.4（2026-09-25 调研驱动优化轮，依据 docs/open-source-comparison.md 附录 A + 三维审计两轮 + 终审，明细见 docs/design-optimization-report.md）：A-4 WCA 均匀打乱推广全模式——打乱按钮 3 阶且 kociemba 可用时优先 WCA（`tools/wca_scramble.py` 子进程生成，经 server `scramble_wca_apply` 标记入口与 MCP 同语义；降级清 WCA 标记 + full_log 差值步数如实提示，服务端信号路径步数未知时省略数字）；A-6 打乱种子化——`cube_scramble` 可选 `(seed, steps)`、`cube_scramble_wca` 可选 `seed`（`validate_seed`：数字/整数/|seed|≤2^53；桥侧非整数显式报错不静默降熵），smoke_bridge 加 `--port`（8788 被常驻实例占用时的唯一端到端验证通道）；A-5 播放速度——`turn_time` 0.05~0.90 s/步可调（clamp），顶栏滑杆即时生效，play_alg/restore 同控；A-8 训练统计简版——`train_stats.gd` 每案例 count/best/mean 持久化 `user://train_stats.cfg`，统计 key 冻结出题分类（`_train_case_cat`，切分类不清当前 case），完成入账要求 `cube.moves>0`（挡 MCP reset/代解直达复原的伪成绩），出现率与跨案例统计表按 §16.3 在先裁决 deferred；A-3 CI——GitHub Actions 跑 10 个 headless 测试 + py_compile×3 + WCA 生成器直跑 + smoke_bridge --port=18925，失败详情入 `::error` annotation（免认证可读）；数据重录——`data/cfop.json` 改由 `tools/rebuild_cfop.py` 从 speedsolving wiki 公共算法表重收集（614 条全量数学验证；f2l 用 wiki 原编号缺 37，与 lukejacksonn 的 1..41 是两套编号体系），消除上游许可依赖；许可证定稿 GPL-3.0。测试 +2（test_scramble_ui/test_train_stats），test_timer/test_server 假绿陷阱修复（`_fail` 累计制，quit(1) 不再被尾部 quit(0) 覆盖）。

## 13. P1.5 鼠标拖层

**输入裁决**：左键按下时 raycast（camera 投射到 cubie 碰撞体）——命中 → 拖层模式；未命中 → orbit（现有行为不变）。单键直觉，零学习成本。

1. **起手条件**：队列空且非播放中（拖层=键盘类，矩阵"播放期忽略"行）；命中面法线 `normal` + 命中格层坐标已知。
2. **转轴推断**：命中后拖动超过 8px 才锁定（防误触）；`dir` = 指针屏幕位移经相机基投影到命中面切平面；`axis = normal.cross(dir)` 取最近坐标轴并归一化，方向符号并入 angle；**轴一旦锁定，本次手势不中途换轴**；`layers = [命中格该轴分量]`（单层；NxN 宽层手势不做）。
3. **实时预览**：拖层期间 pivot 随指针角度实时旋转（0~±180° 连续，无 tween）；`grid_pos` 不动——facelets 查询自然返回已 bake 状态（G2 一致）。
4. **松手 snap**：角度量化到最近 90° 倍数（0/±90/180）；<15° 回弹为 0（不算步、不记日志）；15°~45°（及对称区间）系规格空洞，实现裁决：≥15° 即升到最近非零倍数（16°→90°、45°→90°），量化落在 0 不作回弹——部分拖动不给无效操作手感（2026-09-24 修复轮回写，§18 T-drag 钉死）；否则经**新 finish 路径**按量化角一次性 bake 并走与键盘完全一致的玩家步语义（撤销栈 + full_log + 计步；180° 一步一记，与 `R2` 口径一致）。回弹与 `_abort_active_turn` 的逆旋转归位同构（均为"部分角→原位"），但非零 snap 是"部分角→量化角→PLAYER 记账"的新路径，实现期新写，由 §18 T-drag 兜底。
5. **手势原子性**：`_dragging` 标志挡住 NDJSON 分发器与队列推进（矩阵已补行，§4）；**Esc 在拖层中 = 中断手势回弹归位**（不退出），非拖层时 Esc = 退出程序（现状语义不变）。
6. **验收**：snap 数学（量化/回弹/计步）headless 单测；手感人工验收；不新增视觉测试。

## 14. P2 层先法教学（逐块教学引擎）

**架构裁决**：教学粒度=「当前哪个块未归位 + 它在哪」，不是阶段级固定公式（对任意状态播固定公式会转错）。引擎=纯函数：输入 `to_facelets()`，输出 WCA 记号序列 + 分步教学元数据；**引擎本身就是 LBL 求解器**，`solve` 命令白送，零外部依赖。

### 14.1 记号映射（x2 翻转，v6 审计修订：无撇）

公式表按**标准白底教程记法**存储，本项目配色 U=白/D=黄/F=绿/B=蓝/R=红/L=橙（白在上）。x2 是纯旋转（det=+1），共轭 `g·R(n,θ)·g⁻¹ = R(g·n, θ)` 保持角度与定向，**记号重写不产生撇**（撇只出现在镜像共轭）。v6 初稿的 `U↔D'` 系数学错误，会使每步层对方向反，已废弃。

映射取决于源教程姿态，两型任选其一，实现期按实际采用资料核对并在公式表头部写明：

| 源教程姿态 | 与本项目的关系 | 记号映射（全无撇） |
|---|---|---|
| 白底、蓝前、红右（西方标准） | = 本项目经 x2 | `U↔D、D↔U、F↔B、B↔F、R→R、L→L` |
| 白底、绿前、右橙左红（国内常见） | = 本项目经 z2 | `U↔D、D↔U、F→F、B→B、R↔L、L↔R` |

`remap(alg) -> String` 按上表逐 token 替换；**公式表的触发条件（块位置/朝向描述）同样以源姿态表述，引擎判定前与公式一起经同一映射换算**。正确性由 T15 金标准兜底（§18）。

### 14.2 阶段判定（stage_check(facelets) -> 0..7，v6 审计修订：编号对齐）

0 = 无任何阶段满足（完全打乱/中途乱转）；1~7 为七个实质阶段，**7 完成即复原**：

| # | 阶段 | 判定（复用面查询） |
|---|---|---|
| 1 | 白十字 | U 面 4 棱白 + 各侧面对齐中心色 |
| 2 | U 层四角 | 白角归位（含侧色） |
| 3 | 中层四棱 | 中层棱归位 |
| 4 | D 面十字 | D 面 4 棱黄 |
| 5 | D 面全黄 | D 面 9 格黄（角朝向正确） |
| 6 | D 层角位 | 4 角位置正确（朝向已由 5 保证） |
| 7 | D 层棱位 | 4 棱归位 → 必然 is_solved |

"solved" = 阶段 7 完成，与 §6.2 `solve` 的分段（stages 1..7）口径一致。每步玩家操作后重判；阶段可回退（侧栏变红），不锁操作——转错了判定自己退回去，这正是软件比视频教程强的地方。

### 14.3 公式表（标准白底记法；触发条件=块位置/朝向）

| 阶段 | 触发条件（源姿态表述，与公式同经 §14.1 映射） | 公式 | 教学文案（中文，一句） |
|---|---|---|---|
| 白十字 | —— | **启发式逐块**（非公式，见 14.4） | 每步生成 |
| 2 一层角 | 目标角已 U 预对位至目标槽上方（另两色与相邻中心对齐），白朝右 | `R U R'` | 白色朝右，右手三步带下去 |
| | 同上，白朝前 | `F' U' F` | 白色朝前，左手三步带下去 |
| | 同上，白朝上 | `R U2 R' U' R U R'` | 白色朝天，先立起来再插 |
| | 目标角在底层错误槽/朝向 | `R U R'`（先提出来再按上面处理） | 卡错了先提回顶层 |
| 3 中层棱 | 棱在顶层且已对位（侧色对齐中心），插入右槽 | `U R U' R' U' F' U F` | 远离、开右门、合右门 |
| | 同上，插入左槽 | `U' L' U L U F U' F'` | 远离、开左门、合左门 |
| | 棱在中层错误槽 | 任一插入公式先顶出 | 错槽先顶回顶层 |
| 4 D 面十字 | 点/拐/线 → 十字 | `F R U R' U' F'`（≤3 次，拐朝左上摆位） | 黄点变黄线再变黄十字 |
| 5 D 面全黄 | 7 case（Sune 家族） | Sune `R U R' U R U2 R'`；Anti `R U2 R' U' R U' R'`；其余 5 case 用 Sune/Anti 组合 ≤2 次（case 判定给摆位指引） | 小鱼公式，摆对位置做一到两次 |
| 6 D 层角位 | 三角换（好角摆位 T15 实证：不动角 = DLF 左前；初稿 Niklas 公式 `U R U' L' U R' U' L` 实证破坏角朝向已弃用） | `L F' L B2 L' F L B2 L2`（必要时 U 调整） | 把位置正确的角放左前，其余三个转圈换 |
| 7 D 层棱位 | 三棱换 | Ua `R U' R U R U R U' R' U' R2`；Ub=Ua' | 黄面朝上，三棱顺/逆转 |

角朝向阶段 5 若用新手法 `R' D' R D` 重复技巧亦可（引擎择一实现，测试兜底）；表中共 19 条核心条目。**公式正确性以实现期金标准为准**（§18 T15），表内笔误由测试抓出而非人眼。

### 14.4 白十字启发式（~80 行，v6 审计修订：单层 F2 + 护棱分支）

对每个未归位白棱：①若在 D 层（黄面侧），转 D 对齐目标侧面后 **180° 单层**（如 `F2`）提到 U；②若在中层，单步转到 U 或 D 层——**若该单步会带走 U 层已归位的白棱，先转 U 让开、处理完再转回**（护棱分支，防自拆进度）；③若在 U 层错位，转其**所在**侧面 180° 落回 D 再走 ①（棱不在目标侧面层，转目标侧面不动——v6 原文"目标侧面"系笔误，2026-09-24 修复轮更正）；④侧色对齐后 180° 归位。每步产出 (记号, 文案) 对，教学叙事="先把白棱转到黄面旁边，对好侧面颜色，翻上来"。

### 14.5 教学侧栏 UI

- 右侧 ~220px 侧栏：7 阶段列表，当前进度实时高亮（绿=完成、蓝=当前、红=回退），每阶段一句要领文案。
- 两按钮：**演示下一步**（引擎建议 → play_alg 播放，追加语义，替你执行）；**自动完成本阶段**（循环"建议→执行"批量入队，受打断矩阵约束）。不做"回退本阶段"按钮——undo/restore 已覆盖；演示走 play_alg 不入撤销栈（v5.1 语义），要撤销演示后的整体状态用 restore/undo 玩家步。
- 教学文案的方位词（右/前/左后等）**直接按本项目朝向（U=白在顶）撰写**，不经 remap 转换——remap 只作用于公式记号与触发判定，文案是人写死的中文。
- 入口：TopBar 模式切换（§15.3）；N≠3 禁用。
- `hint` 命令/`cube_hint` 工具返回同一引擎输出（外部 AI 教练 = 循环 hint→apply_alg）。

## 15. P3 计时器

### 15.1 状态机（timer.gd，v6 审计修订：边角钉死）

`idle → scrambled → running → solved`。进入 `scrambled` 的来源=打乱按钮、`scramble` 命令、`cube_scramble_wca`（桥的代为执行走**带打乱标记的内部入口**而非裸 apply_alg，游戏侧据此识别来源）；**首次玩家操作**（键盘转层/拖层；UndoBtn 不起表——它是修正不是转层）自动起表 → running；`is_solved` 为真瞬间停表 → solved，成绩入账。以下均=当前计时作废（不记成绩）：计时中切换模式、`restore`/`reset`/再次打乱、退出程序。计时 running 中 PlayBtn 与教学按钮禁用（竞速不播公式）；undo 照常可用（玩家步语义，计时继续）。不防作弊（本地训练工具，打乱态可见性自由）。

### 15.2 数据与统计

- 存储：`ConfigFile`，`user://times.cfg`；section=日期（YYYY-MM-DD），key=时间戳毫秒+自增序号（防秒级碰撞），value=毫秒。
- 统计：AO5/AO12（去最好最差取平均）、单次最佳；侧栏历史列表。
- 打乱序列展示：计时模式打乱后显示 WCA 记号序列（桥可用→`cube_scramble_wca` 均匀序列；不可用→现有 25 步随机，StatusLabel 提示"非 WCA 均匀打乱"——该提示为 §18 验收项）。

### 15.3 模式切换

TopBar 三态单选：**自由 / 教学 / 计时**。切换即切 UI 布局（教学=右侧栏，计时=中央大字计时+侧栏历史），**魔方与状态跨模式保持**（切到计时不重置魔方）。N≠3 时教学/计时禁用（灰）。

## 16. P4 CFOP 案例训练（原则级，开工前再补 case 表）

1. **数据**：lukejacksonn/cube `src/algorithms.ts`（19KB，F2L/OLL/PLL 全量含分组）一次性抓取 → 转静态 JSON 打包 `data/cfop.json`；离线运行，README 标注来源与许可。
2. **训练交互**：随机 case（把魔方打到该 case 状态，逆向公式从复原态构造）→ 用户盲解 → 对照标准公式（「演示」= play_alg 播 AlgDB 主公式）。
3. 详细 case 表、进度统计 UI 留到 P4 开工前专项 grill，避免为最远的期过度设计。

## 17. NxN 后置三件套

1. **阶数选择**：TopBar 设置按钮 → 弹窗下拉 2~7；确认 = reset + setup(n)（现有语义，full_log/撤销/步数全清）。
2. **宽转键位**：**Alt+字母 = 双层宽转**（`u d l r f b`，layers 两值一次动画；Shift 已被反向占用）；AlgEdit 解析小写记号（NxN 生效）；**3 阶下小写=非法 token 拒绝**（记号集最小，行为可预期）。`is_valid_wca_token` 校验需感知 n（static 改为带 n 参数，小写合法性随阶数变化）。
3. **视觉冒烟**：visual_test 增 N=4 单张截图（setup(4) 三面可见，不逐项验收）。

## 18. 各期测试与验收汇总（self_test / visual_test / smoke_bridge 增量）

| 期 | 增量 | 断言要点 |
|---|---|---|
| P1.5 | T-drag（headless 单测） | snap 量化最近 90° 倍数；<15° 回弹不计步不记 log；180° 一步一记；拖层步入撤销栈/full_log |
| P2 | **T15 金标准**：随机 100 态 → `solve` → 逆序 apply → 全部 solved；LBL 解步数 < 160（2026-09-24 修复轮修订：cube.gd 负轴选层修复后 scramble 为 6 面均匀分布，实测最坏 156/seed 999983，原 <150 系偏浅分布上的经验值；100 态全复原等正确性门不变） | stage_check 对构造状态逐阶段判定正确；hint 返回建议后 apply 即该块归位；自动完成=循环演示至阶段判定通过 |
| P2 | T-MCP：`solve`/`hint` 分发器直测 | 3 阶返回结构完整；N=4 时 ok:false |
| P3 | T-timer：状态机单测 | scrambled→首操作起表（UndoBtn 不起表）→is_solved 停表；AO5/AO12 计算（含去头去尾）纯函数断言；计时中切模式/restore/reset/二次打乱=作废；running 中 PlayBtn 禁用；"非 WCA 均匀打乱"提示路径 |
| P3 | T-bridge（kociemba 装机时跑，未装跳过标记 SKIP） | 随机合法状态生成合法性（角≡0 mod3/棱≡0 mod2/置换奇偶）；solve 取逆 apply 回到该状态；代为执行走打乱标记入口 |
| P4 | 开工前补 | —— |
| NxN | T-wide：Alt 宽转 | 小写记号 3 阶拒绝、N=4 双层同转；阶数切换 reset 语义；**visual_test 增 N=4 单张冒烟截图（§17.3）** |
| P2 | T15 补充（v6 审计后） | remap 两型映射自检各 6 条（x2 型 U↔D/F↔B/R/L 不变；z2 型 U↔D/R↔L/F/B 不变，全无撇）；三角换摆位实证；白十字护棱分支（U 层已归位棱经启发式处理后仍在位） |

验收门维持 exit code 判定；`solve`/`hint`/计时逻辑全部走 headless 自测，手感类（拖层、教学模式浏览）人工验收。
