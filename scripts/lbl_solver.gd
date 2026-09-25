extends RefCounted
## LBL 教学引擎(PLAN §14,P2 核心,纯函数,不依赖场景节点)。
## 输入 cube.to_facelets() 的 54 字节(URFDLB,§3.1 行列序 = Kociemba 标准),输出 WCA 记号。
##
## 源教程姿态(公式表存储基准,§14.1):白底、绿前、右橙左红(国内常见教程拿法)
##   = 本项目坐标系(白上绿前红右)经 z2 旋转 ⇒ 引擎采用 REMAP_MODE = REMAP_Z2。
##   x2 型(白底蓝前红右)映射同在,remap(alg, REMAP_X2) 供切换/测试。
##
## 内部机制:facelet 级置换模拟器(运行时由 §3.1 面定义几何生成 6 个 90° 置换环,
## 旋转矩阵 Basis(normal, -PI/2) 与 cube.gd _bake 同源);每段候选公式「模拟-验证-采用」,
## 触发条件不经文本解析而由模拟结果判定(等效于「触发条件与公式同经 remap」,§14.1),
## 正确性由 tests/test_lbl.gd T15 金标准兜底。

const REMAP_X2 := 0
const REMAP_Z2 := 1
const REMAP_MODE := REMAP_Z2  # 源教程姿态:白底绿前右橙左红(文件头注明)
const MOVE_LIMIT := 170       # solve 步数上限(§14;对发散/死循环的保险丝,须宽于
                              # 金标准测试门 160——cube.gd 负轴选层修复后 6 面均匀分布
                              # 实测最坏 156,见 tests/test_lbl.gd T15 注释,2026-09-24)

const STAGE_NAMES := ["白十字", "U 层四角", "中层四棱", "D 面十字", "D 面全黄", "D 层角位", "D 层棱位"]

const WHITE := 0
const YELLOW := 3

const FACE_IDX := {"U": 0, "R": 1, "F": 2, "D": 3, "L": 4, "B": 5}

## §14.1 无撇映射(x2/z2 均为纯旋转,共轭保定向,重写不产生撇;撇号原样保留)
const REMAP_TABLE := {
	REMAP_X2: {"U": "D", "D": "U", "F": "B", "B": "F", "R": "R", "L": "L"},
	REMAP_Z2: {"U": "D", "D": "U", "R": "L", "L": "R", "F": "F", "B": "B"},
}

## §3.1 面定义(n=3,E=2,行列序表):法线 / 首格坐标 / 行步 / 列步(已含 2 步长)
const FACES_DEF := [
	{"n": Vector3(0, 1, 0), "off": Vector3(-2, 2, -2), "row": Vector3(0, 0, 2), "col": Vector3(2, 0, 0)},   # U 0-8
	{"n": Vector3(1, 0, 0), "off": Vector3(2, 2, 2), "row": Vector3(0, -2, 0), "col": Vector3(0, 0, -2)},   # R 9-17
	{"n": Vector3(0, 0, 1), "off": Vector3(-2, 2, 2), "row": Vector3(0, -2, 0), "col": Vector3(2, 0, 0)},   # F 18-26
	{"n": Vector3(0, -1, 0), "off": Vector3(-2, -2, 2), "row": Vector3(0, 0, -2), "col": Vector3(2, 0, 0)}, # D 27-35
	{"n": Vector3(-1, 0, 0), "off": Vector3(-2, 2, -2), "row": Vector3(0, -2, 0), "col": Vector3(0, 0, 2)}, # L 36-44
	{"n": Vector3(0, 0, -1), "off": Vector3(2, 2, -2), "row": Vector3(0, -2, 0), "col": Vector3(-2, 0, 0)}, # B 45-53
]

## 棱位名 -> 两个 facelet 下标;solved 时两格颜色
const EDGES := {
	"UF": [7, 19], "UR": [5, 10], "UB": [1, 46], "UL": [3, 37],
	"DF": [28, 25], "DR": [32, 16], "DB": [34, 52], "DL": [30, 43],
	"FR": [23, 12], "FL": [21, 41], "BL": [39, 50], "BR": [14, 48],
}
const EDGE_COLORS := {
	"UF": [0, 2], "UR": [0, 1], "UB": [0, 5], "UL": [0, 4],
	"DF": [3, 2], "DR": [3, 1], "DB": [3, 5], "DL": [3, 4],
	"FR": [2, 1], "FL": [2, 4], "BL": [4, 5], "BR": [1, 5],
}

## 角位名 -> 三个 facelet 下标;solved 时三格颜色
const CORNERS := {
	"UFR": [8, 9, 20], "UFL": [6, 18, 38], "ULB": [0, 36, 47], "UBR": [2, 45, 11],
	"DFR": [29, 26, 15], "DLF": [27, 44, 24], "DBL": [33, 53, 42], "DRB": [35, 17, 51],
}
const CORNER_COLORS := {
	"UFR": [0, 1, 2], "UFL": [0, 2, 4], "ULB": [0, 4, 5], "UBR": [0, 5, 1],
	"DFR": [3, 2, 1], "DLF": [3, 4, 2], "DBL": [3, 5, 4], "DRB": [3, 1, 5],
}

