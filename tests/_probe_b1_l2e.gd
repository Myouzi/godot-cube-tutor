extends SceneTree
## 实验 B1 第一棒(正式探针):commutator 参数空间枚举 → wing 3-环核式定向搜索
## 目标:收集 2+1 支集形态(两 wing 同棱+一 wing 另一棱,修 t0/t9)候选核式;
##      1+1+1 形态(三 wing 各一棱,修 t3)已实证,须保留在候选集。
## 域(round=1):切片 轴3×侧2×方向2(n=4 深度 3..n-1 即 3R/3L/3U/3D/3F/3B×''/')
##   × interchange 外层 6 面×''/'/2 × 模板 T1=[S,I']=S I S' I' 与 T2=(S I S' X)^2
##   (已证 1+1+1 核式 "3R U2 3R' D2 3R U2 3R' D2" 即 T2: S=3R I=U2 X=D2)
## 分类:_edge_perm_of 过滤(中心 setwise+wing 块封闭,nxn_solver.gd:1363-1387)
##   → moved==3(单 3-环)→ 按 24 wing 支集落在棱上的分布分类(2+1 / 1+1+1 / 其他)。
## 增值:每候选对 B0 三卡点态(seed=20260929)测 kept 保持+配对数增命中(probe6 判据)。
## 用法:bash -c 'ulimit -v 4000000 && timeout 300 godot --headless -s tests/_probe_b1_l2e.gd -- round=1'
## 通过判据(假绿双校验):exit code==0 且输出无 SCRIPT ERROR。
const NS := preload("res://scripts/nxn_solver.gd")


static func _moved(p: PackedInt32Array) -> int:
	var m := 0
	for i in p.size():
		if p[i] != i:
			m += 1
	return m


static func _cyc(p: PackedInt32Array) -> String:
	var seen := {}
	var out: PackedStringArray = []
	for i in p.size():
		if seen.has(i) or p[i] == i:
			seen[i] = true
			continue
		var cyc: Array = []
		var j: int = i
		while not seen.has(j):
			seen[j] = true
			cyc.append(j)
			j = p[j]
		out.append("(" + ",".join(PackedStringArray(cyc.map(func(x): return str(x)))) + ")")
	return " ".join(out)


static func _inv(t: String) -> String:
	if t.ends_with("'"):
		return t.substr(0, t.length() - 1)
	if t.ends_with("2"):
		return t
	return t + "'"


