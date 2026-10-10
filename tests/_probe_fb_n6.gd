extends SceneTree
## 一次性探针(2026-10-10,v7.3 D1 n=6/7 链质量分阶诊断):
## 对单阶跑 _fb_build(6, cap) 三个 cap 档,打印各级 trans/s 规模 + 自检结果,
## 过自检档再跑 5 随机态 fallback。定位「小 cap 覆盖不足 / 大 cap 爆炸」分界。
## 不在 CI 清单;复核运行(内存护栏):
##   bash -c 'ulimit -v 4000000; timeout 300 godot --headless -s tests/_probe_fb_n6.gd'

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")


func _probe_cap(n: int, cap: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var fb: Dictionary = NS._fb_build(n, cap)
	var ms := Time.get_ticks_msec() - t0
	var levels: Array = fb.levels
	var small := []
	for i in levels.size():
		var lv: Dictionary = levels[i]
		small.append("%d/%d" % [(lv.trans as Dictionary).size(), (lv.s as Array).size()])
	var ok := NS._fb_selfcheck(fb, n)
	print("n=%d cap=%d: %dms levels=%d gens=%d 自检=%s" % [n, cap, ms,
			levels.size(), (fb.gens as Array).size(), "PASS" if ok else "FAIL"])
	print("  级[trans/s]: ", " ".join(PackedStringArray(small)))
	return {"fb": fb, "ok": ok, "ms": ms, "cap": cap}


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		print("")
		var chosen: Dictionary = {"fb": {}, "ok": false, "ms": 0, "cap": 0}
		for cap in [64]:
			var r: Dictionary = _probe_cap(n, cap)
			if r.ok and not (chosen.ok as bool):
				chosen = r
		if (chosen.fb as Dictionary).is_empty():
			print("n=%d: 三档自检全 FAIL,跳过随机态" % n)
			continue
		# 过自检档跑 5 随机态
		var fb: Dictionary = chosen.fb
		var ok_cnt := 0
		var max_tok := 0
		for trial in 5:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = 700000 + n * 100 + trial
			cube.scramble(20, rng)
			var st: PackedByteArray = NS._cn_state_of(cube.to_facelets(), n)
			var pc: int = (n - 2) * (n - 2)
			var pre: String = NS._cn_prealg(st, n)
			if pre != "":
				st = NS._cn_apply(st, NS._cn_id_perm(pre, n, NS._cn_cells(n)))
			if NS._cn_done_mask(st, pc) == 63:
				ok_cnt += 1
				continue
			var t0 := Time.get_ticks_msec()
			var res: Dictionary = NS._cn_fallback(st, n)
			var ms := Time.get_ticks_msec() - t0
			if res.is_empty():
				print("  n=%d trial=%d fallback FAIL (%dms)" % [n, trial, ms])
				continue
			var sim: PackedByteArray = st
			for seg in res.segs:
				sim = NS._cn_apply(sim, seg.perm)
			var done: bool = NS._cn_done_mask(sim, pc) == 63
			print("  n=%d trial=%d %s tokens=%d (%dms)" % [n, trial,
					"OK" if done else "终验FAIL", int(res.tokens), ms])
			if done:
				ok_cnt += 1
				max_tok = maxi(max_tok, int(res.tokens))
		print("n=%d cap=%d 随机态: ok=%d/5 最大 token %d" % [n, chosen.cap, ok_cnt, max_tok])
	quit(0)
