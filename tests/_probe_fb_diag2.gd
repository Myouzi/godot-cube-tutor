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
	var m: int = fb.m
	var pc: int = fb.pc
	var orbit_of: PackedInt32Array = fb.orbit_of
	var og: Dictionary = fb.orbit_groups
	var total_in_groups := 0
	for t in og:
		total_in_groups += (og[t] as Array).size()
	print("m=%d groups_total=%d 轨道数=%d" % [m, total_in_groups, og.size()])
	var sizes := []
	for t in og:
		sizes.append((og[t] as Array).size())
	sizes.sort()
	print("轨道大小: ", str(sizes))
	# gens 层转数量
	var ng := (fb.gens as Array).size()
	print("gens=", ng)
	# 每轨每色 cur vs home
	var cur_by := {}
	var home_by := {}
	for i in m:
		var kc := "%d_%d" % [orbit_of[i], st[i]]
		cur_by[kc] = int(cur_by.get(kc, 0)) + 1
		var kh := "%d_%d" % [orbit_of[i], i / pc]
		home_by[kh] = int(home_by.get(kh, 0)) + 1
	var bad := 0
	for k in cur_by:
		if int(cur_by[k]) != int(home_by.get(k, 0)):
			bad += 1
			if bad <= 5:
				print("违约 k=", k, " cur=", cur_by[k], " home=", home_by.get(k, 0))
	for k in home_by:
		if not cur_by.has(k):
			bad += 1
			if bad <= 5:
				print("home-only k=", k, " home=", home_by[k])
	print("违约组数=", bad)
	quit(0)
