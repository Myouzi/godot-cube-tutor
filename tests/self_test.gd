extends SceneTree
## 魔方核心自测:§7.1 测试 1-6(N=3)+ §7.2 测试 7-9(N=4 冒烟)。
## 运行:godot --headless -s tests/self_test.gd;任何断言失败 exit 1,全过 exit 0。
## 动画路径测试(play_alg/undo)经 Engine.time_scale 提速,插值与 bake 数学不受影响。

var _cube: Node3D


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		quit(1)  # SceneTree.quit(1):进程退出码 1(4.7 无 OS.exit)


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	# -s 模式下节点 _ready 延迟到首帧 root READY;先等其初始化 setup(3) 完成,
	# 否则首帧的自动 setup 会重置测试中途的状态。
	while _cube.get_child_count() == 0:
		await process_frame
	Engine.time_scale = 20.0
	_test_1()
	_test_2()
	_test_3()
	await _test_4()
	_test_5()
	await _test_6()
	_test_7()
	_test_8()
	_test_9()
	_test_10()
	await _test_11()
	await _test_12()
	await _test_13()
	_test_14()
	await _test_15()
	Engine.time_scale = 1.0
	print("ALL PASSED")
	quit(0)


func _turn(axis: Vector3, angle: float, e: int) -> void:
	_cube.apply_turn(axis, [e], angle)


func _pos_set() -> Dictionary:
	var s := {}
	for c in _cube.cubies:
		s[str(c.grid_pos)] = true
	return s


## 测试 1:(R U R' U') × 6 → solved 且 grid_pos 集合还原(方向写反金标准)。
func _test_1() -> void:
	_cube.setup(3)
	var before := _pos_set()
	for i in 6:
		_turn(Vector3.RIGHT, -PI / 2, 2)
		_turn(Vector3.UP, -PI / 2, 2)
		_turn(Vector3.RIGHT, PI / 2, 2)
		_turn(Vector3.UP, PI / 2, 2)
	_check(_cube.is_solved(), "T1 (R U R' U')x6 -> solved")
	_check(_pos_set() == before, "T1 grid_pos 集合还原")


## 测试 2:100 步随机(含中层)→ 坐标集合 == 外露块全集;basis 元素偏差 < 1e-6。
func _test_2() -> void:
	_cube.setup(3)
	seed(20260924)
	var axes := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var depths := [-2, 0, 2]
	for i in 100:
		var axis: Vector3 = axes[randi() % 6]
		var layer: int = depths[randi() % 3]
		var angle := PI / 2 if randi() % 2 == 0 else -PI / 2
		_cube.apply_turn(axis, [layer], angle)
	_check(_cube.cubies.size() == 26, "T2 cubie 数 26")
	var expected := {}
	for x in depths:
		for y in depths:
			for z in depths:
				if absi(x) == 2 or absi(y) == 2 or absi(z) == 2:
					expected[str(Vector3i(x, y, z))] = true
	_check(_pos_set() == expected, "T2 坐标集合 == 外露块全集")
	var ok_range := true
	var ok_basis := true
	for c in _cube.cubies:
		if absi(c.grid_pos.x) > 2 or absi(c.grid_pos.y) > 2 or absi(c.grid_pos.z) > 2:
			ok_range = false
		for col in [c.basis.x, c.basis.y, c.basis.z]:
			for k in 3:
				if absf(col[k] - roundf(col[k])) >= 1e-6:
					ok_basis = false
	_check(ok_range, "T2 grid_pos 分量 ∈ {-2,0,2}")
	_check(ok_basis, "T2 basis 元素偏差 < 1e-6")


