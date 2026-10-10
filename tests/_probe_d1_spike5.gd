extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 spike 第五轮——纯层转直接积域,收尾轮):
## 四轮结论:①commutator/宏交差域无 3格3面;②共轭域=种子类并;③库乘积
##   深度 2/3 微涨不足;④3-cycle³ 直接覆盖≈0。未探域 = 纯层转**直接积**
##   (XY 非 [X,Y]):双 4-cycle 交差 2 格 = 3+3(两个新构型类 3-cycle 的
##   代数源),交差 3 格 = 5-cycle——构造性分解的种子候选。
## 本探针:toks² 与 toks³ 直接积,收集 moved==2/3 全部效应(全构型类),
##   输出按「面分布模式」聚类的种子数与覆盖判定(预注册:类并经共轭=100% GO)。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_spike5.gd

const NS := preload("res://scripts/nxn_solver.gd")

const FACES := ["U", "R", "F", "D", "L", "B"]


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		print("=== n=%d ===" % n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var pc: int = (n - 2) * (n - 2)
		var ctx: Dictionary = NS._cn_ensure(n)
		var toks: Array = []
		for f in FACES:
			for suf in ["", "'", "2"]:
				toks.append(f + suf)
		for d in range(3, n):
			for f in FACES:
				for suf in ["", "'", "2"]:
					toks.append("%d%s%s" % [d, f, suf])
		var tokperms: Array = []
		for t in toks:
			tokperms.append(NS._cn_id_perm(String(t), n, cells))
		var uf := _UnionFind.new(m)
		for p in tokperms:
			for i in m:
				uf.union(i, int(p[i]))
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		var orbit_groups := {}
		for i in m:
			orbit_of[i] = uf.find(i)
			if not orbit_groups.has(orbit_of[i]):
				orbit_groups[orbit_of[i]] = []
			(orbit_groups[orbit_of[i]] as Array).append(i)
		# toks² 直接积
		var cyc3 := {}
		var sw2 := {}
		var mode_dist := {}
		for i in toks.size():
			var pa: PackedInt32Array = tokperms[i]
			for j in toks.size():
				var comp := _compose(pa, tokperms[j], m)
				var alg := "%s %s" % [toks[i], toks[j]]
				_reg(m, pc, orbit_of, alg, comp, cyc3, sw2, mode_dist)
		var t1 := Time.get_ticks_msec()
		print("  toks² (%dms): 3-cycle 类 %d, 单轨对换 %d" % [t1 - t0, cyc3.size(), sw2.size()])
		# toks³(仅对缺类补充:两两缓存 × 单层转)
		var pair := {}
		for i in toks.size():
			for j in toks.size():
				pair["%d_%d" % [i, j]] = _compose(tokperms[i], tokperms[j], m)
		var t2 := Time.get_ticks_msec()
		for pk in pair:
			var pp: PackedInt32Array = pair[pk]
			var ij: PackedStringArray = String(pk).split("_")
			for k in toks.size():
				var comp := _compose(pp, tokperms[k], m)
				var alg := "%s %s %s" % [toks[int(ij[0])], toks[int(ij[1])], toks[k]]
				_reg(m, pc, orbit_of, alg, comp, cyc3, sw2, mode_dist)
		var t3 := Time.get_ticks_msec()
		print("  toks³ (%dms): 3-cycle 类 %d, 单轨对换 %d" % [t3 - t2, cyc3.size(), sw2.size()])
		# 面分布模式谱(3-cycle 三格面分布:同面3/2+1/1+1+1)
		print("  3-cycle 面分布谱: %s" % str(mode_dist))
		# 覆盖:类 ∪ 共轭像(toks²)
		var tok2perm := {}
		for i2 in toks.size():
			for j2 in toks.size():
				var alg2 := "%s %s" % [toks[i2], toks[j2]]
				tok2perm[alg2] = _compose(tokperms[j2], tokperms[i2], m)
		var covered := {}
		for kk in cyc3:
			var parts: PackedStringArray = String(kk).split("|")
			var trip: PackedStringArray = String(parts[1]).split(",")
			var cyc := [int(trip[0]), int(trip[1]), int(trip[2])]
			for alg2 in tok2perm:
				var s2: PackedInt32Array = tok2perm[alg2]
				var img: Array = []
				for ci in 3:
					img.append(_preimg(s2, cyc[ci]))
				img.sort()
				var kk2 := "o%d|%d,%d,%d" % [orbit_of[int(img[0])], img[0], img[1], img[2]]
				if not covered.has(kk2):
					covered[kk2] = "%s [%s]" % [String(cyc3[kk]), alg2]
		var total := 0
		var hit := 0
		var miss_sample: Array = []
		for o in orbit_groups:
			var grp: Array = orbit_groups[o]
			if grp.size() < 3:
				continue
			for a in grp.size():
				for b in range(a + 1, grp.size()):
					for c in range(b + 1, grp.size()):
						total += 1
						var trip2: Array = [grp[a], grp[b], grp[c]]
						trip2.sort()
						var kk3 := "o%d|%d,%d,%d" % [o, trip2[0], trip2[1], trip2[2]]
						if covered.has(kk3):
							hit += 1
						elif miss_sample.size() < 6:
							miss_sample.append(trip2)
		print("  覆盖(类∪toks²共轭像) %d/%d = %.1f%% → %s" % [hit, total,
				100.0 * hit / max(total, 1), "GO" if hit == total else "缺口"])
		if miss_sample.size() > 0:
			print("  缺口样例: %s" % str(miss_sample))
		var s2r: Array = sw2.values()
		s2r.sort_custom(func(a, b) -> bool: return String(a).length() < String(b).length())
		for i3 in mini(4, s2r.size()):
			print("  单轨对换: %s" % s2r[i3])
		print("  总耗时 %dms" % [Time.get_ticks_msec() - t0])
		print("")
	quit(0)


func _reg(m: int, pc: int, orbit_of: PackedInt32Array, alg: String, p: PackedInt32Array,
		cyc3: Dictionary, sw2: Dictionary, mode_dist: Dictionary) -> void:
	var moved: Array = []
	var faces := {}
	for k2 in m:
		if p[k2] != k2:
			moved.append(k2)
			faces[k2 / pc] = true
	if moved.size() == 3:
		var pat := "%d面" % faces.size()
		mode_dist[pat] = int(mode_dist.get(pat, 0)) + 1
		var o: int = orbit_of[moved[0]]
		if orbit_of[moved[1]] != o or orbit_of[moved[2]] != o:
			return
		var cyc: Array = [moved[0]]
		var nxt: int = int(p[moved[0]])
		while nxt != moved[0]:
			cyc.append(nxt)
			nxt = int(p[nxt])
		cyc.sort()
		var kk := "o%d|%d,%d,%d" % [o, cyc[0], cyc[1], cyc[2]]
		if not cyc3.has(kk) or alg.length() < String(cyc3[kk]).length():
			cyc3[kk] = alg
	elif moved.size() == 2:
		var o2: int = orbit_of[moved[0]]
		if orbit_of[moved[1]] == o2:
			var kk4 := "o%d|%d,%d" % [o2, mini(moved[0], moved[1]), maxi(moved[0], moved[1])]
			if not sw2.has(kk4) or alg.length() < String(sw2[kk4]).length():
				sw2[kk4] = alg


func _compose(outer: PackedInt32Array, inner: PackedInt32Array, m: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(m)
	for i in m:
		out[i] = outer[inner[i]]
	return out


func _preimg(s: PackedInt32Array, x: int) -> int:
	for i in s.size():
		if s[i] == x:
			return i
	return -1


class _UnionFind:
	var p: PackedInt32Array

	func _init(size: int) -> void:
		p.resize(size)
		for i in size:
			p[i] = i

	func find(x: int) -> int:
		while p[x] != x:
			p[x] = p[p[x]]
			x = p[x]
		return x

	func union(a: int, b: int) -> void:
		var ra := find(a)
		var rb := find(b)
		if ra != rb:
			p[rb] = ra
