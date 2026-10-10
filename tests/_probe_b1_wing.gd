extends SceneTree
## 一次性探针(2026-10-10,v7.3 B1 开工前论证)【定案】:TNE-4 口径(seed
## 20260929,scramble(40))复现 n=4 组棱降级态,卡点态逐棱色集分析——
## 实测 3 态:2 棱交叉型(t0/t9:两棱各 {A,B})与 3 棱环形交叉型(t3),每色集
## 恰 2 块无丢失;修复效果 = wing 3-环(偶,如 (P1s0 Q1s0 P1s1) 一发解 t0 型),
## 与「面转对 wing 恒偶」守恒自洽——「奇效果」不存在也不需要;池缺口 =
## 特定支集 3-环效应。全数据见方案文档 r3 执行记录。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_b1_wing.gd

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")


func _initialize() -> void:
	var cube: Node3D = CUBE.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	for trial in 10:
		cube.setup(4)
		cube.scramble(40, rng)
		var fs: PackedByteArray = cube.to_facelets()
		var rc: Dictionary = NS.solve_centers(fs)
		if not rc.ok:
			print("t%d 中心段降级(跳过)" % trial)
			continue
		var sim := fs.duplicate()
		NS._apply_alg(sim, String(rc.alg))
		if NS.solve_edges(sim).ok:
			continue
		# 复刻组棱主链到卡点
		var st: PackedByteArray = NS._wing_state_of(sim)
		var guard := 0
		while NS._edges_paired(st) < 12 and guard < 400:
			guard += 1
			var seg: Dictionary = NS._edge_segment(st)
			if seg.is_empty():
				break
			st = NS._edge_apply(st, seg.perm)
		var paired: int = NS._edges_paired(st)
		# 未配对棱分析:每棱两槽的色集 id
		var bad: Array = []
		var slot_dump: Array = []
		for e in 12:
			var w: Array = NS._edge_wings[e]
			var a: int = st[w[0]]
			var b: int = st[w[1]]
			if a == b:
				slot_dump.append("[%d,%d]" % [a, a])
			else:
				bad.append(e)
				slot_dump.append("{%d,%d}" % [a, b])
		# 未配对棱涉及色集的全局分布(色集 -> 槽列表)
		var where: Dictionary = {}
		for e2 in 12:
			var w2: Array = NS._edge_wings[e2]
			for s in [w2[0], w2[1]]:
				var cid: int = st[s]
				if not where.has(cid):
					where[cid] = []
				(where[cid] as Array).append(e2)
		var multi: Array = []
		for cid in where:
			var locs: Array = where[cid]
			if locs.size() != 2:
				multi.append("色集%d@%s" % [cid, str(locs)])
		print("t%d 卡点 %d/12 对 未配对棱=%s" % [trial, paired, str(bad)])
		print("    槽内容: ", " ".join(PackedStringArray(slot_dump)))
		print("    异常色集分布(非2槽): ", ", ".join(PackedStringArray(multi)))
	quit(0)
