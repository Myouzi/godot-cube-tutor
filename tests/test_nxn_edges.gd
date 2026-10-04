extends SceneTree
## v7 P4a 组棱段金标准(docs/v7-teach-nxn-plan.md P4a):
## 覆盖:宏池入池验证(中心面 setwise 保持 + wing 块封闭 + 置换双射,§6 条款)/
## stage_check・progress・hint 构造态 / 固定种子 30 态:打乱 → solve_centers →
## solve_edges → 纯 apply_turn 播放 → 断言 12 棱组各两 wing 同色、每段已配对棱保持、
## 六面中心不破坏 → 逆向回打乱态。
## 降级分层口径(P4a 熔断条款):未覆盖构型 solve_edges 返回 ok:false 且 error
## 注明『组棱段模板池未覆盖(降级)』;金标准对失败态逐个断言该标记并统计比例
## (DEGRADED-RATIO 输出供熔断记录),带标记的降级不算 FAIL。
## 运行:godot --headless -s tests/test_nxn_edges.gd;双校验:exit 0 且无 SCRIPT ERROR。

const NS := preload("res://scripts/nxn_solver.gd")
const LBL := preload("res://scripts/lbl_solver.gd")

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


func _solved_facelets4() -> PackedByteArray:
	_cube.setup(4)
	return _cube.to_facelets()


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	while _cube.get_child_count() == 0:  # 等首帧 setup(3) 完成(同 self_test)
		await process_frame
	_test_basis_and_pool()
	_test_stage_constructed()
	_test_constructed_solve()
	_test_golden_10()
	_test_golden_p4b()
	_test_boundaries()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## TNE-1 wing 基础与宏池入池验证(§6 条款):
## 复原态 wing 表自检(每棱两 wing 色集相同且 12 色集各异)/ 池置换全双射 /
## 抽验宏在复原态 96 字节上中心面同色不破 + wing 块封闭。
func _test_basis_and_pool() -> void:
	var fs := _solved_facelets4()
	NS._ensure_edges()
	var st := NS._wing_state_of(fs)
	var ok_wing := true
	for e in 12:
		var w: Array = NS._edge_wings[e]
		if st[w[0]] != st[w[1]]:
			ok_wing = false
	var uniq := {}
	for i in 24:
		uniq[st[i]] = true
	_check(ok_wing and uniq.size() == 12 and NS._edge_wings.size() == 12,
			"TNE-1a 复原态 12 棱各两 wing 同色集且互异(wing 表自检,池 %d+%d 条)"
			% [NS._edge_pool.size(), NS._edge_local.size()])

	var ok_biject := true
	for pool in [NS._edge_pool, NS._edge_local]:
		for e in pool:
			var p: PackedInt32Array = e.perm
			var seen := {}
			for j in 24:
				if p[j] < 0 or p[j] > 23 or seen.has(p[j]):
					ok_biject = false
				seen[p[j]] = true
	_check(ok_biject, "TNE-1b 池置换全双射(§6 入池条款)")

	# 抽验:基础池每姿态第一条 + 复合库前 20 条,复原态 apply 后中心同色 + 块封闭
	var ok_center := true
	var sample: Array = []
	for k in 4:
		for xr in 2:
			var core: String = NS._rotate_y(NS.EDGE_BASES[0], k)
			if xr == 1:
				core = NS._remap_x2(core)
			sample.append(core)
	for i in mini(20, NS._edge_local.size()):
		sample.append(String(NS._edge_local[i].alg))
	for alg in sample:
		var t := fs.duplicate()
		NS._apply_alg(t, alg)
		if not NS._centers_uniform(t):
			ok_center = false
			printerr("  宏 '%s' 破中心面同色" % alg)
		var st2 := NS._wing_state_of(t)
		for w in 24:
			var pa: int = t[NS._wing_cells[2 * w]]
			var pb: int = t[NS._wing_cells[2 * w + 1]]
			if mini(pa, pb) * 6 + maxi(pa, pb) != st2[w]:
				ok_center = false
	_check(ok_center, "TNE-1c 抽验 %d 条宏:中心面同色保持 + wing 块封闭(模拟器直测)"
			% sample.size())

	_check(NS.stage_check(fs) == 9, "TNE-1d 复原态 stage_check = 9(六面中心同色 + 棱组全配对;"
			+ "9 段契约随 P5 统一)")


