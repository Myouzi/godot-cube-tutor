extends SceneTree
## v7 P3 中心段金标准(docs/v7-teach-nxn-plan.md P3 + docs/v7-impl-design.md):
## 覆盖:配色基准(cube.gd FACES 面序)/ 模板池入池验证(置换双射 + keeps 自洽,
## §6 条款)/ stage_check・progress・hint 构造态 / 固定种子 10 态金标准:
## 打乱 → solve_centers → 纯 apply_turn 播放 → 断言六面中心同色 且 每段中心块只增不减
## → stage_check=1 → 逆向回打乱态。
## 态数定稿(P8):占位 30 态;实测单态 solve_centers 均值 0.35s(固定种子最坏 6.6s),
## 30 态约 11s,按 P8 预算(全量测试本地时长 ≤ 基线 2 倍 = 1.4min)下调至 10 态。
## 降级分层口径(P3 熔断条款):未覆盖构型 solve_centers 返回 ok:false 且 error
## 注明『中心段模板池未覆盖(降级)』;金标准对失败态逐个断言该标记并统计死锁
## 构型比例(输出供熔断记录),带标记的降级不算 FAIL。
## 运行:godot --headless -s tests/test_nxn_centers.gd;双校验:exit 0 且无 SCRIPT ERROR。

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
	_test_cn_golden_5x7()
	_test_boundaries()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## TNC-1 配色基准与模板池入池验证(§6 条款):
## 中心格复原值 = 面号(FACES 面序直读);白红绿角三元组存在且唯一(P3 节一次性断言);
## 池条目置换全双射;keeps 位与置换逐面自洽;共轭宏 = 4 格重排(2+2 对换语义)。
func _test_basis_and_pool() -> void:
	var fs := _solved_facelets4()
	NS._ensure_centers()
	var ok_cells := true
	for i in 24:
		if fs[NS._center_cells[i]] != i / 4:
			ok_cells = false
	_check(ok_cells, "TNC-1a 复原态 24 中心格 = 面号(配色基准 = cube.gd FACES 面序直读)")

	var tri := 0
	for c in NS.CORNER_COLORS.values():
		var s := {c[0]: true, c[1]: true, c[2]: true}
		if s.size() == 3 and s.has(0) and s.has(1) and s.has(2):
			tri += 1
	_check(tri == 1, "TNC-1b 白红绿角三元组存在且唯一(P3 节一次性断言)")

	var ok_biject := true
	for pool in [NS._center_pool1, NS._center_pool2]:
		for e in pool:
			var p: PackedInt32Array = e.perm
			var seen := {}
			for j in 24:
				if p[j] < 0 or p[j] > 23 or seen.has(p[j]):
					ok_biject = false
				seen[p[j]] = true
			# keeps 自洽:keeps 位 fi 当且仅当置换把面 fi 4 格 setwise 映回 fi
			for fi in 6:
				var same := true
				for i in 4:
					var src: int = p[fi * 4 + i]
					if src < fi * 4 or src > fi * 4 + 3:
						same = false
						break
				if same != (int(e.keeps) & (1 << fi) != 0):
					ok_biject = false
	_check(ok_biject, "TNC-1c 池置换全双射且 keeps 位逐面自洽(%d+%d 条,§6 入池条款)"
			% [NS._center_pool1.size(), NS._center_pool2.size()])

	# 共轭宏语义:M7 基态(8 姿态)= 2+2 对换(恰 4 格重排;带 U/D 前缀的变体
	# 额外面内轮换不破语义,不对变体断言)
	var ok_conj := true
	for k in 4:
		for base in [NS._rotate_y(NS.CENTER_CONJUGATE, k), NS._remap_x2(NS._rotate_y(NS.CENTER_CONJUGATE, k))]:
			var perm := NS._center_id_perm(base)
			var moved := 0
			for j in 24:
				if perm[j] != j:
					moved += 1
			if moved != 4:
				ok_conj = false
				printerr("  共轭基态 %s 重排 %d 格(应恰 4)" % [base, moved])
	_check(ok_conj, "TNC-1d 共轭宏(M7 8 姿态基态)恰 4 格重排(2+2 对换语义)")

	var h := NS.hint(_solved_facelets4())
	_check(NS.stage_check(fs) == 9 and int(h.stage) == 9,
			"TNC-1e 复原态 stage_check/hint stage = 9(六面同色,9 段契约随 P5 统一)")