const U_EDGES := ["UF", "UR", "UB", "UL"]
const D_EDGES := ["DF", "DR", "DB", "DL"]
const MID_EDGES := ["FR", "FL", "BL", "BR"]
const U_CORNERS := ["UFR", "UFL", "ULB", "UBR"]
const D_CORNERS := ["DFR", "DLF", "DBL", "DRB"]

## §14.3 公式表(源教程姿态记号存储;text 按 §14.5 以本项目朝向撰写,不经 remap)。
## 触发条件以源姿态注释存储,运行时由「模拟-验证」判定(与公式同受 remap 语义约束)。
const FORMULAS_SRC := {
	2: [  # 触发(源):角已 U 预对位至目标槽上方,白朝右 / 白朝前 / 白朝上;(白角卡错槽 = 提取,复用第 1 条)
		{"alg": "R U R'", "text": "白色朝左,左手三步把白角带上顶层", "text_eject": "白角卡在顶层:先用三步公式把它带下底层"},
		{"alg": "F' U' F", "text": "白色朝前,三步把白角带上顶层", "text_eject": "白角卡在顶层:先用三步公式把它带下底层"},
		{"alg": "R U2 R' U' R U R'", "text": "白色朝下:先立起来,再插进槽里", "text_eject": "白角卡在顶层:先用三步公式把它带下底层"},
	],
	3: [  # 触发(源):棱在顶层且侧色对齐中心,插右槽 / 插左槽;(棱卡错中层槽 = 顶出,复用任一条)
		{"alg": "U R U' R' U' F' U F", "text": "棱已对齐侧面中心:转开、开门、插进中层", "text_eject": "棱卡错中层槽:用插入公式把它顶回下层"},
		{"alg": "U' L' U L U F U' F'", "text": "棱已对齐侧面中心:转开、开门、插进中层", "text_eject": "棱卡错中层槽:用插入公式把它顶回下层"},
	],
	4: [  # 触发(源):黄面呈点/拐/线(拐朝左上摆位);摆位由 D 预转枚举模拟确定
		{"alg": "F R U R' U' F'", "text": "黄点变黄线、黄线变黄十字,最多做三次"},
	],
	5: [  # 触发(源):黄面 7 case(Sune 家族);摆位由 D 预转枚举模拟确定
		{"alg": "R U R' U R U2 R'", "text": "小鱼公式:摆好位置做一到两次"},
		{"alg": "R U2 R' U' R U' R'", "text": "反小鱼公式:摆好位置做一到两次"},
	],
	6: [  # 触发(源):三角换;好角摆位实证=不动角 DLF(左前);Niklas 类公式破坏朝向,弃用
		{"alg": "L F' L B2 L' F L B2 L2", "text": "把位置正确的角放到左前,其余三个转圈换"},
	],
	7: [  # 触发(源):三棱换 Ua / Ub=Ua'(逆公式程序生成,防笔误)
		{"alg": "R U' R U R U R U' R' U' R2", "text": "黄面朝下:三条棱顺着一个方向轮换归位", "text_inv": "黄面朝下:三条棱反方向轮换归位"},
	],
}

# ---- 运行期缓存(static,lazy 初始化)----
static var _perm: Array = []       # 6 x PackedInt32Array:一次 90° 的 facelet 置换(new[j] = old[perm[j]])
static var _formulas: Dictionary = {}  # stage -> Array[{alg(已 remap), text, text_eject?}]
static var _ready := false


# ================================ remap(§14.1) ================================

## 按型映射逐 token 替换面字母;撇号/2 原样保留(纯旋转共轭不产生撇)。
## 注:公开名 remap 与内置函数同名,类内一律经 _remap_alg 转调,防遮蔽解析。
static func remap(alg: String, mode: int = REMAP_MODE) -> String:
	return _remap_alg(alg, mode)


static func _remap_alg(alg: String, mode: int = REMAP_MODE) -> String:
	var tab: Dictionary = REMAP_TABLE[mode]
	var out: PackedStringArray = []
	for token in alg.split(" ", false):
		if token.is_empty():
			continue
		var face: String = token[0]
		if tab.has(face):
			token = String(tab[face]) + token.substr(1)
		out.append(token)
	return " ".join(out)


## 公式取逆(逆序 + 逐 token 取反;2 保持)。
static func invert_alg(alg: String) -> String:
	var tokens := alg.split(" ", false)
	var out: PackedStringArray = []
	for i in range(tokens.size() - 1, -1, -1):
		var t := tokens[i]
		if t.ends_with("'"):
			t = t.substr(0, t.length() - 1)
		elif not t.ends_with("2"):
			t += "'"
		out.append(t)
	return " ".join(out)