## TNE-2 stage/progress/hint 构造态(中心已解、棱部分配对)。
func _test_stage_constructed() -> void:
	var fs := _solved_facelets4()
	NS._apply_alg(fs, "u' R U R' u")  # 单配对宏扰动(中心保持,棱重排)
	_check(NS.stage_check(fs) == 1, "TNE-2a 单宏扰动态 stage_check = 1(中心同色)")
	var prog: float = NS._progress(fs, 1)
	var paired := NS._edges_paired(NS._wing_state_of(fs))
	_check(absf(prog - paired / 12.0) < 0.0001,
			"TNE-2b 进度 = 已配对棱比例(paired=%d/12)" % paired)

	var h: Dictionary = NS.hint(fs)
	var sug: Dictionary = h.suggestion
	var ok_hint: bool = sug.has("alg") and sug.has("text") and not String(sug.alg).is_empty()
	if ok_hint:
		var t := fs.duplicate()
		NS._apply_alg(t, String(sug.alg))
		var st0 := NS._wing_state_of(fs)
		var st1 := NS._wing_state_of(t)
		var kept0 := NS._edge_pair_mask(st0)
		ok_hint = NS.stage_check(t) >= 0 and NS._edge_pair_mask(st1) & kept0 == kept0
	_check(ok_hint, "TNE-2c hint 结构完整且建议执行后已配对色集保持")
	_check(int(h.stage) == 1, "TNE-2d hint stage = 1(中心已解转组棱建议)")


## TNE-3 构造 reachable 态求解(simulator 播放验证;真机播放归金标准)。
func _test_constructed_solve() -> void:
	var ok := true
	seed(20260929)
	for trial in 5:
		var fs := _solved_facelets4()
		var prev := ""
		for i in 20:
			var face: String = ["U", "R", "F", "D", "L", "B"][randi() % 6]
			if face == prev:
				continue
			prev = face
			NS._apply_alg(fs, face + ["", "'", "2"][randi() % 3])
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			ok = false
			printerr("  trial %d solve_centers 失败: %s" % [trial, rc.get("error", "?")])
			break
		var sim := fs.duplicate()
		NS._apply_alg(sim, String(rc.alg))
		var re: Dictionary = NS.solve_edges(sim)
		if not re.ok:
			var err := String(re.get("error", ""))
			if err.contains("组棱段模板池未覆盖(降级)"):
				continue  # 降级态跳过(金标准分层口径同款)
			ok = false
			printerr("  trial %d solve_edges 失败: %s" % [trial, err])
			break
		var t := sim.duplicate()
		NS._apply_alg(t, String(re.alg))
		var st := NS._wing_state_of(t)
		if NS._edges_paired(st) != 12:
			ok = false
			printerr("  trial %d 播放后未全配对(%d/12)" % [trial, NS._edges_paired(st)])
			break
		if not NS._centers_uniform(t):
			ok = false
			printerr("  trial %d 播放后中心破坏" % trial)
			break
	_check(ok, "TNE-3 构造态(外层 20 步打乱)×5:中心段+组棱段→模拟播放全配对且中心不破")


