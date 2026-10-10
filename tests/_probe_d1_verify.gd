extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 保底器实测):
## ①构建成本:_fb_ensure(n) 四阶各一次(SS 链,含 Schreier 递推)——记档 ms;
## ②随机错态求解:随机打乱 → 主通路 _cn_segment 推到穷尽(或直接用随机态)
##   → _cn_fallback → 终验(探针内独立重放 done_mask==63);
## ③CN_KEY_LOCK 9 seed 卡点态实测:复刻 _cn_solve 到卡点 → fallback → ok?
##   → 记表达式 token 数与耗时(0% 硬目标的直接证据)。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_verify.gd

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")

const KEY_LOCK := {5: {20261009: "1056292279", 20261109: "2092487133", 20261209: "1419916045"},
		6: {20261010: "1395471020", 20261110: "4080059418", 20261210: "2633837371"},
		7: {20261011: "1606329917", 20261111: "1335305809", 20261211: "1992924430"}}


func _initialize() -> void:
	# ---- ①构建成本 ----
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		var fb: Dictionary = NS._fb_ensure(n)
		var levels: Array = fb.levels
		var nonempty := 0
		for lv in levels:
			if (lv.s as Array).size() > 0:
				nonempty += 1
		print("构建 n=%d: %dms, levels=%d(非空生成元级 %d), gens=%d" % [n,
				Time.get_ticks_msec() - t0, levels.size(), nonempty, (fb.gens as Array).size()])
	# ---- ②随机错态:打乱 → 直接对中心态跑 fallback(不做主通路,纯随机 σ
	#      完备性压力测试,50 态/阶) ----
	print("")
	for n in [4, 5, 6, 7]:
		var cube: Node3D = CUBE.new()
		var ok_cnt := 0
		var fail_cnt := 0
		var total_ms := 0
		var max_tok := 0
		for trial in 10:
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = 700000 + n * 100 + trial
			cube.scramble(20, rng)
			var fs: PackedByteArray = cube.to_facelets()
			# 直接对「中心段起点态」跑 fallback(不经过主通路——σ 任意性压力)
			var st: PackedByteArray = NS._cn_state_of(fs, n)
			var pc: int = (n - 2) * (n - 2)
			# 契约:先 prealg(真中心换面态 fallback 域外,v7.1 同款)
			var pre0: String = NS._cn_prealg(st, n)
			if pre0 != "":
				st = NS._cn_apply(st, NS._cn_id_perm(pre0, n, NS._cn_cells(n)))
			if NS._cn_done_mask(st, pc) == 63:
				ok_cnt += 1
				continue
			var t0 := Time.get_ticks_msec()
			var r: Dictionary = NS._cn_fallback(st, n)
			total_ms += Time.get_ticks_msec() - t0
			if r.is_empty():
				fail_cnt += 1
				print("  n=%d trial=%d fallback FAIL" % [n, trial])
				continue
			# 独立重放终验
			var sim: PackedByteArray = st
			for seg in r.segs:
				sim = NS._cn_apply(sim, seg.perm)
			if NS._cn_done_mask(sim, pc) == 63:
				ok_cnt += 1
				max_tok = maxi(max_tok, int(r.tokens))
			else:
				fail_cnt += 1
				print("  n=%d trial=%d 终验 FAIL(tokens=%d)" % [n, trial, int(r.tokens)])
		print("随机态 n=%d: ok=%d/10 fail=%d 平均 %dms 最大 token %d" % [n,
				ok_cnt, fail_cnt, total_ms / 50, max_tok])
	# ---- ③9 seed 卡点态 ----
	print("")
	for n in [5, 6, 7]:
		for sd: int in KEY_LOCK[n]:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			cube.scramble(20, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var st: PackedByteArray = NS._cn_state_of(fs, n)
			var pc: int = (n - 2) * (n - 2)
			var pre: String = NS._cn_prealg(st, n)
			if pre != "":
				st = NS._cn_apply(st, NS._cn_id_perm(pre, n, NS._cn_cells(n)))
			# 主循环到卡点(与 _cn_solve 同款确定性路径)
			var guard := 0
			var total := 0
			while NS._cn_done_mask(st, pc) != 63:
				guard += 1
				if guard > NS.CN_STAGE_GUARD or total >= NS.CN_MOVE_LIMIT:
					break
				var seg: Dictionary = NS._cn_segment(st, n)
				if seg.is_empty():
					break
				for mm in (seg.segs if seg.has("segs") else [seg]):
					st = NS._cn_apply(st, mm.perm)
					total += int(mm.tokens)
			if NS._cn_done_mask(st, pc) == 63:
				print("n=%d seed=%d: 主通路已解(?!)" % [n, sd])
				continue
			var t0 := Time.get_ticks_msec()
			var r2: Dictionary = NS._cn_fallback(st, n)
			var ms := Time.get_ticks_msec() - t0
			if r2.is_empty():
				print("n=%d seed=%d: 卡点态 key=%d fallback FAIL (%dms)" % [n, sd, NS._cn_key(st), ms])
				continue
			var sim: PackedByteArray = st
			for seg in r2.segs:
				sim = NS._cn_apply(sim, seg.perm)
			var done: bool = NS._cn_done_mask(sim, pc) == 63
			print("n=%d seed=%d: fallback %s tokens=%d segs=%d (%dms)%s" % [n, sd,
					"OK" if done else "终验FAIL", int(r2.tokens), (r2.segs as Array).size(), ms,
					"" if done else " —— PROBE-BUG"])
	quit(0)
