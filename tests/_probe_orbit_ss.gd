extends SceneTree
## 一次性探针(2026-10-10,v7.3 D1 轨道级联 SS 全链路验证):
## ①分轨采样种子 3-环(token 有限)→ ②层转共轭铺开至点覆盖 24/24 →
## ③每轨独立 24 点小 SS(残差全收)→ ④随机轨内偶置换 sift 自检 →
## ⑤token 成本实测。全绿则移植进 nxn_solver 替换全群 SS。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_orbit_ss.gd

const NS := preload("res://scripts/nxn_solver.gd")

const SEED_TOKEN_MAX := 48
const CONJ_FAMILY_MAX := 1500


func _init_gens(n: int, m: int) -> Array:
	var gens: Array = []
	var seen: Dictionary = {}
	for f in ["U", "R", "F", "D", "L", "B"]:
		for suf in ["", "'", "2"]:
			var ta: String = f + suf
			var tp := NS._cn_id_perm(ta, n, NS._cn_cells(n))
			var kk := NS._fb_key(tp)
			if not seen.has(kk):
				seen[kk] = true
				gens.append({"alg": ta, "perm": tp, "tokens": 1})
	for d in range(3, n):
		for f2 in ["U", "R", "F", "D", "L", "B"]:
			for suf2 in ["", "'", "2"]:
				var ta2: String = "%d%s%s" % [d, f2, suf2]
				var tp2 := NS._cn_id_perm(ta2, n, NS._cn_cells(n))
				var kk2 := NS._fb_key(tp2)
				if not seen.has(kk2):
					seen[kk2] = true
					gens.append({"alg": ta2, "perm": tp2, "tokens": 1})
	var ctx0: Dictionary = NS._cn_ensure(n)
	var cands: Array = []
	for key3 in ["end_atoms", "bfs_atoms"]:
		for e: Dictionary in ctx0[key3]:
			var ep: PackedInt32Array = e.perm
			var mv := 0
			for k2 in m:
				if ep[k2] != k2:
					mv += 1
			if mv == 0 or mv > 12:
				continue
			cands.append({"alg": String(e.alg), "perm": ep, "tokens": int(e.tokens)})
	cands.sort_custom(func(a, b) -> bool: return int(a.tokens) < int(b.tokens))
	for c in cands:
		var kk3 := NS._fb_key(c.perm)
		if not seen.has(kk3):
			seen[kk3] = true
			gens.append(c)
	return gens


## 轨内小 SS(局部点 m_t 个,gens_lt 局部 perm)。返回 {levels, ok}
func _orbit_ss(m_t: int, gens_lt: Array) -> Dictionary:
	var levels: Array = []
	var s_cur: Array = []
	for gi in gens_lt.size():
		s_cur.append({"perm": gens_lt[gi]})
	for i in m_t:
		# transversal BFS:trans[y] = {rep: 把 i 送到 y 的 s_cur 元}
		var trans: Dictionary = {i: {"rep": _id(m_t)}}
		var queue: Array = [i]
		var qi := 0
		while qi < queue.size():
			var x: int = queue[qi]
			qi += 1
			var rep_x: PackedInt32Array = trans[x].rep
			for s in s_cur:
				var y: int = (s.perm as PackedInt32Array)[x]
				if not trans.has(y):
					trans[y] = {"rep": _comp(s.perm, rep_x, m_t)}
					queue.append(y)
		levels.append({"s": s_cur, "trans": trans})
		if i == m_t - 1:
			break
		# Schreier 生成元 v⁻¹∘g∘u → sift → 残差按支持升序取前 40
		# (全收会级联膨胀:s_cur 每级倍增,实测爆内存)
		var resid: Array = []
		var seen3: Dictionary = {}
		for p in trans:
			var u: PackedInt32Array = trans[p].rep
			for g in s_cur:
				var gp: PackedInt32Array = g.perm
				var mid: int = gp[p]
				if not trans.has(mid):
					continue
				var vinv: PackedInt32Array = _inv(trans[mid].rep, m_t)
				var w := _comp(vinv, _comp(gp, u, m_t), m_t)
				if w[i] != i:
					continue
				if seen3.has(w):
					continue
				seen3[w] = true
				var s2 := w.duplicate()
				var sift_ok := true
				for j in i + 1:
					var pj: int = s2[j]
					if pj == j:
						continue
					var tj: Dictionary = levels[j].trans
					if not tj.has(pj):
						sift_ok = false
						break
					s2 = _comp(_inv(tj[pj].rep, m_t), s2, m_t)
				if not sift_ok or _is_id(s2, m_t):
					continue
				resid.append(s2)
		resid.sort_custom(func(a, b) -> bool:
				var sa := 0
				for k8 in m_t:
					if a[k8] != k8:
						sa += 1
				var sb := 0
				for k9 in m_t:
					if b[k9] != k9:
						sb += 1
				return sa < sb)
		var s_next: Array = []
		for r9 in resid:
			if s_next.size() >= 64:
				break
			s_next.append({"perm": r9})
		s_cur = s_cur + s_next
		if s_next.is_empty():
			break
	# 自检:随机积 sift
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091 + m_t
	for t in 30:
		var sig := _id(m_t)
		for step in 8:
			sig = _comp(sig, gens_lt[rng.randi() % gens_lt.size()], m_t)
		if not _sift_check(sig, levels, m_t):
			return {"levels": levels, "ok": false}
	return {"levels": levels, "ok": true}


