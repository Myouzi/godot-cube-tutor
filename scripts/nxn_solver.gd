extends RefCounted
## NxN 教学引擎(v7,docs/v7-teach-nxn-plan.md)。统一入口按 facelets 长度分派,
## 调用方无分派逻辑:24 字节 = 2 阶独立初学者法(本文件);54 字节 = 3 阶转调
## lbl_solver(架构红线:lbl_solver.gd 零改动);96-294 字节 = 4-7 阶降阶法
## 全链(P5):中心段 P3/P4b → 组棱段 P4a/P4b → parity 修正(P5,仅偶数阶,
## 并入组棱段尾)→ 约化提取 3 阶 54 态 → lbl_solver.solve,9 段定长契约;
## 其余长度返回 ok:false 兜底,不落在 lbl_solver 上(n 阶 facelet 模拟器
## 已随 P2 通用 6n²)。
##
## 2 阶三段(初学者法,白底姿态与 lbl_solver 同框:U=白 D=黄):
##   1 白面四角:四个白角归位进 U 层(位置 + 朝向 + 侧色)。
##   2 黄面:四个黄角翻成黄面朝下(OLL,允许黄角在 D 层内换位)。
##   3 角块归位:D 层角块轮换归位 → 六面同色即复原。
## 复原口径 = 六面同色、朝向无关(cube.gd is_solved 同款;2 阶无中心,
## 整体旋转等价的复原态 stage_check/hint 同样判 3)。
##
## 骨架平移 lbl_solver._corner_segment:模板 × 槽位旋转(_rotate_alg)× 摆位前缀
## (D^j)→ 模拟-验证 → 评分单调(已归位白角数不降 ∧ 已归位白角保持)。
## 公式池 7 条(项目姿态直存,stage 3 逆公式程序生成),每条先在本文件 24 facelet
## 模拟器上验证语义(作用槽唯一 / U 层保持 / 朝向保持)再入池,
## 由 tests/test_nxn_2x2.gd 金标准兜底。

const LBL := preload("res://scripts/lbl_solver.gd")
const CUBE := preload("res://scripts/cube.gd")  # token 文法单一规则源(_parse_wca_token)

const MOVE_LIMIT := 120       # solve 步数上限(对发散/死循环的保险丝;2026-09-25 实测
                              # 300 态最坏 74 步、金标准门 95,见 tests/test_nxn_2x2.gd)
const STAGE_GUARD := 60       # 单阶段段数上限(2 阶每段 3-8 步,宽裕 10 倍)

const STAGE_NAMES := ["白面四角", "黄面", "角块归位"]
const STAGE_TIPS := [  # 教学侧栏每阶段一句要领(按本项目朝向 U=白 撰写,随表导出)
	"把四个白色角块带进白面归位,侧面两色与相邻面颜色对齐。",
	"把黄层翻成黄面朝下:摆好位置做小鱼公式,一到两次。",
	"黄层四个角轮换归位:顺着转圈换,六面同色即复原。",
]

const WHITE := 0
const YELLOW := 3

## 面定义(off/row/col 与 cube.gd FACES 几何同源,
## row/col 已含 2 步长;行列序沿用 §3.1 表,3 阶 54 字节与旧版逐字节同构)。
## n 阶 cell 表按此几何生成:坐标 = off*E + row*r + col*c(E=n-1,r/c ∈ n),
## 与 cube.gd _face_cell 同式;n=2 时与旧 2 阶定义逐格一致。
const FACES_DEF := [
	{"n": Vector3(0, 1, 0), "off": Vector3(-1, 1, -1), "row": Vector3(0, 0, 2), "col": Vector3(2, 0, 0)},   # U 0-3
	{"n": Vector3(1, 0, 0), "off": Vector3(1, 1, 1), "row": Vector3(0, -2, 0), "col": Vector3(0, 0, -2)},   # R 4-7
	{"n": Vector3(0, 0, 1), "off": Vector3(-1, 1, 1), "row": Vector3(0, -2, 0), "col": Vector3(2, 0, 0)},   # F 8-11
	{"n": Vector3(0, -1, 0), "off": Vector3(-1, -1, 1), "row": Vector3(0, 0, -2), "col": Vector3(2, 0, 0)}, # D 12-15
	{"n": Vector3(-1, 0, 0), "off": Vector3(-1, 1, -1), "row": Vector3(0, -2, 0), "col": Vector3(0, 0, 2)}, # L 16-19
	{"n": Vector3(0, 0, -1), "off": Vector3(1, 1, -1), "row": Vector3(0, -2, 0), "col": Vector3(-2, 0, 0)}, # B 20-23
]

## 角位名 -> 三个 facelet 下标(面序与 lbl_solver 一致:U/D 面格在前);
## solved 时三格颜色。2 阶全部块都是角块,八位与 lbl CORNER_COLORS 逐位同色。
const CORNERS := {
	"UFR": [3, 4, 9], "UFL": [2, 8, 17], "ULB": [0, 16, 21], "UBR": [1, 20, 5],
	"DFR": [13, 11, 6], "DLF": [12, 19, 10], "DBL": [14, 23, 18], "DRB": [15, 7, 22],
}
const CORNER_COLORS := {
	"UFR": [0, 1, 2], "UFL": [0, 2, 4], "ULB": [0, 4, 5], "UBR": [0, 5, 1],
	"DFR": [3, 2, 1], "DLF": [3, 4, 2], "DBL": [3, 5, 4], "DRB": [3, 1, 5],
}

const U_CORNERS := ["UFR", "UFL", "ULB", "UBR"]
const D_CORNERS := ["DFR", "DLF", "DBL", "DRB"]

## 公式表(项目姿态记号直存,不经 remap;触发条件由「模拟-验证」运行时判定):
##   1 白面四角:基础槽 UFL,白角已由 D^j 转到槽位正下——白朝侧两种三步插入 /
##     白朝下八步先立后插;白角卡在白面错槽 = 顶出,复用任一条
##   2 黄面:小鱼 / 反小鱼(作用于 D 面,U 层白角保持)
##   3 角块归位:D 层三角换(逆公式程序生成,防笔误)
const FORMULAS_SRC := {
	1: [  # 朝向语义 2026-09-25 在本文件 24 facelet 模型上实测:三步两条分别对应
		    # 槽位正下白朝左 / 白朝前,八步条对应白朝下(先立后插)
		{"alg": "L D L' D'", "text": "白角已转到槽位正下、白面朝左:三步带上白面",
				"text_eject": "白角卡在白面错槽:先用三步公式把它带回黄层"},
		{"alg": "F' D' F", "text": "白角已转到槽位正下、白面朝前:三步带上白面",
				"text_eject": "白角卡在白面错槽:先用三步公式把它带回黄层"},
		{"alg": "L D2 L' D' L D L'", "text": "白角白面朝下:先立起来,再插进白面",
				"text_eject": "白角卡在白面错槽:用插入公式把它顶回黄层再重插"},
	],
	2: [
		{"alg": "L D L' D L D2 L'", "text": "小鱼公式:摆好位置做,把黄面翻成全黄"},
		{"alg": "L D2 L' D' L D' L'", "text": "反小鱼公式:摆好位置做,把黄面翻成全黄"},
	],
	3: [
		{"alg": "R F' R B2 R' F R B2 R2", "text": "黄面朝下:三个角顺着转圈换归位,位置对的角不用管"},
	],
}

# ---- 运行期缓存(static,lazy 初始化,按 n 键控)----
static var _cells: Dictionary = {}     # n -> Array[{c: Vector3 坐标, n: Vector3 法线}](6n²,序同 to_facelets)
static var _perm: Dictionary = {}      # n -> {层键: PackedInt32Array}:一次 90° 顺时针层置换(new[j] = old[perm[j]])
static var _formulas: Dictionary = {}  # stage -> Array[{alg, text, text_eject?, slot0..3?}](仅 2 阶公式表)
static var _ready := false


# ================================ n 阶 facelet 模拟器(6n²) ================================

## 2 阶公式表装载(_apply_token/solve/hint 直调私有接口的幂等入口)。
static func _ensure() -> void:
	if _ready:
		return
	_ready = true  # 先置位:slot 预计算内部 _apply_alg 重入直接返回(cell/置换表在 _ensure_n)
	# 公式表装载(stage 3 逆公式程序生成)
	for s in FORMULAS_SRC:
		var arr: Array = []
		for item in FORMULAS_SRC[s]:
			var rec := {"alg": String(item.alg), "text": String(item.text)}
			if item.has("text_eject"):
				rec["text_eject"] = String(item.text_eject)
			arr.append(rec)
		_formulas[s] = arr
	_formulas[3].append({"alg": LBL.invert_alg(String(_formulas[3][0].alg)), "text": "黄面朝下:三个角反方向转圈换归位"})
	# stage 1 各 rotate 档的「作用槽」(solved 态应用后被换出的白角位),供顶出/插入前置过滤
	var solved := PackedByteArray()
	solved.resize(24)
	for i in 24:
		solved[i] = i / 4
	for rec in _formulas[1]:
		for kt in 4:
			var t: PackedByteArray = solved.duplicate()
			_apply_alg(t, LBL._rotate_alg(String(rec.alg), kt))
			var slot := ""
			for name in U_CORNERS:
				if not _corner_solved(t, name):
					slot = name
					break
			rec["slot%d" % kt] = slot


## n 阶 cell 坐标表(FACES_DEF 几何 × n,见 FACES_DEF 注释;按 n 键控)。
static func _ensure_n(n: int) -> void:
	if _cells.has(n):
		return
	var e: int = n - 1  # E,外层层值(与 cube.gd 同名约定)
	var cells: Array = []
	for fi in 6:
		var f: Dictionary = FACES_DEF[fi]
		var off: Vector3 = f.off
		var row: Vector3 = f.row
		var col: Vector3 = f.col
		var nor: Vector3 = f.n
		for r in n:
			for c in n:
				cells.append({
					"c": off * e + row * r + col * c,
					"n": nor,
				})
	_cells[n] = cells


## 一次 90° 顺时针的层置换(层 = cell·axis ∈ layers,层值约定 gp·axis 与 cube.gd
## 一致、含负轴面;Basis(axis, -PI/2) 与 cube.gd bake 数学同源),按 (n, 轴, 层值组)
## 键控缓存;new[j] = old[perm[j]]。
static func _get_perm(n: int, axis: Vector3, layers: Array) -> PackedInt32Array:
	_ensure_n(n)
	if not _perm.has(n):
		_perm[n] = {}
	var key := "%s|%s" % [axis, layers]
	var table: Dictionary = _perm[n]
	if table.has(key):
		return table[key]
	var cells: Array = _cells[n]
	var total: int = cells.size()
	var rot := Basis(axis, -PI / 2.0)
	var perm := PackedInt32Array()
	perm.resize(total)
	for i in total:
		var cell: Dictionary = cells[i]
		var v: int = int(cell.c.dot(axis))
		if not layers.has(v):
			perm[i] = i
			continue
		var nc: Vector3 = (rot * (cell.c as Vector3)).round()
		var nn: Vector3 = (rot * (cell.n as Vector3)).round()
		var j := -1
		for k in total:
			if cells[k].c == nc and cells[k].n == nn:
				j = k
				break
		perm[j] = i  # 新位置 j 的值来自旧位置 i
	table[key] = perm
	return perm


## facelets 长度 → 阶数(6n²);非法长度返回 0。
static func _facelets_n(size: int) -> int:
	var n: int = int(round(sqrt(size / 6.0)))
	return n if 6 * n * n == size else 0


## 记号 → 层置换应用(6n² 通用;token 文法复用 cube.gd _parse_wca_token 单一规则源:
## 外层 R'/R2、内层 dR、宽层 dRw、小写双层,与 parse_alg 完全同门槛,非法 token 原地不动)。
## 倍数语义:2 = 顺时针 ×2、' = 顺时针 ×3(基准顺时针与 cube bake 同向)。
static func _apply_token(f: PackedByteArray, token: String) -> void:
	_ensure()  # 2 阶公式表 lazy 装载(测试可能直调私有接口;幂等)
	var n: int = _facelets_n(f.size())
	if n < 2:
		return
	var step: Dictionary = CUBE._parse_wca_token(token, n)
	if step.is_empty():
		return
	var times := 1
	if step.angle == PI:
		times = 2
	elif step.angle > 0.0:
		times = 3  # +PI/2 逆时针 = 顺时针 ×3
	var p: PackedInt32Array = _get_perm(n, step.axis, step.layers)
	for t in times:
		var old := f.duplicate()
		for j in f.size():
			f[j] = old[p[j]]


static func _apply_alg(f: PackedByteArray, alg: String) -> void:
	for token in alg.split(" ", false):
		if not token.is_empty():
			_apply_token(f, token)


static func _u_pow(k: int) -> String:
	return ["", "U", "U2", "U'"][k % 4]


static func _d_pow(k: int) -> String:
	return ["", "D", "D2", "D'"][k % 4]


# ================================ 块查询 ================================

static func _corner_solved(f: PackedByteArray, name: String) -> bool:
	var idx: Array = CORNERS[name]
	var col: Array = CORNER_COLORS[name]
	return f[idx[0]] == col[0] and f[idx[1]] == col[1] and f[idx[2]] == col[2]


## 朝向无关定位:三色集合匹配的角块所在位名。
static func _find_corner(f: PackedByteArray, colors: Array) -> String:
	for name in CORNERS:
		var idx: Array = CORNERS[name]
		var s := {f[idx[0]]: true, f[idx[1]]: true, f[idx[2]]: true}
		if s.size() == 3 and s.has(colors[0]) and s.has(colors[1]) and s.has(colors[2]):
			return name
	return ""


# ================================ 阶段判定 ================================

## 单阶段完成判定(不含前缀蕴含;stage_check 负责连续前缀)。
static func _done(f: PackedByteArray, stage: int) -> bool:
	match stage:
		1:  # 白面四角:白角归位(位置 + 朝向 + 侧色)
			for c in U_CORNERS:
				if not _corner_solved(f, c):
					return false
			return true
		2:  # 黄面:D 面 4 格黄(朝向;黄角可仍在 D 层内换位)
			for i in range(12, 16):
				if f[i] != YELLOW:
					return false
			return true
		3:  # 角块归位 -> 六面同色(复原口径,朝向无关)
			return _all_faces_uniform(f)
	return false


## 复原口径:六面各自同色,不依赖配色方位(2 阶无中心,is_solved 同款)。
static func _all_faces_uniform(f: PackedByteArray) -> bool:
	for fi in 6:
		var ref: int = f[fi * 4]
		for k in 4:
			if f[fi * 4 + k] != ref:
				return false
	return true


## stage_check:最大连续完成前缀;六面同色直接判 3(整体旋转等价复原态)。
## 96-294 字节 = 4-7 阶 9 段契约(P5):中心未解 0;中心已解棱组未完 1;组棱段
## (含 parity 清理——偶数阶判据未清仍判 1,parity 段语义并入组棱段尾)完成 →
## 约化提取 54 态判 LBL 前缀 +2(lsc 0..7 → sc 2..9)。
static func stage_check(facelets: PackedByteArray) -> int:
	if facelets.size() == 54:
		return LBL.stage_check(facelets)
	if facelets.size() == 6 * CENTER_N * CENTER_N:
		_ensure_centers()
		if not _centers_uniform(facelets):
			return 0
		_ensure_edges()
		if _edges_paired(_wing_state_of(facelets)) < 12:
			return 1
		if _parity_has(facelets, CENTER_N):
			return 1
		return LBL.stage_check(_reduce_to_54(facelets, CENTER_N)) + 2
	var n5: int = _facelets_n(facelets.size())
	if n5 >= 5 and n5 <= 7:
		if not _cn_uniform(facelets, n5):
			return 0
		var ctx: Dictionary = _pr_ensure(n5)
		var st := _pr_state_of(facelets, n5)
		if not _pr_state_ok(st) or _pr_score(st, ctx).x < 12:
			return 1
		if _parity_has(facelets, n5):
			return 1
		return LBL.stage_check(_reduce_to_54(facelets, n5)) + 2
	if facelets.size() != 24:
		return -1
	_ensure()
	if _all_faces_uniform(facelets):
		return 3
	var k := 0
	for s in range(1, 4):
		if _done(facelets, s):
			k = s
		else:
			break
	return k


## 前缀进度保持:阶段 s 的段执行后,阶段 1..s-1 必须仍完成。
static func _prefix_kept(f: PackedByteArray, stage: int) -> bool:
	for k in range(1, stage):
		if not _done(f, k):
			return false
	return true


## 白角进度保持:已归位白角在段执行后不得被拆(f -> f2)。
static func _white_kept(f: PackedByteArray, f2: PackedByteArray) -> bool:
	for c in U_CORNERS:
		if _corner_solved(f, c) and not _corner_solved(f2, c):
			return false
	return true


static func _solved_white_corners(f: PackedByteArray) -> int:
	var n := 0
	for c in U_CORNERS:
		if _corner_solved(f, c):
			n += 1
	return n


static func _yellow_down_count(f: PackedByteArray) -> int:
	var n := 0
	for i in range(12, 16):
		if f[i] == YELLOW:
			n += 1
	return n


static func _solved_d_corners(f: PackedByteArray) -> int:
	var n := 0
	for c in D_CORNERS:
		if _corner_solved(f, c):
			n += 1
	return n


# ================================ 段生成(骨架平移 _corner_segment) ================================

## 单段:{alg, piece, text} 或 {}(卡死兜底,由测试抓)。
static func _segment(f: PackedByteArray, stage: int) -> Dictionary:
	if stage == 1:
		return _white_segment(f)
	return _bfs_segment(f, stage, _stage_actions(stage))


## stage 2/3 的动作集:D^k 摆位 + 公式(摆位由模拟枚举确定)。
static func _stage_actions(stage: int) -> Array:
	var actions: Array = []
	for k in 4:
		var pre := _d_pow(k)
		for item in _formulas[stage]:
			var alg: String = String(item.alg)
			actions.append((pre + " " if pre != "" else "") + alg)
	return actions


