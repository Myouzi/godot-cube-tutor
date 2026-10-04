# v7 实施方案:教学功能扩展到全阶数 2-7

> 状态:已批准(2026-09-25 用户裁决"全阶数 2-7"),替代 H8 裁决中"教学限 N=3"的范围。
> 本文件是实施蓝图;PLAN.md 的契约修订(P9)随各期落地同步进行。
> 2026-09-25 经第二轮审计(四视角 workflow 审计报告 `out/v7-plan-audit-report.md` + grilling 六项裁决)修订,详见文末审计裁决第二轮。

## 目标与裁决变更

推翻 PLAN H8/§11 中"教学限 3 阶"的裁决:教学模式对 2-7 阶全开。计时/训练模式维持 3 阶(CFOP 公式表与 WCA 打乱均为 3 阶资产,不扩)。PLAN.md 新增 v7 版本条目并修订 §6.2/§11/§14 四处契约。

## 架构:三层,3 阶引擎零改动

1. **`lbl_solver.gd` 完全不动**(3 阶回归风险为零)。它继续承担:n=3 直用;4-7 阶约化后复用全部 7 阶段。(2 阶不再复用 lbl——独立解法器,见第 2 条。)
2. **新建 `scripts/nxn_solver.gd`**(静态纯函数,风格对齐 lbl_solver):n 阶 facelet 模拟器 + 分阶阶段表 + 降阶法段生成 + **2 阶独立小解法器**(初学者法 3 段,平移 `_corner_segment` 同款骨架,公式池 5-8 条)。n=3 时直接转调 lbl_solver(调用方无分派逻辑)。
3. **UI/协议解禁**:main.gd 教学按钮按模式放行、侧栏阶段标签动态化;cube_server.gd solve/hint 按 n 放行。
4. **阶段号契约**:nxn_solver.stage_check/hint 直接返回该阶压缩后段号(2 阶 0..3、3 阶 0..7、4-7 阶 0..9)并随表导出 STAGE_NAMES,UI 零过滤逻辑;nxn_solver 入口对输入长度(6n²)与契约做校验(兜底不落在 lbl_solver 上,红线不破)。

## 分期实施(每期独立提交、独立金标准验收)

### P0 记号与 facelet 底座(cube.gd)
- `to_facelets()` 泛化:`resize(6*n*n)` + `r/c in n`(当前 54 写死,是第一阻塞点;行列序沿用 FACES 表,与 §3.1 兼容)。
- `parse_alg`/`is_valid_wca_token` 支持内层记号:`nR`(3 ≤ n ≤ N-1,单内层)与 `nRw`(2 ≤ n ≤ N-1,宽层);**不加 `2R`**(≡ R 冗余,徒增与 R2 的手滑歧义面);现有小写双层语义不变(`play_steps` 已支持任意 layers,只缺 parse 层)。**同步放宽 token 长度上限**(现 `cube.gd:109-110` 的 `t.length() > 3` 会先于文法截断 4 字符的 `3Rw'`/`3Rw2`)。
- **验收 = 记号单元测试**(纯函数,零新依赖):parse_alg 输出结构断言、代数自洽(`3R·3R'` 复原、`3R`×4 复原、`nRw` 层数正确)、非法 token 拒绝、长度上限放宽生效。对拍测试随模拟器移至 P2。

### P1 2 阶教学(nxnn_solver 独立解法器,放弃嵌入)
- 原嵌入方案被审计证伪,弃用:11 步打乱角置换恒奇(数值验证 20000/20000),"棱/中心填复原色"嵌入后违反 3 阶群"角符号=棱符号"不变量(20000 次随机步序列零违反),嵌入态为无解非法态,headless 实跑金标准 0/50。
- 改为**独立初学者法小解法器**:白面四角 → 黄面 → 角块归位,3 段;平移 `_corner_segment` 骨架(模板 × 槽位旋转 × 模拟-验证),公式池 5-8 条(`R U R' U'` 刷朝向、角归位换子等);无嵌入即无奇偶/转正/逆映射问题。
- 阶段表原生导出 3 段(压缩段号 0..3,UI 零过滤);STAGE_TIPS 按 3 段撰写。
- 金标准:2 阶 scramble(步数表已有 {2:11})→ solve → 播放 → is_solved(n 通用、朝向无关),50 态。

