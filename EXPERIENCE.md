# 经验

## Godot 无头视觉验证
- 本机有 X 会话(`DISPLAY=:0`),无需 Xvfb:`godot --rendering-driver opengl3 -s tests/xxx.gd` 可渲染并截图。
- `--headless` 是 dummy 渲染器,截不了图;截图用 SceneTree 脚本里 `root.get_texture().get_image().save_png()`,延后几帧再截。
- 逻辑验证仍用 `godot --headless -s tests/self_test.gd`。
- 抗锯齿(opengl3 下默认无,斜边锯齿明显):`project.godot` 里 `[rendering] anti_aliasing/quality/msaa_3d=2`(4×)+ `screen_space_aa=1`(FXAA),两行配置,桌面 GPU 零感知开销。
- UI 随窗口缩放:`[display] window/size/stretch_mode="canvas_items"` + `stretch_aspect="expand"`;默认 disabled 时窗口可拉伸但 UI 元素不缩放。

## GDScript 坑
- 类型化数组不能直接字面量赋值:`game.snake = [Vector2i(...)]` 报错。先 `var arr: Array[Vector2i] = [...]` 再赋。
- Label 全屏锚点(`anchor_bottom = 1.0`)下 `offset_bottom` 是相对底边的偏移,写 `400` 会把文字顶出窗口外;窗口内定位用负值(如 `-240`)。
- 网格坐标从 0 开始:蛇头到 `x=0` 还没出界,撞墙判定是 `x < 0`。
- **`:=` 对 Variant 推断失败是 parse error 而非运行时错**:`@onready var cube = $CubeRoot`(无类型标注)后写 `var base := 1.7 * cube.n + 2.0`,`cube.n` 是 Variant,整个脚本加载失败。症状极具迷惑性——场景实例退化成无脚本的基类节点(如 Node3D),运行时报 `Nonexistent function 'xxx' in base 'Node3D'`,而函数明明存在于源码。对策:涉及无类型变量的表达式用显式类型标注(`var base: float = ...`)。
- **SceneTree 测试"退出码末尾统一判定"会假绿**:`_run()` 协程中途 SCRIPT ERROR 会终止协程、后续断言全部不执行,但已排队的 `quit(0)` 照常执行 → `ALL PASSED` + exit 0 的假象。回归判定必须同时校验 exit code 与日志中无 `SCRIPT ERROR`(如 `grep -c "SCRIPT ERROR"`)。

## 魔方领域坑
- **to_facelets 泛化:坑在下游契约连锁,不在公式本身**(v7 P0)。54 写死改 6n² 只是 `resize(6*n*n)` + 行列枚举随 n(沿用 FACES 表);真正的破坏面是所有按 54 假设的下游——求解引擎按 facelets 长度分派、NDJSON state 契约、mcp_bridge/smoke_bridge 的长度断言、test_server 的 N=4 拒绝断言。两条纪律:①以「3 阶 54 字节与旧版逐字节同构」为锚点,旧金标准(URFDLB 复原序 + 4 角环断言)回归钉死;②长度契约是破坏性协议变更,下游断言翻转必须与实现**同一提交**(v7 把 S3 翻转排 P7 与解禁同提交,审计曾抓出"翻转排 P8"的分期矛盾)。
- **2 阶态嵌入 3 阶必为非法态(奇偶陷阱,防复发)**:把 2 阶打乱态嵌入 3 阶(棱/中心填复原色)看似"少几块的合法态",实则无解——WCA 2 阶打乱 11 步,每步 90° 面转是角块 4 循环 = 奇置换,11 步叠加角置换恒奇(数值验证 20000/20000);而 3 阶群不变量 **sgn(角置换) = sgn(棱置换)**(每个 90° 面转同时给角与棱各乘一个 4 循环,两符号同步翻转),嵌入态棱置换恒等(偶)而角置换恒奇,违反不变量,不在 3 阶合法态群中(headless 金标准实跑 0/50 复现)。2 阶自身无棱块、不受此约束,嵌入后才受目标群约束。防复发:任何「把 N 阶态嵌入有棱魔方群」的设计,先验 sgn(角)=sgn(棱) 群不变量;v7 已裁决放弃嵌入,2 阶独立解法器(初学者法 3 段)。
- **借鉴红线:无 LICENSE 仓库只借结构思路,不取数**。lukejacksonn/cube(无 LICENSE)曾致 cfop.json 整体重录;GusEscanda/rubik-cube-solver 同样无 LICENSE,仅借鉴其 methods.json「分段树 × 槽位旋转 × 条件匹配」DSL 思路,公式从公共方法域收集重录(A-2 管线)。dwalton76/rubiks-cube-NxNxN-solver 为 MIT 可合法引用,但其 lookup-table + IDA 机器求解路线与教学引擎不同构,仅作降阶分段结构参照。

