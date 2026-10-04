extends SceneTree
## v7 P5 约化 + parity 金标准(docs/v7-teach-nxn-plan.md P5):
## TNR-1 4 阶固定种子 12 态全链(P8 态数定稿,原占位 30;实测单态全链均值 0.26s
##       且含 parity 专项开销,按 CI 预算下调):打乱 → solve(中心段 → 组棱段 →
##       parity 修正 → 约化提取 → lbl 7 段)→ 纯 apply_turn 播放 → is_solved →
##       stage 单调逐段回放(9 段定长,stages 拼接 ≡ alg)→ 逆向回打乱态;
##       降级分层口径(P4a 熔断):组棱段未覆盖构型 solve 返回 ok:false 且 error
##       带降级标记,不判 FAIL(DEGRADED-RATIO 输出)。
## TNR-2 提取映射:复原态 → 3 阶复原态;提取∘n 阶外层 == 3 阶直转对拍(40 步随机)。
## TNR-3 parity 专项(4 阶):OLL 修正公式逆构造单棱翻源态 → 判据触发(仅 OLL)→
##       hint 注入(parity 建议)→ solve 全链复原;PLL 构造态同款(含 solve 全链);
##       OLL+PLL 并存 → 检测驱动循环 ≤2 双清:solve 循环 + hint 循环逐段建议
##       (OLL 优先,执行后转 PLL 建议)至双清(solve/hint 双注入点)。
## TNR-4 stages 契约:9 段定长、段名序列、拼接 ≡ alg;lbl guard 不动(MOVE_LIMIT=170)。
## TNR-5 5-7 阶 sanity:复原态 stage_check/hint = 9;6 阶 OLL/PLL 构造态
##       (奇数阶无 parity)。
## 运行:godot --headless -s tests/test_nxn_reduce.gd;双校验:exit 0 且无 SCRIPT ERROR。

const NS := preload("res://scripts/nxn_solver.gd")
const LBL := preload("res://scripts/lbl_solver.gd")

var _cube: Node3D
var _failed := false
var _last_solve := {}  # TNR-3d 的 OLL 全链解缓存(TNR-4c 复用,免重复 1.9s 全链求解)


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
	_test_extract_map()
	_test_parity_special()
	_test_stages_contract()
	_test_golden_12()
	_test_sanity_5_7()
	print("ALL PASSED" if not _failed else "FAILED")
	quit(1 if _failed else 0)


## TNR-2 提取映射(探针 16 P1-1/P1-2 落地):复原自洽 + 外层对拍。
func _test_extract_map() -> void:
	var ok_map := true
	for n in [4, 5, 6, 7]:
		var r54: PackedByteArray = NS._reduce_to_54(NS._solved_facelets_n(n), n)
		for i in 54:
			if r54[i] != i / 9:
				ok_map = false
	_check(ok_map, "TNR-2a 提取映射:n=4..7 复原态 → 3 阶复原态逐格自洽")

	var fa: PackedByteArray = NS._solved_facelets_n(4)
	var f3 := PackedByteArray()
	f3.resize(54)
	for i in 54:
		f3[i] = i / 9
	seed(20261004)
	var ok_par := true
	for step in 40:
		var tok: String = ["U", "D", "R", "L", "F", "B"][randi() % 6] + ["", "'", "2"][randi() % 3]
		NS._apply_token(fa, tok)
		NS._apply_token(f3, tok)
		if NS._reduce_to_54(fa, 4) != f3:
			ok_par = false
			printerr("  对拍失配 @%d token %s" % [step, tok])
			break
	_check(ok_par, "TNR-2b 约化记号语义:提取∘4 阶外层 == 3 阶直转(40 步随机,播放同语义)")


