extends SceneTree
## A-4 UI 打乱路径自测:主场景打乱按钮 → 3 阶优先 WCA 均匀序列(经 scramble_wca_apply
## 打乱标记入口,与 MCP cube_scramble_wca 同语义)/ N≠3 降级随机步 + 如实提示(先玩后
## 打乱时为本次差值步数)/ MCP scramble 命令(服务端信号路径)降级文案步数不虚报。
## 运行:godot --headless -s tests/test_scramble_ui.gd;任何断言失败 exit 1,全过 exit 0。
## WCA 生成依赖 python3 + kociemba(tools/wca_scramble.py,桥同源逻辑);本机已装,全测。

var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true


func _run() -> void:
	print("RUN-START")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame  # @onready 与 _ready 首帧才完成(同 test_timer)
	while not (main.cube is Node3D) or main.cube.get_child_count() == 0:
		await process_frame
	var cube: Node3D = main.cube
	var server: Node = main.server
	server.cube = cube  # 按钮路径首帧即用 dispatch,不等 _autodiscover 帧推进
	# 1. 3 阶:按钮打乱 → WCA 均匀序列代执行(与 MCP 同路径:标记 + 入队 + 信号反馈)
	main._on_scramble()
	_check(String(server.wca_scramble_alg) != "", "3 阶按钮打乱走 WCA 代执行(wca_scramble_alg 已标记)")
	var wca: String = String(server.wca_scramble_alg)
	_check(server.validate_alg(wca) == "", "WCA 打乱序列全部合法记号")
	_check(int(cube._queue.size()) == wca.split(" ", false).size(),
			"WCA 序列已入队且步数一致(%d 步)" % int(cube._queue.size()))
	_check(String(main._msg).contains("WCA"), "信号反馈已触发(%s)" % main._msg)
	# 2. N≠3:降级随机步(瞬时 bake 不入队)+ 如实提示;降级 = WCA 标记作废
	#    (与 dispatch "scramble" 清理语义一致,cube_server.gd:91——残留会让 state 查询名实不符)
	#    先玩 5 步再打乱:提示必须是本次打乱的 40 步(差值)而非 full_log 累计 45——
	#    锁定步数实现,回归回旧写法 cube.full_log.size() 即红
	cube.setup(4)
	for i in 5:  # 制造玩家历史(full_log 起点非 0,apply_turn 瞬时 bake 各记 1 步)
		cube.apply_turn(Vector3.UP, [cube.E], PI / 2)
	main._on_scramble()
	_check(String(server.wca_scramble_alg) == "", "4 阶降级随机步 = WCA 标记作废(同 MCP scramble 语义)")
	_check(int(cube.full_log.size()) == 45, "先玩 5 步再打乱:full_log=45(5 玩家步 + 40 打乱步)")
	_check(int(cube._queue.size()) == 0, "随机步为瞬时 bake,不入动画队列")
	_check(String(main._msg).contains("40 步随机打乱") and String(main._msg).contains("非 WCA"),
			"降级提示本次打乱步数(40)而非累计路径(45)(%s)" % main._msg)
	# 3. MCP scramble 命令(服务端信号路径,main 经 scramble_entered("",-1) 到达):
	#    自由模式降级文案省略步数(服务端未知,宁缺勿虚报),与按钮路径(带差值数字)区分
	server.dispatch({"id": 0, "cmd": "scramble", "steps": 5})
	_check(String(main._msg).begins_with("已打乱(随机步打乱"),
			"服务端信号路径降级文案无步数(%s)" % main._msg)
	print("test_scramble_ui %s" % ("ALL PASSED" if not _fail else "FAILED"))
	quit(1 if _fail else 0)
