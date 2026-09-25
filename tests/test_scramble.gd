extends SceneTree
## 打乱改造测试(v6.3,T-scramble):NxN 混合层打乱(外层/内层/宽层)+ WCA 官方步数。
## 运行:godot --headless -s tests/test_scramble.gd;退出码末尾统一判定。

var _fail := false


func _initialize() -> void:
	_run()


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  " + msg)
	else:
		printerr("FAIL  " + msg)
		_fail = true


func _run() -> void:
	# 官方步数表(TNoodle:2 阶 11,3 阶 25,4 阶 40,5 阶 60,6 阶 80,7 阶 100)
	var official := {2: 11, 3: 25, 4: 40, 5: 60, 6: 80, 7: 100}
	print("RUN-START")
	for N in [2, 3, 4, 5, 6, 7]:
		var c = load("res://scripts/cube.gd").new()
		root.add_child(c)
		c.setup(N)
		# 1. 守恒基线:每色 N²
		print("N=", N)
		var counts := {}
		for cub in c.cubies:
			for k in cub.stickers:
				var v: int = cub.stickers[k]
				counts[v] = counts.get(v, 0) + 1
		var conserved := true
		for k in counts:
			if counts[k] != N * N:
				conserved = false
		_check(conserved, "N=%d 打乱前每色 %d 枚守恒" % [N, N * N])
		# 2. 无参打乱:官方步数 + 非复原
		c.scramble()
		_check(c.full_log.size() == int(official[N]),
				"N=%d 无参打乱步数 == %d(实得 %d)" % [N, official[N], c.full_log.size()])
		var solved_after: bool = c.is_solved()
		_check(not solved_after, "N=%d 打乱后非复原态" % N)
		# 3. 层组约束:永不整体旋转(宽层组 < n 层)
		var whole := false
		for t in c.full_log:
			if t.layers.size() >= N:
				whole = true
		_check(not whole, "N=%d 无整体旋转步(layers < n)" % N)
		# 4. N>=4 内层/宽层确实参与(存在非外层单层步)
		if N >= 4:
			var has_inner := false
			for t in c.full_log:
				if t.layers.size() > 1 or int(t.layers[0]) != c.E:
					has_inner = true
			_check(has_inner, "N=%d 打乱含内层/宽层步" % N)
		else:
			var all_outer := true
			for t in c.full_log:
				if t.layers.size() != 1 or int(t.layers[0]) != c.E:
					all_outer = false
			_check(all_outer, "N=3 打乱恒外层单层(旧行为保持)")
		# 5. 数学复原:逆序瞬时取反 → 复原(restore 的队列/pop 语义由 self_test T3/T9 覆盖;
		#    headless 下逐帧等动画不推进,故此处用纯数学验证任意层组的可逆性)
		for i in range(c.full_log.size() - 1, -1, -1):
			var t2: Dictionary = c.full_log[i]
			c.apply_turn(t2.axis, t2.layers, -float(t2.angle))
		_check(c.is_solved(), "N=%d full_log 逆序取反精确复原" % N)
		c.queue_free()
	# 7. 显式 steps 优先(测试/MCP 向后兼容)
	var c2 = load("res://scripts/cube.gd").new()
	root.add_child(c2)
	c2.setup(4)
	c2.scramble(5)
	_check(c2.full_log.size() == 5, "显式 steps=5 优先于按阶默认")
	# 8. 种子可复现(A-6):注入 RandomNumberGenerator 实例,同 seed 同步数下
	#    动作序列与 facelets 完全一致,不同 seed 不同;不触碰全局熵
	#    (无参 scramble 走全局 randi() 的原行为已由上面各段覆盖)。
	#    3 阶(恒外层)与 4 阶(内层/宽层参与)两条随机路径都验。
	var runs := []  # {n, seed, seq, facelets}
	for item in [[3, 20260925], [3, 20260925], [3, 777], [4, 42], [4, 42]]:
		var cn: int = item[0]
		var sd: int = item[1]
		c2.setup(cn)  # 每次从复原态打乱,facelets 才可比
		var r := RandomNumberGenerator.new()
		r.seed = sd
		c2.scramble(0, r)  # steps=0 = 按阶官方默认步数
		var seq := []
		for t in c2.full_log:
			seq.append([t.axis, t.layers, t.angle])
		runs.append({"n": cn, "seed": sd, "seq": seq, "facelets": c2.to_facelets()})
	_check(runs[0].seq == runs[1].seq and runs[0].facelets == runs[1].facelets,
			"N=3 同 seed 两次打乱序列与 facelets 完全一致")
	_check(runs[0].seq != runs[2].seq, "N=3 不同 seed 打乱序列不同")
	_check(runs[3].seq == runs[4].seq and runs[3].facelets == runs[4].facelets,
			"N=4 同 seed 两次打乱序列与 facelets 完全一致(内层/宽层路径)")
	c2.queue_free()
	print("T-scramble %s" % ("ALL PASSED" if not _fail else "FAILED"))
	quit(1 if _fail else 0)