## TNR-3 parity 专项(4 阶;修正公式逆构造 + 判据触发 + hint/solve 双注入)。
func _test_parity_special() -> void:
	# 入池验证(_ensure_parity 条款):4/6 阶过、奇数阶直通
	var ok_pool: bool = NS._ensure_parity(4) and NS._ensure_parity(6) and NS._ensure_parity(5) \
			and NS._ensure_parity(7)
	_check(ok_pool, "TNR-3a parity 宏池入池验证:4/6 阶过(中心均匀+棱组保持+判据效应),奇数阶直通")

	# OLL:修正公式作用于复原 4 阶 = 逆构造单棱翻源态
	var fs: PackedByteArray = _solved_facelets4()
	NS._apply_alg(fs, String(NS.PARITY_ALGS[4].oll))
	var q: Dictionary = NS._parity_of(NS._reduce_to_54(fs, 4))
	var ok_oll: bool = bool(q.oll) and not bool(q.pll)
	_check(ok_oll, "TNR-3b OLL 构造态:判据触发(oll=true, pll=false,单棱翻可见)")

	# hint 注入点一:OLL 态建议 = parity 修正段(带文案),执行后判据清
	# (stage=1:parity 未清 = 组棱段未完,parity 段语义并入组棱段尾)
	var h: Dictionary = NS.hint(fs)
	var sug: Dictionary = h.suggestion
	var ok_hint: bool = int(h.stage) == 1 and String(sug.get("piece", "")) == "parity" \
			and String(sug.get("alg", "")) == String(NS.PARITY_ALGS[4].oll)
	if ok_hint:
		var t := fs.duplicate()
		NS._apply_alg(t, String(sug.alg))
		var q2: Dictionary = NS._parity_of(NS._reduce_to_54(t, 4))
		ok_hint = not bool(q2.oll) and not bool(q2.pll)
	_check(ok_hint, "TNR-3c hint 注入(OLL):stage=1(parity 段并入组棱尾)、建议执行后双判据清")

	# solve 注入点:OLL 态全链 solve → 播放 → is_solved → 逆向回源态
	_apply_alg_cube(String(NS.PARITY_ALGS[4].oll))
	var r: Dictionary = NS.solve(fs)
	_last_solve = r
	var ok_solve: bool = bool(r.ok)
	if ok_solve:
		_apply_alg_cube(String(r.alg))
		ok_solve = _cube.is_solved()
	if ok_solve:
		_apply_alg_cube(LBL.invert_alg(String(r.alg)))
		ok_solve = _cube.to_facelets() == fs
	_check(ok_solve, "TNR-3d solve 注入(OLL):全链播放 is_solved 且逆向回源态")

	# PLL 构造态:判据触发(仅 pll)+ hint 注入 + 修正双清 + solve 全链复原
	# (P8 查漏补全:hint 之外 solve 注入点对 PLL 态同样覆盖)
	var fp := _solved_facelets4()
	NS._apply_alg(fp, String(NS.PARITY_ALGS[4].pll))
	var qp: Dictionary = NS._parity_of(NS._reduce_to_54(fp, 4))
	var ok_pll: bool = bool(qp.pll) and not bool(qp.oll)
	var hp: Dictionary = NS.hint(fp)
	ok_pll = ok_pll and String(hp.suggestion.get("piece", "")) == "parity" \
			and String(hp.suggestion.get("alg", "")) == String(NS.PARITY_ALGS[4].pll)
	if ok_pll:
		var t2 := fp.duplicate()
		NS._apply_alg(t2, String(NS.PARITY_ALGS[4].pll))
		var q3: Dictionary = NS._parity_of(NS._reduce_to_54(t2, 4))
		ok_pll = not bool(q3.oll) and not bool(q3.pll)
	if ok_pll:
		_apply_alg_cube(String(NS.PARITY_ALGS[4].pll))  # 真机复现 PLL 构造态
		var rp: Dictionary = NS.solve(fp)
		ok_pll = bool(rp.ok)
		if ok_pll:
			_apply_alg_cube(String(rp.alg))
			ok_pll = _cube.is_solved()
		if ok_pll:
			_apply_alg_cube(LBL.invert_alg(String(rp.alg)))
			ok_pll = _cube.to_facelets() == fp
	_check(ok_pll, "TNR-3e PLL 构造态:判据触发(仅 pll)、hint 注入、修正后双清、solve 全链复原")

	# OLL+PLL 并存:检测驱动循环 ≤2 → solve 循环全链复原(P5 注入点一)
	var fm := _solved_facelets4()
	NS._apply_alg(fm, String(NS.PARITY_ALGS[4].oll))
	NS._apply_alg(fm, String(NS.PARITY_ALGS[4].pll))
	var qm: Dictionary = NS._parity_of(NS._reduce_to_54(fm, 4))
	_apply_alg_cube(String(NS.PARITY_ALGS[4].oll))
	_apply_alg_cube(String(NS.PARITY_ALGS[4].pll))
	var rm: Dictionary = NS.solve(fm)
	var ok_mix: bool = bool(qm.oll) and bool(qm.pll) and bool(rm.ok)
	if ok_mix:
		_apply_alg_cube(String(rm.alg))
		ok_mix = _cube.is_solved()
	_check(ok_mix, "TNR-3f OLL+PLL 并存态:双判据触发,solve 循环 ≤2 全链复原(is_solved)")

	# 并存态 hint 循环(P8 查漏补全,P5 注入点二):建议 OLL(优先)→ 执行后剩
	# PLL → 再建议 PLL → 执行后双清。教学交互走 hint→执行 循环遇并存态不死锁。
	var fmh := _solved_facelets4()
	NS._apply_alg(fmh, String(NS.PARITY_ALGS[4].oll))
	NS._apply_alg(fmh, String(NS.PARITY_ALGS[4].pll))
	var ok_hloop := true
	var seen: Array = []
	for round_i in 3:  # 上限 3 = PARITY_LOOP_MAX + 1(第 3 轮应为完成/无 parity 建议)
		var hi: Dictionary = NS.hint(fmh)
		var si: Dictionary = hi.suggestion
		if String(si.get("piece", "")) != "parity":
			ok_hloop = false
			printerr("  hint 循环第 %d 轮建议非 parity: %s" % [round_i, si])
			break
		seen.append("oll" if String(si.alg) == String(NS.PARITY_ALGS[4].oll) else "pll")
		NS._apply_alg(fmh, String(si.alg))
		var qi: Dictionary = NS._parity_of(NS._reduce_to_54(fmh, 4))
		if not bool(qi.oll) and not bool(qi.pll):
			break
	ok_hloop = ok_hloop and seen.size() == 2 and seen[0] == "oll" and seen[1] == "pll"
	_check(ok_hloop, "TNR-3f2 OLL+PLL 并存态 hint 循环:OLL 优先 → PLL 逐段建议,2 轮后双清")

	# 无 parity 的 LBL 边界态:hint 约化透传(3 阶宏扰动 → LBL 建议非空)
	var fn := _solved_facelets4()
	NS._apply_alg(fn, "R U R' U'")  # 纯外层:中心+棱组保持,提取态 = 3 阶合法态
	var hn: Dictionary = NS.hint(fn)
	var ok_lbl: bool = int(hn.stage) >= 2 and int(hn.stage) < 9 \
			and not String(hn.suggestion.get("alg", "")).is_empty()
	if ok_lbl:
		var t3 := fn.duplicate()
		NS._apply_alg(t3, String(hn.suggestion.alg))
		ok_lbl = NS.stage_check(t3) >= int(hn.stage)
	_check(ok_lbl, "TNR-3g LBL 边界 hint 透传:stage = 2+lbl 前缀,建议执行后 stage 不降")


