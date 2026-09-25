extends Node3D
## 魔方核心引擎(PLAN §3/§4)。视觉即状态:cubie 节点即数据,无贴纸置换表。
## 双入口:apply_turn 瞬时 bake(打乱/自测)/ enqueue_turn 动画(键盘、play_alg、restore 回放)。
## 坐标约定(§2):grid_pos 各分量 ∈ {-(n-1), ..., n-1} 步长 2,全整数转轴零浮点误差。

const FACES := [
	{"n": Vector3.UP, "off": Vector3i(-1, 1, -1), "row": Vector3i(0, 0, 1), "col": Vector3i(1, 0, 0), "color": Color(0.95, 0.95, 0.95)},  # U 0-8
	{"n": Vector3.RIGHT, "off": Vector3i(1, 1, 1), "row": Vector3i(0, -1, 0), "col": Vector3i(0, 0, -1), "color": Color(0.85, 0.12, 0.12)},  # R 9-17
	{"n": Vector3.BACK, "off": Vector3i(-1, 1, 1), "row": Vector3i(0, -1, 0), "col": Vector3i(1, 0, 0), "color": Color(0.10, 0.70, 0.25)},  # F 18-26
	{"n": Vector3.DOWN, "off": Vector3i(-1, -1, 1), "row": Vector3i(0, 0, -1), "col": Vector3i(1, 0, 0), "color": Color(0.95, 0.85, 0.10)},  # D 27-35
	{"n": Vector3.LEFT, "off": Vector3i(-1, 1, -1), "row": Vector3i(0, -1, 0), "col": Vector3i(0, 0, 1), "color": Color(0.95, 0.50, 0.05)},  # L 36-44
	{"n": Vector3.FORWARD, "off": Vector3i(1, 1, -1), "row": Vector3i(0, -1, 0), "col": Vector3i(-1, 0, 0), "color": Color(0.15, 0.35, 0.90)},  # B 45-53
]
const AXIS_OF := {"U": Vector3.UP, "R": Vector3.RIGHT, "F": Vector3.BACK,
		"D": Vector3.DOWN, "L": Vector3.LEFT, "B": Vector3.FORWARD}

const CUBIE_SIZE := 0.94
const STICKER_SIZE := 0.82
const STICKER_OFFSET := 0.471
const QUEUE_LIMIT := 8
const SNAP_THRESHOLD := PI / 12.0  # 15°:拖层松手回弹阈值(§13.4)

enum Kind { PLAYER, UNDO, ALG, REPLAY }

## cubie 节点:grid_pos 为格坐标,stickers 为 {局部法线 Vector3i -> color_id}。
class Cubie extends MeshInstance3D:
	var grid_pos := Vector3i.ZERO
	var stickers := {}

var n := 3
var E := 2  # n-1,外层条件 abs(分量) == E
## 公式播放/回放每步时长(A-5):可调 0.05~0.90 秒/步,赋值即 clamp(滑杆与代码同入口)。
## play_alg 与 restore 动画统一走 _start_turn,天然同受此值控制。
var turn_time: float = 0.18:
	set(v):
		turn_time = clampf(v, 0.05, 0.90)
var cubies := []  # Cubie;非类型化数组以动态访问 grid_pos(EXPERIENCE 坑)
var _grid := {}  # Vector3i -> Cubie
var pivot: Node3D
var _queue := []  # {axis: Vector3, layers: Array, angle: float, kind: int}
var _undo_stack := []  # {axis, layers, angle}
var full_log := []  # §1 决策 4:恒为"初始态→当前态"的全量路径
var moves := 0
var _busy := false
var _current_kind: int = Kind.PLAYER
var _tw: Tween
var _replaying := false
var _sticker_meshes := []
var _box_mesh: BoxMesh
var _dragging := false  # 拖层手势进行中(§4 矩阵"命令暂停"行:一切变更入口忽略)
var _drag_axis := Vector3.ZERO
var _drag_layers := []
var _drag_angle := 0.0