### P2 n 阶 facelet 模拟器(nxn_solver 核心)
- cell 表由 FACES_DEF 几何 × n 生成;任意层置换:`cell.dot(axis)` 匹配层值,E=n-1;static 缓存按 n 键控(现为无键单例)。
- `_apply_token` 支持 6n² 长度 + 内层/宽层 token。
- **验收含对拍测试**(自 P0 移入):n=2..7 上 cube.gd apply_turn ↔ nxn 模拟器逐步一致(范式 `tests/test_lbl.gd:86` `_test_simulator_parity`,T15 系——原方案误引"T14",已修正);token 池按 n 扩到 {外层, nR, nRw},覆盖 parse_alg→apply_turn 链路(仿 :107-125 范式),否则内格映射错位带 bug 全绿。

### P3 中心段(降阶法第 1 步)
- 配色基准:直接以 cube.gd FACES 常量为降阶目标(删"偶数阶由角块推导"——配色是编译期常量,按位置"找白角"无解且实现会随打乱漂移);可保留"白红绿角色三元组存在且唯一"的一次性断言。
- 方法论平移现有 `_corner_segment` 骨架:候选公式模板池 × 槽位旋转(`_rotate_alg` 推广)× 摆位前缀 → 模拟-验证 → 评分(未归位中心数单调降 ∧ 已完成面保持)。
- **模板池显式纳入收尾两面(last two centers)专用公式族**(含"破坏+恢复"型,如 `U' Rw U' Rw'` 族):审计实证 70 种 L2C 布置中 39 种死锁、死锁最短路径 6-8 步,3-5 步初学者模板+前缀覆盖不了。**P3 与 P4b 同款"开工前先补论证"条款**;先按金标准采样统计 L2C 死锁占比,再定池子规模。
- 实施蓝本:GusEscanda/rubik-cube-solver 的 `methods.json`(NxN 人类方法 DSL:分段树 × 槽位旋转 × 条件匹配,与本方案同构,含偶数阶配色与 parity 公式族)——结构思路自由借鉴;**该仓库无 LICENSE,具体公式不得逐字抄**,从公共方法域(教程站/社区通用公式)收集后走 A-2 管线(收集 → 记号转译 → 引擎逆构造数学验证)重录。dwalton76/rubiks-cube-NxNxN-solver(MIT;lookup-table + IDA 机器求解,5x5 求解 90 分钟,不可平移)仅作降阶分段结构参照。GusEscanda 无 LICENSE 事实记入 PLAN 许可一节与 EXPERIENCE。
- 阶段判定:六面中心各自同色;进度 = 已归位中心块比例。

### P4 组棱段(降阶法第 2 步,拆 P4a/P4b 两步交付)
- P4a(4 阶):12 条棱各 2 wing,配对模板(如 `Rw U R' U' Rw'` 族)+ setup 构造(把两同色 wing 送入模板槽,自由度 = y 旋转 + U/D 摆位 + 内层摆位,枚举后模拟验证"配对成功 ∧ 已配对棱保持")。
- P4b(5-7 阶):**每棱 = 2 wing + (n−4) mid**(5 阶 1、6 阶 2、7 阶 3);开工前论证段先覆盖 mid-mid 配对(6/7 阶 mid 链),再覆盖 mid 与 wing 配对;不假设"内层版 wing 模板"可覆盖 mid。

### P5 约化 + parity(降阶法第 3 步)
- 中心+棱组完成 → 只转外层 → 提取 3 阶 54 态(角直接对应、外层 wing 为棱、已解中心为参考)→ lbl_solver.solve。
- parity(仅偶数阶 4/6),**双判据各自检测、各插对应修正段**:
  - OLL parity:棱朝向和 mod 2(单棱翻在排列层完全不可见——原"角/棱排列奇偶"判据被审计证伪,只能抓 PLL);
  - PLL parity:角/棱置换符号比对;
  - "循环 ≤2"对应两类并存的情形;奇数阶无 parity。
- **parity 预判下沉为 nxn_solver.hint 在 LBL 边界的可建议段**(带阶段名/文案)——solve 与 hint/自动完成两条路径都要有注入点;否则教学交互遇 parity 态空建议,`main.gd:820-823` 自动中止,违反验收口径。
- **stages 契约(定死)**:parity 修正公式并入"十二条棱组"段尾,9 段定长不变(段语义 = 组棱完成含 parity 清理;OLL/PLL 公式本身保持中心+棱组,段尾状态断言不受影响,stages 拼接 ≡ alg 保持)。金标准 stage 单调与 S3 断言按此契约落笔。
- guard 参数化范围**显式限定为 nxn_solver 自有的中心/组棱段 guard 与熔断基线**;lbl_solver 的 MOVE_LIMIT=170 与阶段 guard 80 保持原值(经 lbl 的输入恒为 54 态、与 n 无关,作约化后 3 阶段既有保险丝)。bootstrap 顺序:先宽松 nxn guard(约 3× 初值)跑各阶金标准采集分布 → 收紧至实测最坏 + 20% → 复跑全绿;收紧后超限 = fail loud(solve 返回带原因的 error,不静默)。
- 修正公式保持中心+棱组由金标准兜底;P8 parity 构造态的构造法见 P8。