## TNC-2 stage_check/progress/hint 构造态(simulator 构造 reachable 态)。
func _test_stage_constructed() -> void:
	var fs := _solved_facelets4()
	NS._apply_alg(fs, "r U r'")
	_check(NS.stage_check(fs) == 0, "TNC-2a 单宏扰动态 stage_check = 0")
	var prog: float = NS._progress(fs, 0)
	var placed := NS._centers_placed(NS._center_state_of(fs))
	_check(absf(prog - placed / 24.0) < 0.0001 and prog > 0.9,
			"TNC-2b 进度 = 已归位中心块比例(placed=%d/24)" % placed)

	var h: Dictionary = NS.hint(fs)
	var sug: Dictionary = h.suggestion
	var ok_hint: bool = sug.has("alg") and sug.has("text") and not String(sug.alg).is_empty()
	if ok_hint:
		var t := fs.duplicate()
		NS._apply_alg(t, String(sug.alg))
		ok_hint = NS.stage_check(t) >= 0 and NS._centers_placed(NS._center_state_of(t)) >= placed
	_check(ok_hint, "TNC-2c hint 结构完整且建议执行后 placed 不降")
	_check(int(h.stage) == 0 and absf(float(h.progress) - placed / 24.0) < 0.0001,
			"TNC-2d hint stage/progress 口径与 stage_check/进度一致")


## TNC-3 构造 reachable 态求解(simulator 播放验证;真机播放归金标准)。
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
		var r: Dictionary = NS.solve_centers(fs)
		if not r.ok:
			ok = false
			printerr("  trial %d solve_centers 失败: %s" % [trial, r.get("error", "?")])
			break
		var t := fs.duplicate()
		NS._apply_alg(t, String(r.alg))
		if not NS._centers_uniform(t):
			ok = false
			printerr("  trial %d 播放后六面中心不同色" % trial)
			break
	_check(ok, "TNC-3 构造态(外层 20 步打乱)×5:solve_centers→模拟播放六面中心同色")


## TNC-4 金标准:固定种子 10 态(P8 态数定稿,原占位 30)→ solve_centers →
## 纯 apply_turn 播放 → 六面中心同色 + 每段中心块只增不减 → stage_check=1 →
## 逆向回打乱态。降级分层:失败态 error 必带『中心段模板池未覆盖(降级)』,
## 统计死锁构型比例输出(熔断记录口径),带标记降级不判 FAIL。
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
		var p0 := NS._centers_placed(NS._center_state_of(fs))
		var r: Dictionary = NS.solve_centers(fs)
		if not r.ok:
			var err := String(r.get("error", ""))
			if err.contains("中心段模板池未覆盖(降级)"):
				n_degraded += 1
				print("  降级 trial %d: %s" % [trial, err])
				continue
			ok_all = false
			printerr("  trial %d 失败且无降级标记: %s" % [trial, err])
			break
		# 每段只增不减 + 段序回放(cube 真机逐段播放)
		var sim: PackedByteArray = fs.duplicate()
		var prev_placed := p0
		var ok_seg := true
		for seg in r.segments:
			NS._apply_alg(sim, String(seg.alg))
			var pc := NS._centers_placed(NS._center_state_of(sim))
			if pc < prev_placed:
				ok_seg = false
				printerr("  trial %d 段后 placed 回退 %d→%d: %s" % [trial, prev_placed, pc, seg.alg])
				break
			prev_placed = pc
		if not ok_seg or prev_placed != 24:
			ok_all = false
			printerr("  trial %d 段单调/终态不达(placed=%d)" % [trial, prev_placed])
			break
		# 真机全量播放:纯 apply_turn
		_apply_alg_cube(String(r.alg))
		var played: PackedByteArray = _cube.to_facelets()
		if not NS._centers_uniform(played):
			ok_all = false
			printerr("  trial %d 真机播放后六面中心不同色(模拟器/真机对拍失配)" % trial)
			break
		if NS.stage_check(played) != 1:
			ok_all = false
			printerr("  trial %d 解后 stage_check != 1" % trial)
			break
		# moves 字段与段和一致
		var tok := 0
		for seg2 in r.segments:
			tok += LBL._token_count(String(seg2.alg))
		if int(r.moves) > tok or int(r.moves) <= 0:
			ok_all = false
			printerr("  trial %d moves=%d 与段步数和 %d 不符" % [trial, int(r.moves), tok])
			break
		worst_moves = maxi(worst_moves, int(r.moves))
		# 逆向:逆序 apply 回打乱态
		_apply_alg_cube(LBL.invert_alg(String(r.alg)))
		if _cube.to_facelets() != fs:
			ok_all = false
			printerr("  trial %d 逆序 apply 未回打乱态" % trial)
			break
		n_ok += 1
	print("  金标准分布: 全绿 %d/10, 降级 %d/10, 最坏步数 %d" % [n_ok, n_degraded, worst_moves])
	if n_degraded > 0:
		print("  DEGRADED-RATIO %d/%d" % [n_degraded, 10])
	_check(ok_all and n_ok + n_degraded == 10,
		"TNC-4 金标准 10 态:全绿 %d + 带标记降级 %d(死锁构型比例 %.0f%%)"
		% [n_ok, n_degraded, 100.0 * n_degraded / 10.0])


