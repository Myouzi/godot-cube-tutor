extends SceneTree
## cube_server.gd 服务侧自测(PLAN §6.2 P2/P3 增量):solve/hint 结构、N=4 拒绝、
## WCA 打乱标记入口 scramble_wca_apply、socket 冒烟(§18 T-MCP)。
## 运行:godot --headless -s tests/test_server.gd;任何断言失败 exit 1,全过 exit 0。
## 分发器直测(不起 socket)为主,socket 仅一条冒烟;核心数学由 self_test.gd 覆盖。

var _cube: Node3D
var _server: Node
var _fail := false

## lbl_solver.gd 由并行工程师交付(P2);缺失时 solve/hint 走 SKIP 路径,
## 文件就绪后本测试自动变全测(联调由整合阶段兜底)。
const NOT_READY := "lbl_solver not ready"


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true  # 不中途 quit:_run 尾部统一判 exit——中途 quit(1) 会被尾部 quit(0) 覆盖(EXPERIENCE 假绿陷阱)


## solve/hint 断言条件化:引擎未就绪(ok:false + error 含 NOT_READY)→ 打 SKIP 继续返回 true。
func _maybe_skip(r: Dictionary, tag: String) -> bool:
	if r.ok:
		return false
	var err := String(r.get("error", ""))
	if err.contains(NOT_READY):
		print("SKIP  %s 引擎未就绪: %s" % [tag, err])
		return true
	return false  # 其余失败交由调用方 _check 报 FAIL


func _dispatch(cmd: String, extra := {}) -> Dictionary:
	var req := {"id": 1, "cmd": cmd}
	for k in extra:
		req[k] = extra[k]
	return _server.dispatch(req)


func _run() -> void:
	var cube_script: GDScript = load("res://scripts/cube.gd")
	_cube = cube_script.new()
	root.add_child(_cube)
	while _cube.get_child_count() == 0:  # 等首帧 setup(3) 完成(同 self_test)
		await process_frame
	_server = load("res://scripts/cube_server.gd").new()
	_server.cube = _cube
	_test_not_ready_path()
	_test_solve_structure()
	_test_hint_structure()
	_test_n4_reject()
	_test_wca_marker()
	_test_validation()
	_test_seed_validation()
	_test_timer_signals()
	await _test_socket()
	print("ALL PASSED" if not _fail else "FAILED")
	quit(1 if _fail else 0)


## S0:引擎缺失路径(文件就绪后此测试自动退化为一句 PASS):ok:false 且 error 含标记串。
func _test_not_ready_path() -> void:
	if ResourceLoader.exists("res://scripts/lbl_solver.gd"):
		print("PASS  S0 lbl_solver.gd 已就绪,走全测路径")
		return
	_cube.setup(3)
	var r := _dispatch("solve")
	_check(r.ok == false, "S0 引擎缺失 solve ok:false")
	_check(String(r.get("error", "")).contains(NOT_READY), "S0 solve error 含 lbl_solver not ready")
	var r2 := _dispatch("hint")
	_check(r2.ok == false and String(r2.get("error", "")).contains(NOT_READY),
			"S0 hint 同样 ok:false + not ready")


## S1:solve 返回结构:alg 非空 + stages 恰 7 段,每段 {name, alg}(§6.2)。
func _test_solve_structure() -> void:
	_cube.setup(3)
	seed(20260924)
	_cube.scramble(15)
	var r := _dispatch("solve")
	if _maybe_skip(r, "S1"):
		return
	_check(r.ok == true, "S1 solve ok=true")
	_check(r.data.has("alg") and r.data.alg is String and not (r.data.alg as String).is_empty(),
			"S1 solve.alg 非空字符串")
	_check(r.data.stages is Array and r.data.stages.size() == 7, "S1 solve.stages 恰 7 段")
	var ok_shape := true
	for st in r.data.stages:
		if not (st is Dictionary and st.has("name") and st.name is String
				and st.has("alg") and st.alg is String):
			ok_shape = false
	_check(ok_shape, "S1 每段结构 {name:String, alg:String}")
	_check(not _cube.is_animating(), "S1 solve 纯计算不入队(不执行)")


