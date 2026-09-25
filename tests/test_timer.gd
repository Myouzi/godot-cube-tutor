extends SceneTree
## 计时器自测(PLAN §18 P3 行 T-timer):状态机全转移、作废矩阵、UndoBtn 不起表、
## AO5/AO12 去头去尾纯函数、成绩 key 防撞。
## 运行:godot --headless -s tests/test_timer.gd;任何断言失败 exit 1,全过 exit 0。
## 计时钟注入假值;成绩存储重定向到 /tmp 唯一目录,不污染真实 user://times.cfg。

var _fake_now := 0  # 假计时钟毫秒值(lambda 经 self 实时读取)
var _t  # scripts/timer.gd 实例(无类型:动态访问脚本成员)
var _store_path := ""
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
	_store_path = "/tmp/godot_timer_test_%d/times.cfg" % int(Time.get_unix_time_from_system() * 1000.0)
	DirAccess.make_dir_recursive_absolute(_store_path.get_base_dir())
	_test_state_machine()
	_test_invalidate_matrix()
	_test_undo_no_start()
	_test_ao()
	_test_store_collision()
	await _test_ui_gates()
	print("ALL PASSED" if not _fail else "FAILED")
	quit(1 if _fail else 0)


func _new_timer() -> void:
	DirAccess.remove_absolute(_store_path)  # 每组测试独立空存储
	_t = load("res://scripts/timer.gd").new()
	_t.store_path = _store_path
	_t.clock = func() -> int: return _fake_now


func _today() -> String:
	return Time.get_date_string_from_system()


func _record_count() -> int:
	var all: Dictionary = _t.load_all()
	var c := 0
	for day in all:
		c += all[day].size()
	return c


## 状态机全转移:idle→scrambled→running→solved,以及各态下不该发生的转移。
func _test_state_machine() -> void:
	_new_timer()
	_check(_t.state == _t.State.IDLE, "SM 初始 idle")
	_t.on_player_turn()
	_check(_t.state == _t.State.IDLE and _t.elapsed_msec() == 0, "SM idle 转层不起表")
	_t.on_solved()
	_check(_t.state == _t.State.IDLE, "SM idle 下 on_solved 忽略")
	_t.enter_scrambled()
	_check(_t.state == _t.State.SCRAMBLED, "SM idle -> scrambled")
	_fake_now = 1000
	_t.on_undo()
	_check(_t.state == _t.State.SCRAMBLED and _t.elapsed_msec() == 0, "SM scrambled 下 undo 不起表")
	_fake_now = 2000
	_t.on_player_turn()
	_check(_t.state == _t.State.RUNNING, "SM scrambled 首次玩家转层 -> running")
	_fake_now = 3000
	_check(_t.elapsed_msec() == 1000, "SM running 实时读数(3000-2000=1000)")
	_t.on_player_turn()
	_check(_t.state == _t.State.RUNNING and _t.elapsed_msec() == 1000, "SM running 中转层不重置起表")
	_fake_now = 6500
	_t.on_solved()
	_check(_t.state == _t.State.SOLVED and _t.elapsed_msec() == 4500, "SM solved 停表冻结 4500")
	_check(_t.best(_t.load_all()[_today()]) == 4500, "SM 成绩入账 4500")
	_t.on_player_turn()
	_check(_t.state == _t.State.SOLVED, "SM solved 下转层不改变状态")
	_t.enter_scrambled()
	_check(_t.state == _t.State.SCRAMBLED, "SM solved -> 新轮 scrambled")
	_check(_t.elapsed_msec() == 0, "SM 新轮读数归零")