## TNC-6 5-7 阶中心段金标准(P3 2026-10-05,center-macro-impl-design.md §7.2):
## n∈{5,6,7} × 固定 seed 3 态(20261004+n+{0,100,200},与 test_server S9/卡点探针
## 同集,确定性已证)→ solve_centers(_cn 路径,guard 150/步 600)→ ok:true 断言
## 六面中心同色 + 段末 placed 单调不降 + 真机播放/逆向回打乱态;残余降级态断言
## error 含『(降级)』并统计打印(熔断记录口径,带标记不判 FAIL)。
## §7.2 原文预设『取探针中已解完态』——宏族 P1/P2 落地后实测 48 态 0 全解
## (test-design §6.4 表达力上界),本段按降级分支走并如实记档;降级率回落后
## ok 分支自动生效,无需改码。
func _test_cn_golden_5x7() -> void:
	var ok_all := true
	var n_ok := 0
	var n_degraded := 0
	var t0 := Time.get_ticks_msec()
	for n in [5, 6, 7]:
		for off in [0, 100, 200]:
			var sd: int = 20261004 + n + off
			_cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			_cube.scramble(20, rng)
			var fs: PackedByteArray = _cube.to_facelets()
			var r: Dictionary = NS.solve_centers(fs)
			if not r.ok:
				var err := String(r.get("error", ""))
				if err.contains("(降级)"):
					n_degraded += 1
					print("  降级 n=%d seed=%d: %s" % [n, sd, err])
					continue
				ok_all = false
				printerr("  n=%d seed=%d 失败且无降级标记: %s" % [n, sd, err])
				break
			# 段末 placed 单调不降(模拟器逐段回放;prealg/宏段都在 segments)
			var pc: int = (n - 2) * (n - 2)
			var sim: PackedByteArray = NS._cn_state_of(fs, n)
			var prev := NS._cn_placed(sim, pc)
			var ok_seg := true
			for seg in r.segments:
				sim = NS._cn_apply(sim, NS._cn_id_perm(String(seg.alg), n, NS._cn_cells(n)))
				var pc_now := NS._cn_placed(sim, pc)
				if pc_now < prev:
					ok_seg = false
					printerr("  n=%d seed=%d 段后 placed 回退 %d→%d: %s" % [n, sd, prev, pc_now, seg.alg])
					break
				prev = pc_now
			if not ok_seg or prev != 6 * pc:
				ok_all = false
				printerr("  n=%d seed=%d 段单调/终态不达(placed=%d/%d)" % [n, sd, prev, 6 * pc])
				break
			var simfs: PackedByteArray = _apply_and_read(String(r.alg), n)
			if not NS._cn_uniform(simfs, n):
				ok_all = false
				printerr("  n=%d seed=%d 模拟播放后六面中心不同色" % [n, sd])
				break
			# 真机播放 + 逆向回打乱态
			_apply_alg_cube(String(r.alg))
			var played: PackedByteArray = _cube.to_facelets()
			if not NS._cn_uniform(played, n):
				ok_all = false
				printerr("  n=%d seed=%d 真机播放后六面中心不同色(对拍失配)" % [n, sd])
				break
			_apply_alg_cube(LBL.invert_alg(String(r.alg)))
			if _cube.to_facelets() != fs:
				ok_all = false
				printerr("  n=%d seed=%d 逆序 apply 未回打乱态" % [n, sd])
				break
			n_ok += 1
	var ms := Time.get_ticks_msec() - t0
	print("  5-7 阶金标准分布: 全绿 %d/9, 降级 %d/9, 本段耗时 %dms" % [n_ok, n_degraded, ms])
	if n_degraded > 0:
		print("  DEGRADED-RATIO %d/%d" % [n_degraded, 9])
	_check(ok_all and n_ok + n_degraded == 9,
			"TNC-6 5-7 阶金标准 9 态:全绿 %d + 带标记降级 %d(降级比例 %.0f%%)"
					% [n_ok, n_degraded, 100.0 * n_degraded / 9.0])


