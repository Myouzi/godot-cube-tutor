extends Node3D
## 场景入口(PLAN §5/§13~§17):四态模式机(自由/教学/计时/训练)、键盘/Alt 宽转、
## 左键拖层(命中)/orbit(未命中)、教学侧栏(引擎 hint)、计时(timer.gd)、CFOP 训练、UI 接线。
## P4 裁量:训练 = 第四态(与三态同组单选,布局切换同构),N≠3 一并禁用(公式表 3 阶专用)。

const FACE_KEYS := {
	KEY_U: Vector3.UP,
	KEY_D: Vector3.DOWN,
	KEY_L: Vector3.LEFT,
	KEY_R: Vector3.RIGHT,
	KEY_F: Vector3.BACK,
	KEY_B: Vector3.FORWARD,
}
const DRAG_START_PX := 8.0  # 锁轴屏幕位移阈值(§13.2,防误触)
const DRAG_SENSITIVITY := 0.011  # rad/px:锁轴后像素→角度(§13.6 手感人工验收项)

enum Mode { FREE, TEACH, TIMER, TRAIN }

const MODE_NAMES := ["自由模式", "教学模式", "计时模式", "训练模式"]
const STAGE_TIPS := [  # 教学侧栏每阶段一句要领(§14.5,按本项目朝向 U=白 撰写)
	"在顶层拼出白色十字,每条棱的侧面颜色与中心块对齐。",
	"把四个白色角块带进顶层归位,侧面两色与相邻中心对齐。",
	"把不带黄色的四条棱插入中层(先对齐侧面中心再插槽)。",
	"底面拼黄色十字:黄点变黄线、黄线变黄十字。",
	"用小鱼公式把底面九格全部变黄。",
	"底面四个角轮换对位:先把位置正确的角摆好,其余转圈换。",
	"最后三条棱轮换归位,完成整个复原。",
]
const TRAIN_CATS := ["f2l", "oll", "pll"]

@onready var cube = $CubeRoot
@onready var server: Node = $CubeServer
@onready var cam: Camera3D = $Camera3D
@onready var mode_btns := {
	Mode.FREE: $UI/TopBar/ModeFree,
	Mode.TEACH: $UI/TopBar/ModeTeach,
	Mode.TIMER: $UI/TopBar/ModeTimer,
	Mode.TRAIN: $UI/TopBar/ModeTrain,
}
@onready var scramble_btn: Button = $UI/TopBar/ScrambleBtn
@onready var undo_btn: Button = $UI/TopBar/UndoBtn
@onready var reset_btn: Button = $UI/TopBar/ResetBtn
@onready var n_btn: Button = $UI/TopBar/NBtn
@onready var n_menu: PopupMenu = $UI/TopBar/NBtn/NMenu
@onready var alg_edit: LineEdit = $UI/TopBar/AlgEdit
@onready var play_btn: Button = $UI/TopBar/PlayBtn
@onready var speed_slider: HSlider = $UI/TopBar/SpeedSlider
@onready var speed_label: Label = $UI/TopBar/SpeedLabel
@onready var view_reset_btn: Button = $UI/TopBar/ViewResetBtn
@onready var status_label: Label = $UI/StatusLabel
@onready var help_label: Label = $UI/HelpLabel
@onready var time_label: Label = $UI/TimeLabel
@onready var teach_panel: PanelContainer = $UI/TeachPanel
@onready var teach_stage_labels: Array = [
	$UI/TeachPanel/VBox/Stage0, $UI/TeachPanel/VBox/Stage1, $UI/TeachPanel/VBox/Stage2,
	$UI/TeachPanel/VBox/Stage3, $UI/TeachPanel/VBox/Stage4, $UI/TeachPanel/VBox/Stage5,
	$UI/TeachPanel/VBox/Stage6,
]
@onready var teach_tip: Label = $UI/TeachPanel/VBox/TipLabel
@onready var teach_hint: Label = $UI/TeachPanel/VBox/HintLabel
@onready var teach_demo_btn: Button = $UI/TeachPanel/VBox/BtnRow/DemoBtn
@onready var teach_auto_btn: Button = $UI/TeachPanel/VBox/BtnRow/AutoBtn
@onready var timer_panel: PanelContainer = $UI/TimerPanel
@onready var timer_stat: Label = $UI/TimerPanel/VBox/StatLabel
@onready var timer_hist: Label = $UI/TimerPanel/VBox/HistoryLabel
@onready var scramble_seq: Label = $UI/TimerPanel/VBox/ScrambleSeq
@onready var train_panel: PanelContainer = $UI/TrainPanel
@onready var train_cat_btns := {
	"f2l": $UI/TrainPanel/VBox/CatRow/F2LBtn,
	"oll": $UI/TrainPanel/VBox/CatRow/OLLBtn,
	"pll": $UI/TrainPanel/VBox/CatRow/PLLBtn,
}
@onready var train_new_btn: Button = $UI/TrainPanel/VBox/NewCaseBtn
@onready var train_case_label: Label = $UI/TrainPanel/VBox/CaseLabel
@onready var train_alg_label: Label = $UI/TrainPanel/VBox/AlgLabel
@onready var train_show_btn: Button = $UI/TrainPanel/VBox/ShowBtn
@onready var train_result_label: Label = $UI/TrainPanel/VBox/ResultLabel
@onready var train_stat_label: Label = $UI/TrainPanel/VBox/TrainStatLabel