## S2:hint 返回结构:{stage, progress, suggestion:{piece, alg, text}}(§6.2/§14.5)。
func _test_hint_structure() -> void:
	_cube.setup(3)
	seed(42)
	_cube.scramble(20)
	var r := _dispatch("hint")
	if _maybe_skip(r, "S2"):
		return
	_check(r.ok == true, "S2 hint ok=true")
	_check(r.data.has("stage") and r.data.stage is int, "S2 hint.stage 为 int")
	# stage 口径 = 引擎 stage_check 0..7(0 = 完全打乱无阶段满足;服务器契约表的
	# "1..7" 与引擎契约 "0..7(stage_check 口径)" 矛盾,以引擎为准——cube.gd 负轴
	# 选层修复后 6 面均匀分布下 scramble 态可为 0,2026-09-24 整合期裁决)
	_check(r.data.stage >= 0 and r.data.stage <= 7, "S2 hint.stage ∈ 0..7 实际=%d" % r.data.stage)
	_check(r.data.has("progress"), "S2 hint 有 progress")
	var s = r.data.suggestion
	_check(s is Dictionary and s.has("piece") and s.has("alg") and s.has("text"),
			"S2 suggestion 结构 {piece, alg, text}")
	_check(s.alg is String and not (s.alg as String).is_empty(), "S2 suggestion.alg 非空")
	_check(s.text is String and not (s.text as String).is_empty(), "S2 suggestion.text 非空")


## S3:N=4 时 solve/hint 均 ok:false(§11:3 阶专用)。
func _test_n4_reject() -> void:
	_cube.setup(4)
	var r1 := _dispatch("solve")
	_check(r1.ok == false, "S3 N=4 solve ok:false")
	_check(String(r1.get("error", "")).length() > 0, "S3 N=4 solve 带错误信息")
	var r2 := _dispatch("hint")
	_check(r2.ok == false, "S3 N=4 hint ok:false")
	_cube.setup(3)


## S4:WCA 打乱标记入口 scramble_wca_apply(§15.1):响应带 from_wca=true;
## state.wca_scramble_alg 可查询;scramble/restore/reset/普通 apply_alg 的标记语义正确。
func _test_wca_marker() -> void:
	_cube.setup(3)
	var r0 := _dispatch("state")
	_check(r0.data.wca_scramble_alg == "", "S4 初始 wca_scramble_alg 为空")
	var r := _dispatch("scramble_wca_apply", {"alg": "R U R'"})
	_check(r.ok == true and r.data.queued == 3, "S4 scramble_wca_apply 入队 3 步")
	_check(r.data.has("from_wca") and r.data.from_wca == true, "S4 响应带 from_wca=true")
	var st := _dispatch("state")
	_check(st.data.wca_scramble_alg == "R U R'", "S4 state.wca_scramble_alg 可查询")
	var r_plain := _dispatch("apply_alg", {"alg": "U"})
	_check(r_plain.ok == true, "S4 普通 apply_alg ok")
	_check(_dispatch("state").data.wca_scramble_alg == "R U R'",
			"S4 普通 apply_alg 不清标记(非作废操作)")
	var r_sc := _dispatch("scramble", {"steps": 5})
	_check(r_sc.ok == true, "S4 scramble ok")
	_check(_dispatch("state").data.wca_scramble_alg == "", "S4 再次打乱清标记(§15.1 作废)")
	_dispatch("scramble_wca_apply", {"alg": "R"})
	_check(_dispatch("state").data.wca_scramble_alg == "R", "S4 标记重设")
	var r_rs := _dispatch("restore")
	_check(r_rs.ok == true, "S4 restore ok")
	_check(_dispatch("state").data.wca_scramble_alg == "", "S4 restore 清标记(§15.1 作废)")
	_dispatch("scramble_wca_apply", {"alg": "R"})
	_dispatch("reset")
	_check(_dispatch("state").data.wca_scramble_alg == "", "S4 reset 清标记(§15.1 作废)")
	while _cube.is_animating():  # 清残留动画,不污染后续测试
		await process_frame
	_cube.setup(3)


## S5:scramble_wca_apply 复用统一参数校验(非法 alg 拒绝且状态/标记零变化)。
func _test_validation() -> void:
	_cube.setup(3)
	var before: PackedByteArray = _cube.to_facelets()
	var cases := [{"alg": "R X"}, {"alg": ""}, {"alg": "R".repeat(2001)}, {"alg": 42}]
	var all_rejected := true
	for c in cases:
		var r: Dictionary = _dispatch("scramble_wca_apply", c)
		if r.ok != false:
			all_rejected = false
			printerr("  未拒绝: ", c)
	_check(all_rejected, "S5 非法 alg 全部 ok:false")
	_check(_cube.to_facelets() == before, "S5 状态零变化")
	_check(_dispatch("state").data.wca_scramble_alg == "", "S5 标记未被打上")
	_cube.setup(3)


