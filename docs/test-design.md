# Cube Tutor 测试任务设计（v7 交付后）

日期：2026-10-04。范围：代码逻辑层（headless，入 CI）+ 视觉检查层（本地 X 会话，不入 CI）。
原则：**只补缺口，不重写已有 17 个套件**；全部沿用现有基建（SceneTree 脚本 + `_check` + `out/` 截图 + sticker_probe/probe_pixels）。

> **2026-10-04 grilling 裁决已全部实施**：A1（落地为 test_server S9，非原设想"搭金标准车"）、A2、A4（self_test T16）、B1、B2 均已落地，17 套件无新增文件，CI 清单无需改；全量回归 19/19 绿（见 §5 实测与 out/regression_report.md）。各节内标注落地细节。

---

## 0. 判定铁律（沿用 EXPERIENCE.md，所有任务生效）

1. **双校验**：exit code 为 0 **且** 日志无 `SCRIPT ERROR`（`grep -c "SCRIPT ERROR"`）。只看退出码会假绿。
2. **轮询等条件，不固定帧数**：等 `_process` 边沿的断言一律轮询至上限（60 帧或 300×0.1s）；否定性断言给 ≥10 帧观察窗。
3. **视觉裁决确定性优先**（用户既有裁决）：AI/多模态读 3D 透视截图**不作验收门**，只作存档辅助。验收门 = 结构断言（节点树/facelets/段数）+ 像素探针（sticker_probe + probe_pixels）。
4. 长轮询 E2E 口径沿用 test_teach_nxn_e2e：队列清零 + `!animating` 才断言。

---

## 1. 现状盘点（已覆盖，作为回归基线）

| 套件 | 覆盖 |
|---|---|
| self_test / test_drag / test_wide / test_view | cube 核心、拖层吸附、宽转、视角 |
| test_scramble / test_scramble_ui | 打乱口径（WCA 优先/降级提示） |
| test_lbl / test_nxn_{notation,sim,2x2,centers,edges,reduce} | 3 阶 LBL + v7 全阶引擎六件套 |
| test_server | MCP 协议：3 阶 solve 7 段 + **4 阶** solve/hint 9 段 + wca_apply；A1 落地后 S9 加 **2/5/6/7 阶**协议断言（2026-10-04） |
| test_teach_nxn_e2e | 4 阶教学全流程 E2E（打乱→hint→自动完成→复原，parity 路径） |
| test_timer / test_train_stats | 计时作废口径 / 训练统计持久化 |
| smoke_bridge / py_compile / wca_scramble | Python 侧三件 |
| 金标准 | 2-7 阶打乱态全量求解实测 83.4s ≤ 84s 预算（实测出处：2026-10-04 v7 P8 定稿，commit 554669e 提交记录载明「金标准态数实测定稿全量 83.4s≤84s 预算」；headless 全量实跑，态数为实测收敛值。注意 A1 最终未挂此循环，协议断言独立落在 test_server S9，见 §2） |
| visual_test.gd | **仅 N=3 全套**（7 截图+断言）+ N=4 一张冒烟 |

**缺口结论**：逻辑层密度已高，缺口集中在（a）协议口径两端阶采样、（b）模式门禁断言、（c）v7 多阶 UI 的视觉验证（主要增量）。

---

## 2. 任务清单 A — 代码逻辑层（headless，入 CI）