## 段化简:相邻/同轴可交换范围内的同面转动合并(mod 4,0 抵消删除);不改变净效果。
## 同轴不同面(如 L 与 R)转动可交换,故合并可穿越同轴异面 token。
const AXIS_OF_FACE := {"U": 0, "D": 0, "R": 1, "L": 1, "F": 2, "B": 2}


static func _simplify_alg(alg: String) -> String:
	var cur := alg
	var out := _simplify_pass(cur)
	while out != cur:
		cur = out
		out = _simplify_pass(cur)
	return cur


static func _simplify_pass(alg: String) -> String:
	var out: Array = []  # [face, quarter 1..3]
	for token in alg.split(" ", false):
		if token.is_empty():
			continue
		var face: String = token[0]
		var q := 1
		if token.ends_with("2"):
			q = 2
		elif token.ends_with("'"):
			q = 3
		# 从栈顶向栈底找同面 token;途中同轴异面 token 可交换穿越,异轴即停
		var j := out.size() - 1
		while j >= 0 and out[j][0] != face and AXIS_OF_FACE[out[j][0]] == AXIS_OF_FACE[face]:
			j -= 1
		if j >= 0 and out[j][0] == face:
			var total: int = (int(out[j][1]) + q) % 4
			if total == 0:
				out.remove_at(j)
			else:
				out[j][1] = total
		else:
			out.append([face, q])
	var parts: PackedStringArray = []
	for e in out:
		var face2: String = e[0]
		match int(e[1]):
			1: parts.append(face2)
			2: parts.append(face2 + "2")
			3: parts.append(face2 + "'")
	return " ".join(parts)


## y^k 整体旋转的公式重写(remap 的推广):把基础槽公式的面记号按 y 旋转映射替换,
## 角度与撇保持(纯旋转 det=+1 共轭保定向)。k=1:y 顺(与 U 同向)F→L;枚举 k=0..3
## 即得基础槽公式的 4 个槽位版本,方向语义由「模拟-验证」筛选兜底。
const ROT_MAPS := [
	{"U": "U", "D": "D", "F": "F", "B": "B", "R": "R", "L": "L"},
	{"U": "U", "D": "D", "F": "L", "L": "B", "B": "R", "R": "F"},
	{"U": "U", "D": "D", "F": "B", "B": "F", "R": "L", "L": "R"},
	{"U": "U", "D": "D", "F": "R", "R": "B", "B": "L", "L": "F"},
]


static func _rotate_alg(alg: String, k: int) -> String:
	var tab: Dictionary = ROT_MAPS[k % 4]
	var out: PackedStringArray = []
	for token in alg.split(" ", false):
		if token.is_empty():
			continue
		var face: String = token[0]
		if tab.has(face):
			token = String(tab[face]) + token.substr(1)
		out.append(token)
	return " ".join(out)


# ================================ facelet 模拟器 ================================

static func _ensure() -> void:
	if _ready:
		return
	# facelet 坐标表:index -> {c: Vector3 格坐标, n: Vector3 贴纸法线}
	var cells: Array = []
	for fi in 6:
		var f: Dictionary = FACES_DEF[fi]
		for r in 3:
			for c in 3:
				cells.append({
					"c": f.off + f.row * r + f.col * c,
					"n": f.n,
				})
	# 6 个 90° 顺时针置换环(Basis(n, -PI/2),与 cube.gd bake 数学同源)
	for fi in 6:
		var axis: Vector3 = FACES_DEF[fi].n
		var rot := Basis(axis, -PI / 2.0)
		var perm := PackedInt32Array()
		perm.resize(54)
		for i in 54:
			var cell: Vector3 = cells[i].c
			if int(cell.dot(axis)) != 2:  # 不在该层(分量 ∈ {-2,0,2})
				perm[i] = i
				continue
			var nc: Vector3 = (rot * cell).round()
			var nn: Vector3 = (rot * cells[i].n).round()
			var j := -1
			for k in 54:
				if cells[k].c == nc and cells[k].n == nn:
					j = k
					break
			perm[j] = i  # 新位置 j 的值来自旧位置 i
		_perm.append(perm)
	_ready = true  # 置换表已可用;后续公式表/slot 预计算内部调用 _apply_alg 时重入直接返回
	# 公式表 remap(Ub=Ua' 程序生成)
	for s in FORMULAS_SRC:
		var arr: Array = []
		for item in FORMULAS_SRC[s]:
			var rec := {"alg": _remap_alg(String(item.alg)), "text": String(item.text)}
			if item.has("text_eject"):
				rec["text_eject"] = String(item.text_eject)
			arr.append(rec)
		_formulas[s] = arr
	# Ub = Ua 逆(§14.3:Ub=Ua');角位逆三角换同取程序生成,防笔误
	_formulas[7].append({"alg": invert_alg(_formulas[7][0].alg), "text": "黄面朝下:三条棱反方向轮换归位"})
	_formulas[6].append({"alg": invert_alg(_formulas[6][0].alg), "text": "其余三个角反方向转圈换"})
	# 各公式各 rotate 档的「作用槽」(solved 态应用后被换出的块位置),供顶出/插入枚举前置过滤
	var solved := PackedByteArray()
	solved.resize(54)
	for i in 54:
		solved[i] = i / 9
	for stage in [2, 3]:
		for rec in _formulas[stage]:
			for kt in 4:
				var t: PackedByteArray = solved.duplicate()
				_apply_alg(t, _rotate_alg(String(rec.alg), kt))
				var slot := ""
				if stage == 2:
					for name in U_CORNERS:
						if not _corner_solved(t, name):
							slot = name
							break
				else:
					for name in MID_EDGES:
						if not _edge_solved(t, name):
							slot = name
							break
				rec["slot%d" % kt] = slot