var _mode := Mode.FREE
var _timer = load("res://scripts/timer.gd").new()  # 计时逻辑(PLAN §15)
var _train_stats = load("res://scripts/train_stats.gd").new()  # 训练每案例统计(A-8)
var _lbl  # LBL 引擎(lazy load;缺失时教学入口降级提示)
var _cfop := {}  # data/cfop.json:{"f2l":[...], "oll":[...], "pll":[...]}
var _train_cat := "f2l"
var _train_case := {}  # 当前训练 case(空 = 未出题)
var _train_case_cat := ""  # 出题时的分类(统计 key 冻结用:切分类按钮不清 case,完成入账须记到出题分类)
var _train_t0 := 0
var _train_done := false
var _auto_stage := 0  # 「自动完成本阶段」目标阶段(0 = 关闭)
var _teach_fp := ""  # 状态指纹:facelets 未变则 hint/高亮不重算
var _teach_cache := {}  # 状态指纹:facelets 未变则 hint/高亮不重算
var _teach_best := 0  # 本局达到过的最高阶段(回退红显用)
var _was_solved := true  # is_solved 边沿检测(计时停表/训练完成)

var _dist := 7.1
var _view_quat := Quaternion()  # 轨迹球姿态(v6.2):_ready 经 _reset_view 置初始构图
var _orbiting := false  # 左键未命中 cubie:orbit 视角(只动相机)
var _gesture := false  # 左键命中 cubie:拖层手势候选(未锁轴)
var _locked := false  # 已锁轴且 cube.begin_drag 成功
var _press_pos := Vector2.ZERO
var _hit_cubie = null  # 命中的 cubie(动态访问 grid_pos)
var _hit_normal := Vector3.ZERO  # 命中面法线(世界系)
var _hit_point := Vector3.ZERO  # 命中点(世界系,屏幕投影基准)
var _drag_screen_dir := Vector2.ZERO  # 锁轴切向的屏幕投影(单位向量)
var _msg := ""
var _msg_until := 0.0


func _ready() -> void:
	cube.setup(3)
	_reset_view()  # 初始构图:视线 -(1,1,1) + 基准距离 1.7n+2(§3.2)
	scramble_btn.pressed.connect(_on_scramble)
	undo_btn.pressed.connect(_on_undo)
	reset_btn.pressed.connect(_on_reset)
	play_btn.pressed.connect(_on_play)
	speed_slider.value_changed.connect(_on_speed_changed)
	speed_slider.value = cube.turn_time  # 滑杆初值与引擎一致(handler 顺带刷显示)
	view_reset_btn.pressed.connect(_reset_view)
	n_btn.pressed.connect(_on_n_btn)
	n_menu.id_pressed.connect(_on_size_selected)
	teach_demo_btn.pressed.connect(_on_teach_demo)
	teach_auto_btn.pressed.connect(_on_teach_auto)
	train_new_btn.pressed.connect(_on_train_new)
	train_show_btn.pressed.connect(_on_train_show)
	# §15.1:MCP 命令路径的打乱/作废经 server 信号贯穿计时状态机(与按钮路径同语义)
	server.scramble_entered.connect(_on_scramble_entered)
	server.invalidated.connect(_on_server_invalidated)
	for m in mode_btns:
		mode_btns[m].pressed.connect(_set_mode.bind(m))
	for cat in train_cat_btns:
		train_cat_btns[cat].pressed.connect(_set_train_cat.bind(cat))
	_load_cfop()
	_update_mode_ui()


func _load_cfop() -> void:
	var txt := FileAccess.get_file_as_string("res://data/cfop.json")
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_cfop = parsed


## 打乱按钮(A-4):3 阶且 WCA 生成器(python3 + kociemba,与 MCP 桥同源逻辑)可用时
## 优先 WCA 均匀序列——经 server 的 scramble_wca_apply 打乱标记入口代执行,与 MCP
## cube_scramble_wca 完全同语义(计时进 scrambled、序列面板展示、信号反馈统一);
## 代执行失败(返回 ok:false)或生成器不可用或 N≠3 时降级现有随机步并如实提示
## (§15.1 按钮与 MCP scramble 命令同语义;降级须清 WCA 标记,同 dispatch "scramble"
## 的清理语义 cube_server.gd:91——否则 state 查询的 wca_scramble_alg 名实不符)。
func _on_scramble() -> void:
	var alg := _wca_scramble_alg()
	if not alg.is_empty():
		var r: Dictionary = server.dispatch({"id": 0, "cmd": "scramble_wca_apply", "alg": alg})
		if bool(r.get("ok", false)):
			scramble_btn.release_focus()
			return
	server.wca_scramble_alg = ""  # 降级随机步 = WCA 标记作废(§15.1,与 MCP scramble 一致)
	var before: int = cube.full_log.size()
	cube.scramble()
	var after: int = cube.full_log.size()
	_on_scramble_entered("", after - before)  # 随机步路径无服务端信号,直接走统一处理(带真实步数)
	scramble_btn.release_focus()