## TNE-4 金标准:固定种子 10 态(P8 态数定稿,原占位 30;cube.gd scramble(40)
## WCA 口径)→ solve_centers → solve_edges → 纯 apply_turn 播放 → 12 棱全配对 +
## 每段已配对棱保持 + 中心不破坏 → 逆向回打乱态。降级分层:组棱失败态 error
## 必带『组棱段模板池未覆盖(降级)』,统计比例输出(DEGRADED-RATIO,熔断记录
## 口径),带标记降级不判 FAIL。
func _test_golden_10() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var ok_all := true
	var n_ok := 0
	var n_degraded := 0
	var worst_moves := 0
	for trial in 10:
		_cube.setup(4)
		_cube.scramble(40, rng)
		var fs: PackedByteArray = _cube.to_facelets()
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			var errc := String(rc.get("error", ""))
			if errc.contains("中心段模板池未覆盖(降级)"):
				n_degraded += 1
				print("  降级 trial %d(中心段): %s" % [trial, errc])
				continue
			ok_all = false
			printerr("  trial %d 中心段失败且无降级标记: %s" % [trial, errc])
			break
		var sim := fs.duplicate()
		NS._apply_alg(sim, String(rc.alg))
		var re: Dictionary = NS.solve_edges(sim)
		if not re.ok:
			var err := String(re.get("error", ""))
			if err.contains("组棱段模板池未覆盖(降级)"):
				n_degraded += 1
				print("  降级 trial %d(组棱段): %s" % [trial, err])
				continue
			ok_all = false
			printerr("  trial %d 组棱段失败且无降级标记: %s" % [trial, err])
			break
		# 每段已配对棱保持(色集级)+ 段序回放
		var seg_sim := sim.duplicate()
		var kept0 := NS._edge_pair_mask(NS._wing_state_of(sim))
		var ok_seg := true
		for seg in re.segments:
			NS._apply_alg(seg_sim, String(seg.alg))
			var kept_now := NS._edge_pair_mask(NS._wing_state_of(seg_sim))
			if kept_now & kept0 != kept0:
				ok_seg = false
				printerr("  trial %d 段后已配对色集被拆: %s" % [trial, seg.alg])
				break
			kept0 = NS._edge_pair_mask(NS._wing_state_of(seg_sim))
		if not ok_seg or NS._edges_paired(NS._wing_state_of(seg_sim)) != 12:
			ok_all = false
			printerr("  trial %d 段保持/终态不达(%d/12 对)"
					% [trial, NS._edges_paired(NS._wing_state_of(seg_sim))])
			break
		# 真机全量播放:纯 apply_turn(中心 + 组棱一起)
		_apply_alg_cube(String(rc.alg) + " " + String(re.alg))
		var played: PackedByteArray = _cube.to_facelets()
		if not NS._centers_uniform(played):
			ok_all = false
			printerr("  trial %d 真机播放后中心破坏(模拟器/真机对拍失配)" % trial)
			break
		if NS._edges_paired(NS._wing_state_of(played)) != 12:
			ok_all = false
			printerr("  trial %d 真机播放后未全配对" % trial)
			break
		# moves 字段与段和一致
		var tok := 0
		for seg2 in re.segments:
			tok += LBL._token_count(String(seg2.alg))
		if int(re.moves) > tok or int(re.moves) <= 0:
			ok_all = false
			printerr("  trial %d moves=%d 与段步数和 %d 不符" % [trial, int(re.moves), tok])
			break
		worst_moves = maxi(worst_moves, int(re.moves))
		# 逆向:逆序 apply 回打乱态
		_apply_alg_cube(LBL.invert_alg(String(re.alg)))
		if _cube.to_facelets() != sim:
			ok_all = false
			printerr("  trial %d 逆序 apply 未回中心已解态" % trial)
			break
		n_ok += 1
	print("  金标准分布: 全绿 %d/10, 降级 %d/10, 最坏组棱步数 %d" % [n_ok, n_degraded, worst_moves])
	if n_degraded > 0:
		print("  DEGRADED-RATIO %d/%d" % [n_degraded, 10])
	_check(ok_all and n_ok + n_degraded == 10,
		"TNE-4 金标准 10 态:全绿 %d + 带标记降级 %d(降级比例 %.0f%%)"
		% [n_ok, n_degraded, 100.0 * n_degraded / 10.0])


## TNE-6 金标准(P4b,docs/v7-teach-nxn-plan.md P4b 条款):5/6/7 阶层 a 各 15 态
## (n=7 按 P8 条款"先实测单态耗时再定"缩为 3)固定种子,双层口径:
##   层 a(全链路):打乱 → solve_centers → solve_edges → 纯 apply_turn 播放 →
##     断言 12 棱全整棱(每棱 2 wing + n−4 mid 全同色组)+ 六面中心保持 → 逆向;
##   层 b(组棱专项,2 态/阶,P8 态数定稿——原 5 态/阶含 20 宏强打乱,实测降级态
##     BFS 穷尽 8-25s/态爆预算):中心已解构造态 1 宏打乱(trial 0,池闭合数学保证
##     必 ok:打乱宏 _rotate_y 档位在池内,其逆亦在池内)+ 2 宏近解态(trial 1,
##     ok/带标记降级皆容)→ solve_edges → 同款断言——P3 熔断分层口径:降级段
##     (中心)之上的已验证段(组棱)可演示。
## 降级条款同 P3/TNE-4:ok:false 必带『模板池未覆盖(降级)』标记,带标记不判 FAIL
## (trial 0 必 ok 态除外),分层统计输出(DEGRADED-RATIO,熔断记录)。
func _test_golden_p4b() -> void:
	for n in [5, 6, 7]:
		_golden_p4b_n(n, 3 if n >= 7 else 15, 2)