## 阶段 1 白角:U 层卡角(错槽/拧转)→ 槽位旋转公式顶出;D 层游走 → D^j 预对位 +
## 槽位旋转插入。基础槽 = UFL;_rotate_alg 覆盖 4 个 U 槽,方向由模拟-验证筛选。
## 顶出按「顺带归位白角数」评分单调,平局取短段。
static func _white_segment(f: PackedByteArray) -> Dictionary:
	for target in U_CORNERS:
		if _corner_solved(f, target):
			continue
		var best := {}
		var colors: Array = CORNER_COLORS[target]
		var pos := _find_corner(f, colors)
		for item in _formulas[1]:
			var base: String = String(item.alg)
			for kt in 4:
				var slot: String = String(item.get("slot%d" % kt, ""))
				if pos in U_CORNERS:
					if slot != pos:
						continue  # 顶出:公式必须作用角所在槽
					# 顶出:D^j 前缀控制换入槽的白角,优先「顺带归位其他白角」的组合
					for j in 4:
						var pre := _d_pow(j)
						var alg: String = (pre + " " if pre != "" else "") + LBL._rotate_alg(base, kt)
						var t := f.duplicate()
						_apply_alg(t, alg)
						if not _white_kept(f, t):
							continue
						if _find_corner(t, colors) in D_CORNERS:
							var score := _solved_white_corners(t)
							var cur: int = int(best.get("score", -1))
							if score > cur or (score == cur and alg.length() < int(best.get("len", 999))):
								best = {"alg": alg, "piece": target, "text": String(item.text_eject),
										"score": score, "len": alg.length()}
				else:
					if slot != target:
						continue  # 插入:公式必须作用目标槽
					# 插入:D^j 预对位(角转基础槽正下)+ 槽位旋转公式
					for j in 4:
						var pre := _d_pow(j)
						var alg2: String = (pre + " " if pre != "" else "") + LBL._rotate_alg(base, kt)
						var t2 := f.duplicate()
						_apply_alg(t2, alg2)
						if _white_kept(f, t2) and _corner_solved(t2, target):
							return {"alg": alg2, "piece": target, "text": String(item.text)}
		if not best.is_empty():
			best.erase("score")
			best.erase("len")
			return best
	return {}


## 阶段 2-3 的 BFS 段:深度 ≤4(搜索预算上限;BFS 按最短优先返回),目标 =
## 该阶段完成且前缀保持;返回 {alg, piece, text} 或 {}。
static func _bfs_segment(f: PackedByteArray, stage: int, actions: Array) -> Dictionary:
	var queue: Array = [[f, []]]
	var visited := {_key(f): true}
	var depth := 0
	while not queue.is_empty() and depth < 4:
		depth += 1
		var next: Array = []
		for entry in queue:
			var cur: PackedByteArray = entry[0]
			var path: Array = entry[1]
			for a in actions:
				var alg: String = String(a)
				var t: PackedByteArray = cur.duplicate()
				_apply_alg(t, alg)
				var key: int = _key(t)
				if visited.has(key):
					continue
				visited[key] = true
				var path2 := path.duplicate()
				path2.append(alg)
				if _done(t, stage) and _prefix_kept(t, stage):
					return {
						"alg": " ".join(path2),
						"piece": _new_piece(f, t, stage),
						"text": _bfs_text(stage, path2.size()),
					}
				next.append([t, path2])
		queue = next
	return {}


## BFS 去重键。
static func _key(f: PackedByteArray) -> int:
	return hash(f)


static func _bfs_text(stage: int, count: int) -> String:
	match stage:
		2:
			return "摆好位置做小鱼公式,黄面翻成全黄(共 %d 次)" % count
		3:
			return "黄面朝下转圈换角,轮换归位(共 %d 次)" % count
	return ""


## 段后新达成的角位名(hint 的 piece;找不到给阶段首个目标位)。
static func _new_piece(before: PackedByteArray, after: PackedByteArray, stage: int) -> String:
	match stage:
		2:
			for c in D_CORNERS:
				if after[CORNERS[c][0]] == YELLOW and before[CORNERS[c][0]] != YELLOW:
					return c
			return D_CORNERS[0]
		3:
			for c in D_CORNERS:
				if _corner_solved(after, c) and not _corner_solved(before, c):
					return c
			return D_CORNERS[0]
	return ""


# ================================ solve / hint(§6.2 契约) ================================

## solve:{ok, alg, stages:[{name, alg}], moves};卡住/超上限/长度非法返回 ok:false。
## 54 字节 = 3 阶转调 lbl_solver(统一入口,调用方无分派);24 字节 = 2 阶三段;
## 96-294 字节 = 4-7 阶全链(P5):中心段 → 组棱段 → parity 修正(并入组棱段尾)
## → 约化提取 54 态 → lbl_solver.solve,9 段定长。
static func solve(facelets: PackedByteArray) -> Dictionary:
	if facelets.size() == 54:
		return LBL.solve(facelets)
	var n5: int = _facelets_n(facelets.size())
	if n5 >= 4 and n5 <= 7:
		return _nxn_solve(facelets, n5)
	if facelets.size() != 24:
		return {"ok": false, "alg": "", "stages": [], "error": "facelets 须 24(2 阶)/54(3 阶)/96-294(4-7 阶)字节"}
	_ensure()
	var fs := facelets.duplicate()
	var stages: Array = []
	var all: Array = []
	var total := 0
	for s in range(1, 4):
		var segs: Array = []
		var guard := 0
		while not _done(fs, s):
			guard += 1
			if guard > STAGE_GUARD or total >= MOVE_LIMIT:
				return {"ok": false, "alg": "", "stages": [], "error": "阶段 %d 卡住或超 %d 步上限" % [s, MOVE_LIMIT]}
			var seg := _segment(fs, s)
			if seg.is_empty():
				return {"ok": false, "alg": "", "stages": [], "error": "阶段 %d 无法生成进展段" % s}
			_apply_alg(fs, String(seg["alg"]))
			total += LBL._token_count(String(seg["alg"]))
			segs.append(String(seg["alg"]))
			all.append(String(seg["alg"]))
		stages.append({"name": STAGE_NAMES[s - 1], "alg": LBL._simplify_alg(" ".join(segs))})
	var total_alg := LBL._simplify_alg(" ".join(all))
	return {"ok": true, "alg": total_alg, "stages": stages, "moves": LBL._token_count(total_alg)}


## 阶段内进度:进行中阶段(sc+1)的已完成角块比例 0.0~1.0。
static func _progress(f: PackedByteArray, sc: int) -> float:
	if f.size() == 6 * CENTER_N * CENTER_N:  # 4 阶(P3/P4a):0 = 中心比例,1 = 配对棱比例
		if sc == 1:
			_ensure_edges()
			return _edges_paired(_wing_state_of(f)) / 12.0
		return _centers_placed(_center_state_of(f)) / 24.0
	var n5: int = _facelets_n(f.size())
	if n5 >= 5 and n5 <= 7:  # 5-7 阶(P4b):0 = 中心比例,1 = 已组块比例(组棱期)
		if sc == 1:
			return _pr_progress(f, n5)
		return float(_cn_placed(_cn_state_of(f, n5), (n5 - 2) * (n5 - 2))) / float(6 * (n5 - 2) * (n5 - 2))
	match sc:
		0:  # 进行 1:白面四角
			return _solved_white_corners(f) / 4.0
		1:  # 进行 2:黄面
			return _yellow_down_count(f) / 4.0
		2:  # 进行 3:角块归位
			return _solved_d_corners(f) / 4.0
	return 1.0


## hint:{stage(0..9,stage_check 口径), progress, suggestion:{piece, alg, text}}。
## stage=9 已复原,suggestion 为完成文案;否则建议针对阶段 max(1, stage+1)。
## 96-294 字节 = 4-7 阶(P5):统一 _nxn_hint(sc 0/1 分段建议;≥2 = LBL 边界,
## parity 预判 → 修正建议,无 parity → 约化提取 lbl_solver.hint 透传)。
static func hint(facelets: PackedByteArray) -> Dictionary:
	if facelets.size() == 54:
		return LBL.hint(facelets)
	var n5: int = _facelets_n(facelets.size())
	if n5 >= 4 and n5 <= 7:
		return _nxn_hint(facelets, n5)
	if facelets.size() != 24:
		return {"stage": -1, "progress": 0.0, "suggestion": {}, "error": "facelets 须 24(2 阶)/54(3 阶)/96-294(4-7 阶)字节"}
	_ensure()
	var sc := stage_check(facelets)
	var progress := _progress(facelets, sc)
	if sc == 3:
		return {"stage": 3, "progress": 1.0,
				"suggestion": {"piece": "", "alg": "", "text": "魔方已复原"}}
	var s := 1 if sc == 0 else sc + 1
	if s == 1:
		# 白角建议:拼接段直到该 piece 真正归位(顶出段本身不归位)
		var t := facelets.duplicate()
		var parts: Array = []
		var piece := ""
		var text := ""
		for i in 12:
			var seg := _white_segment(t)
			if seg.is_empty():
				break
			_apply_alg(t, String(seg["alg"]))
			if parts.is_empty():
				piece = String(seg["piece"])
				text = String(seg["text"])
			parts.append(String(seg["alg"]))
			if _corner_solved(t, piece):
				break
		if parts.is_empty():
			return {"stage": sc, "progress": progress, "suggestion": {}}
		return {"stage": sc, "progress": progress,
				"suggestion": {"piece": piece, "alg": " ".join(parts), "text": text}}
	var seg2 := _segment(facelets, s)
	if seg2.is_empty():
		return {"stage": sc, "progress": progress, "suggestion": {}}
	return {"stage": sc, "progress": progress, "suggestion": seg2}


# ================================ 4 阶中心段(P3) ================================
## 降阶法第 1 步(docs/v7-teach-nxn-plan.md P3 + docs/v7-impl-design.md):
## - 配色基准 = cube.gd FACES 常量的面序(面号即目标色,编译期常量,不随打乱漂移);
## - 模板池 = L1 交换器(T1-T4)+ 共轭特例(M7)按 §6 入池条款先在模拟器上
##   验证(24 中心格唯一 id 置换,双宏 = 置换乘法合成)再入池;
## - 槽位旋转 = _rotate_alg 推广(数字前缀跳过、小写面保留大小写映射);
## - 摆位前缀 = U^a D^b(外层面内摆位,对已完成 U/D 面恒等)+ 双宏内连接缀;
## - 评分:未归位中心数单调降(placed 每段严格增)∧ 已完成面保持(宏置换对
##   完成面格集 setwise 保持,布局无关可预计算);
## - 卡点:约束 BFS——在「placed 不降 ∧ 完成面保持」子空间完备搜索(3 面完成期
##   颜色态空间 ≤ C(12,4)·C(8,4) = 34650 封顶,visited 去重后远小于此);
## - BFS 穷尽仍无进展 → 查 CENTER_TABLE(构建期产物)→ 未命中 = fail loud 降级
##   (P3 熔断条款:返回 ok:false +『中心段模板池未覆盖(降级)』,不静默)。
## 阶段判定 = 六面中心各自同色;进度 = 已归位中心块比例(24 格中 色==面号)。

const CENTER_N := 4
## 中心段 guard(P5 bootstrap 条款:先宽松采金标准分布,实测后收紧)
const CENTER_STAGE_GUARD := 64
const CENTER_MOVE_LIMIT := 240
## BFS 搜索预算(节点数/深度;3 面完成期子空间 ≤34650 态,预算内可穷尽)
const CENTER_BFS_NODES := 20000
const CENTER_BFS_DEPTH := 8

## L1 基础微段(设计文档 §4.1 T1-T4,引擎记号;单块上提/双块交换/反向变体)
const CENTER_EXCHANGES := ["r U r'", "r U2 r'", "r' U r", "r U' r'"]
## 共轭特例(§4.2 M7):对面 2 格对换,实测最短死锁解除例
const CENTER_CONJUGATE := "r 3R' D 3R r'"
## 双宏内连接缀(§3:外层 U/D 摆位 + 内层 3U 相位旋钮)
const CENTER_CONNECTORS := ["", "U", "U'", "U2", "D", "D'", "D2", "3U", "3U'", "3U2"]

## 卡点查表(24 中心色串 → 一发宏段;构建期产物,当前为空 = 未覆盖走降级路径)
const CENTER_TABLE := {}

## 4-7 阶阶段名(9 段契约,P3 启用首段;组棱起与 3 阶段名随 P4/P5 逐段启用)
const STAGE_NAMES_NXN := ["中心", "组棱", "白十字", "U 层四角", "中层四棱",
		"D 面十字", "D 面全黄", "D 层角位", "D 层棱位"]

static var _center_ready := false
static var _center_cells := PackedInt32Array()  # 24 中心格 facelet 下标(面 fi 行列 1,2)
static var _center_pool1: Array = []            # 单宏:交换器/共轭 × 8 姿态 × U^a D^b 前缀
static var _center_pool2: Array = []            # 闭环双宏:E1 [连接缀] E2
static var _center_pool3: Array = []            # 三段闭环宏:E1 缀 E2 缀 E3(惰性构建)
static var _center_pool3_ready := false
static var _center_atoms: Array = []            # 8 姿态交换器 + 8 姿态共轭(原子置换,池3合成源)


## 4 阶中心段运行期缓存装载(幂等;池条目置换全部经模拟器验证生成——§6 入池条款)。
static func _ensure_centers() -> void:
	if _center_ready:
		return
	_center_ready = true
	for fi in 6:
		for r in [1, 2]:
			for c in [1, 2]:
				_center_cells.append(fi * 16 + r * 4 + c)
	# 原子置换:交换器/共轭 × 8 姿态(y4 × {恒等, x2};模拟器实测)、连接缀(摆位)
	var exch_perms := {}   # 姿态交换器 alg -> perm
	var conj_perms := {}   # 姿态共轭 alg -> perm
	for base in CENTER_EXCHANGES:
		for k in 4:
			var alg := _rotate_y(base, k)
			exch_perms[alg] = _center_id_perm(alg)
			var alg_x := _remap_x2(alg)
			exch_perms[alg_x] = _center_id_perm(alg_x)
	for k in 4:
		var alg_c := _rotate_y(CENTER_CONJUGATE, k)
		conj_perms[alg_c] = _center_id_perm(alg_c)
		var alg_cx := _remap_x2(alg_c)
		conj_perms[alg_cx] = _center_id_perm(alg_cx)
	for alg_a: String in exch_perms:
		_center_atoms.append({"alg": alg_a, "perm": exch_perms[alg_a]})
	for alg_m: String in conj_perms:
		_center_atoms.append({"alg": alg_m, "perm": conj_perms[alg_m]})
	var conn_perms := {}
	for cn in CENTER_CONNECTORS:
		if cn != "":
			conn_perms[cn] = _center_id_perm(cn)
	var u_perms := []
	var d_perms := []
	for k in 4:
		var up := _u_pow(k)
		var dp := _d_pow(k)
		u_perms.append(_center_id_perm(up) if up != "" else PackedInt32Array())
		d_perms.append(_center_id_perm(dp) if dp != "" else PackedInt32Array())
	# 单宏:E × y4 × (U^a D^b 前缀 ×16)——U/D 前缀把借还格对准模板参与格(§3/§4.1)
	for alg_e: String in exch_perms:
		for ua in 4:
			for da in 4:
				var perm_s: PackedInt32Array = exch_perms[alg_e]
				var pre_s := ""
				if ua > 0:
					perm_s = _perm_compose(u_perms[ua], perm_s)
					pre_s = _u_pow(ua) + " "
				if da > 0:
					perm_s = _perm_compose(d_perms[da], perm_s)
					pre_s += _d_pow(da) + " "
				_center_pool1.append(_center_entry(pre_s + alg_e, perm_s))
	for alg_j: String in conj_perms:
		for ua in 4:
			for da in 4:
				var perm: PackedInt32Array = conj_perms[alg_j]
				var pre := ""
				if ua > 0:
					perm = _perm_compose(u_perms[ua], perm)
					pre = _u_pow(ua) + " "
				if da > 0:
					perm = _perm_compose(d_perms[da], perm)
					pre += _d_pow(da) + " "
				_center_pool1.append(_center_entry(pre + alg_j, perm))
	# 闭环双宏:E1 [缀] E2(先 E1 后缀后 E2;置换合成次序见 _perm_compose);
	# 同置换效果去重保最短记号串(32 姿态 × 10 缀 × 32 姿态原始域 ~1e4,去重后入池)
	var seen := {}
	for alg1: String in exch_perms:
		for cn in CENTER_CONNECTORS:
			for alg2: String in exch_perms:
				var perm2: PackedInt32Array = exch_perms[alg1]
				if cn != "":
					perm2 = _perm_compose(perm2, conn_perms[cn])
				perm2 = _perm_compose(perm2, exch_perms[alg2])
				var alg_full: String = alg1 + (" " + cn if cn != "" else "") + " " + alg2
				var pkey := PackedByteArray()
				pkey.resize(24)
				for j in 24:
					pkey[j] = perm2[j]
				var prev_alg: String = String(seen.get(pkey, ""))
				if prev_alg != "" and prev_alg.length() <= alg_full.length():
					continue
				seen[pkey] = alg_full
	for pkey2: PackedByteArray in seen:
		var alg_d: String = seen[pkey2]
		var perm_d := PackedInt32Array()
		perm_d.resize(24)
		for j in 24:
			perm_d[j] = pkey2[j]
		_center_pool2.append(_center_entry(alg_d, perm_d))


## 池条目:置换 + keeps 位掩码(置换把面 fi 的 4 格 setwise 映回 fi = 完成面保持,
## 布局无关可预计算)+ 步数。
static func _center_entry(alg: String, perm: PackedInt32Array) -> Dictionary:
	var keeps := _center_keeps(perm)
	var moves := 0
	for j in 24:
		if perm[j] != j:
			moves |= 1 << perm[j]
	return {"alg": alg, "perm": perm, "keeps": keeps, "moves": moves,
			"tokens": LBL._token_count(alg)}


## 槽位旋转(_rotate_alg 推广,P3 节点名;lbl_solver 零改动):
## 跳过数字前缀;面字母(含小写)按 ROT_MAPS 映射、大小写保留;U/D 及后缀不动。
static func _rotate_y(alg: String, k: int) -> String:
	var tab: Dictionary = LBL.ROT_MAPS[k % 4]
	var out: PackedStringArray = []
	for token in alg.split(" ", false):
		if token.is_empty():
			continue
		var i := 0
		var pre := ""
		while i < token.length() and token[i] >= "0" and token[i] <= "9":
			pre += token[i]
			i += 1
		var face := token[i]
		var up := face.to_upper()
		var mapped: String = String(tab[up])
		if face != up:
			mapped = mapped.to_lower()
		out.append(pre + mapped + token.substr(i + 1))
	return " ".join(out)