func _initialize() -> void:
	NS._ensure_edges()
	var rd := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("round="):
			rd = int(a.substr(6))
	# wing→棱 映射(支集形态分类用;_edge_wings: 棱 e → [w0,w1])
	var edge_of := {}
	for e in 12:
		for w in NS._edge_wings[e]:
			edge_of[w] = e
	# ---- 枚举域 ----
	var slices: Array = []   # 切片 A 件(引擎记号,经 _apply_alg 文法实测)
	var inters: Array = []   # interchange B 件(外层)
	var forms: Array = []    # 核式形态串
	if rd == 1:
		# 切片:轴3(R/U/F)×对侧2(L/D/B)×方向2 → 3R/3R'/3L/3L'/3U/3U'/3D/3D'/3F/3F'/3B/3B'
		# (轴 3 × 深度 3..n-1:n=4 仅深度 3;侧=切片取 R 侧或 L 侧两内层)
		for f in ["R", "L", "U", "D", "F", "B"]:
			slices.append("3" + f)
			slices.append("3" + f + "'")
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i_tok in inters:
				# T1: [S, I] = S I S' I'
				forms.append(s_v + " " + i_tok + " " + s_inv + " " + _inv(i_tok))
				# T2: (S I S' X)^2 —— 已证 1+1+1 核式模板
				for x in inters:
					forms.append(s_v + " " + i_tok + " " + s_inv + " " + x + " "
							+ s_v + " " + i_tok + " " + s_inv + " " + x)
	elif rd == 2:
		# 换轴:双层 r 系(动 4 棱每棱 2 wing——唯一能供同棱 wing 对的切片件,cube.gd:171 layers=[3,1])
		# + 3Rw 系三层宽(depth=3 宽转 layers=[3,1,-1])
		for s_v in ["r", "r'", "r2", "3Rw", "3Rw'", "3Rw2"]:
			slices.append(s_v)
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i_tok in inters:
				forms.append(s_v + " " + i_tok + " " + s_inv + " " + _inv(i_tok))
				for x in inters:
					forms.append(s_v + " " + i_tok + " " + s_inv + " " + x + " "
							+ s_v + " " + i_tok + " " + s_inv + " " + x)
	elif rd == 3:
		# 混合拍 T3: S I1 S' X S I2 S' X(I1/I2/X 独立)——probe6 先例 "3R U' 3R' D2 3R U2 3R' D2"
		# 切片 = 单内层 12 + 双层 r 系 3(T1/T2 域已证的 3-环产出件)
		for f in ["R", "L", "U", "D", "F", "B"]:
			slices.append("3" + f)
			slices.append("3" + f + "'")
		slices.append_array(["r", "r'", "r2"])
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i1 in inters:
				for i2 in inters:
					for x in inters:
						forms.append(s_v + " " + i1 + " " + s_inv + " " + x + " "
								+ s_v + " " + i2 + " " + s_inv + " " + x)
	elif rd == 4:
		# 换轴:切片件补 180° 内层 + 宽层 90°;interchange 件引入内层切片 3U 系
		# (内层 interchange 中心集与切片层不交 → commutator 中心 setwise 仍保持,可过闸)
		for f in ["R", "L", "U", "D", "F", "B"]:
			slices.append("3" + f)
			slices.append("3" + f + "'")
			slices.append("3" + f + "2")
		slices.append_array(["3Rw", "3Rw'", "3Lw", "3Lw'"])
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
		for f in ["U", "D", "L", "R", "F", "B"]:
			inters.append("3" + f)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i_tok in inters:
				forms.append(s_v + " " + i_tok + " " + s_inv + " " + _inv(i_tok))
				for x in inters:
					forms.append(s_v + " " + i_tok + " " + s_inv + " " + x + " "
							+ s_v + " " + i_tok + " " + s_inv + " " + x)
	elif rd == 5:
		# T3 混合拍 × interchange 并集(外层18+内层切片6):I1/I2/X 三槽独立全枚举
		for f in ["R", "L", "U", "D", "F", "B"]:
			slices.append("3" + f)
			slices.append("3" + f + "'")
		slices.append_array(["r", "r'", "r2"])
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
		for f in ["U", "D", "L", "R", "F", "B"]:
			inters.append("3" + f)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i1 in inters:
				for i2 in inters:
					for x in inters:
						forms.append(s_v + " " + i1 + " " + s_inv + " " + x + " "
								+ s_v + " " + i2 + " " + s_inv + " " + x)
	elif rd == 6:
		# 末轮:interchange 件 = 小写宽层族(单独破中心 setwise,commutator 净效果由闸门实测裁决)
		# 切片件 = 单层 90° 全 + r 系 + 3Rw 系;模板 T1+T2;interchange = 外层 18 + 小写宽层 18
		for f in ["R", "L", "U", "D", "F", "B"]:
			slices.append("3" + f)
			slices.append("3" + f + "'")
		slices.append_array(["r", "r'", "r2", "3Rw", "3Rw'"])
		for f in ["U", "D", "L", "R", "F", "B"]:
			for suf in ["", "'", "2"]:
				inters.append(f + suf)
				inters.append(f.to_lower() + suf)
		for s_v in slices:
			var s_inv: String = _inv(s_v)
			for i_tok in inters:
				forms.append(s_v + " " + i_tok + " " + s_inv + " " + _inv(i_tok))
				for x in inters:
					forms.append(s_v + " " + i_tok + " " + s_inv + " " + x + " "
							+ s_v + " " + i_tok + " " + s_inv + " " + x)
	else:
		print("RESULT round=%d forms=0 note=未定义轮次域" % rd)
		quit(0)
		return
	# ---- 枚举 + 过滤 + 分类 ----
	var n_acc := 0
	var n_m3 := 0
	var kind21 := 0
	var kind111 := 0
	var cands := {}   # fbkey(净置换) → {alg, perm, kind}
	for alg in forms:
		var p := NS._edge_perm_of(alg)
		if p.size() != 24:
			continue
		n_acc += 1
		if _moved(p) != 3:
			continue
		n_m3 += 1
		var cnt := {}
		for w in 24:
			if p[w] != w:
				var e: int = edge_of[w]
				cnt[e] = int(cnt.get(e, 0)) + 1
		var vals: Array = cnt.values()
		vals.sort()
		var kind: String = "其他"
		if vals == [2, 1]:
			kind = "2+1"
		elif vals == [1, 1, 1]:
			kind = "1+1+1"
		if kind == "2+1":
			kind21 += 1
		elif kind == "1+1+1":
			kind111 += 1
		var key: String = NS._fb_key(p)
		if not cands.has(key) or String(cands[key].alg).length() > alg.length():
			cands[key] = {"alg": alg, "perm": p, "kind": kind}
	# ---- 已知 1+1+1 核式强制保留(独立实测复核,不依赖域覆盖) ----
	var known := "3R U2 3R' D2 3R U2 3R' D2"
	var pk := NS._edge_perm_of(known)
	var known_ok: bool = pk.size() == 24 and _moved(pk) == 3
	# ---- B0 三卡点态复现(seed=20260929,probe6 同款) ----
	var cube0: Node3D = preload("res://scripts/cube.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var stuck: Array = []
	for trial in 10:
		cube0.setup(4)
		cube0.scramble(40, rng)
		var fs: PackedByteArray = cube0.to_facelets()
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
		if NS._edges_paired(st) < 12:
			stuck.append(st)
	# ---- 候选 × 卡点命中(probe6 判据:kept 保持 + 配对数增) ----
	var lines21: PackedStringArray = []
	var lines111: PackedStringArray = []
	for key in cands:
		var c: Dictionary = cands[key]
		var hit := 0
		var det: Array = []
		for st0 in stuck:
			var p0: int = NS._edges_paired(st0)
			var kept0: int = NS._edge_pair_mask(st0)
			var st2: PackedByteArray = NS._edge_apply(st0, c.perm)
			if NS._edge_pair_mask(st2) & kept0 != kept0:
				continue
			if NS._edges_paired(st2) > p0:
				hit += 1
				det.append("%d→%d" % [p0, NS._edges_paired(st2)])
		var line := "\"%s\" | %s | %s | 卡点命中=%d/%d %s" % [c.alg, _cyc(c.perm), c.kind,
				hit, stuck.size(), "+".join(PackedStringArray(det))]
		if c.kind == "2+1":
			lines21.append(line)
		else:
			lines111.append(line)
	# ---- 汇总输出 ----
	print("== round %d 域: 形态 %d = 切片%d × I%d × 模板(T1+T2) ==" % [rd, forms.size(), slices.size(), inters.size()])
	print("过闸=%d moved==3=%d  2+1=%d  1+1+1=%d  去重候选=%d  B0卡点态=%d" % [n_acc, n_m3, kind21, kind111, cands.size(), stuck.size()])
	print("== 已知 1+1+1 核式实测复核: \"%s\" → %s (moved=%d, ok=%s) ==" % [known, _cyc(pk) if pk.size() == 24 else "拒入", _moved(pk) if pk.size() == 24 else -1, known_ok])
	if lines21.size() > 0:
		print("== 2+1 型候选(%d 条去重) ==" % lines21.size())
		for l in lines21:
			print("  " + l)
	if lines111.size() > 0:
		print("== 1+1+1 型候选(%d 条去重, 前 12 条) ==" % lines111.size())
		for i in mini(12, lines111.size()):
			print("  " + lines111[i])
	print("RESULT round=%d forms=%d acc=%d moved3=%d kind21=%d kind111=%d cands=%d stuck=%d" % [rd, forms.size(), n_acc, n_m3, kind21, kind111, cands.size(), stuck.size()])
	quit(0)
