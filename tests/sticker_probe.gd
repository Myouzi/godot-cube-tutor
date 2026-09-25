extends SceneTree
## 像素级渲染核验探针:精确复刻 visual_test.gd 生成 shot_alg_final 的操作序列
## (玩家步 R + play_alg("R U R' U'")),动画结束后导出每个朝向相机贴纸的
## 屏幕投影坐标 + 预期 albedo 颜色到 out/sticker_probe.json。
## 配合 tools/probe_pixels.py 采样 PNG 像素比对,把"渲染 vs 逻辑"争议变成确定性判定。
## 运行(项目根,必须带 DISPLAY,不能 headless):
##   env DISPLAY=:0 godot --rendering-driver opengl3 -s tests/sticker_probe.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://out")
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		printerr("FAIL  main.tscn 加载失败")
		quit(1)
		return
	var main: Node = scene.instantiate()
	main.get_node("CubeServer").port = 18888
	root.add_child(main)
	for i in 4:
		await process_frame
	var cube = main.get_node("CubeRoot")
	var camera: Camera3D = main.get_node("Camera3D")

	# ---- 复刻 shot_alg_final 序列:中间帧玩家步 R,等完,再 play_alg ----
	cube.enqueue_turn(Vector3.RIGHT, [2], -PI / 2)
	while cube.is_animating():
		await process_frame
	var queued: int = cube.play_alg("R U R' U'")
	if queued != 4:
		printerr("FAIL  play_alg 入队 %d 步(预期 4)" % queued)
		quit(1)
		return
	while cube.is_animating():
		await process_frame

	# ---- 逻辑终态三重确认(与 visual_test 同款独立基线) ----
	var c2 = load("res://scripts/cube.gd").new()
	c2.setup(3)
	c2.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	c2.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	c2.apply_turn(Vector3.UP, [2], -PI / 2)
	c2.apply_turn(Vector3.RIGHT, [2], PI / 2)
	c2.apply_turn(Vector3.UP, [2], PI / 2)
	if cube.to_facelets() != c2.to_facelets():
		printerr("FAIL  重放终态 facelets != 独立基线(探针复现错误)")
		quit(1)
		return
	print("PASS  重放终态 facelets == 独立逻辑基线")

	# ---- 导出贴纸投影 ----
	var cam_forward := -camera.global_transform.basis.z.normalized()
	var probes := []
	for c in cube.cubies:
		for s in c.get_children():
			if not (s is MeshInstance3D):
				continue
			# 贴纸局部 +Y 即其初始法线(stickers 字典键);bake 只旋 cubie.basis,
			# 贴纸局部变换不动,世界法线 = cubie 全局基 × 局部法线。
			var local_n: Vector3 = s.transform.basis.y.normalized()
			var world_n: Vector3 = (c.global_transform.basis * local_n).normalized()
			if world_n.dot(cam_forward) > -0.35:
				continue  # 非朝向相机的贴纸(法线与视线同向/侧向),采样被遮挡,不导出
			var point: Vector3 = s.global_position + world_n * 0.06
			var uv: Vector2 = camera.unproject_position(point)
			var albedo: Color = s.mesh.surface_get_material(0).albedo_color
			probes.append({
				"x": uv.x, "y": uv.y,
				"r": albedo.r, "g": albedo.g, "b": albedo.b,
				"gp": "%d,%d,%d" % [c.grid_pos.x, c.grid_pos.y, c.grid_pos.z],
				"n": "%d,%d,%d" % [int(local_n.x), int(local_n.y), int(local_n.z)],
			})
	var f := FileAccess.open(out_dir + "/sticker_probe.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(probes))
	f.close()
	print("PROBES  %d 个朝向相机的贴纸已导出 -> out/sticker_probe.json" % probes.size())
	quit(0)
