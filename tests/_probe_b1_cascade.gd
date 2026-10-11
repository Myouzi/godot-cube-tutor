extends SceneTree
## 实验 B1 第二棒:组合级联验证(B1 的 go/no-go 闸门,impl-plan §2.2 判读 Q3)
## go = 级联全通 10/10;否则 no_go。找到核式 ≠ 组合全通(probe7 净负教训)。
## 候选核式集 = 第一棒具名候选(2+1 型 candidateCount=0;已知 1+1+1 核式 + 枚举代表样本)
##   ∪ 本探针 r1 域重枚举 1+1+1 全量去重(不依赖上一棒日志留存)。
## 入池模拟 = /tmp/_probe_b1_l2e_probe7.gd 写法修正版:
##   core × y4 × x2 × U^a D^b × 外层 setup 共轭;
##   修 len = 真实字符长度(probe7 len=9 取巧扰动贪心择优,impl-plan :109);
##   修 perm 一律 _edge_perm_of(s_out) 实测 + moved==3 入池断言(impl-plan :110)
##   ——probe7 手算复合 net=s_inv∘perm∘sp 与 _edge_apply 串复合语义
##   (nxn_solver.gd:1402, "S M S'" ⇒ pS∘pM∘pS')方向待对照,实测口径消除该风险。
## 级联 8 轮:R1=known 展开全集入池(修正口径后对照 probe7 净负复现);
##   R2-R6=其余具名按命中变体降序逐条加(命中子集口径=仅注入对基线卡点
##   kept 保持∧配对数增的变体);R7=best+r1 域新增 top4;R8=精简。
##   保留提升、剔除净负/持平。终验复跑留档(不计组合尝试轮)。
## 红线:scripts/ 零改动;_edge_local 复合库不入(nxn_solver.gd:1293-1295 条款)。
## 用法:bash -c 'ulimit -v 4000000 && timeout 600 godot --headless -s tests/_probe_b1_cascade.gd'
## 假绿双校验:exit code==0 且输出无 SCRIPT ERROR。
const NS := preload("res://scripts/nxn_solver.gd")

const NAMED := [
	["known-t3", "3R U2 3R' D2 3R U2 3R' D2"],
	["r1-B2", "3R U2 3R' B2 3R U2 3R' B2"],
	["r2-r", "r U2 r' D2 r U2 r' D2"],
	["r3-F", "r' F r D2 r' F' r D2"],
	["r3-Uinv", "3R U' 3R' D2 3R U 3R' D2"],
	["r6-F2", "r' F2 r D2 r' F2 r D2"],
]


static func _inv(t: String) -> String:
	if t.ends_with("'"):
		return t.substr(0, t.length() - 1)
	if t.ends_with("2"):
		return t
	return t + "'"


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


var _cache := {}
var _stuck: Array = []


## 展开一层:命中变体标 hit(对基线卡点 kept 保持 ∧ 配对数增的态数)。
func _expand(core: String) -> Array:
	if _cache.has(core):
		return _cache[core]
	var toks: Array = []
	for f in ["U", "D", "R", "L", "F", "B"]:
		for suf in ["", "'", "2"]:
			if NS._edge_perm_of(f + suf).size() == 24:
				toks.append(f + suf)
	var out: Array = []
	for s_tok in toks:
		for k in 4:
			for xr in 2:
				var c2: String = NS._rotate_y(core, k)
				if xr == 1:
					c2 = NS._remap_x2(c2)
				var pc2 := NS._edge_perm_of(c2)
				if pc2.size() != 24:
					continue
				# moved==3 是核式级闸门(impl-plan :110):姿态化核式必须仍是 3-环。
				# UD 前缀/setup 变体不断言——UD 前缀净效果=U/D 层转∘3-环,moved>3
				# 与引擎基池宏同性质(EDGE_BASES 条目本就动多 wing),过 _edge_perm_of
				# 闸门(size==24)即可入池,命中筛选交由 _hits 实测。
				if _moved(pc2) != 3:
					push_error("入池闸门 姿态核式 moved!=3: " + c2)
					quit(1)
					return []
				for ua in 4:
					for da in 4:
						var pre := ""
						if ua > 0:
							pre += NS._u_pow(ua) + " "
						if da > 0:
							pre += NS._d_pow(da) + " "
						var s_out: String = pre + c2
						if s_tok != "U":
							s_out = s_tok + " " + s_out + " " + _inv(s_tok)
						var p := NS._edge_perm_of(s_out)
						if p.size() != 24:
							continue
						out.append({"alg": s_out, "perm": p, "len": s_out.length(),
								"hit": _hits(p)})
	_cache[core] = out
	return out


