extends SceneTree
## 一次性探针(2026-10-06,v7.3 A1 二阶枚举——一阶 [X,Y] 阴性后的构造域扩展):
## 一阶结论(见 _probe_cn_atoms.gd):[X,Y] 恒偶置换 + 单层转交差 ≥4 格 →
## moved∈{2,3} 全缺。B2 构造先例 = [宏 B2, 三 token 摆位 dR'dFdR]——
## 本探针把枚举域扩为「现有宏库(M × 层转 toks)」二阶交差:
##   M 域 = end_atoms + bfs_atoms 全库(B1/B2/A 族 T/S/Q/conn/小原子,n 阶数百条);
##   X 域 = 基本转+内层转 toks(≤90/阶)。
## 目标形态:moved==3 ∧ 三格分属三面(B3 单式,主通路/A4 入池选型)。
## 次要观察:moved==3 三格 2 面(与 B2 同形态的新覆盖)、moved==4 双轨双对换。
## 产物 = canonical 去重后最短 alg 代表清单 → A4 骨架选型。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_cn_atoms2.gd

const NS := preload("res://scripts/nxn_solver.gd")

const FACES := ["U", "R", "F", "D", "L", "B"]


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		print("=== n=%d ===" % n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var pc: int = (n - 2) * (n - 2)
		var ctx: Dictionary = NS._cn_ensure(n)
		# M 域:全宏库(去重)
		var lib: Array = []
		var seen := {}
		for key3 in ["pool1", "a_pool1", "bfs_atoms", "end_atoms"]:
			for e: Dictionary in ctx[key3]:
				var a: String = String(e.alg)
				if a == "" or seen.has(a):
					continue
				seen[a] = true
				lib.append(a)
		# X 域:层转
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
		# 轨道(双对换判据用)
		var uf := _UnionFind.new(m)
		for p in tokperms:
			for i in m:
				uf.union(i, int(p[i]))
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		for i in m:
			orbit_of[i] = uf.find(i)
		print("  库 %d 条 × 层转 %d" % [lib.size(), toks.size()])
		var spec3 := {}
		var spec4 := {}
		var spectrum := {}
		for la in lib:
			var lp := NS._cn_id_perm(la, n, cells)
			for ti in toks.size():
				for form in 4:
					# 4 结构:la·T / T·la / la·T·la' / T·la·T'
					var alg: String
					match form:
						0: alg = "%s %s" % [la, toks[ti]]
						1: alg = "%s %s" % [toks[ti], la]
						2: alg = "%s %s %s" % [la, toks[ti], _inv(String(toks[ti]))]
						3: alg = "%s %s %s" % [toks[ti], la, _inv(la)]
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
						if not spec3.has(cyc) or alg.length() < String(spec3[cyc]).length():
							spec3[cyc] = alg
					elif moved.size() == 4:
						var cnt := {}
						for gi in moved:
							var rr: int = orbit_of[gi]
							cnt[rr] = int(cnt.get(rr, 0)) + 1
						if cnt.size() == 2 and (not spec4.has(cyc) or alg.length() < String(spec4[cyc]).length()):
							spec4[cyc] = alg
		print("  形态谱: %s" % str(spectrum))
		print("  B3(3格3面) 去重 %d 种,最短代表前 6:" % spec3.size())
		var reps: Array = spec3.values()
		reps.sort_custom(func(a, b) -> bool: return String(a).length() < String(b).length())
		for i in mini(6, reps.size()):
			print("    %s" % reps[i])
		print("  双轨双对换 去重 %d 种,最短代表前 3:" % spec4.size())
		var reps4: Array = spec4.values()
		reps4.sort_custom(func(a, b) -> bool: return String(a).length() < String(b).length())
		for i in mini(3, reps4.size()):
			print("    %s" % reps4[i])
		print("")
	quit(0)


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


func _ring_key(ring: Array) -> String:
	var s := ""
	for v in ring:
		s += "%d," % v
	return s


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
		var mi := 0
		for q in ring.size():
			if ring[q] < ring[mi]:
				mi = q
		var rot: Array = []
		for q in ring.size():
			rot.append(ring[(mi + q) % ring.size()])
		rings.append(rot)
	rings.sort_custom(func(a, b) -> bool: return _ring_key(a) < _ring_key(b))
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
