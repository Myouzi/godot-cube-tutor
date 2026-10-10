extends SceneTree
const NS := preload("res://scripts/nxn_solver.gd")
func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		var fb: Dictionary = NS._fb_ensure(n)
		var levels: int = (fb.levels as Array).size()
		print("构建 n=%d: %dms levels=%d" % [n, Time.get_ticks_msec() - t0, levels])
	quit(0)