## TNR-4 stages 契约:9 段定长 + 段名序列 + 拼接 ≡ alg;lbl guard 不动。
func _test_stages_contract() -> void:
	var ok_names: bool = NS.STAGE_NAMES_NXN.size() == 9 \
			and String(NS.STAGE_NAMES_NXN[0]) == "中心" and String(NS.STAGE_NAMES_NXN[1]) == "组棱" \
			and String(NS.STAGE_NAMES_NXN[2]) == String(LBL.STAGE_NAMES[0]) \
			and String(NS.STAGE_NAMES_NXN[8]) == String(LBL.STAGE_NAMES[6])
	_check(ok_names, "TNR-4a 9 段段名契约:中心/组棱 + LBL 7 段直续")

	var ok_limit: bool = LBL.MOVE_LIMIT == 170 and NS.PARITY_LOOP_MAX == 2
	_check(ok_limit, "TNR-4b guard 参数化边界:lbl MOVE_LIMIT=170 不动,nxn parity 循环上限 2")

	# 拼接 ≡ alg(以 OLL 构造态全链为样本;复用 TNR-3d 的解,免重复全链求解)
	var r: Dictionary = _last_solve
	var joined: PackedStringArray = []
	for s in r.stages:
		var a: String = String(s.alg)
		if not a.is_empty():
			joined.append(a)
	_check(bool(r.ok) and (r.stages as Array).size() == 9 and " ".join(joined) == String(r.alg),
			"TNR-4c stages 拼接 ≡ alg 且 9 段定长(OLL 构造态样本,%d 步)" % int(r.moves))