### P6 UI 适配(main.gd + main.tscn)
- **教学管线改挂 nxn_solver**(清单显式增列,五处调用点:`_lbl_solver` 加载目标 / `_teach_stage` / `_teach_hint` / `_teach_refresh` / STAGE_NAMES 读取;n=3 由 nxn_solver 内部转调 lbl_solver)。不挂则 n=2 给 24 字节、n≥4 给 6n² 字节喂 54 格引擎——侧栏幻影阶段、SCRIPT ERROR、3 阶公式播到高阶上。
- Stage0~6 七个静态 Label → 空容器 + 切阶时动态生成;`for i in 7`/`sc >= 7` 哨兵(3 处)/`STAGE_TIPS[mini(sc,6)]` 全部改为引擎导出的阶段表长度。
- STAGE_TIPS 按 n 分表;Title 按 n 切"层先法/降阶法";阶段列表外包 ScrollContainer(9 阶段防溢出)。
- **长段演示粒度(裁决)**:setup 前缀与主体宏分两个播放单元(play_alg 拆两次,段内有间歇);段生成器为复合公式输出分段 text(如"先把两块送到顶层 → 配对 → 归位");不做播放中自由中断。
- **失败语义**:nxn_solver.hint 结果增加 reason/降级标记字段(现 lbl hint 失败只回 suggestion:{} 无原因);失败与降级文案以侧栏 HintLabel 为持久载体,状态栏 flash 作补充。
- `can3` 门槛改为按模式:TEACH 全开,TIMER/TRAIN 维持 3 阶;`_on_size_selected` 补"重建阶段标签"钩子。

### P7 协议解禁(cube_server.gd)
- solve/hint 删 `n != 3` 拒绝,改调 nxn_solver;state 的 facelets 长度契约 54 → 6n²(检查 mcp_bridge.py/smoke_bridge.py 长度断言)。
- **S3 断言翻转随本期同一提交**(`tests/test_server.gd:124-132` 的 N=4 solve/hint ok:false 断言,删门后当轮必红——原排 P8 属分期矛盾);翻转后 S3 改用 seed+scramble 打乱态断言 solve ok:true + 9 段 + hint 结构(现复原态直 solve 对打乱态零覆盖)。
- mcp_bridge.py 三工具 description 的"54 字符/×7 段/3 阶专用"过期文案随 6n²/9 段/全阶数同步。

### P8 测试兜底
- 各阶金标准(固定种子、solve→播放→is_solved→stage 单调(按 P5 stages 契约逐段回放)→逆向,全链路同 3 阶口径):2 阶 50 态、4 阶 30 态、5-7 阶各 15 态——**态数为占位初值,先实测各阶单态 solve 耗时再定**。
- parity 构造态专项(4 阶单棱翻):**构造 = OLL parity 修正公式作用于复原 4 阶**(逆构造源态,顺带验证公式自身保持中心+棱组);P5 判据合入后可写。**4 阶 E2E 固定种子显式选含 parity 的态**(防固定种子恰好避开 parity 使缺陷漏网)。
- test_server S3 翻转随 P7(见上);CI 清单与 README 同步。
- UI E2E 一条:仅 4 阶教学全流程(选阶 → 打乱 → 教学 hint/演示/自动完成至复原);**等待用 animating/队列清零的长轮询**(范式 `visual_test.gd:147`,300 次 × 0.1s;4 阶自动完成 100+ 步 × 0.18s ≈ 20-40s,EXPERIENCE.md:18 的 60 帧边沿轮询口径不适用),时长计入 CI 预算。
- **CI 预算定数**:现状基线实测 ≈0.7 min(GitHub Actions API,最近成功 run 44/34/38/44/44s),2 倍预算 ≈1.4 min——比直觉紧,态数与段级缓存(风险 2)按此预算调。