func _ready() -> void:
	setup(3)


## 参数化重建:n 阶生成 n³−(n−2)³ 个外露 cubie;清空队列/撤销栈/full_log/步数。
func setup(n_: int) -> void:
	_abort_active_turn()
	n = n_
	E = n - 1
	for c in cubies:
		c.free()
	cubies.clear()
	_grid.clear()
	_queue.clear()
	_undo_stack.clear()
	full_log.clear()
	moves = 0
	_replaying = false
	_ensure_shared_meshes()
	if pivot == null:
		pivot = Node3D.new()
		pivot.name = "Pivot"
		add_child(pivot)
	for x in range(-E, E + 1, 2):
		for y in range(-E, E + 1, 2):
			for z in range(-E, E + 1, 2):
				if absi(x) != E and absi(y) != E and absi(z) != E:
					continue  # 纯内部块,跳过(永不被选层)
				var c := _make_cubie(Vector3i(x, y, z))
				cubies.append(c)
				_grid[c.grid_pos] = c


## 瞬时转层:直接选层 bake,不经 pivot 与 tween。玩家语义:入撤销栈、moves+1、记 full_log。
func apply_turn(axis: Vector3, layers: Array, angle: float) -> void:
	_bake(axis, layers, angle)
	_undo_stack.push_back({"axis": axis, "layers": layers, "angle": angle})
	moves += 1
	full_log.append({"axis": axis, "layers": layers, "angle": angle})


## 键盘转层入口:入动画队列;队列满(>QUEUE_LIMIT)丢弃;程序化批次播放中忽略(G3);
## 拖层手势中忽略(§4 矩阵:命令暂停)。
func enqueue_turn(axis: Vector3, layers: Array, angle: float) -> bool:
	if _dragging or is_programmatic():
		return false
	return _enqueue(axis, layers, angle, Kind.PLAYER, false)


## 合法 WCA 记号 token:首字符 ∈ UDLRFB(n>=4 时追加小写 udlrfb = 双层宽转,§17.2,
## 小写合法性随阶数——3 阶拒绝),余下至多一个 ' 与至多一个 2,无其他字符
## (§4:"2" 优先于 "'",R2'/R'2 ≡ R2;R''/R22 等重复修饰符非法)。单一规则源,
## parse_alg 与 cube_server.validate_alg 共用,防两份实现漂移。
static func is_valid_wca_token(t: String, n: int = 3) -> bool:
	if t.is_empty() or t.length() > 3:
		return false
	var face := t[0]
	if not AXIS_OF.has(face):
		if n < 4 or not AXIS_OF.has(face.to_upper()):
			return false
		face = face.to_upper()
	var inv := false
	var dbl := false
	for i in range(1, t.length()):
		if t[i] == "'":
			if inv:
				return false
			inv = true
		elif t[i] == "2":
			if dbl:
				return false
			dbl = true
		else:
			return false
	return true


## 解析 WCA 记号(U D L R F B + ' + 2,"2" 优先于 "'";n>=4 追加小写宽转,双层一次动画)
## → 步数组;含非法 token 返回 []。
func parse_alg(alg: String) -> Array:
	var out := []
	for token in alg.split(" ", false):
		if not is_valid_wca_token(token, n):
			return []
		var face := token[0]
		var wide := face != face.to_upper()
		var axis: Vector3 = AXIS_OF[face.to_upper()]
		var inv := "'" in token
		var dbl := "2" in token
		var angle := PI if dbl else (-PI / 2.0 if not inv else PI / 2.0)
		# 宽转 = 该面 + 相邻内层两层一次动画(§17.2);layers 按 gp·axis 约定恒为正值
		var layers := [E, E - 2] if wide else [E]
		out.append({"axis": axis, "layers": layers, "angle": angle})
	return out


