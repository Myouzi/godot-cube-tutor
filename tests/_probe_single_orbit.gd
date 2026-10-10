extends SceneTree
## 一次性探针(2026-10-10,v7.3 D1 轨道级联 SS 前置存在性实验):
## 全群 gens 随机积采样,统计「支持 ⊆ 单轨」的元——若每轨能收集到传递连接
## 的 3-环类样本(Jordan:传递+3-环 ⟹ 生成 A_24),则每轨可独立建小 SS
## (24 点,秒级),替代全群 SS(n≥5 数量级不可行,实测 n=5 卡死)。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_single_orbit.gd

const NS := preload("res://scripts/nxn_solver.gd")


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		# gens 池(与 _fb_build 同款)
		var gens: Array = []
		var seen: Dictionary = {}
		for f in ["U", "R", "F", "D", "L", "B"]:
			for suf in ["", "'", "2"]:
				var ta: String = f + suf
				var tp := NS._cn_id_perm(ta, n, cells)
				var kk := NS._fb_key(tp)
				if not seen.has(kk):
					seen[kk] = true
					gens.append(tp)
		for d in range(3, n):
			for f2 in ["U", "R", "F", "D", "L", "B"]:
				for suf2 in ["", "'", "2"]:
					var ta2: String = "%d%s%s" % [d, f2, suf2]
					var tp2 := NS._cn_id_perm(ta2, n, cells)
					var kk2 := NS._fb_key(tp2)
					if not seen.has(kk2):
						seen[kk2] = true
						gens.append(tp2)
		var ctx0: Dictionary = NS._cn_ensure(n)
		for key3 in ["end_atoms", "bfs_atoms"]:
			for e: Dictionary in ctx0[key3]:
				var ep: PackedInt32Array = e.perm
				var mv := 0
				for k2 in m:
					if ep[k2] != k2:
						mv += 1
				if mv == 0 or mv > 12:
					continue
				var kk3 := NS._fb_key(ep)
				if not seen.has(kk3):
					seen[kk3] = true
					gens.append(ep)
		# 轨道表(并查集 by gens)
		var uf := NS._UnionFindP.new(m)
		for gp in gens:
			for j in m:
				uf.union(j, gp[j])
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		var orbit_groups: Dictionary = {}
		for j in m:
			var r: int = uf.find(j)
			orbit_of[j] = r
			if not orbit_groups.has(r):
				orbit_groups[r] = []
			(orbit_groups[r] as Array).append(j)
		# 随机积采样(深度 2..6)
		var rng := RandomNumberGenerator.new()
		rng.seed = 31337 + n
		var per_orbit: Dictionary = {}   # 轨道代表 -> {sup3:0, sup2:0, other:0, pts:{}, cyc:[]}
		for t in orbit_groups:
			per_orbit[t] = {"sup3": 0, "sup2": 0, "other": 0, "pts": {}, "cyc": []}
		var sample_cnt := 300000
		for it in sample_cnt:
			var p := NS._fb_id(m)
			var depth := 2 + rng.randi() % 5
			for dstep in depth:
				var g: PackedInt32Array = gens[rng.randi() % gens.size()]
				p = NS._fb_comp_first_second(p, g, m)
			# 支持集
			var sup := PackedInt32Array()
			for k4 in m:
				if p[k4] != k4:
					sup.append(k4)
			if sup.is_empty():
				continue
			var t0g: int = orbit_of[sup[0]]
			var all_same := true
			for a in sup.size():
				if orbit_of[sup[a]] != t0g:
					all_same = false
					break
			if not all_same:
				continue
			var rec: Dictionary = per_orbit[t0g]
			if sup.size() == 3:
				rec.sup3 += 1
				if (rec.cyc as Array).size() < 400:
					(rec.cyc as Array).append(p)
			elif sup.size() == 2:
				rec.sup2 += 1
			else:
				rec.other += 1
			for a2 in sup.size():
				(rec.pts as Dictionary)[sup[a2]] = true
		print("n=%d gens=%d 轨道=%s 采样=%d (%dms)" % [n, gens.size(),
				str(orbit_groups.keys()), sample_cnt, Time.get_ticks_msec() - t0])
		for t in per_orbit:
			var rec2: Dictionary = per_orbit[t]
			var pts_n: int = (rec2.pts as Dictionary).size()
			var orb_n: int = (orbit_groups[t] as Array).size()
			print("  轨%d(格%d): 3环=%d 2环=%d 其他=%d 点覆盖=%d/%d" % [t, orb_n,
					rec2.sup3, rec2.sup2, rec2.other, pts_n, orb_n])
	quit(0)
