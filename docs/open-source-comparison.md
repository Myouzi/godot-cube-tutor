# Cube Tutor 与开源魔方项目功能对比调研

- 调研日期:2026-09-25(同日按独立审读意见修订定稿)
- **现状提示(2026-09-25 实施轮后)**:本报告为调研时点快照,附录 A 行动项的当前交付状态以文末「交付状态盘点」小节为准;正文中的项目现状描述(如 d15 测试/CI、G8 无 `.github`、G1 打乱覆盖范围、9.1 行数快照)在实施轮后已部分过时,详见 `docs/design-optimization-report.md`。
- 调研对象:Cube Tutor(本项目)× 8 个开源魔方项目(cstimer、cubic、lukejacksonn/cube、hkociemba、min2phase、tnoodle、cubing.js、taylorjg/rubiks-cube)
- 材料来源:8 个项目的单轮调研画像(源码静态阅读为主,部分含实测),及对本项目工作区的现场核实(清单见第 9 章)

---

## 1. 结论摘要(TL;DR)

**Cube Tutor 在「Godot 桌面 3D 魔方教学 + 2~7 阶全参数化 + MCP 外部控制」这一定位上,开源生态中没有直接等价的竞品;但其打乱算法与求解能力与专业项目存在明显差距,且自身许可证状态是当前最大的法律风险。**

核心结论:

1. **差异化能力(成色分级,详见第 5 章逐项验证)**:MCP 协议外部控制是 9 个项目中唯一的(U1);2~7 阶通用的 3D 表面 raycast 直接拖层(锁轴/实时预览/snap 量化)是独有的功能**组合**,但「鼠标拖层」单点机制不独有(U2);LBL 分步教学**不独一份**(cubic 有竞争者)但质量与验证占优(U3);四模式一体的桌面教学工具形态在 9 项目及 Godot 生态内无对应物(U4)。
2. **最大差距**:随机状态打乱(cstimer/tnoodle/cubing.js 的 3x3 ≤21 步、2x2 最优、4x4 WCA 随机状态;Cube Tutor 默认路径为固定步数随机步)与高性能两阶段求解器(min2phase 自述平均 0.685ms 出 ≤21 步解;Cube Tutor 自研 LBL ≤170 步且为教学导向)。⚠ 上游性能数字均引自各项目 README/Benchmark 自述,本报告未复现(见 9.2)。
3. **LBL 教学引擎并非独一份**:andrew-wilkes/cubic(Godot 4,MIT)有带解说与自动镜头的层先法教学,但仅 3 阶、固定配色、无测试、覆盖未验证且 2024-04 停更;Cube Tutor 的引擎有模拟-验证-采用回环与 100 随机态金标准测试,质量占优。
4. **许可风险最高优先级**:本项目无 LICENSE 文件(本次现场核实);`data/cfop.json` 数据上游 lukejacksonn/cube 无 LICENSE 文件(其 README 有『MIT』文字声明,GitHub 未识别;本项目 README.md:72 按「未附任何开源许可」从严处理);GPL 系项目(cstimer/hkociemba/min2phase/cubing.js/tnoodle)的代码不可直接并入。
5. **替代评估总判断**:LBL 教学引擎、3D 模拟核心、计时器、打乱器均**保留自研**;随机状态打乱与最优解走「MCP 外控调可选 kociemba 包」路径且安装指引已存在(README.md:43-47);CFOP 数据保留但需补上游许可确认。行动项汇总见附录 A。

---

## 2. 对比项目总览表

