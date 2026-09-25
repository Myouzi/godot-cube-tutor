extends SceneTree
## P1.5 拖层自测(PLAN §13 / §18 T-drag):headless 直调 cube 拖层接口,不经鼠标。
## 运行:godot --headless -s tests/test_drag.gd;任何断言失败 exit 1,全过 exit 0。
## 覆盖:snap 量化(45°→90°;15° 阈值 14° 回弹/16° 取 90)、回弹不记任何账、
## 非零 snap 记账(撤销栈+full_log+计步)、180° 一步一记、cancel 不记账、
## 拖层中 grid_pos/facelets 不变(G2)、拖层中变更命令被挡(§4 矩阵"命令暂停"行)。

var _cube: Node3D
var _failed := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		_failed = true
		printerr("FAIL  " + msg)
	# 退出码在 _run 末尾统一判定(中途 quit(1) 会被末尾 quit(0) 覆盖)


func _run() -> void:
	var script: GDScript = load("res://scripts/cube.gd")
	_cube = script.new()
	root.add_child(_cube)
	# -s 模式下 _ready 延迟到首帧;等 setup(3) 完成,防首帧自动 setup 重置状态
	while _cube.get_child_count() == 0:
		await process_frame
	Engine.time_scale = 20.0
	_test_snap_math()
	await _test_snap_45_books_player()
	await _test_bounce_14_no_book()
	await _test_snap_16_books()
	await _test_180_one_step()
	await _test_cancel_no_book()
	await _test_frozen_state_during_drag()
	await _test_commands_blocked()
	await _test_idle_calls_harmless()
	Engine.time_scale = 1.0
	if _failed:
		printerr("FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)


# ---- snap 量化纯函数(P1.5 裁决:<15° 回弹;≥15° 取最近非零 90° 倍数)----

func _test_snap_math() -> void:
	var cases := [
		[0.0, 0.0], [5.0, 0.0], [14.0, 0.0], [-14.0, 0.0],
		[16.0, 90.0], [-16.0, -90.0],
		[44.0, 90.0], [45.0, 90.0], [46.0, 90.0], [89.0, 90.0], [90.0, 90.0], [91.0, 90.0],
		[-44.0, -90.0], [-45.0, -90.0], [-91.0, -90.0],
		[100.0, 90.0], [-100.0, -90.0],
		[135.0, 180.0], [-135.0, -180.0],
		[170.0, 180.0], [180.0, 180.0], [-170.0, -180.0], [-180.0, -180.0],
	]
	var ok := true
	for c in cases:
		var got: float = rad_to_deg(_cube._snap_drag_angle(deg_to_rad(c[0])))
		if not is_equal_approx(got, c[1]):
			ok = false
			printerr("  snap %s° -> %s°, 期望 %s°" % [c[0], got, c[1]])
	_check(ok, "TD-snap 量化表(45→90;14 回弹/16 取 90;135→180)")
	# clamp 边界:±200° 输入折叠到 ±180(接口层 clamp,经 finish 体现)
	_cube.setup(3)
	_cube.begin_drag(Vector3.RIGHT, [2])
	_cube.update_drag(deg_to_rad(200.0))
	var q: float = _cube.finish_drag()
	_check(is_equal_approx(q, PI), "TD-snap update 超界 ±200° clamp 到 ±180°")
	_check(_cube.moves == 1, "TD-snap clamp 后仍按 180° 记一步")


## 45° → finish 返回 90°,按 PLAYER 语义记账,终态 == apply_turn 参照。
func _test_snap_45_books_player() -> void:
	_cube.setup(3)
	var ref: Node3D = load("res://scripts/cube.gd").new()
	root.add_child(ref)
	ref.setup(3)
	ref.apply_turn(Vector3.RIGHT, [2], PI / 2)
	_cube.begin_drag(Vector3.RIGHT, [2])
	_cube.update_drag(deg_to_rad(45.0))
	var q: float = _cube.finish_drag()
	_check(is_equal_approx(q, PI / 2), "TD1 45° snap -> 90°")
	_check(_cube.to_facelets() == ref.to_facelets(), "TD1 终态 == apply_turn(R,90°) 参照")
	_check(_cube.moves == 1, "TD1 计步 1")
	_check(_cube._undo_stack.size() == 1 and _cube.full_log.size() == 1, "TD1 撤销栈+full_log 各 1 条")
	_check(int(_cube._undo_stack[0].angle) == 1 and int(_cube.full_log[0].angle) == 1,
			"TD1 记账角度 == +90°")
	ref.free()


## 14° 松手:回弹 0,不记任何账(撤销栈/full_log/moves 全不变),facelets 不变。
func _test_bounce_14_no_book() -> void:
	_cube.setup(3)
	var f0: PackedByteArray = _cube.to_facelets()
	_cube.begin_drag(Vector3.UP, [2])
	_cube.update_drag(deg_to_rad(14.0))
	var q: float = _cube.finish_drag()
	_check(q == 0.0, "TD2 14° 回弹为 0")
	_check(_cube._undo_stack.is_empty() and _cube.full_log.is_empty() and _cube.moves == 0,
			"TD2 回弹不记任何账(撤销栈/full_log/moves 全不变)")
	_check(_cube.to_facelets() == f0 and _cube.is_solved(), "TD2 回弹后 facelets 不变")


## 16° 松手:取 90°,走 PLAYER 记账。
func _test_snap_16_books() -> void:
	_cube.setup(3)
	_cube.begin_drag(Vector3.UP, [2])
	_cube.update_drag(deg_to_rad(16.0))
	var q: float = _cube.finish_drag()
	_check(is_equal_approx(q, PI / 2), "TD3 16° 取 90°(≥15° 不回弹)")
	_check(_cube.moves == 1 and _cube.full_log.size() == 1, "TD3 16° snap 记账")


## 180° 一步一记(与 R2 口径一致);undo(动画)撤回 -> solved。
func _test_180_one_step() -> void:
	_cube.setup(3)
	_cube.begin_drag(Vector3.RIGHT, [2])
	_cube.update_drag(PI)
	var q: float = _cube.finish_drag()
	_check(is_equal_approx(q, PI), "TD4 180° snap -> 180°")
	_check(_cube.moves == 1, "TD4 180° 计一步")
	_check(_cube._undo_stack.size() == 1 and _cube.full_log.size() == 1, "TD4 一步一记(栈/log 各 1)")
	_check(not _cube.is_solved(), "TD4 180° 后非 solved")
	_check(_cube.undo(), "TD4 undo 受理")
	while _cube.is_animating():
		await process_frame
	_check(_cube.is_solved(), "TD4 undo 180° -> solved")
	_check(_cube.moves == 0 and _cube._undo_stack.is_empty(), "TD4 undo 后栈清/步归 0")


## cancel:回弹归位,不 bake 不记任何账;无 pivot 残留。
func _test_cancel_no_book() -> void:
	_cube.setup(3)
	var f0: PackedByteArray = _cube.to_facelets()
	var p0 := _pos_set()
	_cube.begin_drag(Vector3.BACK, [2])
	_cube.update_drag(0.7)
	_cube.cancel_drag()
	_check(_cube.to_facelets() == f0 and _cube.is_solved(), "TD5 cancel 后 facelets 复原")
	_check(_pos_set() == p0, "TD5 cancel 后 grid_pos 复原")
	_check(_cube._undo_stack.is_empty() and _cube.full_log.is_empty() and _cube.moves == 0,
			"TD5 cancel 不记任何账")
	_check(_cube.pivot.get_child_count() == 0, "TD5 cancel 后 pivot 无残留块")
	_check(not _cube.is_dragging(), "TD5 cancel 后手势标志复位")


## 拖层中 grid_pos 与 facelets 恒不变(G2):pivot 在转,数据不动。
func _test_frozen_state_during_drag() -> void:
	_cube.setup(3)
	var f0: PackedByteArray = _cube.to_facelets()
	var gp0 := _gp_map()
	_cube.begin_drag(Vector3.UP, [2])
	_cube.update_drag(0.3)
	var ok1: bool = _cube.to_facelets() == f0 and _gp_map() == gp0
	_cube.update_drag(1.2)
	var ok2: bool = _cube.to_facelets() == f0 and _gp_map() == gp0
	_check(ok1 and ok2, "TD6 拖层中(0.3/1.2 rad)grid_pos 与 facelets 不变")
	_check(_cube.is_solved(), "TD6 拖层中 is_solved 仍按已 bake 态判定")
	_cube.finish_drag()  # 1.2 rad ≈ 68.8° → 90°,顺带收尾


## 拖层手势中变更命令全部忽略(§4 矩阵"命令暂停"行)。
func _test_commands_blocked() -> void:
	_cube.setup(3)
	_cube.apply_turn(Vector3.RIGHT, [2], PI / 2)  # 造一个玩家步,使 undo 栈非空
	var f0: PackedByteArray = _cube.to_facelets()
	var log0: int = _cube.full_log.size()
	_cube.begin_drag(Vector3.UP, [2])
	var blocked := true
	if _cube.enqueue_turn(Vector3.LEFT, [2], PI / 2):
		blocked = false
	if _cube.undo():
		blocked = false
	if _cube.play_alg("R U R' U'") >= 0:
		blocked = false
	_cube.scramble(5)
	_cube.restore()
	_cube.reset()
	if _cube.to_facelets() != f0 or _cube.full_log.size() != log0 or not _cube.is_dragging():
		blocked = false
	_check(blocked, "TD7 拖层中 enqueue/undo/play_alg/scramble/restore/reset 全部忽略")
	_check(_cube._queue.is_empty(), "TD7 拖层中队列为空(无命令漏入)")
	_cube.cancel_drag()
	while _cube.is_animating():
		await process_frame


## 未起手时调用拖层接口无害:finish 返回 NAN,update/cancel 空操作。
func _test_idle_calls_harmless() -> void:
	_cube.setup(3)
	_check(is_nan(_cube.finish_drag()), "TD8 未起手 finish 返回 NAN")
	_cube.update_drag(1.0)
	_cube.cancel_drag()
	_check(_cube.moves == 0 and _cube.is_solved(), "TD8 未起手 update/cancel 空操作")
	_check(_cube.begin_drag(Vector3.UP, []) == false, "TD8 layers 空 -> begin 拒绝")


func _pos_set() -> Dictionary:
	var s := {}
	for c in _cube.cubies:
		s[str(c.grid_pos)] = true
	return s


func _gp_map() -> Dictionary:
	var m := {}
	for c in _cube.cubies:
		m[c.get_instance_id()] = c.grid_pos
	return m