func _golden_p4b_n(n: int, trials: int, trials_b: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var ok_all := true
	var a_ok := 0
	var a_deg := 0
	var b_ok := 0
	var b_deg := 0
	var worst := 0
	for trial in trials:
		# 层 a:全打乱 → 中心段 → 组棱段
		_cube.setup(n)
		_cube.scramble(40, rng)
		var fs: PackedByteArray = _cube.to_facelets()
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			var errc := String(rc.get("error", ""))
			if errc.contains("中心段模板池未覆盖(降级)"):
				a_deg += 1
			else:
				ok_all = false
				printerr("  n=%d t%d 中心段失败且无降级标记: %s" % [n, trial, errc])
				break
		else:
			var sim := fs.duplicate()
			NS._apply_alg(sim, String(rc.alg))
			var re: Dictionary = NS.solve_edges(sim)
			if not re.ok:
				var err := String(re.get("error", ""))
				if err.contains("组棱段模板池未覆盖(降级)"):
					a_deg += 1
				else:
					ok_all = false
					printerr("  n=%d t%d 组棱段失败且无降级标记: %s" % [n, trial, err])
					break
			else:
				var chk := _play_and_check(n, fs, String(rc.alg), String(re.alg))
				if not chk:
					ok_all = false
					printerr("  n=%d t%d 层 a 播放断言失败" % [n, trial])
					break
				a_ok += 1
				worst = maxi(worst, int(re.moves))
				# 逆向回打乱态(真机纯 apply_turn;_play_and_check 后真机 = 解终态)
				_apply_alg_cube(LBL.invert_alg(String(re.alg)))
				_apply_alg_cube(LBL.invert_alg(String(rc.alg)))
				if _cube.to_facelets() != fs:
					ok_all = false
					printerr("  n=%d t%d 层 a 逆向未回打乱态" % [n, trial])
					break
	# 层 b:中心已解构造态 → 组棱段专项(独立循环;打乱宏模拟器/真机同步应用)。
	# 两档:trial 0 单宏打乱(池闭合必 ok,保证「断言每棱全部块同色组」有实质
	# 执行);trial 1 双宏近解态(ok/带标记降级皆容,TNE-3 构造 reachable 态同款)
	for trial_b in trials_b:
		_cube.setup(n)
		var fb: PackedByteArray = _cube.to_facelets()
		var macro_n: int = 1 if trial_b == 0 else 2
		for i in macro_n:
			var base: String = NS.EDGE_BASES[randi() % 15]  # PLL 除外(探针 1:破中心)
			var algb: String = NS._rotate_y(base, randi() % 4)
			NS._apply_alg(fb, algb)
			_apply_alg_cube(algb)
		var rb: Dictionary = NS.solve_edges(fb)
		if not rb.ok:
			var errb := String(rb.get("error", ""))
			if errb.contains("组棱段模板池未覆盖(降级)"):
				if trial_b == 0:
					ok_all = false
					printerr("  n=%d 层 b 单宏态 solve_edges 降级(违背池闭合必 ok): %s" % [n, errb])
					break
				b_deg += 1
			else:
				ok_all = false
				printerr("  n=%d t%d 层 b 失败且无降级标记: %s" % [n, trial_b, errb])
				break
		else:
			var chk2 := _play_and_check(n, fb, "", String(rb.alg))
			if not chk2:
				ok_all = false
				printerr("  n=%d t%d 层 b 播放断言失败" % [n, trial_b])
				break
			b_ok += 1
			worst = maxi(worst, int(rb.moves))
	print("  n=%d P4b 金标准(层a %d 态 / 层b %d 态): 层a 全绿 %d + 降级 %d;层b 组棱全绿 %d + 降级 %d;最坏组棱步数 %d"
			% [n, trials, trials_b, a_ok, a_deg, b_ok, b_deg, worst])
	print("  DEGRADED-RATIO n=%d %d/%d(层a 中心+组棱链)" % [n, a_deg, trials])
	_check(ok_all and a_ok + a_deg == trials and b_ok + b_deg == trials_b,
			"TNE-6 n=%d 金标准:层a %d 态全绿 %d+降级 %d;层b %d 态组棱全绿 %d+降级 %d"
			% [n, trials, a_ok, a_deg, trials_b, b_ok, b_deg])


## 播放 + 断言:base(真机当前态,中心段求解前)应用中心解(可选)+ 组棱解后,
## 模拟器断言 12 棱全整棱 + 六面中心保持,真机纯 apply_turn 对拍;返回后真机 = 解终态。
func _play_and_check(n: int, base: PackedByteArray, center_alg: String, edge_alg: String) -> bool:
	var sim := base.duplicate()
	if center_alg != "":
		NS._apply_alg(sim, center_alg)
	var t := sim.duplicate()
	NS._apply_alg(t, edge_alg)
	if not NS._cn_uniform(t, n):
		printerr("    播放后六面中心不同色")
		return false
	var ctx: Dictionary = NS._pr_ensure(n)
	var sc: Vector2i = NS._pr_score(NS._pr_state_of(t, n), ctx)
	if sc.x != 12:
		printerr("    播放后未全整棱(%d/12, 已组块 %d)" % [sc.x, sc.y])
		return false
	# 真机对拍(纯 apply_turn 数学路径;真机当前态 = base)
	for s in _cube.parse_alg((center_alg + " " if center_alg != "" else "") + edge_alg):
		_cube.apply_turn(s.axis, s.layers, s.angle)
	if _cube.to_facelets() != t:
		printerr("    模拟器/真机对拍失配")
		return false
	return true


func _test_boundaries() -> void:
	var fs := _solved_facelets4()
	var r0: Dictionary = NS.solve_edges(fs)
	var ok: bool = r0.ok and String(r0.alg).is_empty() and int(r0.moves) == 0
	ok = ok and r0.stages.size() == 1 and String(r0.stages[0].name) == NS.STAGE_NAMES_NXN[1]
	_check(ok, "TNE-5a 复原态 solve_edges:ok、空解、段名=组棱")

	var fbad := PackedByteArray()
	fbad.resize(54)
	_check(NS.solve_edges(fbad).ok == false and NS.solve_edges(fbad).stages.is_empty(),
			"TNE-5b solve_edges(54 字节)fail loud")

	var scrambled := fs.duplicate()
	NS._apply_alg(scrambled, "r U' r'")  # 裸共轭 3 步:跨面 4 循环,中心面同色破坏(探针 7 实测)
	var r1: Dictionary = NS.solve_edges(scrambled)
	_check(r1.ok == false and String(r1.get("error", "")).contains("中心已解"),
			"TNE-5b2 中心未解态 solve_edges 拒绝并带原因")

	# P5 全链落地:solve(96)走 _nxn_solve;此处以中心+棱组已解的构造态断言快速路径
	# (纯外层打乱保持中心+棱组,确定性无降级;全链金标准归 tests/test_nxn_reduce.gd TNR-1)
	var fpre := fs.duplicate()
	seed(20261004)
	for i in 20:
		NS._apply_alg(fpre, ["U", "D", "R", "L", "F", "B"][randi() % 6] + ["", "'", "2"][randi() % 3])
	NS._apply_alg(fpre, String(NS.PARITY_ALGS[4].oll))  # 加 OLL parity:全链须修正
	var rp: Dictionary = NS.solve(fpre)
	_check(bool(rp.ok) and (rp.stages as Array).size() == 9 and int(rp.moves) > 0
			and String(rp.stages[1].alg).contains(String(NS.PARITY_ALGS[4].oll)),
			"TNE-5c solve(96 构造态)全链:9 段且 parity 修正并入『组棱』段尾")

	var f8 := PackedByteArray()
	f8.resize(384)  # 8 阶长度,超出 2-7 契约
	_check(NS.solve_edges(f8).ok == false,
			"TNE-5d n=8 长度:solve_edges fail loud(阶数契约 2-7;n≥5 分派见 TNE-6)")