## 步数组直接批量入队(ALG 语义:不计步、不入撤销栈、记 full_log,追加语义)。
## 供 UI 程序化播放(CFOP 训练演示:整体旋转/宽转步不经字符串校验,由构造方保证合法);
## 非法输入(空步/缺键)整批拒绝。拖层手势中拒绝(§4 矩阵)。
func play_steps(steps: Array) -> int:
	if _dragging:
		return -1
	for s in steps:
		if not (s is Dictionary and s.has("axis") and s.has("layers") and s.has("angle")):
			return -1
	for s in steps:
		_enqueue(s.axis, s.layers, s.angle, Kind.ALG, true)
	return steps.size()


## 公式播放:解析+批量入队(不计步、不入撤销栈,记 full_log);非法记号返回 -1 零入队。
## 程序化批量入队不受队列上限约束(§1 队列上限只约束键盘)。
## 回放中追加合法(§4 追加矩阵):回放步先入队先执行,alg 步追加其后,
## 每条回放步 pop 一条 full_log,pop 不变式不受追加影响(教学演示连续下发不丢步)。
func play_alg(alg: String) -> int:
	if _dragging:
		return -1
	var steps := parse_alg(alg)
	if steps.is_empty():
		return -1
	for s in steps:
		_enqueue(s.axis, s.layers, s.angle, Kind.ALG, true)
	return steps.size()


## 撤销:原子性(§4)——先验队未满,满则整个拒绝;可入才"弹栈 + 入队"。moves-1,undo 步也入 full_log。
func undo() -> bool:
	if _dragging or _undo_stack.is_empty() or is_programmatic():
		return false
	if _queue.size() >= QUEUE_LIMIT:
		return false
	var t: Dictionary = _undo_stack.pop_back()
	_enqueue(t.axis, t.layers, -t.angle, Kind.UNDO, false)
	return true


## 瞬时打乱(v6.3,对齐 WCA tnoodle NxN 策略):random-move——外层/内层/宽层混合随机,
## 过滤同轴连续;步数对齐 WCA 官方(2 阶 11,3 阶 25,4 阶 40,5 阶 60,6 阶 80,7 阶 100),
## 显式 steps(测试/MCP)优先。可选注入 RandomNumberGenerator(A-6):同 seed 同步数下
## 打乱序列完全可复现;缺省 null 走全局 randi()(原行为,既有 seed()+scramble 确定性不变)。
## 完成清空撤销栈与步数(打乱步仍记 full_log)。
func scramble(steps: int = 0, rng: RandomNumberGenerator = null) -> void:
	if _dragging:
		return
	_abort_active_turn()
	if steps <= 0:
		steps = {2: 11, 3: 25, 4: 40, 5: 60, 6: 80, 7: 100}.get(n, 100)
	var prev := Vector3.ZERO
	var done := 0
	while done < steps:
		var axis: Vector3 = FACES[_rand_int(rng, FACES.size() - 1)].n
		if axis == prev:
			continue
		prev = axis
		var angle := PI / 2 if _rand_int(rng, 1) == 0 else -PI / 2
		apply_turn(axis, _random_layers(rng), angle)
		done += 1
	_undo_stack.clear()
	moves = 0


## 打乱随机源(A-6):rng 注入时取自该实例(不污染全局熵),缺省走全局 randi()。
## 返回 [0, hi] 含端点(与原 randi() % size 语义一致)。
func _rand_int(rng: RandomNumberGenerator, hi: int) -> int:
	return rng.randi_range(0, hi) if rng != null else randi() % (hi + 1)


## 随机层组(v6.3):3 阶及以下恒外层单层(键盘可复原,LBL 求解器假设中心定色,
## 中央层转动不可解);N≥4 单层(任意层,含奇数阶中央层,拖层可复原)或 2~3 层
## 连续宽转;宽层永不覆盖全部 n 层(整体旋转无打乱意义)。随机经注入的 rng(A-6)。
func _random_layers(rng: RandomNumberGenerator = null) -> Array:
	if n <= 3:
		return [E]
	if _rand_int(rng, 1) == 0:
		return [_rand_int(rng, n - 1) * 2 - (n - 1)]
	var w: int = 2 if n == 4 else 2 + _rand_int(rng, 1)
	var j: int = _rand_int(rng, n - w)
	var layers := []
	for i in w:
		layers.append((j + i) * 2 - (n - 1))
	return layers


