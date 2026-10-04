extends SceneTree
## v7 P0 记号底座单元测试(docs/v7-teach-nxn-plan.md P0 + 审计裁决 Q4):
## to_facelets 泛化(6n²、3 阶 54 字节回归)/ 数字前缀内层 dR 与宽层 dRw 解析结构 /
## 代数自洽(3R·3R' 复原、3R×4 复原、nRw 层数数学,纯 apply_turn 路径)/
## 非法 token 拒绝 / 长度上限放宽。
## 运行:godot --headless -s tests/test_nxn_notation.gd;任何断言失败 exit 1,全过 exit 0。

var _cube: Node3D
var _failed := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		_failed = true
		printerr("FAIL  " + msg)


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	while _cube.get_child_count() == 0:  # 等首帧 setup(3) 完成(同 self_test)
		await process_frame
	_test_facelets_generalized()
	_test_facelets_n3_regression()
	_test_parse_structure()
	_test_parse_rejects()
	_test_length_relaxed()
	_test_algebra_self_consistent()
	await _test_play_alg_smoke()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## 按解析步瞬时 bake(数学验证统一走纯 apply_turn 路径,不经动画)。
func _apply_alg(alg: String) -> void:
	for s in _cube.parse_alg(alg):
		_cube.apply_turn(s.axis, s.layers, s.angle)


## 步级逆序取反回放(免文本 invert;PI 取反仍 180°)。
func _apply_alg_inverse(steps: Array) -> void:
	for i in range(steps.size() - 1, -1, -1):
		_cube.apply_turn(steps[i].axis, steps[i].layers, -steps[i].angle)


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 20260925
	return r


## 各阶 facelets 泛化:6n² 长度、复原态面序(色 fi 连续 n² 格)、打乱后各色 n² 守恒。
func _test_facelets_generalized() -> void:
	var ok := true
	for nn in range(2, 8):
		_cube.setup(nn)
		var fs: PackedByteArray = _cube.to_facelets()
		if fs.size() != 6 * nn * nn:
			ok = false
			printerr("  n=%d facelets.size=%d 期望 %d" % [nn, fs.size(), 6 * nn * nn])
			continue
		for fi in 6:
			for k in nn * nn:
				if fs[fi * nn * nn + k] != fi:
					ok = false
					printerr("  n=%d 复原态面 %d 格 %d 异色" % [nn, fi, k])
		_cube.scramble(11, _rng())
		var cnt := {}
		for v in _cube.to_facelets():
			cnt[v] = int(cnt.get(v, 0)) + 1
		for fi in 6:
			if int(cnt.get(fi, 0)) != nn * nn:
				ok = false
				printerr("  n=%d 打乱后色 %d 计数 %s" % [nn, fi, cnt])
	_check(ok, "TN1 n=2..7 facelets 6n²、复原面序沿 FACES、打乱后各色 n² 守恒")


## 3 阶逐字节回归:54 字节 + 复原序 URFDLB 面序与旧版一致(既有 test_lbl 对拍
## 60 步 / T15 金标准全绿即旧输出逐字节不变的回归网)。
func _test_facelets_n3_regression() -> void:
	_cube.setup(3)
	var expect := PackedByteArray()
	for fi in 6:
		for k in 9:
			expect.append(fi)
	var fs: PackedByteArray = _cube.to_facelets()
	_check(fs.size() == 54 and fs == expect, "TN2 3 阶 54 字节且复原序逐字节不变(回归)")
	_cube.scramble(25, _rng())
	var fs2: PackedByteArray = _cube.to_facelets()
	var cnt := {}
	for v in fs2:
		cnt[v] = int(cnt.get(v, 0)) + 1
	var keep := fs2.size() == 54
	for fi in 6:
		keep = keep and int(cnt.get(fi, 0)) == 9
	_check(keep, "TN2 3 阶打乱后仍 54 字节、每色 9(回归)")


