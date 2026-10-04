extends SceneTree
## v7 P1 2 阶独立解法器金标准(docs/v7-teach-nxn-plan.md P1 + 审计裁决第二轮必改 1:
## 嵌入方案证伪弃用,改独立初学者法)。覆盖:24 facelet 模拟器对拍 / 公式池语义验证
## (先验证后入池口径)/ stage_check 构造态(含整体旋转等价复原态)/ 50 态固定种子
## 金标准(scramble {2:11} → solve → 纯 apply_turn 播放 → is_solved → 逆向复原)/
## stage 单调 / hint 结构 / n=3 转调。
## 运行:godot --headless -s tests/test_nxn_2x2.gd;任何断言失败 exit 1,全过 exit 0。
## 双校验口径:exit code 0 且输出无 SCRIPT ERROR(EXPERIENCE 假绿陷阱)。

const NS := preload("res://scripts/nxn_solver.gd")
const LBL := preload("res://scripts/lbl_solver.gd")

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


## 纯 apply_turn 数学路径播放(不经动画;parse_alg→逐步 bake)。
func _apply_alg_cube(alg: String) -> void:
	for s in _cube.parse_alg(alg):
		_cube.apply_turn(s.axis, s.layers, s.angle)


## 标准 WCA 语义把一个 token 应用到 2 阶 cube(n=2 外层 E=1)。
func _apply_token_cube2(token: String) -> void:
	var axis: Vector3 = AXIS_OF[token[0]]
	var angle := -PI / 2
	if token.ends_with("2"):
		angle = PI
	elif token.ends_with("'"):
		angle = PI / 2
	_cube.apply_turn(axis, [1], angle)


func _solved_facelets() -> PackedByteArray:
	_cube.setup(2)
	return _cube.to_facelets()


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	while _cube.get_child_count() == 0:  # 等首帧 setup(3) 完成(同 self_test)
		await process_frame
	_test_simulator_parity()
	_test_formula_semantics()
	_test_stage_check_constructed()
	_test_solve_solved_state()
	_test_golden_50()
	_test_stages_monotonic()
	_test_hint()
	_test_n3_delegate()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## 模拟器对拍:cube.gd apply_turn(n=2) 与 nxn 24 facelet 置换逐步一致。
func _test_simulator_parity() -> void:
	_cube.setup(2)
	var sim: PackedByteArray = _cube.to_facelets()
	seed(20260925)
	var faces := ["U", "D", "R", "L", "F", "B"]
	var ok := true
	for i in 60:
		var token: String = faces[randi() % 6] + ["", "'", "2"][randi() % 3]
		_apply_token_cube2(token)
		NS._apply_token(sim, token)
		if _cube.to_facelets() != sim:
			ok = false
			printerr("  对拍不一致 @step %d token %s" % [i, token])
			break
	_check(ok, "TN2-1 24 facelet 置换与 cube.gd(n=2)逐步一致(60 步随机)")


