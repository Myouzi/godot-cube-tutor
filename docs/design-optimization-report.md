# Cube Tutor 设计优化与审计报告

日期:2026-09-25
依据:`docs/open-source-comparison.md`(开源对标调研,附录 A 八项行动项)及其实施、审计、终审全流程记录。

**报告体例**:
- 标注「实施记录」「审计 R1/R2」「处置记录」「终审」的内容为各轮流程记录的转写;其余事实性陈述均为撰写本报告时(2026-09-25)对当前工作区实际执行的命令与读码结果,命令与输出汇总见第五节,未在本轮重验的实施期自验项均随文标注来源轮次。
- 文中全部 `path:line` 代码引用均经本轮读码核实当前行号。`docs:NN` 为 `docs/open-source-comparison.md` 的行号简写;`PLAN §NN` 为 `PLAN.md` 对应章节(§18=PLAN.md:385、§16.3=PLAN.md:395、H4 裁决=PLAN.md:294,均本轮核实);`EXPERIENCE.md` 指项目根 `EXPERIENCE.md`(假绿陷阱条目在其 15 行,本轮核实)。
- 实施轮范围由其任务说明指派,含三个实施 item:A-4+A-6(同 item,共用一份改动文件清单)、A-5+A-8(同 item)、A-3——故交付恰为五项;下文「主指令」指实施轮任务说明原文,其 A-3 条目要求「跑 README『测试』节全部命令」(实施记录据此裁决 8 个/10 个测试的口径分歧,见二、A-3)。

---

## 一、背景与范围

调研报告 `docs/open-source-comparison.md` 附录 A(225–232 行)列出八项行动项 A-1~A-8。本轮(设计优化实施轮 + 两轮审计 + 处置 + 终审)交付其中五项:

| 编号 | 行动项 | 状态 |
|---|---|---|
| A-3 | 添加 CI(GitHub Actions 跑 README「测试」节命令) | ✅ 已交付¹ |
| A-4 | WCA 均匀打乱从计时模式推广到自由/训练模式 | ✅ 已交付 |
| A-5 | 公式播放速度调节 | ✅ 已交付 |
| A-6 | 打乱种子化(MCP 自动化复现优先) | ✅ 已交付 |
| A-8 | 训练每案例统计 | ✅ 已交付(简版;出现率与统计表两项 deferred,见二 A-8、六.6) |
| A-1 | 为仓库添加 LICENSE | ❌ 未交付(范围外,见下) |
| A-2 | 向上游 lukejacksonn/cube 确认许可或重录公式集 | ❌ 未交付(范围外,见下) |
| A-7 | facelet 导入通道 | ❌ 未交付(范围外,见下) |

¹ A-3 的交付物是 CI 配置文件,其全部命令已在本地实测通过,但 **Actions 编排本身从未运行过**(工作区非 git 仓库无法触发,详见第五节)——只看本表请勿高估 A-3 的证据强度。

**A-1/A-2/A-7 范围外理由**(处置记录;此前三轮均无声无息,终审第 4 条指出后补记,现同步落为 `docs/open-source-comparison.md:234-237` 的「交付状态盘点(2026-09-25)」小节;条目编号沿用终审记录原文顺序,见四):

- **A-1(添加 LICENSE)**:许可证取向(专有声明保留权利,还是选 GPL 兼容许可开源)是项目所有者的法律决策,修复轮不宜代选。本轮实测 `ls LICENSE*` → 不存在,与终审发现一致。注意调研正文曾将其定为最高优先级(docs:91「补齐成本极低……优先级最高」、docs:213「须最先补齐」)。
- **A-2(上游许可确认)**:需以项目所有者(或其授权者)的身份向上游仓库公开发起沟通,且沟通的目标诉求取决于 A-1 的取向决策(最终专有与开源对应的表态不同),属所有者决策链,故不宜由修复轮代发;本轮工作区亦无 GitHub 认证环境(`gh` CLI 未安装,本轮实测)。处置记录仅记「需对外沟通,未发起」。README.md:77 仍按「未附任何开源许可」从严自述。
- **A-7(facelet 导入)**:中高成本新功能,未排期。

