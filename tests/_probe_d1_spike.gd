extends SceneTree
## 一次性探针(2026-10-06,v7.3 D1 spike——共轭字典法可行性判定):
## 背景:A1 两轮组合枚举证伪(一阶 [X,Y] 恒偶+交差≥4格;二阶 宏×层转交差
##   无 3格3面——效应格=宏效应格∩层切,面分布为子集的子集),B3 单式不入池
##   (方案风险 2 预案生效,0% 责任移交 D1)。
## D1 架构(本探针判定):共轭字典法——库内 3-cycle 种子宏 M(效应循环 (p q r))
##   × 层转²共轭域 s⁻¹Ms → 效应 = (s⁻¹p s⁻¹q s⁻¹r),覆盖任意同构型类目标。
##   完备性判据:种子循环构型类 × 共轭像 = 覆盖轨道内全部三格构型类。
## 判定预注册(grilling Q11 口径):
##   覆盖率 100%(每轨道全部 C(|O|,3) 构型类可达) → 共轭字典法 GO;
##   <100% → 统计缺口构型类,扩充种子源(二阶谱 3格2面 形态宏 144 条/阶)
##   后重测;仍缺口 → 回报(保底器降级为「逐循环 BFS 长搜」)。
## 共轭域规模:toks²(≤8100) × 种子循环(去重后 ≤ 数十条/阶),效应计算 O(6n²)
##   ——构建期一次量级,实测时长即运行期 _cn_ensure 追加成本的直接证据。
## 不在 CI 清单;复核运行:godot --headless -s tests/_probe_d1_spike.gd

const NS := preload("res://scripts/nxn_solver.gd")

const FACES := ["U", "R", "F", "D", "L", "B"]