## parse_alg 输出结构:层换算 n-1-2k、负轴同式、宽层层数、角度语义。
func _test_parse_structure() -> void:
	var cs: GDScript = load("res://scripts/cube.gd")
	# 3 阶外层回归(既有语义不变)
	_cube.setup(3)
	var st: Dictionary = _cube.parse_alg("R")[0]
	_check(st.axis == Vector3.RIGHT and st.layers == [2] and st.angle == -PI / 2,
			"TN3 3 阶 parse_alg('R') = R 轴外层顺时针(回归)")
	# 数字单内层:第 d 层 gp·axis = n-1-2(d-1)
	_cube.setup(5)
	var s3: Dictionary = _cube.parse_alg("3R")[0]
	_check(s3.axis == Vector3.RIGHT and s3.layers == [0] and s3.angle == -PI / 2,
			"TN3 n=5 '3R' = 中央层(R 面起第 3 层)顺时针")
	_check(_cube.parse_alg("3R'")[0].angle == PI / 2 and _cube.parse_alg("3R2")[0].angle == PI,
			"TN3 '3R'' = +90°、'3R2' = 180°")
	_check(_cube.parse_alg("4R")[0].layers == [-2], "TN3 n=5 '4R' = 第 4 层(gp·axis=-2)")
	_check(_cube.parse_alg("3D")[0].axis == Vector3.DOWN and _cube.parse_alg("3D")[0].layers == [0],
			"TN3 n=5 '3D' 负轴面同式落中央层")
	# 数字宽层:该面起外 d 层一次转
	_check(_cube.parse_alg("3Rw")[0].layers == [4, 2, 0], "TN3 n=5 '3Rw' = 外三层 [4,2,0]")
	_cube.setup(7)
	_check(_cube.parse_alg("4Rw")[0].layers == [6, 4, 2, 0], "TN3 n=7 '4Rw' = 外四层 [6,4,2,0]")
	_cube.setup(4)
	_check(_cube.parse_alg("2Rw")[0].layers == [3, 1], "TN3 n=4 '2Rw' = 双层 [3,1]")
	_check(_cube.parse_alg("3D")[0].layers == [-1], "TN3 n=4 '3D' = D 面起第 3 层(gp·axis=-1)")
	# 小写双层语义不变(§17.2 回归)
	_check(_cube.parse_alg("u")[0].layers == [3, 1] and _cube.parse_alg("u")[0].angle == -PI / 2,
			"TN3 n=4 小写 'u' 双层语义不变(回归)")
	# 混合串逐 token 结构 + 混入非法整体拒绝
	_cube.setup(5)
	var mix: Array = _cube.parse_alg("3R U 4Rw'")
	_check(mix.size() == 3 and mix[2].layers == [4, 2, 0, -2] and mix[2].angle == PI / 2,
			"TN3 混合串 '3R U 4Rw'' 3 步,外四层逆时针")
	_check(_cube.parse_alg("3R 2R") == [], "TN3 混入 2R 整批拒绝")
	_check(cs.is_valid_wca_token("3Rw2", 5) and _cube.parse_alg("3Rw2")[0].angle == PI,
			"TN3 '3Rw2' = 180°")


## 非法 token 拒绝:2R 全阶禁、3 阶记号集最小、深度越界、文法外形态、垃圾。
func _test_parse_rejects() -> void:
	var cs: GDScript = load("res://scripts/cube.gd")
	# 裁决 Q4:不加 2R(两层联动已有小写宽转,单留 2R 徒增与 R2 手滑歧义)
	var all_reject := true
	for nn in range(3, 8):
		if cs.is_valid_wca_token("2R", nn):
			all_reject = false
			printerr("  n=%d 意外接受 2R" % nn)
	_check(all_reject, "TN4 2R 在 n=3..7 全部拒绝(裁决 Q4)")
	# 3 阶记号集最小(§17.2):数字前缀与小写宽转同门槛 n≥4
	_check(not cs.is_valid_wca_token("3R", 3) and not cs.is_valid_wca_token("2Rw", 3)
			and not cs.is_valid_wca_token("3Rw", 3) and not cs.is_valid_wca_token("r", 3),
			"TN4 3 阶拒绝 3R/2Rw/3Rw/r(记号集最小)")
	# 深度越界:d=N 即对面外层,须用对面字母表述
	_check(not cs.is_valid_wca_token("4R", 4) and not cs.is_valid_wca_token("4Rw", 4),
			"TN4 n=4 拒绝 4R/4Rw(越界)")
	_check(not cs.is_valid_wca_token("5R", 5) and not cs.is_valid_wca_token("5Rw", 5),
			"TN4 n=5 拒绝 5R/5Rw(d=N 为对面外层)")
	_check(not cs.is_valid_wca_token("7R", 7) and not cs.is_valid_wca_token("7Rw", 7),
			"TN4 n=7 拒绝 7R/7Rw")
	# 数字前缀配小写 / 大写配 w 无此记号
	_check(not cs.is_valid_wca_token("2r", 5) and not cs.is_valid_wca_token("3rw", 5)
			and not cs.is_valid_wca_token("rw", 5) and not cs.is_valid_wca_token("Rw", 5),
			"TN4 拒绝 2r/3rw/rw/Rw(文法外形态)")
	# 垃圾与重复修饰符(既有语义保持)
	_check(not cs.is_valid_wca_token("3Rww", 5) and not cs.is_valid_wca_token("11R", 5)
			and not cs.is_valid_wca_token("3R4", 5) and not cs.is_valid_wca_token("'R", 5)
			and not cs.is_valid_wca_token("3", 5) and not cs.is_valid_wca_token("0R", 5)
			and not cs.is_valid_wca_token("", 5),
			"TN4 拒绝垃圾 token(3Rww/11R/3R4/'R/3/0R/空)")
	_check(not cs.is_valid_wca_token("R''", 3) and not cs.is_valid_wca_token("R22", 3),
			"TN4 重复修饰符 R''/R22 仍拒绝(回归)")
	_check(cs.is_valid_wca_token("R2'", 3) and cs.is_valid_wca_token("R'2", 3),
			"TN4 R2'/R'2 仍合法 ≡ R2(回归)")