审计方法口径:`EXPERIENCE.md:15` 记载的项目既有**双校验**口径为——exit code 为 0 **且**输出无 `SCRIPT ERROR` 行,它挡的是「SCRIPT ERROR 中断协程后已排队的 `quit(0)` 照常执行」型假绿。审计 R2-3 进一步实证:该双校验仍挡不住测试代码自身缺陷导致的「断言 FAIL 却 exit 0 且打印 ALL PASSED」型假绿(该型已由测试改 `_fail` 累计修复,见三、R2-3)。因此**本报告第五节的验证实际执行三项判定**:exit code、`SCRIPT ERROR` 计数、末行 `ALL PASSED`。

---

## 二、实施明细

### A-3 CI(GitHub Actions)

**做了什么**:新建 `.github/workflows/ci.yml`(本轮实测存在,8 个 step):单 job、ubuntu-latest、push/pull_request 触发、checkout + Godot 4.7.2 官方二进制缓存 + kociemba 安装,完整跑 README「测试」节——10 个 headless GDScript 测试(逐个双校验)、`py_compile tools/mcp_bridge.py tools/wca_scramble.py`、WCA 生成器直跑(`python3 tools/wca_scramble.py | grep -q '"ok": true'`,ci.yml:55-58)、`smoke_bridge --port=18925` 隔离端口(ci.yml:82-83)。

**关键取舍**(实施记录,本轮核实其载体存在):
1. 任务原文说「8 个测试」,但 README:53 现列 10 个(A-4/A-8 新增的 test_scramble_ui、test_train_stats 已入列),按主指令「README『测试』节全部命令」收录 10 个(主指令定义见体例段)——本轮实测 ci.yml:65-66 循环清单确为 10 个。
2. CI 额外安装 kociemba:test_scramble_ui / test_timer 的 3 阶 WCA 断言在 kociemba 缺失时会降级随机步而真红,smoke_bridge 的 WCA 段同样依赖(ci.yml:42-43 注释;处置轮补充点名 test_timer)。本轮实测 README:54 已注明该环境前提。
3. yml 顶部注释(ci.yml:1)如实标注「本地已实测命令本身;Actions 编排未验证(本工作区非 git 仓库,无法本地触发 Actions)」——Actions 编排至今未验证(见六)。
4. 视觉测试(visual_test/sticker_probe)需 X 会话,不入 CI(ci.yml:6)。

**改动文件**:`.github/workflows/ci.yml`、`README.md`(测试节补 CI 说明,本轮实测 README:66)。

**新增测试**:无新增测试文件;CI 本身即测试编排。

### A-4 WCA 均匀打乱推广到自由/训练模式

**做了什么**:
- 从 `tools/mcp_bridge.py` 抽出 `generate_wca_scramble()`(mcp_bridge.py:218,本轮实测:随机合法状态 → kociemba.solve → 解取逆),与 MCP `cube_scramble_wca` 单一实现源(不另造算法,H4 裁决——PLAN.md:294「均匀打乱=随机合法状态→solve→取逆」);新增 `tools/wca_scramble.py`(38 行,本轮实测直跑 ok:true、21 步合法序列)作游戏侧 CLI 入口。
- `scripts/main.gd` 打乱按钮(`_on_scramble`,本轮实测 main.gd:150-162):3 阶时经 python3 子进程取 WCA 序列,走 server 现有 `scramble_wca_apply` dispatch(标记 `wca_scramble_alg` + `scramble_entered` 信号 + 面板展示,与 MCP 完全同语义,cube_server.gd:115-127);生成器不可用、代执行失败(dispatch 返回 ok:false,处置轮补的防御)或 N≠3 时降级随机步并如实提示。
- 降级路径同步清 `server.wca_scramble_alg`(main.gd:157)——否则 state 查询返回旧 WCA 序列名实不符(审计 R1-2 发现的残留问题,已修)。

**关键取舍**:`_wca_scramble_alg` 用 `OS.execute` 同步等待,无超时参数——生成器异常挂死会阻塞 UI,已在代码注释标注 ponytail 上限与升级路径(main.gd:169)。

**改动文件**(实施记录;A-4 与 A-6 同 item,清单共享):`scripts/cube.gd`(其改动属同 item 的 A-6:scramble 加 RNG 注入,见下 A-6 节)、`scripts/main.gd`、`tools/mcp_bridge.py`、`tools/wca_scramble.py`、`tests/test_scramble.gd`、`tests/test_scramble_ui.gd`、`tests/test_timer.gd`、`tests/smoke_bridge.py`、`README.md`。

