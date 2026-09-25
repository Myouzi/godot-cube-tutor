extends SceneTree
## LBL 教学引擎自测(PLAN §14/§18 T15 金标准)。
## 运行:godot --headless -s tests/test_lbl.gd;任何断言失败 exit 1,全过 exit 0。
## 执行器:cube.gd 实例 + 标准 WCA 语义转层(§3.1:顺时针 = Basis(normal, -PI/2))。
## 注:cube.parse_alg 的负轴选层 bug(_outer_layer 曾对 D/L/B 取反)已在 cube.gd
## 修复(恒返回 E);本测试保留 _apply_token_cube 直接语义路径,并在
## _test_parse_negative_axes 对 parse_alg→apply_turn 链路做负轴回归。

const Solver := preload("res://scripts/lbl_solver.gd")

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


## 标准 WCA 语义把一个 token 应用到 cube(正法线 + §3.1 顺时针约定)。
func _apply_token_cube(token: String) -> void:
	var axis: Vector3 = AXIS_OF[token[0]]
	var angle := -PI / 2
	if token.ends_with("2"):
		angle = PI
	elif token.ends_with("'"):
		angle = PI / 2
	_cube.apply_turn(axis, [2], angle)


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	# -s 模式下 _ready 延迟到首帧;等 setup(3) 完成(同 self_test)
	while _cube.get_child_count() == 0:
		await process_frame

	_test_remap()
	_test_simulator_parity()
	_test_parse_negative_axes()
	_test_stage_check_constructed()
	_test_golden_100()
	_test_stages_monotonic()
	_test_hint()
	_test_cross_guard()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## T15 remap 两型:逐面无撇映射 + 撇/2 原样保留 + 组合公式。
func _test_remap() -> void:
	var x2 := {"U": "D", "D": "U", "F": "B", "B": "F", "R": "R", "L": "L"}
	var z2 := {"U": "D", "D": "U", "F": "F", "B": "B", "R": "L", "L": "R"}
	var ok := true
	for face in ["U", "D", "F", "B", "R", "L"]:
		if Solver.remap(face, Solver.REMAP_X2) != x2[face]:
			ok = false
		if Solver.remap(face, Solver.REMAP_Z2) != z2[face]:
			ok = false
		if Solver.remap(face + "'", Solver.REMAP_X2) != x2[face] + "'":
			ok = false
		if Solver.remap(face + "2", Solver.REMAP_Z2) != z2[face] + "2":
			ok = false
	_check(ok, "remap 两型逐面映射正确且全无撇")
	_check(Solver.remap("R U R' U'", Solver.REMAP_X2) == "R D R' D'",
			"remap x2 组合公式(R→R)")
	_check(Solver.remap("R U R' U'", Solver.REMAP_Z2) == "L D L' D'",
			"remap z2 组合公式(R→L)")
	_check(Solver.REMAP_MODE == Solver.REMAP_Z2, "引擎采用 z2 型(源:白底绿前右橙左红)")


## T15 模拟器对拍:cube.gd apply_turn 与 solver facelet 置换逐步一致。
func _test_simulator_parity() -> void:
	_cube.setup(3)
	var sim: PackedByteArray = _cube.to_facelets()
	seed(20260924)
	var faces := ["U", "D", "R", "L", "F", "B"]
	var ok := true
	for i in 60:
		var token: String = faces[randi() % 6] + ["", "'", "2"][randi() % 3]
		_apply_token_cube(token)
		Solver._apply_token(sim, token)
		if _cube.to_facelets() != sim:
			ok = false
			printerr("  对拍不一致 @step %d token %s" % [i, token])
			break
	_check(ok, "solver facelet 置换与 cube.gd 逐步一致(60 步随机)")


## cube.parse_alg 负轴回归:D/L/B 单层(含 '/2)解析落本面外层(layers=[E]),
## 且 parse_alg→apply_turn 与 solver 独立置换逐步一致(_outer_layer 修复前负轴转到对面层;
## 3 阶小写是宽转记号、非法,故测大写单层)。
func _test_parse_negative_axes() -> void:
	_cube.setup(3)
	var ok := true
	var fs: PackedByteArray = _cube.to_facelets()
	for tok in ["D", "L", "B", "D'", "L2", "B2"]:
		var steps: Array = _cube.parse_alg(tok)
		if steps.size() != 1 or steps[0].layers != [2]:
			ok = false
			printerr("  parse_alg(%s) 未落本面外层: %s" % [tok, steps])
			break
		var ref: PackedByteArray = fs.duplicate()
		Solver._apply_token(ref, tok)
		_cube.apply_turn(steps[0].axis, steps[0].layers, steps[0].angle)
		fs = _cube.to_facelets()
		if fs != ref:
			ok = false
			printerr("  parse_alg(%s)→apply_turn 与置换参照不一致" % tok)
			break
	_check(ok, "parse_alg 负轴 d/l/b 单层落本面外层且与置换参照一致(修复回归)")