## 测试 3:cube.scramble(25)(过滤同轴连续)→ 逆序回放 → solved(§7.1 条目 3 + §4 打乱要求)。
## 注:§4 规定 scramble 完成清空撤销栈,故"逆序撤销"以 full_log 逆序取反 apply 等价实现(同 T11)。
func _test_3() -> void:
	_cube.setup(3)
	_cube.scramble(25)
	_check(not _cube.is_solved(), "T3 打乱 25 后非 solved")
	_check(_cube.moves == 0 and _cube._undo_stack.is_empty(), "T3 打乱清空撤销栈与步数(§4)")
	_check(_cube.full_log.size() == 25, "T3 full_log 记 25 条打乱步")
	var ok_filter: bool = _cube.full_log.size() == 25
	for i in range(1, _cube.full_log.size()):
		if _cube.full_log[i].axis == _cube.full_log[i - 1].axis:
			ok_filter = false
	_check(ok_filter, "T3 scramble 过滤同轴连续(§4)")
	var log_copy: Array = _cube.full_log.duplicate()
	for i in range(log_copy.size() - 1, -1, -1):
		var t: Dictionary = log_copy[i]
		_cube.apply_turn(t.axis, t.layers, -t.angle)
	_check(_cube.is_solved(), "T3 逆序取反回放 -> solved")


## 测试 4:单步 R → 非 solved,撤销 → solved。
func _test_4() -> void:
	_cube.setup(3)
	_turn(Vector3.RIGHT, -PI / 2, 2)
	_check(not _cube.is_solved(), "T4 单步 R 后非 solved")
	while not _cube.undo():
		await process_frame
	while _cube.is_animating():
		await process_frame
	_check(_cube.is_solved(), "T4 undo -> solved")
	_check(_cube.moves == 0, "T4 moves 归 0")


## 测试 5:to_facelets() 标准符合性:复原序 + 4 角环 + R 转后 U→B→D→F 环。
func _test_5() -> void:
	_cube.setup(3)
	var f: PackedByteArray = _cube.to_facelets()
	_check(f.size() == 54, "T5 facelets 长 54")
	var ok_solved := true
	for fi in 6:
		for k in 9:
			if f[fi * 9 + k] != fi:
				ok_solved = false
	_check(ok_solved, "T5 solved 态 == URFDLB 复原序")
	# Kociemba 角环锚点(0-based):URF=(U9,R1,F3)=(8,9,20) ULB=(U1,L1,B3)=(0,36,47)
	# DFR=(D3,F9,R7)=(29,26,15) DBL=(D7,B9,L7)=(33,53,42)
	_check(f[8] == 0 and f[9] == 1 and f[20] == 2, "T5 角环 URF")
	_check(f[0] == 0 and f[36] == 4 and f[47] == 5, "T5 角环 ULB")
	_check(f[29] == 3 and f[26] == 2 and f[15] == 1, "T5 角环 DFR")
	_check(f[33] == 3 and f[53] == 5 and f[42] == 4, "T5 角环 DBL")
	var before: PackedByteArray = _cube.to_facelets()
	_turn(Vector3.RIGHT, -PI / 2, 2)
	var after: PackedByteArray = _cube.to_facelets()
	_check(after[45] == before[8] and after[48] == before[5] and after[51] == before[2],
			"T5 R: U 右列 -> B c0 整列(逆序)")
	_check(after[2] == before[20] and after[5] == before[23] and after[8] == before[26],
			"T5 R: F 右列 -> U 右列")
	_check(after[20] == before[29] and after[23] == before[32] and after[26] == before[35],
			"T5 R: D 右列 -> F 右列")
	_check(after[29] == before[51] and after[32] == before[48] and after[35] == before[45],
			"T5 R: B c0 -> D 右列(逆序)")


