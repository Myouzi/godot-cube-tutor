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

## 渲染争议仲裁
- 多模态模型逐格读 3D 透视截图**不可靠**:同一张魔方截图三次独立读数互相矛盾,甚至出现"中心块变色"级幻觉;多轮读图对质无意义。
- "渲染 vs 逻辑"争议用像素级探针确定性裁决(已留在仓库):`tests/sticker_probe.gd` 从游戏内导出每个朝向相机贴纸的屏幕投影坐标+预期 albedo → `tools/probe_pixels.py` 采样 PNG 像素做最近色分类比对,100% 匹配即渲染正确。
- 审读魔方截图别把"每色恒 9"守恒律套到可见三面:守恒只对全 54 贴纸成立,任一视角可见 27 格的分布必然不均(隐藏面补齐)。

## 环境坑
- 游戏内 TCP 服务器端口被旧实例占用时按规格降级继续运行,桥连上的可能是**旧进程**(缺新命令)→ 冒烟测试报 unknown cmd。先 `pgrep -af godot` + 查 8788,kill 旧运行实例(`--editor` 编辑器本体不监听,别误杀)。
- 本机 nc 是 OpenBSD 变体(Debian 1.234),没有 `-q`;TCP 半关收尾用 `timeout 3 nc -N`。
- PyPI 直连被重置(ConnectionResetError 104),pip 装包走清华镜像:`-i https://pypi.tuna.tsinghua.edu.cn/simple`。
- GitHub 主站超时,但 `raw.githubusercontent.com` / `api.github.com` / `codeload.github.com` 直连可用;clone 换 codeload tar.gz 或镜像站。
