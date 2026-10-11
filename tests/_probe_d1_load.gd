extends SceneTree
## D1 commit 3 A/B 对账探针(impl-plan §3.3 两步走):
## ①四阶 _fb_ensure 加载路径验证(离线词表 vs 回退现算);
## ②B0 39 卡点态(tests/fixtures/stage0_sigma.json)fallback 终验;
## ③keylock 9 seed(tests/fixtures/d1_keylock_sigma.json)fallback 终验;
## ④随机态 50/阶(共 200)fallback 压力。
## 在 CN_FB_PARITY_FIX=false(关)与 true(开)两次运行下分别跑,ok 数与 token
## 差即引擎侧对账(关侧预期:n5 raw σ 满维恒等=B0 9/9 + keylock 3/3,n6/7 按
## 阶段0 raw 口径 2/15 与 0/15 大面积挂;开侧预期:39/39+9/9——Python 词表
## 机器证明,本探针验证引擎行为与之一致)。
## 不在 CI 清单;复核运行:
## bash -c 'ulimit -v 4000000 && timeout 600 godot --headless -s tests/_probe_d1_load.gd'

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")
const B0_FIX := "res://tests/fixtures/stage0_sigma.json"
const KL_FIX := "res://tests/fixtures/d1_keylock_sigma.json"


func _fb_fallback_verify(st: PackedByteArray, n: int, pc: int) -> Dictionary:
	"""对中心态跑 fallback 并独立重放终验。返回 {ok, tokens, ms}。"""
	if NS._cn_done_mask(st, pc) == 63:
		return {"ok": true, "tokens": 0, "ms": 0}
	var t0 := Time.get_ticks_msec()
	var r: Dictionary = NS._cn_fallback(st, n)
	var ms := Time.get_ticks_msec() - t0
	if r.is_empty():
		return {"ok": false, "tokens": 0, "ms": ms}
	var sim: PackedByteArray = st
	for seg in r.segs:
		sim = NS._cn_apply(sim, seg.perm)
	return {"ok": NS._cn_done_mask(sim, pc) == 63, "tokens": int(r.tokens), "ms": ms}


func _pre(st: PackedByteArray, n: int) -> PackedByteArray:
	var pre: String = NS._cn_prealg(st, n)
	if pre != "":
		st = NS._cn_apply(st, NS._cn_id_perm(pre, n, NS._cn_cells(n)))
	return st


func _arr2st(a: Array) -> PackedByteArray:
	var st := PackedByteArray()
	st.resize(a.size())
	for i in a.size():
		st[i] = int(a[i])
	return st


func _initialize() -> void:
	var b0: Dictionary = JSON.parse_string(FileAccess.open(B0_FIX, FileAccess.READ).get_as_text())
	var kl: Dictionary = JSON.parse_string(FileAccess.open(KL_FIX, FileAccess.READ).get_as_text())
	var b0_by_n: Dictionary = {}
	for s in b0.stuck_states:
		var nk := int(s.n)
		var arr: Dictionary = b0_by_n.get(nk, {"states": [], "n": nk})
		(arr.states as Array).append(s)
		b0_by_n[nk] = arr
	var kl_by_n: Dictionary = {}
	for s in kl.keylock_states:
		var nk2 := int(s.n)
		var arr2: Dictionary = kl_by_n.get(nk2, {"states": [], "n": nk2})
		(arr2.states as Array).append(s)
		kl_by_n[nk2] = arr2

	# ---- ① 加载路径 ----
	print("== ① _fb_ensure 加载路径(PARITY_FIX=%s) ==" % ("true" if NS.CN_FB_PARITY_FIX else "false"))
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		var fb: Dictionary = NS._fb_ensure(n)
		print("n=%d: ensure %dms levels=%d gens=%d" % [n,
				Time.get_ticks_msec() - t0, (fb.levels as Array).size(), (fb.gens as Array).size()])
	# ---- ②③④ fallback 对账 ----
	var grand := {"ok": 0, "tot": 0}
	for n in [4, 5, 6, 7]:
		var pc: int = (n - 2) * (n - 2)
		# ② B0 卡点态
		var b0e: Dictionary = b0_by_n.get(n, {"states": []})
		var ok2 := 0
		var tok2 := 0
		for s in b0e.states:
			var st := _pre(_arr2st(s.st), n)
			var v := _fb_fallback_verify(st, n, pc)
			ok2 += 1 if v.ok else 0
			tok2 += int(v.tokens)
		grand.ok += ok2
		grand.tot += (b0e.states as Array).size()
		# ③ keylock 9 seed
		var kle: Dictionary = kl_by_n.get(n, {"states": []})
		var ok3 := 0
		var tok3 := 0
		for s in kle.states:
			var st2 := _pre(_arr2st(s.st), n)
			var v2 := _fb_fallback_verify(st2, n, pc)
			ok3 += 1 if v2.ok else 0
			tok3 += int(v2.tokens)
		grand.ok += ok3
		grand.tot += (kle.states as Array).size()
		# ④ 随机态 50
		var ok4 := 0
		var tok4 := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 800000 + n
		for trial in 50:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			cube.scramble(40, rng)
			var st3 := _pre(NS._cn_state_of(cube.to_facelets(), n), n)
			cube.free()
			var v3 := _fb_fallback_verify(st3, n, pc)
			ok4 += 1 if v3.ok else 0
			tok4 += int(v3.tokens)
		grand.ok += ok4
		grand.tot += 50
		print("n=%d: B0 %d/%d(keylock %d/%d) 随机 %d/50 | tokens B0=%d KL=%d RND=%d" % [n,
				ok2, (b0e.states as Array).size(), ok3, (kle.states as Array).size(),
				ok4, tok2, tok3, tok4])
	print("== 总计 fallback ok %d/%d (PARITY_FIX=%s) ==" % [grand.ok, grand.tot,
			"true" if NS.CN_FB_PARITY_FIX else "false"])
	quit(0)
