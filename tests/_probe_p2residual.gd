extends SceneTree
## 一次性探针(2026-10-05,P2 残余第 1 步解剖——grilling 定案 8 问+3 加固口径):
## CN_KEY_LOCK 9 seed(n=5/6/7 × 3,test_server.gd S9 哈希锁定表同源)复现卡点态,
## 回答三个预注册问题:
##   Q1(风险 6 触发前提):放宽 end_dfs 剪枝后卡点态是否存在净增宏链——
##      三档模拟:对照(=原版行为,卡点态上必然无解,有解即探针实现 BUG)/
##      单点(仅首宏 inc≥-1,设计文档既定口径)/任意步(每步 inc≥-1,更宽参考档);
##      budget 主档 = 引擎同款 ctx.cap×3,另跑无限档(1<<30)记上界参考,防
##      「理论存在但引擎预算内不可达」虚标 GO。
##   Q2(风险 7 目标形态):卡点态色流矩阵平衡流环分解(行和=列和数学性质保证
##      可分解),3-环=三面循环=B3 主治域;3-环态再实测 B3 合成单式
##      (B2 展开族两两复合,moved==3 且跨 3 面,含自算 keeps 按入池口径过滤)inc。
##   Q3(两路径外残余):Q1/Q2 均不治的散点态单列计数,不预归因 focus 机理。
## 保真度清单(grilling Q1 定案):sub 池 keeps 预筛 / focus 期 ma 出口 /
##   budget=cap×3 / 命中链逐跳复核(独立重放校验档位与终态) / 自检门 9 key 全中
##   CN_KEY_LOCK(任一漂移即 FAIL,数据不可信)。
## 预注册判定门槛(grilling 定案,先定死后跑):R6_GO=单点档净增链 ≥2/9;
##   单点 0-1 而任意步 ≥2 → 回报再裁;R7_GO=3-环形态 ≥1 态且 B3 合成式 inc>0。
## 终局(2026-10-05 实跑):R6/R7 双 NO-GO,定性见 EXPERIENCE.md 2026-10-05 条——
##   R6=链存在但 cap×3 预算内不可达(无限档单点5/任意4 态有链),实施须配预算
##   扩张,超「局部放宽」预设;R7=B2×2 与 B2×U^a×B2 两合成域「3格3面」均 0 条,
##   §3.5「B2×2=三面循环」前提实测不成立,B3 需外部公式收集另立工作包;
##   主发现=9/9 卡点态错格主体为 3-环(44-92%)+2-环对换,中盘卡住非收尾坎。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_p2residual.gd
## (装载与主循环复刻参考 tests/_probe_stuck_survey.gd 同款确定性路径)。

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")

const FACE_NAMES := ["U", "R", "F", "D", "L", "B"]

## 与 test_server.gd:24 CN_KEY_LOCK 同源复制(P2 落地后 2026-10-05 实测)。
const KEY_LOCK := {5: {20261009: "1056292279", 20261109: "2092487133", 20261209: "1419916045"},
	6: {20261010: "1395471020", 20261110: "4080059418", 20261210: "2633837371"},
	7: {20261011: "1606329917", 20261111: "1335305809", 20261211: "1992924430"}}

## 放宽档:0=对照(原版行为) 1=仅首宏 inc≥-1(风险 6 既定) 2=任意步 inc≥-1(参考)。
const RELAX_NONE := 0
const RELAX_FIRST := 1
const RELAX_ANY := 2

var _any_fail := false
var _b3_diag_done := false