static func _apply_token(f: PackedByteArray, token: String) -> void:
	_ensure()  # 测试可能直调私有接口;幂等
	var fi: int = FACE_IDX[token[0]]
	var times := 1
	if token.ends_with("2"):
		times = 2
	elif token.ends_with("'"):
		times = 3
	var p: PackedInt32Array = _perm[fi]
	for t in times:
		var old := f.duplicate()
		for j in 54:
			f[j] = old[p[j]]


static func _apply_alg(f: PackedByteArray, alg: String) -> void:
	for token in alg.split(" ", false):
		if not token.is_empty():
			_apply_token(f, token)


static func _token_count(alg: String) -> int:
	return alg.split(" ", false).size()


static func _u_pow(k: int) -> String:
	return ["", "U", "U2", "U'"][k % 4]


static func _d_pow(k: int) -> String:
	return ["", "D", "D2", "D'"][k % 4]


# ================================ 块查询 ================================

static func _edge_solved(f: PackedByteArray, name: String) -> bool:
	var idx: Array = EDGES[name]
	var col: Array = EDGE_COLORS[name]
	return f[idx[0]] == col[0] and f[idx[1]] == col[1]


static func _corner_solved(f: PackedByteArray, name: String) -> bool:
	var idx: Array = CORNERS[name]
	var col: Array = CORNER_COLORS[name]
	return f[idx[0]] == col[0] and f[idx[1]] == col[1] and f[idx[2]] == col[2]


## 朝向无关定位:双色/三色集合匹配的块所在位名。
static func _find_edge(f: PackedByteArray, colors: Array) -> String:
	for name in EDGES:
		var idx: Array = EDGES[name]
		var a: int = f[idx[0]]
		var b: int = f[idx[1]]
		if (a == colors[0] and b == colors[1]) or (a == colors[1] and b == colors[0]):
			return name
	return ""


static func _find_corner(f: PackedByteArray, colors: Array) -> String:
	for name in CORNERS:
		var idx: Array = CORNERS[name]
		var s := {f[idx[0]]: true, f[idx[1]]: true, f[idx[2]]: true}
		if s.size() == 3 and s.has(colors[0]) and s.has(colors[1]) and s.has(colors[2]):
			return name
	return ""


# ================================ 阶段判定(§14.2) ================================

## 单阶段完成判定(不含前缀蕴含;stage_check 负责连续前缀)。
static func _done(f: PackedByteArray, stage: int) -> bool:
	match stage:
		1:  # 白十字:U 面 4 棱白 + 各侧面对齐中心色
			for e in U_EDGES:
				if not _edge_solved(f, e):
					return false
			return true
		2:  # U 层四角:白角归位(含侧色)
			for c in U_CORNERS:
				if not _corner_solved(f, c):
					return false
			return true
		3:  # 中层四棱归位
			for e in MID_EDGES:
				if not _edge_solved(f, e):
					return false
			return true
		4:  # D 面十字:4 棱黄(朝向)
			return _yellow_cross_count(f) == 4
		5:  # D 面 9 格黄
			return _yellow_face_count(f) == 9
		6:  # D 层角位:4 角位置正确(朝向已由 5 保证)
			return _placed_d_corners(f) == 4
		7:  # D 层棱位 -> 必然 is_solved(6 面同色口径)
			for fi in 6:
				var ref: int = f[fi * 9]
				for k in 9:
					if f[fi * 9 + k] != ref:
						return false
			return true
	return false


## stage_check:最大连续完成前缀,0 = 无任何阶段满足,7 = 复原(is_solved 口径)。
static func stage_check(facelets: PackedByteArray) -> int:
	_ensure()
	var k := 0
	for s in range(1, 8):
		if _done(facelets, s):
			k = s
		else:
			break
	return k


