extends SceneTree
const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")
func _initialize() -> void:
	var n := 6
	var fb: Dictionary = NS._fb_ensure(n)
	var cube: Node3D = CUBE.new()
	cube.setup(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 700600
	cube.scramble(20, rng)
	var st: PackedByteArray = NS._cn_state_of(cube.to_facelets(), n)
	var pre0: String = NS._cn_prealg(st, n)
	if pre0 != "":
		st = NS._cn_apply(st, NS._cn_id_perm(pre0, n, NS._cn_cells(n)))
	var gens: Array = fb.gens
	var levels: Array = fb.levels
	var gen_inv: Array = fb.gen_inv
	var m: int = fb.m
	var sigma: PackedInt32Array = NS._fb_sigma_of(st, fb)
	print("sigma empty=", sigma.is_empty())
	if sigma.is_empty():
		quit(0)
		return
	var s := sigma.duplicate()
	var fail_lv := -1
	for i in levels.size():
		var p: int = s[i]
		if p == i:
			continue
		var trans: Dictionary = levels[i].trans
		if not trans.has(p):
			fail_lv = i
			print("trans 缺: 级 %d s(%d)=%d |trans|=%d" % [i, i, p, trans.size()])
			break
		var uflat: PackedInt32Array = (trans[p] as Dictionary).flat
		var uinv := NS._fb_chain_perm(NS._fb_chain_inv(uflat, gen_inv), gens, m)
		s = NS._fb_comp_first_second(uinv, s, m)
	if fail_lv < 0:
		print("sift 全过 残差id=", NS._fb_is_id(s, m, m), " 非不动点=", range(m).filter(func(x): return s[x] != x).size())
		# 双逆序重放
		quit(0)
		return
	# trans 缺的级:该级 s_cur 大小与轨道
	var lv: Dictionary = levels[fail_lv]
	print("失败级 s_cur=", (lv.s as Array).size(), " trans 点数=", (lv.trans as Dictionary).size())
	# 检查缺的值属于哪个点集
	var miss_vals := {}
	for i2 in range(fail_lv, m):
		var p2: int = s[i2]
		if p2 != i2 and not lv.trans.has(p2):
			miss_vals[p2] = true
	print("缺失目标值样例: ", str(miss_vals.keys().slice(0, 8)))
	quit(0)
## 追加:sigma_of 内部路径诊断版(复制逻辑打印出口)