## 作废矩阵:计时中切模式/restore/reset/二次打乱 = 作废,不记成绩。
## restore/reset 的语义是 UI 在 cube.restore()/cube.reset() 之后调用 invalidate(),此处直测该方法。
func _test_invalidate_matrix() -> void:
	_new_timer()
	_t.enter_scrambled()
	_fake_now = 1000
	_t.on_player_turn()
	_fake_now = 4000
	_t.invalidate()  # 计时中切模式
	_check(_t.state == _t.State.IDLE and _t.elapsed_msec() == 0, "INV 计时中切模式 invalidate -> idle 归零")
	var n0 := _record_count()
	_t.on_solved()  # 作废后 is_solved 不入账
	_check(_record_count() == n0, "INV 作废后 on_solved 不入账")
	_t.enter_scrambled()  # restore/reset 后重回打乱态再起表
	_fake_now = 5000
	_t.on_player_turn()
	_fake_now = 8000
	_t.enter_scrambled()  # running 中二次打乱 = 作废 + 开新轮
	_check(_t.state == _t.State.SCRAMBLED and _t.elapsed_msec() == 0, "INV running 中二次打乱作废开新轮")
	_fake_now = 9000
	_t.on_solved()
	_check(_record_count() == n0, "INV 二次打乱作废的成绩不入账")
	_t.on_player_turn()
	_t.invalidate()
	_t.invalidate()
	_check(_t.state == _t.State.IDLE, "INV invalidate 幂等(restore/reset/切模式重复调用)")
	_t.enter_scrambled()
	_t.enter_scrambled()
	_check(_t.state == _t.State.SCRAMBLED, "INV scrambled 中再打乱仍 scrambled")


## UndoBtn 不起表:on_undo 不改状态;on_player_turn 只认转层(scrambled 才起表,其余态忽略)。
func _test_undo_no_start() -> void:
	_new_timer()
	_t.enter_scrambled()
	_fake_now = 1000
	_t.on_undo()
	_t.on_undo()
	_check(_t.state == _t.State.SCRAMBLED and _t.elapsed_msec() == 0, "UNDO scrambled 下连续 undo 不起表")
	_fake_now = 2000
	_t.on_player_turn()
	_fake_now = 3000
	_t.on_undo()
	_check(_t.state == _t.State.RUNNING and _t.elapsed_msec() == 1000, "UNDO running 中 undo 不打断计时")
	_t.on_solved()
	_fake_now = 4000
	_t.on_undo()
	_check(_t.state == _t.State.SOLVED and _t.elapsed_msec() == 1000, "UNDO solved 下 undo 不清成绩")


## AO5/AO12 纯函数:去最好最差取平均;不足条数 = -1;单次最佳。
func _test_ao() -> void:
	var t: GDScript = load("res://scripts/timer.gd")
	_check(absf(t.ao5([5, 1, 4, 2, 3]) - 3.0) < 1e-6, "AO5 [1..5] 去头去尾 = 3.0")
	_check(absf(t.ao5([1000, 700, 900, 800, 3000]) - 900.0) < 1e-6, "AO5 已知数据 (800+900+1000)/3 = 900")
	_check(t.ao5([1, 2, 3, 4]) == -1.0, "AO5 不足 5 条 = -1")
	var twelve := []
	for i in range(1, 13):
		twelve.append(i * 100)
	# 排序后 100..1200,去 100(最好)与 1200(最差),平均 200..1100 = 6500/10 = 650
	_check(absf(t.ao12(twelve) - 650.0) < 1e-6, "AO12 1..12 去头去尾 = 650")
	twelve.shuffle()
	_check(absf(t.ao12(twelve) - 650.0) < 1e-6, "AO12 与输入顺序无关")
	twelve.pop_front()
	_check(t.ao12(twelve) == -1.0, "AO12 不足 12 条 = -1")
	_check(absf(t.ao([10, 20], 5) + 1.0) < 1e-6 and absf(t.ao([], 5) + 1.0) < 1e-6, "AO 底层空/不足 = -1")
	_check(t.best([500, 300, 900]) == 300, "best 取最小")
	_check(t.best([]) == -1, "best 空表 = -1")