## WCA 均匀打乱序列获取(A-4,仅 3 阶):python3 子进程跑 tools/wca_scramble.py
## (复用 mcp_bridge.py 的生成逻辑:随机合法状态 → kociemba.solve → 解取逆,
## 单一实现源),主线程同步等待(表初始化后单次毫秒级,加 python 启动约 <1s)。
## 不可用(python3/脚本/kociemba 缺失、输出非法)返回 "",调用方降级随机步。
## ponytail: OS.execute 无超时参数,生成器异常挂死会阻塞 UI;上线程化前接受该上限。
func _wca_scramble_alg() -> String:
	if cube.n != 3:
		return ""
	var script := ProjectSettings.globalize_path("res://tools/wca_scramble.py")
	if not FileAccess.file_exists(script):
		return ""
	var out := []
	var code := OS.execute("python3", [script], out)
	if code != 0 or out.is_empty():
		return ""
	var parsed = JSON.parse_string("".join(out))
	if not (parsed is Dictionary) or not bool(parsed.get("ok", false)):
		return ""
	var alg := String(parsed.get("alg", ""))
	if server.validate_alg(alg) != "":  # 生成器输出按外部输入校验(信任边界)
		return ""
	return alg


## 打乱进入 scrambled(§15.1,按钮/scramble 命令/WCA 代执行三来源统一):
## 计时模式进 scrambled(running 中隐式作废旧轮开新轮);其余模式当前计时作废,
## 并对打乱来源如实反馈(A-4:WCA 代执行/随机步降级在自由/训练模式同样提示)。
## alg 非空 = WCA 均匀打乱代执行,顺带在计时面板展示记号序列(§15.2)。
## rand_steps = 本次随机步打乱的真实步数(按钮路径已知;服务端信号路径未知传 -1,
## 提示省略步数——full_log 含玩家历史,不能拿来当本次步数,否则数字虚报)。
func _on_scramble_entered(alg: String, rand_steps := -1) -> void:
	_teach_best = 0  # 新局:回退红基准清零(§14.2 红语义只针对本局)
	if _mode == Mode.TIMER:
		_timer.enter_scrambled()
		_was_solved = false
		_refresh_timer_stats()
		if alg.is_empty():
			# 面板文本同非计时分支口径:步数已知(按钮路径)显示真实值,服务端信号路径未知则省略
			if rand_steps < 0:
				scramble_seq.text = "(本次为随机步打乱,非 WCA 均匀打乱)"
			else:
				scramble_seq.text = "(本次为 %d 步随机打乱,非 WCA 均匀打乱)" % rand_steps
			# A-4 后到达此分支的唯一原因 = kociemba 不可用(MCP cube_scramble_wca 同样依赖它,勿再引导)
			_flash("已打乱(非 WCA 均匀打乱;WCA 均匀打乱需 kociemba 可用)")
		else:
			scramble_seq.text = "WCA 打乱序列:\n" + alg
			_flash("WCA 均匀打乱已代执行(%d 步)" % alg.split(" ", false).size())
	else:
		_timer.invalidate()
		if alg.is_empty():  # A-4:随机步降级(生成器不可用或 N≠3),提示风格与计时一致
			if rand_steps < 0:  # 服务端信号路径:本次步数未知,宁缺勿虚报
				_flash("已打乱(随机步打乱,非 WCA 均匀打乱;WCA 均匀打乱需 3 阶且 kociemba 可用)")
			else:
				_flash("已打乱(%d 步随机打乱,非 WCA 均匀打乱;WCA 均匀打乱需 3 阶且 kociemba 可用)" % rand_steps)
		else:
			_flash("WCA 均匀打乱已代执行(%d 步)" % alg.split(" ", false).size())


## MCP restore/reset 到达:当前计时作废(§15.1;防 running 中经 is_solved 边沿误记成绩)
func _on_server_invalidated() -> void:
	_timer.invalidate()
	scramble_seq.text = ""


func _on_undo() -> void:
	if cube.undo():
		_timer.on_undo()  # 显式入口:不起表不打断(§15.1)
	undo_btn.release_focus()


func _on_reset() -> void:
	cube.reset()
	_timer.invalidate()
	_teach_best = 0  # 新局:回退红基准清零
	scramble_seq.text = ""
	_train_case = {}
	_train_case_cat = ""
	_train_done = false
	reset_btn.release_focus()


func _on_play() -> void:
	# §6.2 G5:UI 与分发器共用同一校验函数(含 ≤2000 字符/≤300 token 边界;小写随阶数)
	if server.validate_alg(alg_edit.text) != "" or cube.play_alg(alg_edit.text) < 0:
		_flash("公式非法:U D L R F B + ' + 2(小写宽转仅 4 阶以上)")
	play_btn.release_focus()


