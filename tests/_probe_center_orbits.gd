extends SceneTree
## 一次性探针(2026-10-06,v7.3 r2 §1 A0 中心群结构论证——grilling Q1/Q9 定案):
## 产出三项,决定 A5 对换原子收集规格与 D1 保底器数学底座:
##   P1 轨道枚举:中心格在 24 旋转群(_cn_axis_tokens 轴整转 × a,b 组合 45 候选,
##      _cn_prealg 同款生成机制)作用下的轨道闭包(union-find)→ 轨道表;
##      代码现状 _cn_cells 无轨道概念,此表为新底座。
##   P2 奇偶耦合:基本转 token(外层 18 + 内层 6×(n-3)×3)对每轨道的置换符号
##      向量 v ∈ F2^k;高斯消元求张成子空间秩 r——r==k 情形 X(无耦合,单轨
##      moved==2 单式可用);r<k 情形 Y(存在 k-r 个约束,轨道奇偶必须落在
##      rank-r 子空间,奇原子需双轨同步对换复合宏)。输出正交补基=约束向量。
##      前置自检:每 token 的置换必须保持 P1 轨道划分(破坏=轨道闭包生成元
##      不足,P1 数据不可信,fail loud)。
##   P3 真中心轨道处置(奇数阶):真中心 6 格轨道单列;v7.1 _cn_prealg 已将真
##      中心归位后才进保底域,该轨道按「不动轨道」登记(保底宏须保持)。
## 同轨传递性由轨道定义直接保证(同轨=互达类),无需单独实测;3-cycle 宏域
##   构造实测属 D1 spike(依赖 A4 宏作用位),不在本探针。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_center_orbits.gd
##
## 终局结论(2026-10-06 实测):轨道表 n=4=1轨(24格 x-center 同轨)/n=5=3轨
##   (角24+边中24+真中心6)/n=6=4轨×24/n=7=7轨(6×24+真中心6);奇偶耦合两阶分化:
##   n=4(k=1,r=1)与 n=5(k=3,r=3)=**情形 X**(轨道奇偶独立,单轨 moved==2 对换
##   物理可达);n=6(k=4,r=2,约束 0⊕3=0 ∧ 1⊕2=0)与 n=7(非真中心 k=6,r=3,
##   约束 0⊕4=0 ∧ 1⊕3=0 ∧ 2⊕3⊕4⊕5=0)=**情形 Y**(单轨对换不可达,奇原子
##   须跨轨双对换复合宏——恰好是社区「center swap」公式的常见天然形态)。
##   真中心轨道(奇数阶)按不动轨道登记(prealg 已归位,保底宏须保持)。
##   首版生成元教训:_cn_axis_tokens 轴整转是 n-1 层宽转(prealg 专用),在非
##   真中心格上不等价整体旋转,闭包出碎片轨道;轨道生成元必须用基本转全体。

const NS := preload("res://scripts/nxn_solver.gd")

const FACES := ["U", "R", "F", "D", "L", "B"]