## 回放还原(v5.1 pop 不变式):打断+清撤销栈+moves 归 0,不清 full_log;
## 逆序逐条取反入动画队列,每条回放步 bake 完成即从 full_log 尾部 pop 一条。
## 任意时刻被打断,剩余 full_log 自动就是剩余路径,restore 幂等。
func restore() -> void:
	if _dragging:
		return
	_abort_active_turn()
	_undo_stack.clear()
	moves = 0
	if full_log.is_empty():
		_replaying = false
		return
	_replaying = true
	var log_copy := full_log.duplicate()
	for i in range(log_copy.size() - 1, -1, -1):
		var t: Dictionary = log_copy[i]
		_enqueue(t.axis, t.layers, -t.angle, Kind.REPLAY, true)


## 瞬时重置:按当前阶重建,清空一切历史。拖层手势中忽略(§4 矩阵)。
func reset() -> void:
	if _dragging:
		return
	setup(n)


## 54 字节 URFDLB(3 阶语义),行列序按 §3.1 表。
func to_facelets() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(54)
	var i := 0
	for fi in FACES.size():
		var f: Dictionary = FACES[fi]
		for r in 3:
			for c in 3:
				var cub = _grid[_face_cell(fi, r, c)]
				var local := Vector3i((cub.basis.inverse() * Vector3(f.n)).round())
				out[i] = cub.stickers[local]
				i += 1
	return out


## 还原判定:按面查同色,不依赖中心块(NxN 通用)。
func is_solved() -> bool:
	for fi in FACES.size():
		var f: Dictionary = FACES[fi]
		var ref := -1
		for r in n:
			for c in n:
				var cub = _grid[_face_cell(fi, r, c)]
				var color: int = cub.stickers[Vector3i((cub.basis.inverse() * Vector3(f.n)).round())]
				if ref == -1:
					ref = color
				elif color != ref:
					return false
	return true


func is_animating() -> bool:
	return _busy or not _queue.is_empty()


## 程序化批次播放中(ALG/REPLAY 在队或执行中):UI 据此忽略键盘与 UndoBtn。
func is_programmatic() -> bool:
	if _busy and (_current_kind == Kind.ALG or _current_kind == Kind.REPLAY):
		return true
	for item in _queue:
		if item.kind == Kind.ALG or item.kind == Kind.REPLAY:
			return true
	return false


# ---- 拖层(PLAN §13,实时预览 + 松手 snap)----

func is_dragging() -> bool:
	return _dragging


## 拖层起手:锁定轴与层,层块 reparent 进 pivot 供实时预览。
## 起手条件(§13.1):队列空且非动画且非程序化播放;手势已进行或 layers 空则拒绝。
func begin_drag(axis: Vector3, layers: Array) -> bool:
	if _dragging or layers.is_empty() or is_animating() or is_programmatic():
		return false
	_dragging = true
	_drag_axis = axis
	_drag_layers = layers
	_drag_angle = 0.0
	for c in cubies:
		if _axis_value(c.grid_pos, axis) in layers:
			c.reparent(pivot, true)
	return true


## 拖层预览:pivot 实时旋转(无 tween),角度连续 clamp 到 ±180°。
## grid_pos 不前转,facelets/is_solved 恒为已 bake 状态(G2,§13.3)。
func update_drag(angle: float) -> void:
	if not _dragging:
		return
	_drag_angle = clampf(angle, -PI, PI)
	pivot.basis = Basis(_drag_axis, _drag_angle)


