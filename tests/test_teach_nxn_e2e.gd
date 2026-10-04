extends SceneTree
## v7 P8:4 阶教学全流程 UI E2E(docs/v7-teach-nxn-plan.md P8 验收条款,Q5):
## 选阶(4 阶)→ 打乱 → 教学 hint/演示/自动完成至复原,全程真实 UI 管线
## (main.tscn + main.gd 教学按钮路径,headless 无截图)。
## 打乱构造(P8 parity 构造法 + 固定种子):OLL parity 修正公式作用于复原 4 阶
## (瞬时 apply_turn 夹具)+ 固定种子 4 步外层轻打乱(play_alg UI 动画管线)。
## 不用打乱按钮 scramble(40) 的实测依据:50 个固定种子中 ok 且含 parity 的态
## 解长 254-337 步(动画 46-61s 爆 CI 预算),无 <250 步者;构造法使「态含 parity」
## 由判据断言自证,达成 P8 意图(防固定种子恰好避开 parity 使缺陷漏网)。
## 等待纪律:一律「队列/动画清零 + 2 连稳」长轮询(范式 visual_test.gd:147,
## 300 次 × 0.1s 上限),严禁 60 帧边沿口径(EXPERIENCE.md:18;4 阶自动完成
## 数十步 × 0.18s ≈ 10-20s)。双校验:exit 0 且无 SCRIPT ERROR。

const NS := preload("res://scripts/nxn_solver.gd")

var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true


## 长轮询至稳定态:队列/动画清零、非程序化批次、无挂起演示续播、自动完成已收段
## (_auto_stage == 0),且该状态连续 2 次轮询保持——auto 运行中 _process 会在
## 队列清零当帧接单下一条建议,单次「清零」不构成稳定,须连稳确认(上限 300 × 0.1s)。
func _wait_settled(main: Node) -> bool:
	var stable := 0
	for i in 300:
		var cube: Node3D = main.cube
		if not cube.is_animating() and int(cube._queue.size()) == 0 \
				and not cube.is_programmatic() \
				and String(main._demo_pending).is_empty() and int(main._auto_stage) == 0:
			stable += 1
			if stable >= 2:
				return true
		else:
			stable = 0
		await create_timer(0.1).timeout
	return false