func _hits(p: PackedInt32Array) -> int:
	var h := 0
	for s in _stuck:
		var st: PackedByteArray = s["st"]
		var p0: int = NS._edges_paired(st)
		var kept: int = NS._edge_pair_mask(st)
		var st2: PackedByteArray = NS._edge_apply(st, p)
		if NS._edge_pair_mask(st2) & kept != kept:
			continue
		if NS._edges_paired(st2) > p0:
			h += 1
	return h


## 组合级联一轮:注入(子集口径=命中变体 / full=展开全集)→ 跑全 10 态 → 恢复池。
func _cascade(cores: Array, cfs: Array, base_n: int, full: bool) -> Dictionary:
	NS._edge_pool.resize(base_n)
	var merged := {}
	var n_raw := 0
	var n_hit := 0
	for c in cores:
		for e in _expand(c):
			n_raw += 1
			if not full and int(e["hit"]) <= 0:
				continue
			n_hit += 1
			var key: String = NS._fb_key(e["perm"])
			if not merged.has(key) or int(merged[key]["len"]) > int(e["len"]):
				merged[key] = e
	var arr: Array = merged.values()
	arr.sort_custom(func(a, b) -> bool: return int(a["len"]) < int(b["len"]))
	NS._edge_pool.append_array(arr)
	var okc := 0
	var rows: PackedStringArray = []
	var rem: Array = []
	var rem_pairs: Array = []
	for i in cfs.size():
		if cfs[i] == null:
			rows.append("t%d 中心降级" % i)
			rem.append(i)
			continue
		var rc: Dictionary = NS.solve_edges(cfs[i])
		if rc.ok:
			okc += 1
			rows.append("t%d ok" % i)
		else:
			var msg: String = String(rc.error)
			var cut := msg.find(",")
			if cut > 0:
				msg = msg.substr(0, cut)
			var pr := msg.find("卡点 ")
			var pr_end := msg.find("/", pr) if pr >= 0 else -1
			rem_pairs.append(int(msg.substr(pr + 3, pr_end - pr - 3)) if pr_end > pr else -1)
			rows.append("t%d FAIL[%s]" % [i, msg])
			rem.append(i)
	NS._edge_pool.resize(base_n)
	return {"ok": okc, "rows": rows, "rem": rem, "rem_pairs": rem_pairs,
			"n": arr.size(), "raw": n_raw,
			"inj": n_hit if not full else n_raw}


