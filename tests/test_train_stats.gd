extends SceneTree
## A-5 播放速度 + A-8 训练每案例统计 自测:
## - A-5:cube.turn_time 属性默认/赋值/越界 clamp(纯属性断言,不起动画)+ 顶栏滑杆 UI 接线;
## - A-8:train_stats.gd 聚合(已知记录序列 → count/best/mean、case 互不串、持久化读回)
##   + 训练面板当前 case 统计显示(存储重定向临时目录,不污染 user://)。
## 运行:godot --headless -s tests/test_train_stats.gd;任何断言失败 exit 1,全过 exit 0。

var _path := ""
var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true  # 不中途 quit:_run 尾部统一判 exit——中途 quit(1) 会被尾部 quit(0) 覆盖(EXPERIENCE 假绿陷阱)


func _run() -> void:
	_path = "/tmp/godot_train_stats_test_%d/train_stats.cfg" % int(Time.get_unix_time_from_system() * 1000.0)
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	_test_speed_clamp()
	_test_stats_agg()
	await _test_ui()
	print("ALL PASSED" if not _fail else "FAILED")
	quit(1 if _fail else 0)


## A-5:turn_time 赋值即 clamp(0.05~0.90),默认 0.18。纯属性读写,不起动画。
func _test_speed_clamp() -> void:
	var cube = load("res://scripts/cube.gd").new()  # 不进场景树:属性 setter 纯数学
	_check(absf(cube.turn_time - 0.18) < 1e-6, "SPEED 默认 0.18")
	cube.turn_time = 0.5
	_check(absf(cube.turn_time - 0.5) < 1e-6, "SPEED 设 0.5 → 0.5")
	cube.turn_time = 0.01
	_check(absf(cube.turn_time - 0.05) < 1e-6, "SPEED 下越界 0.01 → clamp 0.05")
	cube.turn_time = 5.0
	_check(absf(cube.turn_time - 0.90) < 1e-6, "SPEED 上越界 5.0 → clamp 0.90")
	cube.turn_time = 0.05
	_check(absf(cube.turn_time - 0.05) < 1e-6, "SPEED 下界 0.05 原样接受")
	cube.turn_time = 0.90
	_check(absf(cube.turn_time - 0.90) < 1e-6, "SPEED 上界 0.90 原样接受")
	cube.free()


## A-8:聚合逻辑(存储重定向临时目录):已知序列 → count/best/mean;跨分类同名防串;持久化。
func _test_stats_agg() -> void:
	DirAccess.remove_absolute(_path)  # 独立空存储
	var ts = load("res://scripts/train_stats.gd").new()
	ts.store_path = _path
	var s: Dictionary = ts.stats("f2l/1")
	_check(int(s.count) == 0 and int(s.best_ms) == -1 and float(s.mean_ms) == -1.0,
			"STAT 空记录 count=0 best=-1 mean=-1")
	for ms in [1000, 2000, 3000, 4000]:
		ts.record("f2l/1", ms)
	s = ts.stats("f2l/1")
	_check(int(s.count) == 4, "STAT 4 条记录 count=4")
	_check(int(s.best_ms) == 1000, "STAT best=1000")
	_check(absf(float(s.mean_ms) - 2500.0) < 1e-6, "STAT mean=(1000+2000+3000+4000)/4=2500")
	ts.record("f2l/1", 500)
	s = ts.stats("f2l/1")
	_check(int(s.count) == 5 and int(s.best_ms) == 500 and absf(float(s.mean_ms) - 2100.0) < 1e-6,
			"STAT 追加 500 → count=5 best=500 mean=2100")
	ts.record("oll/1", 9999)
	_check(int(ts.stats("f2l/1").count) == 5 and int(ts.stats("oll/1").count) == 1,
			"STAT 跨分类同名 case(f2l/1 与 oll/1)互不串")
	_check(int(ts.stats("pll/9").count) == 0, "STAT 未记录 case 空聚合")
	var ts2 = load("res://scripts/train_stats.gd").new()
	ts2.store_path = _path
	var s2: Dictionary = ts2.stats("f2l/1")
	_check(int(s2.count) == 5 and int(s2.best_ms) == 500, "STAT 持久化:新实例同路径读回一致")
	# 同毫秒 key 防撞(同 timer.gd 口径):假钟钉死同一毫秒,连续 record 依自增序号区分
	DirAccess.remove_absolute(_path)  # 独立空存储
	var ts3 = load("res://scripts/train_stats.gd").new()
	ts3.store_path = _path
	ts3.clock = func() -> int: return 1700000000000  # 假钟:强制 10 条全部落在同一毫秒
	for i in 10:
		ts3.record("f2l/1", 100 + i)
	var cf := ConfigFile.new()
	cf.load(_path)
	var ks := cf.get_section_keys("f2l/1")
	var uniq := {}
	for k in ks:
		uniq[str(k)] = true
	_check(int(ts3.stats("f2l/1").count) == 10, "KEY 假钟同毫秒 10 条 record 全部入账")
	_check(ks.size() == 10 and uniq.size() == 10, "KEY 同毫秒无碰撞(自增序号区分)")
	ks.sort()
	_check(String(ks[0]).ends_with("_0") and String(ks[9]).ends_with("_9"),
			"KEY 序号 0..9 依序递增")