### A1. 全阶 2/5/6/7 协议结构断言（优先级：高）— **已实施：tests/test_server.gd S9（2026-10-04）**
- **被测**：`cube_server.gd` v7 P7 解禁后的 solve/hint 协议。现只有 n=3（7 段）与 n=4（9 段）。
- **落地形态**：tests/test_server.gd `_test_nxn_protocol_all()`（tests/test_server.gd:179）+ 新增类常量 `S9_DEGRADE_MARK="(降级)"`（tests/test_server.gd:19）。n=2/5/6/7 四点采样（3/4 阶由既有 S1/S3 覆盖，未动）：每阶按 intent 依次试 seed 20261004+n / +100 / +200——第一个 solve ok:true 的 seed 断言完整结构（alg 非空、stages 恰 9 段（n=2 为 3 段）、每段 {name,alg}）后 break；ok:false 的 seed 断言 error 含降级标记，并以 PASS 行打印完整降级原因（fail loud；非降级失败如「parity 修正循环…仍存在(fail loud)」scripts/nxn_solver.gd:3079、「约化 3 阶段: …」scripts/nxn_solver.gd:3084 不含该标记，照旧 FAIL 不被掩饰）。hint 断言（ok:true、stage∈0..9、progress、suggestion 三键、error 空时 alg 非空/非空时 PASS 降级行）固定在第一个 seed 的状态上（重 setup+scramble 对齐）；尾部 `_cube.setup(3)` 清理。scripts/ 零改动。
- **F5 裁决依据**（为何不是"两端采样 n=2/n=7 + 5/6 同构假设"）：PARITY_ALGS[6] 与 5 阶奇数阶口径此前**无任何 server 级断言**，"两端同构"不成立——6 阶偶数阶 parity 路径与 5/7 阶奇数阶口径各有独立分支，必须实点覆盖。也未按原设想搭金标准车：金标准循环是 84s 预算的耗时大头，且其 seed 不可控；协议断言落 test_server 可控 seed 独立采样，与求解循环解耦。实测注记：5-7 阶打乱态 solve 全部走降级熔断（9 seed 无一全解，2026-10-04 探针实测），降级分支是主路径而非兜底；5-7 阶打乱态 hint 的 error 为空（`_cn_hint` 首宏可生成，scripts/nxn_solver.gd:2212 起只在段生成为空时才带 error），S9 hint 空分支被真实覆盖。
- **验证**：`godot --headless -s tests/test_server.gd` → exit 0、111 条 PASS、日志无 FAIL/SCRIPT ERROR、末行 ALL PASSED，墙钟 9.510s（2026-10-04 实测）。
- **2026-10-05 修订**：S9 改单 solve 经济口径（n≥5 首 seed 降级即停 `degraded_stop`，不再烧后续 seed 的秒级 solve dispatch）——中心段预对齐 + focus 单调化入引擎后（commit 8ee627c）失败路径含爬坡+逃逸链，多 seed 采样测试成本过高；宏族扩充落地、降级率回落后恢复多 seed。瘦身后实测 9.3s，17 套件全绿回基线。

### A2. 模式门禁断言（优先级：高，10 分钟）
- **被测**：`main.gd:301` `mode_btns[m].disabled = (m==TIMER or m==TRAIN) and cube.n != 3`——现无任何测试。
- **任务**：setup(4) 后断言 TIMER/TRAIN 按钮 `disabled==true` 且 TEACH/FREE 可用；切回 3 阶断言恢复 `false`。
- **落点**：`tests/test_teach_nxn_e2e.gd` 追加（已实例化 main，零新增脚手架）。
- **已实施**（2026-10-04）：tests/test_teach_nxn_e2e.gd 追加 4 阶 `mode_btns[2]/[3]` disabled 且 `[0]/[1]` 可用断言（:67-69）+ 切回 3 阶恢复断言（:145），既有流程零改动。

### A3. 回归门（已有，列为固定门，不扩）
- 17 套件全绿（双校验）+ 金标准 83.4s ≤ 84s + smoke_bridge `--port=18925`。
- CI（`.github/workflows/ci.yml`）已在跑，A1/A2 完成后同步 CI 清单。**2026-10-04 确认：A1/A2/A4 全部落在清单内既有套件文件（test_server / test_teach_nxn_e2e / self_test），无新套件文件，CI 清单无需改。**

---

## 3. 任务清单 B — 视觉检查层（本地 `DISPLAY=:0` opengl3，不入 CI）

### B1. visual_test.gd v7 增量扩展（核心交付，优先级：高）
在现有 N=3 流程后追加（沿用 `_save_shot`/`_check`），全部截图出 `out/`：