### P9 文档
- PLAN.md:v7 版本条目、H8/§11/§6.2/§14 契约修订;EXPERIENCE.md 回填新坑(如 to_facelets 泛化、2 阶奇偶陷阱——"棱/中心填复原色"嵌入非法的群论原因,防将来复发)。

## 关键风险

1. P3/P4 模板池:存在性风险已由开源印证消除(GusEscanda `methods.json` 同构 DSL 跑通 NxN 全程),剩余为移植风险(记号转译、GDScript 重写、金标准调普)+ **L2C 死锁构型(39/70)需专用公式族覆盖** → **熔断条款**:P3/P4a/P4b 各设时限(2 个工作日)与金标准通过率门槛,超限即降级该段为"阶段高亮 + 自由练习"(步进演示只承诺已验证段),后续补齐模板即可恢复。**降级期间的分层验收**:P8 E2E 与验收口径随降级分层(降级段断言"高亮正确 + 已验证段可演示"),模板补齐后恢复全链路门——降级不是"纯减法",全链路口径在模板补齐前不成立。
2. 高阶段计算量(每步模拟 × 候选)→ GDScript 数组操作已是现有引擎模式,n≤7 规模可控,实测后必要时加段级缓存(以 CI 预算 ≈1.4 min 为触发参照)。
3. E2E 时序:边沿断言用轮询纪律(EXPERIENCE.md:18),长动画等待用队列清零长轮询(visual_test.gd:147 范式),防 CI flaky。

## 验收口径

教学模式下 2-7 阶任意打乱态:侧栏阶段正确高亮、"演示下一步/自动完成本阶段"全程可走通至复原(**已验证段**;熔断降级段按分层口径)、各阶金标准 CI 全绿(exit code + 无 SCRIPT ERROR 双校验)。

## 审计裁决

### 第一轮(grilling,2026-09-25,Q1-Q7 全部闭环)
- Q1 模板池:GusEscanda/Dwalton 蓝本 + A-2 重录管线 + 熔断降级(融入 P3、风险 1);"3 阶 160 组验证"证据链(检索 ≠ 搜索)不再作为依据。
- Q2 组棱:P4 拆 P4a(4 阶 wing)/P4b(5-7 阶含 mid 块论证),修正"3 wing"术语错误。
- Q3 parity:卡住检测 → 奇偶预判(后被第二轮审计修正为双判据,见下)。
- Q4 记号:砍 `2R`,只加 `nR`/`nRw`;对拍测试扩至 2-7 全阶。
- Q5 验收:P8 增 4 阶教学全流程 UI E2E 一条。
- Q6 guard:bootstrap 顺序(宽松采集 → 收紧复跑)+ fail loud。
- Q7 失败语义:状态栏提示原因,侧栏高亮照常(后被第二轮细化为 reason 字段 + HintLabel 载体)。
- 事实核对:方案全部代码现状声明与仓库一致;阶数菜单与 scramble 已 2-7 阶就绪(main.gd:288、cube.gd:202),P1 金标准无基建缺口。

### 第二轮(workflow 四视角审计 + grilling,2026-09-25)
- 审计:4 视角(架构协议/魔方方法论/测试验收/教学体验)× 独立复核,23 条发现、22 confirmed(复核含 python 数值验证与 Godot headless 实跑 0/50 复现)、1 refuted(parity 构造态"落不了地"——修正公式可自构造);关键数学经主代理独立复验(2 阶 11 步恒奇 20000/20000、3 阶不变量零违反、行号抽查属实)。报告:`out/v7-plan-audit-report.md`。
- 必改 1(P1 嵌入态非法)→ 裁决 **(b) 放弃嵌入**,2 阶独立初学者法小解法器(3 段、公式池 5-8 条,Q6a);转正/伪棱配套作废,金标准维持 {2:11}×50 态。
- 必改 2(P5 parity 判据漏 OLL)→ **双判据**(OLL 棱朝向和 mod 2 / PLL 置换符号)+ hint 路径注入;parity 段并入组棱段尾、9 段定长(**Q3i**)。
- 必改 3(分期矛盾)→ 对拍随模拟器移 P2、P0 验收改记号单元测试(**Q4a**);S3 翻转随 P7 同一提交。
- 🟡 8 条 + ⚪ 4 条 + refuted 保留句全部按报告修正方向落地(**Q5**);长段演示粒度裁决 **full**:setup/主体分播放单元 + 分段 text(**Q2**)。
- 引用修正:P0"T14" → `test_lbl.gd:86` `_test_simulator_parity`(T15 系)。
