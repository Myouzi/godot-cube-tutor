extends SceneTree
## v6.2 万向视角自测(轨迹球四元数相机):headless 实例化 main.tscn,直调 main 脚本接口。
## 运行:godot --headless -s tests/test_view.gd;任何断言失败 exit 1,全过 exit 0。
## 覆盖:初始构图复现(视线 -(1,1,1),visual_test 7 图依赖)、连续同向增量越过旧欧拉
## ±90° 极点后连续可用无 NaN、固定 seed 随机 2000 次增量后 basis 正交且距离恒 _dist、
## 复位恢复初始姿态+基准距离且幂等、右拖方向与旧模型 yaw 减小同向。
## 断言失败只置 _fail,_run 末尾统一 quit(EXPERIENCE:退出码末尾统一判定防假绿)。

var _failed := false
var _main: Node
var _dist := 0.0
var _init_quat := Quaternion()  # 实例化后的初始姿态(复位幂等/构图基准)


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		_failed = true
		printerr("FAIL  " + msg)


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame  # @onready 与 _ready 首帧才完成(同 test_timer 实例化模式)
	while not (_main.cube is Node3D) or _main.cube.get_child_count() == 0:
		await process_frame
	_dist = _main._dist
	_init_quat = _main._view_quat
	_test_initial_pose()
	_test_over_pole()
	_test_random_2000()
	_test_reset()
	_test_drag_direction()
	_main.free()
	if _failed:
		printerr("FAILED")
		quit(1)
	else:
		print("ALL PASSED")
		quit(0)


func _cam_pos() -> Vector3:
	return _main.cam.global_position


func _view_dir() -> Vector3:
	return -_main.cam.global_transform.basis.z  # 相机 -Z = 视线(应指向原点)


func _no_nan() -> bool:
	var t: Transform3D = _main.cam.global_transform
	for k in 3:
		if is_nan(t.basis[k].x) or is_nan(t.basis[k].y) or is_nan(t.basis[k].z) \
				or is_nan(t.origin[k]):
			return false
	return true


func _dist_ok() -> bool:
	return absf(_cam_pos().length() - _dist) < 1e-3


func _looks_at_origin() -> bool:
	return _view_dir().dot(-_cam_pos().normalized()) > 1.0 - 1e-6


## 初始构图:相机位于 (1,1,1).normalized()*_dist(误差 <0.01)且视线朝向原点。
func _test_initial_pose() -> void:
	var expect := Vector3(1, 1, 1).normalized() * _dist
	_check(_cam_pos().distance_to(expect) < 0.01, "INIT 相机位于 (1,1,1).normalized()*dist")
	_check(_looks_at_origin(), "INIT 视线朝向原点")
	_check(_no_nan(), "INIT 无 NaN")


## 万向性核心:连续同方向增量越过旧欧拉模型 pitch ±90° 极点(初值 35.264°,
## 下拉 60×2°=120°、上推 80×2°=160° 均越界),全程无 NaN、距离恒 _dist、视线仍朝原点。
## 正面钉死穿越(防退化为钳位欧拉 ±89.9° 仍假绿):下拉后俯仰 155.26°,相机
## y=_dist*sin(155.26°)≈0.418*_dist(钳位模型 y≈_dist);上推后俯仰 -124.74°,
## y≈-0.822*_dist(钳位模型 y≈-_dist)。阈值 ±0.9*_dist 两侧可区分。
func _test_over_pole() -> void:
	_main._reset_view()
	var ok := true
	for i in 60:
		_main._apply_orbit_delta(0.0, 5.0)  # 下拉 2°/次,越过 +90°(旧模型钳 89.9° 处)
		if not _no_nan() or not _dist_ok():
			ok = false
			break
	_check(ok, "POLE 连续下拉 120° 越极:全程无 NaN 且距离恒 _dist")
	_check(_looks_at_origin(), "POLE 越极后视线仍朝原点")
	_check(_cam_pos().y < _dist * 0.9,
			"POLE 极点被真实穿越:下拉后相机 y≈0.418*dist < 0.9*dist(钳位 89.9° 时 y≈dist)")
	ok = true
	for i in 80:
		_main._apply_orbit_delta(0.0, -5.0)  # 上推 2°/次,越过 -90°
		if not _no_nan() or not _dist_ok():
			ok = false
			break
	_check(ok, "POLE 连续上推 160° 越负极:全程无 NaN 且距离恒 _dist")
	_check(_looks_at_origin(), "POLE 越负极后视线仍朝原点")
	_check(_cam_pos().y > -_dist * 0.9,
			"POLE 负极被真实穿越:上推后相机 y≈-0.822*dist > -0.9*dist(钳位 -89.9° 时 y≈-dist)")


## 固定 seed 随机 2000 次增量:全程无 NaN、距离恒 _dist;末尾 basis 各轴单位化、
## 两两垂直(容差 1e-3)。
func _test_random_2000() -> void:
	_main._reset_view()
	seed(20260925)
	var ok := true
	for i in 2000:
		_main._apply_orbit_delta(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		if not _no_nan() or not _dist_ok():
			ok = false
			break
	_check(ok, "RAND 2000 次随机增量:全程无 NaN 且距离恒 _dist")
	var b: Basis = _main.cam.global_transform.basis
	var ortho := _no_nan()
	for k in 3:
		if absf(b[k].length() - 1.0) > 1e-3:
			ortho = false
	for pair in [[0, 1], [1, 2], [0, 2]]:
		if absf(b[pair[0]].dot(b[pair[1]])) > 1e-3:
			ortho = false
	_check(ortho, "RAND 末态 basis 正交(轴单位、两两垂直,容差 1e-3)")


## 复位:增量后 _reset_view 恢复初始姿态与基准距离;连续两次复位幂等。
func _test_reset() -> void:
	_main._apply_orbit_delta(30.0, -40.0)
	_main._reset_view()
	var expect := Vector3(1, 1, 1).normalized() * _dist
	_check(_cam_pos().distance_to(expect) < 0.01, "RESET 复位恢复初始位置")
	_check(_looks_at_origin(), "RESET 复位恢复初始视线(朝原点)")
	_check(absf(_main._view_quat.dot(_init_quat)) > 1.0 - 1e-9, "RESET 姿态四元数同初始(±q 等价)")
	_check(absf(_main._dist - (1.7 * _main.cube.n + 2.0)) < 1e-6, "RESET 距离恢复基准 1.7n+2")
	_main._apply_orbit_delta(-15.0, 25.0)
	_main._reset_view()
	var t1: Transform3D = _main.cam.global_transform
	_main._reset_view()
	var t2: Transform3D = _main.cam.global_transform
	var idem := t1.origin.distance_to(t2.origin) < 1e-9
	for k in 3:
		idem = idem and t1.basis[k].distance_to(t2.basis[k]) < 1e-9
	_check(idem, "RESET 连续两次复位幂等")


## 方向手感:单次右拖(dx>0)视线方位角(atan2(view.x, view.z))减小,
## 与旧模型 _yaw -= dx*0.4(yaw 减小)同向。初始 -135°,4° 增量远离 ±180 无跨界。
func _test_drag_direction() -> void:
	_main._reset_view()
	var az0 := atan2(_view_dir().x, _view_dir().z)
	_main._apply_orbit_delta(10.0, 0.0)
	var az1 := atan2(_view_dir().x, _view_dir().z)
	_check(az1 < az0, "FEEL 右拖视线方位角减小(与旧模型 yaw 减小同向)")
	_main._reset_view()