## 长度上限放宽:旧 length>3 截断 4 字符的 3Rw'/3Rw2;放宽后放行且文法仍严格。
func _test_length_relaxed() -> void:
	var cs: GDScript = load("res://scripts/cube.gd")
	_check(cs.is_valid_wca_token("3Rw'", 5) and cs.is_valid_wca_token("3Rw2", 5),
			"TN5 4 字符 token 3Rw'/3Rw2 放行(长度上限放宽生效)")
	_check(cs.is_valid_wca_token("3R2'", 5) and cs.is_valid_wca_token("3Rw2'", 5),
			"TN5 等价形 3R2'≡3R2、3Rw2'≡3Rw2 放行(修饰符任意顺序文法一致)")
	_check(not cs.is_valid_wca_token("3Rw2'2", 5) and not cs.is_valid_wca_token("33Rw2", 5),
			"TN5 6 字符/双数字仍拒绝(上限粗筛,文法把关)")
	_cube.setup(5)
	_check(_cube.parse_alg("3Rw'")[0].angle == PI / 2 and _cube.parse_alg("3Rw2")[0].angle == PI
			and _cube.parse_alg("3Rw'")[0].layers == [4, 2, 0],
			"TN5 parse_alg 4 字符 token 完整链路(angle/layers 正确)")


## 代数自洽(纯 apply_turn):dR/dRw 群阶、层数换算、复合公式可逆。
func _test_algebra_self_consistent() -> void:
	# 单内层:3R·3R' = 恒等,3R×4 = 恒等;负轴同验
	_cube.setup(5)
	_apply_alg("3R 3R'")
	_check(_cube.is_solved(), "TN6 n=5 3R·3R' 复原")
	_apply_alg("3R 3R 3R 3R")
	_check(_cube.is_solved(), "TN6 n=5 3R×4 复原")
	_apply_alg("3D 3D'")
	_check(_cube.is_solved(), "TN6 n=5 3D·3D' 复原(负轴)")
	_apply_alg("3D 3D 3D 3D")
	_check(_cube.is_solved(), "TN6 n=5 3D×4 复原(负轴)")
	# 宽层:3Rw×4 = 恒等
	_apply_alg("3Rw 3Rw 3Rw 3Rw")
	_check(_cube.is_solved(), "TN6 n=5 3Rw×4 复原")
	# dRw 层数数学:一次 dRw == d 次单层叠加(仿 T-wide TW3 范式)
	_cube.setup(5)
	_apply_alg("2Rw")
	var wide_fs: PackedByteArray = _cube.to_facelets()
	_cube.setup(5)
	_cube.apply_turn(Vector3.RIGHT, [4], -PI / 2)
	_cube.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	_check(_cube.to_facelets() == wide_fs, "TN6 n=5 2Rw 一次 == [4]+[2] 两次单层叠加")
	_cube.setup(6)
	_apply_alg("3Rw")
	var w6: PackedByteArray = _cube.to_facelets()
	_cube.setup(6)
	for l in [5, 3, 1]:
		_cube.apply_turn(Vector3.RIGHT, [l], -PI / 2)
	_check(_cube.to_facelets() == w6, "TN6 n=6 3Rw 一次 == [5]+[3]+[1] 三次单层叠加")
	# 单内层与宽层换算交叉:dR(第 d 层单转)== dRw·(d-1)Rw'(外 d 层 · 逆外 d-1 层)
	_cube.setup(4)
	_apply_alg("3R")
	var inner_fs: PackedByteArray = _cube.to_facelets()
	_cube.setup(4)
	_apply_alg("3Rw 2Rw'")
	_check(_cube.to_facelets() == inner_fs, "TN6 n=4 3R == 3Rw·2Rw'(层数换算自洽)")
	# 复合公式可逆:应用后逆序取反回放复原
	_cube.setup(6)
	var steps: Array = _cube.parse_alg("3R 4Rw2 5R' 2Rw U'")
	for s in steps:
		_cube.apply_turn(s.axis, s.layers, s.angle)
	_apply_alg_inverse(steps)
	_check(_cube.is_solved(), "TN6 n=6 复合 nR/nRw 公式逆序回放复原")


## play_alg 端到端冒烟:解析→入队→动画→记账对新记号透明(队列清零轮询,T-wide 范式)。
func _test_play_alg_smoke() -> void:
	_cube.setup(5)
	var queued: int = _cube.play_alg("3Rw' 3Rw")
	while _cube.is_animating():
		await process_frame
	_check(queued == 2 and _cube.is_solved() and _cube.moves == 0 and _cube.full_log.size() == 2,
			"TN7 play_alg('3Rw' 3Rw') n=5 入队 2 步、播放后复原、ALG 记账语义不变")