## x2 共轭记号重映射(lbl_solver REMAP_X2 同款语义,U↔D F↔B R↔L;数字前缀跳过、
## 大小写保留)。y4 × x2 = 8 姿态:交换器/共轭由此覆盖全部 6 面作"作用面"——
## 仅 y 旋转的池对 D 面格只有面内轮换(净效果不动 D 格),D 面全错构型必死锁
## (2026-09-29 三随机态全降级实证),x2 共轭 = 设计文档 §5.2「D 轴对称」落地。
static func _remap_x2(alg: String) -> String:
	var tab := {"U": "D", "D": "U", "F": "B", "B": "F", "R": "L", "L": "R"}
	var out: PackedStringArray = []
	for token in alg.split(" ", false):
		if token.is_empty():
			continue
		var i := 0
		var pre := ""
		while i < token.length() and token[i] >= "0" and token[i] <= "9":
			pre += token[i]
			i += 1
		var face := token[i]
		var up := face.to_upper()
		var mapped: String = String(tab[up])
		if face != up:
			mapped = mapped.to_lower()
		out.append(pre + mapped + token.substr(i + 1))
	return " ".join(out)


## 宏置换(§6.3 语义环范式):复原态 24 中心格填唯一 id → _apply_alg → 读回
## new[j] = 旧位(24 中心格在任意层转下互相封闭置换)。
static func _center_id_perm(alg: String) -> PackedInt32Array:
	var id := PackedByteArray()
	id.resize(96)
	id.fill(200)
	for i in 24:
		id[_center_cells[i]] = i
	_apply_alg(id, alg)
	var perm := PackedInt32Array()
	perm.resize(24)
	for i in 24:
		perm[i] = id[_center_cells[i]]
	return perm


## 置换合成(先 B 后 A,与 _apply 次序一致):new[j] = old[pA[pB[j]]]。
## 维度自适应 pa(P4b 起 4 阶 24 维与 5-7 阶中心/块维共用)。
static func _perm_compose(pa: PackedInt32Array, pb: PackedInt32Array) -> PackedInt32Array:
	var m: int = pa.size()
	var out := PackedInt32Array()
	out.resize(m)
	for j in m:
		out[j] = pa[pb[j]]
	return out