func _initialize() -> void:
	NS._ensure_edges()
	var base_n: int = NS._edge_pool.size()
	# ---------- 阶段 A:基线 B0 全 10 态(无注入) ----------
	var cube0: Node3D = preload("res://scripts/cube.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var cfs: Array = []
	var base_fail: Array = []
	for trial in 10:
		cube0.setup(4)
		cube0.scramble(40, rng)
		var fs: PackedByteArray = cube0.to_facelets()
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			cfs.append(null)
			print("BASE t%d 中心段降级:%s" % [trial, String(rc.error)])
			continue
		var sim: PackedByteArray = fs.duplicate()
		NS._apply_alg(sim, String(rc.alg))
		cfs.append(sim)
		if NS.solve_edges(sim).ok:
			continue
		base_fail.append(trial)
		# 卡点 wing 态提取(第一棒 _probe_b1_l2e.gd:226-236 同款重放)
		var st: PackedByteArray = NS._wing_state_of(sim)
		var guard := 0
		while NS._edges_paired(st) < 12 and guard < 400:
			var seg: Dictionary = NS._edge_segment(st)
			if seg.is_empty():
				break
			st = NS._edge_apply(st, seg.perm)
			guard += 1
		if NS._edges_paired(st) < 12:
			_stuck.append({"trial": trial, "st": st})
	var base_score := 10 - base_fail.size()
	print("== 阶段 A 基线:SCORE=%d/10 卡点 trial=%s ==" % [base_score, str(base_fail)])
	for s in _stuck:
		var st: PackedByteArray = s["st"]
		print("  卡点 t%d 配对=%d/12 wing态=%s" % [s["trial"], NS._edges_paired(st),
				NS._edge_key(st).substr(0, 48)])
	# ---------- 阶段 B:候选核式集 ----------
	var cands: Array = []   # [{name, alg, fbkey}]
	var seen_core := {}
	for nm in NAMED:
		var p: PackedInt32Array = NS._edge_perm_of(nm[1])
		if p.size() != 24 or _moved(p) != 3:
			print("ASSERT-FAIL 具名候选过闸失败: %s" % nm[0])
			quit(1)
			return
		var key: String = NS._fb_key(p)
		cands.append({"name": nm[0], "alg": nm[1], "fbkey": key})
		seen_core[key] = true
	# r1 域重枚举 1+1+1 全量去重(第一棒 round=1 域复刻;交叉验证 2+1=0)
	var edge_of := {}
	for e in 12:
		for w in NS._edge_wings[e]:
			edge_of[w] = e
	var forms: Array = []
	var inters: Array = []
	for f in ["U", "D", "L", "R", "F", "B"]:
		for suf in ["", "'", "2"]:
			inters.append(f + suf)
	for f in ["R", "L", "U", "D", "F", "B"]:
		for s_v in ["3" + f, "3" + f + "'"]:
			var s_inv: String = _inv(s_v)
			for i_tok in inters:
				forms.append(s_v + " " + i_tok + " " + s_inv + " " + _inv(i_tok))
				for x in inters:
					forms.append(s_v + " " + i_tok + " " + s_inv + " " + x + " "
							+ s_v + " " + i_tok + " " + s_inv + " " + x)
	var kind21 := 0
	var kind111 := 0
	var c111 := {}   # fbkey → alg(取 len 短)
	for alg in forms:
		var p: PackedInt32Array = NS._edge_perm_of(alg)
		if p.size() != 24 or _moved(p) != 3:
			continue
		var cnt := {}
		for w in 24:
			if p[w] != w:
				var eid: int = edge_of[w]
				cnt[eid] = int(cnt.get(eid, 0)) + 1
		var vals: Array = cnt.values()
		vals.sort()
		if vals == [2, 1]:
			kind21 += 1
			continue
		if vals != [1, 1, 1]:
			continue
		kind111 += 1
		var key: String = NS._fb_key(p)
		if not c111.has(key) or String(c111[key]).length() > alg.length():
			c111[key] = alg
	print("== 阶段 B r1 域枚举:形态 %d,moved==3 中 2+1=%d(交叉验证上一棒=0) 1+1+1 去重=%d =="
			% [forms.size(), kind21, c111.size()])
	var r7_pool: Array = []
	for key in c111:
		if not seen_core.has(key):
			r7_pool.append(c111[key])
	r7_pool.sort_custom(func(a, b) -> bool: return a.length() < b.length())
	# ---------- 阶段 C:probe7 复合方向对照 + 单发验证 ----------
	var demo_core: String = NAMED[0][1]
	var sp: PackedInt32Array = NS._edge_perm_of("F")
	var s_inv := PackedInt32Array()
	s_inv.resize(24)
	for i in 24:
		s_inv[sp[i]] = i
	var pc2: PackedInt32Array = NS._edge_perm_of(demo_core)
	var demo_alg: String = "F " + demo_core + " F'"
	var pmeas: PackedInt32Array = NS._edge_perm_of(demo_alg)
	var p7 := PackedInt32Array()
	p7.resize(24)
	for w in 24:
		p7[w] = s_inv[pc2[sp[w]]]
	print("EXP-CHK probe7手算复合 == 实测_edge_perm_of: %s (demo=\"%s\")"
			% [str(p7 == pmeas), demo_alg])
	print("== 阶段 C 单发验证(裸核式层 / 展开层,基线卡点 %d 态) ==" % _stuck.size())
	for c in cands:
		var bare: PackedInt32Array = NS._edge_perm_of(c["alg"])
		var ex: Array = _expand(c["alg"])
		var vhit := 0
		var vbest := 0
		for e in ex:
			var h: int = e["hit"]
			if h > 0:
				vhit += 1
			vbest = maxi(vbest, h)
		c["vhit"] = vhit
		print("CAND %-10s \"%s\" 净=%s 裸=%d/%d 展开=%d条 命中变体=%d 单变体最多覆盖=%d态"
				% [c["name"], c["alg"], _cyc(bare), _hits(bare), _stuck.size(),
				ex.size(), vhit, vbest])
	# ---------- 阶段 D:组合级联 ≤8 轮 ----------
	var best_set: Array = []
	var best_score: int = base_score
	var best_rem: Array = base_fail.duplicate()
	var rnd := 0
	# R1:probe7 对照——known 展开全集入池(修正 len/perm 后的净负复现)
	rnd += 1
	var r1: Dictionary = _cascade([NAMED[0][1]], cfs, base_n, true)
	print("ROUND 1 full对照[known] 池+%d(展开%d) SCORE=%d/10 Δ=%+d rem=%s"
			% [r1["n"], r1["raw"], r1["ok"], r1["ok"] - best_score, str(r1["rem"])])
	print("   %s" % " | ".join(PackedStringArray(r1["rows"])))
	if r1["ok"] > best_score:
		best_set = [NAMED[0][1]]
		best_score = r1["ok"]
		best_rem = r1["rem"]
	else:
		print("   → 全集口径不提升(%s)" % ("净负,probe7 现象复现" if r1["ok"] < best_score else "持平"))
	# R2..R6:其余 5 条 named 按命中变体降序,命中子集口径逐条加
	var order: Array = []
	for i in range(1, cands.size()):
		order.append(cands[i])
	order.sort_custom(func(a, b) -> bool: return int(a.get("vhit", 0)) > int(b.get("vhit", 0)))
	for c in order:
		if rnd >= 7:
			break
		rnd += 1
		var trial_set: Array = best_set.duplicate()
		trial_set.append(c["alg"])
		var r: Dictionary = _cascade(trial_set, cfs, base_n, false)
		print("ROUND %d +[%s] 池+%d(展开%d/命中%d) SCORE=%d/10 Δ=%+d rem=%s"
				% [rnd, c["name"], r["n"], r["raw"], r["inj"], r["ok"],
				r["ok"] - best_score, str(r["rem"])])
		print("   %s" % " | ".join(PackedStringArray(r["rows"])))
		if r["ok"] > best_score:
			best_set = trial_set
			best_score = r["ok"]
			best_rem = r["rem"]
		elif r["ok"] < best_score:
			print("   → 净负,剔除 %s(probe7 教训)" % c["name"])
		else:
			print("   → 持平无贡献,剔除 %s" % c["name"])
	# R7:r1 域枚举新增候选(alg 最短前 4 一组并池,命中子集口径)
	if rnd < 8 and r7_pool.size() > 0:
		rnd += 1
		var pick: Array = []
		for i in mini(4, r7_pool.size()):
			pick.append(r7_pool[i])
		var trial_set: Array = best_set.duplicate()
		trial_set.append_array(pick)
		var r: Dictionary = _cascade(trial_set, cfs, base_n, false)
		var names: PackedStringArray = []
		for a in pick:
			names.append(a.substr(0, 24))
		print("ROUND %d +[r1域top4:%s] 池+%d(展开%d/命中%d) SCORE=%d/10 Δ=%+d rem=%s"
				% [rnd, " / ".join(names), r["n"], r["raw"], r["inj"], r["ok"],
				r["ok"] - best_score, str(r["rem"])])
		print("   %s" % " | ".join(PackedStringArray(r["rows"])))
		if r["ok"] > best_score:
			best_set = trial_set
			best_score = r["ok"]
			best_rem = r["rem"]
	# R8:命中核合击——展开层有单发证据(vhit>0)的具名核全部并池最后一搏
	# (R2 实测 r2-r 把 t3 卡点深度 9→10 推进后卡新 10/12 态,但贪心剔核致
	#  「多命中核组合」从未被测;此轮补测组合上限)
	if rnd < 8:
		var hitters: Array = []
		for c in cands:
			if int(c.get("vhit", 0)) > 0:
				hitters.append(c["alg"])
		if hitters.size() >= 2:
			rnd += 1
			var r: Dictionary = _cascade(hitters, cfs, base_n, false)
			print("ROUND %d 合击[%d条命中核] 池+%d(展开%d/命中%d) SCORE=%d/10 Δ=%+d rem=%s 卡点深度=%s(基线和29)"
					% [rnd, hitters.size(), r["n"], r["raw"], r["inj"], r["ok"],
					r["ok"] - best_score, str(r["rem"]), str(r["rem_pairs"])])
			print("   %s" % " | ".join(PackedStringArray(r["rows"])))
			if r["ok"] > best_score:
				best_set = hitters
				best_score = r["ok"]
				best_rem = r["rem"]
	# 终验留档(不占组合尝试轮:确定性复跑)
	var final: Dictionary = _cascade(best_set, cfs, base_n, false)
	print("== 终验 best_cores=%d 条 池+%d SCORE=%d/10 rem=%s =="
			% [best_set.size(), final["n"], final["ok"], str(final["rem"])])
	var verdict := "go" if best_score == 10 else "no_go"
	var joined: String = " / ".join(PackedStringArray(best_set))
	print("RESULT verdict=%s base=%d/10 best=%d/10 rounds=%d best_cores=[%s] remaining=%s"
			% [verdict, base_score, best_score, rnd, joined, str(best_rem)])
	quit(0)