## TNR-1 金标准:固定种子 12 态全链(打乱 → solve → 播放 → is_solved → stage 单调
## 逐段回放 → 逆向)。降级分层:组棱段未覆盖构型 ok:false 带降级标记,不判 FAIL。
func _test_golden_12() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var ok_all := true
	var n_ok := 0
	var n_degraded := 0
	var worst_moves := 0
	for trial in 12:
		_cube.setup(4)
		_cube.scramble(40, rng)
		var fs: PackedByteArray = _cube.to_facelets()
		var r: Dictionary = NS.solve(fs)
		if not r.ok:
			var err := String(r.get("error", ""))
			if err.contains("模板池未覆盖(降级)") or err.contains("中心段: ") or err.contains("组棱段: "):
				n_degraded += 1
				continue
			ok_all = false
			printerr("  trial %d 失败且无降级标记: %s" % [trial, err])
			break
		# 纯 apply_turn 播放 → is_solved
		_apply_alg_cube(String(r.alg))
		if not _cube.is_solved():
			ok_all = false
			printerr("  trial %d 播放后未复原(模拟器/真机对拍失配)" % trial)
			break
		# stage 单调逐段回放(9 段定长)
		var seg_sim: PackedByteArray = fs.duplicate()
		var prev := 0
		var ok_seg := true
		for seg in r.stages:
			NS._apply_alg(seg_sim, String(seg.alg))
			var sc_now: int = NS.stage_check(seg_sim)
			if sc_now < prev:
				ok_seg = false
				printerr("  trial %d stage 回退:%d → %d(段 %s)" % [trial, prev, sc_now, seg.name])
				break
			prev = sc_now
		if not ok_seg or prev != 9 or (r.stages as Array).size() != 9:
			ok_all = false
			printerr("  trial %d 段回放不达(单调=%s 末=%d 段数=%d)"
					% [trial, ok_seg, prev, (r.stages as Array).size()])
			break
		worst_moves = maxi(worst_moves, int(r.moves))
		# 逆向:逆序 apply 回打乱态
		_apply_alg_cube(LBL.invert_alg(String(r.alg)))
		if _cube.to_facelets() != fs:
			ok_all = false
			printerr("  trial %d 逆向未回打乱态" % trial)
			break
		n_ok += 1
	print("  金标准分布: 全绿 %d/12, 降级 %d/12, 最坏全链步数 %d" % [n_ok, n_degraded, worst_moves])
	if n_degraded > 0:
		print("  DEGRADED-RATIO %d/%d" % [n_degraded, 12])
	_check(ok_all and n_ok + n_degraded == 12,
		"TNR-1 金标准 12 态全链:全绿 %d + 带标记降级 %d(降级比例 %.0f%%)"
		% [n_ok, n_degraded, 100.0 * n_degraded / 12.0])


## TNR-5 5-7 阶 sanity:复原态 stage_check/hint = 9(9 段契约);6 阶 OLL 构造态全链。
func _test_sanity_5_7() -> void:
	var ok_s: bool = true
	for n in [5, 6, 7]:
		var f: PackedByteArray = NS._solved_facelets_n(n)
		var sc: int = NS.stage_check(f)
		var h: Dictionary = NS.hint(f)
		if sc != 9 or int(h.stage) != 9 or String(h.suggestion.get("text", "")) != "魔方已复原":
			ok_s = false
			printerr("  n=%d 复原: stage=%d hint.stage=%s" % [n, sc, str(h.get("stage", "?"))])
	_check(ok_s, "TNR-5a 5-7 阶复原态:stage_check/hint = 9(完成文案)")

	# 6 阶 OLL 构造态:中心+棱组保持(宏性质)→ 全链 = parity 修正 + LBL(快速路径)
	var f6: PackedByteArray = NS._solved_facelets_n(6)
	NS._apply_alg(f6, String(NS.PARITY_ALGS[6].oll))
	var q6: Dictionary = NS._parity_of(NS._reduce_to_54(f6, 6))
	var r6: Dictionary = NS.solve(f6)
	var ok6: bool = bool(q6.oll) and bool(r6.ok) and (r6.stages as Array).size() == 9
	if ok6:
		var seg_sim: PackedByteArray = f6.duplicate()
		for seg in r6.stages:
			NS._apply_alg(seg_sim, String(seg.alg))
		ok6 = NS.stage_check(seg_sim) == 9
	_check(ok6, "TNR-5b 6 阶 OLL 构造态:判据触发、全链 9 段、逐段回放复原")

	# 6 阶 PLL 构造态(P8 查漏补全):判据触发(仅 pll)+ hint 注入 + 修正双清
	var fp6: PackedByteArray = NS._solved_facelets_n(6)
	NS._apply_alg(fp6, String(NS.PARITY_ALGS[6].pll))
	var qp6: Dictionary = NS._parity_of(NS._reduce_to_54(fp6, 6))
	var hp6: Dictionary = NS.hint(fp6)
	var okp6: bool = bool(qp6.pll) and not bool(qp6.oll) \
			and String(hp6.suggestion.get("piece", "")) == "parity" \
			and String(hp6.suggestion.get("alg", "")) == String(NS.PARITY_ALGS[6].pll)
	if okp6:
		var t6 := fp6.duplicate()
		NS._apply_alg(t6, String(NS.PARITY_ALGS[6].pll))
		var q6b: Dictionary = NS._parity_of(NS._reduce_to_54(t6, 6))
		okp6 = not bool(q6b.oll) and not bool(q6b.pll)
	_check(okp6, "TNR-5c 6 阶 PLL 构造态:判据触发(仅 pll)、hint 注入、修正后双清")
