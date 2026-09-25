# Cube Tutor — Godot 魔方教学软件

3D 魔方教学与训练工具,Godot 4.7 / GDScript。"视觉即状态"架构(cubie 节点即数据,无贴纸置换表),支持 **2~7 阶**。设计与验收规格见 [PLAN.md](PLAN.md)。

## 功能

- **自由模式**:键盘转层、撤销/重置、打乱(3 阶且 kociemba 可用时优先 WCA 均匀序列,否则随机步并如实提示)、公式播放(输入框 + 播放按钮,WCA 记号;「速度」滑杆 0.05~0.90 秒/步即时生效)
- **教学**(限 3 阶):层先法逐块引导——右侧 7 阶段进度栏、当前块提示与分步公式、「演示下一步」/「自动完成本阶段」;转错阶段自动回退标红
- **计时**(限 3 阶):打乱后首操作自动起表、复原瞬间停表;历史成绩、AO5/AO12、单次最佳,持久化到 `user://times.cfg`;restore/reset/切模式作废当次;打乱与自由模式同口径(3 阶且 kociemba 可用时优先 WCA 均匀序列,序列显示在面板)
- **训练**(限 3 阶):CFOP 案例库离线出题(F2L 41 / OLL 57 / PLL 21,共 119 case),随机 case 构造 + 参考公式演示;打乱与自由模式同口径(优先 WCA);每案例成绩统计(次数/best/mean,持久化 `user://train_stats.cfg`)
- **NxN**:顶栏「N 阶」切换 2~7 阶,全参数化;Alt+字母宽转(4 阶以上);打乱对齐 WCA TNoodle 策略(内层/宽层混合随机,步数 40~100 随阶提升),内层可用拖层转动
- **MCP 外部控制**:游戏内 TCP NDJSON 服务器 + 零依赖 Python stdio 桥,外部 AI 可读状态、打乱、回放还原、LBL 求解、教学提示、Kociemba 最优解、WCA 均匀打乱

## 运行

```bash
godot   # 项目根执行;Godot 4.7.x
```

界面随窗口大小自动缩放。

## 操作

| 输入 | 行为 |
|---|---|
| `U D L R F B` | 转对应面 90°(顺时针) |
| `Shift` + 字母 | 反向转 |
| `Alt` + 字母 | 宽转双层(4 阶以上) |
| 左键按住魔方拖动 | 拖层:实时预览,松手吸附最近 90°(<15° 回弹不计步) |
| 左键空白处拖动 | 轨迹球全向旋转(自由滚转,可累积歪斜) |
| 滚轮 | 缩放视角(0.5~2 倍基准距离) |
| `Home` / 顶栏「回正」 | 复位视角(初始三视图姿态 + 基准距离) |
| 顶栏「速度」滑杆 | 调节公式播放/回放速度(0.05~0.90 秒/步,即时生效) |
| `Esc` | 拖层中 = 中断手势回弹;其余 = 退出程序 |

## MCP 桥接入

游戏运行中(监听 `127.0.0.1:8788`,单连接)执行:

```bash
python3 tools/mcp_bridge.py   # stdio,零强制依赖
```

工具:`cube_get_state` / `cube_scramble`(可选 `seed`,同 (seed, steps) 打乱序列可复现) / `cube_restore` / `cube_reset` / `cube_apply_alg` / `cube_solve` / `cube_hint` / `cube_solve_optimal` / `cube_scramble_wca`(可选 `seed`,同 seed 打乱序列可复现)。其中 `cube_solve_optimal`、`cube_scramble_wca` 依赖可选的 `kociemba` 包(未安装时工具仍列出,调用返回安装指引):

```bash
pip install kociemba -i https://pypi.tuna.tsinghua.edu.cn/simple  # PyPI 直连会被重置
```

## 测试

```bash
# 逻辑(headless):self_test / test_drag / test_scramble / test_scramble_ui / test_lbl / test_server / test_timer / test_view / test_wide / test_train_stats
# 注:test_scramble_ui / test_timer 的 WCA 断言依赖 python3 + kociemba(缺失会降级随机步而真红,非假绿)
godot --headless -s tests/self_test.gd
python3 -m py_compile tools/mcp_bridge.py tools/wca_scramble.py
python3 tools/wca_scramble.py          # WCA 生成器直跑(依赖 kociemba),应输出 "ok": true
python3 tests/smoke_bridge.py          # 起真实游戏进程 + 桥端到端;--port=N 指定隔离端口(避让常驻实例)

# 视觉(需要 X 会话):出 7 张截图到 out/
env DISPLAY=:0 godot --rendering-driver opengl3 -s tests/visual_test.gd
```

判定一律同时校验 exit code 与日志无 `SCRIPT ERROR`(退出码假绿陷阱见 [EXPERIENCE.md](EXPERIENCE.md))。

以上逻辑命令已有 CI:GitHub Actions(`.github/workflows/ci.yml`,ubuntu-latest + Godot 4.7.2 官方二进制)在 push/pull_request 时自动跑全部 headless 测试(双校验)、`py_compile`、WCA 生成器直跑与 `smoke_bridge --port=18925`;视觉测试需 X 会话,仍仅本地跑。

## 数据来源

- **来源仓库**:[lukejacksonn/cube](https://github.com/lukejacksonn/cube),文件 `src/algorithms.ts`
- **抓取 URL**:https://raw.githubusercontent.com/lukejacksonn/cube/master/src/algorithms.ts(master 分支,2026-09-24 抓取)
- **用途**:离线打包为 `data/cfop.json`(F2L 41 / OLL 57 / PLL 21,共 119 case、214 条公式),供 P4 CFOP 案例训练离线运行
- **处理方式**:仅做结构化(TS 数组 → JSON,`moves` 改名 `algs`,每条附加 `case` 唯一标识),数据本身不增删改;`probability` 字段按源数据原样保留

## 许可

- **本项目代码**:GPL-3.0(见 [LICENSE](LICENSE),2026-09-25 定稿)。选择 GPL 系使未来可合法并入同为 GPL 的上游实现(hkociemba、min2phase 的 GPLv3 侧、cstimer 等),代价是衍生作品须同许可开源。
- **上游数据**:`data/cfop.json` 来自 lukejacksonn/cube 仓库,该仓库**未附任何开源许可**(根目录无 LICENSE 文件,GitHub API license 检测为 null,`package.json` 亦无 license 字段,2026-09-24 核实),仅 README 文字声明 MIT。该数据文件作为独立的数据打包保留其来源与限制声明,不随本仓库 LICENSE 主张或授予权利;已向上游发起许可确认(issue 文本见 `docs/upstream-license-issue.md`),无果将以社区通用公式集重录替换。
