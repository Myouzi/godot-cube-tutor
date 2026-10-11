extends SceneTree
## 一次性探针(2026-10-11,v7.4 阶段0实验A第一棒;第二棒改 n=7 trials 3→15 同步 B0
## 扩样,卡点态 27→39=n5:9+n6:15+n7:15):B0 口径中心卡点态
## σ 置换导出 + gens/对齐样例导出,供 /tmp/minkwitz_spike.py 换域消费(卡点态直测)。
## 口径同 tests/_probe_b0_survey.gd(rng.seed=20260929、scramble(40)、solve_centers)。
## σ 构造复用引擎 _fb_sigma_of(nxn_solver.gd:3621)全逻辑——含 PARITY 分支:
## v/basis/_fb_in_span/_fb_nearest_span + swap 修正(:3688-3772 逐行复刻,保持
## 字典迭代序语义)。CN_FB_PARITY_FIX 现为 false(:3413),运行期 σ=未修正版;
## n=6/7 实测多数态 σ 奇偶越出行空间(σ∉⟨gens⟩,sifting 结构性必挂)——
## 修正后版(=PARITY_FIX=true 行为)一并导出供 A/B 两口径直测(impl-plan §3.3)。
## fb 用轻量版:只喂层转全集(域同 _fb_build :3463-3484),orbit 由并查集重建
## (复刻 :3601-3613)。库原子是层转乘积不改变群,轨道不变,故不跑 27GB OOM
## 的 _fb_build。不在 CI 清单;复核运行:
## bash -c 'ulimit -v 4000000 && timeout 600 godot --headless -s tests/_probe_stage0_export.gd'

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")
const OUT := "res://tests/fixtures/stage0_sigma.json"


## 层转全集 gens(与 _fb_build 生成元域同款:外层 6×3 + 内层 d∈3..n-1 6×3,
## _fb_key 去重;不含库原子——σ/orbit 只依赖群不依赖生成元集)
func _layer_gens(n: int, cells: PackedInt32Array) -> Array:
	var gens: Array = []
	var seen: Dictionary = {}
	for f in ["U", "R", "F", "D", "L", "B"]:
		for suf in ["", "'", "2"]:
			var ta: String = f + suf
			var tp: PackedInt32Array = NS._cn_id_perm(ta, n, cells)
			var kk := NS._fb_key(tp)
			if seen.has(kk):
				continue
			seen[kk] = true
			gens.append({"alg": ta, "perm": tp, "tokens": 1})
	for d in range(3, n):
		for f2 in ["U", "R", "F", "D", "L", "B"]:
			for suf2 in ["", "'", "2"]:
				var ta2: String = "%d%s%s" % [d, f2, suf2]
				var tp2: PackedInt32Array = NS._cn_id_perm(ta2, n, cells)
				var kk2 := NS._fb_key(tp2)
				if seen.has(kk2):
					continue
				seen[kk2] = true
				gens.append({"alg": ta2, "perm": tp2, "tokens": 1})
	return gens


## 轻量 fb:_fb_sigma_of 只消费 m/pc/gens/orbit_of/orbit_groups
func _light_fb(n: int) -> Dictionary:
	var cells: PackedInt32Array = NS._cn_cells(n)
	var m: int = cells.size()
	var gens := _layer_gens(n, cells)
	var uf := NS._UnionFindP.new(m)
	for g in gens:
		var gp: PackedInt32Array = g.perm
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
	return {"m": m, "pc": (n - 2) * (n - 2), "gens": gens,
			"orbit_of": orbit_of, "orbit_groups": orbit_groups}