## 播放速度滑杆(A-5):即时生效(play_alg/restore 均走 cube.turn_time);
## 越界值由 cube 属性 setter clamp,显示随引擎实际值。
func _on_speed_changed(v: float) -> void:
	cube.turn_time = v
	speed_label.text = "%.2f s/步" % cube.turn_time


func _set_mode(m: int) -> void:
	if m == _mode:
		return
	_mode = m
	_timer.invalidate()  # §15.1:切换模式 = 当前计时作废
	_auto_stage = 0
	_update_mode_ui()


func _update_mode_ui() -> void:
	var can3: bool = cube.n == 3  # 教学/计时/训练 3 阶专用(§11)
	for m in mode_btns:
		mode_btns[m].disabled = (m != Mode.FREE and not can3)
		mode_btns[m].set_pressed_no_signal(m == _mode)
	if _mode != Mode.FREE and not can3:
		_mode = Mode.FREE  # 阶数切走后当前模式不可用 → 回自由
	teach_panel.visible = _mode == Mode.TEACH
	timer_panel.visible = _mode == Mode.TIMER
	time_label.visible = _mode == Mode.TIMER
	train_panel.visible = _mode == Mode.TRAIN
	teach_auto_btn.text = "自动完成本阶段"
	_teach_fp = ""  # 强制重算
	if _mode == Mode.TIMER:
		_refresh_timer_stats()


func _on_n_btn() -> void:
	n_menu.clear()
	for i in range(2, 8):
		n_menu.add_item("%d 阶" % i, i)
	var gp := n_btn.get_global_rect()
	n_menu.position = Vector2i(gp.position + Vector2(0, gp.size.y))
	n_menu.popup()


func _on_size_selected(id: int) -> void:
	if id < 2 or id > 7 or id == cube.n:
		return
	cube.setup(id)  # 确认 = reset + setup(n)(§17.1:full_log/撤销/步数全清)
	_dist = 1.7 * cube.n + 2.0
	_update_cam()
	n_btn.text = "%d 阶" % cube.n
	_timer.invalidate()
	_teach_best = 0  # 新局:回退红基准清零
	_train_case = {}
	_train_case_cat = ""
	_train_done = false
	_auto_stage = 0
	_update_mode_ui()
	_flash("已切换到 %d 阶(状态重置)" % cube.n)


# ---- 玩家操作入口(键盘/拖层):教学重判 + 计时起表 ----

func _on_player_action() -> void:
	_timer.on_player_turn()  # 仅 SCRAMBLED 态起表(timer 内部判定)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE:
		if cube.is_dragging():
			cube.cancel_drag()  # §13.5:拖层中 Esc = 中断手势回弹归位,不退出
		else:
			get_tree().quit()
	elif k.keycode == KEY_HOME:
		_reset_view()  # v6.2:复位视角(与顶栏「回正」同入口)
	elif k.alt_pressed and FACE_KEYS.has(k.keycode):
		_wide_turn(FACE_KEYS[k.keycode], k.shift_pressed)  # §17.2:Alt+字母 = 双层宽转
	elif FACE_KEYS.has(k.keycode):
		var angle := PI / 2 if k.shift_pressed else -PI / 2  # 顺时针 = -90°(§3.1 右手系)
		if cube.enqueue_turn(FACE_KEYS[k.keycode], [cube.E], angle):
			_on_player_action()


## 双层宽转(§17.2):该面 + 相邻内层两层一次动画;3 阶无宽转键位(记号集最小)。
## layers 按 gp·axis 约定恒为正值(负轴外层块点积同为 +E,见 cube._outer_layer)。
func _wide_turn(axis: Vector3, invert: bool) -> void:
	if cube.n < 4:
		return
	var angle := PI / 2 if invert else -PI / 2
	if cube.enqueue_turn(axis, [cube.E, cube.E - 2], angle):
		_on_player_action()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_left(event.position)
		else:
			_release_left()
	elif event is InputEventMouseButton and event.pressed \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# 滚轮缩放(v6.1):基准距离 1.7n+2 的 0.5~2 倍,单步 ×1.1(上滚拉近)
		var base: float = 1.7 * cube.n + 2.0
		var f: float = (1.0 / 1.1) if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1
		_dist = clampf(_dist * f, base * 0.5, base * 2.0)
		_update_cam()
	elif event is InputEventMouseMotion:
		if _locked:
			_update_gesture(event.position)
		elif _gesture:
			_try_lock(event.position)
		elif _orbiting:
			_apply_orbit_delta(event.relative.x, event.relative.y)


# ---- 左键拖层(§13):命中即拖/未命中 orbit;>8px 锁轴;松手 snap ----

func _press_left(pos: Vector2) -> void:
	_press_pos = pos
	var hit := _raycast_cubie(pos)
	# 起手条件(§13.1):命中 cubie 且队列空且非播放;否则 orbit(现有行为)
	if hit.is_empty() or cube.is_animating() or cube.is_programmatic():
		_orbiting = true
		return
	_gesture = true
	_hit_cubie = hit.cubie
	_hit_normal = hit.normal
	_hit_point = hit.point