**新增测试**:
- `tests/test_scramble_ui.gd`(新,60 行,本轮实测全读):3 阶按钮走 WCA 代执行(标记+入队步数一致+信号反馈,35-40 行)、4 阶降级随机步且 WCA 标记作废(49 行)、先玩 5 步再打乱断言提示为本次 40 步而非累计 45(43-53 行,锁定差值实现)、MCP scramble 命令服务端信号路径降级文案无步数(56-58 行)。
- `tests/test_timer.gd`:计时模式 WCA 断言 + 降级分支直驱断言(本轮实测 214-219 行:服务端路径 `(本次为随机步打乱,非 WCA 均匀打乱)` 与按钮路径 25 步两分支逐字断言;216 行断言无过时 MCP 引导)。
- `tests/smoke_bridge.py`:WCA 端到端断言(本轮实测输出含「cube_scramble_wca seed=424242 可复现」等 18 项 PASS)。

### A-5 公式播放速度调节

**做了什么**:`scripts/cube.gd` 删 `const TURN_TIME := 0.18` 改实例属性 `var turn_time: float = 0.18` 带 setter,赋值即 clamp 0.05~0.90(本轮实测 cube.gd:34-36)——滑杆与代码同一入口;公式播放与回放动画统一经 `_start_turn` 单点执行(cube.gd:33 注释声明、462 定义、456 唯一调用点,本轮核实),天然同受此值控制。`scenes/main.tscn` 顶栏加 SpeedSlider(HSlider)+ SpeedLabel(本轮实测 main.tscn:118-126:min 0.05 / max 0.9 / step 0.01 / value 0.18,与 clamp 一致);main.gd `_ready` 连 `value_changed` 即时生效并同步显示(main.gd:117-118、255-257)。

**改动文件**:`scripts/cube.gd`、`scripts/main.gd`、`scenes/main.tscn`、`tests/test_train_stats.gd`、`README.md`(本轮实测 README:7 功能行、README:33 操作表均有滑杆条目)。

**新增测试**(`tests/test_train_stats.gd`,本轮实测全读):turn_time 默认 0.18、设 0.5 生效、0.01→clamp 0.05、5.0→clamp 0.90、边界原样接受(37-47 行,纯属性断言不起动画);滑杆初值=引擎值、量程/步长与 clamp 边界锁定(106-110 行,防场景与引擎单方面漂移——审计 R1-16 发现的缺口)、拖 0.62 即时写入引擎(112 行)。

### A-6 打乱种子化

**做了什么**:
- 引擎侧:`cube.gd` 的 `scramble()` 加可选 `RandomNumberGenerator` 注入(本轮实测 cube.gd:197);null 路径保持全局 `randi()`,零行为漂移(保住 test_lbl 金标准等 `seed()+randi()` 既有确定性)。`cube_server.gd` 的 `scramble` 命令加 `seed` 参数,经 `validate_seed` 校验(非数字/非整数/超 2^53 精度界三拒绝分支,本轮实测 cube_server.gd:84-90、168-174)。
- MCP 侧:`cube_scramble` 透传 seed(mcp_bridge.py:131 CMD_OF);`cube_scramble_wca` 加可选 seed(inputSchema 含 integer 属性,mcp_bridge.py:111-122;实现 279-285 行,非整数 seed 含 bool/浮点/字符串显式报错「seed 必须为整数(JSON integer)」,与游戏侧 validate_seed 同口径——审计 R2-2 发现的静默降熵问题,已修)。

**关键取舍**:游戏侧按钮的 `wca_scramble.py` 不提供 seed 入口(打乱按钮场景无复现需求);审计 R1-4 曾指出 WCA 打乱不可种子复现,处置轮已给 MCP `cube_scramble_wca` 补上 seed,范围按「MCP 自动化复现场景优先」收窄。

**改动文件**(实施记录 + 处置记录):`scripts/cube.gd`、`scripts/cube_server.gd`、`tools/mcp_bridge.py`、`tests/test_scramble.gd`、`tests/smoke_bridge.py`、`README.md`(本轮实测 README:44 工具列表对 cube_scramble 与 cube_scramble_wca 均标注可选 seed)。