## 置换应用(纯 24 格中心态)。
static func _center_apply(state: PackedByteArray, perm: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(24)
	for j in 24:
		out[j] = state[perm[j]]
	return out


## 96 facelets → 24 中心色态(配色基准 = cube.gd FACES 面序:面号即目标色)。
static func _center_state_of(f: PackedByteArray) -> PackedByteArray:
	_ensure_centers()
	var st := PackedByteArray()
	st.resize(24)
	for i in 24:
		st[i] = f[_center_cells[i]]
	return st


## 已归位中心块数(P3 进度口径:色 == 面号)。
static func _centers_placed(state: PackedByteArray) -> int:
	var k := 0
	for i in 24:
		if state[i] == i / 4:
			k += 1
	return k


## 完成面位掩码(面 fi 4 格全 = fi)。
static func _centers_done_mask(state: PackedByteArray) -> int:
	var mask := 0
	for fi in 6:
		var same := true
		for i in 4:
			if state[fi * 4 + i] != fi:
				same = false
				break
		if same:
			mask |= 1 << fi
	return mask


## 六面中心各自同色(P3 阶段判定,任意色朝向无关;96 facelets 直查)。
static func _centers_uniform(f: PackedByteArray) -> bool:
	for fi in 6:
		var ref: int = f[_center_cells[fi * 4]]
		for i in 4:
			if f[_center_cells[fi * 4 + i]] != ref:
				return false
	return true


## 卡点态查表键(24 中心色串;设计文档 §4.3 查表范式 key_of)。
static func _center_key(state: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for i in 24:
		parts.append(str(state[i]))
	return "".join(parts)


## 下一段:贪心 depth1 → 卡点约束 BFS →(惰性)三段闭环池贪心/BFS → 破坏+恢复 →
## {}(上层查表/降级)。
static func _center_segment(state: PackedByteArray) -> Dictionary:
	var best := _center_greedy(state)
	if not best.is_empty():
		return best
	var bfs := _center_bfs(state)
	if not bfs.is_empty():
		return bfs
	_ensure_pool3()
	best = _center_greedy(state)
	if not best.is_empty():
		return best
	bfs = _center_bfs(state)
	if not bfs.is_empty():
		return bfs
	return _center_bfr(state)


## 破坏+恢复段(§4.2 M 族「破坏+恢复」的搜索化):单宏有意破已完成面 → 修复 BFS 在
## 「原完成面逐宏保持(已破者除外)∧ placed 逐宏不降」约束下恢复并净推进;整段作为
## 单个 segment:段级 placed 严格增 ∧ 完成面恢复保持(段内破允,即宏段语义)。
## 剪枝:破口必须触及错位格(moves 掩码)、破口深度 ≤4(placed 掉幅);破口浅者先试。
static func _center_bfr(state: PackedByteArray) -> Dictionary:
	var done0 := _centers_done_mask(state)
	if done0 == 0:
		return {}
	var p0 := _centers_placed(state)
	var misplaced := 0
	for j in 24:
		if state[j] != j / 4:
			misplaced |= 1 << j
	var cands: Array = []
	for e in _center_pool1:
		if int(e.keeps) & done0 == done0:
			continue  # 不破口(保持族已由贪心/BFS 搜过)
		if int(e.moves) & misplaced == 0:
			continue  # 不触及错位格:修复无从触及,必无效
		var s1 := _center_apply(state, e.perm)
		var p1 := _centers_placed(s1)
		if p1 < p0 - 4:
			continue
		cands.append({"e": e, "s1": s1, "p1": p1})
	cands.sort_custom(func(a, b) -> bool: return int(a.p1) > int(b.p1))
	for c in cands:
		var rep := _center_repair_bfs(c.s1, done0, p0)
		if rep.is_empty():
			continue
		var e: Dictionary = c.e
		var algs: Array = [String(e.alg)]
		var net: PackedInt32Array = e.perm
		var last: PackedByteArray = rep.state
		var pend := _centers_placed(last)
		for m in rep.path:
			algs.append(String(m.alg))
			net = _perm_compose(net, m.perm)
		return {"alg": " ".join(algs), "perm": net, "inc": pend - p0,
				"tokens": LBL._token_count(" ".join(algs)),
				"text": "破坏+恢复宏:借已完成面中转,净送回 %d 块中心" % (pend - p0),
				"bfs": true}
	return {}


## 修复 BFS:从破口态出发,每步宏保持 done0 ∩ 当前完成面 ∧ placed 不降;
## 目标 = 完成面 ⊇ done0 ∧ placed > p0(净推进)。预算与深度受限(卡点专用)。
static func _center_repair_bfs(s1: PackedByteArray, done0: int, p0: int) -> Dictionary:
	var queue: Array = [[s1, []]]
	var visited := {_center_key(s1): true}
	var nodes := 1
	while not queue.is_empty() and nodes < 4000:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		if path.size() >= 6:
			continue
		var must := done0 & _centers_done_mask(cur)
		for pool in [_center_pool1, _center_pool2, _center_pool3]:
			for e in pool:
				if must & ~int(e.keeps) != 0:
					continue
				var nxt: PackedByteArray = _center_apply(cur, e.perm)
				var np := _centers_placed(nxt)
				if np < _centers_placed(cur):
					continue
				var key := _center_key(nxt)
				if visited.has(key):
					continue
				visited[key] = true
				nodes += 1
				var path2 := path.duplicate()
				path2.append({"alg": e.alg, "perm": e.perm})
				if np > p0 and _centers_done_mask(nxt) & done0 == done0:
					return {"state": nxt, "path": path2}
				if nodes >= 4000:
					break
				queue.append([nxt, path2])
			if nodes >= 4000:
				break
	return {}


## 三段闭环宏(§4.3 结构模板兜底:E 缀 E 缀 E,12-15 步域):池2 置换 × 连接缀 ×
## 交换器原子合成,按 §6 条款在模拟器置换上验证 keeps(至少保持 U/D 或四侧面之一组
## setwise)后入池,同效果去重保最短记号串;惰性构建(仅卡点路径触达)。
static func _ensure_pool3() -> void:
	if _center_pool3_ready:
		return
	_center_pool3_ready = true
	var conn_perms := {}
	for cn in ["U", "U'", "D", "D'", "3U", "3U'"]:
		conn_perms[cn] = _center_id_perm(cn)
	var seen := {}
	for e2 in _center_pool2:
		var p2: PackedInt32Array = e2.perm
		for cn: String in conn_perms:
			var p2c: PackedInt32Array = _perm_compose(p2, conn_perms[cn])
			for e3 in _center_atoms:
				var perm3 := PackedInt32Array()
				perm3.resize(24)
				for j in 24:
					perm3[j] = p2c[e3.perm[j]]
				var keeps := _center_keeps(perm3)
				# 须整组 setwise 保持 U/D 或四侧面之一(§4.2/§4.3 判据:U/D 白黄保持的
				# 侧面重排族,或四侧保持的 L2C U↔D 搬运族);零散单面保持的杂效果不入
				if (keeps & 9) != 9 and (keeps & 30) != 30:
					continue
				var pkey := PackedByteArray()
				pkey.resize(24)
				for j in 24:
					pkey[j] = perm3[j]
				if seen.has(pkey):
					continue
				seen[pkey] = true
				var alg: String = String(e2.alg) + " " + cn + " " + String(e3.alg)
				_center_pool3.append(_center_entry(alg, perm3))
				if _center_pool3.size() >= 30000:
					return


## 置换的面保持位掩码(keeps;_center_entry 同式,池3构建期复用)。
static func _center_keeps(perm: PackedInt32Array) -> int:
	var keeps := 0
	for fi in 6:
		var same := true
		for i in 4:
			var src: int = perm[fi * 4 + i]
			if src < fi * 4 or src > fi * 4 + 3:
				same = false
				break
		if same:
			keeps |= 1 << fi
	return keeps


## depth1 贪心:全池扫描,完成面保持 ∧ placed 严格增,择 (inc 最大, tokens 最短)。
static func _center_greedy(state: PackedByteArray) -> Dictionary:
	var done := _centers_done_mask(state)
	var pc := _centers_placed(state)
	var best := {}
	for pool in [_center_pool1, _center_pool2, _center_pool3]:
		for entry in pool:
			if done & ~int(entry.keeps) != 0:
				continue  # 破已完成面
			var inc: int = _centers_placed(_center_apply(state, entry.perm)) - pc
			if inc <= 0:
				continue
			var tok: int = int(entry.tokens)
			if best.is_empty() or inc > int(best.inc) or (inc == int(best.inc) and tok < int(best.tokens)):
				best = {"alg": String(entry.alg), "perm": entry.perm, "inc": inc,
						"tokens": tok, "text": "中心交换宏:送回 %d 块中心" % inc, "bfs": false}
	return best


## 卡点约束 BFS:在「每步宏完成面保持 ∧ placed 不降」子空间完备搜索 placed 增路径
## (宏段级整理——设计文档 §0.2『持平整理』的搜索化;状态空间 3 面完成期 ≤34650)。
## 返回 {segs: [宏条目...]}(首条 placed 增路径,逐宏段级单调)或 {}(穷尽无解)。
static func _center_bfs(state: PackedByteArray) -> Dictionary:
	var pc := _centers_placed(state)
	var done0 := _centers_done_mask(state)
	var sub: Array = []  # 初始完成面保持的子池(必要条件,一次预过滤;节点内再按自身 done 复查)
	for pool in [_center_pool1, _center_pool2, _center_pool3]:
		for e in pool:
			if done0 & ~int(e.keeps) == 0:
				sub.append(e)
	var queue: Array = [[state, [], pc]]
	var visited := {_center_key(state): true}
	var nodes := 1
	while not queue.is_empty() and nodes < CENTER_BFS_NODES:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		var cp: int = entry[2]
		if path.size() >= CENTER_BFS_DEPTH:
			continue
		var done := _centers_done_mask(cur)
		for e in sub:
			if done & ~int(e.keeps) != 0:
				continue  # 破已完成面(含中途新完成的面)
			var nxt: PackedByteArray = _center_apply(cur, e.perm)
			var np := _centers_placed(nxt)
			if np < cp:
				continue  # placed 不降(约束单调)
			var key := _center_key(nxt)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append({"alg": String(e.alg), "perm": e.perm,
					"tokens": int(e.tokens), "inc": np - cp})
			if np > pc:
				# 首个推进节点:BFS 保证宏数最少;逐宏成段(每段 placed 不降)
				var segs: Array = []
				for m in path2:
					segs.append({"alg": String(m.alg), "perm": m.perm,
							"inc": int(m.inc), "tokens": int(m.tokens),
							"text": "中心整理宏:重排未完成面后送回 %d 块" % int(m.inc),
							"bfs": true})
				return {"segs": segs}
			if nodes >= CENTER_BFS_NODES:
				break
			queue.append([nxt, path2, np])
	return {}


## 中心段求解:{ok, alg, stages:[{name, alg}], moves, segments:[{alg, text}]}。
## 未覆盖构型(约束 BFS 穷尽 + 查表未命中)返回 ok:false,error 注明降级(P3 熔断)。
static func solve_centers(facelets: PackedByteArray) -> Dictionary:
	var n5: int = _facelets_n(facelets.size())
	if n5 >= 5 and n5 <= 7:
		return _cn_solve(facelets, n5)
	if facelets.size() != 6 * CENTER_N * CENTER_N:
		var n: int = _facelets_n(facelets.size())
		var msg: String = ("阶数超出 2-7 契约(%d)" % n) if n > 7 else "facelets 须 96-294(4-7 阶)字节"
		return {"ok": false, "alg": "", "stages": [], "segments": [], "error": msg}
	_ensure_centers()
	var state := _center_state_of(facelets)
	if _centers_done_mask(state) == 63:
		return {"ok": true, "alg": "", "stages": [{"name": STAGE_NAMES_NXN[0], "alg": ""}],
				"moves": 0, "segments": []}
	var segs: Array = []
	var all: Array = []
	var total := 0
	var guard := 0
	while _centers_done_mask(state) != 63:
		guard += 1
		if guard > CENTER_STAGE_GUARD or total >= CENTER_MOVE_LIMIT:
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "中心段超 guard 上限(段 %d / 步 %d)" % [guard, total]}
		var seg := _center_segment(state)
		if seg.is_empty():
			# 约束子空间完备搜索穷尽 → 查表(构建期产物)→ 未命中 = 降级 fail loud
			var hit: String = String(CENTER_TABLE.get(_center_key(state), ""))
			if hit == "":
				return {"ok": false, "alg": "", "stages": [], "segments": [],
						"error": "中心段模板池未覆盖(降级): 卡点态 %s" % _center_key(state)}
			var perm_hit := _center_id_perm(hit)
			seg = {"alg": hit, "perm": perm_hit, "inc": 0, "tokens": LBL._token_count(hit),
					"text": "查表一发宏:收尾两面布置", "bfs": false}
		for m in (seg.segs if seg.has("segs") else [seg]):
			state = _center_apply(state, m.perm)
			segs.append({"alg": String(m.alg), "text": String(m.text)})
			all.append(String(m.alg))
			total += int(m.tokens)
	# 不走 LBL._simplify_alg(其合并表只认大写 token,内层/小写记号会崩;lbl 红线禁改),
	# 段间合并留待 P5 段级缓存一并处理。
	var joined := " ".join(all)
	return {"ok": true, "alg": joined,
			"stages": [{"name": STAGE_NAMES_NXN[0], "alg": joined}],
			"moves": LBL._token_count(joined), "segments": segs}


## 4 阶 hint(P3/P4a):stage 0/1;建议 = 贪心单宏,卡点给 BFS 首宏,死锁给降级标记。
## stage 1(中心已解)转组棱段建议(P4a)。
static func _center_hint(facelets: PackedByteArray) -> Dictionary:
	_ensure_centers()
	var sc := stage_check(facelets)
	var progress := _centers_placed(_center_state_of(facelets)) / 24.0
	if sc == 1:
		return _edge_hint(facelets)
	var state := _center_state_of(facelets)
	var seg := _center_segment(state)
	if seg.is_empty():
		return {"stage": sc, "progress": progress, "suggestion": {},
				"error": "中心段模板池未覆盖(降级): 卡点态 %s" % _center_key(state)}
	if seg.has("segs"):
		seg = seg.segs[0]
	return {"stage": sc, "progress": progress,
			"suggestion": {"piece": "中心", "alg": String(seg.alg), "text": String(seg.text)}}


# ================================ 4 阶组棱段(P4a) ================================
## 降阶法第 2 步(docs/v7-teach-nxn-plan.md P4a):12 条棱各 2 wing,配对判据 =
## 同棱两 wing 色集相同(无序;wing 块朝向翻转不影响色集,OLL parity 判据随 P5)。
## - 配色基准 = cube.gd FACES 面序(棱位色集 = 复原态该棱 wing 色对,12 种);
## - 配对模板(本会话模拟器逐条实测语义,docs/v7-impl-design.md §6 入池条款):
##   r 系 5 步族 = 「破坏+恢复」共轭宏(r U R' U' r' 等,中心面内轮换型——
##   单侧 4 中心格 setwise 保持,任意已解中心态面同色不破);
##   u/d 系配对族 = ruwix 初学者教程公共公式转译(Uw≡u、Dw≡d:u' R U R' u 等);
##   A 段 = ruwix 最后两棱技巧段(R F' U R' F,纯外层);
##   PLL parity = 社区公式转译(2R2≡3R2、Uw2≡u2;wing 双对换宏)。
## - setup 自由度 = 模板 y 旋转(_rotate_y)× x2 共轭(_remap_x2)× U^a D^b 摆位前缀
##   (内层摆位以共轭缀并入基型,见 u/d 系;裸内层前缀会跨面挪中心格,不入池);
## - 段生成 = 贪心(配对数增 ∧ 已配对色集保持)→ 持平 BFS(复合小宏库,深度 2)
##   → 破坏+恢复(拆 ≤1 对后修复净增,段级判据不变——段内破允,段末保持);
## - 卡点(约束搜索穷尽)= fail loud 降级(P4a 熔断条款:返回 ok:false 且 error
##   注明『组棱段模板池未覆盖(降级)』,不静默)。
## 2026-09-29 固定种子 30 态实测:17/30 全通 + 13 态带标记降级(交叉构型缺
## wing 奇置换宏,复合域内不存在——熔断记录,后续按 P4b 论证条款补池)。

## 组棱段 guard(P5 bootstrap 条款:先宽松采金标准分布,实测后收紧)
const EDGE_STAGE_GUARD := 80
const EDGE_MOVE_LIMIT := 480
const EDGE_BFS_NODES := 1500
const EDGE_BFR_CANDS := 6
const EDGE_BFR_NODES := 1500

## 基型池(引擎记号;每条均在 4 阶模拟器实测:中心面 setwise 保持 + wing 块封闭)
const EDGE_BASES := [
	"r U R' U' r'", "r U' R' U r'", "r U2 R' U2 r'",
	"r U R U' r'", "r U' R U r'", "r U2 R U2 r'",
	"u L' U' L u'", "u' L' U' L u", "u R U R' u'", "u' R U R' u",
	"u R U' R' u'", "u2 R U R' u2", "u2 L' U' L u2",
	"d R F' U R' F d'", "R F' U R' F",
	"3R2 U2 3R2 u2 3R2 u2",
]

static var _edge_ready := false
static var _wing_cells := PackedInt32Array()  # 48:wing w 的两贴纸 facelet 下标 = [2w, 2w+1]
static var _edge_wings: Array = []            # 棱 e(0..11)-> [w0, w1](wing 序按坐标排序固定)
static var _edge_pool: Array = []             # 基础宏:{alg, perm(24 wing 色集置换), len}
static var _edge_local: Array = []            # 复合小宏(两宏复合,动 3..8 wing;卡点专用)


## 组棱段运行期缓存装载(幂等;置换全部经模拟器验证生成——§6 入池条款)。
static func _ensure_edges() -> void:
	if _edge_ready:
		return
	_edge_ready = true
	_ensure_n(4)
	# wing 表(坐标法):wing = 恰一分量 ±1、另两 ±3 的格;同坐标 2 facelet 同块;
	# 棱 = 两个 ±3 分量(带符号)相同的 wing 组,棱内 wing 按坐标序固定。
	var by_xyz := {}
	var cells: Array = _cells[4]
	for i in cells.size():
		var v: Vector3 = cells[i].c
		var key := "%d,%d,%d" % [int(v.x), int(v.y), int(v.z)]
		if not by_xyz.has(key):
			by_xyz[key] = []
		(by_xyz[key] as Array).append(i)
	var wings: Array = []
	for key: String in by_xyz:
		var arr: Array = by_xyz[key]
		if arr.size() != 2:
			continue
		var parts: PackedStringArray = key.split(",")
		var abs3 := 0
		var abs1 := 0
		for p in parts:
			var a: int = abs(int(p))
			if a == 3:
				abs3 += 1
			elif a == 1:
				abs1 += 1
		if abs3 == 2 and abs1 == 1:
			wings.append([key, arr])
	wings.sort_custom(func(a, b) -> bool: return String(a[0]) < String(b[0]))
	var edge_id := {}
	for w: Array in wings:
		var parts: PackedStringArray = String(w[0]).split(",")
		var ekey := ""
		for pi in 3:
			var pv: int = int(parts[pi])
			ekey += ("*" if abs(pv) == 1 else str(pv)) + ","
		if not edge_id.has(ekey):
			edge_id[ekey] = edge_id.size()
			_edge_wings.append([])
		var wid: int = _wing_cells.size() / 2
		_wing_cells.append(w[1][0])
		_wing_cells.append(w[1][1])
		_edge_wings[edge_id[ekey]].append(wid)
	# 基础池:基型 × y4 × x2 × U^a D^b 前缀;入池断言 = 中心 setwise + wing 块封闭
	var up := _edge_perm_of("U")
	var dp := _edge_perm_of("D")
	for base in EDGE_BASES:
		for k in 4:
			for xr in 2:
				var core := _rotate_y(base, k)
				if xr == 1:
					core = _remap_x2(core)
				var pcore := _edge_perm_of(core)
				if pcore.size() != 24:
					continue  # 姿态破中心或拆块(不会发生,防御)
				for ua in 4:
					for da in 4:
						var alg := ""
						var pre := pcore
						if ua > 0:
							alg += _u_pow(ua) + " "
							var t := PackedInt32Array()
							t.resize(24)
							for w in 24:
								t[w] = up[pre[w]]
							pre = t
						if da > 0:
							alg += _d_pow(da) + " "
							var t2 := PackedInt32Array()
							t2.resize(24)
							for w2 in 24:
								t2[w2] = dp[pre[w2]]
							pre = t2
						_edge_pool.append({"alg": alg + core, "perm": pre,
								"len": (alg + core).length()})
	# 复合小宏库:u/d 系局部宏(u 系 7 + d 系 1 + A 1 + PLL 1)自复合(先 i 后 j),
	# 动 3..7 wing,同效果去重;卡点(BFS/BFR)专用弹药——r 系宏效果全域动 8,
	# 复合杂效果搅扰整理路径,不入复合域(2026-09-29 金标准对拍定案)
	var ubases: Array = []
	for base in EDGE_BASES:
		if not base.begins_with("r "):
			ubases.append(base)
	var upool: Array = []
	var seen := {}
	for base in ubases:
		for k in 4:
			for xr in 2:
				var core := _rotate_y(base, k)
				if xr == 1:
					core = _remap_x2(core)
				var pcore := _edge_perm_of(core)
				if pcore.size() != 24:
					continue
				for ua in 4:
					for da in 4:
						var alg := ""
						var pre := pcore
						if ua > 0:
							alg += _u_pow(ua) + " "
							var t := PackedInt32Array()
							t.resize(24)
							for w in 24:
								t[w] = up[pre[w]]
							pre = t
						if da > 0:
							alg += _d_pow(da) + " "
							var t2 := PackedInt32Array()
							t2.resize(24)
							for w3 in 24:
								t2[w3] = dp[pre[w3]]
							pre = t2
						var s := alg + core
						if seen.has(s):
							continue
						seen[s] = true
						upool.append({"alg": s, "perm": pre, "len": s.length()})
	var seen2 := {}
	for i in upool.size():
		var pi: PackedInt32Array = upool[i].perm
		for j in upool.size():
			var pj: PackedInt32Array = upool[j].perm
			var comp := PackedInt32Array()
			comp.resize(24)
			var moved := 0
			for w4 in 24:
				comp[w4] = pi[pj[w4]]
				if comp[w4] != w4:
					moved += 1
			if moved < 3 or moved > 7:
				continue
			var key := PackedByteArray()
			key.resize(24)
			for w5 in 24:
				key[w5] = comp[w5]
			if seen2.has(key):
				continue
			seen2[key] = true
			_edge_local.append({"alg": String(upool[i].alg) + " " + String(upool[j].alg),
					"perm": comp,
					"len": String(upool[i].alg).length() + String(upool[j].alg).length() + 1})


## 宏置换提取:复原态 96 字节填唯一 id → apply → 读回。
## 拒入池条件(§6 条款):中心面 setwise 不保(任意面 4 中心格映出本面)
## 或 wing 块拆散(两贴纸分离)——返回空。
static func _edge_perm_of(alg: String) -> PackedInt32Array:
	_ensure_centers()
	var id := PackedByteArray()
	id.resize(96)
	id.fill(200)
	for i in 24:
		id[_center_cells[i]] = 100 + i
	for w in 24:
		id[_wing_cells[2 * w]] = 2 * w
		id[_wing_cells[2 * w + 1]] = 2 * w + 1
	_apply_alg(id, alg)
	for fi in 6:
		for i in 4:
			var src: int = int(id[_center_cells[fi * 4 + i]]) - 100
			if src < fi * 4 or src > fi * 4 + 3:
				return PackedInt32Array()
	var perm := PackedInt32Array()
	perm.resize(24)
	for w in 24:
		var va: int = id[_wing_cells[2 * w]]
		var vb: int = id[_wing_cells[2 * w + 1]]
		if va / 2 != vb / 2:
			return PackedInt32Array()
		perm[w] = va / 2
	return perm


## 96 facelets → 24 wing 色集态(每 wing 两贴纸色对的有序化 id,翻转无关)。
static func _wing_state_of(f: PackedByteArray) -> PackedByteArray:
	_ensure_edges()
	var st := PackedByteArray()
	st.resize(24)
	for w in 24:
		var pa: int = f[_wing_cells[2 * w]]
		var pb: int = f[_wing_cells[2 * w + 1]]
		st[w] = mini(pa, pb) * 6 + maxi(pa, pb)
	return st


static func _edge_apply(st: PackedByteArray, perm: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(24)
	for w in 24:
		out[w] = st[perm[w]]
	return out


## 已配对棱数(棱内两 wing 色集相同)。
static func _edges_paired(st: PackedByteArray) -> int:
	var n := 0
	for e in 12:
		var w: Array = _edge_wings[e]
		if st[w[0]] == st[w[1]]:
			n += 1
	return n


## 已配对色集位掩码(位 = 色集 id;「已配对棱保持」的块级口径——配对可整体
## 换位,不许拆)。
static func _edge_pair_mask(st: PackedByteArray) -> int:
	var m := 0
	for e in 12:
		var w: Array = _edge_wings[e]
		if st[w[0]] == st[w[1]]:
			m |= 1 << st[w[0]]
	return m


## 下一段:贪心 → 持平 BFS(复合库)→ 破坏+恢复 → {}(上层降级)。
## 返回 {alg(整段串), perm(整段置换), tokens, text};段级判据 = 已配对色集
## 保持 ∧ 配对数增(BFS/BFR 段内多宏,段内破允段末保持,与中心段宏段语义同款)。
static func _edge_segment(st: PackedByteArray) -> Dictionary:
	var g := _edge_greedy(st)
	if not g.is_empty():
		return g
	var b := _edge_level_bfs(st)
	if not b.is_empty():
		return b
	return _edge_bfr(st)


## depth1 贪心:全基础池扫描,已配对保持 ∧ 配对数严格增,择 (inc 最大, len 最短)。
static func _edge_greedy(st: PackedByteArray) -> Dictionary:
	var p0 := _edges_paired(st)
	var kept := _edge_pair_mask(st)
	var best := {}
	for entry in _edge_pool:
		var st2 := _edge_apply(st, entry.perm)
		var mk := 0
		var pc := 0
		for e in 12:
			var w: Array = _edge_wings[e]
			if st2[w[0]] == st2[w[1]]:
				pc += 1
				mk |= 1 << st2[w[0]]
		if mk & kept != kept:
			continue
		var inc: int = pc - p0
		if inc <= 0:
			continue
		var ln: int = int(entry.len)
		if best.is_empty() or inc > int(best.inc) or (inc == int(best.inc) and ln < int(best.len)):
			best = {"alg": String(entry.alg), "perm": entry.perm, "len": ln,
					"inc": inc, "pc": pc, "p0": p0}
	if best.is_empty():
		return {}
	return {"alg": String(best.alg), "perm": best.perm,
			"tokens": LBL._token_count(String(best.alg)),
			"text": "棱配对宏:配对数 %d → %d" % [int(best.p0), int(best.pc)]}


## 持平 BFS:复合小宏库,配对数不降 ∧ 已配对保持子空间,目标配对数增(深度 ≤2)。
## 返回整段(宏序列合并;逐宏单调故段级保持)或 {}。
static func _edge_level_bfs(st0: PackedByteArray) -> Dictionary:
	var p0 := _edges_paired(st0)
	var queue: Array = [[st0, []]]
	var visited := {hash(st0): true}
	var nodes := 1
	while not queue.is_empty() and nodes < EDGE_BFS_NODES:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		if path.size() >= 2:
			continue
		var kept := _edge_pair_mask(cur)
		for m in _edge_local:
			var st2 := _edge_apply(cur, m.perm)
			if _edge_pair_mask(st2) & kept != kept:
				continue
			if _edges_paired(st2) < _edges_paired(cur):
				continue
			var key: int = hash(st2)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append(m)
			if _edges_paired(st2) > p0:
				var algs: Array = []
				var net := PackedInt32Array()
				net.resize(24)
				for w in 24:
					net[w] = w
				for mm: Dictionary in path2:
					algs.append(String(mm.alg))
					var tmp := PackedInt32Array()
					tmp.resize(24)
					for w2 in 24:
						tmp[w2] = net[mm.perm[w2]]
					net = tmp
				var joined := " ".join(algs)
				return {"alg": joined, "perm": net,
						"tokens": LBL._token_count(joined),
						"text": "棱整理宏:BFS 持平整理后配对(%d 步)" % path2.size()}
			queue.append([st2, path2])
	return {}


## 破坏+恢复段:单宏有意拆 ≤1 已配对(段内破允)→ 修复 BFS 在「原已配对色集
## 逐宏保持(已拆者除外)∧ 配对数不降」约束下恢复并净增;段级判据不变。
static func _edge_bfr(st0: PackedByteArray) -> Dictionary:
	var p0 := _edges_paired(st0)
	var kept0 := _edge_pair_mask(st0)
	var cands: Array = []
	for m in _edge_local:
		var st2 := _edge_apply(st0, m.perm)
		var p1 := _edges_paired(st2)
		if p1 < p0 - 1:
			continue
		cands.append({"m": m, "s1": st2, "p1": p1})
	cands.sort_custom(func(a, b) -> bool: return int(a.p1) > int(b.p1))
	var tried := 0
	for c: Dictionary in cands:
		if tried >= EDGE_BFR_CANDS:
			break
		tried += 1
		var rep := _edge_repair(c.s1, kept0, p0)
		if rep.is_empty():
			continue
		var algs: Array = [String(c.m.alg)]
		var net := PackedInt32Array()
		net.resize(24)
		for w in 24:
			net[w] = c.m.perm[w]
		for mm: Dictionary in rep:
			algs.append(String(mm.alg))
			var tmp := PackedInt32Array()
			tmp.resize(24)
			for w2 in 24:
				tmp[w2] = net[mm.perm[w2]]
			net = tmp
		var joined := " ".join(algs)
		return {"alg": joined, "perm": net, "tokens": LBL._token_count(joined),
				"text": "破坏+恢复宏:借已配对棱中转重组后净配对"}
	return {}


## 修复 BFS:从破口态出发,每步「原已配对色集中已恢复者保持 ∧ 配对数不降」;
## 目标 = 配对数 > p0 且 kept0 全部恢复。复合库,预算受限(卡点专用)。
static func _edge_repair(s1: PackedByteArray, kept0: int, p0: int) -> Array:
	var queue: Array = [[s1, []]]
	var visited := {hash(s1): true}
	var nodes := 1
	while not queue.is_empty() and nodes < EDGE_BFR_NODES:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		var must: int = kept0 & _edge_pair_mask(cur)
		for m in _edge_local:
			var st2 := _edge_apply(cur, m.perm)
			if _edge_pair_mask(st2) & must != must:
				continue
			if _edges_paired(st2) < _edges_paired(cur):
				continue
			var key: int = hash(st2)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append(m)
			if _edges_paired(st2) > p0 and _edge_pair_mask(st2) & kept0 == kept0:
				return path2
			queue.append([st2, path2])
	return []


## 组棱段求解:{ok, alg, stages:[{name, alg}], moves, segments:[{alg, text}]}。
## 前置 = 中心已解(先 solve_centers);未覆盖构型返回 ok:false 且 error 注明
## 『组棱段模板池未覆盖(降级)』(P4a 熔断条款,fail loud 不静默)。
static func solve_edges(facelets: PackedByteArray) -> Dictionary:
	var n5: int = _facelets_n(facelets.size())
	if n5 >= 5 and n5 <= 7:
		return _pr_solve(facelets, n5)
	if facelets.size() != 6 * CENTER_N * CENTER_N:
		var n: int = _facelets_n(facelets.size())
		var msg: String = ("阶数超出 2-7 契约(%d)" % n) if n > 7 else "facelets 须 96-294(4-7 阶)字节"
		return {"ok": false, "alg": "", "stages": [], "segments": [], "error": msg}
	_ensure_centers()
	_ensure_edges()
	if _centers_done_mask(_center_state_of(facelets)) != 63:
		return {"ok": false, "alg": "", "stages": [], "segments": [],
				"error": "组棱段要求中心已解(先跑 solve_centers)"}
	var st := _wing_state_of(facelets)
	var p0 := _edges_paired(st)
	if p0 == 12:
		return {"ok": true, "alg": "",
				"stages": [{"name": STAGE_NAMES_NXN[1], "alg": ""}],
				"moves": 0, "segments": []}
	var segs: Array = []
	var all: Array = []
	var total := 0
	var guard := 0
	while _edges_paired(st) < 12:
		guard += 1
		if guard > EDGE_STAGE_GUARD or total >= EDGE_MOVE_LIMIT:
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "组棱段超 guard 上限(段 %d / 步 %d)" % [guard, total]}
		var seg := _edge_segment(st)
		if seg.is_empty():
			# 约束搜索穷尽 → P4a 熔断降级(fail loud;分层验收见方案风险 1)
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "组棱段模板池未覆盖(降级): 卡点 %d/12 对, wing 态 %s"
							% [_edges_paired(st), _edge_key(st)]}
		st = _edge_apply(st, seg.perm)
		segs.append({"alg": String(seg.alg), "text": String(seg.text)})
		all.append(String(seg.alg))
		total += int(seg.tokens)
	var joined := " ".join(all)
	return {"ok": true, "alg": joined,
			"stages": [{"name": STAGE_NAMES_NXN[1], "alg": joined}],
			"moves": LBL._token_count(joined), "segments": segs}