## 公式池语义验证(先验证后入池口径):逐条在 24 facelet 模型上断言
## 结构性质——stage1 作用槽唯一且 rotate 覆盖四槽、只动槽内白角 + 黄层;
## stage2 保 U 层白角(翻 D 面朝向);stage3 保 U 层 + 黄面朝向(纯置换)。
func _test_formula_semantics() -> void:
	seed(20260926)
	var ok_slot := true
	var slots := {}
	for item in NS._formulas[1]:
		for kt in 4:
			var t: PackedByteArray = _solved_facelets()
			NS._apply_alg(t, LBL._rotate_alg(String(item.alg), kt))
			var broken: Array = []
			for c in NS.U_CORNERS:
				if not NS._corner_solved(t, c):
					broken.append(c)
			if broken.size() != 1:
				ok_slot = false
				printerr("  公式 %s rot%d 作用槽不唯一: %s" % [item.alg, kt, broken])
			slots[broken[0]] = true
	if slots.size() != 4:
		ok_slot = false
		printerr("  stage1 公式池 rotate 槽未覆盖四槽: %s" % [slots.keys()])
	_check(ok_slot, "TN2-2a stage1 公式:每条每档作用槽唯一,rotate 合计覆盖 4 个 U 槽")

	# 只动槽内白角 + D 层:随机态应用后,槽外已归位白角保持(插入/顶出依赖的不变式)
	var ok_keep := true
	for trial in 20:
		_cube.setup(2)
		_cube.scramble(11)
		var fs: PackedByteArray = _cube.to_facelets()
		for item in NS._formulas[1]:
			for kt in 4:
				var slot := _slot_of(String(item.alg), kt)
				var t: PackedByteArray = fs.duplicate()
				NS._apply_alg(t, LBL._rotate_alg(String(item.alg), kt))
				for c in NS.U_CORNERS:
					if c != slot and NS._corner_solved(fs, c) and not NS._corner_solved(t, c):
						ok_keep = false
						printerr("  公式 %s rot%d 拆了槽外白角 %s" % [item.alg, kt, c])
	_check(ok_keep, "TN2-2b stage1 公式:槽外已归位白角全程保持(20 态 × 3 公式 × 4 档)")

	var ok_oll := true
	for item in NS._formulas[2]:
		var t: PackedByteArray = _solved_facelets()
		NS._apply_alg(t, String(item.alg))
		if NS._solved_white_corners(t) != 4:
			ok_oll = false
			printerr("  OLL 公式 %s 破坏 U 层白角" % item.alg)
		if NS._all_faces_uniform(t):
			ok_oll = false
			printerr("  OLL 公式 %s 对复原态无翻朝向作用" % item.alg)
	_check(ok_oll, "TN2-2c stage2 公式:U 层白角保持且确实翻动黄面朝向")

	var ok_pll := true
	for item in NS._formulas[3]:
		var t: PackedByteArray = _solved_facelets()
		NS._apply_alg(t, String(item.alg))
		if NS._solved_white_corners(t) != 4 or NS._yellow_down_count(t) != 4:
			ok_pll = false
			printerr("  PLL 公式 %s 破坏 U 层或黄面朝向" % item.alg)
		if NS._all_faces_uniform(t):
			ok_pll = false
			printerr("  PLL 公式 %s 对复原态无置换作用" % item.alg)
	_check(ok_pll, "TN2-2d stage3 公式:U 层 + 黄面朝向保持,纯角置换")

	# 逆公式程序生成防笔误:base·inv 恒等
	var t_inv: PackedByteArray = _solved_facelets()
	NS._apply_alg(t_inv, String(NS._formulas[3][0].alg))
	NS._apply_alg(t_inv, String(NS._formulas[3][1].alg))
	_check(t_inv == _solved_facelets() and NS._formulas[3][1].alg == LBL.invert_alg(String(NS._formulas[3][0].alg)),
			"TN2-2e stage3 逆公式程序生成且 base·inv 恒等")


## 公式 rot 档的作用槽(solved 态应用后唯一被换出的 U 角)。
func _slot_of(alg: String, kt: int) -> String:
	var t: PackedByteArray = _solved_facelets()
	NS._apply_alg(t, LBL._rotate_alg(alg, kt))
	for c in NS.U_CORNERS:
		if not NS._corner_solved(t, c):
			return c
	return ""


## stage_check 构造态:复原 / 半程 / 整体旋转等价复原态(2 阶无中心,
## R2 L2 = x2 整体旋转,六面同色口径须判 3)。
func _test_stage_check_constructed() -> void:
	_check(NS.stage_check(_solved_facelets()) == 3, "TN2-3 stage_check(复原)=3")

	_cube.setup(2)
	_apply_alg_cube("D")
	var fs_d: PackedByteArray = _cube.to_facelets()
	_check(NS.stage_check(fs_d) == 2, "TN2-3 stage_check(复原后 D)=2:白角/黄面保持,归位破")

	_cube.setup(2)
	_apply_alg_cube("U")
	var fs_u: PackedByteArray = _cube.to_facelets()
	_check(NS.stage_check(fs_u) == 0, "TN2-3 stage_check(复原后 U)=0:白角错位")

	_cube.setup(2)
	_apply_alg_cube("R")
	var fs_r: PackedByteArray = _cube.to_facelets()
	_check(NS.stage_check(fs_r) == 0, "TN2-3 stage_check(复原后 R)=0")

	_cube.setup(2)
	_apply_alg_cube("R2 L2")
	var fs_x2: PackedByteArray = _cube.to_facelets()
	_check(_cube.is_solved() and NS.stage_check(fs_x2) == 3,
			"TN2-3 stage_check(R2 L2 整体旋转等价复原态)=3(朝向无关口径)")