func _release_left() -> void:
	if _locked:
		var q: float = cube.finish_drag()
		if not is_nan(q) and q != 0.0:
			_on_player_action()  # 非零 snap = 玩家步:计时起表点(回弹不算)
	_gesture = false
	_locked = false
	_orbiting = false


## 锁轴(§13.2):屏幕位移 >8px 后,经相机基投影到命中面切平面,
## axis = normal.cross(dir) 取最近坐标轴,方向符号随角度;本次手势不换轴。
func _try_lock(pos: Vector2) -> void:
	var d := pos - _press_pos
	if d.length() <= DRAG_START_PX:
		return
	var world: Vector3 = cam.global_transform.basis * Vector3(d.x, -d.y, 0.0)
	var t := world - _hit_normal * world.dot(_hit_normal)  # 投影到命中面切平面
	if t.length() < 1e-6:
		_gesture_to_orbit()
		return
	var axis := _snap_axis(_hit_normal.cross(t.normalized()))
	var g: Vector3i = _hit_cubie.grid_pos
	if not cube.begin_drag(axis, [int(g.x * axis.x + g.y * axis.y + g.z * axis.z)]):
		_gesture_to_orbit()
		return
	var tang := axis.cross(_hit_normal).normalized()  # axis = normal×t ⇒ t = axis×normal
	_drag_screen_dir = _screen_dir(tang)
	_locked = true


func _update_gesture(pos: Vector2) -> void:
	if _drag_screen_dir == Vector2.ZERO:
		return
	cube.update_drag((pos - _press_pos).dot(_drag_screen_dir) * DRAG_SENSITIVITY)


func _gesture_to_orbit() -> void:
	_gesture = false
	_orbiting = true


## 射线最近坐标轴:分量绝对值最大者,保留符号。
func _snap_axis(v: Vector3) -> Vector3:
	var out := Vector3.ZERO
	var best := -1.0
	for k in 3:
		if absf(v[k]) > best:
			best = absf(v[k])
			out = Vector3.ZERO
			out[k] = signf(v[k])
	return out


## 世界方向在命中点处的屏幕投影(单位向量;方向近视线时返回 ZERO,角度保持)。
func _screen_dir(world_dir: Vector3) -> Vector2:
	var v := cam.unproject_position(_hit_point + world_dir * 0.5) - cam.unproject_position(_hit_point)
	return v.normalized() if v.length() > 0.001 else Vector2.ZERO


## 手写 ray-OBB(cubie 无碰撞体):cubie 无缩放,局部 slab 相交的 t 与世界同尺度;
## 返回 {cubie, normal, point} 或 {}。可拖层前提是命中可见外露块(cubies 只含外露)。
func _raycast_cubie(pos: Vector2) -> Dictionary:
	var origin := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var half: float = 0.5 * cube.CUBIE_SIZE
	var best := INF
	var hit := {}
	for c in cube.cubies:
		var inv: Transform3D = c.global_transform.affine_inverse()
		var lo: Vector3 = inv * origin
		var ld: Vector3 = inv.basis * dir
		var tmin := -INF
		var tmax := INF
		var n_axis := -1
		var n_sign := 1.0
		var ok := true
		for k in 3:
			var dc := float(ld[k])
			var o := float(lo[k])
			if absf(dc) < 1e-9:
				if absf(o) > half:
					ok = false
					break
				continue
			var t1 := (-half - o) / dc  # 进入 -k 面的 t(法线 -k)
			var t2 := (half - o) / dc
			var s := -1.0
			if t1 > t2:  # d<0:从 +k 面进入
				var tmp := t1
				t1 = t2
				t2 = tmp
				s = 1.0
			if t1 > tmin:
				tmin = t1
				n_axis = k
				n_sign = s
			tmax = minf(tmax, t2)
			if tmin > tmax:
				ok = false
				break
		if ok and tmin > 0.001 and tmin < best:
			best = tmin
			var nl := Vector3.ZERO
			nl[n_axis] = n_sign
			hit = {"cubie": c, "normal": (c.global_transform.basis * nl).normalized(),
					"point": origin + dir * tmin}
	return hit


## 轨迹球增量(v6.2,grilling K1):dx 绕相机局部 up、dy 绕相机局部 right,
## 世界系左乘累积到 _view_quat。负号 = 拖场景手感,与旧欧拉版一致
## (右拖场景右转 / 下拉视角升高),灵敏度同旧版 0.4°/px。无欧拉极点,可越过 ±90°。
func _apply_orbit_delta(dx: float, dy: float) -> void:
	var b := Basis(_view_quat)
	var step := deg_to_rad(0.4)
	if dx != 0.0:
		_view_quat = Quaternion(b.y, -dx * step) * _view_quat
	if dy != 0.0:
		_view_quat = Quaternion(b.x, -dy * step) * _view_quat
	_view_quat = _view_quat.normalized()  # 防长程累积漂移出单位长度
	_update_cam()