| 项目 | 定位 | 技术栈 | 规模 / 活跃度¹ | 平台 / 分发 | 许可证 |
|---|---|---|---|---|---|
| **Cube Tutor(本项目)** | 桌面 3D 魔方教学工具(2~7 阶 + LBL 教学 + 计时 + CFOP 训练 + MCP 外控) | Godot 4.7 / GDScript + Python 桥 | 约 5400 行全量(本次实测 15 个 .gd 4703 行 + 3 个 .py 697 行,清单见 9.1);本地工作区,非 git 仓库,无对外发布地址² | 桌面(Godot 4.7,project.godot:15;未配置 export_presets.cfg,本次核实) | **无(缺失)** |
| [cstimer](https://github.com/cs0x7f/cstimer) | 专业速拧计时/训练 Web 应用(cstimer.net) | JavaScript 单页应用 + PHP 服务端 | src 约 7.07 万行 JS(画像口径,不含 jQuery);776 星;push 2026-09-07,活跃 | Web / PWA 离线安装 | GPL-3.0(根 LICENSE 完整 GPLv3 全文 + npm 声明;本次 raw 核验 cs0x7f/cstimer/master/LICENSE 首两行为 GNU GPL v3) |
| [cubic](https://github.com/andrew-wilkes/cubic) | 3x3 层先法教学模拟器 | GDScript(Godot 4.2) | 8 脚本约 1500 行(画像);22 星;push 2024-04-18,停更 | 桌面(itch.io 发行) | MIT(根 LICENSE,© 2023 Andrew Wilkes) |
| [lukejacksonn/cube](https://github.com/lukejacksonn/cube) | CFOP F2L/OLL/PLL 案例演示 PWA(本项目 cfop.json 数据源) | TypeScript/Preact + three.js(Google Cuber) | 自有代码 4 文件 + vendored cuber.cjs 284KB(画像);16 星;push 2024-01-30,停更 | Web PWA(在线部署 cube.lukejacksonn.com) | **无 LICENSE 文件**;README 文字声明 MIT;GitHub API license=null |
| [hkociemba](https://github.com/hkociemba/RubiksCube-TwophaseSolver) | 两阶段算法官方参考实现 / 求解服务 | Python(纯标准库+可选 OpenCV) | 26 个 py 约 250KB(画像);PyPI RubikTwoPhase v1.1.1;758 星;push 2026-07-19,活跃 | 跨平台桌面 / PyPI 库 / TCP 服务 | GPL-3.0(根 LICENSE + setup.cfg) |
| [min2phase](https://github.com/cs0x7f/min2phase) | Kociemba 两阶段求解器高度优化 Java 库 | Java(核心约 2800 行,画像) | 340 星;push 2023-02-21,不活跃但稳定 | 跨平台 Java 库 / 可运行 jar | GPLv3 + MIT 双许可(README:106/123 两节全文,任选其一) |
| [tnoodle](https://github.com/thewca/tnoodle) | WCA 唯一官方打乱程序 | Kotlin/ktor + React + Java | 474 星(画像);push 2026-03-30,活跃 | 桌面 JAR(默认端口 2014,系统托盘)+ GCE 云端部署 | AGPL-3.0(根 LICENSE,本次 raw 核验首两行为 AGPLv3;打乱核心 lib-scrambles 为 Maven 引入的**独立仓库** [thewca/tnoodle-lib](https://github.com/thewca/tnoodle-lib),其 LICENSE 为 GPL-3.0,本次 raw 核验;主仓库内无该目录) |
| [cubing.js](https://github.com/cubing/cubing.js) | 魔方生态基础库(alg/打乱/求解/3D/蓝牙) | TypeScript monorepo + WASM | npm cubing@0.63.7(画像);360 星;push 2026-09-24,非常活跃 | npm 库 / Web Component / CLI | GPL-3.0 与 MPL-2.0 双许可(根 LICENSE-GPL.md v3 + LICENSE-MPL.md v2.0) |
| [taylorjg/rubiks-cube](https://github.com/taylorjg/rubiks-cube) | 自动打乱-自动求解观赏演示 Web 应用 | three.js + React 19 + Vite | 约 20 文件核心约 1500 行(画像);29 星;push 2026-09-21,活跃 | Web(GitHub Pages 自动部署) | MIT(根 LICENSE.md) |

> ¹ 行数口径随画像自述而异(cstimer 仅计 src/、Cube Tutor 为全量、cstimer 之外多为核心代码),仅作数量级参照,不可逐行对比。活跃度阈值:最近 push 距调研时点(2026-09)超过 6 个月记「停更/不活跃」;「星数/推送日期」为画像调研时点的 GitHub API 快照。
> ² Cube Tutor 当前为本地工作区:本次核实无 `.git` 目录(非 git 仓库)、无对外发布仓库与 itch.io 等发行页,是全表唯一无法跳转验证的行;其行数与文件清单经本次现场核实(9.1)。
> 平台/分发维度由总览表承载,不进入 15 域功能矩阵(调研画像不含该域)。

注:8 个对比项目均有明确许可或双许可,唯 lukejacksonn/cube 仅有 README 文字声明而无 LICENSE 文件——恰为本项目 CFOP 数据上游。

---

## 3. 功能矩阵(15 功能域 × 9 项目)

记号:●=有,◐=部分,○=无,✕=README 明确不做。判定依据为 8 份调研画像的 d1~d15 条目(各条目均含上游仓库的具体文件/行号证据,见第 9 章关于画像可核验性的说明)。

| 功能域 | Cube Tutor | cstimer | cubic | lukejacksonn | hkociemba | min2phase | tnoodle | cubing.js | taylorjg |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| d1 3D 渲染/视角/键盘操作 | ● | ● | ● | ◐ | ○ | ○ | ○ | ● | ● |
| d2 鼠标拖层交互 | ●(2~7 阶) | ◐(手势转层;raycast 代码被注释) | ○ | ●(仅 3 阶,Cuber 引擎) | ○ | ○ | ○ | ○ | ○ |
| d3 多阶支持 | ●(2~7 阶参数化) | ●(2~11 阶+任意) | ○(仅 3 阶) | ○(仅 3 阶) | ○(仅 3 阶) | ○(仅 3 阶) | ●(2~11 阶) | ●(至 40 阶+) | ○(仅 2/3 阶) |
| d4 WCA 官方/随机状态打乱³ | ◐(官方步数,非随机状态) | ●(3/2/4 阶随机状态) | ○(随机 10~15 步) | ○(无打乱) | ◐(均匀随机状态,无公式输出) | ●(随机状态+取逆) | ●(官方本体,含距离校验) | ●(16 事件全覆盖) | ◐(随机步,非官方) |
| d5 公式记号解析与播放 | ●(UDLRFB+宽转+MES/xyz) | ●(含层范围 2-3R) | ◐(仅基础记号) | ●(含宽转/MES/xyz) | ○(仅面转枚举,无播放) | ◐(仅外层转) | ◐(无 MES) | ●(AST:换位/共轭/NISS) | ◐(仅 6 外层转) |
| d6 LBL 分步教学 | ●(七阶段+提示+演示) | ○ | ●(54 步状态机+解说) | ◐(CFOP 文字策略) | ○ | ○ | ○ | ○ | ○ |
| d7 通用求解器 | ◐(LBL ≤170 步;最优解依赖外置包) | ●(30 项求解器套件) | ◐(层先法绑定教学) | ○ | ●(两阶段官方实现) | ●(自述 0.685ms/≤21 步+最优模式) | ●(3/4 阶+通用 BFS) | ●(min2phase WASM+异形) | ●(Kociemba 浏览器端) |
| d8 计时与成绩统计 | ●(AO5/AO12/持久化) | ●(多输入源+深度统计) | ○ | ○ | ○ | ○ | ○ | ○ | ○ |
| d9 CFOP 案例训练⁴ | ●(119 case/214 公式+出题+统计) | ●(40+ 子集+案例统计表) | ◐(5 个公式按钮) | ●(119 case/214 公式演示,无出题) | ○ | ◐(8 种受限随机状态) | ○ | ○ | ○ |
| d10 外部控制(TCP/API/CLI/MCP) | ●(TCP+MCP,唯一 MCP) | ◐(npm 模块+iframe) | ○ | ○ | ●(TCP 服务器+CLI+PyPI) | ◐(Java API/jar) | ●(HTTP REST+WS+CLI) | ●(npm+CLI+WS) | ○ |
| d11 异形魔方 | ✕ 明确不做 | ●(229 种/49 组) | ○ | ○ | ○ | ○ | ●(WCA 全 17 项) | ●(WCA 全项+4D 等) | ○ |
| d12 拍照/图像识别 | ✕ 明确不做 | ○ | ○ | ○ | ◐(实验性 webcam) | ○ | ○ | ○ | ○ |
| d13 蓝牙/智能魔方硬件 | ✕ 明确不做 | ●(5 厂商+计时器) | ○ | ○ | ○ | ○ | ○ | ●(5 厂商+机器人) | ○ |
| d14 在线对战/社区 | ✕ 明确不做 | ●(对战/比赛/OAuth) | ○ | ○ | ○ | ○ | ○(WCIF 为赛事数据交换) | ◐(Twizzle 分享) | ○ |
| d15 测试与 CI | ●(10+2 测试,无 CI) | ◐(静态检查+testbench,CI 不跑测试) | ○(无测试) | ○(无测试) | ◐(基准+输入校验,无单测) | ●(穷举最优性验证+Travis) | ●(JUnit5+React 测试+Actions) | ●(33 测试+5 job CI) | ●(vitest 35 用例+CI/CD) |

> ³ d4 判级标准(全列统一):●=可产出 WCA 风格打乱**公式序列**(随机状态经求解取逆,或官方随机步机制+距离校验);◐=仅有部分要素。hkociemba 为 ◐ 因其 cubie.py randomize() 生成数学均匀随机状态但无打乱公式序列输出封装(画像 d4 原文:「不输出 WCA 官方打乱公式序列」);min2phase 为 ● 因 Tools.randomCube()+solution(INVERSE_SOLUTION) 即得官方同源机制(画像 d4)。taylorjg 与 Cube Tutor 为 ◐ 均因「随机步符合步式约束但非随机状态」。Cube Tutor 步数规范:cube.gd:196 实测为 `{2:11, 3:25, 4:40, 5:60, 6:80, 7:100}`(与 tnoodle 官方步数一致);另计时模式在 MCP 桥可用时已走 WCA 均匀序列(README.md:9)。
> ⁴ d9 口径统一为「案例数/公式条数」:Cube Tutor 与 lukejacksonn 数据同源(同一上游 algorithms.ts),均为 119 案例(F2L 41/OLL 57/PLL 21)共 214 条公式,覆盖面完全相同;差异在功能形态(Cube Tutor 有随机出题+耗时统计,lukejacksonn 有静态缩略图导航+倒放)。cstimer 的 40+ 子集为另一量级(含 Roux/Mehta/EG 等),不可与 119 case 直接比大小。

矩阵要点:

- **Cube Tutor 是唯一在 d1/d2/d3/d6/d8/d9/d10 七个域全部为「有」的项目**——桌面教学工具形态的完整性是它的根本优势;cstimer 覆盖面更广但 d6(教学)为无。
- d11~d14 四域 Cube Tutor 均为 README 明确边界(异形/拍照/蓝牙/在线),与 cstimer、cubing.js 的「全家桶」路线形成刻意的定位区分。
- 求解器(d7)与打乱质量(d4)是 Cube Tutor 唯二明显落后的核心域能力。

---

## 4. 差距分析(别人有、我们没有)

与 README 明确边界重合的项(异形、拍照识别、蓝牙、在线对战)不列为差距,仅在矩阵中标注。以下按补齐优先级排序。

### 高优先级

**G1 随机状态打乱(来源:cstimer、tnoodle、cubing.js、min2phase、hkociemba)**
Cube Tutor 默认打乱为「对齐官方步数规范的随机步」(cube.gd:196:2 阶 11 步~7 阶 100 步,内层/宽层混合随机),而专业项目对 3x3 采用随机 facelet + min2phase 求 ≤21 步解取逆(cstimer `scramble_333_edit.js:49`)、2x2 最优随机状态(cstimer `2x2x2.js:401-434`)、4x4 WCA 随机状态(tnoodle `FourByFourCubePuzzle.java` 用 cs.threephase);tnoodle 还对每条打乱做最小距离下限校验(`Puzzle.generateWcaScramble` 循环)。随机步打乱存在状态分布偏差,对速拧训练有效性有实际影响。5~7 阶官方本身即随机步数(60/80/100 步),差距集中在 2/3/4 阶;且缓解路径已存在——计时模式在 MCP 桥(kociemba 包)可用时已走 WCA 均匀序列(README.md:9),缺的是自由/训练模式的默认覆盖与无外置包时的降级质量。

**G2 高性能两阶段求解器(来源:min2phase、hkociemba、cubing.js、cstimer、taylorjg)**
min2phase 自述全初始化约 195ms 后平均 0.685ms 出 ≤21 步解(Benchmark.md:8-12),且有最优解模式与增量续搜;hkociemba 自述平均 18.63~20.02 步随预算可调;cubing.js 将 min2phase 编译为 WASM 在 Web Worker 运行;taylorjg 用 npm rubik-solver 在浏览器端求解。(以上性能数字均引自上游自述,未复现,见 9.2。)Cube Tutor 自研 LBL 为 ≤170 步教学解,最优解依赖可选外置 kociemba 包(未装时 MCP 工具返回安装指引,README.md:43-47)。作为教学工具可接受,但「给定任意状态快速给短解」的能力缺失。

**G3 自身许可证缺失**
8 个对比项目的许可证状态来自各自画像(均有明确许可或双许可,仅 lukejacksonn 例外);本项目无 LICENSE 文件为**本次现场核实**(工作区根目录 `ls` 无该文件)。无许可证 = 默认保留所有权利,他人无法合规复用,也使 GPL 系代码的并入边界无从谈起。补齐成本极低(选一个许可证写一个文件),优先级最高。

### 中优先级

**G4 种子化可复现打乱(来源:tnoodle、cstimer、cubing.js、min2phase)**
tnoodle `generateSeededScramble` + SecureRandom、cstimer worker.js setSeed(ISAAC CSPRNG)、cubing.js `deriveScrambleForEvent`(seed+salt 层级)、min2phase `Tools.setRandomSource`。可复现打乱对 MCP 自动化测试、问题复现与教学回放都有价值;Cube Tutor 打乱不可种子化(画像与本次源码抽查均未见种子机制,cube.gd:191-203 scramble() 直接用 randi())。

**G5 案例训练的子集广度与按案例统计(来源:cstimer、min2phase)**
cstimer 案例训练覆盖 40+ 子集(CFOP 之外还有 Roux CMLL/LSE、Mehta 全套、2x2 EG/CLL/TCLL、Megaminx LL 等),trainstat 按案例给出缩略图、出现次数、best/mean 统计表(`stats/trainstat.js:24-40`);min2phase 提供 8 种受限均匀随机状态生成器(randomLastLayer/randomLastSlot/ZBLL/CLL 等,`src/Tools.java:318-379`)。Cube Tutor 有 119 case(F2L/OLL/PLL)随机出题+耗时统计,但无每案例 best/mean/出现率表,子集限于 CFOP 三组。

**G6 播放速度调节(来源:lukejacksonn、cubic)**
lukejacksonn 0-900ms 连续滑杆(cube.tsx:84-93)、cubic 转速滑条+Step/Play/Pause/Stop 四态控制(main.gd:668-698)。教学场景下慢速跟练是刚需,Cube Tutor 的公式播放无速度调节(其上游数据源项目调研明示此差异)。

**G7 实体魔方状态导入(来源:cubic)**
cubic 的 2D Color Map 展开图编辑器可点选移动/翻转/交换棱角块把实体魔方状态搬进软件并立即求解(color_map.gd:66-140);hkociemba 另有实验性 webcam 识别(属本项目明确不做范围)。Cube Tutor 有 Kociemba 54 字符 facelet **导出**而无导入通道——「实体魔方 → 软件 → LBL 教学」的闭环缺半环。

**G8 自动化 CI(来源:cubing.js、tnoodle、taylorjg、min2phase)**
cubing.js 5 个 GitHub Actions job、tnoodle gradle build+Coveralls、taylorjg lint+test+build+自动部署+Dependabot、min2phase Travis 8 项任务。Cube Tutor 有 10 个 GDScript headless 测试+2 个 Python 端到端,但无 `.github` 目录(本次现场核实),测试只能手动触发。

### 低优先级

**G9 7 阶以上任意阶(来源:cubing.js、cstimer、tnoodle)**
cubing.js 自述实测 40 阶加载 162ms、cstimer 支持任意 dimension。WCA 正式项目止于 7 阶,Cube Tutor 的 2~7 阶覆盖全部官方项目,扩展收益低。

**G10 公式结构化 AST(来源:cubing.js)**
cubing.js Alg 解析器支持换位 [A,B]/共轭 [A:B]/分组重复 (A)2/NISS/行内注释(parseAlg.ts:20-25)。教学场景线性公式串够用。

**G11 多语言 i18n(来源:cstimer 35 语言、tnoodle 27 语言)**
Cube Tutor 当前无国际化设施(画像与本次源码抽查均未见)。

**G12 打乱示意图导出(来源:tnoodle SVG/PNG、cstimer SVG)**
Cube Tutor 有 3D 实体渲染,平面示意图价值有限。

---

## 5. 差异化优势(我们有、别人没有)

以下逐项对照 8 个项目的调研画像验证「独一份」成色,不合格的如实降级。

**U1 MCP 外部控制 —— 独一份(9 项目唯一)✔**
逐一核对 8 项目 d10:cstimer 有 npm 模块与 iframe 嵌入但无 TCP/MCP/CLI;cubic 无任何外部通道;lukejacksonn 无(仅构建用截图脚本);hkociemba 有 TCP 服务器+CLI+PyPI 但无 MCP、无结构化协议;min2phase 仅 Java API;tnoodle 有 HTTP REST/WebSocket/CLI 但无 MCP;cubing.js 有 npm/CLI/WebSocket 但无 MCP;taylorjg 无。**MCP(Model Context Protocol)桥(tools/mcp_bridge.py,349 行)使 Cube Tutor 成为唯一可被 AI 代理直接操控的魔方工具**。9 个工具清单(本次自 mcp_bridge.py:35-112 与 README.md:43 核实):`cube_get_state` / `cube_scramble` / `cube_restore` / `cube_reset` / `cube_apply_alg` / `cube_solve` / `cube_hint` / `cube_solve_optimal` / `cube_scramble_wca`,其中后两个依赖可选 kociemba 包,未安装时工具仍列出、调用返回安装指引(mcp_bridge.py:22)。
安全维度的如实评估:9 个项目的外控接口画像均未提及任何鉴权或命令签名机制(tnoodle 甚至有 `/kill/tnoodle/now` 关停端点与 CORS anyHost;hkociemba 的 TCP 监听所有网络接口,sockets.py:55)。Cube Tutor 将 TCP 监听绑定于 127.0.0.1:8788 且单连接(README.md:37),暴露面是生态内最谨慎的一档,但同样无鉴权——本地单用户场景可接受,若日后开放远程需补鉴权。

**U2 NxN(2~7 阶)raycast 直接拖层 —— 组合独有,机制不独有 ✔(降级表述)**
拖层交互在生态中存在:lukejacksonn 的 Google Cuber 引擎内置拖层(仅 3 阶);cstimer 有「九宫格方向手势」转层且其 raycast 拖层完整实现存在但整体被注释禁用(twisty.js:299-393 包在 `/** */` 内);cubing.js 明确未实现拖层(DragTracker 仅用于视角)。**「手写 ray-OBB 拾取 + 8px 锁轴 + 实时预览 + 15° snap 量化 + Esc 回弹,且对 2~7 阶全部生效」的这一组合在 9 个项目中没有第二个**,但「3D 魔方鼠标拖层」作为单点能力不是独有。

**U3 LBL 分步教学引擎 —— 非独一份,质量与验证占优 ✔(如实表述)**
最接近的竞争者是 cubic:54 步层先法教学状态机 + 文字解说 + 相机自动转向解题面(23 处 rotate_to_face)+ Step/Play/Pause/Stop 控制,且另有 Cube Tutor 没有的 2D Color Map 状态编辑。但 cubic 仅 3 阶(与 Cube Tutor 教学模式相同)、绑定固定配色、异常分支直接 breakpoint、求解器对全部合法状态的覆盖未验证(其调研 uncertainties 明示)、无任何测试、2024-04 停更。Cube Tutor 的 lbl_solver.gd(902 行)有 facelet 置换模拟 + 模拟-验证-采用回环 + BFS 段(深度≤4)+ 100 随机态金标准测试(最坏 156 步)。**结论:「层先法动画教学」在生态中至少有两份实现,Cube Tutor 不独有;其相对优势是引擎级测试验证与任意打乱态的可靠覆盖,而非排他性。**

**U4 四模式一体的桌面教学工具形态 —— 9 项目中无对应物 ✔**
自由/教学/计时/训练四模式整合在 9 个项目中无对应物:cstimer 是 Web 全家桶但无教学模式;cubic 有教学无计时无训练;lukejacksonn 有演示无计时无教学;其余为库或演示。在 Godot 桌面生态中亦无同量级项目(第 7 章)。

**U5 轨迹球四元数无极点视角 —— 差异点(小)✔**
cstimer 为轨道式视角带上下限(twisty.js:194-210)、cubing.js/taylorjg 用 OrbitControls 有距离与俯仰约束,Cube Tutor 为全向滚转无极点的四元数轨迹球。属体验差异而非功能代差。

**U6 WCA 记号完备解析(GDScript 实现)—— 有限定条件的生态独有 ✔(降级表述)**
UDLRFB+'+2、n≥4 宽转、M E S/x y z、双通道播放,在 cstimer/cubing.js 中同样存在(JS 实现)。在 GDScript/Godot 生态内,就第 7 章检索所见 6 个项目没有第二份完整 WCA 记号实现——但该检索的完备性无法评估(见 7 章说明),故此条为「就现有检索而言独有」,不作为强断言。

**U7 计时器、CFOP 训练 —— 不是优势,如实降级 ✘**
计时统计领域 cstimer 全面领先(多输入源、可配置 trim、趋势/分布/复盘图表、云同步);CFOP 案例训练 cstimer 的 40+ 子集+trainstat 统计更广。Cube Tutor 这两域是「够用的桌面实现」,不列入差异化优势。

---

## 6. 替代评估(逐模块:替换 / 保留自研)

| 模块 | 对照对象 | 判断 | 理由 |
|---|---|---|---|
| LBL 教学引擎(lbl_solver.gd 902 行) | hkociemba / min2phase | **保留自研** | 两阶段算法输出 ≤21 步混合解,无阶段语义,无法承载「阶段检测/下一步提示/演示下一步/自动完成本阶段」的教学功能;LBL 是差异化核心(U3)。且两者均为 GPL-3.0,并入需整包开源,而本项目尚无许可证(G3)。最优解需求已由 MCP 外控调可选 kociemba 包覆盖,维持现状即可。 |
| 打乱器(cube.gd 内 WCA 步数打乱) | tnoodle / cubing.js | **保留自研,2/3/4 阶随机状态经外置包补足** | 5~7 阶官方机制本就是随机步数+距离校验,Cube Tutor 已对齐步数规范(cube.gd:196);差距集中在 2/3/4 阶随机状态(G1)。移植路径全部有阻碍:tnoodle AGPL、cubing.js GPL/MPL 双许可、min2phase 的 GDScript 移植先例 bsehovac/kociemba-godot 无许可证(不可抄)。现实路径是现状的 MCP 外控:kociemba 包安装指引已在 README.md:43-47(含清华镜像 pip 命令),且计时模式已实现「桥可用时打乱走 WCA 均匀序列」(README.md:9);待办仅剩把该路径推广到自由/训练模式或文档中更显眼的位置(附录 A-4)。 |
| CFOP 训练数据(data/cfop.json,119 case/214 公式) | lukejacksonn/cube 上游 | **保留数据,补许可确认** | 数据已实际使用且 README「数据来源」节声明来源与抓取 URL(README.md:63-68);但上游仓库无 LICENSE 文件、GitHub API license=null、仅 README 文字声明『MIT』(画像 licenseEvidence),本项目 README.md:72 亦按「未附任何开源许可」从严自述。行动项:向上游 issue 请求补 LICENSE 文件或书面确认(附录 A-2);若无法确认,以社区通用公式集重录替换(公式本身不受版权保护,具体编排与呈现方式受)。 |
| 计时器(timer.gd 132 行) | cstimer | **保留自研** | AO5/AO12(去头去尾)/单次最佳/按日期持久化/作废语义已完备,桌面单机场景自足;cstimer 为 Web 单页应用,无可在 Godot 中复用的组件。深度统计(趋势/分布/按案例)如需要按 G5 自增,而非替换。 |
| 3D 模拟核心(cube.gd 527 行) | cubing.js twisty / cstimer twisty / Google Cuber | **保留自研** | 三者均为 JS 生态,无法嵌入 Godot;核心资产(2~7 阶参数化 cubie 生成、动画队列上限 8 + Tween 演出后精确 bake、ray-OBB 拖层、is_solved NxN 判定)是本项目最大工程投入且构成 U2/U4。Godot 生态内无同量级实现可引(第 7 章)。 |
| MCP 桥(tools/mcp_bridge.py 349 行 + cube_server.gd 285 行) | 无直接竞品 | **保留自研** | 9 个项目中唯一(U1),是 AI 代理接入的战略资产;hkociemba 的 TCP 服务可作协议设计参照但不提供 MCP 语义。安全上维持 127.0.0.1 单连接绑定即可,勿开放远程(U1 安全评估)。 |

---

## 7. Godot 生态核实

以下为前序调研提供的 Godot 引擎魔方项目清单(存在性已核实;**检索渠道与关键词未随数据提供,完备性无法评估,应视为「已知清单」而非穷举**):

| 项目 | 星数 | 状态 | 许可证 | 简评 |
|---|---|---|---|---|
| andrew-wilkes/cubic | 22 | 2024-04 停更 | MIT | Godot 4 教学模拟器,层先法阶段按钮+求解动画+回放+速度调节+2D Color Map,itch.io 发行;**Godot 生态中最接近 Cube Tutor 定位的完整工具**(已入对比名单) |
| Cykyrios/RubiksCube | 3 | 2023-01 停更 | GPL-3.0 | Android 3x3 演示 app,结构完整但小型 |
| bsehovac/kociemba-godot | 3 | 2020-02 停更 | **无许可证** | Kociemba 算法 GDScript 移植(源自 muodov/kociemba),算法 demo 非完整工具;**无许可证不可直接复用其代码** |
| sakateka/godot-cube-solver | 3 | 2025-09 活跃 | MIT | Godot 4.4 点贴纸设色 + 内置 min2phase 移植求解 3x3,面向 Android APK,小型可用 |
| JacobKulberg/rubiks-cube-solver | 2 | 2026-01 | **无许可证** | Godot 4.5.1 求解+可视化,Thistlethwaite 约 31 步/1 秒(上游自述),学习型项目 |
| (aminhamki/RB-Gen) | 0 | 2026-06 | **无许可证** | JS+Godot 极简打乱+计时器,学习项目 |

**结论:就上述已知清单而言,Godot 生态内没有与 Cube Tutor 同量级的完整魔方教学工具。** 最接近的 cubic 在阶数(仅 3)、验证(无测试)、工程规模(约 1500 行 vs 约 5400 行,行数口径见总览表注 1)、维护状态(停更)上均显著落后;两个无许可证的求解器移植(kociemba-godot、JacobKulberg)因许可缺失不可作为代码来源。Cube Tutor 若补齐 LICENSE(G3),按本清单它将是 Godot 魔方工具中代码规模最大(约 5400 行 vs 其余最大约 1500 行)且许可状态明确的项目;「头部」与否取决于发布后的社区接受度,此处不作断言。

---

## 8. 其他相关项目

入选标准:前序调研中另行核实的、与 Cube Tutor 的计时/训练两个功能域相邻的工具型项目(星数 ≥40 且仓库可访问),仅作参照,无完整 15 域画像,不入矩阵。

- [bryanlundberg/NexusTimer](https://github.com/bryanlundberg/NexusTimer):83 星,push 2026-09-24 活跃,GPL-3.0,TypeScript Web——极简速拧训练工具(计时+训练+统计),可作计时器 UX 参照。
- [tao-yu/Alg-Trainer](https://github.com/tao-yu/Alg-Trainer):48 星,push 2024-06-14,MIT,JavaScript Web——算法记忆训练器(F2L/OLL/PLL 等 alg sets,支持智能魔方输入),可作训练模式交互参照。

---

## 9. 调研方法与局限

### 9.1 方法

- 8 个对比项目的画像来自单轮调研:以源码静态阅读为主(codeload.github.com tarball 逐一核对),部分含本机实测(cstimer 源码拼接实跑 30 类打乱、cubing.js npm 实测 16 事件打乱与求解、taylorjg npm test 35 用例通过、min2phase 输入校验路径、lukejacksonn 在线部署 HTTP 200)。
- **画像的可核验性说明**:画像为工作流前序调研的产出,未随本报告发布为独立文件;但画像的每条 d1~d15 判定均附上游仓库的具体文件/行号证据(如 cstimer twisty.js:299-393、min2phase src/Tools.java:318-379),读者可据总览表的上游仓库地址逐一回查。矩阵各格判定即转录自这些条目,未做二次复核(见局限)。
- 本报告撰写与修订时对 Cube Tutor 工作区做的现场核实(全部命令实际执行):
  - `find … -name "*.gd" | xargs wc -l`:15 个 .gd 文件合计 4703 行——scripts/cube.gd 527、cube_server.gd 285、lbl_solver.gd 902、main.gd 713、timer.gd 132;tests/self_test.gd 412、sticker_probe.gd 80、test_drag.gd 216、test_lbl.gd 344、test_scramble.gd 80、test_server.gd 249、test_timer.gd 219、test_view.gd 162、test_wide.gd 170、visual_test.gd 212;
  - `find … -name "*.py" | xargs wc -l`:3 个 .py 文件合计 697 行——tools/mcp_bridge.py 349、probe_pixels.py 84、tests/smoke_bridge.py 264;
  - `ls`:无 `.github` 目录(无 CI)、无 LICENSE 文件、无 export_presets.cfg、无 `.git`(非 git 仓库);
  - `grep` cube.gd:191-203:打乱步数映射 `{2:11, 3:25, 4:40, 5:60, 6:80, 7:100}`;
  - 读 tools/mcp_bridge.py:35-112:9 个 MCP 工具名清单;读 README.md:43-47(kociemba 安装指引)、README.md:9(计时模式桥可用时走 WCA 均匀序列)、README.md:63-72(数据来源与上游许可自述);
  - 修订时网络核验许可证(GitHub API 匿名配额耗尽,改走 raw.githubusercontent.com):cs0x7f/cstimer/master/LICENSE = GPLv3 全文 ✔、thewca/tnoodle/master/LICENSE = AGPLv3 全文 ✔、thewca/tnoodle-lib/master/LICENSE = GPLv3 全文 ✔(tnoodle-lib 为 Maven 依赖的独立仓库,主仓库内无对应目录)。

### 9.2 局限

- **单轮调研**:8 项目画像未二次复核,结论以画像为准;画像各自的 uncertainties(如 cstimer 在线功能未连网验证、tnoodle 未构建运行、cubic 求解器全状态覆盖未验证)原样继承,本报告未消解。
- **性能数字未实测**:min2phase 0.685ms、hkociemba 18.63 步、cubing.js 40 阶 162ms、taylorjg 20~22 步等均引自各项目 README/Benchmark 自述,本报告未独立复现;第 1 章「差距/代差」的定性成立(机制差异明确:随机状态 vs 随机步、两阶段 vs 层先法),但具体倍数应以自述数字看待。
- **星数与活跃度为调研时点快照**(2026-09 前后,GitHub API,部分项目遇限流以 codeload 源码为准)。
- **许可风险提示(重要)**:
  1. 本项目自身无 LICENSE 文件(本次核实)——他人无法合规复用,须最先补齐;
  2. `data/cfop.json` 上游 lukejacksonn/cube 无 LICENSE 文件,仅 README 文字声明『MIT』(GitHub 未识别;本项目 README.md:72 亦按「未附任何开源许可」自述),存在不确定性,建议取得书面/issue 确认;
  3. GPL/AGPL 系项目(cstimer、hkociemba、min2phase、cubing.js、tnoodle)的代码不可直接并入,除非本项目决定以兼容许可证整体开源;
  4. Godot 生态内 kociemba-godot 与 JacobKulberg/rubiks-cube-solver 均无许可证,不可作为代码来源;
  5. min2phase 为 GPLv3+MIT 双许可、cubing.js 为 GPL+MPL 双许可——若未来需要移植求解算法,MIT/MPL 侧是唯一无传染路径,须在取用时逐文件确认许可归属(如 cubing.js 中 vendored 代码另含 Apache/MIT 许可)。

---

## 附录 A:行动项清单(按优先级)

| # | 行动项 | 关联结论 | 成本估计 |
|---|---|---|---|
| A-1 | 为仓库添加 LICENSE 文件(需先决定许可证取向:若保持专有则声明保留权利;若开源且需引用 GPL 代码则选兼容许可) | G3、9.2-1 | 极低(单文件) |
| A-2 | 向 lukejacksonn/cube 提 issue 请求补 LICENSE 或书面确认 MIT;无果则重录公式集替换 cfop.json | 替代:CFOP 数据、9.2-2 | 低 |
| A-3 | 添加 CI(GitHub Actions 跑 README「测试」节已有命令:headless self_test 等 + smoke_bridge.py) | G8 | 低(命令已存在) |
| A-4 | 把「桥可用时 WCA 均匀打乱」从计时模式推广到自由/训练模式,或在 README 首屏更显著引导 kociemba 安装 | G1、替代:打乱器 | 中 |
| A-5 | 公式播放速度调节(参照 lukejacksonn 0-900ms 滑杆与 cubic 四态控制) | G6 | 中 |
| A-6 | 打乱种子化(MCP 自动化复现场景优先) | G4 | 中 |
| A-7 | facelet 导入通道(实体魔方 → LBL 教学闭环,参照 cubic Color Map 交互) | G7 | 中高 |
| A-8 | 每案例 best/mean/出现率统计表(times.cfg 已有按日期数据可聚合) | G5 | 中 |

### 交付状态盘点(2026-09-25,随实施轮维护)

- **已交付**:A-3(CI:`.github/workflows/ci.yml` 跑全部 headless 测试 + py_compile + WCA 生成器直跑 + smoke_bridge)、A-4(WCA 均匀打乱从计时模式推广到自由/训练模式,README 功能节同步)、A-5(公式播放速度滑杆 0.05~0.90 s/步)、A-6(打乱种子化:`cube_scramble` 可选 (seed, steps)、`cube_scramble_wca` 可选 seed,均端到端断言可复现)、A-8(每案例统计**简版**:次数/best/mean——出现率与跨案例统计表两项未实现,取舍声明见 `scripts/main.gd` `_update_train_stat` 注释)。
- **决策后更新(2026-09-25)**:A-1 **已交付**——项目所有者裁决 GPL-3.0,`LICENSE` 已就位(README「许可」节同步);A-2 **已完成**——项目所有者裁决走备选「社区通用公式集重录」:`data/cfop.json` 已由 `tools/rebuild_cfop.py` 从 speedsolving wiki 公共算法表重收集替换(119 case / 614 条公式,全量数学验证),上游许可依赖消除,向上游发 issue 确认不再必要。A-7(facelet 导入通道)——**项目所有者裁决暂不做(2026-09-25)**,需求出现时再启动。至此附录 A 八项全部闭环:A-1~A-6、A-8 已交付,A-7 明示搁置。