static func _yellow_cross_count(f: PackedByteArray) -> int:
	var n := 0
	for e in D_EDGES:
		if f[EDGES[e][0]] == YELLOW:  # D 面格
			n += 1
	return n


static func _yellow_face_count(f: PackedByteArray) -> int:
	var n := 0
	for i in range(27, 36):
		if f[i] == YELLOW:
			n += 1
	return n


static func _placed_d_corners(f: PackedByteArray) -> int:
	var n := 0
	for c in D_CORNERS:
		if _corner_solved(f, c):
			n += 1
	return n


static func _placed_d_edges(f: PackedByteArray) -> int:
	var n := 0
	for e in D_EDGES:
		if _edge_solved(f, e):
			n += 1
	return n


## 前缀进度保持:阶段 s 的段执行后,阶段 1..s-1 必须仍完成。
static func _prefix_kept(f: PackedByteArray, stage: int) -> bool:
	for k in range(1, stage):
		if not _done(f, k):
			return false
	return true


# ================================ 白十字启发式(§14.4) ================================

## U 层已归位白棱是否全部保持归位(f -> f2)。
static func _u_cross_kept(f: PackedByteArray, f2: PackedByteArray) -> bool:
	for e in U_EDGES:
		if _edge_solved(f, e) and not _edge_solved(f2, e):
			return false
	return true


## 白十字单段:{alg, piece, text} 或 {}(卡死兜底,由测试抓)。
static func _cross_segment(f: PackedByteArray) -> Dictionary:
	for target in U_EDGES:
		if _edge_solved(f, target):
			continue
		var colors: Array = EDGE_COLORS[target]
		var pos := _find_edge(f, colors)
		var f2 := f.duplicate()
		@warning_ignore("unused_variable")
		var probe := f2
		# --- U 层 ---
		if pos in U_EDGES:
			var white_up: bool = f[EDGES[pos][0]] == WHITE
			# 白朝上:优先 U 直接对位(不拆已归位棱时)
			if white_up:
				for k in [1, 2, 3]:
					var alg := _u_pow(k)
					var t := f.duplicate()
					_apply_alg(t, alg)
					if _edge_solved(t, target) and _u_cross_kept(f, t):
						return {"alg": alg, "piece": target,
								"text": "白棱已在顶层:转 U 对准侧面颜色归位"}
				# U 轮转会拆已归位棱:转棱所在侧面 180° 落回 D 再走底层流程(③;
				# PLAN 原文"目标侧面"系笔误——棱不在目标侧面层,转之不动)
				var face: String = pos[1]
				var alg2: String = face + "2"
				var t2 := f.duplicate()
				_apply_alg(t2, alg2)
				if _find_edge(t2, colors) in D_EDGES and _u_cross_kept(f, t2):
					return {"alg": alg2, "piece": target,
							"text": "顶层白棱位置不对:转 %s2 落到底层重新对齐" % face}
			else:
				# 翻转态:相邻面单步下中层(动 U 位=它自己,恒安全)
				var face: String = pos[1]
				for suffix in ["", "'"]:
					var alg: String = face + String(suffix)
					var t := f.duplicate()
					_apply_alg(t, alg)
					if _find_edge(t, colors) in MID_EDGES and _u_cross_kept(f, t):
						return {"alg": alg, "piece": target,
								"text": "白棱白色朝侧面:先转下中层,再翻上来归位"}
		# --- D 层(黄面侧)① ---
		elif pos in D_EDGES:
			var face: String = target[1]
			for k in 4:
				var alg: String = (_d_pow(k) + " " if k != 0 else "") + face + "2"
				var t := f.duplicate()
				_apply_alg(t, alg)
				if _edge_solved(t, target) and _u_cross_kept(f, t):
					return {"alg": alg, "piece": target,
							"text": "白棱在底层:转 D 对齐侧面颜色,%s2 翻上顶层" % face}
			# 翻转态 D 棱:180° 翻上顶层走 U 层流程;翻转会拆 U 层归位棱时先 U 让开再转回
			var face0: String = pos[1]
			for k in 4:
				var u := _u_pow(k)
				var alg3: String = (u + " " if u != "" else "") + face0 + "2" + (" " + invert_alg(u) if u != "" else "")
				var t3 := f.duplicate()
				_apply_alg(t3, alg3)
				if _find_edge(t3, colors) in U_EDGES and _u_cross_kept(f, t3):
					return {"alg": alg3, "piece": target,
							"text": "底层白棱白色朝侧面:先翻上顶层再调整(必要时先让开已归位棱)"}
		# --- 中层 ②(护棱分支)---
		elif pos in MID_EDGES:
			var cands := ["R", "F'", "L'", "B'", "R'", "F", "L", "B"]
			# 提取结果质量:0=到 U 层白朝上 / 1=到 D 层白朝下(可直接走①),2=其他(翻转态)
			var grade := func(t: PackedByteArray) -> int:
				var p := _find_edge(t, colors)
				if p in U_EDGES:
					return 0 if t[EDGES[p][0]] == WHITE else 2
				if p in D_EDGES:
					return 1 if t[EDGES[p][0]] == WHITE else 2
				return 9
			var best_alg := ""
			var best_u := ""
			var best_u_inv := ""
			var best_grade := 9
			for a in cands:
				var t := f.duplicate()
				_apply_alg(t, String(a))
				var g: int = grade.call(t)
				# 直接提取只接受「可用态」(U 白朝上 / D 白朝下);翻转态宁可护棱绕行
				if g < best_grade and g <= 1 and _u_cross_kept(f, t):
					best_grade = g
					best_alg = String(a)
			# 护棱:先转 U 让开已归位白棱,提取后再转回
			for a in cands:
				if best_alg != "" and best_grade <= 1:
					break
				for k in [1, 2, 3]:
					var u := _u_pow(k)
					var alg: String = u + " " + String(a) + " " + invert_alg(u)
					var t := f.duplicate()
					_apply_alg(t, alg)
					var g: int = grade.call(t)
					if g < best_grade and g <= 2 and _u_cross_kept(f, t):
						best_grade = g
						best_alg = String(a)
						best_u = u
						best_u_inv = invert_alg(u)
			# 兜底:只有翻转态直接动作可用时取之(避免空段;测试金标准兜底正确性)
			if best_alg == "":
				for a in cands:
					var t := f.duplicate()
					_apply_alg(t, String(a))
					var g: int = grade.call(t)
					if g < 9 and _u_cross_kept(f, t):
						best_alg = String(a)
						break
			if best_alg != "":
				var full_alg: String = best_alg
				var text := "白棱卡在中层:单步提取到顶层或底层"
				if best_u != "":
					full_alg = best_u + " " + best_alg + " " + best_u_inv
					text = "白棱卡在中层:先转 U 让开已归位的白棱,提取后再转回"
				return {"alg": full_alg, "piece": target, "text": text}
	return {}