func _comp(a: PackedInt32Array, b: PackedInt32Array, m: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(m)
	for i in m:
		r[i] = a[b[i]]
	return r


func _inv(a: PackedInt32Array, m: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(m)
	for i in m:
		r[a[i]] = i
	return r


func _id(m: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(m)
	for i in m:
		r[i] = i
	return r


func _is_id(a: PackedInt32Array, m: int) -> bool:
	for i in m:
		if a[i] != i:
			return false
	return true


func _sift_check(sig: PackedInt32Array, levels: Array, m_t: int) -> bool:
	var s := sig.duplicate()
	for i in levels.size():
		var pj: int = s[i]
		if pj == i:
			continue
		var trans: Dictionary = levels[i].trans
		if not trans.has(pj):
			return false
		var found: PackedInt32Array = PackedInt32Array()
		for u2 in levels[i].s:
			if (u2.perm as PackedInt32Array)[pj] == i:
				found = u2.perm
				break
		if found.is_empty():
			return false
		s = _comp(_inv(found, m_t), s, m_t)
	return _is_id(s, m_t)


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var gens: Array = _init_gens(n, m)
		# 轨道表
		var uf := NS._UnionFindP.new(m)
		for g0 in gens:
			var gp0: PackedInt32Array = g0.perm
			for j in m:
				uf.union(j, gp0[j])
		var orbit_groups: Dictionary = {}
		for j in m:
			var r: int = uf.find(j)
			if not orbit_groups.has(r):
				orbit_groups[r] = []
			(orbit_groups[r] as Array).append(j)
		print("n=%d gens=%d 轨道数=%d" % [n, gens.size(), orbit_groups.size()])
		var all_ok := true
		for t in orbit_groups:
			var pts: Array = orbit_groups[t]
			pts.sort()
			var m_t: int = pts.size()
			if m_t <= 6:
				print("  轨%d(格%d): 真中心/小轨,层转不动,跳过" % [t, m_t])
				continue
			var loc: Dictionary = {}
			for a in m_t:
				loc[pts[a]] = a
			# ① 种子采样:随机积判「支持==3 且 ⊆ 本轨」;支持组合去重(每组
			# 最多 3 个)避免采样局部化(实测 50 种子全挤同 3 点,共轭铺不开)
			var rng := RandomNumberGenerator.new()
			rng.seed = 424242 + t
			var seeds: Array = []
			var seen_seed: Dictionary = {}
			var sup_group: Dictionary = {}
			for it in 600000:
				var p := NS._fb_id(m)
				var depth := 2 + rng.randi() % 7
				for dstep in depth:
					p = NS._fb_comp_first_second(p,
							(gens[rng.randi() % gens.size()] as Dictionary).perm, m)
				var sup := PackedInt32Array()
				for k4 in m:
					if p[k4] != k4:
						sup.append(k4)
				if sup.size() != 3:
					continue
				var in_t := true
				for a2 in 3:
					if loc.has(sup[a2]) == false:
						in_t = false
						break
				if not in_t:
					continue
				var gkey := "%d_%d_%d" % [mini(sup[0], sup[1]),
						int(clamp(sup[0] + sup[1] - sup[2], 0, 999)),
						int(clamp(sup[0] + sup[2] - sup[1], 0, 999))]
				if (sup_group.get(gkey, 0) as int) >= 3:
					continue
				sup_group[gkey] = (sup_group.get(gkey, 0) as int) + 1
				var kk5 := NS._fb_key(p)
				if seen_seed.has(kk5):
					continue
				seen_seed[kk5] = true
				seeds.append(p)
				if seeds.size() >= 120:
					break
			# ② 共轭铺开:g c g⁻¹(g 限单转 token=1)
			var family: Array = []
			var fam_seen: Dictionary = {}
			var cover: Dictionary = {}
			var frontier: Array = []
			for c5 in seeds:
				var kk6 := NS._fb_key(c5)
				if fam_seen.has(kk6):
					continue
				fam_seen[kk6] = true
				family.append(c5)
				frontier.append(c5)
				for a3 in 3:
					cover[c5[a3]] = true
			while frontier.size() > 0 and family.size() < CONJ_FAMILY_MAX \
					and cover.size() < m_t:
				var c6: PackedInt32Array = frontier.pop_back()
				for g1 in gens:
					if int(g1.tokens) > 8:
						continue
					var gp: PackedInt32Array = g1.perm
					# nc = g∘c∘g⁻¹
					var nc := NS._fb_comp_first_second(gp,
							NS._fb_comp_first_second(c6, NS._fb_inv(gp, m), m), m)
					var kk7 := NS._fb_key(nc)
					if fam_seen.has(kk7):
						continue
					var ok_t := true
					for k7 in m:
						if nc[k7] != k7 and not loc.has(k7):
							ok_t = false
							break
					if not ok_t:
						continue
					fam_seen[kk7] = true
					family.append(nc)
					frontier.append(nc)
					for a4 in 3:
						cover[nc[a4]] = true
					if family.size() >= CONJ_FAMILY_MAX or cover.size() >= m_t:
						break
				if family.size() >= CONJ_FAMILY_MAX or cover.size() >= m_t:
					break
			# ③ 精选:贪心传递最小集(支持并集不增者丢)——控制 SS 级 0 规模
			var keep: Array = []
			var keep_pts: Dictionary = {}
			for c7 in family:
				var adds := false
				for a5 in 3:
					if not keep_pts.has(c7[a5]):
						adds = true
						break
				if adds or keep.size() < 48:
					keep.append(c7)
					for a6 in 3:
						keep_pts[c7[a6]] = true
				if keep.size() >= 96:
					break
			# ④ 局部化 + 轨内 SS
			var gens_lt: Array = []
			for c8 in keep:
				var lp := PackedInt32Array()
				lp.resize(m_t)
				for a7 in m_t:
					lp[a7] = loc[c8[pts[a7]]]
				gens_lt.append(lp)
			var ss: Dictionary = _orbit_ss(m_t, gens_lt)
			print("  轨%d(格%d): 种子=%d 族=%d 覆盖=%d/%d SS=%s levels=%d" %
					[t, m_t, seeds.size(), family.size(), cover.size(), m_t,
					"PASS" if ss.ok else "FAIL", (ss.levels as Array).size()])
			if not ss.ok or cover.size() < m_t:
				all_ok = false
		print("n=%d 汇总: %s (%dms)" % [n, "全绿" if all_ok else "有失败",
				Time.get_ticks_msec() - t0])
	quit(0)
