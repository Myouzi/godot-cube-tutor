extends SceneTree
## 一次性探针(2026-10-04 卡点态形态普查,宏族扩充工作包前置实测):
## 4/5/6/7 阶 × seed 20261004+n+off(offset 档 SEED_OFFSETS:基线 3 档 {0,1,2}
## 保持与 survey §4.2 12 样本可比,+100/+200 对齐 test_server S9 的多 seed 集,
## 3..9 为扩大采样档),scramble(20, seed) → NS.solve;
## 降级发生时复刻 _cn_solve 主循环(nx:2198 同款确定性路径)走到卡点,
## 抓完整中心态(6·pc 字节)做形态分析:
##   - placed / 完成面 / 每面对格数
##   - 每面错格 4-邻接连通拓扑(孤立单格/成对/条带/块/环)
##   - 面级色流量 M[面][色](非对角)→ 对换型 / 3-cycle 型 / 混合
##   - 卡点所处段/步计数与降级类型(穷尽 vs 超 guard)
## 不在 CI 清单,复核运行:godot --headless -s tests/_probe_stuck_survey.gd
## (参考 tests/test_nxn_centers.gd 的 NS/CUBE 装载与 SceneTree 写法;既述
##  tests/_probe_center_deg.gd 在本仓库工作区与 git 历史中均不存在,无从引用)。

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")

const FACE_NAMES := ["U", "R", "F", "D", "L", "B"]

## seed 偏移档:基线 3 档({0,1,2} = survey §4.2 的 12 样本)+ S9 对齐档
## {100,200}(加 +0 即 test_server S9 的 [seed, +100, +200] 三 seed)+ 扩样档
## {3..9}。每阶 12 态、共 48 态(center-macro-impl-design.md §6 P0 改动④)。
const SEED_OFFSETS := [0, 1, 2, 100, 200, 3, 4, 5, 6, 7, 8, 9]


