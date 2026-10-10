extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 spike 第三轮——乘积域效应字典):
## 前两轮结论:①一阶/二阶交差域无 3格3面;②共轭域覆盖=种子构型类并(32-50%,
##   转动作用保构型类,setup 打不开新类)。数学出路:宏乘积打破构型类封闭
##   (两 3-cycle 交差 2 格 = 双对换;交差 1 格 = 5-cycle;乘积域效应空间大)。
## 本探针:库宏(end_atoms+bfs_atoms)深度 2 乘积(双序 M1·M2/M1·M2·M1' 类)的
##   效应枚举 → 收集 moved==3(按构型类)/moved==2 同轨/moved==4 双轨双对换,
##   输出构型类覆盖进步与代表序列。若深度 2 不够,升深度 3(60³ 可控)。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_spike3.gd

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
		# 库(去重)
		var lib: Array = []
		var seen_lib := {}
		for key3 in ["end_atoms", "bfs_atoms"]:
			for e: Dictionary in ctx[key3]:
				var a: String = String(e.alg)
				if a == "" or seen_lib.has(a):
					continue
				seen_lib[a] = true
				lib.append(a)
		var libperms: Array = []
		for la in lib:
			libperms.append(NS._cn_id_perm(la, n, cells))
		print("  库 %d 条,深度 2 乘积 %d 组合" % [lib.size(), lib.size() * lib.size() * 2])
		# 深度 2 乘积:M1·M2 与 M1·toks(库×层转也算——层转是库外但步骤化后仍是序列)
		var cyc3 := {}      # "o|a,b,c" -> 最短 alg
		var sw2 := {}       # "o|a,b" -> 最短 alg (单轨对换)
		var sw4 := {}       # "o1|o2|..." -> 最短 alg (双轨双对换)
		var spec3_cnt := {}
		for i in lib.size():
			var pa: PackedInt32Array = libperms[i]
			for j in lib.size():
				var comp := _compose(pa, libperms[j], m)
				_reg(m, pc, orbit_of, orbit_groups, "%s %s" % [lib[i], lib[j]], comp, cyc3, sw2, sw4, spec3_cnt)
		var t1 := Time.get_ticks_msec()
		print("  深度2乘积枚举 (%dms)" % [t1 - t0])
		print("  moved==3 循环(全部面分布) 去重 %d 个" % cyc3.size())
		# 覆盖判定:C(|O|,3) 中被 cyc3 覆盖的比例(注意乘积域效应=直接查,无共轭
		# ——但运行期可用 setup 共轭放大:类覆盖 = 种子类 ∪ 乘积新类 的并经共轭像)
		# 本探针先看「乘积直接覆盖」+「乘积类 ∪ 库类 经 toks² 共轭」两个口径。
		# 口径 B:乘积新类的共轭像并入覆盖集
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
		print("  口径B(乘积类∪共轭像) 覆盖 %d/%d = %.1f%% → %s" % [hit, total,
				100.0 * hit / max(total, 1), "GO" if hit == total else "仍缺口"])
		if miss_sample.size() > 0:
			print("  缺口样例: %s" % str(miss_sample))
		print("  单轨对换种子 %d, 双轨双对换种子 %d" % [sw2.size(), sw4.size()])
		var s2r: Array = sw2.values()
		s2r.sort_custom(func(a, b) -> bool: return String(a).length() < String(b).length())
		for i3 in mini(3, s2r.size()):
			print("    对换: %s" % s2r[i3])
		var s4r: Array = sw4.values()
		s4r.sort_custom(func(a, b) -> bool: return String(a).length() < String(b).length())
		for i4 in mini(3, s4r.size()):
			print("    双对换: %s" % s4r[i4])
		print("  总耗时 %dms" % [Time.get_ticks_msec() - t0])
		print("")
	quit(0)


func _reg(m: int, pc: int, orbit_of: PackedInt32Array, orbit_groups: Dictionary,
		alg: String, p: PackedInt32Array, cyc3: Dictionary, sw2: Dictionary,
		sw4: Dictionary, spec3_cnt: Dictionary) -> void:
	var moved: Array = []
	var faces := {}
	for k2 in m:
		if p[k2] != k2:
			moved.append(k2)
			faces[k2 / pc] = true
	if moved.size() == 3:
		var o: int = orbit_of[moved[0]]
		if orbit_of[moved[1]] != o or orbit_of[moved[2]] != o:
			return
		var cyc: Array = [moved[0]]
		var nxt: int = int(p[moved[0]])
		while nxt != moved[0]:
			cyc.append(nxt)
			nxt = int(p[nxt])
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