# ================================ 阶段 2-7 公式段(§14.3) ================================

## 单段:{alg, piece, text} 或 {}。
static func _segment(f: PackedByteArray, stage: int) -> Dictionary:
	if stage == 1:
		return _cross_segment(f)
	return _formula_segment(f, stage)


## 阶段 2-7 公式段:{alg, piece, text} 或 {}。
static func _formula_segment(f: PackedByteArray, stage: int) -> Dictionary:
	var flist: Array = _formulas[stage]
	if stage == 2:
		return _corner_segment(f, flist)
	if stage == 3:
		return _mid_edge_segment(f, flist)
	# 阶段 4-7(OLL/PLL):动作 = D^k 摆位 + 公式;单段允许「形态变化不计数」的中间步
	# (如黄十字拐→线黄棱数不增),故用小深度 BFS 直达阶段完成,状态空间小保证收敛。
	var actions: Array = []
	for k in 4:
		var pre := _d_pow(k)
		for item in flist:
			actions.append((pre + " " if pre != "" else "") + String(item.alg))
	return _bfs_segment(f, stage, actions)


## 阶段 4-7 的 BFS 段:深度 ≤4(搜索预算上限;BFS 按最短优先返回,§14.3 口径
## "≤2/≤3 次可解时不会用满"),目标 = 该阶段完成;返回 {alg, piece, text} 或 {}。
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
				if _done(t, stage):
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
		4:
			return "摆好位置做黄十字公式,点到线、线到十字(共 %d 次)" % count
		5:
			return "摆好位置做小鱼公式,一到两次(共 %d 次)" % count
		6:
			return "把位置正确的角摆到左前,转圈换(共 %d 次)" % count
		7:
			return "三条棱轮换归位,必要时调整摆位(共 %d 次)" % count
	return ""


## 段后新达成阶段的块位名(hint 的 piece;找不到给阶段首个目标位)。
static func _new_piece(before: PackedByteArray, after: PackedByteArray, stage: int) -> String:
	match stage:
		4:
			for e in D_EDGES:
				if after[EDGES[e][0]] == YELLOW and before[EDGES[e][0]] != YELLOW:
					return e
			return D_EDGES[0]
		5:
			for c in D_CORNERS:
				if after[CORNERS[c][0]] == YELLOW and before[CORNERS[c][0]] != YELLOW:
					return c
			return D_CORNERS[0]
		6:
			for c in D_CORNERS:
				if _corner_solved(after, c) and not _corner_solved(before, c):
					return c
			return D_CORNERS[0]
		7:
			for e in D_EDGES:
				if _edge_solved(after, e) and not _edge_solved(before, e):
					return e
			return D_EDGES[0]
	return ""