## 复原态直解:ok、空解、三段表完整(对打乱态零覆盖之外的边界)。
func _test_solve_solved_state() -> void:
	var r: Dictionary = NS.solve(_solved_facelets())
	var ok: bool = r.ok == true and String(r.alg).is_empty() and int(r.moves) == 0
	ok = ok and r.stages.size() == 3
	for si in 3:
		ok = ok and String(r.stages[si].name) == NS.STAGE_NAMES[si] and String(r.stages[si].alg).is_empty()
	_check(ok, "TN2-4 复原态 solve:ok、空解、三段表与 STAGE_NAMES 对齐")


## 金标准:固定种子 50 态 → scramble(11)(cube.gd 口径 {2:11})→ solve →
## 纯 apply_turn 播放 → is_solved → stage_check=3 → 逆向复原回打乱态。
## 步数门依据:2026-09-25 实测 300 态(12 个种子)最坏 74 步、零失败,门取 +28% 余量。
func _test_golden_50() -> void:
	seed(20260925)
	var ok_all := true
	var worst := 0
	for trial in 50:
		_cube.setup(2)
		_cube.scramble(11)
		var fs: PackedByteArray = _cube.to_facelets()
		var r: Dictionary = NS.solve(fs)
		if not r.ok:
			ok_all = false
			printerr("  trial %d solve 失败: %s" % [trial, r.get("error", "?")])
			break
		var toks: int = LBL._token_count(String(r.alg))
		worst = maxi(worst, toks)
		if toks >= 95:
			ok_all = false
			printerr("  trial %d 步数 %d >= 95" % [trial, toks])
			break
		if int(r.moves) != toks:
			ok_all = false
			printerr("  trial %d moves 字段不一致" % trial)
			break
		if r.stages.size() != 3:
			ok_all = false
			printerr("  trial %d stages 段数 %d != 3" % [trial, r.stages.size()])
			break
		_apply_alg_cube(String(r.alg))
		if not _cube.is_solved():
			ok_all = false
			printerr("  trial %d 执行解后未复原(六面同色)" % trial)
			break
		if NS.stage_check(_cube.to_facelets()) != 3:
			ok_all = false
			printerr("  trial %d 解后 stage_check != 3" % trial)
			break
		_apply_alg_cube(LBL.invert_alg(String(r.alg)))
		if _cube.to_facelets() != fs:
			ok_all = false
			printerr("  trial %d 逆序 apply 未回到打乱态" % trial)
			break
	_check(ok_all, "TN2-5 金标准:50 态 solve→apply 全复原且步数<95(最坏 %d)" % worst)


## solve 分段单调性:每段执行后 stage_check 不低于该段阶段号
## (最后一段可能恰好一并完成,故只断言下限)。
func _test_stages_monotonic() -> void:
	seed(20260927)
	var ok := true
	for trial in 5:
		_cube.setup(2)
		_cube.scramble(11)
		var fs: PackedByteArray = _cube.to_facelets()
		var r: Dictionary = NS.solve(fs)
		if not r.ok:
			ok = false
			break
		var replay: PackedByteArray = fs.duplicate()
		for si in range(r.stages.size()):
			NS._apply_alg(replay, String(r.stages[si].alg))
			if NS.stage_check(replay) < si + 1:
				ok = false
				printerr("  trial %d 阶段 %d 后 stage_check=%d" % [trial, si + 1, NS.stage_check(replay)])
	_check(ok, "TN2-6 solve 分段:每段后 stage_check 不低于该阶段(5 态)")


