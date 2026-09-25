extends SceneTree
## 视觉验收(PLAN §8,仅 N=3):opengl3 真渲染截 3 张 PNG 到 out/ + facelets 逻辑断言。
## 运行(项目根,必须带 DISPLAY,不能 headless):
##   env DISPLAY=:0 godot --rendering-driver opengl3 -s tests/visual_test.gd
## 断言失败或异常 exit 1。

var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true


func _wait_frames(k: int) -> void:
	for i in k:
		await process_frame


func _sock_send(peer: StreamPeerTCP, req: Dictionary) -> void:
	peer.put_data((JSON.stringify(req) + "\n").to_utf8_buffer())


func _sock_recv(peer: StreamPeerTCP, timeout_frames: int) -> Dictionary:
	var buf := ""
	for i in timeout_frames:
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			buf += peer.get_data(avail)[1].get_string_from_utf8()
		var lf := buf.find("\n")
		if lf >= 0:
			var v = JSON.parse_string(buf.substr(0, lf))
			return v if v is Dictionary else {}
		await process_frame
	return {}


func _save_shot(path: String) -> void:
	await _wait_frames(4)  # 延帧:确保该状态已被渲染进后备缓冲
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("SAVED  " + path)


func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("res://out")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		printerr("FAIL  main.tscn 加载失败")
		quit(1)
		return
	var main: Node = scene.instantiate()
	main.get_node("CubeServer").port = 18888  # §8 验收端口,避让可能运行中的游戏实例(8788)
	root.add_child(main)
	await _wait_frames(4)  # _ready + setup(3) 重建完成
	var cube = main.get_node("CubeRoot")

	# ---- shot 1:初始态(含 UI),U 白 / R 红 / F 绿 ----
	var f0: PackedByteArray = cube.to_facelets()
	var solved_seq := PackedByteArray()
	solved_seq.resize(54)
	for i in 54:
		solved_seq[i] = i / 9
	_check(f0 == solved_seq, "初始 facelets == URFDLB 复原序(U白/R红/F绿)")
	_check(cube.is_solved(), "初始 is_solved")
	await _save_shot(out_dir + "/shot_initial.png")

	# ---- shot 2:R 层转中间帧(t≈0.5 → 约 45°),该层倾斜其余不动 ----
	cube.enqueue_turn(Vector3.RIGHT, [2], -PI / 2)
	await _wait_frames(2)  # _process 已 pop 队列、tween 启动
	await create_timer(0.09).timeout  # TURN_TIME(0.18s)一半
	var moved := 0
	var still := 0
	for c in cube.cubies:
		var expected: Vector3 = Vector3(c.grid_pos) * 0.5
		if c.global_position.distance_to(expected) > 0.02:
			moved += 1
		else:
			still += 1
	_check(moved == 8 and still == 18, "中间帧仅 R 层 8 块位移(转轴中心块不动),其余 18 块不动")
	await _save_shot(out_dir + "/shot_turn_mid.png")
	while cube.is_animating():
		await process_frame

	# ---- shot 3:play_alg("R U R' U'") 终帧 + facelets 逻辑断言 ----
	var moves_before: int = cube.moves  # 中间帧那步 enqueue_turn 是玩家步,moves==1
	var queued: int = cube.play_alg("R U R' U'")
	_check(queued == 4, "play_alg 入队 4 步")
	while cube.is_animating():
		await process_frame
	# 基线 cube 不入树(纯逻辑参照):一旦 add_child 会在同点位(原点)再渲染一副
	# 复原态魔方,与主魔方 26+26 cubie 共面 z-fighting/穿插,污染此后全部截图
	# (shot_alg_final/teach/timer/n4 出现白噪点、红描边、穿模三角与"不可达"色数)。
	var c2 = load("res://scripts/cube.gd").new()
	c2.setup(3)
	c2.apply_turn(Vector3.RIGHT, [2], -PI / 2)  # 复现中间帧那步,基线对齐
	c2.apply_turn(Vector3.RIGHT, [2], -PI / 2)
	c2.apply_turn(Vector3.UP, [2], -PI / 2)
	c2.apply_turn(Vector3.RIGHT, [2], PI / 2)
	c2.apply_turn(Vector3.UP, [2], PI / 2)
	var f1: PackedByteArray = cube.to_facelets()
	_check(f1 == c2.to_facelets(), "alg 终帧 facelets == 瞬时 apply 序列预期")
	_check(f1 != solved_seq, "alg 终帧非复原态")
	_check(cube.moves == moves_before, "play_alg 步数不计(moves 不变)")
	await _save_shot(out_dir + "/shot_alg_final.png")

	# ---- §8(v5.1 G6):MCP restore 全自动验收:socket 触发 → 轮询 state 至
	# queue_len==0 && !animating → 断言 facelets == 复原序;中间帧截图存档(不作验收门)。
	var solved_str := "UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB"
	var peer := StreamPeerTCP.new()
	_check(peer.connect_to_host("127.0.0.1", 18888) == OK, "§8 socket 连接游戏内 CubeServer")
	var frames := 0
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and frames <= 600:
		peer.poll()
		frames += 1
		await process_frame
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_sock_send(peer, {"id": 1, "cmd": "apply_alg", "alg": "R U F D L B"})
		var r1: Dictionary = await _sock_recv(peer, 600)
		_check(int(r1.get("id", -1)) == 1 and r1.get("ok") == true, "§8 apply_alg 打乱 ok")
		var scrambled := false
		for j in 600:  # 先等打乱播完:restore 是打断入口(§4),pending 会被清,须先达稳态
			_sock_send(peer, {"id": 50 + j, "cmd": "state"})
			var w: Dictionary = await _sock_recv(peer, 600)
			var wd: Dictionary = w.get("data", {})
			if wd.get("animating") == false and int(wd.get("queue_len", -1)) == 0:
				scrambled = String(wd.get("facelets", "")) != solved_str
				break
			await create_timer(0.1).timeout
		_check(scrambled, "§8 打乱已播完且 facelets 偏离复原序")
		_sock_send(peer, {"id": 2, "cmd": "restore"})
		var r2: Dictionary = await _sock_recv(peer, 600)
		_check(int(r2.get("id", -1)) == 2 and r2.get("ok") == true
				and int(r2.data.queued) >= 1, "§8 restore 触发 ok 且 queued>=1")
		var mid_saved := false
		var final := {}
		for i in 300:  # 轮询至 queue_len==0 且 !animating(上限 300 次 × 0.1s)
			_sock_send(peer, {"id": 1000 + i, "cmd": "state"})
			var st: Dictionary = await _sock_recv(peer, 600)
			var d: Dictionary = st.get("data", {})
			if d.is_empty():
				break
			if d.get("animating") == true and not mid_saved:
				await _save_shot(out_dir + "/shot_restore_mid.png")  # 存档,不作验收门
				mid_saved = true
			if d.get("animating") == false and int(d.get("queue_len", -1)) == 0:
				final = d
				break
			await create_timer(0.1).timeout
		_check(String(final.get("facelets", "")) == solved_str and final.get("solved") == true,
				"§8 restore 后 facelets == 复原序(轮询至 animating=false 且 queue_len==0)")
		peer.disconnect_from_host()
	else:
		_check(false, "§8 连接超时")

	# ---- §17.3/§18 增量三张:教学模式侧栏+高亮 / 计时布局 / N=4 冒烟 ----
	# shot_teach:D2 只动下两层,stage_check=5(1-5 绿、6 蓝当前),教学模式右侧栏高亮
	cube.apply_turn(Vector3.DOWN, [2], PI)
	main._set_mode(1)  # Mode.TEACH
	await _wait_frames(4)  # _process 跑一轮侧栏刷新
	var teach_visible: bool = main.get_node("UI/TeachPanel").visible
	_check(teach_visible, "§14.5 教学模式侧栏可见")
	await _save_shot(out_dir + "/shot_teach.png")
	main._set_mode(0)

	# shot_timer:中央大字计时(假钟 12.345s running)+ 右侧历史/AO 统计
	var tmp_times := "/tmp/godot_visual_times_%d/times.cfg" % int(Time.get_unix_time_from_system() * 1000.0)
	DirAccess.make_dir_recursive_absolute(tmp_times.get_base_dir())
	var cf := ConfigFile.new()
	cf.set_value("2026-09-24", "1000_0", 15230)
	cf.set_value("2026-09-24", "2000_1", 18410)
	cf.set_value("2026-09-24", "3000_2", 12870)
	cf.save(tmp_times)
	main._timer.store_path = tmp_times
	main._timer.clock = func() -> int: return 5000
	main._set_mode(2)  # Mode.TIMER
	cube.scramble()
	main._timer.enter_scrambled()
	main._timer.on_player_turn()  # 首操作起表(start=5000)
	main._timer.clock = func() -> int: return 17345  # elapsed = 12.345s
	main._refresh_timer_stats()
	await _wait_frames(4)
	_check(main.get_node("UI/TimeLabel").visible and main._timer.is_running(),
			"§15.3 计时模式大字可见且 running")
	await _save_shot(out_dir + "/shot_timer.png")
	main._set_mode(0)

	# shot_n4:N=4 冒烟(setup(4) 三面可见,不逐项验收;§17.3)
	main._on_size_selected(4)
	await _wait_frames(4)
	_check(cube.n == 4 and cube.cubies.size() == 56, "§17.3 N=4 setup(4) 冒烟(cubie 56)")
	await _save_shot(out_dir + "/shot_n4.png")
	main._on_size_selected(3)

	c2.free()
	main.free()
	if _fail:
		printerr("VISUAL TEST FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)