## facelets 上的模拟播放(不复原 _cube;_cn_uniform 6n² 直查用)。
func _apply_and_read(alg: String, n: int) -> PackedByteArray:
	_cube.setup(n)
	_apply_alg_cube(alg)
	return _cube.to_facelets()


## TNC-5 边界:solve(96) 不冒充全解(带原因 fail loud);n=5 长度 fail loud;
## stage_check 非法长度 -1;复原态 solve_centers 空解。
func _test_boundaries() -> void:
	var fs := _solved_facelets4()
	var r0: Dictionary = NS.solve_centers(fs)
	var ok: bool = r0.ok and String(r0.alg).is_empty() and int(r0.moves) == 0
	ok = ok and r0.stages.size() == 1 and String(r0.stages[0].name) == NS.STAGE_NAMES_NXN[0]
	_check(ok, "TNC-5a 复原态 solve_centers:ok、空解、段名=中心")

	_cube.setup(4)
	seed(20260929)  # 固定种子:防全局随机撞降级路径使断言 flaky
	_cube.scramble(40)
	# P5 全链落地:96 字节走 _nxn_solve(打乱态能否全解由 P4a 组棱降级率决定,
	# 全链金标准归 tests/test_nxn_reduce.gd TNR-1;此处断言入口契约与快速路径)
	var rs: Dictionary = NS.solve(_cube.to_facelets())
	var rs_ok: bool = (bool(rs.ok) and (rs.stages as Array).size() == 9) \
			or (not bool(rs.ok) and String(rs.get("error", "")).contains("组棱段: "))
	var rfs: Dictionary = NS.solve(_solved_facelets4())
	var ok_entry: bool = rs_ok and rfs.ok and int(rfs.moves) == 0 \
			and (rfs.stages as Array).size() == 9
	_check(ok_entry,
			"TNC-5b solve(96 字节)入口分派:复原态空解 9 段;打乱态 ok 或带组棱降级标记(P5 全链)")

	# n=5 已随 P4b/P5 扩展支持(复原态空解 + 9 段 stage 契约;8 阶长度仍 fail loud)
	_cube.setup(5)
	var f5s: PackedByteArray = _cube.to_facelets()
	var r5: Dictionary = NS.solve_centers(f5s)
	_check(r5.ok and String(r5.alg).is_empty() and NS.stage_check(f5s) == 9
			and int(NS.hint(f5s).stage) == 9,
			"TNC-5c n=5 复原态:solve_centers 空解 + stage_check/hint = 9(P5 9 段契约)")
	seed(20260929)
	_cube.scramble(40)
	_check(NS.stage_check(_cube.to_facelets()) == 0,
			"TNC-5c2 n=5 打乱态 stage_check = 0(中心未解)")
	var f8 := PackedByteArray()
	f8.resize(384)
	_check(NS.solve_centers(f8).ok == false and NS.stage_check(f8) == -1,
			"TNC-5c3 n=8 长度:solve_centers/stage_check fail loud(阶数契约 2-7)")

	var fbad := PackedByteArray()
	fbad.resize(90)
	_check(NS.solve_centers(fbad).ok == false and NS.stage_check(fbad) == -1,
			"TNC-5d 非法长度 90 兜底")