## _fb_sigma_of 全逻辑复刻(含 PARITY 分支),返回:
## {sigma, sigma_fixed, in_span, fixed, empty}
func _sigma_full(st: PackedByteArray, fb: Dictionary) -> Dictionary:
	var m: int = fb.m
	var pc: int = fb.pc
	var orbit_of: PackedInt32Array = fb.orbit_of
	var orbit_groups: Dictionary = fb.orbit_groups
	# home 格集:per (轨道, 颜色)(同 :3629-3640)
	var home_by := {}
	for t in orbit_groups:
		for j in orbit_groups[t]:
			var c: int = j / pc
			var key := "%d_%d" % [t, c]
			if not home_by.has(key):
				home_by[key] = []
			(home_by[key] as Array).append(j)
	var h := PackedInt32Array()
	h.resize(m)
	var cur_by := {}
	for i in m:
		var key2 := "%d_%d" % [orbit_of[i], st[i]]
		if not cur_by.has(key2):
			cur_by[key2] = []
		(cur_by[key2] as Array).append(i)
	for key3 in cur_by:
		if not home_by.has(key3):
			return {"empty": true}
		var cur: Array = cur_by[key3]
		var home: Array = home_by[key3]
		if cur.size() != home.size():
			return {"empty": true}
		for a in cur.size():
			h[cur[a]] = home[a]
	# h 每轨道符号 v + gens 符号矩阵行空间 basis(同 :3688-3741)
	var orbit_ids: Array = orbit_groups.keys()
	orbit_ids.sort()
	var k_t: int = orbit_ids.size()
	var v := PackedInt32Array()
	v.resize(k_t)
	for ti in k_t:
		var t: int = orbit_ids[ti]
		var grp: Array = orbit_groups[t]
		var sub := PackedInt32Array()
		sub.resize(grp.size())
		var loc := {}
		for a in grp.size():
			loc[grp[a]] = a
		for a in grp.size():
			sub[a] = loc[h[grp[a]]]
		v[ti] = NS._fb_parity(sub)
	var basis: Array = []
	var gens: Array = fb.gens
	for g in gens:
		var vec := PackedInt32Array()
		vec.resize(k_t)
		var gp: PackedInt32Array = g.perm
		for ti in k_t:
			var t2: int = orbit_ids[ti]
			var grp2: Array = orbit_groups[t2]
			var sub2 := PackedInt32Array()
			sub2.resize(grp2.size())
			var loc2 := {}
			for a in grp2.size():
				loc2[grp2[a]] = a
			for a in grp2.size():
				sub2[a] = loc2[gp[grp2[a]]]
			vec[ti] = NS._fb_parity(sub2)
		var w := vec.duplicate()
		for row in basis:
			var lead := -1
			for c2 in k_t:
				if row[c2] == 1:
					lead = c2
					break
			if lead >= 0 and w[lead] == 1:
				for c3 in k_t:
					w[c3] ^= row[c3]
		var wlead := -1
		for c4 in k_t:
			if w[c4] == 1:
				wlead = c4
				break
		if wlead >= 0:
			basis.append(w)
	var sigma := NS._fb_inv(h, m)
	var in_span := NS._fb_in_span(v, basis, k_t)
	if in_span:
		return {"sigma": sigma, "sigma_fixed": sigma, "in_span": true, "fixed": false}
	# 奇偶修正(同 :3744-3772;字典迭代序=插入序,与运行期一致)
	var v2 := NS._fb_nearest_span(v, basis, k_t)
	for ti in k_t:
		if v[ti] != v2[ti]:
			var t3: int = orbit_ids[ti]
			var done_swap := false
			for key4 in cur_by:
				var kk_parts: PackedStringArray = String(key4).split("_")
				if int(kk_parts[0]) != t3:
					continue
				var cur3: Array = cur_by[key4]
				var home3: Array = home_by[key4]
				if cur3.size() >= 2:
					var tmp = home3[0]
					home3[0] = home3[1]
					home3[1] = tmp
					h[cur3[0]] = home3[0]
					h[cur3[1]] = home3[1]
					done_swap = true
					break
			if not done_swap:
				return {"empty": true}
	return {"sigma": sigma, "sigma_fixed": NS._fb_inv(h, m), "in_span": false,
			"fixed": true}


func _p2a(p: PackedInt32Array) -> Array:
	var a: Array = []
	a.resize(p.size())
	for i in p.size():
		a[i] = p[i]
	return a


