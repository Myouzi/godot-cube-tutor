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

	# ---- B1.1 全阶冒烟(2/5/6/7;4 已有 shot_n4):重建稳后断言 cubie 数/复原序/is_solved ----
	var n_cubies := {2: 8, 5: 98, 6: 152, 7: 218}  # n³−(n−2)³ 外露块数
	for nn in [2, 5, 6, 7]:
		main._on_size_selected(nn)
		await _wait_frames(4)  # 重建稳(既有 shot_n4 同口径)
		var cells: int = nn * nn
		var seq := PackedByteArray()
		seq.resize(6 * cells)
		for i in 6 * cells:
			seq[i] = i / cells  # 复原序:面 fi 全为 fi(既有 54 字节写法泛化)
		_check(cube.n == nn and cube.cubies.size() == int(n_cubies[nn]),
				"B1.1 N=%d 冒烟(cubie %d)" % [nn, n_cubies[nn]])
		_check(cube.to_facelets() == seq, "B1.1 N=%d facelets == 复原序(6n²=%d 字节)" % [nn, 6 * cells])
		_check(cube.is_solved(), "B1.1 N=%d is_solved" % nn)
		await _save_shot(out_dir + "/shot_n%d.png" % nn)

	# ---- B1.2 教学侧栏按阶重建:n=2 三段 / n=4 九段(最长列表,兼验 ScrollContainer) ----
	main._on_size_selected(2)
	main._set_mode(1)  # Mode.TEACH
	await _wait_frames(4)  # _process 刷一轮侧栏(既有 shot_teach 口径)
	_check(main._teach_stage_labels.size() == 3, "B1.2 N=2 教学侧栏重建 3 段")
	_check(main.get_node("UI/TeachPanel").visible, "B1.2 N=2 TeachPanel 可见")
	await _save_shot(out_dir + "/shot_teach_n2.png")
	main._set_mode(0)
	main._on_size_selected(4)
	main._set_mode(1)
	await _wait_frames(4)
	_check(main._teach_stage_labels.size() == 9, "B1.2 N=4 教学侧栏重建 9 段(最长列表)")
	await _save_shot(out_dir + "/shot_teach_n4.png")
	main._set_mode(0)

	# ---- B1.3 4 阶宽转中间帧(R 向 [1,3] 两层)----
	# 期望 28/28(非 32/24):x=1 层 16 槽位中 (1,±1,±1) 4 块为纯内部块,setup 跳过不
	# 建节点(cube.gd:82-83,4³−2³=56 可见块),故 x=1 层可见 12 + x=3 层 16 = 28 动。
	# 探针实测:全动画期 moved 恒 28(非时序敏感值),播完 bake 归位 moved=0。
	# 时序口径:插桩实测重场景+截图回读后单帧可达 ~0.99s,tween 一帧跨完 0.18s 全程并
	# bake 归位,固定真实窗定点采样必落空(moved=0;仅 time_scale=0.1 抬门槛不够——B1.4
	# 段前回读两慢帧内 tween 已推进 2×0.099s≥0.18s 播完,定点采样仍落空)。根治:段内
	# time_scale=0.1 压 tween 有效 delta(慢帧 step≈0.099s,首恢复点即 ~55% 进度)+
	# 逐帧扫描捕获 moved 首达期望值的动画中间帧(全动画期 moved 恒 28/12,渐进段不误采);
	# 播完仍捕获不到(极端 >1.8s/帧)则如实 FAIL。段末恢复 1.0。
	Engine.time_scale = 0.1
	cube.enqueue_turn(Vector3.RIGHT, [1, 3], -PI / 2)
	var moved4 := 0
	var still4 := 0
	for _scan4 in 400:  # 有界轮询(EXPERIENCE 长轮询口径;缩放后动画 1.8s 真实,400 帧富余)
		await process_frame
		moved4 = 0
		still4 = 0
		for c in cube.cubies:
			var expected4: Vector3 = Vector3(c.grid_pos) * 0.5
			if c.global_position.distance_to(expected4) > 0.02:
				moved4 += 1
			else:
				still4 += 1
		if moved4 == 28 or not cube.is_animating():
			break
	_check(moved4 == 28 and still4 == 28, "B1.3 4 阶宽转中间帧两层 28 块位移,其余 28 块不动(实测 moved=%d still=%d)" % [moved4, still4])
	Engine.time_scale = 1.0  # 段末恢复,播完等待/后续段落回正常时序
	await _save_shot(out_dir + "/shot_turn_mid_n4.png")
	while cube.is_animating():
		await process_frame

	# ---- B1.4 4 阶内层中间帧(单内层 [1],即 3R 口径)----
	# 期望 12/44(非 16/40):同 B1.3,内层 4 个 (±1,±1,±1) 槽位是纯内部块,可见 12 块。
	# 时序口径同 B1.3(time_scale=0.1 + 逐帧扫描捕获 moved==12,段末恢复)。
	Engine.time_scale = 0.1
	cube.enqueue_turn(Vector3.RIGHT, [1], -PI / 2)
	var movedi := 0
	var stilli := 0
	for _scani in 400:  # 有界轮询(同 B1.3 口径)
		await process_frame
		movedi = 0
		stilli = 0
		for c in cube.cubies:
			var expectedi: Vector3 = Vector3(c.grid_pos) * 0.5
			if c.global_position.distance_to(expectedi) > 0.02:
				movedi += 1
			else:
				stilli += 1
		if movedi == 12 or not cube.is_animating():
			break
	_check(movedi == 12 and stilli == 44, "B1.4 4 阶内层中间帧 12 块位移,其余 44 块不动(实测 moved=%d still=%d)" % [movedi, stilli])
	Engine.time_scale = 1.0
	await _save_shot(out_dir + "/shot_inner_mid_n4.png")
	while cube.is_animating():
		await process_frame

	# ---- B1.5 hint 降级持久显示(4 阶)。任务预设「scramble(20) 停中心段必走降级」实测
	# 不成立:0/90 随机态(裸打乱 70 + 循 1000-3029 跟随建议)hint 均出建议——中心段死锁
	# 已被 _remap_x2 共轭修复覆盖,_center_segment 不再穷尽。实测可达降级 = 组棱段卡点
	# (nxn_solver.gd:1660 _edge_hint 穷尽返回 error):seed 4002 打乱后逐步执行引擎建议,
	# 13 步确定性卡点(两次预跑复核)。断言 ⚠ 持久显示口径 main.gd:747。
	cube.reset()
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 4002
	cube.scramble(20, rng_b)  # 瞬时 bake 无动画;保守等稳(ask 口径)
	while cube.is_animating():
		await process_frame
	var deg := false
	for step5 in 40:
		var h5: Dictionary = main._teach_hint()
		if not String(h5.get("error", "")).is_empty():
			deg = true
			break
		var sug5: Dictionary = h5.get("suggestion", {})
		if sug5.is_empty():
			break
		for st5 in cube.parse_alg(String(sug5.get("alg", ""))):
			cube.apply_turn(st5.axis, st5.layers, st5.angle)
	_check(deg, "B1.5 4 阶跟随建议至组棱卡点,hint 降级返回非空 error")
	main._set_mode(1)
	await _wait_frames(4)  # _process 刷新 → HintLabel 持久显示降级原因
	_check(String(main.teach_hint.text).contains("⚠"), "B1.5 HintLabel 持久显示 ⚠ 降级原因")
	await _save_shot(out_dir + "/shot_hint_degrade.png")
	main._set_mode(0)

	# ---- B1.5b 中心段降级样本(N=5,补拍 2026-10-04)。机制:5-7 阶 solve 降级是
	# guard 预算口径(_cn_solve 12 段上限,段生成器不穷尽),hint 单段建议因此深走
	# 不降级;但 N=5 seed 20261009 跟随建议 19 步确定性撞到 _cn_segment 穷尽
	# (「中心段模板池未覆盖(降级): 卡点态 …」,探针预跑复核)。N=6/7 走 80 步不降级。
	main._on_size_selected(5)
	await _wait_frames(4)
	var rng6 := RandomNumberGenerator.new()
	rng6.seed = 20261009
	cube.scramble(20, rng6)
	while cube.is_animating():
		await process_frame
	var deg_c := false
	for step6 in 80:
		var h6: Dictionary = main._teach_hint()
		if not String(h6.get("error", "")).is_empty():
			deg_c = true
			_check(String(h6.error).contains("中心段"),
					"B1.5b 中心段降级 error 含「中心段」标记 实际=%s" % String(h6.error).substr(0, 48))
			break
		var sug6: Dictionary = h6.get("suggestion", {})
		if sug6.is_empty() or String(sug6.get("alg", "")).is_empty():
			break
		for st6 in cube.parse_alg(String(sug6.alg)):
			cube.apply_turn(st6.axis, st6.layers, st6.angle)
	_check(deg_c, "B1.5b N=5 seed 20261009 跟随建议至中心段卡点,hint 降级非空 error")
	main._set_mode(1)
	await _wait_frames(4)  # _process 刷新 → HintLabel 持久显示中心段降级原因
	_check(String(main.teach_hint.text).contains("⚠"), "B1.5b HintLabel 持久显示 ⚠ 中心段降级")
	await _save_shot(out_dir + "/shot_hint_degrade_center.png")
	main._set_mode(0)

	main._on_size_selected(3)

	c2.free()
	main.free()
	if _fail:
		printerr("VISUAL TEST FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)