1. **B1.1 全阶冒烟**：setup(2/5/6/7) 各一张（n4 已有）。每阶断言：cubie 数（8/98/152/218）、`to_facelets()` 复原序、`is_solved()`；截图存档人审三面可见、无穿模。
2. **B1.2 教学侧栏按阶重建**：N=2 进 TEACH → 断言 `_teach_stage_labels.size()==3` + TeachPanel.visible，截图；N=4 → `size()==9`（含 parity 项），截图（9 段是 ScrollContainer 最长列表，兼验滚动布局）。N=3 已有 shot_teach。
3. **B1.3 宽转中间帧**：4 阶 `enqueue_turn` R 轴两层、中途断言 `moved==32 and still==24`（对称于 N=3 的 8/18 断言），截图验证双层倾斜。
4. **B1.4 内层中间帧**：4 阶单内层（`3R` 口径的层），中途断言 `moved==16`，截图。可与 B1.3 同流程两段。
5. **B1.5 hint 失败/降级持久显示（必须覆盖）**：v7 P6 熔断条款的用户可见面。可确定性构造就真实构造（构造路径由事实调查定位）；不可构造则重构出最小可注入点（如临时替换 `_teach_hint` 依赖的求解入口）再测。断言 HintLabel 文本含失败原因 + 截图；降级显示（parity 提示）一并覆盖。
- **预算**：实施 ~1-1.5 小时（含时序调试）；单轮运行 ~3-5 分钟。
- **已实施**（2026-10-04）：tests/visual_test.gd 在 shot_n4 段之后、末尾 `main._on_size_selected(3)` 与清理之前纯插入（git diff --stat：118 insertions(+), 0 deletions(-)，既有 N=3 套件与断言零改动），五项全落地：
  - **B1.1**（visual_test.gd:204）：n=2/5/6/7 依次 `_on_size_selected(n)` → 4 帧重建稳 → 断言 cube.n、cubies.size()（8/98/152/218 = n³−(n−2)³）、`to_facelets()` 复原序（6n² 字节）、`is_solved()` → shot_n2/n5/n6/n7.png。
  - **B1.2**（:220）：n=2 断言 `_teach_stage_labels.size()==3` + TeachPanel visible → shot_teach_n2.png；n=4 `size()==9` → shot_teach_n4.png。
  - **B1.3/B1.4**（:235/:267）：4 阶宽转 [1,3]/内层 [1] 中间帧，time_scale=0.1 + 逐帧扫描捕获（全动画期 moved 恒定，非时序敏感）；期望值按探针实测定稿 **28/28 与 12/44**——原推 32/24、16/40 基于"每层 16 块"，被证伪：4 阶 setup 跳过 (±1,±1,±1) 8 个纯内部块（scripts/cube.gd:82-83，4³−2³=56），x=1 层仅 12 可见。FAIL 消息内嵌实测 moved/still 备 flake 排障。
  - **B1.5**（:295 起）：hint 降级持久显示——seed 4002 scramble(20) + 循环执行引擎建议至 `_teach_hint()` 返回非空 error（实测 13 步命中**组棱段**降级）→ TEACH 模式断言 error 非空且 `main.teach_hint.text` 含 ⚠（scripts/main.gd:747 口径）→ shot_hint_degrade.png。构造前提修正：裸打乱+循建议 **0 例中心段降级**（x2 共轭修复后中心段总能找到宏，CENTER_TABLE 空 scripts/nxn_solver.gd:629 仅在四层搜索穷尽后查询），实测可达降级在组棱段（`_edge_hint` 穷尽返回 error，scripts/nxn_solver.gd:1660-1661，seed 20 例中 6 例命中）——截图为真实降级态。

### B2. 像素探针 N=4 扩展（优先级：中，可选）
- `sticker_probe.gd` + `probe_pixels.py` 现仅 N=3。扩一档 N=4：投影坐标 + albedo 比对，确定性裁决多阶渲染（贴纸色、无错位）。渲染相关改动（材质/MSAA/投影）后必跑。
- **预算**：~30 分钟（探针脚本是全参数化的则近零改动，先确认再动）。
- **已实施**（2026-10-04）：tests/sticker_probe.gd 新增 `_parse_n()`（:17，`OS.get_cmdline_user_args()` 解析 `--n=N`，缺省 3，范围 2..7 否则 FAIL exit 1）。n=3 缺省路径逐行保留；n≥4 走游戏切阶入口 `main._on_size_selected(n)`（相机距离 1.7n+2 同步，scripts/main.gd:328——裸 `cube.setup(n)` 相机不拉远会致贴纸越界失配）、单步 `enqueue_turn(Vector3.RIGHT,[cube.E],-PI/2)`（选层 `cube.E=n-1` 泛化，与外层 layers=[n-1] 同口径 scripts/cube.gd:175），写 out/sticker_probe_n{n}.json + 延帧 4 自截图 out/sticker_probe_n{n}.png。tools/probe_pixels.py 加 `--n`（缺省 3）分派读取产物，打印按 6n² 总贴纸口径，退出码由 rate≥0.95 收紧为**全匹配才 0**（打印 MATCH 100%）。实测：n=3 链路 27/27、n=4 链路 48/48 全匹配 MATCH 100%，两链路各重跑一轮均稳定（2026-10-04，`env DISPLAY=:0 godot --rendering-driver opengl3`）。