## 成绩 key 防撞:同毫秒连续多条成绩,靠自增序号区分,全部可读回。
func _test_store_collision() -> void:
	_new_timer()
	for expect in [[1000, 1000], [2500, 1500], [4000, 1500]]:
		_t.enter_scrambled()
		_fake_now = expect[0]
		_t.on_player_turn()
		_fake_now = expect[0] + expect[1]
		_t.on_solved()
	var day := _today()
	var all: Dictionary = _t.load_all()
	_check(all.has(day), "KEY 今日日期 section 存在")
	var arr: Array = all[day]
	_check(arr.size() == 3, "KEY 连续 3 条成绩都入账")
	_check(arr[0] == 1000 and arr[1] == 1500 and arr[2] == 1500, "KEY 值正确 1000/1500/1500")
	var cf := ConfigFile.new()
	cf.load(_store_path)
	var keys := cf.get_section_keys(day)
	_check(keys.size() == 3, "KEY 实际 key 数 3")
	var uniq := {}
	for k in keys:
		uniq[str(k)] = true
	_check(uniq.size() == 3, "KEY 无碰撞(同毫秒靠自增序号区分)")


## UI 接线(§18 T-timer):running 中 PlayBtn 禁用;"非 WCA 均匀打乱"提示路径。
## 实例化 main.tscn(headless 可跑,同 smoke_bridge);计时钟注入假值。
func _test_ui_gates() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame  # @onready 与 _ready 首帧才完成,提前访问 cube 为 Nil
	while not (main.cube is Node3D) or main.cube.get_child_count() == 0:
		await process_frame
	main._timer.clock = func() -> int: return 0
	main._set_mode(load("res://scripts/main.gd").Mode.TIMER)
	await process_frame
	_check(main.play_btn.disabled == false, "UI scrambled 态 PlayBtn 可用")
	main._timer.enter_scrambled()
	main._timer.on_player_turn()
	_check(main._timer.is_running(), "UI 计时进入 running")
	await process_frame
	await process_frame
	_check(main.play_btn.disabled == true, "UI running 中 PlayBtn 禁用(§15.1 竞速不播公式)")
	main._timer.invalidate()
	await process_frame
	_check(main.play_btn.disabled == false, "UI 作废后 PlayBtn 恢复可用")
	# A-4:计时模式打乱按钮优先 WCA 均匀序列(本机 kociemba 已装)→ 面板显示 WCA 序列;
	# "非 WCA 均匀打乱"降级提示改由 N≠3 分支覆盖(tests/test_scramble_ui.gd)。
	main._on_scramble()
	await process_frame
	_check(String(main.scramble_seq.text).begins_with("WCA 打乱序列"),
			"UI 计时模式打乱走 WCA 均匀序列(A-4,面板显示)")
	main._timer.invalidate()
	# A-4 计时模式专属降级分支(main.gd TIMER 段,此前失测):直接驱动统一入口,
	# 断言面板文本 + status 提示(新口径指 kociemba,不再指向 MCP cube_scramble_wca)
	main._on_scramble_entered("")
	_check(String(main.scramble_seq.text) == "(本次为随机步打乱,非 WCA 均匀打乱)",
			"UI 计时模式降级(服务端信号路径)面板不虚报步数")
	_check(String(main._msg).contains("非 WCA 均匀打乱") and not String(main._msg).contains("MCP"),
			"UI 计时模式降级 status 提示且无过时 MCP 引导(%s)" % main._msg)
	main._on_scramble_entered("", 25)  # 按钮降级路径(3 阶恒 25 步)带真实步数
	_check(String(main.scramble_seq.text) == "(本次为 25 步随机打乱,非 WCA 均匀打乱)",
			"UI 计时模式降级(按钮路径)面板显示真实步数")
	main._timer.invalidate()
	# MCP 命令路径贯穿计时状态机(§15.1):server 信号 → main → timer
	await process_frame  # CubeServer _autodiscover cube
	var server: Node = main.server
	server.dispatch({"id": 1, "cmd": "scramble_wca_apply", "alg": "R"})
	_check(main._timer.state == main._timer.State.SCRAMBLED,
			"UI MCP scramble_wca_apply → 计时进 scrambled(§15.1)")
	_check(String(main.scramble_seq.text).contains("R"), "UI WCA 打乱序列显示在计时面板(§15.2)")
	server.dispatch({"id": 2, "cmd": "restore"})
	_check(main._timer.state == main._timer.State.IDLE, "UI MCP restore → 计时作废(§15.1)")
	main._timer.invalidate()
	main.free()