## 阶段 2 白角:U 层卡角 → 槽位旋转公式顶出;D 层游走 → D^j 预对位 + 槽位旋转插入。
## 基础槽 = UFL(remap 后);_rotate_alg 覆盖 4 个 U 槽,方向由模拟-验证筛选。
static func _corner_segment(f: PackedByteArray, flist: Array) -> Dictionary:
	for target in U_CORNERS:
		if _corner_solved(f, target):
			continue
		var best := {}
		var colors: Array = CORNER_COLORS[target]
		var pos := _find_corner(f, colors)
		for item in flist:
			var base: String = String(item.alg)
			for kt in 4:
				var slot: String = String(item.get("slot%d" % kt, ""))
				if pos in U_CORNERS:
					if slot != pos:
						continue  # 顶出:公式必须作用角所在槽
					# 顶出:D^j 前缀控制换入槽的白角,优先「顺带归位其他白角」的组合
					for j in 4:
						var pre := _d_pow(j)
						var alg: String = (pre + " " if pre != "" else "") + _rotate_alg(base, kt)
						var t := f.duplicate()
						_apply_alg(t, alg)
						if not _prefix_kept(t, 2):
							continue
						if _find_corner(t, colors) in D_CORNERS:
							var score := _solved_corners(t)
							var cur: int = best.get("score", -1)
							if score > cur or (score == cur and alg.length() < int(best.get("len", 999))):
								best = {"alg": alg, "piece": target, "text": String(item.text_eject),
										"score": score, "len": alg.length()}
				else:
					if slot != target:
						continue  # 插入:公式必须作用目标槽
					# 插入:D^j 预对位(角转基础槽正下)+ 槽位旋转公式
					for j in 4:
						var pre := _d_pow(j)
						var alg2: String = (pre + " " if pre != "" else "") + _rotate_alg(base, kt)
						var t2 := f.duplicate()
						_apply_alg(t2, alg2)
						if _prefix_kept(t2, 2) and _corner_solved(t2, target):
							return {"alg": alg2, "piece": target, "text": String(item.text)}
		if not best.is_empty():
			best.erase("score")
			best.erase("len")
			return best
	return {}


static func _solved_corners(f: PackedByteArray) -> int:
	var n := 0
	for c in U_CORNERS:
		if _corner_solved(f, c):
			n += 1
	return n


## 阶段 3 中层棱:D 层 → D^j 预对位 + 槽位旋转插入;中层卡棱 → 槽位旋转顶出。
## 基础槽:右插公式作用 FL、左插公式作用 FR(remap 后);rotate 覆盖 4 个中层槽。
static func _mid_edge_segment(f: PackedByteArray, flist: Array) -> Dictionary:
	for target in MID_EDGES:
		if _edge_solved(f, target):
			continue
		var best := {}
		var colors: Array = EDGE_COLORS[target]
		var pos := _find_edge(f, colors)
		if pos in U_EDGES or pos == "":
			continue  # 阶段 2 完成后中层棱只会在 D 层/中层槽
		for item in flist:
			var base: String = String(item.alg)
			for kt in 4:
				var slot: String = String(item.get("slot%d" % kt, ""))
				if pos in MID_EDGES:
					if slot != pos:
						continue  # 顶出:公式必须作用棱所在槽
					# 顶出:D^j 前缀控制换入槽的棱;评分先「顺带归位数」、后「顶出+插入总 token」
					for j in 4:
						var pre := _d_pow(j)
						var alg: String = (pre + " " if pre != "" else "") + _rotate_alg(base, kt)
						var t := f.duplicate()
						_apply_alg(t, alg)
						if not _prefix_kept(t, 3):
							continue
						if _find_edge(t, colors) in D_EDGES:
							var score := _solved_mid_edges(t)
							var cur: int = best.get("score", -1)
							var cur_len: int = int(best.get("len", 999))
							var total_len: int = _token_count(alg) + _shortest_insert_len(t, target)
							if score > cur or (score == cur and total_len < cur_len):
								best = {"alg": alg, "piece": target, "text": String(item.text_eject),
										"score": score, "len": total_len}
				else:
					if slot != target:
						continue  # 插入:公式必须作用目标槽
					# 插入:D^j 预对位 + 槽位旋转公式
					for j in 4:
						var pre := _d_pow(j)
						var alg2: String = (pre + " " if pre != "" else "") + _rotate_alg(base, kt)
						var t2 := f.duplicate()
						_apply_alg(t2, alg2)
						if _prefix_kept(t2, 3) and _edge_solved(t2, target):
							return {"alg": alg2, "piece": target, "text": String(item.text)}
		if not best.is_empty():
			best.erase("score")
			best.erase("len")
			return best
	return {}


static func _solved_mid_edges(f: PackedByteArray) -> int:
	var n := 0
	for e in MID_EDGES:
		if _edge_solved(f, e):
			n += 1
	return n


