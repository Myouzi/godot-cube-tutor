extends SceneTree
## 一次性探针(2026-10-06,v7.3 A1/A5——「自有结构输出+来源登记」构造主轨,B 族
## 交换子构造规则同款口径:commutator 数学事实=操作事实不受版权):
## 一阶 commutator 全枚举 [X,Y]=X Y X' Y'(X,Y ∈ 基本转+内层转全集,A0 toks 同源),
## 模拟器读回效应,筛三类保底/主通路原子:
##   B3 目标:moved==3 ∧ 三格分属三面(解剖 G2 口径,三面循环单式);
##   对换原子:moved==2 ∧ 两格同轨道(n=4/5 情形 X 规格由 A0 定);
##   双对换原子:moved==4 ∧ 两轨道各一对换(n=6/7 情形 Y 规格)。
## 顺带统计全形态谱(moved×faces 分布),供判定「一阶域是否足够、需否扩双 token」。
## 产物 = 按效应 canonical 去重后的最短 alg 清单 → A4 入池选型输入。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_cn_atoms.gd

const NS := preload("res://scripts/nxn_solver.gd")

const FACES := ["U", "R", "F", "D", "L", "B"]


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		print("=== n=%d ===" % n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var pc: int = (n - 2) * (n - 2)
		var ctx: Dictionary = NS._cn_ensure(n)
		# A0 轨道表(基本转闭包,与 _probe_center_orbits 同口径;此处仅用于
		# 对换原子分轨判据,复算成本低)
		var toks: Array = []
		for f in FACES:
			for suf in ["", "'", "2"]:
				toks.append(f + suf)
		for d in range(3, n):
			for f in FACES:
				for suf in ["", "'", "2"]:
					toks.append("%d%s%s" % [d, f, suf])
		var perms: Array = []
		for t in toks:
			perms.append(NS._cn_id_perm(String(t), n, cells))
		# 轨道(union-find)
		var uf := _UnionFind.new(m)
		for p in perms:
			for i in m:
				uf.union(i, int(p[i]))
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		for i in m:
			orbit_of[i] = uf.find(i)
		# 一阶 commutator 全枚举
		var spec3 := {}      # 3格3面: canonical -> {alg, moved}
		var spec2 := {}      # 单轨对换: "轨道root" -> {alg, moved}
		var spec4 := {}      # 双轨双对换: "r1|r2" -> {alg, moved}
		var spectrum := {}
		var inv := {}
		for i in toks.size():
			inv[toks[i]] = _invert(String(toks[i]))
		for i in toks.size():
			var xa: String = toks[i]
			var xi: String = inv[xa]
			for j in toks.size():
				if j == i:
					continue
				var ya: String = toks[j]
				var yi: String = inv[ya]
				var alg := "%s %s %s %s" % [xa, ya, xi, yi]
				var p := NS._cn_id_perm(alg, n, cells)
				var moved: Array = []
				var faces := {}
				for k2 in m:
					if p[k2] != k2:
						moved.append(k2)
						faces[k2 / pc] = true
				var dk := "%d格%d面" % [moved.size(), faces.size()]
				spectrum[dk] = int(spectrum.get(dk, 0)) + 1
				var cyc := _canon(p)
				if moved.size() == 3 and faces.size() == 3:
					if not spec3.has(cyc) or alg.length() < int(spec3[cyc].alg.length()):
						spec3[cyc] = {"alg": alg, "moved": moved}
				elif moved.size() == 2 and faces.size() == 2:
					var rk: int = orbit_of[moved[0]]
					if orbit_of[moved[1]] == rk:
						if not spec2.has(rk) or alg.length() < int(spec2[rk].alg.length()):
							spec2[rk] = {"alg": alg, "moved": moved}
				elif moved.size() == 4 and faces.size() == 4:
					# 双轨双对换判定:4 格分 2 轨各 2
					var cnt := {}
					for gi in moved:
						var rr: int = orbit_of[gi]
						cnt[rr] = int(cnt.get(rr, 0)) + 1
					if cnt.size() == 2:
						var ks: Array = cnt.keys()
						ks.sort()
						var key2 := "%d|%d" % [ks[0], ks[1]]
						if not spec4.has(key2) or alg.length() < int(spec4[key2].alg.length()):
							spec4[key2] = {"alg": alg, "moved": moved}
		print("  形态谱: %s" % str(spectrum))
		print("  B3(3格3面) 去重 %d 种,代表:" % spec3.size())
		var show := 0
		for cyc in spec3:
			if show >= 6:
				break
			show += 1
			print("    %s  moved=%s" % [String(spec3[cyc].alg), str(spec3[cyc].moved)])
		print("  单轨对换(n=4/5 规格) 覆盖轨道 %d 个:" % spec2.size())
		for rk in spec2:
			var oi: int = -1
			for gi in m:
				if orbit_of[gi] == rk:
					oi = gi
					break
			print("    轨道root=%d(例格%d): %s" % [rk, oi, String(spec2[rk].alg)])
		print("  双轨双对换(n=6/7 规格) 覆盖轨道对 %d 对:" % spec4.size())
		for key3 in spec4:
			print("    %s: %s" % [key3, String(spec4[key3].alg)])
		print("")
	quit(0)


func _invert(alg: String) -> String:
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


## 置换 canonical(循环分解,(a b c) 使 a=环内最小下标;不动点省略;按环首排序)。
func _canon(p: PackedInt32Array) -> String:
	var seen := PackedByteArray()
	seen.resize(p.size())
	var rings: Array = []
	for s in p.size():
		if seen[s] == 1 or p[s] == s:
			continue
		var ring: Array = []
		var j := s
		while seen[j] == 0:
			seen[j] = 1
			ring.append(j)
			j = int(p[j])
		# 旋转到最小下标开头
		var mi := 0
		for q in ring.size():
			if ring[q] < ring[mi]:
				mi = q
		var rot: Array = []
		for q in ring.size():
			rot.append(ring[(mi + q) % ring.size()])
		rings.append(rot)
	rings.sort_custom(func(a, b) -> bool: return _ring_key(a) < _ring_key(b))
	return _ring_join(rings)


func _ring_key(ring: Array) -> String:
	var s := ""
	for v in ring:
		s += "%d," % v
	return s


func _ring_join(rings: Array) -> String:
	var s := ""
	for ring in rings:
		s += "(" + _ring_key(ring).trim_suffix(",") + ")"
	return s


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