func _initialize() -> void:
	var cube: Node3D = CUBE.new()
	# 预注册判定汇总(定案口径:主档 budget 计数,无限档仅参考)
	var r6_first := 0        # 单点档净增链(placed 终态 > p0)命中态数
	var r6_any := 0          # 任意步档净增链命中态数
	var r6_first_ma := 0     # 单点档「ma 改善出口」链命中态数(focus 态参考口径,单列)
	var r6_unb_first := 0    # 无限档单点档额外命中(主档无解而无限档有解,分档)
	var r6_unb_any := 0      # 无限档任意步档额外命中
	var ring_states := 0     # 含 3-环色流形态的态数
	var b3_hit := 0          # B3 合成式 inc>0 命中态数(仅 3-环态测)
	var outer_residual := 0  # 两路径外残余(Q1 无解 ∧ 无 3-环 ∧ placed≥80% ∧ 完成面≥1)
	var other_form := 0      # 未归类(Q1 无解 ∧ 无 3-环 但不满足外残余判据)
	for n in [5, 6, 7]:
		for sd: int in KEY_LOCK[n]:
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			cube.scramble(20, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var r: Dictionary = NS.solve(fs)
			var err := String(r.get("error", ""))
			print("=== n=%d seed=%d ===" % [n, sd])
			if r.get("ok", false) or not err.contains("降级"):
				_fail("自检门:预期降级(与 CN_KEY_LOCK 建表口径不符),实际 ok=%s err=%s" % [r.get("ok"), err])
				continue
			var st: PackedByteArray = _stuck_state(fs, n)
			var key: int = NS._cn_key(st)
			var key_ok: bool = str(key) == String(KEY_LOCK[n][sd])
			print("  key=%d 对照=%s %s" % [key, String(KEY_LOCK[n][sd]), "命中" if key_ok else "漂移"])
			if not key_ok or not err.contains(str(key)):
				_fail("自检门:卡点 key 漂移(复现路径与建表口径不一致),本探针数据不可信")
				continue
			# ---- Q1:三档 DFS + 无限档 ----
			var q1: Dictionary = _q1_relax_dfs(st, n)
			var hit_first: bool = q1.first_net > 0
			var hit_any: bool = q1.any_net > 0
			if hit_first:
				r6_first += 1
			if hit_any:
				r6_any += 1
			if q1.first_ma > 0:
				r6_first_ma += 1
			r6_unb_first += int(q1.unb_first)
			r6_unb_any += int(q1.unb_any)
			# ---- Q2:环分解(三角形优先消解口径) + B3 合成式 ----
			var ctx: Dictionary = NS._cn_ensure(n)
			var pc: int = int(ctx.pc)
			var rings: Dictionary = _flow_rings(st, pc)
			var tri: int = int(rings.tri)
			var has3: bool = tri > 0
			var ring_pct := float(tri) / float(6 * pc - NS._cn_placed(st, pc))
			if has3:
				ring_states += 1
			var b3_max := -99
			var b3_alg := ""
			if has3:
				var b3: Dictionary = _q2_b3_hit(st, n)
				b3_max = int(b3.max_inc)
				b3_alg = String(b3.alg)
				if b3_max > 0:
					b3_hit += 1
			# ---- Q3 归类 ----
			var placed: int = NS._cn_placed(st, pc)
			var done0: int = NS._cn_done_mask(st, pc)
			var n_done := 0
			for fi in 6:
				if done0 & (1 << fi) != 0:
					n_done += 1
			var cat := ""
			if hit_first or hit_any:
				cat = "风险6可治(%s)" % ("单点档" if hit_first else "仅任意步档")
			elif has3 and b3_max > 0:
				cat = "B3可治(max_inc=%d)" % b3_max
			elif has3:
				cat = "3-环形态但B3合成式inc≤0(max=%d)" % b3_max
			elif float(placed) >= 0.8 * 6.0 * float(pc) and n_done >= 1:
				cat = "两路径外残余"
				outer_residual += 1
			else:
				cat = "未归类形态"
				other_form += 1
			print("  Q1: 对照=%s 单点净增=%s(首宏inc=%d,深%d,增%d) 任意步净增=%s(首宏inc=%d,深%d,增%d) 单点ma链=%d 无限档额外=单点%d/任意%d" % [
					"有解(BUG!)" if q1.ctrl_solved else "无解✓",
					"是" if hit_first else "否", q1.first_head_inc, q1.first_depth, q1.first_gain,
					"是" if hit_any else "否", q1.any_head_inc, q1.any_depth, q1.any_gain,
					q1.first_ma, q1.unb_first, q1.unb_any])
			if hit_first and String(q1.first_alg) != "":
				print("    单点档链: %s" % String(q1.first_alg))
			var ring_pct_s := ""
			if has3:
				ring_pct_s = " 3环占比=%.0f%%" % (ring_pct * 100.0)
			var b3_s := "未测(无3环)"
			if has3:
				b3_s = "max_inc=%d [%s]" % [b3_max, b3_alg]
			print("  Q2: 3环消解=%d格 剩余环=%s%s B3=%s" % [tri, str(rings.rest), ring_pct_s, b3_s])
			print("  placed=%d/%d 完成面=%d 归类=%s" % [placed, 6 * pc, n_done, cat])
			print("")
	# ---- 预注册判定输出 ----
	print("========== 预注册判定(门槛先定死后跑) ==========")
	var r6_go: bool = r6_first >= 2
	print("R6(风险6 首宏inc≥-1): 单点档净增链 %d/9 → %s" % [r6_first,
			"GO(≥2)" if r6_go else ("回报再裁(单点<2 但任意步≥2)" if r6_any >= 2 else "NO-GO(证伪,不实施)")])
	print("R6 参考: 任意步档 %d/9, 单点ma改善链 %d 态, 无限档额外命中 单点%d/任意%d(理论存在预算内不可达)" % [r6_any, r6_first_ma, r6_unb_first, r6_unb_any])
	var r7_go: bool = ring_states >= 1 and b3_hit >= 1
	print("R7(风险7 B3): 3-环形态 %d 态, 合成式命中 %d 态 → %s" % [ring_states, b3_hit,
			"GO(≥1 环形态且 inc>0)" if r7_go else "NO-GO(B3 证伪记档)"])
	print("Q3 单列: 两路径外残余 %d 态, 未归类 %d 态(均不计入两路径收益预期)" % [outer_residual, other_form])
	if _any_fail:
		quit(1)
	else:
		quit(0)


func _fail(msg: String) -> void:
	print("FAIL  " + msg)
	_any_fail = true


## 复刻 _cn_solve 主循环(与 _probe_stuck_survey._trace_stuck 同款确定性路径)到
## 「搜索穷尽」break,返回卡点中心态。与 solve 同输入同轨迹(key 已由自检门对照)。
func _stuck_state(fs: PackedByteArray, n: int) -> PackedByteArray:
	var st: PackedByteArray = NS._cn_state_of(fs, n)
	var pc: int = (n - 2) * (n - 2)
	var cells: PackedInt32Array = NS._cn_cells(n)
	var pre: String = NS._cn_prealg(st, n)
	var total := 0
	var guard := 0
	if pre != "":
		st = NS._cn_apply(st, NS._cn_id_perm(pre, n, cells))
		total += int(NS.LBL._token_count(pre))
	while NS._cn_done_mask(st, pc) != 63:
		guard += 1
		if guard > NS.CN_STAGE_GUARD or total >= NS.CN_MOVE_LIMIT:
			break  # 超 guard 轨迹:key 必对不上自检门,此处防死循环即可
		var seg: Dictionary = NS._cn_segment(st, n)
		if seg.is_empty():
			return st
		for m in (seg.segs if seg.has("segs") else [seg]):
			st = NS._cn_apply(st, m.perm)
			total += int(m.tokens)
	return st  # 超 guard/防御性返回,key 由自检门判漂移


## Q1:对卡点态跑放宽版 _cn_dfs_rec(_cn_end_dfs 同款 sub 池/入口参数/深度档/
## budget),三档 + 无限档。保真度:keeps 预筛、focus 期 ma 出口、budget 共享,
## 与 nxn_solver.gd:2038-2055 逐项对齐;唯一差异 = relax 档位的下限。
## 命中链经 _verify_chain 独立重放复核,复核失败 = 探针 BUG(_fail)。
func _q1_relax_dfs(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = NS._cn_ensure(n)
	var pc: int = int(ctx.pc)
	var done0 := NS._cn_done_mask(st, pc)
	var p0: int = NS._cn_placed(st, pc)
	var focus: bool = done0 == 0
	var m0 := 0
	if focus:
		m0 = NS._cn_max_align(st, pc)
	var sub: Array = []
	for e: Dictionary in ctx.end_atoms:
		if done0 & ~int(e.keeps) == 0:
			sub.append(e)
	var out := {"ctrl_solved": false, "first_net": 0, "first_head_inc": 0, "first_depth": 0,
			"first_gain": 0, "first_alg": "", "first_ma": 0,
			"any_net": 0, "any_head_inc": 0, "any_depth": 0, "any_gain": 0,
			"unb_first": 0, "unb_any": 0}
	# 对照档(原版行为):卡点态上必然无解;有解 = 探针实现与引擎不一致。
	var b_ctrl := {"n": int(ctx.cap) * 3}
	for depth in [2, 3]:
		var rc: Dictionary = _dfs_relax(st, sub, p0, m0, focus, done0, pc, depth, b_ctrl, RELAX_NONE, true)
		if not rc.is_empty():
			out.ctrl_solved = true
			_fail("PROBE-BUG: 对照档(原版行为)在卡点态上竟有解——探针实现与引擎不一致,中止判读")
			return out
	# 单点档(主档 budget)与任意步档(主档 budget)。ma 改善链仅在该档最终无
	# 净增链时计 1(focus 态参考口径,防与净增双计)。
	var b_first := {"n": int(ctx.cap) * 3}
	var b_any := {"n": int(ctx.cap) * 3}
	var first_ma_found := false
	for depth in [2, 3]:
		var r1: Dictionary = _dfs_relax(st, sub, p0, m0, focus, done0, pc, depth, b_first, RELAX_FIRST, true)
		if r1.is_empty():
			continue
		if _chain_is_net(r1, st, pc, focus, p0, m0):
			out.first_net = 1
			out.first_head_inc = int(r1.segs[0].head_inc)
			out.first_depth = int(r1.segs.size())
			out.first_gain = NS._cn_placed(_replay(st, r1), pc) - p0
			out.first_alg = _chain_algs(r1)
			break
		elif focus:
			first_ma_found = true
	if out.first_net == 0 and first_ma_found:
		out.first_ma = 1
	for depth in [2, 3]:
		var r2: Dictionary = _dfs_relax(st, sub, p0, m0, focus, done0, pc, depth, b_any, RELAX_ANY, true)
		if not r2.is_empty() and _chain_is_net(r2, st, pc, focus, p0, m0):
			out.any_net = 1
			out.any_head_inc = int(r2.segs[0].head_inc)
			out.any_depth = int(r2.segs.size())
			out.any_gain = NS._cn_placed(_replay(st, r2), pc) - p0
			break
	# 无限档(仅放宽两档;分档记「主档无解而无限档有解」次数 = 预算内不可达证据)。
	for mode in [RELAX_FIRST, RELAX_ANY]:
		var b_inf := {"n": 1 << 30}
		for depth in [2, 3]:
			var r3: Dictionary = _dfs_relax(st, sub, p0, m0, focus, done0, pc, depth, b_inf, mode, true)
			if not r3.is_empty() and _chain_is_net(r3, st, pc, focus, p0, m0):
				if mode == RELAX_FIRST and out.first_net == 0:
					out.unb_first += 1
				elif mode == RELAX_ANY and out.any_net == 0:
					out.unb_any += 1
				break
	return out


## _cn_dfs_rec(nx:2059-2085)的放宽版:唯一差异 = placed 下限(见 floor_n)。
## segs 每段记录 alg/perm/tokens/head_inc(该跳起点→终点的 placed 增量,复核用)。
func _dfs_relax(cur: PackedByteArray, sub: Array, p0: int, m0: int, focus: bool,
		done0: int, pc: int, depth_left: int, budget: Dictionary, mode: int, first: bool) -> Dictionary:
	if depth_left == 0 or int(budget.n) <= 0:
		return {}
	var cp: int = NS._cn_placed(cur, pc)
	for e: Dictionary in sub:
		if int(budget.n) <= 0:
			return {}
		budget.n = int(budget.n) - 1
		var nxt := NS._cn_apply(cur, e.perm)
		var np: int = NS._cn_placed(nxt, pc)
		var floor_n := cp
		if mode == RELAX_ANY or (mode == RELAX_FIRST and first):
			floor_n = cp - 1
		if np < floor_n:
			continue
		if NS._cn_done_mask(nxt, pc) & done0 != done0:
			continue
		var head_inc := np - cp
		if np > p0 or (focus and NS._cn_max_align(nxt, pc) > m0):
			return {"segs": [{"alg": String(e.alg), "perm": e.perm, "tokens": int(e.tokens),
					"head_inc": head_inc}]}
		var r: Dictionary = _dfs_relax(nxt, sub, p0, m0, focus, done0, pc, depth_left - 1, budget, mode, false)
		if not r.is_empty():
			var segs: Array = r.segs
			segs.push_front({"alg": String(e.alg), "perm": e.perm, "tokens": int(e.tokens),
					"head_inc": head_inc})
			return {"segs": segs}
	return {}


## 命中链判净:非 focus 态须终态 placed > p0;focus 态出口本就允许 ma 改善,
## 净增口径 = 重放终态 placed > p0(ma 改善链不算净增,由调用方单列)。
## 判净前先过 _verify_chain 逐跳复核(独立重放校验档位与终态,复核失败=探针BUG)。
func _chain_is_net(r: Dictionary, st0: PackedByteArray, pc: int,
		focus: bool, p0: int, m0: int, mode := -2) -> bool:
	var mode_eff: int = mode
	if mode_eff == -2:
		mode_eff = RELAX_ANY  # 复核档位从宽取任意步(两档都 ≥ 该下限,不误伤单点档)
	var verr: String = _verify_chain(r, st0, pc, focus, p0, m0, mode_eff)
	if verr != "":
		_fail("PROBE-BUG: 链复核失败 %s" % verr)
		return false
	return NS._cn_placed(_replay(st0, r), pc) > p0


func _replay(st0: PackedByteArray, r: Dictionary) -> PackedByteArray:
	var cur := st0
	for s in r.segs:
		cur = NS._cn_apply(cur, s.perm)
	return cur


func _chain_algs(r: Dictionary) -> String:
	var parts: Array = []
	for s in r.segs:
		parts.append("%s(inc%+d)" % [String(s.alg), int(s.head_inc)])
	return " → ".join(parts)


## 逐跳复核:从入口态独立重放,校验 (a) 每跳 placed 增量 ≥ 档位下限
## (mode=RELAX_FIRST: 首跳 ≥-1 其余 ≥0;RELAX_ANY: 每跳 ≥-1);
## (b) 完成面保持;(c) 出口条件(非 focus: 终态 placed > p0;focus: ma > m0 或净增)。
func _verify_chain(r: Dictionary, st0: PackedByteArray, pc: int,
		focus: bool, p0: int, m0: int, mode: int) -> String:
	var cur := st0
	var prev := NS._cn_placed(cur, pc)
	var done0 := NS._cn_done_mask(cur, pc)
	for i in r.segs.size():
		cur = NS._cn_apply(cur, s_perm(r.segs[i]))
		var np: int = NS._cn_placed(cur, pc)
		var floor_inc := 0
		if mode == RELAX_ANY or (mode == RELAX_FIRST and i == 0):
			floor_inc = -1
		if np - prev < floor_inc:
			return "第%d跳 inc=%d 违反档位下限%d" % [i, np - prev, floor_inc]
		if NS._cn_done_mask(cur, pc) & done0 != done0:
			return "第%d跳破坏完成面" % i
		prev = np
	if not (prev > p0 or (focus and NS._cn_max_align(cur, pc) > m0)):
		return "终态不满足出口条件"
	return ""


func s_perm(s: Dictionary) -> PackedInt32Array:
	return s.perm


## Q2-a:色流矩阵环分解。M[面][色]=面上他色格数(f≠c),行和[f]=列和[f]
## (面 f 错格数=色 f 外流数)→ 剩余流量图节点入=出。
## 两段式:(1) 三角形优先消解——3-环(B3 主治域)按「存在即可消」口径统计,
## 与宏治疗语义直接对应;(2) 剩余图栈式简单环分解(遇重复栈节点挖子环,
## 修正首版「闭路径当单环」缺陷——len>6 即该缺陷的特征)。
## 返回 {tri: 3-环消解格数, rest: [{len,cnt}]}。
func _flow_rings(st: PackedByteArray, pc: int) -> Dictionary:
	var w := []
	for f in 6:
		var row := []
		row.resize(6)
		for c in 6:
			row[c] = 0
		w.append(row)
	for f in 6:
		for i in pc:
			var v: int = st[f * pc + i]
			if v != f:
				w[f][v] += 1
	# (1) 三角形优先消解
	var tri := 0
	var found := true
	while found:
		found = false
		for a in 6:
			for b in 6:
				for c in 6:
					if a != b and b != c and c != a \
							and w[a][b] > 0 and w[b][c] > 0 and w[c][a] > 0:
						w[a][b] -= 1
						w[b][c] -= 1
						w[c][a] -= 1
						tri += 3
						found = true
						break
				if found:
					break
			if found:
				break
	# (2) 剩余图:栈式简单环分解
	var rings: Array = []
	while true:
		var start := -1
		for f in 6:
			for c in 6:
				if w[f][c] > 0:
					start = f
					break
			if start >= 0:
				break
		if start < 0:
			break
		var path: Array = [start]
		var pos := {start: 0}
		var cur: int = start
		while true:
			var nxt := -1
			for c in 6:
				if w[cur][c] > 0:
					nxt = c
					break
			if nxt < 0:
				break  # 仅栈=[start] 时可达(栈顶不变量 out=in+1)
			w[cur][nxt] -= 1
			if pos.has(nxt):
				# 挖子环:path[pos[nxt]..end] 长度即环长(闭回 nxt)
				rings.append(path.size() - int(pos[nxt]))
				while path.size() > int(pos[nxt]) + 1:
					pos.erase(path[path.size() - 1])
					path.pop_back()
				cur = nxt
			else:
				pos[nxt] = path.size()
				path.push_back(nxt)
				cur = nxt
	var agg := {}
	for ln in rings:
		agg[ln] = int(agg.get(ln, 0)) + int(ln)
	var rest: Array = []
	for ln in agg:
		rest.append({"len": int(ln), "cnt": int(agg[ln])})
	rest.sort_custom(func(a, b): return a.len < b.len)
	return {"tri": tri, "rest": rest}


## Q2-b:B3 合成单式族 = B2 展开族(nx:1821-1848 同款重建:y4×x2,轨道档 d∈3..n-1)
## 两两复合(含同式自乘与两方向),筛 moved==3 且三格分属三面;keeps 自算
## (面全不动→bit),测试时按入池口径过滤(与引擎 end_atoms keeps 预筛一致)。
## 返回 {max_inc, alg}:该态上全部 B3 合成式的最大 inc(≤0 = 无命中)。
func _q2_b3_hit(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = NS._cn_ensure(n)
	var cells: PackedInt32Array = ctx.cells
	var pc: int = int(ctx.pc)
	var done0 := NS._cn_done_mask(st, pc)
	var p0: int = NS._cn_placed(st, pc)
	var b2s: Array = []
	for d in range(3, n):
		var skel := "B2 %dR' %dF %dR B2 %dR' %dF' %dR" % [d, d, d, d, d, d]
		for bk in 4:
			for bx in 2:
				var balg: String = NS._rotate_y(skel, bk)
				if bx == 1:
					balg = NS._remap_x2(balg)
				var bperm := NS._cn_id_perm(balg, n, cells)
				var mv := 0
				for bi in bperm.size():
					if bperm[bi] != bi:
						mv += 1
				if mv == 0:
					continue
				b2s.append(bperm)
	var max_inc := -99
	var best := ""
	var diag := {}   # (moved,faces) 形态谱:判定 B3 目标形态(moved==3∧faces==3)是否可达
	# 摆位缀 conn(nx:1855 同款 9 条);纯 B2×2 无 U 摆位实测产生不出 3格3面
	# (首版诊断 0 条),§3.5 组合口径本含 U 前缀摆位,故补缀位枚举(前/中/后)。
	var conns: Array = []
	for cn in ["U", "U'", "U2", "D", "D'", "D2", "3U", "3U'", "3U2"]:
		conns.append(NS._cn_id_perm(cn, n, cells))
	for i in b2s.size():
		for j in b2s.size():
			var pa: PackedInt32Array = b2s[i]
			var pb: PackedInt32Array = b2s[j]
			for ci in conns.size():
				var pu: PackedInt32Array = conns[ci]
				for pos in 3:
					var seq: Array
					if pos == 0:
						seq = [pu, pa, pb]     # 执行序 U → B2a → B2b
					elif pos == 1:
						seq = [pb, pu, pa]    # B2b → U → B2a(§3.5 中缀口径)
					else:
						seq = [pb, pa, pu]    # B2b → B2a → U
					var comp := _seq_perm(seq)
					var moved: Array = []
					var faces := {}
					for k2 in comp.size():
						if comp[k2] != k2:
							moved.append(k2)
							faces[k2 / pc] = true
					var dk := "%d格%d面" % [moved.size(), faces.size()]
					diag[dk] = int(diag.get(dk, 0)) + 1
					if moved.size() != 3 or faces.size() != 3:
						continue
					var keeps := 0
					for f in 6:
						var all_keep := true
						for i2 in pc:
							if comp[f * pc + i2] != f * pc + i2:
								all_keep = false
								break
						if all_keep:
							keeps |= 1 << f
					if done0 & ~keeps == 0:
						continue  # 入池口径:破坏完成面的合成式即使 inc>0 引擎也不会用
					var inc: int = NS._cn_placed(NS._cn_apply(st, comp), pc) - p0
					if inc > max_inc:
						max_inc = inc
						best = "B2[%d]·conn%d(pos%d)·B2[%d] moved=%s keeps=%d" % [i, ci, pos, j, str(moved), keeps]
	if not _b3_diag_done:
		_b3_diag_done = true
		print("  [B3诊断] n=%d B2展开%d条×conn9×pos3复合形态谱=%s(目标形态=3格3面)" % [n, b2s.size(), str(diag)])
	return {"max_inc": max_inc, "alg": best}


## 执行序复合:seq 按执行顺序排列(先执行在前),T[k] = P_last[...P_0[k]]。
func _seq_perm(seq: Array) -> PackedInt32Array:
	var acc: PackedInt32Array = seq[0]
	for idx in range(1, seq.size()):
		var p: PackedInt32Array = seq[idx]
		var nxt := PackedInt32Array()
		nxt.resize(acc.size())
		for k in acc.size():
			nxt[k] = p[acc[k]]
		acc = nxt
	return acc