## 测试 6:play_alg("R U R' U'") 与逐键产生相同 facelets,步数不计。
func _test_6() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	var ca = script.new()
	var cb = script.new()
	root.add_child(ca)
	root.add_child(cb)
	ca.setup(3)
	cb.setup(3)
	var queued: int = ca.play_alg("R U R' U'")
	_check(queued == 4, "T6 play_alg 入队 4 步")
	_check(ca.is_programmatic(), "T6 播放期间程序化标志为真")
	while ca.is_animating():
		await process_frame
	cb.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	cb.apply_turn(Vector3.UP, [2], -PI / 2)
	cb.apply_turn(Vector3.RIGHT, [2], PI / 2)
	cb.apply_turn(Vector3.UP, [2], PI / 2)
	_check(ca.to_facelets() == cb.to_facelets(), "T6 play_alg 与逐键 facelets 一致")
	_check(ca.moves == 0, "T6 play_alg 步数不计")
	_check(cb.moves == 4, "T6 逐键步数计 4")
	_check(not ca.is_programmatic(), "T6 播放结束程序化标志复位")
	ca.free()
	cb.free()


## 测试 7:setUp(4):cubie 数 56;坐标集合 == {±3,±1}³ 外露块。
func _test_7() -> void:
	_cube.setup(4)
	_check(_cube.cubies.size() == 56, "T7 N=4 cubie 数 56")
	var expected := {}
	for x in [-3, -1, 1, 3]:
		for y in [-3, -1, 1, 3]:
			for z in [-3, -1, 1, 3]:
				if absi(x) == 3 or absi(y) == 3 or absi(z) == 3:
					expected[str(Vector3i(x, y, z))] = true
	_check(_pos_set() == expected, "T7 坐标集合 == {±3,±1}³ 外露块")


## 测试 8:R×4、U×4 → solved 且集合不变。
func _test_8() -> void:
	_cube.setup(4)
	var before := _pos_set()
	for i in 4:
		_turn(Vector3.RIGHT, -PI / 2, 3)
	for i in 4:
		_turn(Vector3.UP, -PI / 2, 3)
	_check(_cube.is_solved(), "T8 R×4 U×4 -> solved")
	_check(_pos_set() == before, "T8 集合不变")


## 测试 9:cube.scramble(25) → 逆序回放 → solved(N=4,同 T3 方法,§7.2)。
func _test_9() -> void:
	_cube.setup(4)
	_cube.scramble(25)
	_check(not _cube.is_solved(), "T9 打乱 25 后非 solved")
	_check(_cube.moves == 0 and _cube._undo_stack.is_empty(), "T9 打乱清空撤销栈与步数(§4)")
	var ok_filter: bool = _cube.full_log.size() == 25
	for i in range(1, _cube.full_log.size()):
		if _cube.full_log[i].axis == _cube.full_log[i - 1].axis:
			ok_filter = false
	_check(ok_filter, "T9 scramble 25 步且过滤同轴连续(§4)")
	var log_copy: Array = _cube.full_log.duplicate()
	for i in range(log_copy.size() - 1, -1, -1):
		var t: Dictionary = log_copy[i]
		_cube.apply_turn(t.axis, t.layers, -t.angle)
	_check(_cube.is_solved(), "T9 逆序取反回放 -> solved")


## 测试 10:NDJSON 分发器直测(不起 socket):state 结构完整;scramble 后非 solved;
## reset 后 solved 且 full_log 清空;未知 cmd ok:false。
func _test_10() -> void:
	var server: Node = load("res://scripts/cube_server.gd").new()
	server.cube = _cube
	_cube.setup(3)
	var r: Dictionary = server.dispatch({"id": 10, "cmd": "state"})
	_check(r.ok == true, "T10 state ok")
	_check(String(r.data.facelets).length() == 54, "T10 state.facelets 长 54")
	_check(r.data.has("n") and r.data.has("solved") and r.data.has("moves")
			and r.data.has("animating") and r.data.has("queue_len"), "T10 state 结构完整")
	var r2: Dictionary = server.dispatch({"id": 11, "cmd": "scramble", "steps": 10})
	_check(r2.ok == true and r2.data.solved == false, "T10 scramble 后 solved=false")
	_check(r2.data.facelets != r.data.facelets, "T10 scramble 后 facelets 变化")
	var r3: Dictionary = server.dispatch({"id": 12, "cmd": "reset"})
	_check(r3.ok == true and r3.data.solved == true, "T10 reset 后 solved=true")
	_check(_cube.full_log.is_empty(), "T10 reset 后 full_log 清空")
	var r4: Dictionary = server.dispatch({"id": 13, "cmd": "bogus"})
	_check(r4.ok == false, "T10 未知 cmd ok:false")
	server.free()


