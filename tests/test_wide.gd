extends SceneTree
## NxN 宽转自测(PLAN §17/§18 T-wide):小写记号 3 阶拒绝 / N=4 双层同转(解析、
## 数学、play_alg 入队、协议校验感知 n)/ 阶数切换 reset 语义(§17.1)。
## 运行:godot --headless -s tests/test_wide.gd;任何断言失败 exit 1,全过 exit 0。

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
	Engine.time_scale = 20.0
	_test_lowercase_rejected_n3()
	_test_wide_parse_n4()
	await _test_wide_math_n4()
	_test_wide_play_alg_n4()
	_test_server_validates_by_n()
	_test_setup_resets()
	_test_sizes_smoke()
	Engine.time_scale = 1.0
	if _failed:
		printerr("FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)


## 小写合法性随阶数(§17.2):3 阶拒绝(记号集最小),大写不受影响。
func _test_lowercase_rejected_n3() -> void:
	_cube.setup(3)
	var cs: GDScript = load("res://scripts/cube.gd")
	_check(cs.is_valid_wca_token("u", 3) == false, "TW1 is_valid_wca_token('u', 3) = false")
	_check(cs.is_valid_wca_token("d2", 3) == false, "TW1 is_valid_wca_token('d2', 3) = false")
	_check(cs.is_valid_wca_token("U", 3) and cs.is_valid_wca_token("R'", 3),
			"TW1 大写记号 3 阶仍合法")
	_check(_cube.parse_alg("r u") == [], "TW1 parse_alg 小写 n=3 返回 [](拒绝)")
	_check(_cube.parse_alg("R U") != [], "TW1 parse_alg 大写 n=3 正常")
	_check(_cube.play_alg("u") == -1, "TW1 play_alg('u') n=3 拒绝(零入队)")
	_check(_cube.full_log.is_empty(), "TW1 拒绝后零状态变化")


## N=4 双层解析:小写 token 合法,步 = 该面 + 相邻内层两层一次动画(§17.2)。
func _test_wide_parse_n4() -> void:
	_cube.setup(4)
	var cs: GDScript = load("res://scripts/cube.gd")
	_check(cs.is_valid_wca_token("u", 4) and cs.is_valid_wca_token("u'", 4)
			and cs.is_valid_wca_token("u2", 4) and cs.is_valid_wca_token("l", 4),
			"TW2 小写 u/u'/u2/l 在 n=4 合法")
	var steps: Array = _cube.parse_alg("u")
	_check(steps.size() == 1, "TW2 parse_alg('u') 1 步")
	var s: Dictionary = steps[0]
	_check(s.axis == Vector3.UP, "TW2 u 轴 = UP")
	_check(s.layers == [3, 1], "TW2 u 双层 = [3, 1](外层+相邻内层,gp·axis 约定)")
	_check(s.angle == -PI / 2, "TW2 u 顺时针 = -90°")
	_check(_cube.parse_alg("d")[0].layers == [3, 1], "TW2 d 双层 = [3, 1](D 侧两层,gp·axis 恒正)")
	_check(_cube.parse_alg("u2")[0].angle == PI, "TW2 u2 = 180°")
	_check(_cube.parse_alg("u x") == [], "TW2 非法 token 混入仍整体拒绝")


## N=4 双层数学:u 一次双层 apply == 外层+内层两次单层叠加(facelets 对照)。
func _test_wide_math_n4() -> void:
	_cube.setup(4)
	var ref: Node3D = load("res://scripts/cube.gd").new()
	root.add_child(ref)
	ref.setup(4)
	ref.apply_turn(Vector3.UP, [3], -PI / 2)
	ref.apply_turn(Vector3.UP, [1], -PI / 2)
	_cube.apply_turn(Vector3.UP, [3, 1], -PI / 2)  # 与 parse_alg("u") 同参
	_check(_cube.to_facelets() == ref.to_facelets(), "TW3 u 双层一次 == 两次单层叠加")
	_check(not _cube.is_solved(), "TW3 双层转后非 solved")
	# u4 = 恒等(每层 4×90°);对照:双层 u 连续 4 次 → solved
	for i in 3:
		_cube.apply_turn(Vector3.UP, [3, 1], -PI / 2)
	_check(_cube.is_solved(), "TW3 u×4 → solved")
	# d2(底两层 180°)与分层对照
	_cube.setup(4)
	ref.setup(4)
	ref.apply_turn(Vector3.DOWN, [3], PI)
	ref.apply_turn(Vector3.DOWN, [1], PI)
	_cube.apply_turn(Vector3.DOWN, [3, 1], PI)
	_check(_cube.to_facelets() == ref.to_facelets(), "TW3 d2 双层 180° 对照一致")
	ref.free()
	while _cube.is_animating():
		await process_frame


## N=4 play_alg 小写入队(批量、ALG 语义、记 full_log 不计步)。
func _test_wide_play_alg_n4() -> void:
	_cube.setup(4)
	var queued: int = _cube.play_alg("u d' l2")
	_check(queued == 3, "TW4 play_alg('u d' l2') n=4 入队 3 步")
	while _cube.is_animating():
		await process_frame
	_check(_cube.full_log.size() == 3 and _cube.moves == 0, "TW4 ALG 语义:log 记 3 不计步")
	_check(not _cube.is_solved(), "TW4 u d' l2 后非 solved")
	_check(_cube.play_alg(invert3("u d' l2")) == 3, "TW4 逆序列可入队")
	while _cube.is_animating():
		await process_frame
	_check(_cube.is_solved(), "TW4 逆序列回放 → solved")


static func invert3(alg: String) -> String:
	var out: PackedStringArray = []
	var tokens := alg.split(" ", false)
	for i in range(tokens.size() - 1, -1, -1):
		var t := tokens[i]
		if t.ends_with("'"):
			t = t.substr(0, t.length() - 1)
		elif not t.ends_with("2"):
			t += "'"
		out.append(t)
	return " ".join(out)


## 协议校验感知 n(§17.2:is_valid_wca_token 带参后 validate_alg 共用单一规则源)。
func _test_server_validates_by_n() -> void:
	var server: Node = load("res://scripts/cube_server.gd").new()
	server.cube = _cube
	_cube.setup(3)
	_check(server.validate_alg("u") != "", "TW5 n=3 validate_alg('u') 非法")
	_cube.setup(4)
	_check(server.validate_alg("u") == "", "TW5 n=4 validate_alg('u') 合法")
	_check(server.validate_alg("u X") != "", "TW5 n=4 混入非法 token 仍拒绝")
	server.free()


## 阶数切换 reset 语义(§17.1):确认 = reset + setup(n),full_log/撤销/步数全清。
func _test_setup_resets() -> void:
	_cube.setup(4)
	_cube.apply_turn(Vector3.UP, [3, 1], -PI / 2)
	_cube.apply_turn(Vector3.RIGHT, [3], -PI / 2)
	_check(_cube.full_log.size() == 2 and _cube.moves == 2, "TW6 前置:N=4 造 2 步历史")
	_cube.setup(3)
	_check(_cube.is_solved(), "TW6 setup(3) 后复原态")
	_check(_cube.full_log.is_empty() and _cube.moves == 0 and _cube._undo_stack.is_empty(),
			"TW6 切换后 full_log/步数/撤销栈全清")
	_check(_cube.cubies.size() == 26, "TW6 切回 n=3 cubie 数 26")


## 2..7 阶 cubie 数冒烟:n³ − (n−2)³。
func _test_sizes_smoke() -> void:
	_cube.setup(3)  # 恢复 3 阶给后续测试
	var ok := true
	for nn in range(2, 8):
		_cube.setup(nn)
		var expect: int = pow(nn, 3) - pow(nn - 2, 3)
		if _cube.cubies.size() != expect:
			ok = false
			printerr("  n=%d cubies=%d 期望 %d" % [nn, _cube.cubies.size(), expect])
		if not _cube.is_solved():
			ok = false
	_check(ok, "TW7 n=2..7 cubie 数 == n³-(n-2)³ 且初始复原")
	_cube.setup(3)