func _initialize() -> void:
	var any_fail := false
	for n in [4, 5, 6, 7]:
		print("=== n=%d ===" % n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		# ---- P1 轨道闭包(基本转全体做生成元;首版误用 _cn_axis_tokens 轴整转
		# ——那是 n-1 层宽转,prealg 对真中心的专用工具,在其余中心格上不等价
		# 整体旋转,闭包出 21+1+1+1 碎片。轨道定义 = 合法转动群下的互达类,
		# 生成元就该用基本转 token 集) ----
		var toks: Array = []
		for f in FACES:
			for suf in ["", "'", "2"]:
				toks.append(f + suf)
		for d in range(3, n):
			for f in FACES:
				for suf in ["", "'", "2"]:
					toks.append("%d%s%s" % [d, f, suf])
		var rots: Array = []
		for t in toks:
			rots.append(NS._cn_id_perm(String(t), n, cells))
		var uf := _UnionFind.new(m)
		for p in rots:
			for i in m:
				uf.union(i, int(p[i]))
		# 轨道收集:root -> 索引列表(升序)
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		var roots: Array = []
		for i in m:
			var r: int = uf.find(i)
			orbit_of[i] = r
			if not roots.has(r):
				roots.append(r)
		var orbits: Array = []
		for r in roots:
			var grp: Array = []
			for i in m:
				if orbit_of[i] == r:
					grp.append(i)
			orbits.append(grp)
		# 输出:每轨道大小 + 面内位置模式(fi,r,c 反推)
		var pat_s: Array = []
		for oi in orbits.size():
			var pats := {}
			for gi in orbits[oi]:
				var cell: int = cells[gi]
				var fi: int = cell / (n * n)
				var rem: int = cell % (n * n)
				var r: int = rem / n
				var c: int = rem % n
				var key := "%s(%d,%d)" % [FACES[fi], r, c]
				pats[key] = true
			var pl: Array = pats.keys()
			pl.sort()
			pat_s.append("轨道%d[%d格]: %s" % [oi, orbits[oi].size(), " ".join(pl)])
		for s in pat_s:
			print("  " + s)
		# ---- P2 奇偶耦合(F2 秩;toks 即 P1 生成元集) ----
		var k: int = orbits.size()
		var orb_set: Array = []
		for oi in orbits.size():
			var grp := PackedInt32Array()
			grp.resize(orbits[oi].size())
			for j in orbits[oi].size():
				grp[j] = orbits[oi][j]
			orb_set.append(grp)
		var vecs: Array = []
		var check_ok := true
		for t in toks:
			var perm := NS._cn_id_perm(String(t), n, cells)
			var v: Array = []
			for oi in k:
				# 自检:置换保持轨道划分
				for j in orb_set[oi].size():
					if orbit_of[int(perm[orb_set[oi][j]])] != orbit_of[orb_set[oi][j]]:
						check_ok = false
				v.append(_parity_on(perm, orb_set[oi]))
			vecs.append(v)
		if not check_ok:
			print("  FAIL  P2 自检:存在 token 破坏轨道划分(轨道闭包生成元不足),数据不可信")
			any_fail = true
			continue
		var rank_data: Dictionary = _f2_rank(vecs, k)
		var r: int = int(rank_data.rank)
		var basis: Array = rank_data.basis
		if r == k:
			print("  奇偶耦合: 无(F2 秩 r=%d=k=%d)→ **情形 X**:每轨道奇偶独立可控,单轨 moved==2 对换单式可用" % [r, k])
		else:
			var cons: Array = _f2_orth_complement(basis, k)
			var cs: Array = []
			for cv in cons:
				var parts: Array = []
				for oi in k:
					if int(cv[oi]) == 1:
						parts.append("轨道%d" % oi)
				cs.append("+".join(parts) + "=0(奇偶恒同步)")
			print("  奇偶耦合: **情形 Y**(秩 r=%d < k=%d,约束 %d 条): %s → 奇原子需多轨同步对换复合宏" % [r, k, cons.size(), "; ".join(cs)])
		# ---- P3 真中心轨道(奇数阶) ----
		if n % 2 == 1:
			var mid: int = (n - 1) / 2
			var tc := -1
			for oi in orbits.size():
				var is_tc: bool = orbits[oi].size() == 6
				if is_tc:
					for gi in orbits[oi]:
						var cell: int = cells[gi]
						var fi: int = cell / (n * n)
						var rem: int = cell % (n * n)
						if rem / n != mid or rem % n != mid:
							is_tc = false
							break
				if is_tc:
					tc = oi
					break
			print("  真中心轨道: %s——prealg 后按不动轨道登记,保底宏须保持" % ("轨道%d(6 格,每面 (mid,mid))" % tc if tc >= 0 else "未检出(检判缺陷,P3 数据不可信)"))
			if tc < 0:
				any_fail = true
		print("  token 总数 %d(外层 18+内层 %d),轨道数 k=%d" % [toks.size(), 6 * (n - 3) * 3, k])
		print("")
	quit(1 if any_fail else 0)


## 置换 perm 限制在子集 grp 上的奇偶(0 偶 1 奇):循环分解,O(len) 双指针。
func _parity_on(perm: PackedInt32Array, grp: PackedInt32Array) -> int:
	var seen := PackedByteArray()
	seen.resize(grp.size())
	var cycles := 0
	for s in grp.size():
		if seen[s] == 1:
			continue
		cycles += 1
		var j := s
		while seen[j] == 0:
			seen[j] = 1
			# grp 内位置 j 的格映射:perm[grp[j]] 必在 grp 内(P2 自检保证),
			# 找回它在 grp 的下标——预计算反查表更省,这里 grp 小(≤30)线性可接受
			var target: int = perm[grp[j]]
			var nxt := -1
			for q in grp.size():
				if grp[q] == target:
					nxt = q
					break
			j = nxt
	return (grp.size() - cycles) % 2


## F2 高斯消元:返回 {rank, basis}(basis 为行简化后非零行)。
func _f2_rank(vecs: Array, k: int) -> Dictionary:
	var rows: Array = []
	for v in vecs:
		rows.append((v as Array).duplicate())
	var basis: Array = []
	var col := 0
	var ri := 0
	while col < k and ri < rows.size():
		var piv := -1
		for j in range(ri, rows.size()):
			if int(rows[j][col]) == 1:
				piv = j
				break
		if piv < 0:
			col += 1
			continue
		var tmp: Array = rows[ri]
		rows[ri] = rows[piv]
		rows[piv] = tmp
		for j in rows.size():
			if j != ri and int(rows[j][col]) == 1:
				for c2 in k:
					rows[j][c2] = int(rows[j][c2]) ^ int(rows[ri][c2])
		basis.append(rows[ri])
		ri += 1
		col += 1
	return {"rank": basis.size(), "basis": basis}


## 正交补:与 basis 全部行正交的 F2^k 向量空间基——枚举 2^k(k≤5)取正交
## 非零向量,对其复用 _f2_rank 取行简化基(独立性与秩由消元保证)。
func _f2_orth_complement(basis: Array, k: int) -> Array:
	var orth: Array = []
	for mask in range(1 << k):
		var v: Array = []
		var bits := 0
		for b in k:
			var bit: int = (mask >> b) & 1
			v.append(bit)
			bits += bit
		if bits == 0:
			continue
		var ok := true
		for row in basis:
			var dot := 0
			for c in k:
				dot += int(v[c]) & int(row[c])
			if dot % 2 == 1:
				ok = false
				break
		if ok:
			orth.append(v)
	return (_f2_rank(orth, k) as Dictionary).basis


class _UnionFind:
	var p: PackedInt32Array

	func _init(size: int) -> void:
		p.resize(size)
		for i in size:
			p[i] = i

	func find(x: int) -> int:
		while p[x] != x:
			p[x] = p[p[x]]
			x = p[x]
		return x

	func union(a: int, b: int) -> void:
		var ra := find(a)
		var rb := find(b)
		if ra != rb:
			p[rb] = ra