## 卡点态查表键(24 wing 色集串;P4b 补池时作查表键控)。
static func _edge_key(st: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for i in 24:
		parts.append(str(st[i]))
	return "".join(parts)


## 组棱 hint(中心已解的 stage 1 态):建议 = 段生成首宏;卡点给降级标记
## (P6 失败语义的 error 载体)。全配对态由 _nxn_hint 拦截转 parity/约化注入,
## 此处完成分支为防御路径。
static func _edge_hint(facelets: PackedByteArray) -> Dictionary:
	_ensure_edges()
	var st := _wing_state_of(facelets)
	var paired := _edges_paired(st)
	var progress := paired / 12.0
	if paired == 12:
		return {"stage": 1, "progress": 1.0,
				"suggestion": {"piece": "", "alg": "", "text": "组棱段已完成"},
				"error": "组棱段已完成"}
	var seg := _edge_segment(st)
	if seg.is_empty():
		return {"stage": 1, "progress": progress, "suggestion": {},
				"error": "组棱段模板池未覆盖(降级): 卡点 %d/12 对" % paired}
	return {"stage": 1, "progress": progress,
			"suggestion": {"piece": "棱", "alg": String(seg.alg), "text": String(seg.text)}}


# ================================ 5-7 阶中心段(P4b 推广) ================================
## 降阶法第 1 步的 5-7 阶推广(docs/v7-impl-design.md §8「5-7 阶推广……P4b 条款范围」):
## 机制与 4 阶中心段同构(贪心 → 卡点约束 BFS → 破坏+恢复 → 降级 fail loud),差异:
## - 中心格 = 每面 (n−2)² 格,格类(+ 型/x 型/中央)随 n 分层,判据统一在颜色态上
##   (每面中心格各自同色 = 阶段判定;色==面号 = placed);
## - 原子族按层档展开:宽层 dRw(d=2..n−2)与单内层 dR(d=3..n−2)的 U 夹心交换器,
##   y4 × x2 姿态 × U^a 摆位前缀;置换全部经模拟器实测读回(§6 入池条款机制化,
##   中心格在任何层转下封闭,无需另设拒入条件);
## - 池规模控制:U^a 前缀 4 档(D 侧摆位由 x2 姿态对称覆盖,同 4 阶教训);
##   4 阶的闭环双宏池(pool2)/三段池(pool3)不设——闭环效果由卡点约束 BFS 在
##   池1 域内搜索覆盖(深度 ≤ CN_BFS_DEPTH),更深的死锁走降级(P4b 熔断条款)。
## n=4 中心段(P3)代码路径零改动,见上方专用区段。

const CN_STAGE_GUARD := 12
const CN_MOVE_LIMIT := 50
const CN_BFS_NODES := 3000
const CN_BFS_DEPTH := 2
const CN_BFR_CANDS := 4
const CN_BFR_NODES := 3000

static var _cn_ctx := {}   # n -> {cells, pc, m, pool1, sub1(完成面保持子池,按需重建)}


## 中心格 facelet 下标表(每面行/列 ∈ 1..n−2)。
static func _cn_cells(n: int) -> PackedInt32Array:
	var ctx: Dictionary = _cn_ensure(n)
	return ctx.cells


static func _cn_ensure(n: int) -> Dictionary:
	if _cn_ctx.has(n):
		return _cn_ctx[n]
	var pc: int = (n - 2) * (n - 2)
	var cells := PackedInt32Array()
	for fi in 6:
		for r in range(1, n - 1):
			for c in range(1, n - 1):
				cells.append(fi * n * n + r * n + c)
	# 原子族:宽层/单内层 U 夹心交换器 + D 共轭对换器(4 阶 CENTER_CONJUGATE 的
	# n 阶推广;dRw 夹 eR——2026-10-03 探针 4/5 实测:交换器域两步复合 max inc=0
	# 的无完成面卡点,共轭 8 格多面保持效果是唯一破口材料)
	var bases: Array = []
	for d in range(2, n - 1):
		for core in ["U", "U2", "U'"]:
			bases.append("%dRw %s %dRw'" % [d, core, d])
			bases.append("%dRw' %s %dRw" % [d, core, d])
	for d in range(3, n - 1):
		for core in ["U", "U2", "U'"]:
			bases.append("%dR %s %dR'" % [d, core, d])
			bases.append("%dR' %s %dR" % [d, core, d])
	for d in range(2, n - 1):
		for e2 in range(3, n):
			bases.append("%dRw %dR' D %dR %dRw'" % [d, e2, e2, d])
	# 小步长原子(2026-10-03 探针 9:n=5 的 4-token 域实测 41 个 ≤6 格效果类,
	# 形态统一为 dR 3U± dR' 3U∓ 的内层×3U 摆位共轭——收尾期「精确 1-2 格」专用)
	for d in range(3, n):
		for cu in ["3U 3U'", "3U' 3U", "3U2 3U2"]:
			bases.append("%dR %s %dR'" % [d, cu, d])
	var atoms: Array = []
	for base in bases:
		for k in 4:
			for xr in 2:
				var alg: String = _rotate_y(base, k)
				if xr == 1:
					alg = _remap_x2(alg)
				atoms.append({"alg": alg, "perm": _cn_id_perm(alg, n, cells)})
	# 池1 = 原子 × U^a 前缀(2026-10-03 性能实证:n=7 的 D 前缀展开使贪心全扫
	# 达 8960 条/段,guard 内跑不完;D 侧摆位由 x2 姿态近似覆盖)
	var u_perms: Array = []
	for kk in 4:
		var us: String = _u_pow(kk)
		u_perms.append(_cn_id_perm(us, n, cells) if us != "" else PackedInt32Array())
	var pool1: Array = []
	for at: Dictionary in atoms:
		for ua in 4:
			var perm: PackedInt32Array = at.perm
			var pre := ""
			if ua > 0:
				perm = _perm_compose(u_perms[ua], perm)
				pre = _u_pow(ua) + " "
			pool1.append(_cn_entry(pre + String(at.alg), perm, pc))
	# 摆位缀置换(conn;供 BFS 摆位域/end_atoms;池2 闭环已删——其效果 =
	# bfs_atoms 深度 2 子集,2026-10-04 性能实证:坎段全扫 pool2+pool2b ~6 万条
	# 为单态分钟级热点,且层 a 0/33 全降级下未贡献通过)
	var conn := {}
	for cn in ["U", "U'", "U2", "D", "D'", "D2", "3U", "3U'", "3U2"]:
		conn[cn] = _cn_id_perm(cn, n, cells)
	# u1 = pool1 的 U 前缀子集 + 摆位缀原子(BFS/修复域:D 前缀留给破口域,域小搜索才深)
	var u1: Array = []
	for en: Dictionary in pool1:
		var alga: String = String(en.alg)
		if not (alga.begins_with("D ") or alga.begins_with("D2 ") or alga.begins_with("D' ")
				or alga.contains(" D ") or alga.contains(" D2 ") or alga.contains(" D' ")):
			u1.append(en)
	for cn2 in ["U", "U'", "U2", "D", "D'", "D2", "3U", "3U'", "3U2"]:
		u1.append(_cn_entry(cn2, conn[cn2], pc))
	# bfs_atoms = 无前缀原子 + 摆位缀(BFS/修复域;前缀展开域在深度 2 全遍历口径下
	# 覆盖率不足——2026-10-03 探针 8:169² 全遍历 252ms,有解路径 2 条全在复合深度 2)
	var bfs_atoms: Array = []
	var seen_at := {}
	for en3: Dictionary in pool1:
		var algb: String = String(en3.alg)
		if algb.begins_with("U ") or algb.begins_with("U2 ") or algb.begins_with("U' ") \
				or algb.begins_with("D ") or algb.begins_with("D2 ") or algb.begins_with("D' "):
			continue
		if seen_at.has(algb):
			continue
		seen_at[algb] = true
		bfs_atoms.append(en3)
	for cn3: String in conn:
		bfs_atoms.append(_cn_entry(cn3, conn[cn3], pc))
	# conj1 = 破口域(共轭原子 × U^a D^b;探针 5 配方:可修复破口集中在共轭效果)
	var conj1: Array = []
	for en2: Dictionary in pool1:
		if String(en2.alg).contains(" D "):
			conj1.append(en2)
	# end_atoms = 小原子 + 摆位缀(收尾 DFS 专用小域;小原子 = dR 3U± dR' 共轭,
	# 探针 9 实测 ≤6 格效果类的唯一来源)
	var end_atoms: Array = []
	for at4: Dictionary in atoms:
		var a4: String = String(at4.alg)
		if a4.contains(" D "):
			continue
		if a4.contains("3U") and a4.contains("R"):
			end_atoms.append(_cn_entry(a4, at4.perm, pc))
	for cn4: String in conn:
		end_atoms.append(_cn_entry(cn4, conn[cn4], pc))
	_cn_ctx[n] = {"cells": cells, "pc": pc, "m": cells.size(), "pool1": pool1,
			"u1": u1, "conj1": conj1,
			"bfs_atoms": bfs_atoms, "end_atoms": end_atoms,
			"cap": 800}
	return _cn_ctx[n]


## 宏置换提取(§6.3 语义环范式):复原态 6n² 填唯一 id(中心格 0..m−1)→
## apply → 读回(中心格在任意层转下互相封闭)。
static func _cn_id_perm(alg: String, n: int, cells: PackedInt32Array) -> PackedInt32Array:
	var id := PackedByteArray()
	id.resize(6 * n * n)
	id.fill(200)
	for i in cells.size():
		id[cells[i]] = i
	_apply_alg(id, alg)
	var perm := PackedInt32Array()
	perm.resize(cells.size())
	for i in cells.size():
		perm[i] = int(id[cells[i]])
	return perm


## 池条目:置换 + keeps(面 setwise 保持位掩码)+ touch(被换出面掩码,BFR 剪枝;
## n≥7 中心格 >64,面级 6 bit 替代 4 阶的格级 moves)+ 步数。
static func _cn_entry(alg: String, perm: PackedInt32Array, pc: int) -> Dictionary:
	var keeps := 0
	var touch := 0
	for j in perm.size():
		var src: int = perm[j]
		if src != j:
			touch |= 1 << (src / pc)
	for fi in 6:
		var same := true
		for i in pc:
			var src2: int = perm[fi * pc + i]
			if src2 < fi * pc or src2 >= (fi + 1) * pc:
				same = false
				break
		if same:
			keeps |= 1 << fi
	return {"alg": alg, "perm": perm, "keeps": keeps, "touch": touch,
			"tokens": LBL._token_count(alg)}


static func _cn_apply(st: PackedByteArray, perm: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(st.size())
	for j in st.size():
		out[j] = st[perm[j]]
	return out


## 已归位中心块数(色 == 面号;P3 进度口径的 n 阶版)。
static func _cn_placed(st: PackedByteArray, pc: int) -> int:
	var k := 0
	for i in st.size():
		if st[i] == i / pc:
			k += 1
	return k


## 完成面位掩码(面 fi 中心格全 = fi)。
static func _cn_done_mask(st: PackedByteArray, pc: int) -> int:
	var mask := 0
	for fi in 6:
		var same := true
		for i in pc:
			if st[fi * pc + i] != fi:
				same = false
				break
		if same:
			mask |= 1 << fi
	return mask


## 六面中心各自同色(阶段判定,任意色朝向无关;6n² facelets 直查)。
static func _cn_uniform(f: PackedByteArray, n: int) -> bool:
	var pc: int = (n - 2) * (n - 2)
	for fi in 6:
		var ref: int = f[fi * n * n + n + 1]  # 首中心格 (1,1)
		for r in range(1, n - 1):
			for c in range(1, n - 1):
				if f[fi * n * n + r * n + c] != ref:
					return false
	return true


static func _cn_state_of(f: PackedByteArray, n: int) -> PackedByteArray:
	var cells: PackedInt32Array = _cn_cells(n)
	var st := PackedByteArray()
	st.resize(cells.size())
	for i in cells.size():
		st[i] = f[cells[i]]
	return st


static func _cn_key(st: PackedByteArray) -> int:
	return hash(st)


## 单面最大对格数(第一完成面的引导评分,done=0 期主键)。
static func _cn_max_align(st: PackedByteArray, pc: int) -> int:
	var m := 0
	for fi in 6:
		var k := 0
		for i in pc:
			if st[fi * pc + i] == fi:
				k += 1
		if k > m:
			m = k
	return m


## 6 位掩码计数(BFS/贪心评分用)。
static func _popcount6(m: int) -> int:
	var k := 0
	for fi in 6:
		if m & (1 << fi) != 0:
			k += 1
	return k


## 下一段:贪心 → 卡点约束 BFS → 破坏+恢复 → {}(上层降级)。
static func _cn_segment(st: PackedByteArray, n: int) -> Dictionary:
	var g := _cn_greedy(st, n)
	if not g.is_empty():
		return g
	var b := _cn_bfs(st, n)
	if not b.is_empty():
		return b
	var d := _cn_end_dfs(st, n)
	if not d.is_empty():
		return d
	return _cn_bfr(st, n)


## 收尾 DFS(2026-10-03 探针 8/9 链:收尾坎深 ≥3、深度 2 全遍历 0 正增量;裁域
## 小原子+缀后深度 3 迭代加深在节点预算内完备,n=5 全域 57³=18.5 万节点)
static func _cn_end_dfs(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = _cn_ensure(n)
	var pc: int = ctx.pc
	var done0 := _cn_done_mask(st, pc)
	var p0: int = _cn_placed(st, pc)
	var focus: bool = done0 == 0
	var m0 := 0
	if focus:
		m0 = _cn_max_align(st, pc)
	var sub: Array = []
	for e: Dictionary in ctx.end_atoms:
		if done0 & ~int(e.keeps) == 0:
			sub.append(e)
	var budget := {"n": int(ctx.cap) * 3}
	for depth in [2, 3]:
		var r: Dictionary = _cn_dfs_rec(st, sub, p0, m0, focus, done0, pc, depth, budget)
		if not r.is_empty():
			return r
	return {}


static func _cn_dfs_rec(cur: PackedByteArray, sub: Array, p0: int, m0: int, focus: bool,
		done0: int, pc: int, depth_left: int, budget: Dictionary) -> Dictionary:
	if depth_left == 0 or int(budget.n) <= 0:
		return {}
	var cp: int = _cn_placed(cur, pc)
	for e: Dictionary in sub:
		if int(budget.n) <= 0:
			return {}
		budget.n = int(budget.n) - 1
		var nxt := _cn_apply(cur, e.perm)
		var np: int = _cn_placed(nxt, pc)
		if np < cp:
			continue  # placed 不降(单调剪枝)
		if _cn_done_mask(nxt, pc) & done0 != done0:
			continue  # 完成面保持
		if np > p0 or (focus and _cn_max_align(nxt, pc) > m0):
			return {"segs": [{"alg": String(e.alg), "perm": e.perm,
					"tokens": int(e.tokens), "inc": np - p0,
					"text": "中心收尾宏:精确整理送回 %d 块" % (np - p0), "bfs": true}]}
		var r: Dictionary = _cn_dfs_rec(nxt, sub, p0, m0, focus, done0, pc, depth_left - 1, budget)
		if not r.is_empty():
			var segs: Array = r.segs
			segs.push_front({"alg": String(e.alg), "perm": e.perm,
					"tokens": int(e.tokens), "inc": np - p0,
					"text": "中心收尾宏:精确整理送回 %d 块" % int(r.segs[0].inc), "bfs": true})
			return {"segs": segs}
	return {}


## depth1 贪心:全池扫描,完成面保持 ∧ placed 严格增,择 (inc 最大, tokens 最短)。
static func _cn_greedy(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = _cn_ensure(n)
	var pc: int = ctx.pc
	var done := _cn_done_mask(st, pc)
	var p0: int = _cn_placed(st, pc)
	# 评分(人类降阶法结构,2026-10-03 实证调优):
	#   done=0 期 = lex(单面最大对格增, placed 增)——集中堆出第一个完成面;分散推进
	#   placed 会落入「高 placed 无完成面」死坎(全部 15 预演态同款卡点);
	#   done≠0 期 = placed 增(完成面由 keeps 硬约束保护,4 阶语义)。
	# 平局取短;first-hit 早退(7 阶池域全扫每段秒级,不可负担)
	var best := {}
	var focus: bool = done == 0
	var m0 := 0
	if focus:
		m0 = _cn_max_align(st, pc)
	for entry: Dictionary in ctx.pool1:
		if done & ~int(entry.keeps) != 0:
			continue  # 破已完成面
		var st2 := _cn_apply(st, entry.perm)
		var inc: int = _cn_placed(st2, pc) - p0
		var ma: int = 0
		if focus:
			ma = _cn_max_align(st2, pc) - m0
			# focus 期严格单调(2026-10-05 二轮修复):对格非降(降 = 与 placed 度量
			# 互相让位造成 43↔44 无限震荡,n=6 实测 300 段烧穿);对格平台期需 placed
			# 增;对格爬升期允许 placed ≤2 回退(腾位再插入)
			if ma < 0:
				continue
			if ma == 0 and inc <= 0:
				continue
			if ma > 0 and inc < -2:
				continue
		elif inc <= 0:
			continue
		var tok: int = int(entry.tokens)
		var key2: int = inc
		if focus:
			key2 = ma * 1000 + inc
		best = {"alg": String(entry.alg), "perm": entry.perm, "inc": inc,
				"tokens": tok, "k": key2, "text": "中心交换宏:送回 %d 块中心" % inc}
		break  # first-hit:命中即取(2026-10-03 性能实证,最优全扫在 n=7 不可负担)
	if best.is_empty():
		return {}
	return {"alg": String(best.alg), "perm": best.perm, "inc": int(best.inc),
			"tokens": int(best.tokens), "text": String(best.text), "bfs": false}


## 卡点约束 BFS:在「每步宏完成面保持 ∧ placed 不降」子空间完备搜索 placed 增路径。
## 返回 {segs: [宏条目...]}(首条 placed 增路径,逐宏单调)或 {}(穷尽无解)。
static func _cn_bfs(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = _cn_ensure(n)
	var pc: int = ctx.pc
	var p0: int = _cn_placed(st, pc)
	var done0 := _cn_done_mask(st, pc)
	var focus: bool = done0 == 0
	var m0 := 0
	if focus:
		m0 = _cn_max_align(st, pc)  # focus 期目标通道:maxalign 净增(最后 1 格进面)
	var sub: Array = []
	for e: Dictionary in ctx.bfs_atoms:
		if done0 & ~int(e.keeps) == 0:
			sub.append(e)
	var queue: Array = [[st, [], p0, m0]]
	var visited := {_cn_key(st): true}
	var nodes := 1
	var cap: int = ctx.cap
	while not queue.is_empty() and nodes < cap:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		var cp: int = entry[2]
		var cm: int = entry[3]
		if path.size() >= CN_BFS_DEPTH:
			continue
		var done := _cn_done_mask(cur, pc)
		for e: Dictionary in sub:
			if done & ~int(e.keeps) != 0:
				continue
			var nxt: PackedByteArray = _cn_apply(cur, e.perm)
			var np: int = _cn_placed(nxt, pc)
			# 剪枝:done≠0 期 placed 不降;focus 期对格非降 + placed 有底
			# p0-3(腾位预算,与贪心 focus 度量同口径,2026-10-05)
			var nm: int = cm
			if focus:
				nm = _cn_max_align(nxt, pc)
				if nm < cm or np < p0 - 3:
					continue
			elif np < cp:
				continue
			var key := _cn_key(nxt)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append({"alg": String(e.alg), "perm": e.perm,
					"tokens": int(e.tokens), "inc": np - cp})
			if np > p0 or (focus and nm > m0):
				var segs: Array = []
				for m: Dictionary in path2:
					segs.append({"alg": String(m.alg), "perm": m.perm,
							"inc": int(m.inc), "tokens": int(m.tokens),
							"text": "中心整理宏:重排未完成面后送回 %d 块" % int(m.inc),
							"bfs": true})
				return {"segs": segs}
			if nodes >= CN_BFS_NODES:
				break
			queue.append([nxt, path2, np, nm])
	return {}


## 破坏+恢复段(§4.2 M 族搜索化的 n 阶版):单宏有意破已完成面 → 修复 BFS 在
## 「原完成面逐宏保持(已破者除外)∧ placed 逐宏不降」约束下恢复并净推进;
## 段级判据 = placed 严格增 ∧ 完成面恢复保持(段内破允,即宏段语义)。
static func _cn_bfr(st: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = _cn_ensure(n)
	var pc: int = ctx.pc
	var done0 := _cn_done_mask(st, pc)
	# P4b 推广:无完成面时同样可用(无完成面卡点实测,2026-10-03 探针 3:
	# n=5 placed 41/54 无完成面卡死)——破口 = placed 掉幅,恢复 = 净增;
	# done0≠0 时恢复须先补回完成面(与 4 阶语义一致)
	var p0: int = _cn_placed(st, pc)
	var m0 := 0
	if done0 == 0:
		m0 = _cn_max_align(st, pc)  # focus 期修复目标通道:maxalign 净增(暂破允许)
	var misplaced_faces := 0
	for fi in 6:
		for i in pc:
			if st[fi * pc + i] != fi:
				misplaced_faces |= 1 << fi
				break
	var cands: Array = []
	for e: Dictionary in ctx.conj1:
		var s1 := _cn_apply(st, e.perm)
		var p1: int = _cn_placed(s1, pc)
		if done0 != 0:
			if int(e.keeps) & done0 == done0:
				continue  # 不破口(保持族已由贪心/BFS 搜过)
		elif p1 >= p0:
			continue  # 无完成面:只有真掉 placed 的宏才是破口(不降者贪心/BFS 已搜过)
		if int(e.touch) & misplaced_faces == 0:
			continue  # 不触及错位格:修复无从触及,必无效
		if p1 < p0 - 4:
			continue
		cands.append({"e": e, "s1": s1, "p1": p1})
	# 排序:done0≠0 = 浅破优先(4 阶语义);无完成面 = 深破优先(2026-10-03 探针 5
	# 实测:无完成面卡点的可修复破口集中在最大掉幅 p0−4,浅破口修复不出净增)
	if done0 != 0:
		cands.sort_custom(func(a, b) -> bool: return int(a.p1) > int(b.p1))
	else:
		cands.sort_custom(func(a, b) -> bool: return int(a.p1) < int(b.p1))
	var tried := 0
	for c: Dictionary in cands:
		if tried >= CN_BFR_CANDS:
			break
		tried += 1
		var rep := _cn_repair(c.s1, done0, p0, n, m0)
		if rep.is_empty():
			continue
		var e: Dictionary = c.e
		var algs: Array = [String(e.alg)]
		var net: PackedInt32Array = e.perm
		var last: PackedByteArray = rep.state
		var pend: int = _cn_placed(last, pc)
		for m: Dictionary in rep.path:
			algs.append(String(m.alg))
			net = _perm_compose(net, m.perm)
		return {"alg": " ".join(algs), "perm": net, "inc": pend - p0,
				"tokens": LBL._token_count(" ".join(algs)),
				"text": "破坏+恢复宏:借已完成面中转,净送回 %d 块中心" % (pend - p0),
				"bfs": true}
	return {}


## 修复 BFS:从破口态出发,每步宏保持 done0 ∩ 当前完成面 ∧ placed 不降;
## 目标 = 完成面 ⊇ done0 ∧ placed > p0(净推进)。
static func _cn_repair(s1: PackedByteArray, done0: int, p0: int, n: int, m0: int) -> Dictionary:
	var ctx: Dictionary = _cn_ensure(n)
	var pc: int = ctx.pc
	var queue: Array = [[s1, []]]
	var visited := {_cn_key(s1): true}
	var nodes := 1
	var cap: int = int(ctx.cap) / 4  # 修复 BFS 便宜化:多破口候选轮换优于单候选深挖(2026-10-04)
	while not queue.is_empty() and nodes < cap:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		if path.size() >= 6:
			continue
		var must := done0 & _cn_done_mask(cur, pc)
		for e: Dictionary in ctx.bfs_atoms:
			if must & ~int(e.keeps) != 0:
				continue
			var nxt: PackedByteArray = _cn_apply(cur, e.perm)
			var np: int = _cn_placed(nxt, pc)
			if np < _cn_placed(cur, pc):
				continue
			var key := _cn_key(nxt)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append({"alg": String(e.alg), "perm": e.perm})
			var goal: bool = np > p0 or (done0 == 0 and _cn_max_align(nxt, pc) > m0)
			if goal and _cn_done_mask(nxt, pc) & done0 == done0:
				return {"state": nxt, "path": path2}
			if nodes >= CN_BFR_NODES:
				break
			queue.append([nxt, path2])
	return {}


## 5-7 阶中心段求解:{ok, alg, stages, moves, segments}(结构同 4 阶 solve_centers);
## 未覆盖构型 = 降级 fail loud(P4b 熔断条款,error 带降级标记,不静默)。
static func _cn_solve(facelets: PackedByteArray, n: int) -> Dictionary:
	_ensure_centers()  # stage 契约共用常量;池按 n 键控独立
	var st := _cn_state_of(facelets, n)
	var pc: int = (n - 2) * (n - 2)
	if _cn_done_mask(st, pc) == 63:
		return {"ok": true, "alg": "", "stages": [{"name": STAGE_NAMES_NXN[0], "alg": ""}],
				"moves": 0, "segments": []}
	# 真中心预对齐(2026-10-05 降级率修复之一):奇数阶打乱含核心层转层时,真中心
	# 整体搬到别的面(实测 scramble(20) 后 88-93% 偏离原面),『每面=原色』目标
	# 不可达 → 降级率 100%。先做一次全 Cube 旋转(全部 n 层同向转,层记号展开)
	# 把核转回原姿态,目标即回到可达域;偶数阶无核,跳过。
	var pre := _cn_prealg(st, n)
	var segs: Array = []
	var all: Array = []
	var total := 0
	if pre != "":
		st = _cn_apply(st, _cn_id_perm(pre, n, _cn_cells(n)))
		segs.append({"alg": pre, "text": "真中心预对齐:整 Cube 旋转把色方案转回原姿态"})
		all.append(pre)
		total += LBL._token_count(pre)
	# 收敛仍靠贪心→逃逸链(2026-10-05 实验链定稿:guard 上调/随机重启/逃逸搜索
	# 加宽/time box 四路实验对 lex 局部 optimum(差 1-2 格收尾坎)全部 0 破解,
	# 降级率仍 100%——剩余缺口 = 宏族扩充(中盘 3-cycle + 收尾两面宏,§6 入池
	# 条款逐条实测),预计落地时 guard 需上调至 100-250 段/400-900 步,见 EXPERIENCE。
	# 本函数保留:预对齐(可达性前提)+ focus 单调化(禁 placed↔对格震荡)。
	var guard := 0
	while _cn_done_mask(st, pc) != 63:
		guard += 1
		if guard > CN_STAGE_GUARD or total >= CN_MOVE_LIMIT:
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "中心段模板池未覆盖(降级): 超 guard 上限(段 %d / 步 %d)"
							% [guard, total]}
		var seg := _cn_segment(st, n)
		if seg.is_empty():
			# 约束搜索穷尽 = 降级 fail loud(P3 熔断条款同款,P4b 续用)
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "中心段模板池未覆盖(降级): 卡点态 %s" % _cn_key(st)}
		for m in (seg.segs if seg.has("segs") else [seg]):
			st = _cn_apply(st, m.perm)
			segs.append({"alg": String(m.alg), "text": String(m.text)})
			all.append(String(m.alg))
			total += int(m.tokens)
	var joined := " ".join(all)
	return {"ok": true, "alg": joined,
			"stages": [{"name": STAGE_NAMES_NXN[0], "alg": joined}],
			"moves": LBL._token_count(joined), "segments": segs}


## 真中心预对齐旋转搜索(仅奇数阶):当前真中心排布 = 原色方案在某个核心旋转
## ρ 下像;枚举 24 个旋转(x^a y^b / y^a z^b / z^a x^b,a,b∈0..3,层记号展开),
## 逐个模拟『应用后真中心各回原面』,命中返回其 alg,未命中返回 ""(理论必命中:
## 核心姿态 ∈ 24 旋转)。
static func _cn_prealg(st: PackedByteArray, n: int) -> String:
	if n % 2 == 0:
		return ""
	var cells: PackedInt32Array = _cn_cells(n)
	var pc: int = (n - 2) * (n - 2)
	var mid: int = (n - 1) / 2  # 面内真中心格 (mid, mid) ∈ 1..n-2
	var idx := PackedInt32Array()
	for fi in 6:
		idx.append(fi * pc + (mid - 1) * (n - 2) + (mid - 1))
	var axis_algs := {
		"R": " ".join(PackedStringArray(_cn_axis_tokens("R", n))),
		"U": " ".join(PackedStringArray(_cn_axis_tokens("U", n))),
		"F": " ".join(PackedStringArray(_cn_axis_tokens("F", n))),
	}
	var pairs := [["R", "U"], ["U", "F"], ["F", "R"]]
	for a in 4:
		for b in 4:
			if a == 0 and b == 0:
				continue
			for pr: Array in pairs:
				var alg := ""
				for i in a:
					alg += axis_algs[pr[0]] + " "
				for i in b:
					alg += axis_algs[pr[1]] + " "
				alg = alg.strip_edges()
				var st2 := _cn_apply(st, _cn_id_perm(alg, n, cells))
				var ok := true
				for fi in 6:
					if st2[idx[fi]] != fi:
						ok = false
						break
				if ok:
					return alg
	return ""


## 全 Cube 旋转的层记号展开:绕 face 轴全部 n 层同向 90°(如 x = R 向全层)。
static func _cn_axis_tokens(face: String, n: int) -> PackedStringArray:
	var toks := PackedStringArray()
	for k in range(1, n):
		toks.append(face if k == 1 else "%d%s" % [k, face])
	return toks


## 5-7 阶 hint:stage 0 = 中心段建议(贪心首宏);stage 1 = 转组棱段建议。
static func _cn_hint(facelets: PackedByteArray, n: int) -> Dictionary:
	_ensure_centers()
	var sc := stage_check(facelets)
	var pc: int = (n - 2) * (n - 2)
	var progress := float(_cn_placed(_cn_state_of(facelets, n), pc)) / float(6 * pc)
	if sc == 1:
		return _pr_hint(facelets, n)
	var st := _cn_state_of(facelets, n)
	var seg := _cn_segment(st, n)
	if seg.is_empty():
		return {"stage": sc, "progress": progress, "suggestion": {},
				"error": "中心段模板池未覆盖(降级): 卡点态 %s" % _cn_key(st)}
	if seg.has("segs"):
		seg = seg.segs[0]
	return {"stage": sc, "progress": progress,
			"suggestion": {"piece": "中心", "alg": String(seg.alg), "text": String(seg.text)}}


# ================================ 5-7 阶组棱段(P4b) ================================
## 每棱 = 2 wing + (n−4) mid(P4b 条款:5 阶 1、6 阶 2、7 阶 3)。
## - 块几何(坐标法,探针实测生成式):棱块 = 恰两分量 abs=n−1;翼 = 第三分量
##   abs=n−3;mid = 更内。每块两贴面格同 id,置换经模拟器实测读回(§M7 三系统
##   入池条款机制化:块封闭 + 中心颜色态保持,不满足者不入池);
## - 模板家族(全部构建期实测入池):
##   wing 池 = P4a 基型(除 PLL)× y4 × x2 × U^a D^b(前缀);
##   W 池 = dRw U R' U' dRw' 宽层夹心族(§M4.1,层档 d=3..n−2)× y4 × x2 × U^a D^b;
##   W² 池 = W 姿态 × 缀{U,U',U2} × W 姿态(§M4.2 对换器/配对器)× U^a 前缀,去重保短;
## - 统一判据(两族宏互相搅动 mid/wing——探针实测 r 系动 mid、W 系动 wing,
##   §M0.1 避让纪律的机制化):进度 = (整棱数, 已组块数) lexicographic;
##   保持 = 每色最大集中度不降(组可整体换棱,不许拆;整棱由色判据自动蕴含);
## - 顺序条款(先 mid-mid 链配对、再 mid-wing 合并)由评分结构承载:
##   链/对 = 已组块增,合并 = 整棱增;贪心/卡点 BFS 模拟验证逐段单调;
## - 卡点 = 非单调约束 BFS(允许段内拆 ≤1 组后净恢复,§M6.2 条款)→
##   穷尽 = 降级 fail loud(『组棱段模板池未覆盖(降级)』,P4b 熔断条款)。

const PR_STAGE_GUARD := 120
const PR_MOVE_LIMIT := 720
const PR_TIME_BUDGET_MS := 15000  # 单态求解时间盒(2026-10-04:坎搜索在 GDScript 下
                                 # 10-60s/坎,时间盒管总账,超限 = 降级 fail loud)
const PR_BFS_NODES := 2500
const PR_BFS_DEPTH := 2
const PR_W3_NODES := 50000  # W³ 深度 1 线性全扫上限(2.4 万条域 × 每条一次 apply,实测秒级)

## W 夹心族基础核(§M4.1:两个 core;层档 d 按阶展开 3..n−2)
const PR_W_CORES := ["%dRw U R' U' %dRw'", "%dRw U' R U %dRw'"]
## wing 池基型 = P4a EDGE_BASES 除 PLL 末条(n=5/6/7 探针实测:15 条中心颜色态全保持)

static var _pr_ctx := {}   # n -> {nb, blocks, block_edge, edge_blocks, nbe, pools, bfs_pool}


static func _pr_ensure(n: int) -> Dictionary:
	if _pr_ctx.has(n):
		return _pr_ctx[n]
	_ensure_n(n)
	var e: int = n - 1
	var cells: Array = _cells[n]
	var by_xyz := {}
	for i in cells.size():
		var v: Vector3 = (cells[i] as Dictionary).c
		var key := "%d,%d,%d" % [int(v.x), int(v.y), int(v.z)]
		if not by_xyz.has(key):
			by_xyz[key] = []
		(by_xyz[key] as Array).append(i)
	var wings: Array = []
	var mids: Array = []
	for key: String in by_xyz:
		var arr: Array = by_xyz[key]
		if arr.size() != 2:
			continue
		var parts: PackedStringArray = key.split(",")
		var abs_e := 0
		var abs_in := -1
		for p in parts:
			var a: int = abs(int(p))
			if a == e:
				abs_e += 1
			else:
				abs_in = a
		if abs_e != 2:
			continue
		if abs_in == e - 2:
			wings.append([key, arr])
		else:
			mids.append([key, arr])
	wings.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	mids.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	# 块表:wing 先(mid 配对段不动 wing 编号口径);棱 id = 两 abs=e 分量带通配键
	var blocks := PackedInt32Array()      # 块 b -> 2 facelet 下标
	var block_edge := PackedByteArray()   # 块 b -> 棱 id(= 色 id)
	var edge_id := {}
	var edge_blocks: Array = []           # 棱 e -> [块 id...](wing 序 + mid 序,坐标序固定)
	for w: Array in wings:
		var bid: int = blocks.size() / 2
		var eid := _pr_edge_key(String(w[0]), e)
		if not edge_id.has(eid):
			edge_id[eid] = edge_id.size()
			edge_blocks.append([])
		blocks.append(w[1][0])
		blocks.append(w[1][1])
		block_edge.append(edge_id[eid])
		edge_blocks[edge_id[eid]].append(bid)
	for md: Array in mids:
		var bid2: int = blocks.size() / 2
		var eid2 := _pr_edge_key(String(md[0]), e)
		if not edge_id.has(eid2):
			edge_id[eid2] = edge_id.size()
			edge_blocks.append([])
		blocks.append(md[1][0])
		blocks.append(md[1][1])
		block_edge.append(edge_id[eid2])
		edge_blocks[edge_id[eid2]].append(bid2)
	var nb: int = blocks.size() / 2
	var nbe: int = n - 2
	# 摆位前缀置换(块级;外层 U/D 不拆块)
	var up: Array = []
	var dp: Array = []
	for kk in 4:
		var us: String = _u_pow(kk)
		var ds: String = _d_pow(kk)
		up.append(_pr_perm_of(us, n, blocks, edge_id) if us != "" else PackedInt32Array())
		dp.append(_pr_perm_of(ds, n, blocks, edge_id) if ds != "" else PackedInt32Array())
	# 宏置换缓存(基础姿态,池合成源)
	var wing_pool: Array = []
	var seen := {}
	for base in EDGE_BASES:
		if base == "3R2 U2 3R2 u2 3R2 u2":
			continue  # PLL parity 宏:n≥5 探针实测破中心颜色态,不入池
		for k in 4:
			for xr in 2:
				var core: String = _rotate_y(base, k)
				if xr == 1:
					core = _remap_x2(core)
				var pcore := _pr_perm_of(core, n, blocks, edge_id)
				if pcore.size() != nb:
					continue  # 破中心颜色态(拒入,§M7 条款)
				for ua in 4:
					for da in 4:
						var perm: PackedInt32Array = pcore
						var pre := ""
						if ua > 0:
							perm = _perm_compose(up[ua], perm)
							pre = _u_pow(ua) + " "
						if da > 0:
							perm = _perm_compose(dp[da], perm)
							pre += _d_pow(da) + " "
						var alg := pre + core
						if seen.has(alg):
							continue
						seen[alg] = true
						wing_pool.append(_pr_entry(alg, perm))
	# W 池:宽层夹心核 × y4 × x2 × U^a D^b
	var w_pool: Array = []
	var w_atoms: Array = []  # 无前缀姿态(W² 合成源)
	for d in range(3, n - 1):
		for base0: String in PR_W_CORES:
			var base2: String = base0 % [d, d]
			for k2 in 4:
				for xr2 in 2:
					var core2: String = _rotate_y(base2, k2)
					if xr2 == 1:
						core2 = _remap_x2(core2)
					var pc2 := _pr_perm_of(core2, n, blocks, edge_id)
					if pc2.size() != nb:
						continue
					w_atoms.append({"alg": core2, "perm": pc2})
					for ua2 in 4:
						for da2 in 4:
							var perm2: PackedInt32Array = pc2
							var pre2 := ""
							if ua2 > 0:
								perm2 = _perm_compose(up[ua2], perm2)
								pre2 = _u_pow(ua2) + " "
							if da2 > 0:
								perm2 = _perm_compose(dp[da2], perm2)
								pre2 += _d_pow(da2) + " "
							var alg2 := pre2 + core2
							if seen.has(alg2):
								continue
							seen[alg2] = true
							w_pool.append(_pr_entry(alg2, perm2))
	# W² 池:W 姿态 × 缀 × W 姿态 × U^a 前缀(同效果去重保短;§M4.2 配对器)
	var conn := {}
	for cn in ["", "U", "U'", "U2"]:
		if cn != "":
			conn[cn] = up[["", "U", "U2", "U'"].find(cn)]
	var seen_eff := {}
	var w2_pool: Array = []
	for a1: Dictionary in w_atoms:
		for cn: String in conn:
			for a2: Dictionary in w_atoms:
				var perm3: PackedInt32Array = _perm_compose(a1.perm, conn[cn])
				perm3 = _perm_compose(perm3, a2.perm)
				var ekey := _pr_perm_key(perm3)
				var alg_full: String = String(a1.alg) + (" " + cn if cn != "" else "") + " " + String(a2.alg)
				var prev: String = String(seen_eff.get(ekey, ""))
				if prev != "" and prev.length() <= alg_full.length():
					continue
				seen_eff[ekey] = alg_full
				var perms := perm3
				if prev != "":
					# 替换已登记同效果条目:重建池(条目少,重建代价可忽略)
					for i2 in w2_pool.size():
						if String(w2_pool[i2].alg) == prev:
							w2_pool.remove_at(i2)
							break
				for ua3 in 4:
					var perm4 := perms if ua3 == 0 else _perm_compose(up[ua3], perms)
					var alg3: String = (_u_pow(ua3) + " " if ua3 > 0 else "") + alg_full
					w2_pool.append(_pr_entry(alg3, perm4))
	var pools: Array = [wing_pool, w_pool, w2_pool]
	# BFS 域 = 无前缀核(W 姿态 + W² 姿态;2026-10-03 同中心段教训:前缀展开域在
	# 深度 2 全遍历口径下覆盖率不足,核域² 在预算内完备)+ W³ 三段闭环域
	# (§M6.2 既定扩域:W² 贪心覆盖 ~50%,收尾 2-4 组坎 = W³ 域的深度 1 遍历)
	var w2_core: Array = []
	for en3: Dictionary in w2_pool:
		var algf: String = String(en3.alg)
		if algf.begins_with("U ") or algf.begins_with("U2 ") or algf.begins_with("U' ") \
				or algf.begins_with("D ") or algf.begins_with("D2 ") or algf.begins_with("D' "):
			continue
		w2_core.append(en3)
	var bfs_pool: Array = []
	for en2: Dictionary in w_pool:
		var alge: String = String(en2.alg)
		if alge.begins_with("U ") or alge.begins_with("U2 ") or alge.begins_with("U' ") \
				or alge.begins_with("D ") or alge.begins_with("D2 ") or alge.begins_with("D' "):
			continue
		bfs_pool.append(en2)
	bfs_pool.append_array(w2_core)
	var w3_seen := {}
	var w3_budget := 200000
	var w3_pool: Array = []
	for a3a: Dictionary in w2_core:
		for cn3c: String in conn:
			for a3b: Dictionary in w_atoms:
				if w3_budget <= 0:
					break
				w3_budget -= 1
				var p3: PackedInt32Array = _perm_compose(a3a.perm, conn[cn3c])
				p3 = _perm_compose(p3, a3b.perm)
				var k3 := _pr_perm_key(p3)
				if w3_seen.has(k3):
					continue
				w3_seen[k3] = true
				w3_pool.append(_pr_entry(String(a3a.alg) + " " + cn3c + " " + String(a3b.alg), p3))
			if w3_budget <= 0:
				break
		if w3_budget <= 0:
			break
	_pr_ctx[n] = {"nb": nb, "blocks": blocks, "block_edge": block_edge,
			"edge_blocks": edge_blocks, "nbe": nbe,
			"pools": pools, "bfs_pool": bfs_pool, "w3_pool": w3_pool,
			"up": up, "dp": dp}
	return _pr_ctx[n]


## 棱 id 键:两 abs=e 分量固定、第三分量通配(wing/mid 同棱同键)。
static func _pr_edge_key(key: String, e: int) -> String:
	var parts: PackedStringArray = key.split(",")
	var out := ""
	for pi in 3:
		var pv: int = int(parts[pi])
		out += ("*" if abs(pv) != e else str(pv)) + ","
	return out


## 块级宏置换提取(§M7 三系统一次 apply):复原态块两格同 id、中心格独立 id →
## apply → 块封闭 + 中心面颜色态保持检查,通过返回块置换,否则空(拒入池)。
static func _pr_perm_of(alg: String, n: int, blocks: PackedInt32Array, edge_id: Dictionary) -> PackedInt32Array:
	var nb: int = blocks.size() / 2
	var id := PackedByteArray()
	id.resize(6 * n * n)
	id.fill(200)
	for b in nb:
		id[blocks[2 * b]] = b
		id[blocks[2 * b + 1]] = b
	var pc: int = (n - 2) * (n - 2)
	var ci := 0
	for fi in 6:
		for r in range(1, n - 1):
			for c in range(1, n - 1):
				id[fi * n * n + r * n + c] = 100 + ci
				ci += 1
	_apply_alg(id, alg)
	var perm := PackedInt32Array()
	perm.resize(nb)
	for b in nb:
		var va: int = id[blocks[2 * b]]
		var vb: int = id[blocks[2 * b + 1]]
		if va >= 100 or vb >= 100 or va != vb:
			return PackedInt32Array()  # 拆块(防御)或中心格串入(不可能,防御)
		perm[b] = va
	return perm


static func _pr_entry(alg: String, perm: PackedInt32Array) -> Dictionary:
	var mask := 0
	for b in perm.size():
		if perm[b] != b:
			mask |= 1 << b
	return {"alg": alg, "perm": perm, "mask": mask, "tokens": LBL._token_count(alg)}


static func _pr_perm_key(perm: PackedInt32Array) -> String:
	var parts: PackedStringArray = []
	for b in perm.size():
		parts.append(str(perm[b]))
	return ",".join(parts)


## 6n² facelets → 块色态(色 id = 复原态所在棱号;朝向无关:两贴面色对唯一)。
static func _pr_state_of(f: PackedByteArray, n: int) -> PackedByteArray:
	var ctx: Dictionary = _pr_ensure(n)
	var blocks: PackedInt32Array = ctx.blocks
	var nb: int = ctx.nb
	var solved := PackedByteArray()
	solved.resize(6 * n * n)
	for i in solved.size():
		solved[i] = i / (n * n)
	var pair2edge := {}
	for b in nb:
		var pa: int = solved[blocks[2 * b]]
		var pb: int = solved[blocks[2 * b + 1]]
		pair2edge[mini(pa, pb) * 6 + maxi(pa, pb)] = ctx.block_edge[b]
	var st := PackedByteArray()
	st.resize(nb)
	for b2 in nb:
		var pa2: int = f[blocks[2 * b2]]
		var pb2: int = f[blocks[2 * b2 + 1]]
		st[b2] = pair2edge.get(mini(pa2, pb2) * 6 + maxi(pa2, pb2), 255)
	return st


## 块色态合法性(255 = 非法双色对哨兵;非法魔方态 fail loud 用)。
static func _pr_state_ok(st: PackedByteArray) -> bool:
	for v in st:
		if v > 11:
			return false
	return true


static func _pr_apply(st: PackedByteArray, perm: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(st.size())
	for b in st.size():
		out[b] = st[perm[b]]
	return out


## 每棱每色计数 + 每色最大集中度(保持判据的色态视图)。
static func _pr_stats(st: PackedByteArray, ctx: Dictionary) -> Array:
	var cnt := PackedInt32Array()
	cnt.resize(144)
	var block_edge: PackedByteArray = ctx.block_edge
	for b in st.size():
		cnt[int(block_edge[b]) * 12 + st[b]] += 1
	var conc := PackedInt32Array()
	conc.resize(12)
	for eid in 12:
		for c in 12:
			var v: int = cnt[eid * 12 + c]
			if v > conc[c]:
				conc[c] = v
	return [cnt, conc]


## 进度 = (整棱数, 已组块数) lexicographic。
static func _pr_score(st: PackedByteArray, ctx: Dictionary) -> Vector2i:
	var stats: Array = _pr_stats(st, ctx)
	var cnt: PackedInt32Array = stats[0]
	var nbe: int = ctx.nbe
	var prim := 0
	var sec := 0
	for eid in 12:
		for c in 12:
			var v: int = cnt[eid * 12 + c]
			if v >= 2:
				sec += v
			if v == nbe:
				prim += 1
	return Vector2i(prim, sec)


## 保持判据:每色最大集中度不降(组可整体换棱,不许拆;整棱自动蕴含)。
static func _pr_kept(conc0: PackedInt32Array, conc1: PackedInt32Array) -> bool:
	for c in 12:
		if conc0[c] >= 2 and conc1[c] < conc0[c]:
			return false
	return true


## 组棱期进度(0.0~1.0):已组块比例(整棱贡献满格)。
static func _pr_progress(f: PackedByteArray, n: int) -> float:
	var ctx: Dictionary = _pr_ensure(n)
	var st := _pr_state_of(f, n)
	if not _pr_state_ok(st):
		return 0.0
	var s := _pr_score(st, ctx)
	return float(s.y) / float(12 * ctx.nbe)


## 下一段:贪心 → 非单调约束 BFS(允许段内拆 ≤1 组后净恢复)→ {}(降级)。
static func _pr_segment(st: PackedByteArray, ctx: Dictionary) -> Dictionary:
	var g := _pr_greedy(st, ctx)
	if not g.is_empty():
		return g
	return _pr_bfs(st, ctx)


## depth1 贪心:全池扫描,组级保持 ∧ (整棱, 已组块) lex 增,择优(lex 最大,tokens 最短)。
static func _pr_greedy(st: PackedByteArray, ctx: Dictionary) -> Dictionary:
	var s0 := _pr_score(st, ctx)
	var stats0: Array = _pr_stats(st, ctx)
	var conc0: PackedInt32Array = stats0[1]
	# 未组块掩码:作用块集与之无交的条目不可能推进,快速跳过
	var loose := 0
	var nbe: int = ctx.nbe
	var block_edge: PackedByteArray = ctx.block_edge
	var cnt: PackedInt32Array = stats0[0]
	var full := {}
	for eid in 12:
		for c in 12:
			if cnt[eid * 12 + c] == nbe:
				full[eid] = c
	for b in st.size():
		var eid2: int = block_edge[b]
		if not full.has(eid2) or full[eid2] != st[b]:
			loose |= 1 << b
	var best := {}
	for pool: Array in ctx.pools:
		for entry: Dictionary in pool:
			if int(entry.mask) & loose == 0:
				continue
			var st2 := _pr_apply(st, entry.perm)
			var conc1: PackedInt32Array = _pr_stats(st2, ctx)[1]
			if not _pr_kept(conc0, conc1):
				continue
			var s1 := _pr_score(st2, ctx)
			if s1 <= s0:
				continue
			var tok: int = int(entry.tokens)
			if best.is_empty() or s1.x > int(best.px) or (s1.x == int(best.px) and s1.y > int(best.py)) \
					or (s1.x == int(best.px) and s1.y == int(best.py) and tok < int(best.tokens)):
				best = {"alg": String(entry.alg), "perm": entry.perm, "px": s1.x, "py": s1.y,
						"tokens": tok}
	if best.is_empty():
		return {}
	return {"alg": String(best.alg), "perm": best.perm,
			"tokens": int(best.tokens),
			"text": "棱组宏:整棱 %d → %d" % [s0.x, int(best.px)]}


## 非单调约束 BFS(§M6.2 条款):允许段内一步拆 ≤1 组(已组块数掉 ≤2 且整棱不降),
## 段末 = 组级保持(相对初始)∧ score lex 净增;深度 ≤ PR_BFS_DEPTH(整段返回)。
static func _pr_bfs(st0: PackedByteArray, ctx: Dictionary) -> Dictionary:
	var r := _pr_bfs_stage(st0, ctx, ctx.bfs_pool, PR_BFS_DEPTH, PR_BFS_NODES)
	if not r.is_empty():
		return r
	r = _pr_bfs_stage(st0, ctx, ctx.w3_pool, 1, PR_W3_NODES)
	if not r.is_empty():
		return r
	return _pr_w3_compound(st0, ctx)


## 阶段 3:[W³, 核] 复合的定向投影(两阶段化丢失的深度 2 复合恢复;W³ 全池线性
## 预扫取掉幅 ≤2 的 top-K,再各做一次核域线性收尾——全组合 600 万的预算内子集)
static func _pr_w3_compound(st0: PackedByteArray, ctx: Dictionary) -> Dictionary:
	var s0 := _pr_score(st0, ctx)
	var conc0: PackedInt32Array = _pr_stats(st0, ctx)[1]
	var cands: Array = []
	for w3: Dictionary in ctx.w3_pool:
		var s1 := _pr_apply(st0, w3.perm)
		var sc1 := _pr_score(s1, ctx)
		if sc1.x < s0.x or sc1.y < s0.y - 2:
			continue  # 掉幅 >2(拆 >1 组)
		var conc1: PackedInt32Array = _pr_stats(s1, ctx)[1]
		if _pr_kept(conc0, conc1) and sc1 > s0:
			return _pr_mk_seg([w3], s0, ctx)
		cands.append({"st": s1, "sc": sc1, "w": w3})
	cands.sort_custom(func(a, b) -> bool:
		var va: Vector2i = a.sc
		var vb: Vector2i = b.sc
		return va > vb)
	for c: Dictionary in cands.slice(0, 12):
		var st1: PackedByteArray = c.st
		var sc1: Vector2i = c.sc
		for k: Dictionary in ctx.bfs_pool:
			var s2 := _pr_apply(st1, k.perm)
			var conc2: PackedInt32Array = _pr_stats(s2, ctx)[1]
			var s2v := _pr_score(s2, ctx)
			if s2v > s0 and _pr_kept(conc0, conc2):
				return _pr_mk_seg([c.w, k], s0, ctx)
	return {}


## 段组装(宏序列 → {alg, perm, tokens, text})。
static func _pr_mk_seg(macs: Array, s0: Vector2i, ctx: Dictionary) -> Dictionary:
	var algs: Array = []
	var net := PackedInt32Array()
	net.resize(ctx.nb)
	for b in net.size():
		net[b] = b
	for mm: Dictionary in macs:
		algs.append(String(mm.alg))
		var tmp := PackedInt32Array()
		tmp.resize(net.size())
		for b2 in net.size():
			tmp[b2] = net[mm.perm[b2]]
		net = tmp
	var joined := " ".join(algs)
	return {"alg": joined, "perm": net, "tokens": LBL._token_count(joined),
			"text": "棱组整理:BFS 非单调重组后净推进(%d 步)" % macs.size()}


static func _pr_bfs_stage(st0: PackedByteArray, ctx: Dictionary, pool: Array,
		depth: int, node_cap: int) -> Dictionary:
	var s0 := _pr_score(st0, ctx)
	var conc0: PackedInt32Array = _pr_stats(st0, ctx)[1]
	var queue: Array = [[st0, []]]
	var visited := {_pr_state_key(st0): true}
	var nodes := 1
	while not queue.is_empty() and nodes < node_cap:
		var entry: Array = queue.pop_front()
		var cur: PackedByteArray = entry[0]
		var path: Array = entry[1]
		if path.size() >= depth:
			continue
		var sc := _pr_score(cur, ctx)
		for m: Dictionary in pool:
			var st2 := _pr_apply(cur, m.perm)
			var conc2: PackedInt32Array = _pr_stats(st2, ctx)[1]
			var s2 := _pr_score(st2, ctx)
			# 途中:整棱不降,已组块掉幅 ≤2(拆 ≤1 对),末步由段末判据收口
			if s2.x < sc.x or s2.y < sc.y - 2:
				continue
			var key := _pr_state_key(st2)
			if visited.has(key):
				continue
			visited[key] = true
			nodes += 1
			var path2 := path.duplicate()
			path2.append(m)
			if s2 > s0 and _pr_kept(conc0, conc2):
				var algs: Array = []
				var net := PackedInt32Array()
				net.resize(st0.size())
				for b in net.size():
					net[b] = b
				for mm: Dictionary in path2:
					algs.append(String(mm.alg))
					var tmp := PackedInt32Array()
					tmp.resize(net.size())
					for b2 in net.size():
						tmp[b2] = net[mm.perm[b2]]
					net = tmp
				var joined := " ".join(algs)
				return {"alg": joined, "perm": net, "tokens": LBL._token_count(joined),
						"text": "棱组整理:BFS 非单调重组后净推进(%d 步)" % path2.size()}
			if nodes >= node_cap:
				break
			queue.append([st2, path2])
	return {}


static func _pr_state_key(st: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in st.size():
		parts.append(str(st[b]))
	return "".join(parts)


## 5-7 阶组棱段求解(结构同 4 阶 solve_edges;前置 = 中心已解)。
## 未覆盖构型 = 降级 fail loud(P4b 熔断条款,error 带降级标记,不静默)。
static func _pr_solve(facelets: PackedByteArray, n: int) -> Dictionary:
	if not _cn_uniform(facelets, n):
		return {"ok": false, "alg": "", "stages": [], "segments": [],
				"error": "组棱段要求中心已解(先跑 solve_centers)"}
	var ctx: Dictionary = _pr_ensure(n)
	var st := _pr_state_of(facelets, n)
	if not _pr_state_ok(st):
		return {"ok": false, "alg": "", "stages": [], "segments": [],
				"error": "组棱段 facelets 非法(棱块双色对越界,非合法魔方态)"}
	var s0 := _pr_score(st, ctx)
	if s0.x == 12:
		return {"ok": true, "alg": "",
				"stages": [{"name": STAGE_NAMES_NXN[1], "alg": ""}],
				"moves": 0, "segments": []}
	var segs: Array = []
	var all: Array = []
	var total := 0
	var guard := 0
	while _pr_score(st, ctx).x < 12:
		guard += 1
		if guard > PR_STAGE_GUARD or total >= PR_MOVE_LIMIT:
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "组棱段模板池未覆盖(降级): 超 guard 上限(段 %d / 步 %d)"
							% [guard, total]}
		var seg := _pr_segment(st, ctx)
		if seg.is_empty():
			# 非单调搜索穷尽 = P4b 熔断降级(fail loud;分层验收见方案风险 1)
			var sc := _pr_score(st, ctx)
			return {"ok": false, "alg": "", "stages": [], "segments": [],
					"error": "组棱段模板池未覆盖(降级): 整棱 %d/12, 已组块 %d, 块态 %s"
							% [sc.x, sc.y, _pr_state_key(st)]}
		st = _pr_apply(st, seg.perm)
		segs.append({"alg": String(seg.alg), "text": String(seg.text)})
		all.append(String(seg.alg))
		total += int(seg.tokens)
	var joined := " ".join(all)
	return {"ok": true, "alg": joined,
			"stages": [{"name": STAGE_NAMES_NXN[1], "alg": joined}],
			"moves": LBL._token_count(joined), "segments": segs}


## 5-7 阶组棱 hint(中心已解的 stage 1 态):建议 = 段生成首宏;卡点给降级标记
## (P6 失败语义载体)。整棱满态由 _nxn_hint 拦截转 parity/约化注入,不到此处。
static func _pr_hint(facelets: PackedByteArray, n: int) -> Dictionary:
	var ctx: Dictionary = _pr_ensure(n)
	var st := _pr_state_of(facelets, n)
	if not _pr_state_ok(st):
		return {"stage": 1, "progress": 0.0, "suggestion": {},
				"error": "组棱段 facelets 非法(棱块双色对越界,非合法魔方态)"}
	var s := _pr_score(st, ctx)
	var progress := float(s.y) / float(12 * ctx.nbe)
	if s.x == 12:
		return {"stage": 1, "progress": 1.0,
				"suggestion": {"piece": "", "alg": "", "text": "组棱段已完成"},
				"error": "组棱段已完成"}
	var seg := _pr_segment(st, ctx)
	if seg.is_empty():
		return {"stage": 1, "progress": progress, "suggestion": {},
				"error": "组棱段模板池未覆盖(降级): 整棱 %d/12, 已组块 %d" % [s.x, s.y]}
	return {"stage": 1, "progress": progress,
			"suggestion": {"piece": "棱", "alg": String(seg.alg), "text": String(seg.text)}}


# ================================ P5 约化 + parity(docs/v7-teach-nxn-plan.md P5) ================================
## 降阶法第 3 步:中心+棱组完成 → 只转外层 → 提取 3 阶 54 态(角直接对应、外层
## wing 为棱、已解中心为参考)→ lbl_solver.solve;约化后记号在 n 阶 = 外层转动,
## 播放语义相同(提取映射与外层置换交换,TNR 测试对拍兜底)。
## parity 双判据(仅偶数阶 4/6,方案 P5 + 审计第二轮必改 2):
##   OLL = 棱朝向和 mod 2(单棱翻在排列层不可见,必须算朝向;Kociemba 不变量,
##         对位按实际色对的自然朝向判定,排列无关);
##   PLL = 角/棱置换符号比对(3 阶合法态两者相等)。
## 修正公式并入『组棱』段尾(9 段定长契约,stages 拼接 ≡ alg);检测驱动循环
## ≤2 覆盖两类并存(OLL 宏 χ 保持、PLL 宏翻转奇性保持,两类修正互相独立)。
## 宏入池条款(§6 同款,2026-10-04 本会话模拟器实测):复原态应用 → 中心均匀
## 保持 + 棱组 12/12 保持 + 判据效应(OLL:翻转奇性翻转且 χ 保持;PLL:χ 翻转
## 且翻转奇性保持),未过不入池(fail loud,不静默)。
## 来源:speedsolving wiki 4x4x4 Parity Algorithms 公共公式域转译(纯切片
## pure-flip 族;r→3Rw/l→3Lw/2→3Fw2 层换档推 6 阶),社区原记号 → 引擎记号
## (Rw≡r≡2Rw、小写双层同形)。

const PARITY_ALGS := {
	4: {"oll": "r' U2 l F2 l' F2 r2 U2 r U2 r' U2 F2 r2 F2",
		"pll": "3R2 U2 3R2 u2 3R2 u2"},
	6: {"oll": "3Rw' U2 3Lw F2 3Lw' F2 3Rw2 U2 3Rw U2 3Rw' U2 F2 3Rw2 F2",
		"pll": "3Rw2 B2 U2 3Lw2 U2 B2 3Rw2"},
}

const PARITY_LOOP_MAX := 2  # 修正循环上限(方案 P5 裁决:覆盖两类并存)

static var _parity_ready := {}  # n -> true(宏池入池验证已过)


## n 阶复原 facelets(6n²,面号 = i/(n²);宏池入池验证用)。
static func _solved_facelets_n(n: int) -> PackedByteArray:
	var f := PackedByteArray()
	f.resize(6 * n * n)
	for i in f.size():
		f[i] = i / (n * n)
	return f


## 约化提取:n 阶 6n² → 3 阶 54 态。行列映射与 FACES_DEF 几何同源:
## 角格 (0,n−1) 直接对应;棱格(恰一维 ∈ {1,n−2})统一取 1 侧 wing;中心已解作色参考。
static func _reduce_to_54(f: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(54)
	for fi in 6:
		for r3 in 3:
			for c3 in 3:
				var r: int = 0 if r3 == 0 else (n - 1 if r3 == 2 else 1)
				var c: int = 0 if c3 == 0 else (n - 1 if c3 == 2 else 1)
				out[fi * 9 + r3 * 3 + c3] = f[fi * n * n + r * n + c]
	return out


## 棱朝向和(Kociemba 格序口径,排列无关):棱朝向 = U/D 色所在格的序号
## (格 0 → 0,格 1 → 1);不含 U/D 色的中层棱 = F/B 色在格 0 → 0,否则 1。
## 计数(朝向 1 的棱数)mod 2 = OLL parity 判据。标准 Kociemba facelet→cubie
## 映射在该 EDGES 表下对外层转守恒("面归属"版判定不是不变量,勿改回)。
## 前置 = 棱组已解(提取色对全为 12 合法棱色对)。
static func _edge_flip_sum(f54: PackedByteArray) -> int:
	var cnt := 0
	for e: String in LBL.EDGES:
		var idx: Array = LBL.EDGES[e]
		var a: int = f54[idx[0]]
		var b: int = f54[idx[1]]
		if a == b or a > 5 or b > 5:
			continue  # 非法双色对(非棱组解态):判据前置不满足,调用侧兜底
		if a == 0 or a == 3:
			pass  # UD 色在格 0 → 朝向 0
		elif b == 0 or b == 3:
			cnt += 1  # UD 色在格 1 → 朝向 1
		elif a == 2 or a == 5 or b == 2 or b == 5:
			if not (a == 2 or a == 5):
				cnt += 1  # 中层棱:F/B 色在格 1 → 朝向 1
		else:
			continue  # 纯 RL 色对(非法棱色对)
	return cnt


## 置换符号(逆序数奇偶;perm[i] = 位 i 上的块 id)。
static func _perm_sign(perm: PackedInt32Array) -> int:
	var s := 1
	for i in perm.size():
		for j in range(i + 1, perm.size()):
			if perm[i] > perm[j]:
				s = -s
	return s


## parity 双判据:{oll, pll}。OLL = 翻转棱数 mod 2;PLL = 角/棱排列符号不等。
static func _parity_of(f54: PackedByteArray) -> Dictionary:
	var ckey := {}
	for name in LBL.CORNERS:
		var cols: Array = LBL.CORNER_COLORS[name]
		var k := [cols[0], cols[1], cols[2]]
		k.sort()
		ckey[k] = LBL.CORNERS.keys().find(name)
	var cperm := PackedInt32Array()
	cperm.resize(8)
	var ci := 0
	for name2 in LBL.CORNERS.keys():
		var idx: Array = LBL.CORNERS[name2]
		var trip := [f54[idx[0]], f54[idx[1]], f54[idx[2]]]
		trip.sort()
		cperm[ci] = int(ckey[trip])
		ci += 1
	var ekey := {}
	for name3 in LBL.EDGES:
		var cols2: Array = LBL.EDGE_COLORS[name3]
		var k2 := [cols2[0], cols2[1]]
		k2.sort()
		ekey[k2] = LBL.EDGES.keys().find(name3)
	var eperm := PackedInt32Array()
	eperm.resize(12)
	var ei := 0
	var legal := true
	for name4 in LBL.EDGES.keys():
		var idx2: Array = LBL.EDGES[name4]
		var pair := [f54[idx2[0]], f54[idx2[1]]]
		pair.sort()
		if not ekey.has(pair):
			legal = false  # 非法双色对(棱组未解):PLL 判据前置不满足
			break
		eperm[ei] = int(ekey[pair])
		ei += 1
	if not legal:
		return {"oll": false, "pll": false}
	return {"oll": _edge_flip_sum(f54) % 2 == 1,
			"pll": _perm_sign(cperm) != _perm_sign(eperm)}


## n 阶中心均匀 / 棱组配对(判据复用;P5 前置检查统一入口)。
static func _nxn_uniform(f: PackedByteArray, n: int) -> bool:
	if n == CENTER_N:
		_ensure_centers()
		return _centers_uniform(f)
	return _cn_uniform(f, n)


static func _nxn_paired(f: PackedByteArray, n: int) -> int:
	if n == CENTER_N:
		_ensure_edges()
		return _edges_paired(_wing_state_of(f))
	var ctx: Dictionary = _pr_ensure(n)
	return _pr_score(_pr_state_of(f, n), ctx).x


## parity 宏池入池验证(幂等;§6 条款,未过返回 false = 调用侧 fail loud)。
static func _ensure_parity(n: int) -> bool:
	if n % 2 != 0:
		return true  # 奇数阶无 parity
	if _parity_ready.has(n):
		return true
	var algs: Dictionary = PARITY_ALGS.get(n, {})
	if algs.is_empty():
		return false
	var fs := _solved_facelets_n(n)
	var f1 := fs.duplicate()
	_apply_alg(f1, String(algs.oll))
	if not _nxn_uniform(f1, n) or _nxn_paired(f1, n) != 12:
		return false
	var q1 := _parity_of(_reduce_to_54(f1, n))
	if not bool(q1.oll) or bool(q1.pll):
		return false  # OLL 宏须:翻转奇性翻转 ∧ χ 保持
	var f2 := fs.duplicate()
	_apply_alg(f2, String(algs.pll))
	if not _nxn_uniform(f2, n) or _nxn_paired(f2, n) != 12:
		return false
	var q2 := _parity_of(_reduce_to_54(f2, n))
	if bool(q2.oll) or not bool(q2.pll):
		return false  # PLL 宏须:翻转奇性保持 ∧ χ 翻转
	_parity_ready[n] = true
	return true


## 当前态 parity 检测(宏池验证前置;未过返回 {} = fail loud 载体)。
static func _parity_checked(f: PackedByteArray, n: int) -> Dictionary:
	if not _ensure_parity(n):
		return {}
	return _parity_of(_reduce_to_54(f, n))


## parity 存在性(stage_check 用):奇数阶恒无;宏池未过按无 parity 处理
## (fail loud 语义在 solve/hint 层),判据任一触发即存在。
static func _parity_has(f: PackedByteArray, n: int) -> bool:
	if n % 2 != 0:
		return false
	var par := _parity_checked(f, n)
	return not par.is_empty() and (bool(par.oll) or bool(par.pll))


## 4-7 阶全链求解:中心段 → 组棱段 → parity 修正(并入组棱段尾)→ 约化提取 →
## lbl_solver.solve(7 段)。stages 9 段定长;stages 拼接 ≡ alg。
## 分段降级/超限 = ok:false 带原因(熔断条款 fail loud,不静默)。
static func _nxn_solve(facelets: PackedByteArray, n: int) -> Dictionary:
	var rc := solve_centers(facelets)
	if not rc.ok:
		return {"ok": false, "alg": "", "stages": [], "error": "中心段: " + String(rc.error)}
	var f1 := facelets.duplicate()
	_apply_alg(f1, String(rc.alg))
	var re := solve_edges(f1)
	if not re.ok:
		return {"ok": false, "alg": "", "stages": [], "error": "组棱段: " + String(re.error)}
	var f2 := f1.duplicate()
	_apply_alg(f2, String(re.alg))
	var stages: Array = [
		{"name": STAGE_NAMES_NXN[0], "alg": String(rc.alg)},
		{"name": STAGE_NAMES_NXN[1], "alg": String(re.alg)},
	]
	var all: Array = []
	if not String(rc.alg).is_empty():
		all.append(String(rc.alg))
	if not String(re.alg).is_empty():
		all.append(String(re.alg))
	# parity 修正(仅偶数阶;检测驱动循环 ≤2,修正公式并入『组棱』段尾)
	if n % 2 == 0:
		var loop := 0
		while loop < PARITY_LOOP_MAX:
			var par := _parity_checked(f2, n)
			if par.is_empty():
				return {"ok": false, "alg": "", "stages": [],
						"error": "parity 宏池入池验证未过(降级)"}
			if not bool(par.oll) and not bool(par.pll):
				break
			var algs: Dictionary = PARITY_ALGS[n]
			var fix: String = String(algs.oll if bool(par.oll) else algs.pll)
			_apply_alg(f2, fix)
			var seg_alg: String = String(stages[1].alg)
			stages[1].alg = (seg_alg + " " + fix) if seg_alg != "" else fix
			all.append(fix)
			loop += 1
		var par_end := _parity_checked(f2, n)
		if not par_end.is_empty() and (bool(par_end.oll) or bool(par_end.pll)):
			return {"ok": false, "alg": "", "stages": [],
					"error": "parity 修正循环(%d 轮)后仍存在(fail loud)" % PARITY_LOOP_MAX}
	# 约化:提取 3 阶 54 态 → lbl_solver.solve(记号 = 外层转动,n 阶播放语义相同)
	var f54 := _reduce_to_54(f2, n)
	var rl := LBL.solve(f54)
	if not rl.ok:
		return {"ok": false, "alg": "", "stages": [], "error": "约化 3 阶段: " + String(rl.error)}
	for s in rl.stages:
		stages.append(s)
		if not String(s.alg).is_empty():
			all.append(String(s.alg))
	var total_alg := " ".join(all)
	return {"ok": true, "alg": total_alg, "stages": stages, "moves": LBL._token_count(total_alg)}


## parity 修正建议(组棱满后的 LBL 边界注入;返回 {} = 无 parity,不注入)。
static func _parity_suggestion(facelets: PackedByteArray, n: int, stage: int,
		progress: float) -> Dictionary:
	var par := _parity_checked(facelets, n)
	if par.is_empty():
		return {"stage": stage, "progress": progress, "suggestion": {},
				"error": "parity 宏池入池验证未过(降级)"}
	var algs: Dictionary = PARITY_ALGS[n]
	if bool(par.oll):
		return {"stage": stage, "progress": progress,
				"suggestion": {"piece": "parity", "alg": String(algs.oll),
				"text": "奇偶校验:检测到单棱翻转(OLL parity),做这条修正公式恢复棱组定向"}}
	if bool(par.pll):
		return {"stage": stage, "progress": progress,
				"suggestion": {"piece": "parity", "alg": String(algs.pll),
				"text": "奇偶校验:检测到角棱置换奇偶错位(PLL parity),做这条修正公式恢复"}}
	return {}


## 4-7 阶 hint(P5):sc 0 = 中心段建议;sc 1 = 组棱段建议(组棱满而 stage=1 =
## 偶数阶 parity 未清,转 LBL 边界注入);sc ≥2 = LBL 边界——parity 预判
## (solve 与 hint 双注入点之二)→ 修正建议;无 parity → 约化提取 →
## lbl_solver.hint(stage 映射 lsc+2,9 段契约)。
static func _nxn_hint(facelets: PackedByteArray, n: int) -> Dictionary:
	var sc := stage_check(facelets)
	if sc == 0:
		return _center_hint(facelets) if n == CENTER_N else _cn_hint(facelets, n)
	if sc == 9:
		return {"stage": 9, "progress": 1.0,
				"suggestion": {"piece": "", "alg": "", "text": "魔方已复原"}}
	if sc == 1 and _nxn_paired(facelets, n) == 12:
		# 组棱满而 stage=1:parity 未清(parity 段语义并入组棱段尾)→ 注入修正建议
		var ps: Dictionary = _parity_suggestion(facelets, n, 1, 1.0)
		if not ps.is_empty():
			return ps
		return _edge_hint(facelets) if n == CENTER_N else _pr_hint(facelets, n)
	if sc == 1:
		return _edge_hint(facelets) if n == CENTER_N else _pr_hint(facelets, n)
	var progress: float = LBL._progress(_reduce_to_54(facelets, n), sc - 2)
	if n % 2 == 0:
		var ps2: Dictionary = _parity_suggestion(facelets, n, sc, progress)
		if not ps2.is_empty():
			return ps2
	# 无 parity → LBL 建议约化透传
	var lh := LBL.hint(_reduce_to_54(facelets, n))
	return {"stage": 2 + int(lh.stage), "progress": float(lh.progress),
			"suggestion": lh.suggestion}
