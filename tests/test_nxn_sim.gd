extends SceneTree
## v7 P2 n 阶 facelet 模拟器对拍金标准(docs/v7-teach-nxn-plan.md P2):
## n=2..7 全阶,cube.gd apply_turn ↔ nxn 模拟器逐步一致(范式 tests/test_lbl.gd:86
## _test_simulator_parity);token 池按 n 扩到 {外层, nR, nRw} × {'', ',2},
## cube 侧走 parse_alg→apply_turn 链路(范式 tests/test_lbl.gd:107
## _test_parse_negative_axes),打乱态起步——内格映射错位在复原态不可见,必须打乱才测得出。
## 运行:godot --headless -s tests/test_nxn_sim.gd;任何断言失败 exit 1,全过 exit 0。
## 双校验口径:exit code 0 且输出无 SCRIPT ERROR(EXPERIENCE 假绿陷阱)。

const NS := preload("res://scripts/nxn_solver.gd")

const AXIS_OF := {
	"U": Vector3(0, 1, 0), "D": Vector3(0, -1, 0),
	"R": Vector3(1, 0, 0), "L": Vector3(-1, 0, 0),
	"F": Vector3(0, 0, 1), "B": Vector3(0, 0, -1),
}

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
	_test_outer_parity_all_n()
	_test_parse_chain_pool()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## 该阶合法 token 池(基 token;文法门槛随 n,cube.gd _parse_wca_token 单一规则源):
## 外层全阶;nR 3 ≤ d ≤ n-1、nRw 2 ≤ d ≤ n-1(n≥4 才开放,同小写宽转门槛)。
func _pool(n: int) -> Array:
	var pool: Array = []
	for face in ["U", "D", "R", "L", "F", "B"]:
		pool.append(face)
		if n >= 4:
			for d in range(3, n):
				pool.append("%d%s" % [d, face])
			for d in range(2, n):
				pool.append("%d%sw" % [d, face])
	return pool


## TNS-1 外层对拍(范式 test_lbl.gd:86):n=2..7 各 60 步随机外层 token,
## cube apply_turn 直接语义路径(layers=[E])与 NS._apply_token 逐步比对。
func _test_outer_parity_all_n() -> void:
	var ok_all := true
	for nn in range(2, 8):
		_cube.setup(nn)
		var sim: PackedByteArray = _cube.to_facelets()
		seed(20260925 + nn)
		var ok := true
		for i in 60:
			var token: String = ["U", "D", "R", "L", "F", "B"][randi() % 6] + ["", "'", "2"][randi() % 3]
			var axis: Vector3 = AXIS_OF[token[0]]
			var angle := -PI / 2  # 顺时针(§3.1,与 cube bake 同向)
			if token.ends_with("2"):
				angle = PI
			elif token.ends_with("'"):
				angle = PI / 2
			_cube.apply_turn(axis, [nn - 1], angle)
			NS._apply_token(sim, token)
			if _cube.to_facelets() != sim:
				ok = false
				printerr("  n=%d 对拍不一致 @step %d token %s" % [nn, i, token])
				break
		if not ok:
			ok_all = false
	_check(ok_all, "TNS-1 外层置换 n=2..7 与 cube.gd 逐步一致(每阶 60 步随机,范式 test_lbl:86)")


## TNS-2 全池对拍:n=2..7,token 池 {外层, nR, nRw} × {'', ',2} 全量逐 token,
## cube 侧 parse_alg→apply_turn(覆盖 P0 parse 层→bake 链路),模拟器 NS._apply_token,
## 打乱态起步且整池连续演化(内格映射错位必须测得出)。
func _test_parse_chain_pool() -> void:
	var rng := RandomNumberGenerator.new()
	var ok_all := true
	for nn in range(2, 8):
		_cube.setup(nn)
		rng.seed = 20260925 + nn
		_cube.scramble({2: 11, 3: 25, 4: 40, 5: 60, 6: 80, 7: 100}.get(nn, 100), rng)
		var sim: PackedByteArray = _cube.to_facelets()
		var pool: Array = _pool(nn)
		var ok := true
		var count := 0
		for base in pool:
			for suf in ["", "'", "2"]:
				var token: String = String(base) + suf
				var steps: Array = _cube.parse_alg(token)
				if steps.is_empty():
					ok = false
					printerr("  n=%d 池内 token %s parse_alg 拒绝" % [nn, token])
					break
				for s in steps:
					_cube.apply_turn(s.axis, s.layers, s.angle)
				NS._apply_token(sim, token)
				count += 1
				if _cube.to_facelets() != sim:
					ok = false
					printerr("  n=%d token %s(%d/%d)后对拍不一致" % [nn, token, count, pool.size() * 3])
					break
			if not ok:
				break
		if not ok:
			ok_all = false
	_check(ok_all, "TNS-2 全池 {外层,nR,nRw}×{'',',2} parse_alg→apply_turn 链路 n=2..7 对拍一致(打乱态起步)")