## UI 接线:滑杆即时生效 + 训练面板统计显示(main.tscn headless,同 test_timer 模式)。
func _test_ui() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame  # @onready 与 _ready 首帧才完成,提前访问 cube 为 Nil
	while not (main.cube is Node3D) or main.cube.get_child_count() == 0:
		await process_frame
	# A-5:滑杆初值与引擎一致;量程/步长与 cube clamp(0.05~0.90)锁定(防两处单方面漂移);
	# 拖动即时写入引擎(值显示同步)
	_check(absf(main.speed_slider.value - main.cube.turn_time) < 1e-6, "UI 滑杆初值 = 引擎 turn_time")
	_check(absf(main.speed_slider.min_value - 0.05) < 1e-6
			and absf(main.speed_slider.max_value - 0.90) < 1e-6
			and absf(main.speed_slider.step - 0.01) < 1e-6,
			"UI 滑杆量程/步长 = 引擎 clamp 边界(0.05~0.90,step 0.01)")
	main.speed_slider.value = 0.62
	_check(absf(main.cube.turn_time - 0.62) < 1e-6, "UI 滑杆拖动 → cube.turn_time 即时生效")
	_check(String(main.speed_label.text).contains("0.62"),
			"UI 滑杆值显示同步(%s)" % main.speed_label.text)
	# A-8:存储重定向临时目录后走真实出题路径
	main._train_stats.store_path = _path
	DirAccess.remove_absolute(_path)
	main._set_mode(load("res://scripts/main.gd").Mode.TRAIN)
	main._on_train_new()
	_check(not main._train_case.is_empty(), "UI 训练出题成功(cfop.json 已载入)")
	_check(String(main.train_stat_label.text).contains("首次"),
			"UI 出题显示首次挑战(%s)" % main.train_stat_label.text)
	# 入账显示接线(手动 record + 刷新,只验显示;真实完成边沿的端到端见下方 E2E)
	var id: String = main._train_case_id()
	main._train_stats.record(id, 1234)
	main._update_train_stat()
	_check(String(main.train_stat_label.text).contains("1 次")
			and String(main.train_stat_label.text).contains("1.23"),
			"UI 入账后显示 1 次 · best 1.23s(%s)" % main.train_stat_label.text)
	# E2E(A-8 核心行为「训练完成 → 自动入账」):先复位(case 逆向构造以复原态为基准,
	# 同玩家完成上一 case 后再出题的自然流程)→ 出题 → _process 记下未复原基线
	# (_was_solved=false)→ 正序 apply_turn 瞬时复原(出题 = 逆序逆角构造,不起动画)
	# → 等 2 帧,main._process 的 is_solved 上升沿自动 record(不经任何手动 record 调用)。
	main._on_reset()
	main._on_train_new()
	_check(not main._train_case.is_empty(), "E2E 再次出题成功")
	var id2: String = main._train_case_id()
	var before: int = int(main._train_stats.stats(id2).count)
	await process_frame  # _process 把 _was_solved 置 false(未复原基线)
	var steps: Array = main._cfop_steps(String(main._train_case.algs[0]))
	for s in steps:
		main.cube.apply_turn(s.axis, s.layers, s.angle)
	for i in 60:  # 轮询而非固定 2 帧:CI 慢 runner 上 _process 边沿可能迟到(首跑 flaky 实证)
		if main._train_done:
			break
		await process_frame
	_check(main._train_done == true, "E2E 完成边沿已触发(_train_done=true)")
	_check(int(main._train_stats.stats(id2).count) == before + 1,
			"E2E 完成自动入账(count %d→%d,未经手动 record)" % [before, before + 1])
	_check(String(main.train_result_label.text).contains("完成"),
			"E2E 结果标签更新(%s)" % main.train_result_label.text)
	# 污染防护①(终审):出题后切分类按钮,完成仍须记到出题分类(key 冻结于出题时,
	# _set_train_cat 不清当前 case)
	main._on_reset()
	main._on_train_new()
	_check(not main._train_case.is_empty(), "防护①出题成功")
	var id_frozen: String = main._train_case_id()
	_check(id_frozen.begins_with("f2l/"), "出题 key 冻结于出题分类(%s)" % id_frozen)
	_check(not ".0" in id_frozen, "数字 case 名整型化(key 无 '.0' 形态,%s)" % id_frozen)
	main._set_train_cat("oll")
	_check(main._train_case_id() == id_frozen, "切分类后统计 key 不变(仍指出题分类)")
	await process_frame  # 记未复原基线(_was_solved=false)
	var steps2: Array = main._cfop_steps(String(main._train_case.algs[0]))
	for s in steps2:  # 正序 apply_turn 瞬时复原(玩家语义计步,moves>0)
		main.cube.apply_turn(s.axis, s.layers, s.angle)
	for i in 60:  # 轮询等边沿(同 E2E:CI 慢 runner 固定帧数不可靠)
		if main._train_done:
			break
		await process_frame
	_check(int(main._train_stats.stats(id_frozen).count) == 1,
			"切分类后完成记到出题分类(%s)" % id_frozen)
	_check(int(main._train_stats.stats("oll/%s" % main._case_name(main._train_case)).count) == 0,
			"未出题的 oll 同名 case 零入账(不串账)")
	# 污染防护②(终审):出题后纯 MCP 路径(reset)造成的复原跳变不入账——
	# 完成入账要求 cube.moves>0(出题后有玩家净操作;ALG/REPLAY 不计步,scramble/reset 恒 0)
	main._on_reset()
	main._on_train_new()
	var id3: String = main._train_case_id()
	var before3: int = int(main._train_stats.stats(id3).count)
	main.server.cube = main.cube  # dispatch 直测,不等 _autodiscover(同 test_scramble_ui)
	main.server.dispatch({"id": 0, "cmd": "reset"})
	for i in 10:  # 否定性断言:给 _process 足够(但有限)帧窗去「错误地」入账,窗口过小会假绿
		await process_frame
	_check(main.cube.is_solved(), "防护②MCP reset 后已复原(场景成立)")
	_check(int(main._train_stats.stats(id3).count) == before3,
			"MCP reset 造成的复原跳变不入账(净玩家步 0,不产伪成绩)")
	_check(main._train_done == false, "伪完成不置 _train_done(后续真完成仍可入账)")
	main.free()