**新增测试**:
- `tests/test_scramble.gd` 3 条种子断言(本轮实测 78-98 行):N=3 同 seed 两次序列与 facelets 完全一致、不同 seed 不同、N=4 同 seed 一致(内层/宽层路径)。
- `tests/test_server.gd` S8(本轮实测 183-197 行):seed="abc"→「seed 必须为数字」、1.5 与 9007199254740994(2^53+2)→「seed 须为整数」拒绝、seed=42 放行——validate_seed 三条拒绝分支的负例回归(审计 R1-13 发现零覆盖,已固化为断言)。
- `tests/smoke_bridge.py` 端到端:同 seed=424242 两次复现、seed=424243 不同、WCA seed='abc' 显式报错(本轮实测输出含该 3 项 PASS)。

### A-8 训练每案例统计(简版)

**做了什么**:新建 `scripts/train_stats.gd`(44 行,RefCounted 纯逻辑):`record`/`stats`,ConfigFile 持久化 `user://train_stats.cfg`,store_path 可注入(测试重定向),key 用 `unix毫秒_序号` 防同毫秒撞键(本轮实测 train_stats.gd:10-25,同 timer.gd 口径;毫秒 clock 可注入供假钟测试,train_stats.gd:7)。main.gd 训练完成分支入账并刷新(main.gd:768-778),出题时显示统计(`_update_train_stat`,main.gd:721-731);key = `分类/case名`(main.gd:736-737)——cfop.json 中 f2l 与 oll 有 41 对同名 case(实施记录;本轮实测类型分布 f2l 41/oll 57/pll 21),须带分类前缀防串。main.tscn TrainPanel 加 TrainStatLabel(main.tscn:336)。

