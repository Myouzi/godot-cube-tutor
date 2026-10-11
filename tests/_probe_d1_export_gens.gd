extends SceneTree
## D1 commit 1 探针(2026-10-11):Minkwitz 离线管线输入——层转全集 gens 按阶
## 4..7 导出 JSON。域同 _fb_build(nxn_solver.gd:3463-3484):外层 6面×3suffix +
## 内层 d∈3..n-1 6面×3suffix,_fb_key 去重(对层互逆重复已并),记号同引擎。
## 阶段0 fixture(tests/fixtures/stage0_sigma.json 的 gens_by_n)已实测 n=5/6/7
## =45/54/63 并澄清 impl-plan §9.2 的 90 vs 63 冲突(spike 90 是未去重 token
## 数);本探针补 n=4 单独落盘管线输入。每阶附 djb2 32 位域哈希(commit 2 的
## bin 头用同款哈希防旧版误载;Python 侧 tools/minkwitz_build.py 同款实现)。
## 不含库原子——σ/orbit 只依赖群不依赖生成元集,库原子是层转乘积不改变群。
## 不在 CI 清单;复核运行:
## bash -c 'ulimit -v 4000000 && timeout 300 godot --headless -s tests/_probe_d1_export_gens.gd'

const NS := preload("res://scripts/nxn_solver.gd")
const OUT := "res://tests/fixtures/minkwitz_gens.json"


## djb2 32 位域哈希: h=5381 起步,对规范串逐字符 h=(h*33+unicode)&0x7FFFFFFF。
## Python 侧同款: h=5381; for ch in s: h=(h*33+ord(ch))&0x7FFFFFFF
static func _domain_hash(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h * 33) + s.unicode_at(i)) & 0x7FFFFFFF
	return h


## 层转全集 gens(域同 _fb_build :3463-3484:外层 6×3 + 内层 d∈3..n-1 6×3,
## _fb_key 去重;与 tests/_probe_stage0_export.gd:23-45 同款)
func _layer_gens(n: int, cells: PackedInt32Array) -> Array:
	var gens: Array = []
	var seen: Dictionary = {}
	for f in ["U", "R", "F", "D", "L", "B"]:
		for suf in ["", "'", "2"]:
			var ta: String = f + suf
			var tp: PackedInt32Array = NS._cn_id_perm(ta, n, cells)
			var kk := NS._fb_key(tp)
			if seen.has(kk):
				continue
			seen[kk] = true
			gens.append({"alg": ta, "perm": tp, "tokens": 1})
	for d in range(3, n):
		for f2 in ["U", "R", "F", "D", "L", "B"]:
			for suf2 in ["", "'", "2"]:
				var ta2: String = "%d%s%s" % [d, f2, suf2]
				var tp2: PackedInt32Array = NS._cn_id_perm(ta2, n, cells)
				var kk2 := NS._fb_key(tp2)
				if seen.has(kk2):
					continue
				seen[kk2] = true
				gens.append({"alg": ta2, "perm": tp2, "tokens": 1})
	return gens


func _p2a(p: PackedInt32Array) -> Array:
	var a: Array = []
	a.resize(p.size())
	for i in p.size():
		a[i] = p[i]
	return a


func _initialize() -> void:
	var out := {
		"meta": {
			"generated_by": "tests/_probe_d1_export_gens.gd",
			"domain": "中心段 cells 域: idx -> facelet fi*n*n + r*n + c (fi 面序 U R F D L B, r,c ∈ 1..n-2), 同引擎 _cn_cells",
			"perm_semantics": "pull: new[j] = old[perm[j]] (同引擎 _cn_apply), gens 与运行期 _fb_build 消费同一语义",
			"gens_domain": "层转全集: 外层 6面×3suffix + 内层 d∈3..n-1 6面×3suffix, _fb_key 去重(对层互逆重复已并), 记号同引擎(如 '3R' 从 R 面数第 3 层)。不含库原子——σ/orbit 只依赖群不依赖生成元集",
			"domain_hash": "djb2 32 位: 规范串 = 'n=<n>;' + 逐 gens '<alg>:<c0,c1,...>;', h=5381 起步 h=(h*33+unicode)&0x7FFFFFFF。commit 2 的 bin 头用同款哈希防旧版误载",
		},
		"gens_by_n": {},
		"domain_hash_by_n": {},
	}
	for n in [4, 5, 6, 7]:
		var cells: PackedInt32Array = NS._cn_cells(n)
		var m: int = cells.size()
		var gens := _layer_gens(n, cells)
		# 规范串与域哈希(alg 与 perm 序列全部入哈希)
		var canon := "n=%d;" % n
		var glist: Array = []
		for g in gens:
			var pa: Array = _p2a(g.perm)
			var perm_s := ""
			for i in pa.size():
				if i > 0:
					perm_s += ","
				perm_s += str(pa[i])
			canon += "%s:%s;" % [String(g.alg), perm_s]
			glist.append({"alg": String(g.alg), "perm": pa})
		var dh := _domain_hash(canon)
		# 轨道指纹(并查集,同 _fb_build :3601-3613 口径)
		var uf := NS._UnionFindP.new(m)
		for g in gens:
			var gp: PackedInt32Array = g.perm
			for j in m:
				uf.union(j, gp[j])
		var orbit_groups: Dictionary = {}
		for j in m:
			var r: int = uf.find(j)
			if not orbit_groups.has(r):
				orbit_groups[r] = []
			(orbit_groups[r] as Array).append(j)
		var orb_sizes: Array = []
		for t in orbit_groups:
			orb_sizes.append((orbit_groups[t] as Array).size())
		orb_sizes.sort()
		out["gens_by_n"][str(n)] = glist
		out["domain_hash_by_n"][str(n)] = dh
		print("n=%d: cells=%d 层转gens=%d 轨道=%s 域哈希=%d" % [n, m, gens.size(), str(orb_sizes), dh])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("打不开 %s" % OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("WROTE %s (n=4..7)" % OUT)
	quit(0)