## CI 与自动化(GitHub Actions)
- headless E2E 等 `_process` 边沿的断言必须**轮询等条件**(上限 60 帧),固定「等 2 帧」在 CI 慢 runner 上时序 flaky(2026-09-25 首跑实证:本地干净 clone 10 测全过、同测试 30 连跑全过、119 case 全量探针全过,CI 仍挂);否定性断言(「不入账」)给 10 帧观察窗,窗口过小会假绿。
- **60 帧边沿轮询只适用短时序断言;长动画等待必须队列清零长轮询**(v7 P8 口径):4 阶教学「自动完成本阶段」100+ 步 × 0.18s ≈ 20-40s,远超 60 帧上限——等待须轮询 `animating`/`queue_len` 至双双清零(范式 `tests/visual_test.gd:147`,300 次 × 0.1s)。E2E 等待写法先问自己:等的是"某状态位翻转"(边沿,短窗)还是"一整段动画播完"(长轮询,分钟级)。
- **CI 时长预算数字**(v7 P8 定):基线实测 ≈0.7 min(GitHub Actions API,最近成功 run 44/34/38/44/44s),2 倍预算 ≈1.4 min;新增测试(尤其长 E2E)先按此预算核算,超预算先优化(段级缓存/减态数)再合入,防 CI 时长失控。
- 公开仓库的 Actions 诊断:`runs/{id}/logs` 与日志网页均需认证,jobs API 匿名只给 conclusion;`::error` **annotation 免认证可读**——CI 设计成失败时把输出尾部塞进 annotation 文本,当场定位根因,不用求 token。
- git push 走 SSH over 443(`~/.ssh/config`:`Host github.com → HostName ssh.github.com → Port 443`);https 无缓存凭证时免交互直接失败,配一次密钥永久免密。

## 渲染争议仲裁
- 多模态模型逐格读 3D 透视截图**不可靠**:同一张魔方截图三次独立读数互相矛盾,甚至出现"中心块变色"级幻觉;多轮读图对质无意义。
- "渲染 vs 逻辑"争议用像素级探针确定性裁决(已留在仓库):`tests/sticker_probe.gd` 从游戏内导出每个朝向相机贴纸的屏幕投影坐标+预期 albedo → `tools/probe_pixels.py` 采样 PNG 像素做最近色分类比对,100% 匹配即渲染正确。
- 审读魔方截图别把"每色恒 9"守恒律套到可见三面:守恒只对全 54 贴纸成立,任一视角可见 27 格的分布必然不均(隐藏面补齐)。

## 环境坑
- 游戏内 TCP 服务器端口被旧实例占用时按规格降级继续运行,桥连上的可能是**旧进程**(缺新命令)→ 冒烟测试报 unknown cmd。先 `pgrep -af godot` + 查 8788,kill 旧运行实例(`--editor` 编辑器本体不监听,别误杀)。
- 本机 nc 是 OpenBSD 变体(Debian 1.234),没有 `-q`;TCP 半关收尾用 `timeout 3 nc -N`。
- PyPI 直连被重置(ConnectionResetError 104),pip 装包走清华镜像:`-i https://pypi.tuna.tsinghua.edu.cn/simple`。
- GitHub 主站超时,但 `raw.githubusercontent.com` / `api.github.com` / `codeload.github.com` 直连可用;clone 换 codeload tar.gz 或镜像站。(2026-09-25 复测:主站恢复可达;push 仍走 SSH 443 更稳。)
- MediaWiki `api.php?action=parse&prop=wikitext` 对 Python urllib 默认 UA 返回 403,须自定义 User-Agent;拿 wikitext 源码比抓网页 HTML 稳(模板 `{{case}}`/`{{Alg}}` 可直接正则解析)。
