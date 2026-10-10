extends SceneTree
## 【作废探针——结果不可信,保留只为记录 bug 形态】(2026-10-10,v7.3 B1)
## 本版 sinv_of 只存了逆置换,下方「setup」循环把逆当正用(sp 与 si 同数组),
## 产出「moved==3 ×208 条」全部是错误公式下的假货(alg 标注与效应不对应)。
## 正确语义版 = tests/_probe_b1_enum2.gd:真实 setup+宏+undo 三重积
## 「外层18×池宏2440×外层18」moved==3/5 零命中(直方图边界 4..24),
## moved==4(双对换)1440+ moved==6(双3-环)8352 新效应 1388 条对 B0 卡点态
## 单发零命中——支集覆盖 ~0.4%,枚举收集路线证伪,详见方案文档 r3 执行记录。
## 不在 CI 清单;运行:godot --headless -s tests/_probe_b1_enum.gd

const NS := preload("res://scripts/nxn_solver.gd")


func _initialize() -> void:
	NS._ensure_edges()
	# 层转全集(单切片;3X 与 D' 等重复置换由 key 去重)
	var toks: Array = []
	var seen_p: Dictionary = {}
	for f in ["U", "D", "R", "L", "F", "B"]:
		# 仅外层(内层切片破坏中心 setwise,_edge_perm_of 返回空——§6 拒入条款)
		for suf in ["", "'", "2"]:
			for _pre in [""]:
				var t: String = f + suf
				var p := NS._edge_perm_of(t)
				if p.size() != 24:
					continue
				var k := NS._fb_key(p)
				if seen_p.has(k):
					continue
				seen_p[k] = true
				toks.append(t)
	# 池(基础+复合)
	var pool: Array = []
	var seen_eff: Dictionary = {}
	for m in NS._edge_pool:
		pool.append(m)
		seen_eff[NS._fb_key(m.perm)] = true
	for m2 in NS._edge_local:
		pool.append(m2)
		seen_eff[NS._fb_key(m2.perm)] = true
	print("层转(去重)=%d 池宏=%d" % [toks.size(), pool.size()])
	# 三重积 s×p×s'(setup+宏+undo 型):净 = comp(sp, comp(mp, sp_inv))
	var hits3: Array = []
	var hits4: Array = []
	var seen3: Dictionary = {}
	var sinv_of: Dictionary = {}
	for s_tok: String in toks:
		var sp := NS._edge_perm_of(s_tok)
		var si := PackedInt32Array()
		si.resize(24)
		for w in 24:
			si[sp[w]] = w
		sinv_of[s_tok] = si
	for s_tok: String in toks:
		var sp: PackedInt32Array = sinv_of[s_tok]
		var si: PackedInt32Array = sinv_of[s_tok]
		for m: Dictionary in pool:
			var mp: PackedInt32Array = m.perm
			var mid := PackedInt32Array()
			mid.resize(24)
			for w in 24:
				mid[w] = mp[sp[w]]   # 先 s 后 p
			for s2_tok: String in toks:
				var sp2 := NS._edge_perm_of(s2_tok)
				var net := PackedInt32Array()
				net.resize(24)
				var moved := 0
				for w2 in 24:
					net[w2] = si[sp2[mid[w2]]]   # 再 s'
					if net[w2] != w2:
						moved += 1
				if moved != 3 and moved != 4:
					continue
				var k2 := NS._fb_key(net)
				if seen_eff.has(k2) or seen3.has(k2):
					continue
				seen3[k2] = true
				var alg: String = s_tok + " " + String(m.alg) + " " + s2_tok
				if moved == 3:
					hits3.append({"alg": alg, "perm": net})
				else:
					hits4.append({"alg": alg, "perm": net})
	print("新效应 moved==3(3-环): %d 条; moved==4: %d 条" % [hits3.size(), hits4.size()])
	for h in hits3.slice(0, 8):
		var net: PackedInt32Array = h.perm
		var cyc: Array = []
		var done: Dictionary = {}
		for w in 24:
			if net[w] == w or done.has(w):
				continue
			var cy: Array = []
			var j := w
			while not done.has(j):
				done[j] = true
				cy.append(j)
				j = net[j]
			cyc.append(cy)
		print("  [%s] 环=%s" % [h.alg, str(cyc)])
	quit(0)
