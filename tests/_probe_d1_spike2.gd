extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 spike 第二轮——种子域扩充):
## 第一轮结论(tets/_probe_d1_spike.gd):库种子(4-60 个/阶)×toks² 共轭覆盖
##   32-50%——缺口本质 = 种子构型类不全(toks² 像 = 种子构型类的转动群轨道,
##   toks 单步即生成全转动作用;缺口类 = 同面相邻/同面共线等库种子没有的
##   构型类)。
## 本轮扩充:种子域 = 二阶交差域全部 moved==3 效应(atoms2 口径:库宏 × 层转
##   ×4 复合形式,n=4 实测 3格2面 144 条)∪ 库种子。共轭域 = toks²(取满,像
##   = 种子类轨道,实测确认 toks 单步与 toks² 覆盖等价)。
## 判定预注册:覆盖率 100% → GO(共轭字典法);<100% → 缺口类清单记档回报。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_spike2.gd

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
		# 轨道
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
		# ---- 种子域:库宏 × 层转 交差 moved==3(4 复合形式)+ 库直取 ----
		var lib: Array = []
		var seen_lib := {}
		for key3 in ["end_atoms", "bfs_atoms"]:
			for e: Dictionary in ctx[key3]:
				var a: String = String(e.alg)
				if a == "" or seen_lib.has(a):
					continue
				seen_lib[a] = true
				lib.append(a)
		var inv_cache := {}
		for t in toks:
			inv_cache[t] = _inv(String(t))
		var seed_cyc := {}   # "o|a,b,c" -> 代表 alg(最小 length)
		var moved3_alg := {} # 环 canonical -> alg(全库域收集)
		var add_seed := func(alg: String, p: PackedInt32Array) -> void:
			var moved: Array = []
			for k2 in m:
				if p[k2] != k2:
					moved.append(k2)
			if moved.size() != 3:
				return
			var o: int = orbit_of[moved[0]]
			if orbit_of[moved[1]] != o or orbit_of[moved[2]] != o:
				return
			var cyc: Array = [moved[0]]
			var nxt: int = int(p[moved[0]])
			while nxt != moved[0]:
				cyc.append(nxt)
				nxt = int(p[nxt])
			var kk := "o%d|%d,%d,%d" % [o, cyc[0], cyc[1], cyc[2]]
			if not seed_cyc.has(kk) or alg.length() < String(seed_cyc[kk]).length():
				seed_cyc[kk] = alg
		for la in lib:
			add_seed.call(la, NS._cn_id_perm(la, n, cells))
		var t1 := Time.get_ticks_msec()
		for la in lib:
			var lp := NS._cn_id_perm(la, n, cells)
			for ti in toks.size():
				for form in 4:
					var alg: String
					match form:
						0: alg = "%s %s" % [la, toks[ti]]
						1: alg = "%s %s" % [toks[ti], la]
						2: alg = "%s %s %s" % [la, toks[ti], inv_cache[toks[ti]]]
						3: alg = "%s %s %s" % [toks[ti], la, _inv(la)]
					var p := NS._cn_id_perm(alg, n, cells)
					var mv := 0
					for k2 in m:
						if p[k2] != k2:
							mv += 1
					if mv == 3:
						add_seed.call(alg, p)
		var t2 := Time.get_ticks_msec()
		print("  种子域: 库 %d × 层转交差 (%dms) → 单轨种子循环 %d 个" % [lib.size(), t2 - t1, seed_cyc.size()])
		# ---- 共轭像集合(toks²;预复合缓存) ----
		var tok2perm := {}
		for i in toks.size():
			for j in toks.size():
				var alg2 := "%s %s" % [toks[i], toks[j]]
				tok2perm[alg2] = _compose(tokperms[j], tokperms[i], m)
		var covered := {}
		for kk in seed_cyc:
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
					covered[kk2] = "%s' %s %s" % [alg2, String(seed_cyc[kk]), _inv(alg2)]
		# ---- 覆盖率 ----
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
		print("  覆盖率 %d/%d = %.1f%% → %s" % [hit, total, 100.0 * hit / max(total, 1),
				"GO(共轭字典法完备)" if hit == total else "缺口(记档回报)"])
		if miss_sample.size() > 0:
			print("  缺口样例: %s" % str(miss_sample))
		print("  总耗时 %dms" % [Time.get_ticks_msec() - t0])
		print("")
	quit(0)


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


func _inv(alg: String) -> String:
	var parts: PackedStringArray = alg.split(" ")
	var out: Array = []
	for i in range(parts.size() - 1, -1, -1):
		var t: String = parts[i]
		if t.ends_with("'"):
			out.append(t.substr(0, t.length() - 1))
		elif t.ends_with("2"):
			out.append(t)
		else:
			out.append(t + "'")
	return " ".join(out)


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