## 相机摆位完全由 _view_quat 决定:位于局部 +Z 轴上、距离恒 _dist、看向原点。
## up 即相机局部 Y(随姿态走),世界 UP 在极点处会退化,不用;输入无 NaN 则全程无 NaN。
func _update_cam() -> void:
	var b := Basis(_view_quat)
	cam.global_transform = Transform3D(b, b.z * _dist)


## 复位视角(v6.2,grilling K2):初始三视图姿态(视线 -(1,1,1))+ 基准距离。
## 双入口:Home 键 + 顶栏「回正」按钮。
func _reset_view() -> void:
	_view_quat = Basis.looking_at(-Vector3(1, 1, 1).normalized(), Vector3.UP) \
			.get_rotation_quaternion()
	var base: float = 1.7 * cube.n + 2.0  # cube 无类型标注:显式 float,勿用 :=(Variant 推断 parse error)
	_dist = base
	_update_cam()


# ---- 教学侧栏(§14.5)----

func _lbl_solver():
	if _lbl == null:
		if not ResourceLoader.exists("res://scripts/lbl_solver.gd"):
			return null
		_lbl = load("res://scripts/lbl_solver.gd")
	return _lbl


func _on_teach_demo() -> void:
	var h := _teach_hint()
	if h.is_empty() or String(h.get("suggestion", {}).get("alg", "")).is_empty():
		_flash("引擎暂无建议")
		return
	if cube.play_alg(String(h.suggestion.alg)) < 0:
		_flash("演示入队失败(播放中?)")
	teach_demo_btn.release_focus()


func _on_teach_auto() -> void:
	# 自动完成本阶段(§14.5):循环「建议→执行」至该阶段判定通过;再点 = 停止
	if _auto_stage > 0:
		_auto_stage = 0
		teach_auto_btn.text = "自动完成本阶段"
		return
	var sc: int = _teach_stage()
	if sc >= 7:
		_flash("已复原,无需自动")
		return
	_auto_stage = 1 if sc == 0 else sc + 1
	teach_auto_btn.text = "停止自动"
	teach_auto_btn.release_focus()


func _teach_stage() -> int:
	var s = _lbl_solver()
	if s == null:
		return 0
	return s.stage_check(cube.to_facelets())


func _teach_hint() -> Dictionary:
	var s = _lbl_solver()
	if s == null:
		return {}
	var fp := str(hash(cube.to_facelets()))  # 全局 hash():PackedByteArray 无 hash 方法
	if fp == _teach_fp and _teach_cache.has("hint"):
		return _teach_cache.hint
	var h: Dictionary = s.hint(cube.to_facelets())
	_teach_fp = fp
	_teach_cache = {"hint": h}
	return h


## 教学侧栏刷新:高亮(绿完成/蓝当前/红回退)+ 当前阶段要领 + 引擎建议。
func _teach_refresh() -> void:
	if _mode != Mode.TEACH or cube.is_animating():
		return
	var s = _lbl_solver()
	if s == null:
		teach_hint.text = "教学引擎未就绪(scripts/lbl_solver.gd 缺失)"
		return
	var sc: int = _teach_stage()
	_teach_best = maxi(_teach_best, sc)
	for i in 7:
		var st := i + 1
		var color := Color(0.6, 0.6, 0.6)
		var mark := "    "
		if st <= sc:
			color = Color(0.35, 0.85, 0.35)  # 绿 = 完成
			mark = "✓ "
		elif st == sc + 1:
			color = Color(0.35, 0.6, 0.95)  # 蓝 = 当前
			mark = "▶ "
		elif st <= _teach_best:
			color = Color(0.9, 0.35, 0.3)  # 红 = 回退(曾完成现在未完成)
			mark = "↩ "
		teach_stage_labels[i].add_theme_color_override("font_color", color)
		teach_stage_labels[i].text = "%d.%s%s" % [st, mark, s.STAGE_NAMES[i]]
	teach_tip.text = STAGE_TIPS[mini(sc, 6)]
	var h := _teach_hint()
	var sug: Dictionary = h.get("suggestion", {})
	if sc >= 7:
		teach_hint.text = "🎉 已复原!魔方完成。"
	elif sug.is_empty():
		teach_hint.text = "引擎暂无建议(状态异常?)"
	else:
		teach_hint.text = "建议(%s):%s\n公式:%s" % [String(sug.get("piece", "")),
				String(sug.get("text", "")), String(sug.get("alg", ""))]


# ---- 计时模式(§15)----

func _fmt_ms(ms: int) -> String:
	return "%d:%02d.%03d" % [ms / 60000, int(ms / 1000) % 60, ms % 1000]


