extends SceneTree
## 一次性探针(2026-10-05 样例宏验证):对 docs/center-macro-impl-design.md
## 第 5 章「样例验证清单」逐条实测——V1-V10 + §5.3 否定样例。
## 口径(§5.0):复原态填唯一 id → 应用宏 → _cn_id_perm 读回置换,
## 位置链 i→perm[i] 收集环,与「声称效果」列逐格比对;_cn_entry 的
## keeps/touch 与「不动面」列比对;记号逐 token 过 is_valid_wca_token。
## 不在 CI 清单;复核:
##   cd /home/muyouzi/godot-project && \
##   /home/muyouzi/.local/bin/godot --headless -s tests/_probe_macro_check.gd
## exit 0 = 全部条目 PASS,1 = 存在 FAIL。

const NS := preload("res://scripts/nxn_solver.gd")
const CUBE := preload("res://scripts/cube.gd")
const FACE := ["U", "R", "F", "D", "L", "B"]

## 声称数据原样摘自 docs/center-macro-impl-design.md §5.1/§5.2(环格名、
## keeps/touch 掩码;位序 U R F D L B = 1 2 4 8 16 32)。
const CASES := [
	{"id": "V1", "n": 7, "alg": "4R F2 4R'",
		"cycles": [["F00", "F44"], ["F01", "F43"], ["F03", "F41"], ["F04", "F40"],
			["F10", "F34"], ["F11", "F33"], ["F13", "F31"], ["F14", "F30"],
			["F20", "F24"], ["F21", "F23"], ["D02", "D42"], ["D12", "D32"]],
		"keeps": 63, "touch": 12},
	{"id": "V2", "n": 5, "alg": "3R F2 3R'",
		"cycles": [["F00", "F22"], ["F02", "F20"], ["F10", "F12"], ["D01", "D21"]],
		"keeps": 63, "touch": 12},
	{"id": "V3", "n": 5, "alg": "3R F 4R F' 3R' F 4R' F'",
		"cycles": [["F21", "D21", "D10"]],
		"keeps": 51, "touch": 12},
	{"id": "V4", "n": 7, "alg": "3R F 6R F' 3R' F 6R' F'",
		"cycles": [["F43", "D43", "D30"]],
		"keeps": 51, "touch": 12},
	# V4 修订记录(§5.1,2026-10-05)依据的 n=7 六档全表其余五档,复验一并断言:
	{"id": "R34", "n": 7, "alg": "3R F 4R F' 3R' F 4R' F'",
		"cycles": [["F23", "D23", "D32"]], "keeps": 51, "touch": 12},
	{"id": "R35", "n": 7, "alg": "3R F 5R F' 3R' F 5R' F'",
		"cycles": [["F33", "D33", "D31"]], "keeps": 51, "touch": 12},
	{"id": "R45", "n": 7, "alg": "4R F 5R F' 4R' F 5R' F'",
		"cycles": [["F32", "D32", "D21"]], "keeps": 51, "touch": 12},
	{"id": "R46", "n": 7, "alg": "4R F 6R F' 4R' F 6R' F'",
		"cycles": [["F42", "D42", "D20"]], "keeps": 51, "touch": 12},
	{"id": "R56", "n": 7, "alg": "5R F 6R F' 5R' F 6R' F'",
		"cycles": [["F41", "D41", "D10"]], "keeps": 51, "touch": 12},
	{"id": "V5", "n": 5, "alg": "4R' F' 3R' F 4R F' 3R F",
		"cycles": [["U10", "U21", "F10"]],
		"keeps": 58, "touch": 5},
	{"id": "V6", "n": 5, "alg": "3R F2 3R' F2",
		"cycles": [["F01", "F21"], ["D01", "D21"]],
		"keeps": 63, "touch": 12},
	{"id": "V7", "n": 4, "alg": "l2 L2 f2 F2 l2 L2 f2 F2",
		"cycles": [["U00", "U11", "D00"], ["U10", "D10", "D01"]],
		"keeps": 54, "touch": 9},
	{"id": "V8", "n": 4, "alg": "B2 3R' 3F 3R B2 3R' 3F' 3R",
		"cycles": [["L10", "B11", "B00"]],
		"keeps": 15, "touch": 48},
	{"id": "V9", "n": 5, "alg": "4L2 4B2 4L2 4B2",
		"cycles": [["U02", "U20", "D02"], ["U22", "D22", "D00"]],
		"keeps": 54, "touch": 9},
	{"id": "V10", "n": 4, "alg": "3R2 3F2 3R2 3F2",
		"cycles": [["U00", "D00", "D11"], ["U01", "D10", "U10"]],
		"keeps": 54, "touch": 9},
]


