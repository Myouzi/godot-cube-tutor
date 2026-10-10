extends SceneTree
## 一次性探针(2026-10-10,v7.3 B0 重测):层 a 金标准态拆降级归属——
## solve_centers 失败=中心段降级(D1 保底器未通);solve_edges 失败=纯组棱
## 降级(B1/B2 的需求依据)。口径同 TNE-6 层 a(rng.seed=20260929,scramble(40))。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_b0_survey.gd

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")


func _initialize() -> void:
	for n in [5, 6, 7]:
		var trials: int = 3 if n >= 7 else 15
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260929
		var cn_deg := 0
		var ed_deg := 0
		var okc := 0
		for trial in trials:
			var cube: Node3D = CUBE.new()
			cube.setup(n)
			cube.scramble(40, rng)
			var fs: PackedByteArray = cube.to_facelets()
			var rc: Dictionary = NS.solve_centers(fs)
			if not rc.ok:
				cn_deg += 1
				print("  n=%d t%d 中心段: %s" % [n, trial,
						String(rc.get("error", "")).left(60)])
				continue
			var sim := fs.duplicate()
			NS._apply_alg(sim, String(rc.alg))
			var re: Dictionary = NS.solve_edges(sim)
			if not re.ok:
				ed_deg += 1
				print("  n=%d t%d 组棱段: %s" % [n, trial,
						String(re.get("error", "")).left(60)])
				continue
			okc += 1
		print("n=%d 层a %d 态: 全绿 %d, 中心段降级 %d, 纯组棱降级 %d" % [n,
				trials, okc, cn_deg, ed_deg])
	quit(0)
