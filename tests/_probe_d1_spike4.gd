extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 spike 第四轮——3-cycle³ 乘积域种子完备性):
## 三轮结论:①一阶/二阶交差无 3格3面;②共轭域=种子类并(32-50%);③深度 2
##   乘积微涨(50.8%)。数学:库域生成群 ⊇ A_24(Jordan:传递+本原+含 3-cycle,
##   本原性由 D1 实现期块系统枚举复核),缺口类只是乘积深度不足;两 3-cycle
##   积 ∈ {5-cycle,双对换,3+3,6,id},三积可回出新构型类 3-cycle。
## 本探针:循环类域(库 3-cycle 去重,含 2 面/3 面/面内全部分布)三乘积
##   (带两两缓存)收集 moved∈{2,3,4} 种子,全构型类覆盖判定。
##   预注册:覆盖 100% → D1 消解法 GO;<100% → 缺口类记档。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_spike4.gd

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
		# 库 3-cycle 循环类域(全部面分布;含面内对换 Q 族单独入 sw2 观察域)
		var c3: Array = []   # [{alg, perm}]
		var seen_c := {}
		for key3 in ["end_atoms", "bfs_atoms"]:
			for e: Dictionary in ctx[key3]:
				var perm: PackedInt32Array = e.perm
				var mv := 0
				for k2 in m:
					if perm[k2] != k2:
						mv += 1
				if mv != 3:
					continue
				var cyc: Array = [0, 0, 0]
				var s0 := -1
				for k3 in m:
					if perm[k3] != k3:
						s0 = k3
						break
				cyc[0] = s0
				cyc[1] = int(perm[s0])
				cyc[2] = int(perm[int(perm[s0])])
				cyc.sort()
				var kk := "%d,%d,%d" % [cyc[0], cyc[1], cyc[2]]
				if seen_c.has(kk):
					continue
				seen_c[kk] = true
				c3.append({"alg": String(e.alg), "perm": perm})
		var t1 := Time.get_ticks_msec()
		print("  3-cycle 循环类 %d 个 (%dms)" % [c3.size(), t1 - t0])
		# 两两乘积缓存
		var pair := {}
		for i in c3.size():
			var pa: PackedInt32Array = c3[i].perm
			for j in c3.size():
				var pb: PackedInt32Array = c3[j].perm
				pair["%d_%d" % [i, j]] = _compose(pa, pb, m)
		var t2 := Time.get_ticks_msec()
		print("  两两缓存 %d (%dms)" % [pair.size(), t2 - t1])
		# 三乘积:(pair ∘ c3) 收集种子
		var cyc3 := {}
		var sw2 := {}
		var sw4 := {}
		for pk in pair:
			var pp: PackedInt32Array = pair[pk]
			var ij: PackedStringArray = String(pk).split("_")
			for k in c3.size():
				var comp := _compose(pp, c3[k].perm, m)
				var alg := "%s %s %s" % [c3[int(ij[0])].alg, c3[int(ij[1])].alg, c3[k].alg]
				_reg(n, m, pc, orbit_of, alg, comp, cyc3, sw2, sw4)
		var t3 := Time.get_ticks_msec()
		print("  三乘积枚举 (%dms)" % [t3 - t2])
		print("  种子: 3-cycle %d 类 / 单轨对换 %d / 双轨双对换 %d" % [cyc3.size(), sw2.size(), sw4.size()])
		# 覆盖判定(乘积直接覆盖;共轭像放大在 D1 运行期做,此处看类完备性)
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
						var trip: Array = [grp[a], grp[b], grp[c]]
						trip.sort()
						var kk3 := "o%d|%d,%d,%d" % [o, trip[0], trip[1], trip[2]]
						if cyc3.has(kk3):
							hit += 1
						elif miss_sample.size() < 6:
							miss_sample.append(trip)
		print("  3-cycle 类覆盖 %d/%d = %.1f%% → %s" % [hit, total, 100.0 * hit / max(total, 1),
				"GO(消解法种子完备)" if hit == total else "仍缺口"])
		if miss_sample.size() > 0:
			print("  缺口样例: %s" % str(miss_sample))
		print("  总耗时 %dms" % [Time.get_ticks_msec() - t0])
		print("")
	quit(0)


func _reg(n: int, m: int, pc: int, orbit_of: PackedInt32Array, alg: String,
		p: PackedInt32Array, cyc3: Dictionary, sw2: Dictionary, sw4: Dictionary) -> void:
	var moved: Array = []
	for k2 in m:
		if p[k2] != k2:
			moved.append(k2)
	if moved.size() == 3:
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
	elif moved.size() == 4:
		var cnt := {}
		for gi in moved:
			var rr: int = orbit_of[gi]
			cnt[rr] = int(cnt.get(rr, 0)) + 1
		if cnt.size() == 2:
			var ks: Array = cnt.keys()
			ks.sort()
			var kk5 := "%d|%d" % [ks[0], ks[1]]
			if not sw4.has(kk5) or alg.length() < String(sw4[kk5]).length():
				sw4[kk5] = alg


func _compose(outer: PackedInt32Array, inner: PackedInt32Array, m: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(m)
	for i in m:
		out[i] = outer[inner[i]]
	return out


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