func _initialize() -> void:
	var out := {
		"meta": {
			"generated_by": "tests/_probe_stage0_export.gd",
			"protocol": "B0 层a口径: cube.setup(n); cube.scramble(40, rng); rng.seed=20260929(每 n 重置); NS.solve_centers(to_facelets) 失败即卡点态; trial=B0 循环序号",
			"domain": "中心段 cells 域: idx -> facelet fi*n*n + r*n + c (fi 面序 U R F D L B, r,c ∈ 1..n-2), 同引擎 _cn_cells / spike build_cells",
			"perm_semantics": "pull: new[j] = old[perm[j]] (同引擎 _cn_apply), gens 与 sigma 同一语义",
			"sigma_semantics": "sigma = _fb_sigma_of(st, fb) = h^-1 (h[cur]=home 同轨同色升序配对); sifting 消费方向 p = sigma[i] (nxn_solver.gd:3821)。sigma=未修正版(=运行期 CN_FB_PARITY_FIX=false 现行为); sigma_fixed=奇偶修正版(=PARITY_FIX=true 行为, swap 修正复刻 :3744-3772)。n=5 行空间满维(r=k=3)两版恒等; n=6/7 实测多数态 sigma 奇偶越出行空间(σ∉⟨gens⟩, 未修正 sifting 结构性必挂)——直测主口径用 sigma_fixed, sigma 保留供 A/B 对账(impl-plan §3.3)",
			"gens_domain": "层转全集: 外层 6面×3suffix + 内层 d∈3..n-1 6面×3suffix, _fb_key 去重(对层互逆重复已并), 记号同引擎(如 '3R' 从 R 面数第 3 层)。n=5/6/7 去重后 45/54/63 个——澄清 impl-plan §9.2 的 90 vs 63 冲突: spike 90 是未去重 token 数",
			"align_samples": "外层转/内层转已知 σ 样例(引擎 _cn_id_perm 实算), 供 GDScript↔Python 索引对齐比对",
		},
		"gens_by_n": {},
		"align_samples_by_n": {},
		"stuck_states": [],
	}
	var stuck_total := 0
	for n in [5, 6, 7]:
		var trials: int = 15
		var fb := _light_fb(n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var gens: Array = fb.gens
		var orbit_groups: Dictionary = fb.orbit_groups
		# 轨道指纹(供对齐核对)
		var orb_sizes: Array = []
		for t in orbit_groups:
			orb_sizes.append((orbit_groups[t] as Array).size())
		orb_sizes.sort()
		# gens 导出
		var glist: Array = []
		for g in gens:
			glist.append({"alg": String(g.alg), "perm": _p2a(g.perm)})
		out["gens_by_n"][str(n)] = glist
		# 对齐样例:外层转 2 例 + 内层 d 转 2 例
		var samples := {}
		for alg in ["U", "F2", "3R", "4L'"]:
			samples[alg] = _p2a(NS._cn_id_perm(alg, n, cells))
		out["align_samples_by_n"][str(n)] = samples
		# B0 口径扫态
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260929
		var cn_deg := 0
		var empty_sigma := 0
		var oob := 0
		for trial in trials:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			cube.scramble(40, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var rc: Dictionary = NS.solve_centers(fs)
			if rc.ok:
				cube.free()
				continue
			cn_deg += 1
			var st: PackedByteArray = NS._cn_state_of(fs, n)
			var sr: Dictionary = _sigma_full(st, fb)
			if sr.get("empty", false):
				empty_sigma += 1
			var oob_here: bool = not bool(sr.in_span)
			if oob_here:
				oob += 1
			var sta: Array = []
			sta.resize(st.size())
			for i in st.size():
				sta[i] = st[i]
			out["stuck_states"].append({
				"n": n,
				"trial": trial,
				"error": String(rc.get("error", "")),
				"st": sta,
				"sigma": _p2a(sr.sigma),
				"sigma_fixed": _p2a(sr.sigma_fixed),
				"parity_in_span": not oob_here,
				"sigma_empty": bool(sr.get("empty", false)),
			})
			cube.free()
		stuck_total += cn_deg
		print("n=%d: 层转gens=%d 轨道=%s 中心段卡点 %d/%d sigma空配对=%d 奇偶越界=%d" % [n,
				gens.size(), str(orb_sizes), cn_deg, trials, empty_sigma, oob])
	print("合计卡点态 %d (B0 层a口径 n=5/6/7 trials=15 实测)" % stuck_total)
	# 落盘
	var dir := DirAccess.open("res://tests")
	if dir != null and not dir.dir_exists("fixtures"):
		var err := dir.make_dir("fixtures")
		if err != OK:
			push_error("make_dir fixtures 失败: %d" % err)
			quit(1)
			return
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("打不开 %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("WROTE %s (卡点 %d)" % [OUT, out["stuck_states"].size()])
	quit(0)