func _refresh_timer_stats() -> void:
	var ts: GDScript = load("res://scripts/timer.gd")
	var flat := []
	var all: Dictionary = _timer.load_all()
	for day in all:
		for t in all[day]:
			flat.append(t)
	var ao5: float = ts.ao5(flat)
	var ao12: float = ts.ao12(flat)
	var best: int = ts.best(flat)
	timer_stat.text = "AO5  %s\nAO12 %s\n最佳  %s" % [
			"-" if ao5 < 0 else "%.3f" % (ao5 / 1000.0),
			"-" if ao12 < 0 else "%.3f" % (ao12 / 1000.0),
			"-" if best < 0 else _fmt_ms(best)]
	var lines := []
	for i in range(flat.size() - 1, maxi(-1, flat.size() - 13), -1):
		lines.append("%2d. %s" % [flat.size() - i, _fmt_ms(flat[i])])
	timer_hist.text = "最近成绩:\n" + ("\n".join(lines) if lines else "(暂无)")


# ---- CFOP 训练(P4,§16)----

func _set_train_cat(cat: String) -> void:
	_train_cat = cat


## CFOP 公式清洗 → 步数组。源记号集(实测 lukejacksonn/cube 全量):
## UDLRFB+2+'+3 / 小写宽转 udlrfb / 整体旋转 x y z / 中层 M E S / 括号。
## - 小写宽转(WCA = 该面+相邻内层两层):layers 两值一次动画
## - y/x/z 整体旋转:三层一步(净 facelet 效果 = 绕该轴刚体旋转,与 _bake 几何同源;
##   y 与 U 同向、x 与 R 同向、z 与 F 同向)
## - M/E/S 中层(layers=[0]):M 跟 L、E 跟 D、S 跟 F 方向
## - X3 三连转 = 逆 90°(与 X' 等价)
func _cfop_steps(alg: String) -> Array:
	var axis_of := {"U": Vector3.UP, "D": Vector3.DOWN, "L": Vector3.LEFT,
			"R": Vector3.RIGHT, "F": Vector3.BACK, "B": Vector3.FORWARD,
			"Y": Vector3.UP, "X": Vector3.RIGHT, "Z": Vector3.BACK,
			"M": Vector3.LEFT, "E": Vector3.DOWN, "S": Vector3.BACK}
	var steps := []
	for raw in alg.replace("(", " ").replace(")", " ").split(" ", false):
		var tok := raw.strip_edges()
		if tok.is_empty():
			continue
		var base := tok[0]
		if not axis_of.has(base.to_upper()):
			continue  # 未知记号跳过(数据源仅含上述记号)
		var axis: Vector3 = axis_of[base.to_upper()]
		var inv := tok.ends_with("'")
		var dbl := "2" in tok  # "2" 优先于 "'"(X2' ≡ X2 = 180°;与 cube.parse_alg 同口径)
		var angle := PI
		if not dbl:
			angle = PI / 2.0 if (inv or tok.ends_with("3")) else -PI / 2.0
		var lower := base.to_lower()
		if lower in ["y", "x", "z"]:  # 整体旋转:三层一步
			steps.append({"axis": axis, "layers": [cube.E, 0, -cube.E], "angle": angle})
		elif lower in ["m", "e", "s"]:  # 中层单层
			steps.append({"axis": axis, "layers": [0], "angle": angle})
		elif lower == base:  # 小写宽转:该面+相邻内层(layers 按 gp·axis 恒正)
			steps.append({"axis": axis, "layers": [cube.E, cube.E - 2], "angle": angle})
		else:  # 大写外层单层
			steps.append({"axis": axis, "layers": [cube.E], "angle": angle})
	return steps


func _on_train_new() -> void:
	if _cfop.is_empty() or not _cfop.has(_train_cat):
		_flash("CFOP 数据未加载(data/cfop.json)")
		return
	var pool: Array = _cfop[_train_cat]
	var case: Dictionary = pool[randi() % pool.size()]
	var steps := _cfop_steps(String(case.algs[0]))
	if steps.is_empty():
		_flash("该 case 公式无法解析")
		return
	# 从复原态逆向公式构造到该 case(瞬时),并清记账(出题不算玩家历史)
	for i in range(steps.size() - 1, -1, -1):
		cube.apply_turn(steps[i].axis, steps[i].layers, -steps[i].angle)
	cube._undo_stack.clear()
	cube.moves = 0
	cube.full_log.clear()
	_timer.invalidate()
	_train_case = case
	_train_case_cat = _train_cat  # key 冻结于出题时:切分类按钮不清 case,入账须记到出题分类
	_train_done = false
	_teach_best = 0  # 新 case = 新局:回退红基准清零
	_train_t0 = Time.get_ticks_msec()
	train_case_label.text = "%s · %s" % [_case_name(case), String(case.get("group", _train_cat))]
	train_alg_label.text = "参考公式:\n" + String(case.algs[0]).strip_edges()
	train_result_label.text = "把它复原!(不看公式)"
	_update_train_stat()
	train_new_btn.release_focus()


