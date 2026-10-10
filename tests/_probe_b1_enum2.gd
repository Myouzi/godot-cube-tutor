extends SceneTree
## 一次性探针(2026-10-10,v7.3 B1 覆盖性验证)【定案】:真实 setup+宏+undo
## 三重积枚举(外层×池宏 2440×外层)——moved 直方图 {4:1440,6:8352,7:288,
## 8:14832,...},moved==3/5 零命中(3-环在此域不可达);收 moved∈{3,4,6} 新
## 效应 1388 条对 B0 三卡点态串联(≤6 发贪心)零命中——支集覆盖不足是本质,
## 枚举收集路线证伪。B1 残余路径 = 社区 L2E 定向公式转译或理论 commutator
## 构造。不在 CI 清单;复核运行:godot --headless -s tests/_probe_b1_enum2.gd

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")


static func _enum_hits(seen_eff: Dictionary) -> Array:
	var toks: Array = []
	for f in ["U", "D", "R", "L", "F", "B"]:
		for suf in ["", "'", "2"]:
			toks.append(f + suf)
	var sinv_of: Dictionary = {}
	for s_tok: String in toks:
		var sp := NS._edge_perm_of(s_tok)
		var si := PackedInt32Array()
		si.resize(24)
		for w in 24:
			si[sp[w]] = w
		sinv_of[s_tok] = [sp, si]
	var pool_all: Array = []
	for m in NS._edge_pool:
		pool_all.append(m)
	for m2 in NS._edge_local:
		pool_all.append(m2)
	var histo: Dictionary = {}
	var s0 := NS._edge_perm_of("U")
	print("DBG U perm size=%d 前4=%s" % [s0.size(), str(s0.slice(0, 4))])
	print("DBG toks=%d pool=%d" % [toks.size(), pool_all.size()])
	var hits: Array = []
	var seen3: Dictionary = {}
	for s_tok: String in toks:
		var sp: PackedInt32Array = sinv_of[s_tok][0]
		var si: PackedInt32Array = sinv_of[s_tok][1]
		for m0 in pool_all:
			var m: Dictionary = m0
			var mp: PackedInt32Array = m.perm
			var mid := PackedInt32Array()
			mid.resize(24)
			for w in 24:
				mid[w] = mp[sp[w]]
			for s2_tok: String in toks:
				var sp2: PackedInt32Array = sinv_of[s2_tok][0]
				var si2: PackedInt32Array = sinv_of[s2_tok][1]
				var net := PackedInt32Array()
				net.resize(24)
				var moved := 0
				for w2 in 24:
					net[w2] = si[sp2[mid[w2]]]
					if net[w2] != w2:
						moved += 1
				histo[moved] = (histo.get(moved, 0) as int) + 1
				if moved != 3 and moved != 4 and moved != 6:
					continue
				var k2 := NS._fb_key(net)
				if seen_eff.has(k2) or seen3.has(k2):
					continue
				seen3[k2] = true
				hits.append({"alg": s_tok + " " + String(m.alg) + " " + s2_tok,
						"perm": net})
	print("DBG moved直方图: ", str(histo))
	print("新效应收集: hits=%d" % hits.size())
	return hits


func _initialize() -> void:
	NS._ensure_edges()
	var seen_eff: Dictionary = {}
	for m in NS._edge_pool:
		seen_eff[NS._fb_key(m.perm)] = true
	for m2 in NS._edge_local:
		seen_eff[NS._fb_key(m2.perm)] = true
	var hits := _enum_hits(seen_eff)
	# 效应支集分布(按无序支集去重)
	var supp: Dictionary = {}
	for h in hits:
		var p: PackedInt32Array = h.perm
		var pts: Array = []
		for w in 24:
			if p[w] != w:
				pts.append(w)
		pts.sort()
		supp[str(pts)] = true
	print("3-环宏 %d 条, 效应去重 %d, 支集去重 %d" % [hits.size(), seen3_count(hits), supp.size()])
	# B0 卡点态重测:卡点 → 新宏单发解?→ 贪心域(基础池+hits)推进
	var cube: Node3D = CUBE.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	for trial in 10:
		cube.setup(4)
		cube.scramble(40, rng)
		var fs: PackedByteArray = cube.to_facelets()
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			continue
		var sim := fs.duplicate()
		NS._apply_alg(sim, String(rc.alg))
		if NS.solve_edges(sim).ok:
			continue
		var st: PackedByteArray = NS._wing_state_of(sim)
		var guard := 0
		while NS._edges_paired(st) < 12 and guard < 400:
			guard += 1
			var seg: Dictionary = NS._edge_segment(st)
			if seg.is_empty():
				break
			st = NS._edge_apply(st, seg.perm)
		var before: int = NS._edges_paired(st)
		if before == 12:
			continue
		# 新宏单发 + 串联(至多 4 发,每发选 inc 最大)
		var total_alg: Array = []
		for shot in 6:
			var best: Dictionary = {}
			var bp := NS._edges_paired(st)
			for h in hits:
				var st2 := NS._edge_apply(st, h.perm)
				var np := NS._edges_paired(st2)
				if np > bp:
					best = h
					bp = np
					break
			if best.is_empty():
				break
			st = NS._edge_apply(st, best.perm)
			total_alg.append(String(best.alg))
			if NS._edges_paired(st) == 12:
				break
		var after: int = NS._edges_paired(st)
		print("t%d 卡点 %d/12 → 新宏串联后 %d/12 (%s) 发=%d" % [trial, before,
				after, "解掉" if after == 12 else "残余", total_alg.size()])
	quit(0)


static func seen3_count(hits: Array) -> int:
	return hits.size()