func _initialize() -> void:
	var fails := 0
	for c in CASES:
		if not _check(c):
			fails += 1
	# --- V6 附带声称:n=7 的 `4R F2 4R' F2` 同构 8 格 4 对 ---
	if not _check({"id": "V6b", "n": 7, "alg": "4R F2 4R' F2",
			"cycles": [["F02", "F42"], ["F12", "F32"], ["D02", "D42"],
				["D12", "D32"]],
			"keeps": 63, "touch": 12}):
		fails += 1
	# --- V9 附带声称:与复合形式 r2 R2 f2 F2 ... 实测同环 ---
	print("\n[V9b] n=5 对拍: `4L2 4B2 4L2 4B2` vs `r2 R2 f2 F2 r2 R2 f2 F2`")
	var cells9: PackedInt32Array = NS._cn_cells(5)
	var p_a: PackedInt32Array = NS._cn_id_perm("4L2 4B2 4L2 4B2", 5, cells9)
	var p_b: PackedInt32Array = NS._cn_id_perm("r2 R2 f2 F2 r2 R2 f2 F2", 5, cells9)
	var same := true
	for i in p_a.size():
		if p_a[i] != p_b[i]:
			same = false
			break
	print("  perm 全等(同环同向)=%s" % ["PASS" if same else "FAIL"])
	if not same:
		fails += 1
	# --- §5.3 否定样例 1:n=5 `3L2 3F2 3L2 3F2` = IDENTITY ---
	print("\n[N1] n=5 `3L2 3F2 3L2 3F2` 应为 IDENTITY(中央层自消)")
	var ident := true
	var p_n1: PackedInt32Array = NS._cn_id_perm("3L2 3F2 3L2 3F2", 5, cells9)
	for i in p_n1.size():
		if p_n1[i] != i:
			ident = false
			break
	print("  identity=%s → %s" % [ident, "PASS" if ident else "FAIL"])
	if not ident:
		fails += 1
	# --- §5.3 否定样例 2:n=4 T 族枚举域为空(内层仅一档) ---
	print("\n[N2] n=4 T 族枚举域(d,e ∈ 3..n-1, d≠e)应为空")
	var t3: bool = CUBE.is_valid_wca_token("3R", 4)
	var t2: bool = CUBE.is_valid_wca_token("2R", 4)
	var t4: bool = CUBE.is_valid_wca_token("4R", 4)
	var pairs := 0
	for d in range(3, 4):
		for e in range(3, 4):
			if d != e:
				pairs += 1
	print("  is_valid_wca_token: 3R(n=4)=%s 2R(n=4)=%s 4R(n=4)=%s;域{3..n-1}内 d≠e 有序对数=%d"
			% [t3, t2, t4, pairs])
	var n2ok: bool = t3 and not t2 and not t4 and pairs == 0
	print("  → %s(3R 唯一合法内层档 → 无 d≠e 组合)" % ["PASS" if n2ok else "FAIL"])
	if not n2ok:
		fails += 1
	# 附带观察(非清单条目):n=4 同带形非纯 3-cycle
	var cells4: PackedInt32Array = NS._cn_cells(4)
	var p_same: PackedInt32Array = NS._cn_id_perm("3R F 3R F' 3R' F 3R' F'", 4, cells4)
	var mv := 0
	for i in p_same.size():
		if p_same[i] != i:
			mv += 1
	print("\n[obs] n=4 同带形 `3R F 3R F' 3R' F 3R' F'` moved=%d(非纯 3-cycle:%s)"
			% [mv, "是" if mv != 3 else "否(意外)"])
	print("\n===== 汇总:%d FAIL =====" % fails)
	quit(1 if fails > 0 else 0)