func _initialize() -> void:
	for n in [4, 5, 6, 7]:
		var t0 := Time.get_ticks_msec()
		print("=== n=%d ===" % n)
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var pc: int = (n - 2) * (n - 2)
		var ctx: Dictionary = NS._cn_ensure(n)
		var toks: Array = []
		for f in FACES:
			for suf in ["", "'", "2"]:
				toks.append(f + suf)
		for d in range(3, n):
			for f in FACES:
				for suf in ["", "'", "2"]:
					toks.append("%d%s%s" % [d, f, suf])
		var tokperms: Array = []
		for t in toks:
			tokperms.append(NS._cn_id_perm(String(t), n, cells))
		var inv_toks: Array = []
		for t in toks:
			inv_toks.append(_inv(String(t)))
		# 轨道
		var uf := _UnionFind.new(m)
		for p in tokperms:
			for i in m:
				uf.union(i, int(p[i]))
		var orbit_of := PackedInt32Array()
		orbit_of.resize(m)
		var orbit_groups := {}
		for i in m:
			orbit_of[i] = uf.find(i)
			if not orbit_groups.has(orbit_of[i]):
				orbit_groups[orbit_of[i]] = []
			(orbit_groups[orbit_of[i]] as Array).append(i)
		# 种子 3-cycle:库内 moved==3 宏(B2/T 族等)的效应循环
		var seeds: Array = []   # [{alg, cycle:[p,q,r]}]
		var seen_cyc := {}
		for key3 in ["end_atoms", "bfs_atoms"]:
			for e: Dictionary in ctx[key3]:
				var perm: PackedInt32Array = e.perm
				var moved: Array = []
				for k2 in m:
					if perm[k2] != k2:
						moved.append(k2)
				if moved.size() != 3:
					continue
				# 环起点 = 最小下标
				var nxt: int = int(perm[moved[0]])
				var cyc: Array = [moved[0]]
				while nxt != moved[0]:
					cyc.append(nxt)
					nxt = int(perm[nxt])
				var key := "%d,%d,%d" % [cyc[0], cyc[1], cyc[2]]
				if seen_cyc.has(key):
					continue
				seen_cyc[key] = true
				seeds.append({"alg": String(e.alg), "cycle": cyc})
		print("  种子循环 %d 个(库 moved==3 去重)" % seeds.size())
		# 全部三格构型类(按轨道) = C(|O|,3) 的转动群轨道分类:
		# 判定法 = 用「共轭像实测算」代替抽象分类——对每个候选三格 {a,b,c}
		# (按轨道枚举),检查是否存在种子循环 (p q r) 与 s∈toks² 使
		# s(p)=a', s(q)=b', s(r)=c'({a,b,c} 的某个环起序匹配)。
		# 直接枚举 C(24,3)=2024 × 种子 × toks²(8100) 太大;换向:
		# 构建共轭像集合 = {(s⁻¹p, s⁻¹q, s⁻¹r)} 全部(种子 × 8100),key=排序三元组
		# → 目标三格枚举查集合。种子×8100 次效应计算 O(m) —— n=7: 40×72900×294
		# ≈ 8.6 亿 ops,GDScript 分钟级;先只取每构型类首见,预算内可跑。
		var covered := {}
		var seed_repr: Array = []
		for sd in seeds:
			var cyc: Array = sd.cycle
			var o: int = orbit_of[cyc[0]]
			if orbit_of[cyc[1]] != o or orbit_of[cyc[2]] != o:
				continue   # 种子循环跨轨不计(单轨传递性判定对象)
			seed_repr.append(sd)
		print("  单轨种子循环 %d 个" % seed_repr.size())
		var tok2perm := {}
		for i in toks.size():
			for j in toks.size():
				var alg2 := "%s %s" % [toks[i], toks[j]]
				tok2perm[alg2] = _compose(tokperms[j], tokperms[i], m)
		var t1 := Time.get_ticks_msec()
		print("  toks² 复合缓存 %d 项 (%dms)" % [tok2perm.size(), t1 - t0])
		for sd in seed_repr:
			var cyc: Array = sd.cycle
			for alg2 in tok2perm:
				var s2: PackedInt32Array = tok2perm[alg2]
				# 效应 = s⁻¹ M s 的循环 = (s⁻¹(p) s⁻¹(q) s⁻¹(r))——共轭映射下
				# M 循环 (p→q→r→p) 的像。s⁻¹(x) = 使 s(y)=x 的 y,查反表:
				# 这里直接用 s2 的逆复合:像格 = s2⁻¹(cyc[i])。
				var trip: Array = []
				for ci in 3:
					trip.append(_preimg(s2, cyc[ci]))
				trip.sort()
				var kk := "%d|%d,%d,%d" % [orbit_of[int(trip[0])], trip[0], trip[1], trip[2]]
				if not covered.has(kk):
					covered[kk] = {"alg": "%s' %s %s" % [alg2, sd.alg, _inv(alg2)], "seed": sd.alg}
		var t2 := Time.get_ticks_msec()
		print("  共轭像构建 (%dms)" % [t2 - t1])
		# 覆盖率:每轨道 C(|O|,3) 三格组合查表
		var total := 0
		var hit := 0
		var miss_sample: Array = []
		for o in orbit_groups:
			var grp: Array = orbit_groups[o]
			if grp.size() < 3:
				continue
			for a in grp.size():
				for b in range(a + 1, grp.size()):
					for c in range(b + 1, grp.size()):
						total += 1
						var trip: Array = [grp[a], grp[b], grp[c]]
						trip.sort()
						var kk := "%d|%d,%d,%d" % [o, trip[0], trip[1], trip[2]]
						if covered.has(kk):
							hit += 1
						elif miss_sample.size() < 8:
							miss_sample.append(trip)
		print("  覆盖率 %d/%d = %.1f%% → %s" % [hit, total, 100.0 * hit / max(total, 1),
				"GO(共轭字典法完备)" if hit == total else "缺口(种子源需扩充)"])
		if miss_sample.size() > 0:
			print("  缺口样例: %s" % str(miss_sample))
		print("  总耗时 %dms" % [Time.get_ticks_msec() - t0])
		print("")
	quit(0)


func _compose(outer: PackedInt32Array, inner: PackedInt32Array, m: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(m)
	for i in m:
		out[i] = outer[inner[i]]
	return out


func _preimg(s: PackedInt32Array, x: int) -> int:
	for i in s.size():
		if s[i] == x:
			return i
	return -1


func _inv(alg: String) -> String:
	var parts: PackedStringArray = alg.split(" ")
	var out: Array = []
	for i in range(parts.size() - 1, -1, -1):
		var t: String = parts[i]
		if t.ends_with("'"):
			out.append(t.substr(0, t.length() - 1))
		elif t.ends_with("2"):
			out.append(t)
		else:
			out.append(t + "'")
	return " ".join(out)


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