## S8:scramble 可选 seed 的三条拒绝分支(A-6 validate_seed):非数字/非整数/
## 超 2^53 精度界全部 ok:false,合法 seed 放行(dispatch 层直测,无需 TCP)。
func _test_seed_validation() -> void:
	_cube.setup(3)
	var r_str: Dictionary = _dispatch("scramble", {"steps": 5, "seed": "abc"})
	_check(r_str.ok == false and String(r_str.get("error", "")) == "seed 必须为数字",
			"S8 非数字 seed 拒绝且文案准确")
	var r_frac: Dictionary = _dispatch("scramble", {"steps": 5, "seed": 1.5})
	_check(r_frac.ok == false and String(r_frac.get("error", "")).begins_with("seed 须为整数"),
			"S8 非整数 seed 拒绝")
	var r_big: Dictionary = _dispatch("scramble", {"steps": 5, "seed": 9007199254740994})  # 2^53+2
	_check(r_big.ok == false and String(r_big.get("error", "")).begins_with("seed 须为整数"),
			"S8 超 2^53 精度界 seed 拒绝")
	var r_ok: Dictionary = _dispatch("scramble", {"steps": 5, "seed": 42})
	_check(r_ok.ok == true, "S8 合法 seed=42 放行")
	_cube.setup(3)


## S7:计时事件信号(§15.1):scramble/scramble_wca_apply → scramble_entered;
## restore/reset → invalidated;apply_alg 不发任何计时事件(main.gd 据此驱动 timer)。
func _test_timer_signals() -> void:
	_cube.setup(3)
	var entered: Array = []
	var invalids: Array = []
	_server.scramble_entered.connect(func(alg: String) -> void: entered.append(alg))
	_server.invalidated.connect(func() -> void: invalids.append(true))
	_dispatch("scramble", {"steps": 5})
	_check(entered == [""], "S7 scramble 命令 → scramble_entered(\"\")")
	_dispatch("apply_alg", {"alg": "U"})
	_check(entered.size() == 1 and invalids.is_empty(), "S7 apply_alg 不发计时事件")
	_dispatch("scramble_wca_apply", {"alg": "R U R'"})
	_check(entered == ["", "R U R'"], "S7 scramble_wca_apply → scramble_entered(打乱序列)")
	_dispatch("restore")
	_dispatch("reset")
	_check(invalids.size() == 2, "S7 restore/reset → invalidated ×2")
	while _cube.is_animating():  # 清残留动画,不污染 socket 冒烟
		await process_frame
	_cube.setup(3)


## S6:socket 冒烟一条:真 TCP 发 solve,收合法 JSON 响应且 stages 7 段(§18 socket 只测 solve/hint)。
func _test_socket() -> void:
	_cube.setup(3)
	seed(7)
	_cube.scramble(12)
	_server.port = 18924  # 避让默认 8788(smoke 与游戏实例)
	root.add_child(_server)
	await process_frame
	var peer := StreamPeerTCP.new()
	_check(peer.connect_to_host("127.0.0.1", 18924) == OK, "S6 connect_to_host")
	var frames := 0
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer.poll()
		frames += 1
		if frames > 600:
			_check(false, "S6 连接超时")
			peer.disconnect_from_host()
			_server.free()
			return
		await process_frame
	peer.put_data("{\"id\":1,\"cmd\":\"solve\"}\n".to_utf8_buffer())
	var buf := ""
	frames = 0
	while buf.find("\n") == -1:
		peer.poll()
		var avail := peer.get_available_bytes()
		if avail > 0:
			buf += peer.get_data(avail)[1].get_string_from_utf8()
		frames += 1
		if frames > 600:
			_check(false, "S6 响应超时")
			peer.disconnect_from_host()
			_server.free()
			return
		await process_frame
	var resp = JSON.parse_string(buf.get_slice("\n", 0))
	_check(resp is Dictionary and int(resp.get("id", -1)) == 1,
			"S6 socket 响应合法 JSON 且 id 回显")
	if resp.get("ok") == true:
		_check(resp.data.stages is Array and resp.data.stages.size() == 7,
				"S6 socket solve stages 7 段")
	elif String(resp.get("error", "")).contains(NOT_READY):
		print("SKIP  S6 socket solve 结构断言(引擎未就绪)")
	else:
		_check(false, "S6 socket solve ok=false 且非未就绪: " + str(resp))
	peer.disconnect_from_host()
	_server.free()