## 单条验证:token 合法 + 环逐格一致 + keeps/touch 一致。打印明细。
func _check(c: Dictionary) -> bool:
	var n: int = c.n
	var k: int = n - 2
	var pc: int = k * k
	print("\n[%s] n=%d alg=`%s`" % [c.id, n, c.alg])
	# ① token 合法性
	var bad_tokens: Array = []
	for t in String(c.alg).split(" ", false):
		if not CUBE.is_valid_wca_token(t, n):
			bad_tokens.append(t)
	if not bad_tokens.is_empty():
		print("  tokens: 非法 %s → FAIL" % str(bad_tokens))
		return false
	# ② 置换环
	var cells: PackedInt32Array = NS._cn_cells(n)
	var perm: PackedInt32Array = NS._cn_id_perm(String(c.alg), n, cells)
	var act := _perm_cycles(perm, pc, k)
	var moved := 0
	for i in perm.size():
		if perm[i] != i:
			moved += 1
	# ③ keeps/touch
	var e: Dictionary = NS._cn_entry(String(c.alg), perm, pc)
	print("  moved=%d keeps=%d(%s) touch=%d(%s)" % [moved, int(e.keeps),
			_mask_str(int(e.keeps)), int(e.touch), _mask_str(int(e.touch))])
	print("  实测环: %s" % [_fmt_cycles(act, true)])
	var ok := true
	if not _cycles_equal(act, c.cycles):
		ok = false
		print("  声称环: %s → 环不一致" % [_fmt_cycles(c.cycles, false)])
	if moved != _claimed_moved(c.cycles):
		ok = false
	if int(e.keeps) != int(c.keeps):
		ok = false
		print("  声称 keeps=%d(%s) → 不一致" % [int(c.keeps), _mask_str(int(c.keeps))])
	if int(e.touch) != int(c.touch):
		ok = false
		print("  声称 touch=%d(%s) → 不一致" % [int(c.touch), _mask_str(int(c.touch))])
	print("  → %s" % ("PASS" if ok else "FAIL"))
	return ok


## 沿位置链 i→perm[i] 收集非平凡环(§5.0 口径),格名化。
func _perm_cycles(perm: PackedInt32Array, pc: int, k: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(perm.size())
	var out: Array = []
	for i in perm.size():
		if perm[i] == i:
			seen[i] = 1
			continue
		if seen[i] == 1:
			continue
		var cyc: Array = []
		var j := i
		while seen[j] == 0:
			seen[j] = 1
			cyc.append("%s%d%d" % [FACE[j / pc], (j % pc) / k, (j % pc) % k])
			j = perm[j]
		out.append(cyc)
	return out


## 环多重集相等:每环取旋转等价规范形(字典序最小旋转),排序后比对。
func _cycles_equal(act: Array, claimed: Array) -> bool:
	var a := _sig(act)
	var b := _sig(claimed)
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func _sig(cycles: Array) -> Array:
	var s: Array = []
	for cyc in cycles:
		var best := ""
		for i in cyc.size():
			var rot: Array = []
			for j in cyc.size():
				rot.append(cyc[(i + j) % cyc.size()])
			var str_rot: String = " ".join(PackedStringArray(rot))
			if best == "" or str_rot < best:
				best = str_rot
		s.append(best)
	s.sort()
	return s


func _claimed_moved(cycles: Array) -> int:
	var m := 0
	for cyc in cycles:
		m += cyc.size()
	return m


func _fmt_cycles(cycles: Array, paren: bool) -> String:
	var parts: PackedStringArray = []
	for cyc in cycles:
		if paren:
			parts.append("(" + " ".join(PackedStringArray(cyc)) + ")")
		else:
			parts.append(" ".join(PackedStringArray(cyc)))
	return "".join(parts)


func _mask_str(m: int) -> String:
	var s := ""
	for i in 6:
		s += FACE[i] if (m & (1 << i)) != 0 else "-"
	return s