## 从 t 态把 target 中层棱插入目标槽的最短插入段 token 数(枚举 D^j + rotate)。
static func _shortest_insert_len(t: PackedByteArray, target: String) -> int:
	var colors: Array = EDGE_COLORS[target]
	if _find_edge(t, colors) in MID_EDGES:
		return 999  # 仍在中层,插入枚举不适用
	var best_len := 999
	for item in _formulas[3]:
		var base: String = String(item.alg)
		for kt in 4:
			if String(item.get("slot%d" % kt, "")) != target:
				continue
			for j in 4:
				var pre := _d_pow(j)
				var alg: String = (pre + " " if pre != "" else "") + _rotate_alg(base, kt)
				var t2: PackedByteArray = t.duplicate()
				_apply_alg(t2, alg)
				if _prefix_kept(t2, 3) and _edge_solved(t2, target):
					best_len = mini(best_len, _token_count(alg))
	return best_len


# ================================ solve / hint(§6.2) ================================

## solve:{ok, alg, stages:[{name, alg}], moves};卡住/超上限返回 ok:false。
static func solve(facelets: PackedByteArray) -> Dictionary:
	_ensure()
	if facelets.size() != 54:
		return {"ok": false, "alg": "", "stages": [], "error": "facelets 须 54 字节"}
	var fs := facelets.duplicate()
	var stages: Array = []
	var all: Array = []
	var total := 0
	for s in range(1, 8):
		var segs: Array = []
		var guard := 0
		while not _done(fs, s):
			guard += 1
			if guard > 80 or total >= MOVE_LIMIT:
				return {"ok": false, "alg": "", "stages": [], "error": "阶段 %d 卡住或超 %d 步上限" % [s, MOVE_LIMIT]}
			var seg := _segment(fs, s)
			if seg.is_empty():
				return {"ok": false, "alg": "", "stages": [], "error": "阶段 %d 无法生成进展段" % s}
			_apply_alg(fs, seg["alg"])
			total += _token_count(seg["alg"])
			segs.append(seg["alg"])
			all.append(seg["alg"])
		stages.append({"name": STAGE_NAMES[s - 1], "alg": _simplify_alg(" ".join(segs))})
	var total_alg := _simplify_alg(" ".join(all))
	return {"ok": true, "alg": total_alg, "stages": stages, "moves": _token_count(total_alg)}


## 阶段内进度:进行中阶段(sc+1)的已完成子块比例 0.0~1.0。
static func _progress(f: PackedByteArray, sc: int) -> float:
	match sc:
		0:  # 进行 1:白十字棱
			var n := 0
			for e in U_EDGES:
				if _edge_solved(f, e):
					n += 1
			return n / 4.0
		1:  # 进行 2:白角
			var n1 := 0
			for c in U_CORNERS:
				if _corner_solved(f, c):
					n1 += 1
			return n1 / 4.0
		2:  # 进行 3:中层棱
			var n2 := 0
			for e in MID_EDGES:
				if _edge_solved(f, e):
					n2 += 1
			return n2 / 4.0
		3:  # 进行 4:D 面黄棱
			return _yellow_cross_count(f) / 4.0
		4:  # 进行 5:D 面黄格
			return _yellow_face_count(f) / 9.0
		5:  # 进行 6:D 角位
			return _placed_d_corners(f) / 4.0
		6:  # 进行 7:D 棱位
			return _placed_d_edges(f) / 4.0
	return 1.0


## hint:{stage(0..7,stage_check 口径), progress, suggestion:{piece, alg, text}}。
## stage=7 已复原,suggestion 为完成文案;否则建议针对阶段 max(1, stage+1)。
static func hint(facelets: PackedByteArray) -> Dictionary:
	_ensure()
	var sc := stage_check(facelets)
	var progress := _progress(facelets, sc)
	if sc == 7:
		return {"stage": 7, "progress": 1.0,
				"suggestion": {"piece": "", "alg": "", "text": "魔方已复原"}}
	var s := 1 if sc == 0 else sc + 1
	if s == 1:
		# 十字建议:拼接启发式段直到该 piece 真正归位(中间提取段本身不归位)
		var t := facelets.duplicate()
		var parts: Array = []
		var piece := ""
		var text := ""
		for i in 12:
			var seg := _cross_segment(t)
			if seg.is_empty():
				break
			_apply_alg(t, seg["alg"])
			if parts.is_empty():
				piece = String(seg["piece"])
				text = String(seg["text"])
			parts.append(seg["alg"])
			if _edge_solved(t, piece):
				break
		if parts.is_empty():
			return {"stage": sc, "progress": progress, "suggestion": {}}
		return {"stage": sc, "progress": progress,
				"suggestion": {"piece": piece, "alg": " ".join(parts), "text": text}}
	var seg := _formula_segment(facelets, s)
	if seg.is_empty():
		return {"stage": sc, "progress": progress, "suggestion": {}}
	return {"stage": sc, "progress": progress, "suggestion": seg}
