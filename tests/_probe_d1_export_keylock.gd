extends SceneTree
## D1 commit 2 配套探针(2026-10-11):9 seed 卡点态(CN_KEY_LOCK,与
## _probe_d1_verify.gd:13-15 同表)的 σ 导出——tools/minkwitz_build.py 质量门
## 「9 seed 卡点态直测」的输入。口径完全复刻 _probe_d1_verify.gd ③ 段:
## scramble(20)、_cn_prealg 先行、主通路 _cn_segment 推到卡点;σ 用轻量层转域
## fb(同 _probe_stage0_export.gd,不跑 27GB 风险的 _fb_build)双口径导出
## (sigma=未修正/sigma_fixed=PARITY_FIX=true 行为)。
## 不在 CI 清单;复核运行:
## bash -c 'ulimit -v 4000000 && timeout 600 godot --headless -s tests/_probe_d1_export_keylock.gd'

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")
const OUT := "res://tests/fixtures/d1_keylock_sigma.json"

const KEY_LOCK := {5: {20261009: "1056292279", 20261109: "2092487133", 20261209: "1419916045"},
		6: {20261010: "1395471020", 20261110: "4080059418", 20261210: "2633837371"},
		7: {20261011: "1606329917", 20261111: "1335305809", 20261211: "1992924430"}}


## 层转全集 gens(与 tests/_probe_stage0_export.gd:23-45 同款)
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


## 轻量 fb(同 _probe_stage0_export.gd:49-68:只喂层转全集,orbit 并查集重建)
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


## σ 双口径(引擎 _fb_sigma_of 语义:未修正+修正,同 _probe_stage0_export.gd:73-182)
func _sigma_full(st: PackedByteArray, fb: Dictionary) -> Dictionary:
	var m: int = fb.m
	var pc: int = fb.pc
	var orbit_of: PackedInt32Array = fb.orbit_of
	var orbit_groups: Dictionary = fb.orbit_groups
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
			"generated_by": "tests/_probe_d1_export_keylock.gd",
			"protocol": "CN_KEY_LOCK 9 seed(同 _probe_d1_verify.gd:13-15):cube.setup(n); rng.seed=sd; cube.scramble(20, rng); _cn_prealg 先行; 主通路 _cn_segment 推到卡点(guard=CN_STAGE_GUARD/CN_MOVE_LIMIT); 卡点态 st 导出 σ 双口径",
			"sigma_semantics": "同 tests/fixtures/stage0_sigma.json meta.sigma_semantics:pull 语义,sigma=未修正(=PARITY_FIX=false 现行为),sigma_fixed=修正版(=PARITY_FIX=true 行为);sifting 消费方向 p=sigma[i]",
		},
		"keylock_states": [],
	}
	var total := 0
	for n in [5, 6, 7]:
		var fb := _light_fb(n)
		for sd: int in KEY_LOCK[n]:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			cube.scramble(20, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var st: PackedByteArray = NS._cn_state_of(fs, n)
			var pc: int = (n - 2) * (n - 2)
			var pre: String = NS._cn_prealg(st, n)
			if pre != "":
				st = NS._cn_apply(st, NS._cn_id_perm(pre, n, NS._cn_cells(n)))
			# 主循环到卡点(与 _probe_d1_verify.gd:92-101 同款)
			var guard := 0
			var toks := 0
			while NS._cn_done_mask(st, pc) != 63:
				guard += 1
				if guard > NS.CN_STAGE_GUARD or toks >= NS.CN_MOVE_LIMIT:
					break
				var seg: Dictionary = NS._cn_segment(st, n)
				if seg.is_empty():
					break
				for mm in (seg.segs if seg.has("segs") else [seg]):
					st = NS._cn_apply(st, mm.perm)
					toks += int(mm.tokens)
			if NS._cn_done_mask(st, pc) == 63:
				print("n=%d seed=%d: 主通路已解(?!),跳过" % [n, sd])
				cube.free()
				continue
			var key := NS._cn_key(st)
			var expect: String = KEY_LOCK[n][sd]
			var key_match: bool = str(key) == expect
			var sr := _sigma_full(st, fb)
			var sta: Array = []
			sta.resize(st.size())
			for i in st.size():
				sta[i] = st[i]
			out["keylock_states"].append({
				"n": n,
				"seed": sd,
				"key": str(key),
				"key_match_expected": key_match,
				"st": sta,
				"sigma": _p2a(sr.sigma),
				"sigma_fixed": _p2a(sr.sigma_fixed),
				"parity_in_span": bool(sr.in_span),
				"sigma_empty": bool(sr.get("empty", false)),
			})
			total += 1
			print("n=%d seed=%d: 卡点 key=%s 预期=%s 匹配=%s σ空=%s 越界=%s" % [n, sd,
					str(key), expect, "是" if key_match else "否",
					"是" if bool(sr.get("empty", false)) else "否",
					"否" if bool(sr.in_span) else "是"])
			cube.free()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("打不开 %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("WROTE %s (9 seed 卡点态 %d 个)" % [OUT, total])
	quit(0)