### B3. 截图人审清单（每轮发版前，~10 分钟）
对 `out/` 全部截图按固定 checklist 过一遍：
- 三面可见、六色正确、贴纸数守恒只按全 6n² 口径（可见三面分布必然不均，勿套"每色恒 9"）；
- 无 z-fighting/白噪点/穿模三角；
- 教学侧栏：段数与阶匹配、当前段高亮、文字不溢出、9 段滚动可用的视觉证据；
- 计时大字/历史面板布局不遮挡魔方。
注意：人审结论记录为"存档意见"，与像素探针冲突时以探针为准（既有裁决）。

**B3 执行记录（2026-10-04，AI 读图存档意见，16/16 PASS，非验收门）**：三面可见、六色正确、无 z-fighting/白噪点/穿模（含 5/6/7 阶高密度网格）；段数与阶匹配（2 阶 3 段/3 阶 7 段/4 阶 9 段，当前段蓝▶、回退段红↩、已完成绿✓）；9 段列表无溢出；4-7 阶计时/训练按钮置灰与门禁断言互证；计时大字不遮挡魔方。存档观察一条：shot_hint_degrade 实际触发的是**组棱段**降级（卡点 10/12 对）而非任务书预期的中心段降级——"降级 error 持久显示"验收语义不变，且补得组棱降级视觉样本。**中心段样本已补拍（同日 B1.5b）**：探针实证中心降级可达性——n=4 不可达（`_remap_x2` 共轭修复，0/90）；5-7 阶 solve 降级是 guard 预算口径（段生成器不穷尽）；**N=5 seed 20261009 跟随 hint 建议 19 步确定性撞 `_cn_segment` 穷尽**（卡点态 1612319060），visual_test 增 B1.5b 段出 `shot_hint_degrade_center.png`（9 段侧栏「1.▶中心」+ ⚠ 持久显示，截图人审过）；N=6/7 深走 80 步不降级。

### B4. 明确跳过项
- **全屏像素基线 diff（pixelmatch 基线库）**：跳过。理由：Godot 跨 GPU/驱动渲染不稳定，全屏 diff 只能测"没变"不能测"对"，假红率高；渲染争议的正道是 B2 像素探针（逐贴纸语义比对）。**3D 视口不入基线（GPU 差异）；2D 面板基线在有 UI 密集改版需求时再建**（裁决 2026-10-04：保留口子，不写"永不"）。
- **多模态模型自动审图作验收门**：跳过（既有裁决：三次读数互相矛盾）。
- **5/6 阶教学侧栏截图**：跳过，9 段列表最长形态已由 N=4 覆盖，5/6/7 同构。

---

## 4. 执行矩阵（裁决 2026-10-04：触发器挂在改动类型上，取消"发版"节点）

| 改动类型 | 跑什么 |
|---|---|
| 任何 push/PR（CI） | A3 全量 headless + smoke_bridge（CI 已有，本地不重复） |
| 改协议/solver | A1 口径 + 受影响套件本地先跑 |
| 改 UI/教学管线 | B1 全量（本地 X 会话），**当场**人审当轮截图（B3 清单） |
| 改渲染（材质/AA/相机） | B1 + B2 |

本地 A3 全量与 CI 重复，日常只跑受影响套件；"每次提交前全量"与"发版前人审"两个虚构时机已删。

## 5. 总预算

**实施节奏（裁决 2026-10-04）：一次全部做完，单 commit。**
A1 ~20 分钟、A2 ~10 分钟、B1 ~1-1.5 小时、B2 ~30 分钟、B3 截图产出后人审 ~10 分钟。合计 ~2-2.5 小时。

**实测（2026-10-04，已实施后全量回归）**：headless 17 套件 + python 2 项共 **19/19 PASS**，总墙钟 ~86.3s，逐项耗时与备注见 **out/regression_report.md**（test_server 含 S9 后单套件 9.3s 报告口径 / 9.5s 实施自跑口径，均 ≤ 预算）。视觉层 B1（`env DISPLAY=:0 godot --rendering-driver opengl3 -s tests/visual_test.gd`，ALL PASSED）与 B2 探针双链路 MATCH 100% 为本地 X 会话项，不入 CI。