func _run() -> void:
	print("RUN-START")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("CubeServer").port = 18999  # 避让开发机常驻实例的 8788(同 visual_test)
	root.add_child(main)
	await process_frame
	while not (main.cube is Node3D) or main.cube.get_child_count() == 0:
		await process_frame
	var cube: Node3D = main.cube
	var t0 := Time.get_ticks_msec()

	# ---- 1) 选阶 → 教学模式 ----
	main._on_size_selected(4)
	await _wait_settled(main)
	_check(cube.n == 4 and cube.cubies.size() == 56, "选阶 4 阶:setup(4) 完成(cubie 56)")
	# v7 测试设计 A2:模式门禁(main.gd _refresh,TIMER/TRAIN 限 3 阶;Mode 枚举
	# FREE/TEACH/TIMER/TRAIN = 0/1/2/3)——F4 类缺口:此前零断言
	_check(main.mode_btns[2].disabled and main.mode_btns[3].disabled,
			"模式门禁:4 阶计时/训练按钮禁用")
	_check(not main.mode_btns[0].disabled and not main.mode_btns[1].disabled,
			"模式门禁:4 阶自由/教学按钮可用")
	# 全程 187 步动画(打乱+演示+自动完成),0.18s/步 ≈ 34s 爆预算;走速度滑杆
	# 真实 UI 入口调至最小档 0.05(main.tscn:122)——动画节奏非本测试验收点
	main._on_speed_changed(0.05)
	main._set_mode(1)  # Mode.TEACH
	await _wait_settled(main)
	_check(main.get_node("UI/TeachPanel").visible, "教学模式侧栏可见")
	_check(int(main._teach_stage_labels.size()) == 9, "9 段阶段标签动态重建(P6 引擎表长)")

	# ---- 2) 打乱:OLL parity 构造(瞬时夹具)+ 固定种子 4 步外层轻打乱(UI 动画) ----
	var oll: String = String(NS.PARITY_ALGS[4].oll)
	_cube_apply_alg(cube, oll)  # 复原态 → 单棱翻 parity 态(中心+棱组保持)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261004
	var shuffle_toks: Array = []
	var prev := ""
	for i in 4:
		var face: String = ["U", "D", "R", "L", "F", "B"][rng.randi() % 6]
		if face == prev:
			face = "F" if face != "F" else "R"  # 避同面连续(与 scramble 同款过滤,简化口径)
		prev = face
		shuffle_toks.append(face + ["", "'", "2"][rng.randi() % 3])
	var queued: int = cube.play_alg(" ".join(PackedStringArray(shuffle_toks)))
	await _wait_settled(main)
	var fp: PackedByteArray = cube.to_facelets()
	var par: Dictionary = NS._parity_of(NS._reduce_to_54(fp, 4))
	_check(queued == 4 and fp.size() == 96 and (bool(par.oll) or bool(par.pll)),
		"打乱完成:play_alg 入队 4 步、96 字节、态含 parity(oll=%s pll=%s,判据自证)"
			% [par.oll, par.pll])
	_check(int(NS.stage_check(fp)) == 1, "打乱态 stage_check = 1(中心+棱组保持,parity 段未清)")

	# ---- 3) 教学 hint 路径:侧栏建议 = parity 修正段 ----
	var h: Dictionary = main._teach_hint()
	var sug: Dictionary = h.get("suggestion", {})
	_check(String(sug.get("piece", "")) == "parity" and String(sug.get("alg", "")) == oll,
		"教学 hint 建议为 parity 修正段(alg 与 PARITY_ALGS[4].oll 一致)")
	await process_frame  # _process 跑一轮 _teach_refresh 刷侧栏文案
	_check(String(main.teach_hint.text).contains("parity"),
		"侧栏 HintLabel 持久显示 parity 建议")

	# ---- 4) 演示下一步:播放 parity 修正(UI 演示管线)→ 判据双清 ----
	main._on_teach_demo()
	_check(cube.is_animating(), "演示已入队播放")
	var settled: bool = await _wait_settled(main)
	var par2: Dictionary = NS._parity_of(NS._reduce_to_54(cube.to_facelets(), 4))
	_check(settled and not bool(par2.oll) and not bool(par2.pll),
		"演示播放完成后 parity 双判据清(oll=pll=false)")
	_check(int(NS.stage_check(cube.to_facelets())) == 2, "parity 清后 stage 进入 3 阶段(2)")

	# ---- 5) 自动完成至复原:循环「自动完成本阶段」按钮(UI 自动管线) ----
	var seg_rounds := 0
	var ok_auto := true
	while int(NS.stage_check(cube.to_facelets())) < 9:
		seg_rounds += 1
		if seg_rounds > 12:  # 9 段 + 余量:卡死 = auto 中止,报错 fail loud
			ok_auto = false
			printerr("  自动完成超 12 轮未复原(hint=%s)" % str(main._teach_hint()))
			break
		main._on_teach_auto()  # _auto_stage 置位,_process 逐建议驱动
		settled = await _wait_settled(main)
		if not settled:
			ok_auto = false
			printerr("  第 %d 轮自动完成 30s 未收敛(hint=%s)" % [seg_rounds, str(main._teach_hint())])
			break
	var ok_final: bool = ok_auto and cube.is_solved() \
			and int(NS.stage_check(cube.to_facelets())) == 9
	_check(ok_final, "自动完成至复原:is_solved 且 stage_check = 9(%d 轮收段,%.1fs)"
			% [seg_rounds, (Time.get_ticks_msec() - t0) / 1000.0])
	await process_frame
	_check(String(main.teach_hint.text).contains("已复原"),
		"复原后侧栏显示完成文案")

	# A2 收尾:切回 3 阶门禁恢复(setup(3) 重置魔方,不影响已过断言)
	main._on_size_selected(3)
	await _wait_settled(main)
	_check(not main.mode_btns[2].disabled and not main.mode_btns[3].disabled,
			"模式门禁:切回 3 阶计时/训练恢复可用")

	print("test_teach_nxn_e2e %s(总耗时 %.1fs)" % ["ALL PASSED" if not _fail else "FAILED",
			(Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if _fail else 0)


## 瞬时构造夹具:parse_alg → 逐步 apply_turn(不经动画;数学路径同金标准测试)。
func _cube_apply_alg(cube: Node3D, alg: String) -> void:
	for s in cube.parse_alg(alg):
		cube.apply_turn(s.axis, s.layers, s.angle)