## 松手(§13.4):角度量化,<15° 回弹为 0(不算步、不记日志);非零量化角
## 经新 finish 路径一次性 bake 并按 PLAYER 语义记账(撤销栈+full_log+计步;
## 180° 一步一记,与 R2 口径一致)。返回量化角;未在拖层手势中返回 NAN。
func finish_drag() -> float:
	if not _dragging:
		return NAN
	var q := _snap_drag_angle(_drag_angle)
	_dragging = false
	_release_pivot()
	if q == 0.0:
		return 0.0
	_bake(_drag_axis, _drag_layers, q)
	var t := {"axis": _drag_axis, "layers": _drag_layers, "angle": q}
	_undo_stack.push_back(t)
	moves += 1
	full_log.append(t)
	return q


## 取消手势(Esc,§13.5):回弹归位,不 bake 不记任何账。
func cancel_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	_release_pivot()


## snap(P1.5 实现裁决):|a| < 15° → 0(回弹);否则取最近 90° 倍数,
## 落在 0(15°~45° 区间)时升到 ±90° —— 16° 取 90°,45° 取 90°(round 半开远离零)。
func _snap_drag_angle(a: float) -> float:
	if absf(a) < SNAP_THRESHOLD:
		return 0.0
	var q := roundf(a / (PI / 2.0)) * (PI / 2.0)
	if q == 0.0:
		q = PI / 2.0 * signf(a)
	return q


## 拖层收尾公共:层块 reparent 回自身(keep_global=false,局部值即未转原位),
## pivot 复位。回弹与 cancel 走此归位;非零 snap 随后由 _bake 精确覆盖。
func _release_pivot() -> void:
	for c in pivot.get_children():
		c.reparent(self, false)
	pivot.basis = Basis()


# ---- 内部 ----

func _make_cubie(gp: Vector3i) -> Cubie:
	var c := Cubie.new()
	c.grid_pos = gp
	c.position = Vector3(gp) * 0.5
	c.mesh = _box_mesh
	for fi in FACES.size():
		var f: Dictionary = FACES[fi]
		var normal: Vector3 = f.n
		if int(gp.x * normal.x + gp.y * normal.y + gp.z * normal.z) == E:
			var s := MeshInstance3D.new()
			s.mesh = _sticker_meshes[fi]
			s.position = normal * STICKER_OFFSET
			s.basis = Basis(Quaternion(Vector3.UP, normal))  # PlaneMesh 朝 +Y,转向法线
			c.add_child(s)
			c.stickers[Vector3i(normal)] = fi
	add_child(c)
	return c


func _ensure_shared_meshes() -> void:
	if _box_mesh != null:
		return
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE * CUBIE_SIZE
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.07, 0.07, 0.07)
	_box_mesh.material = bm
	for f in FACES:
		var pm := PlaneMesh.new()
		pm.size = Vector2.ONE * STICKER_SIZE
		var m := StandardMaterial3D.new()
		m.albedo_color = f.color
		pm.material = m
		_sticker_meshes.append(pm)


## bake 数学(§4 步骤 3,瞬时/动画共用):精确值覆盖,grid 字典同步。
## 两阶段:先 erase 全部转层块旧键再统一写回,避免块间新/旧键交错互删。
func _bake(axis: Vector3, layers: Array, angle: float) -> void:
	var R := Basis(axis, angle)
	var moving := []
	for c in cubies:
		if _axis_value(c.grid_pos, axis) in layers:
			moving.append(c)
			_grid.erase(c.grid_pos)
	for c in moving:
		c.basis = R * c.basis
		c.position = (R * c.position).snapped(Vector3.ONE * 0.5)
		c.grid_pos = Vector3i((R * Vector3(c.grid_pos)).round())
		_grid[c.grid_pos] = c


func _enqueue(axis: Vector3, layers: Array, angle: float, kind: int, bypass_limit: bool) -> bool:
	if not bypass_limit and _queue.size() >= QUEUE_LIMIT:
		return false
	_queue.push_back({"axis": axis, "layers": layers, "angle": angle, "kind": kind})
	return true


func _process(_delta: float) -> void:
	if _dragging:
		return  # 拖层手势中挡队列推进(§4 矩阵"命令暂停"行)
	if _busy or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_busy = true
	_current_kind = item.kind
	_start_turn(item)