## T15 stage_check 构造态:复原态、单步破坏、solve 分段逐阶段。
func _test_stage_check_constructed() -> void:
	_cube.setup(3)
	var solved_fs: PackedByteArray = _cube.to_facelets()
	_check(Solver.stage_check(solved_fs) == 7, "stage_check(复原)=7")

	_apply_token_cube("D")
	var fs_d: PackedByteArray = _cube.to_facelets()
	_check(Solver.stage_check(fs_d) == 5, "stage_check(复原后 D)=5:D 面黄保持,角位/棱位破")

	_cube.setup(3)
	_apply_token_cube("F2")
	var fs_f2: PackedByteArray = _cube.to_facelets()
	_check(Solver.stage_check(fs_f2) == 0, "stage_check(复原后 F2)=0:白十字破且黄十字/角全破")

	_cube.setup(3)
	_apply_token_cube("R")
	var fs_r: PackedByteArray = _cube.to_facelets()
	_check(Solver.stage_check(fs_r) == 0, "stage_check(复原后 R)=0")


## 金标准:随机 100 态 → solve → 正向逐步 apply → 全部 solved 且 <160。
## 步数门依据:cube.gd 负轴选层修复后 6 面均匀分布实测最坏 156(2026-09-24,
## seed 999983;修复前 D/L/B 实际转对面层、scramble 分布偏浅,旧门 <150 是
## 偏浅分布上的经验值)。正确性断言(apply 后复原)不变。
## 另验逆向:解的逆从复原态 apply 回到打乱态(解是双向一致路径)。
func _test_golden_100() -> void:
	seed(999983)
	var ok_all := true
	var worst := 0
	for trial in 100:
		_cube.setup(3)
		_cube.scramble(25)
		var fs: PackedByteArray = _cube.to_facelets()
		var r: Dictionary = Solver.solve(fs)
		if not r.ok:
			ok_all = false
			printerr("  trial %d solve 失败: %s" % [trial, r.get("error", "?")])
			break
		var toks: int = Solver._token_count(r.alg)
		worst = maxi(worst, toks)
		if toks >= 160:
			ok_all = false
			printerr("  trial %d 步数 %d >= 160" % [trial, toks])
			break
		if int(r.moves) != toks:
			ok_all = false
			printerr("  trial %d moves 字段不一致" % trial)
			break
		for token in r.alg.split(" ", false):
			_apply_token_cube(token)
		if not _cube.is_solved():
			ok_all = false
			printerr("  trial %d 执行解后未复原" % trial)
			break
		if Solver.stage_check(_cube.to_facelets()) != 7:
			ok_all = false
			printerr("  trial %d 解后 stage_check != 7" % trial)
			break
		for token in Solver.invert_alg(r.alg).split(" ", false):
			_apply_token_cube(token)
		if _cube.to_facelets() != fs:
			ok_all = false
			printerr("  trial %d 逆序 apply 未回到打乱态" % trial)
			break
	_check(ok_all, "T15 金标准:100 随机态 solve→apply 全复原且步数<160(最坏 %d)" % worst)


## solve 分段单调性:每段执行后 stage_check 不低于该段阶段号
## (最后一段可能恰好一并完成后续阶段,故只断言下限;构造中间态逐阶段判定)。
func _test_stages_monotonic() -> void:
	seed(20260925)
	var ok := true
	for trial in 5:
		_cube.setup(3)
		_cube.scramble(25)
		var fs: PackedByteArray = _cube.to_facelets()
		var r: Dictionary = Solver.solve(fs)
		if not r.ok:
			ok = false
			break
		var replay: PackedByteArray = fs.duplicate()
		for si in range(r.stages.size()):
			Solver._apply_alg(replay, r.stages[si].alg)
			if Solver.stage_check(replay) < si + 1:
				ok = false
				printerr("  trial %d 阶段 %d 后 stage_check=%d" % [trial, si + 1, Solver.stage_check(replay)])
	_check(ok, "solve 分段:每段后 stage_check 不低于该阶段(5 态)")