## 测试 11:restore 数学:30 步(混 5 次 undo)后按 full_log 逆序取反逐条 apply →
## solved 且坐标全集不变——验证"undo 也入 log"与逆序回放正确性(§7.3)。
func _test_11() -> void:
	_cube.setup(3)
	seed(991)
	var before := _pos_set()
	var axes := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	var prev := Vector3.ZERO
	for i in 30:
		var axis: Vector3 = axes[randi() % 6]
		while axis == prev:
			axis = axes[randi() % 6]
		prev = axis
		var angle := PI / 2 if randi() % 2 == 0 else -PI / 2
		_turn(axis, angle, 2)
		if i % 6 == 5:
			while not _cube.undo():
				await process_frame
	while _cube.is_animating():
		await process_frame
	_check(_cube.full_log.size() == 35, "T11 full_log 记 35 条(30 玩家步+5 undo 步) 实际=%d moves=%d" % [_cube.full_log.size(), _cube.moves])
	var log_copy: Array = _cube.full_log.duplicate()
	for i in range(log_copy.size() - 1, -1, -1):
		var t: Dictionary = log_copy[i]
		_cube.apply_turn(t.axis, t.layers, -t.angle)
	_check(_cube.is_solved(), "T11 逆序取反回放 -> solved")
	_check(_pos_set() == before, "T11 坐标全集不变")


## 测试 12:socket 冒烟:起 CubeServer(18923),StreamPeerTCP 连 127.0.0.1 发一行,
## 收到合法 JSON 响应(§7.3)。
func _test_12() -> void:
	var server: Node = load("res://scripts/cube_server.gd").new()
	server.cube = _cube
	server.port = 18923  # 避让默认 8788(smoke 与游戏实例)
	_cube.setup(3)
	root.add_child(server)
	await process_frame
	var peer := StreamPeerTCP.new()
	_check(peer.connect_to_host("127.0.0.1", 18923) == OK, "T12 connect_to_host")
	var frames := 0
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.poll()
		frames += 1
		if frames > 600:
			_check(false, "T12 连接超时")
			server.free()
			return
		await process_frame
	peer.put_data("{\"id\":1,\"cmd\":\"state\"}\n".to_utf8_buffer())
	var buf := ""
	frames = 0
	while buf.find("\n") == -1:
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			buf += peer.get_data(avail)[1].get_string_from_utf8()
		frames += 1
		if frames > 600:
			_check(false, "T12 响应超时")
			peer.disconnect_from_host()
			server.free()
			return
		await process_frame
	var resp = JSON.parse_string(buf.get_slice("\n", 0))
	_check(resp is Dictionary and int(resp.get("id", -1)) == 1 and resp.get("ok") == true,
			"T12 收到合法 JSON 响应 id=1 ok=true")
	_check(String(resp.data.facelets).length() == 54, "T12 响应 facelets 长 54")
	peer.disconnect_from_host()
	server.free()