## hint:结构对齐 lbl_solver({stage, progress, suggestion:{piece, alg, text}});
## 建议执行后 piece 达成阶段条件且 stage 不降;复原态(含旋转等价)给完成文案。
func _test_hint() -> void:
	seed(20260928)
	var ok := true
	for trial in 10:
		_cube.setup(2)
		_cube.scramble(11)
		var fs: PackedByteArray = _cube.to_facelets()
		var sc := NS.stage_check(fs)
		var h: Dictionary = NS.hint(fs)
		if int(h.get("stage", -1)) != sc or not h.has("progress") or not h.has("suggestion"):
			ok = false
			printerr("  trial %d hint 结构不完整: %s" % [trial, h.keys()])
			break
		var sug: Dictionary = h.suggestion
		if sc == 3:
			if String(sug.get("alg", "x")) != "":
				ok = false
				printerr("  trial %d 复原态建议应为空" % trial)
			break
		if not sug.has("piece") or not sug.has("alg") or not sug.has("text") or String(sug.alg).is_empty():
			ok = false
			printerr("  trial %d suggestion 不完整: %s" % [trial, sug])
			break
		var t: PackedByteArray = fs.duplicate()
		NS._apply_alg(t, String(sug.alg))
		if NS.stage_check(t) < sc:
			ok = false
			printerr("  trial %d hint 执行后 stage 回退" % trial)
			break
		match sc:
			0:
				if not NS._corner_solved(t, String(sug.piece)) or not NS._white_kept(fs, t):
					ok = false
					printerr("  trial %d piece %s 未归位或拆了已归位白角" % [trial, sug.piece])
			1:
				if NS.stage_check(t) < 2 or t[NS.CORNERS[String(sug.piece)][0]] != NS.YELLOW:
					ok = false
					printerr("  trial %d 黄面段未完成或 piece %s 未翻黄" % [trial, sug.piece])
			2:
				if NS.stage_check(t) < 3:
					ok = false
					printerr("  trial %d 归位段未完成" % trial)
	_check(ok, "TN2-7 hint:结构完整、piece 达成阶段条件、stage 不降(10 态)")

	var h_solved: Dictionary = NS.hint(_solved_facelets())
	_cube.setup(2)
	_apply_alg_cube("R2 L2")
	var h_rot: Dictionary = NS.hint(_cube.to_facelets())
	var ok_solved: bool = int(h_solved.stage) == 3 and String(h_solved.suggestion.text) == "魔方已复原"
	ok_solved = ok_solved and int(h_rot.stage) == 3 and String(h_rot.suggestion.alg).is_empty()
	_check(ok_solved, "TN2-7 复原态/旋转等价复原态 hint:stage=3 完成文案")


## n=3 转调:solve/hint/stage_check 与 lbl_solver 逐字节同结果(统一入口,调用方无分派);
## 长度非法兜底 ok:false / -1 / error,不落在 lbl_solver 上。
func _test_n3_delegate() -> void:
	_cube.setup(3)
	_cube.scramble(25)
	var fs3: PackedByteArray = _cube.to_facelets()
	var via_nxn: Dictionary = NS.solve(fs3)
	var via_lbl: Dictionary = LBL.solve(fs3)
	var ok: bool = via_nxn == via_lbl
	ok = ok and NS.stage_check(fs3) == LBL.stage_check(fs3) and NS.hint(fs3) == LBL.hint(fs3)
	_check(ok, "TN2-8 n=3 solve/hint/stage_check 转调 lbl_solver 结果一致")

	var bad := PackedByteArray()
	bad.resize(30)
	_check(NS.solve(bad).ok == false and NS.stage_check(bad) == -1
			and NS.hint(bad).get("error", "") != "",
			"TN2-8 长度非法兜底:solve ok:false、stage_check -1、hint 带 error")