## hint:建议执行后该 piece 块达成本阶段完成条件,且 stage_check 不降。
func _test_hint() -> void:
	seed(20260926)
	var ok := true
	for trial in 10:
		_cube.setup(3)
		_cube.scramble(25)
		var fs: PackedByteArray = _cube.to_facelets()
		var sc := Solver.stage_check(fs)
		var h: Dictionary = Solver.hint(fs)
		if h.get("stage", -1) != sc or not h.has("progress") or not h.has("suggestion"):
			ok = false
			printerr("  trial %d hint 结构不完整: %s" % [trial, h.keys()])
			break
		var sug: Dictionary = h.suggestion
		if sc == 7:
			if String(sug.get("alg", "x")) != "":
				ok = false
				printerr("  trial %d 复原态建议应为空" % trial)
			break
		if not sug.has("piece") or not sug.has("alg") or not sug.has("text") or String(sug.alg).is_empty():
			ok = false
			printerr("  trial %d suggestion 不完整: %s" % [trial, sug])
			break
		var t: PackedByteArray = fs.duplicate()
		Solver._apply_alg(t, sug.alg)
		if Solver.stage_check(t) < sc:
			ok = false
			printerr("  trial %d hint 执行后 stage 回退" % trial)
			break
		if not _piece_done(t, int(sc), String(sug.piece)):
			ok = false
			printerr("  trial %d piece %s 未达成本阶段条件" % [trial, sug.piece])
			break
	_check(ok, "hint:结构完整、piece 执行后归位、stage 不降(10 态)")


## piece 的阶段语境完成判定(stage 为 stage_check 原值;建议针对 sc+1 阶段)。
func _piece_done(fs: PackedByteArray, sc: int, piece: String) -> bool:
	match sc + 1:
		1, 2, 3:
			if Solver.EDGES.has(piece):
				return Solver._edge_solved(fs, piece)
			return Solver._corner_solved(fs, piece)
		4:
			return fs[Solver.EDGES[piece][0]] == 3  # D 面格黄(朝向)
		5:
			return fs[Solver.CORNERS[piece][0]] == 3
		6:
			return Solver._corner_solved(fs, piece)
		7:
			return Solver._edge_solved(fs, piece)
	return false


## 白十字护棱:构造「中层白棱的直接提取(grade≤1)都会拆已归位棱」的态,
## 循环 hint 执行至十字完成,断言已归位白棱全程在位。
func _test_cross_guard() -> void:
	seed(99)
	var found := PackedByteArray()
	var replay: Array = []
	for attempt in 80:
		_cube.setup(3)
		_cube.scramble(8)
		var fs: PackedByteArray = _cube.to_facelets()
		if not _guard_needed(fs):
			continue
		found = fs
		replay = _cube.full_log.duplicate()
		break
	if found.is_empty():
		_check(false, "护棱构造态未找到(80 次尝试)")
		return
	# 用求解路径执行十字,断言初始已归位白棱全程保持
	var fs: PackedByteArray = found.duplicate()
	var keep := []
	for e in ["UF", "UR", "UB", "UL"]:
		if Solver._edge_solved(fs, e):
			keep.append(e)
	_check(keep.size() >= 2, "护棱态已有 %d 条归位白棱(构造成功)" % keep.size())
	var ok := true
	var guarded := false
	for round in 30:
		if Solver._done(fs, 1):
			break
		var h: Dictionary = Solver.hint(fs)
		if h.suggestion.is_empty():
			ok = false
			printerr("  护棱轮 %d 空建议" % round)
			break
		if String(h.suggestion.alg).split(" ", false).size() >= 3:
			guarded = true  # U 让开 + 提取 + 转回 的护棱包装段
		Solver._apply_alg(fs, h.suggestion.alg)
		for e in keep:
			if not Solver._edge_solved(fs, e):
				ok = false
				printerr("  护棱轮 %d 后 %s 白棱被拆" % [round, e])
	_check(ok, "护棱:已归位白棱经启发式全流程保持(包装段出现=%s)" % guarded)
	_check(Solver._done(fs, 1), "护棱:十字最终完成")


## 谓词:存在中层白棱,其全部直接提取(到 U 白朝上/D 白朝下且不拆归位棱)都不可行。
func _guard_needed(fs: PackedByteArray) -> bool:
	var kept := 0
	for e in ["UF", "UR", "UB", "UL"]:
		if Solver._edge_solved(fs, e):
			kept += 1
	if kept < 2:
		return false
	var cands := ["R", "F'", "L'", "B'", "R'", "F", "L", "B"]
	for pos in ["FR", "FL", "BL", "BR"]:
		var idx: Array = Solver.EDGES[pos]
		if fs[idx[0]] != 0 and fs[idx[1]] != 0:
			continue
		var colors := [0, fs[idx[1]]] if fs[idx[0]] == 0 else [0, fs[idx[0]]]
		var any_safe := false
		for a in cands:
			var t: PackedByteArray = fs.duplicate()
			Solver._apply_alg(t, String(a))
			var dest: String = Solver._find_edge(t, colors)
			var good: bool = dest in Solver.U_EDGES or dest in Solver.D_EDGES
			if good and Solver._u_cross_kept(fs, t):
				any_safe = true
				break
		if not any_safe:
			return true
	return false