## 动画路径(§4):1 选层 reparent → 2 tween 演出 → 3 bake → 4 复位。
## 动画期不清 _grid 条目(§6.2 G2):保留的是"已 bake"键,to_facelets/is_solved 全程可查;
## 前转统一由 _finish_turn 的 _bake 两阶段(先擦旧键再写新键)完成。
func _start_turn(item: Dictionary) -> void:
	var axis: Vector3 = item.axis
	var layers: Array = item.layers
	var angle: float = item.angle
	for c in cubies:
		if _axis_value(c.grid_pos, axis) in layers:
			c.reparent(pivot, true)
	_tw = create_tween()
	_tw.tween_method(func(t: float) -> void: pivot.basis = Basis(axis, angle * t), 0.0, 1.0, turn_time)
	_tw.finished.connect(_finish_turn.bind(item), CONNECT_ONE_SHOT)


func _finish_turn(item: Dictionary) -> void:
	for c in pivot.get_children():
		# keep_global=false:basis 保持未转的局部值(§4 bake 数学),随后 _bake 精确值覆盖,
		# 若保留全局变换会把 pivot 中间旋转吸收进 basis 造成双重旋转。
		c.reparent(self, false)
	pivot.basis = Basis()
	_bake(item.axis, item.layers, item.angle)  # 此时 grid_pos 仍是旧键,选层/擦键恰好命中
	_busy = false
	_commit(item)


## 步执行完成后的记帐(bake 后):玩家/撤销计步,回放步 pop full_log(G1)。
func _commit(item: Dictionary) -> void:
	var t := {"axis": item.axis, "layers": item.layers, "angle": item.angle}
	match int(item.kind):
		Kind.PLAYER:
			_undo_stack.push_back(t)
			moves += 1
			full_log.append(t)
		Kind.UNDO:
			moves -= 1
			full_log.append(t)
		Kind.ALG:
			full_log.append(t)
		Kind.REPLAY:
			if not full_log.is_empty():
				full_log.pop_back()
			if full_log.is_empty():
				_replaying = false


## 打断(scramble/reset/restore 入口):kill tween + 清队列;救援 pivot 中半转块,逆中间角精确归位,
## 使"该步既未执行也未记 log",状态与 full_log 自洽(pop 不变式)。
## 注意:动画期 grid_pos 从未前转(前转只发生在 _finish_turn/_bake),仍是该步之前的旧键,
## 因此此处禁止旋转 grid_pos,只恢复视觉并以原键写回 _grid。
func _abort_active_turn() -> void:
	_queue.clear()
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if _busy:
		var Rinv := pivot.basis.inverse()
		for c in pivot.get_children():
			c.reparent(self, true)
			c.basis = Rinv * c.basis
			c.position = (Rinv * c.position).snapped(Vector3.ONE * 0.5)
			_grid[c.grid_pos] = c
		pivot.basis = Basis()
		_busy = false
	_replaying = false


## §3.1 行列序:面首格 off*E + 行步*2r + 列步*2c。
func _face_cell(fi: int, r: int, c: int) -> Vector3i:
	var f: Dictionary = FACES[fi]
	return Vector3i(f.off) * E + Vector3i(f.row) * (2 * r) + Vector3i(f.col) * (2 * c)


## layers 值约定 = gp·axis(§2 坐标):任意轴上其外层块的点积恒为 +E(负轴如 DOWN,
## D 层块 y=-E,gp·axis = -y = +E)。修复前返回 sum*E 使负轴(D/L/B)parse_alg/scramble
## 转到对面层——正轴断言/自洽回放测试测不出,教学引擎交叉验证暴露(整合期修复)。
func _outer_layer(axis: Vector3) -> int:
	return E


func _axis_value(gp: Vector3i, axis: Vector3) -> int:
	return int(gp.x * axis.x + gp.y * axis.y + gp.z * axis.z)