## 测试 13:追加语义:连续两次 apply_alg(第二条到达时第一条仍在播)→
## 两条全部执行,终态 == 依次独立执行(§7.4)。真实速率保证"仍在播"。
func _test_13() -> void:
	Engine.time_scale = 1.0
	var server: Node = load("res://scripts/cube_server.gd").new()
	server.cube = _cube
	_cube.setup(3)
	var r1: Dictionary = server.dispatch({"id": 20, "cmd": "apply_alg", "alg": "R U"})
	_check(r1.ok == true and r1.data.queued == 2, "T13 第一条 alg 入队 2 步")
	await process_frame  # 让第一条进入动画执行
	_check(_cube.is_animating(), "T13 第一条播放中")
	var r2: Dictionary = server.dispatch({"id": 21, "cmd": "apply_alg", "alg": "R' U'"})
	_check(r2.ok == true and r2.data.queued == 2, "T13 第二条 alg 追加入队(不清队列)")
	while _cube.is_animating():
		await process_frame
	var script: GDScript = load("res://scripts/cube.gd")
	var cb: Node3D = script.new()
	root.add_child(cb)
	cb.setup(3)
	cb.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	cb.apply_turn(Vector3.UP, [2], -PI / 2)
	cb.apply_turn(Vector3.RIGHT, [2], PI / 2)
	cb.apply_turn(Vector3.UP, [2], PI / 2)
	_check(_cube.to_facelets() == cb.to_facelets(), "T13 两次 apply_alg 终态 == 依次独立执行")
	_check(_cube.full_log.size() == 4, "T13 full_log 记 4 步不丢")
	cb.free()
	server.free()


## 测试 14:参数校验:steps 越界/非整数、非法 token、超长、空串、未知 cmd →
## 全部 ok:false 且状态零变化(§7.4)。
func _test_14() -> void:
	var server: Node = load("res://scripts/cube_server.gd").new()
	server.cube = _cube
	_cube.setup(3)
	var before: PackedByteArray = _cube.to_facelets()
	var cases := [
		{"id": 30, "cmd": "scramble", "steps": 0},
		{"id": 31, "cmd": "scramble", "steps": 101},
		{"id": 32, "cmd": "scramble", "steps": 2.5},
		{"id": 33, "cmd": "scramble", "steps": "25"},
		{"id": 34, "cmd": "apply_alg", "alg": "R X"},
		{"id": 35, "cmd": "apply_alg", "alg": "R U U2 R3"},
		{"id": 36, "cmd": "apply_alg", "alg": "R".repeat(2001)},
		{"id": 37, "cmd": "apply_alg", "alg": "R ".repeat(301).strip_edges()},
		{"id": 38, "cmd": "apply_alg", "alg": ""},
		{"id": 39, "cmd": "apply_alg", "alg": 42},
	]
	var all_rejected := true
	for c in cases:
		var r: Dictionary = server.dispatch(c)
		if r.ok != false:
			all_rejected = false
			printerr("  未拒绝: ", c)
	_check(all_rejected, "T14 非法参数全部 ok:false")
	_check(_cube.to_facelets() == before, "T14 状态零变化(facelets 不变)")
	_check(_cube.full_log.is_empty() and _cube.moves == 0, "T14 full_log/moves 零变化")
	server.free()


## 测试 15(整合期防回归):cube.play_alg 全记号实测 == lbl_solver facelet 模拟(同源金标准)。
## 负轴(D/L/B)此前因 _outer_layer 符号错转对面层——正轴断言/逆序自洽回放测不出,
## 由本条逐记号对照钉死。
func _test_15() -> void:
	var lbl: GDScript = load("res://scripts/lbl_solver.gd")
	if lbl == null:
		return
	_cube.setup(3)
	var ok := true
	for face in ["U", "D", "L", "R", "F", "B", "U'", "D'", "L'", "R'", "F'", "B'",
			"U2", "D2", "L2", "R2", "F2", "B2"]:
		_cube.setup(3)
		var engine_f: PackedByteArray = _cube.to_facelets().duplicate()
		lbl._apply_alg(engine_f, face)
		_cube.play_alg(face)
		while _cube.is_animating():
			await process_frame
		if _cube.to_facelets() != engine_f:
			ok = false
			printerr("  play_alg(%s) 实测 != 引擎模拟" % face)
	_check(ok, "T15 18 记号 play_alg 实测 == facelet 模拟(含全部负轴)")