**关键取舍与已声明缺失**:A-8 原文「每案例 best/mean/**出现率**统计**表**」只交付当前 case 单行(次数/best/mean)。**出现率未实现**(record 仅挂在完成边沿,出题事件不入账,无法计算出现率)、**跨案例统计表视图不存在**。此缺失曾由审计 R1-1 指出「报告自称简版但未声明」;现已双重声明:`main.gd` `_update_train_stat` 注释(717-720 行,注明归属 PLAN §16.3「进度统计 UI 留 P4 开工前专项 grill」,PLAN.md:395)与处置记录 deferred 条目。终审后补的两条防护见四。

**改动文件**:`scripts/train_stats.gd`、`scripts/main.gd`、`scenes/main.tscn`、`tests/test_train_stats.gd`、`README.md`(本轮实测 README:10 训练行含统计描述)。

**新增测试**(`tests/test_train_stats.gd`,183 行,本轮实测全读):聚合断言(已知序列 count/best/mean、追加更新、空记录 -1 哨兵、f2l/1 与 oll/1 互不串、持久化读回,52-76 行);同毫秒防撞(假钟钉死同一毫秒连打 10 条,key 唯一、序号 _0.._9 依序,77-94 行——审计 R1-15 发现的零覆盖,已补);UI 接线(出题显「首次挑战」、入账后显「1 次 · best 1.23s」,存储重定向临时目录);**真实 E2E**(130-149 行:`_on_reset`→出题→等 1 帧记未复原基线→正序 apply_turn 瞬时复原→等 2 帧,`_process` 的 is_solved 上升沿自动 record,不经任何手动 record——审计 R1-12 指出原测试绕过完成边沿,已补真实闭环);该文件顺带修了 `_check` 失败被尾部 `quit(0)` 覆盖的假绿陷阱(21 行注释,EXPERIENCE 口径)。

---

## 三、审计与修复记录

两轮审计共产出 24 条发现(R1 17 条、R2 7 条;其中 main.gd:200 与 main.gd:201 的步数虚报各出现两条重复记录,系同一问题两次录入,处置合并),处置 24/24:fixed 22、deferred 2。本节按主题归并,处置结论均为处置记录所载,关键项经本轮读码核实载体存在。

### 3.1 代码质量类(fixed)

| 发现(出处) | 问题 | 处置 |
|---|---|---|
| R1-2 / R1-8(合并:main.gd 降级路径) | 按钮随机步降级绕过 server,WCA 标记 `wca_scramble_alg` 残留名实不符(cube_server.gd:27-30 约定 vs 91 行清理);且 dispatch 返回值被丢弃,失败静默 | 降级路径补 `server.wca_scramble_alg=""`;`_on_scramble` 重构为检查 dispatch 返回,失败落入降级。本轮实测 main.gd:150-162 与 test_scramble_ui.gd:49 断言「降级 = 标记作废」 |
| R1-3 + R1-7 / R2-1 + R2-4(重复)(main.gd:200/201) | 非计时/计时分支降级提示步数虚报:取 `cube.full_log.size()`(恒为初始态→当前态全量路径,cube.gd:42)或写死 25,而 MCP `cube_scramble` steps 合法域 1..100(mcp_bridge.py:51);且 `scramble_entered.emit("")` 不携带步数(cube_server.gd:92) | `_on_scramble_entered` 加 `rand_steps` 参数:按钮路径传 full_log 前后差值(真实本次步数),服务端信号路径传 -1 → 文案省略数字,宁缺勿虚报;计时/非计时两分支均接入(main.gd:195-220,本轮实测)。test_timer.gd 原写死 25 的逐字断言改双分支(214/219 行) |
| R1-6(main.gd:193) | 计时降级提示括号引导「经 MCP cube_scramble_wca」已过时:该分支唯一到达原因是 kociemba 不可用,而 MCP 工具同样依赖 kociemba,指引无效 | 文案改「已打乱(非 WCA 均匀打乱;WCA 均匀打乱需 kociemba 可用)」(main.gd:208),验收子串「非 WCA 均匀打乱」保留(PLAN §18=PLAN.md:385 只钉提示本身);test_timer.gd:216 断言无 MCP 字样 |
| R2-2(mcp_bridge.py:279-280) | `cube_scramble_wca` 可选 seed 对非整数输入静默降为系统熵源(同 seed 不复现且无错误信号);同桥 cube_scramble 则显式报错 | `handle_kociemba_tool` 对非整数 seed 返回 isError「seed 必须为整数(JSON integer)」(本轮实测 mcp_bridge.py:279-285);smoke_bridge 加 'abc' 负例断言(本轮实测 PASS) |

### 3.2 达成度/文档类(fixed 6 条 + deferred 2 条)

- **fixed**:README 计时行过时口径「桥可用时打乱走 WCA」(R1-5/R1-10,改「与自由模式同口径」,本轮实测 README:9);训练行缺 WCA 描述(同条,README:10);速度滑杆与统计缺功能节/操作表条目(R1-10,README:7/10/33);cube_scramble_wca 的 seed 未入 README 工具表、CI 描述漏 WCA 直跑步骤(R2-5,README:44/66);test_timer 的 kociemba 环境前提未注明(R1-11,README:54 + ci.yml:42-43)。
- **fixed(测试前提)**:py_compile 未覆盖 `tools/wca_scramble.py`(R1-9,ci.yml:52 本轮实测已含);WCA 生成器直跑未固化为 CI 步骤(R1-17,ci.yml:55-58 本轮实测已含)。
- **deferred ①**:A-8 的出现率与统计表两项未实现且未声明(R1-1)→ 「未声明」部分已修(main.gd:717-720 注释 + docs 盘点),功能本身 deferred,理由见二、A-8 节。
- **deferred ②**:A-1/A-2/A-7 三项无交付且无任何状态声明(终审第 4 条)→ docs:234-237 补「交付状态盘点」。

### 3.3 测试强度类(fixed 9 条)

| 发现 | 问题 | 处置(本轮实测佐证) |
|---|---|---|
| R1-12 | A-8「训练完成→自动入账」无真实端到端(原 UI 段手动 record 绕过 is_solved 边沿) | test_train_stats.gd:130-149 真实 E2E(边沿自动入账);顺带修该文件假绿陷阱 |
| R1-13 | validate_seed 三拒绝分支零回归 | test_server.gd S8(183-197) |
| R1-14 | 计时模式降级提示分支(main.gd 计时专属文本)失测 | test_timer 直驱 `_on_scramble_entered("")` 断言面板文本+status(214-217) |
| R1-15 | train_stats 同毫秒 key 防撞逻辑零覆盖 | 假钟注入点(train_stats.gd:7)+ 10 连打唯一性断言(test_train_stats:77-94) |
| R1-16 | SpeedSlider 场景参数与 cube clamp 一致性无锁定 | test_train_stats:107-110 量程/步长断言 |
| R2-3 | **假绿陷阱(同轮半修)**:R1 只修了 test_train_stats 的 `_check` 失败被尾部 `quit(0)` 覆盖,同款陷阱在 test_timer/test_server 仍在——末段同步区(最后一条 await 之后)断言 FAIL 时 exit 0 且打印 ALL PASSED,CI 双校验失效;窗口内恰是核心断言(timer:222/224/226 计时状态机贯穿、server:258-266 S6 socket 冒烟)。审计用副本注入探针实证(修复前 exit=0+ALL PASSED) | 两文件改 `_fail` 累计、尾部统一判 exit(1 if _fail else 0);按审计同法副本注入验证修复后 exit=1。本轮实测 10 测试循环 grep `SCRIPT ERROR` 均为 0 |
| R2-6 | 「先玩后打乱」步数差值修复无回归断言(降级场景 full_log 起点 0,差值≡full_log.size(),回归旧写法不红) | test_scramble_ui:45-53 改为先 apply 5 步再打乱,断言 full_log=45 且提示 40 步 |
| R2-7 | rand_steps<0 分支(服务端信号路径文案)零覆盖 | test_scramble_ui:56-58 新增场景 3(dispatch scramble steps=5,断言无数字文案) |

### 3.4 误报与记录瑕疵(如实列)

- R1-3 与 R1-7、R2-1 与 R2-4 为重复录入(同一 main.gd:200/201 步数虚报),处置记录亦各对应两条;本报告已合并。
- 终审第 3 条(cfop.json name '6.0' 显示,见四)在 R1/R2 均未被发现,系三轮均漏的真实问题,非误报。

---

## 四、终审意见

终审 5 条发现:2 条已修复(4.1)、1 条未处置留后(4.3)、1 条 deferred、1 条部分处置(4.2)。**条目编号沿用终审记录原文顺序**(③=cfop 显示、④=A-1/A-2/A-7、⑤=调研报告过时),故各小节内编号不连续;全文交叉引用(一、3.2、3.4)均按此编号。

### 4.1 已修复(附防护测试,本轮实测 test_train_stats 全过)

1. **训练统计 key 用「当前」分类而非出题时分类**(medium):`_set_train_cat` 只改 `_train_cat` 不清 `_train_case`,完成入账记到从未出题的分类(终审探针实测:出题 f2l/6.0 → 切 oll → 复原,成绩记到 oll/6.0)。处置:新增 `_train_case_cat` 成员于出题时冻结分类(main.gd:87、706),`_train_case_id()` 改用之(main.gd:736-737),`_on_reset`/`_on_size_selected` 同步清空(241、305);test_train_stats 防护①(150-168 行:出题→切 oll→复原→断言记到 f2l 且 oll 同名 case 零入账)。
2. **完成判定只看 is_solved 上升沿,不校验复原方式**(medium):出题后经 MCP `cube_scramble`+`cube_reset` 可把无关复原跳变记成 0.02 秒伪成绩并持久化(终审探针实测 done=true count=1「耗时 0.02 秒」)——MCP 自动化在训练模式出题后做 reset/代解是本项目卖点场景。处置:完成入账加 `cube.moves > 0` guard(main.gd:769-772,前提读码验证:cube.gd `_commit` 仅 PLAYER/UNDO 计步,ALG/REPLAY 不计,scramble/reset 后恒 0);test_train_stats 防护②(169-182 行:出题→dispatch reset→断言不入账且 `_train_done=false`)。

### 4.2 deferred / 部分处置

4. **A-1/A-2/A-7 无交付且无声无息**(medium)→ deferred,已补 docs:234-237 交付状态盘点(见一)。
5. **调研报告正文未随实施更新**(low)→ **部分处置,仅附录 A 补盘点;正文过时描述本轮实测仍未改**,逐处核实:`docs/open-source-comparison.md` d15 行(65)仍「无 CI」、注 3(67)与 G1(85)仍称 WCA 打乱仅计时模式「缺的是自由/训练模式的默认覆盖」、G8(108)与 9.1(202)仍「无 .github 目录(本次现场核实)」、159 行仍「待办仅剩把该路径推广到自由/训练模式(附录 A-4)」、行数快照(27/131/163/200)仍称 15 个 .gd 4703 行、mcp_bridge.py 349 行——本轮实测 main.gd 814 / cube.gd 539 / cube_server.gd 302 / mcp_bridge.py 379 行。按报告读者会得到错误的现状判断。

### 4.3 未处置(留后)

3. **cfop.json 数字 case 名显示为 '6.0' 形态**(low,三轮均漏):f2l/oll 全部 98 个 case 的 name 是 JSON 数字,`JSON.parse_string` 转 float 后 `str()` 输出 '6.0'——训练面板显示「6.0 · Basic Insert」(main.gd:710 `str(case.name)`),统计 key 落成 'f2l/6.0'/'oll/46.0'(main.gd:737)。本轮实测类型分布:f2l {int:41}、oll {int:57}、pll {str:21}。key 内部自洽不影响互串(测试用同一 `_train_case_id()` 内部比较,永远测不出),但与产品语义(案号 6)不符、持久化数据可读性差。**未修复,亦无处置声明**;若将来改 key 格式,已持久化的 `user://train_stats.cfg` 旧记录会与新 key 断链,需一并考虑。

---

## 五、最终验证状态

以下命令为**撰写本报告时在当前工作区实际执行**(全部双校验口径),无一凭实施期记录转写:

| # | 命令 | 结果 |
|---|---|---|
| 1 | `godot --headless -s tests/<t>.gd` × 10(self_test / test_drag / test_lbl / test_scramble / test_scramble_ui / test_server / test_timer / test_train_stats / test_view / test_wide,CI 同款循环) | **10/10 exit=0、SCRIPT ERROR 计数 0、末行 ALL PASSED** |
| 2 | `python3 -m py_compile tools/mcp_bridge.py tools/wca_scramble.py` | OK |
| 3 | `python3 tools/wca_scramble.py`(直跑) | `ok: true`,21 步合法序列 |
| 4 | `python3 tests/smoke_bridge.py --port=18925`(CI 同款隔离端口,起真实游戏进程+桥端到端) | **exit=0,18 项 PASS / 0 FAIL / ALL PASSED**,含 `cube_scramble_wca seed=424242 可复现`、`seed='abc' 显式报错(不静默降熵)`;未触碰用户常驻 8788 实例(实施前 `pgrep` 确认常驻进程,实施后确认无残留测试进程) |
| 5 | `ls /home/muyouzi/godot-project/LICENSE*` | 不存在(A-1 未交付的实证) |
| 6 | `wc -l` 关键文件 | main.gd 814 / cube.gd 539 / cube_server.gd 302 / train_stats.gd 44 / mcp_bridge.py 379 / wca_scramble.py 38 |
| 7 | cfop.json name 类型分布(python3) | f2l {int:41} / oll {int:57} / pll {str:21}(终审 4.3 的实证) |
| 8 | 收尾轮(留后项 3/4 闭合后)同款全套复跑:10 个 headless 测试 + py_compile(2 文件)+ smoke_bridge --port=18925 | **全绿**(exit=0、SCRIPT ERROR 计数 0、ALL PASSED);test_train_stats 含新增「key 无 '.0' 形态」断言 |
| 8 | main.tscn SpeedSlider 参数读值 | min 0.05 / max 0.9 / step 0.01 / value 0.18 |
| 9 | `godot --version` | 4.7.2.stable.official.ed1daf0bf——与 ci.yml:17 `GODOT_VERSION: 4.7.2-stable` 同版,CI 与本机测试环境一致 |
| 10 | `gh auth status` | `gh: 未找到命令`(gh CLI 未安装,支撑一、A-2 范围外理由) |
| 11 | docs/README/ci.yml/PLAN/EXPERIENCE/test 文件逐处读码核对 | 见二~四各处引用;PLAN §18/§16.3/H4 锚点与 EXPERIENCE 假绿条目行号均本轮核实 |

**未在本轮执行、状态如实声明**:
- **GitHub Actions 编排**:从未实际验证(工作区非 git 仓库、无远端,无法触发;仅实施期用 PyYAML 验过 yml 语法可解析)。ci.yml:1 顶部注释如实标注。这是本报告最大的未验证项——上表 #1–#4 已覆盖 ci.yml 中全部 **13 条测试命令**(10 个 headless 测试 + py_compile + WCA 生成器直跑 + smoke_bridge,即 ci.yml 的四个命令类 step 的逐条展开)且全部通过,但「push 后 Actions 真的绿」未经证据支持;ci.yml 的环境类步骤(checkout/缓存/Godot 下载/kociemba 安装)亦未实测。
- **视觉测试**(`tests/visual_test.gd`、`sticker_probe.gd`):需 X 会话,不在本轮改动与验证范围;动画视觉手感(拖层灵敏度等)属人工验收项。
- **kociemba 缺失时的两条自然降级路径**(实施记录声明):3 阶生成器缺失降级与计时模式 kociemba 缺失降级未自然触发实测(本机 kociemba 已装,smoke_bridge WCA 段跑通即为证);覆盖方式为 N≠3 降级断言 + 计时分支直驱断言(test_timer:214-219)走同一代码分支。
- 实施期各轮 selfCheck 中声明的其余隔离端口验证(18891/18925/18926 等)系各轮当时实测,本轮仅重验上表所列。

---

## 六、遗留事项与建议

**用户决策点(阻塞项,非代码问题)**:
1. **A-1 许可证取向**:**已决策并交付(2026-09-25)**——项目所有者选 GPL-3.0(动机:未来可合法并入同为 GPL 的上游实现),`LICENSE`(GNU GPL v3 官方全文)已写入仓库根目录,README「许可」节同步本项目代码许可与 `data/cfop.json` 的独立数据声明。
2. **A-2 上游许可确认**:**已完成(2026-09-25 备选路径)**——项目所有者裁决不走 issue 确认,直接以社区通用公式集重录:`tools/rebuild_cfop.py` 从 speedsolving wiki(OLL / First Two Layers / PLL 页,MediaWiki API)逐条重收集,记号转换(括号重复展开、`Rw`→`r`、`X3`→`X'`)后生成新 `data/cfop.json`(f2l 41(wiki 原编号,37=Solved 跳过)/ oll 57 / pll 21,共 614 条,丢弃 wiki 原文坏数据 3 条),全部 614 条经引擎数学验证(逆构造→正序复原,探针 614/614),全套测试与冒烟全绿。上游 lukejacksonn/cube 许可依赖消除;代拟的 issue 文本保留在 `docs/upstream-license-issue.md` 备用但无需发送。「公式本身不受版权保护,具体编排与呈现方式受」一语**转引自 docs/open-source-comparison.md:160**(调研报告 A-2 行动项原文),系调研报告的判断而非法律意见。

**代码/文档留后项(按影响排序)**:
3. **调研报告正文现状同步**(终审 4.2,部分处置 → 收尾轮已闭合最小版):d15/G1/G8/9.1/替代评估表等处的「无 CI」「WCA 仅计时模式」及行数快照已全部过时;收尾轮已在文档头部加「现状提示」指引(现状以文末交付状态盘点为准,过时条目点名),正文保留时点快照原文,待下次修订统一刷新。
4. **cfop.json 数字 case 名 '6.0' 显示**(终审 4.3 → 收尾轮已修):显示层与 key 构造统一整型化——main.gd 新增 `_case_name()`(JSON 数字 name 经 float 整数化取 '6'),`train_case_label` 与 `_train_case_id()` 均改用之;test_train_stats 新增 key 无 '.0' 形态防回归断言。`user://train_stats.cfg` 经查不存在(实施轮统计为新增功能、测试均重定向临时目录),无 key 迁移负担。
5. **A-7 facelet 导入通道**:中高成本,「实体魔方 → LBL 教学」闭环缺半环(docs:105),未排期。
6. **A-8 出现率与统计表**:deferred,归属 PLAN §16.3 P4 开工前专项 grill;当前单行简版已声明取舍(main.gd:717-720)。
7. **`_wca_scramble_alg` 无超时**(实施记录自曝):`OS.execute` 异常挂死会阻塞 UI(main.gd:169 ponytail 注释),上线程化前接受该上限。
8. **审计外相邻问题(未动,如实转记)**:「本轮修复」指处置轮对 test_train_stats E2E(见 3.3 R1-12)的修复;处置 note 注明相邻问题——`_on_train_new` 从**当前状态**而非复原态构造 case(main.gd:698-703:对当前态逐条叠加逆向公式)——未动。「语义兼容」为本报告基于本轮读码的判据:出题路径显式 `cube.moves = 0` 且清 `full_log`(main.gd:702-703),故无论从复原态还是当前态构造 case,完成判定的 `moves > 0` guard(4.1 条 2)前提——出题后有玩家净操作——均成立,统计正确性不受出题起点影响;残余风险仅在产品语义层:未复原时点「新 case」得到的起局状态并非该 case 的标准状态,属训练体验问题。现有 E2E 以 `_on_reset` 前置复现自然流程(test_train_stats.gd:134)未覆盖非复原态出题分支。

**建议的下一步**(一条即可动手):在补齐 LICENSE 决策后,把仓库 init 为 git 仓库并推送远端,让 CI 的 Actions 编排从「未验证」变为可实测——这是当前唯一整段未经证据支持的交付物。