## 当前 case 统计(A-8,简版):出现次数/best/mean;无记录提示首次。
## 对 A-8 原文『best/mean/出现率统计表』的已声明取舍:出现率(需出题事件入账,
## 现仅完成时 record,无法计算)与跨案例统计表视图均未实现——进度统计 UI 按
## PLAN §16.3 留 P4 开工前专项 grill,本版仅交付当前 case 单行。
func _update_train_stat() -> void:
	if _train_case.is_empty():
		train_stat_label.text = ""
		return
	var s: Dictionary = _train_stats.stats(_train_case_id())
	if int(s.count) == 0:
		train_stat_label.text = "历史:首次挑战"
		return
	var best_s: float = int(s.best_ms) / 1000.0
	var mean_s: float = float(s.mean_ms) / 1000.0
	train_stat_label.text = "历史:%d 次 · best %.2fs · mean %.2fs" % [int(s.count), best_s, mean_s]


## case 名整型化:cfop.json 中 f2l/oll 的 name 是 JSON 数字,Godot 解析为 float 后
## str() 得 '6.0'——显示层与统计 key 统一取整数形('6';pll 的 name 本是字符串不受影响)。
func _case_name(c: Dictionary) -> String:
	var nm = c.get("name", "")
	if nm is float and nm == floorf(nm):
		return str(int(nm))
	return str(nm)


## 统计 key(跨分类同名 case 防串,如 f2l/1 与 oll/1)。分类取出题时冻结的
## _train_case_cat 而非当前 _train_cat——切分类不清当前 case,完成入账须记到出题分类。
func _train_case_id() -> String:
	return "%s/%s" % [_train_case_cat, _case_name(_train_case)]


func _on_train_show() -> void:
	if _train_case.is_empty():
		_flash("先随机出题")
		return
	var steps := _cfop_steps(String(_train_case.algs[0]))
	if cube.play_steps(steps) < 0:
		_flash("演示入队失败")
	train_show_btn.release_focus()


# ---- 主循环:UI 状态驱动 ----

func _flash(msg: String) -> void:
	_msg = msg
	_msg_until = Time.get_ticks_msec() / 1000.0 + 2.5


func _process(_delta: float) -> void:
	undo_btn.disabled = cube.is_programmatic() or cube.is_dragging()  # §4 打断矩阵
	play_btn.disabled = cube.is_programmatic() or _timer.is_running()  # §15.1:竞速不播公式
	# is_solved 边沿(仅稳定态判定):计时停表入账 / 训练完成(§15.1)
	if not cube.is_animating():
		var s: bool = cube.is_solved()
		if s and not _was_solved:
			if _mode == Mode.TIMER:
				_timer.on_solved()
				_flash("复原!成绩 %s" % _fmt_ms(_timer.elapsed_msec()))
				_refresh_timer_stats()
			elif _mode == Mode.TRAIN and not _train_case.is_empty() and not _train_done \
					and cube.moves > 0:
				# moves>0 = 出题后有玩家净操作(键盘/拖层 +1、undo -1;ALG 播放/REPLAY 不计步,
				# scramble/reset 完成后恒 0):挡住「MCP scramble+reset 把无关复原跳变记成
				# 0.02 秒伪成绩」与「代解 apply_alg 直达复原」——纯程序路径不产生玩家成绩。
				_train_done = true
				var ms := Time.get_ticks_msec() - _train_t0
				_train_stats.record(_train_case_id(), ms)  # A-8:完成即入账
				_update_train_stat()
				train_result_label.text = "完成!耗时 %.2f 秒 · 步数 %d" % [ms / 1000.0, cube.moves]
				_flash("训练完成!")
		_was_solved = s
	if Time.get_ticks_msec() / 1000.0 < _msg_until:
		status_label.text = _msg
	elif not cube.is_animating():  # 动画期不刷新判定文本,避免状态串跳变
		if cube.is_solved():
			status_label.text = "%s · 已还原 ✓ · 步数 %d" % [MODE_NAMES[_mode], cube.moves]
		else:
			status_label.text = "%s · 步数 %d" % [MODE_NAMES[_mode], cube.moves]
	if _mode == Mode.TIMER:
		var ms: int = _timer.elapsed_msec()
		time_label.text = _fmt_ms(ms)
		time_label.add_theme_color_override("font_color",
				Color(0.4, 0.95, 0.5) if _timer.is_running() else Color(1, 1, 1))
	if _mode == Mode.TEACH:
		if _auto_stage > 0 and not cube.is_animating() and not cube.is_programmatic():
			_auto_step()
		else:
			_teach_refresh()


## 「自动完成本阶段」驱动(§14.5):每轮动画结束后追加一条引擎建议,直至阶段通过。
func _auto_step() -> void:
	var sc: int = _teach_stage()
	if sc >= _auto_stage:
		_auto_stage = 0
		teach_auto_btn.text = "自动完成本阶段"
		_teach_refresh()
		_flash("阶段完成!")
		return
	var h := _teach_hint()
	var sug: Dictionary = h.get("suggestion", {})
	var alg := String(sug.get("alg", ""))
	if alg.is_empty() or cube.play_alg(alg) < 0:
		_auto_stage = 0
		teach_auto_btn.text = "自动完成本阶段"
		_flash("自动中止:引擎无建议")