func _initialize() -> void:
	var cube: Node3D = CUBE.new()
	for n in [4, 5, 6, 7]:
		for k in SEED_OFFSETS:
			var sd: int = 20261004 + n + k
			cube.setup(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = sd
			cube.scramble(20, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var t0 := Time.get_ticks_msec()
			var r: Dictionary = NS.solve(fs)
			var ms := Time.get_ticks_msec() - t0
			var err := String(r.get("error", ""))
			print("=== n=%d seed=%d (%dms) ===" % [n, sd, ms])
			print("solve: ok=%s error=%s" % [r.ok, err])
			if err.contains("降级"):
				_trace_stuck(fs, n, err)
			print("")
	quit(0)


## 复刻 _cn_solve 主循环(nx:2198-2243)到降级点,打印完整中心态形态分析。
## 确定性路径,与 solve 同输入同轨迹;卡点 key 与 error 内嵌哈希对照验证一致。
func _trace_stuck(fs: PackedByteArray, n: int, solve_err: String) -> void:
	var st: PackedByteArray = NS._cn_state_of(fs, n)
	var pc: int = (n - 2) * (n - 2)
	var inner: int = n - 2
	var cells: PackedInt32Array = NS._cn_cells(n)
	var pre: String = NS._cn_prealg(st, n)
	var guard := 0
	var total := 0
	var nseg := 0
	if pre != "":
		st = NS._cn_apply(st, NS._cn_id_perm(pre, n, cells))
		total += int(NS.LBL._token_count(pre))
	var kind := ""
	var key := 0
	while NS._cn_done_mask(st, pc) != 63:
		guard += 1
		if guard > NS.CN_STAGE_GUARD or total >= NS.CN_MOVE_LIMIT:
			kind = "超guard"
			break
		var seg: Dictionary = NS._cn_segment(st, n)
		if seg.is_empty():
			kind = "搜索穷尽"
			key = NS._cn_key(st)
			break
		nseg += 1
		for m in (seg.segs if seg.has("segs") else [seg]):
			st = NS._cn_apply(st, m.perm)
			total += int(m.tokens)
	print("trace: 类型=%s 段=%d(已执行)步=%d guard=%d key=%d" % [kind, nseg, total, guard, key])
	if kind == "搜索穷尽":
		var ok_match: bool = solve_err.contains(str(key))
		print("  key与solve.error内嵌哈希一致: %s" % ok_match)
	elif kind == "超guard":
		_dump_state(st, n, "[降级点=guard耗尽]")
		st = _relaxed_run(st, n, cells, total, guard, nseg)
		_dump_state(st, n, "[relaxed 终点]")
	_dump_state(st, n, "[卡点态=搜索穷尽]")


## 中心态形态全打印:placed/完成面/每面对格数与错格网格('.'=对格,数字=色)/
## 错格 4-邻接拓扑/面级色流量(面 fi 上混入色 c 的格数,守恒)。
func _dump_state(st: PackedByteArray, n: int, tag: String) -> void:
	var pc: int = (n - 2) * (n - 2)
	var inner: int = n - 2
	var placed: int = NS._cn_placed(st, pc)
	var done_mask: int = NS._cn_done_mask(st, pc)
	var done_faces: Array = []
	for fi in 6:
		if done_mask & (1 << fi) != 0:
			done_faces.append(FACE_NAMES[fi])
	print("  %s placed=%d/%d 完成面=%s 错格=%d" % [tag, placed, 6 * pc, done_faces, 6 * pc - placed])
	for fi in 6:
		var okc := 0
		var grid := ""
		for r in inner:
			var line := ""
			for c in inner:
				var v: int = st[fi * pc + r * inner + c]
				if v == fi:
					okc += 1
					line += ". "
				else:
					line += "%d " % v
			grid += "\n    " + line
		var wrong: Array = _wrong_cells(st, fi, pc, inner)
		var topo: String = _topology(wrong, inner)
		print("  %s(%d/%d%s) 错格拓扑=%s%s" % [FACE_NAMES[fi], okc, pc,
				" 完成" if done_mask & (1 << fi) != 0 else "", topo, grid])
	var flows := ""
	for fi in 6:
		for c in 6:
			if c == fi:
				continue
			var cnt := 0
			for i in pc:
				if st[fi * pc + i] == c:
					cnt += 1
			if cnt > 0:
				flows += "%s←%s:%d " % [FACE_NAMES[fi], FACE_NAMES[c], cnt]
	print("  色流: %s" % flows)


## 第二轮(仅超 guard 样本):预算读引擎常量 NS.CN_STAGE_GUARD / NS.CN_MOVE_LIMIT
## (center-macro-impl-design.md §4.1 配套:常量上调后探针自动切到落地口径,
## 基线前后 diff 用同一预算口径)。返回穷尽/二限时的中心态。
func _relaxed_run(st: PackedByteArray, n: int, cells: PackedInt32Array,
		total0: int, guard0: int, nseg0: int) -> PackedByteArray:
	var total := total0
	var guard := guard0
	var nseg := nseg0
	var kind2 := ""
	var key2 := 0
	while NS._cn_done_mask(st, (n - 2) * (n - 2)) != 63:
		guard += 1
		if guard > NS.CN_STAGE_GUARD or total >= NS.CN_MOVE_LIMIT:
			kind2 = "二限"
			break
		var seg: Dictionary = NS._cn_segment(st, n)
		if seg.is_empty():
			kind2 = "真穷尽"
			key2 = NS._cn_key(st)
			break
		nseg += 1
		for m in (seg.segs if seg.has("segs") else [seg]):
			st = NS._cn_apply(st, m.perm)
			total += int(m.tokens)
	print("relaxed(%d段/%d步): %s 段=%d 步=%d key=%d" % [NS.CN_STAGE_GUARD, NS.CN_MOVE_LIMIT, kind2, nseg, total, key2])
	return st


func _wrong_cells(st: PackedByteArray, fi: int, pc: int, inner: int) -> Array:
	var out: Array = []
	for i in pc:
		if st[fi * pc + i] != fi:
			out.append(i)
	return out


## 错格 4-邻接连通分量;分量形状命名:孤立/成对/条带(直线)/块(满矩形)/
## 缺心(矩形去中心)/团(不规则)。返回 "size×shape" 的 "+" 连接串。
func _topology(wrong: Array, inner: int) -> String:
	if wrong.is_empty():
		return "无"
	var wset := {}
	for i in wrong:
		wset[i] = true
	var seen := {}
	var comps: Array = []
	for i in wrong:
		if seen.has(i):
			continue
		var stack: Array = [i]
		seen[i] = true
		var comp: Array = []
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			comp.append(cur)
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var r: int = cur / inner + d[0]
				var c: int = cur % inner + d[1]
				var j: int = r * inner + c
				if r < 0 or r >= inner or c < 0 or c >= inner or not wset.has(j) or seen.has(j):
					continue
				seen[j] = true
				stack.append(j)
		comps.append(comp)
	var parts: Array = []
	for comp in comps:
		var rmin := 99
		var rmax := -1
		var cmin := 99
		var cmax := -1
		for j in comp:
			rmin = min(rmin, j / inner)
			rmax = max(rmax, j / inner)
			cmin = min(cmin, j % inner)
			cmax = max(cmax, j % inner)
		var w := cmax - cmin + 1
		var h := rmax - rmin + 1
		var shape := "团"
		if comp.size() == 1:
			shape = "孤立"
		elif comp.size() == 2:
			shape = "成对"
		elif comp.size() == w * h and (w == 1 or h == 1):
			shape = "条带%d" % comp.size()
		elif comp.size() == w * h:
			shape = "块%dx%d" % [w, h]
		elif comp.size() == w * h - 1 and w >= 2 and h >= 2:
			shape = "缺心%dx%d" % [w, h]
		parts.append("%d×%s" % [comp.size(), shape])
	return "+".join(parts)
