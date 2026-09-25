extends Node
## MCP 外部控制:TCP NDJSON 服务器(PLAN §6)。
## 仅绑 127.0.0.1(默认 8788,-- --cube-port=N 可改);一行 JSON 请求 → 一行 JSON 响应。
## _process 轮询 take_connection,主线程分发,与动画/队列天然无竞态。
## 命令分发 dispatch() 与 socket 层解耦(收/返 Dictionary),不起 socket 可直测(§6.2)。

const CubeScript := preload("res://scripts/cube.gd")
const LBL_SOLVER_PATH := "res://scripts/lbl_solver.gd"  # P2 教学引擎/LBL 求解器(§14)
const FACELET_CHARS := "URFDLB"
const STEPS_MIN := 1
const STEPS_MAX := 100
const ALG_MAX_CHARS := 2000
const ALG_MAX_TOKENS := 300
const MAX_LINE_BYTES := 65536

## CubeRoot(须实现 to_facelets())。main.gd/场景注入或测试直赋;缺省每帧自动发现。
var cube: Node = null
var port := 8788

## 计时事件信号(§15.1):main.gd 据此驱动 timer 状态机——
## scramble_entered(alg):scramble 命令/按钮(alg="")或 WCA 代执行(alg=打乱序列)
##   到达 = 进 scrambled 态(running 中即作废旧轮);普通 apply_alg 不发。
## invalidated():restore/reset 到达 = 当前计时作废。
signal scramble_entered(alg: String)
signal invalidated()

## WCA 打乱标记(§15.1/P3 服务侧):非空 = 当前状态来自一次 WCA 打乱代执行,
## 值即打乱序列(state 可查询)。计时的状态迁移由上方信号驱动;scramble/restore/
## reset 到达本服务器时标记即清(计时作废语义),玩家手动转层不在此清。
var wca_scramble_alg := ""

var _tcp: TCPServer
var _peer: StreamPeerTCP
var _rxbuf := PackedByteArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():  # `godot ... -- --cube-port=N`(F3)
		if arg.begins_with("--cube-port="):
			port = int(arg.get_slice("=", 1))
	_tcp = TCPServer.new()
	if _tcp.listen(port, "127.0.0.1") != OK:  # 端口被占:仅警告,游戏照常运行(§6.4)
		push_warning("CubeServer: 监听 127.0.0.1:%d 失败,MCP 外部控制不可用" % port)
		_tcp = null


func _exit_tree() -> void:
	_drop_peer()
	if _tcp != null:
		_tcp.stop()


func _process(_delta: float) -> void:
	if cube == null:
		_autodiscover()
	if _tcp == null:
		return
	if _peer != null:
		_serve_peer()  # 先 poll 现有连接:检测对端关闭/收发,死连接先释放槽
	if _tcp.is_connection_available():
		var conn := _tcp.take_connection()
		if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			conn.disconnect_from_host()  # 单连接语义:新连接 accept 后立即断开(§6.4)
		else:
			_peer = conn
			_rxbuf = PackedByteArray()


# ---- 分发器(socket 层解耦,收/返 Dictionary,§6.2)----

func dispatch(req: Dictionary) -> Dictionary:
	var id = req.get("id")
	var cmd := String(req.get("cmd", ""))
	if cube == null:
		return _err(id, "cube not ready")
	match cmd:
		"state":
			return {"id": id, "ok": true, "data": _state_data()}
		"scramble":
			var verr := validate_steps(req.get("steps", 25))
			if verr != "":
				return _err(id, verr)
			var rng: RandomNumberGenerator = null
			if req.has("seed"):  # A-6:可选种子,同 (seed, steps) 打乱序列完全可复现
				var serr := validate_seed(req.get("seed"))
				if serr != "":
					return _err(id, serr)
				rng = RandomNumberGenerator.new()
				rng.seed = int(req.get("seed"))
			cube.scramble(int(req.get("steps", 25)), rng)
			wca_scramble_alg = ""  # 再次打乱 = WCA 标记作废(§15.1)
			scramble_entered.emit("")  # 计时:进 scrambled(running 中=作废旧轮)
			return {"id": id, "ok": true, "data":
					{"facelets": facelets_str(), "solved": cube.is_solved(), "moves": cube.moves}}
		"restore":
			var k: int = cube.full_log.size()  # 回放步数 = 待回放路径长
			cube.restore()
			wca_scramble_alg = ""  # restore = 计时作废(§15.1)
			invalidated.emit()
			return {"id": id, "ok": true, "data": {"queued": k}}
		"reset":
			cube.reset()
			wca_scramble_alg = ""  # reset = 计时作废(§15.1)
			invalidated.emit()
			return {"id": id, "ok": true, "data": {"facelets": facelets_str(), "solved": cube.is_solved()}}
		"apply_alg":
			var alg = req.get("alg")
			var verr := validate_alg(alg)
			if verr != "":
				return _err(id, verr)
			var queued: int = cube.play_alg(alg)  # 校验已过;parse 与校验同规则,此处仅防御
			if queued < 0:
				return _err(id, "play_alg 解析失败")
			return {"id": id, "ok": true, "data": {"queued": queued}}
		"scramble_wca_apply":
			# WCA 打乱代执行内部标记入口(§15.1):桥的 cube_scramble_wca 走此命令而非裸
			# apply_alg,计时模块据此识别打乱来源进入 scrambled 态。动画路径与 apply_alg
			# 完全一致(play_alg),差别仅在打上 wca_scramble_alg 标记 + 响应带 from_wca。
			var wca_alg = req.get("alg")
			var wca_verr := validate_alg(wca_alg)
			if wca_verr != "":
				return _err(id, wca_verr)
			var wca_queued: int = cube.play_alg(wca_alg)
			if wca_queued < 0:
				return _err(id, "play_alg 解析失败")
			wca_scramble_alg = wca_alg
			scramble_entered.emit(wca_alg)  # 计时:进 scrambled(§15.1 WCA 打乱来源)
			return {"id": id, "ok": true, "data": {"queued": wca_queued, "from_wca": true}}
		"solve":
			# LBL 分层解(§6.2/§14):纯计算不执行,3 阶专用。引擎是纯函数,输入已 bake
			# facelets,播放中调用与 state 同口径。
			if cube.n != 3:
				return _err(id, "solve 仅支持 3 阶(当前 n=%d)" % cube.n)
			if _lbl_solver() == null:
				return _err(id, "lbl_solver not ready: scripts/lbl_solver.gd 缺失(P2 并行交付中)")
			var sol := _lbl_solve()
			if not bool(sol.get("ok", false)):  # 引擎失败(ok:false)不得包进 ok:true data
				return _err(id, String(sol.get("error", "LBL 求解失败")))
			return {"id": id, "ok": true, "data": sol}
		"hint":
			# 教学提示(§6.2/§14):当前阶段/进度/下一步建议,3 阶专用。
			if cube.n != 3:
				return _err(id, "hint 仅支持 3 阶(当前 n=%d)" % cube.n)
			if _lbl_solver() == null:
				return _err(id, "lbl_solver not ready: scripts/lbl_solver.gd 缺失(P2 并行交付中)")
			var h := _lbl_hint()
			if h.is_empty():
				return _err(id, "教学引擎无建议(状态异常?)")
			if (h.get("suggestion", {}) as Dictionary).is_empty():
				# 引擎枚举不到段(状态异常):stage/progress 仍有效,建议补全 §6.2 三键结构
				h["suggestion"] = {"piece": "", "alg": "", "text": ""}
			return {"id": id, "ok": true, "data": h}
		_:
			return _err(id, "unknown cmd: " + cmd)


## 参数校验(§6.2 v5.1 信任边界,公开供 UI AlgEdit 复用)。返回 "" = 合法。
## 校验先于入队,全有或全无。
func validate_steps(v) -> String:
	if not (v is int or v is float):
		return "steps 必须为数字"
	var f := float(v)
	if f != floorf(f) or f < STEPS_MIN or f > STEPS_MAX:
		return "steps 越界(须 %d..%d)" % [STEPS_MIN, STEPS_MAX]
	return ""


## A-6:seed 校验(JSON 数字 → int64;整数性 + 2^53 精度界,超出即失真)。
func validate_seed(v) -> String:
	if not (v is int or v is float):
		return "seed 必须为数字"
	var f := float(v)
	if f != floorf(f) or absf(f) > 9007199254740992.0:
		return "seed 须为整数且 |seed| ≤ 2^53(JSON 安全整数)"
	return ""


func validate_alg(alg) -> String:
	if not (alg is String):
		return "alg 必须为字符串"
	if alg.is_empty():
		return "alg 不能为空"
	if alg.length() > ALG_MAX_CHARS:
		return "alg 超长(>%d 字符)" % ALG_MAX_CHARS
	var tokens: PackedStringArray = alg.split(" ", false)
	if tokens.size() > ALG_MAX_TOKENS:
		return "alg 超过 %d token" % ALG_MAX_TOKENS
	for t in tokens:
		if not is_valid_wca_token(t):
			return "非法 WCA 记号: " + t
	return ""


func is_valid_wca_token(t: String) -> bool:
	# 单一规则源在 cube.gd,防两份实现漂移;小写宽转合法性随当前阶数(§17.2)
	return CubeScript.is_valid_wca_token(t, cube.n)


# ---- 内部 ----

func _state_data() -> Dictionary:
	return {
		"n": cube.n,
		"facelets": facelets_str(),
		"solved": cube.is_solved(),
		"moves": cube.moves,
		"animating": cube.is_animating(),
		"queue_len": cube._queue.size(),
		"wca_scramble_alg": wca_scramble_alg,  # 可查询 WCA 打乱标记(§15.1,见字段注释)
	}


func facelets_str() -> String:
	var out := ""
	for b in cube.to_facelets():
		out += FACELET_CHARS[b]
	return out


## LBL 引擎惰性加载(命令到达时才 load,勿顶层 preload——并行交付的
## scripts/lbl_solver.gd 缺失时不得阻塞主场景启动)。约定接口:
## static LblSolver.solve(facelets: String) -> Dictionary / static LblSolver.hint(facelets: String)。
## 返回 null = 未就绪(调用方回 ok:false + "lbl_solver not ready")。
func _lbl_solver():
	if not ResourceLoader.exists(LBL_SOLVER_PATH):
		return null
	return load(LBL_SOLVER_PATH)


## LBL 求解(§14,引擎即求解器):输入已 bake facelets,输出 {alg, stages:[{name, alg}]×7}。
## 引擎实现由 scripts/lbl_solver.gd 提供(P2 并行交付),接口以其文件为准:
## solve/hint 收 PackedByteArray(整合期裁决,引擎口径),故直传 cube.to_facelets()。
func _lbl_solve() -> Dictionary:
	var solver = _lbl_solver()
	if solver == null:
		return {}
	return solver.solve(cube.to_facelets())


## 教学提示(§14):输出 {stage, progress, suggestion:{piece, alg, text}}。
func _lbl_hint() -> Dictionary:
	var solver = _lbl_solver()
	if solver == null:
		return {}
	return solver.hint(cube.to_facelets())


func _err(id, msg: String) -> Dictionary:
	return {"id": id, "ok": false, "error": msg}


## CubeServer 与 CubeRoot 同场景时的自动发现(找到即停)。
func _autodiscover() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for child in tree.root.find_children("*", "", true, false):
		if child != self and child.has_method("to_facelets"):
			cube = child
			return


func _serve_peer() -> void:
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop_peer()  # 对端关闭/错误:释放单连接槽
		return
	var avail := _peer.get_available_bytes()
	if avail > 0:
		_rxbuf.append_array(_peer.get_data(avail)[1])
	while true:
		var lf := _rxbuf.find(10)  # b'\n'
		if lf < 0:
			break
		var line := _rxbuf.slice(0, lf).get_string_from_utf8()
		_rxbuf = _rxbuf.slice(lf + 1)
		_handle_line(line)
	if _rxbuf.size() > MAX_LINE_BYTES:
		_send({"id": null, "ok": false, "error": "line too long"})
		_drop_peer()


func _handle_line(line: String) -> void:
	var req = JSON.parse_string(line)
	if req is Dictionary:
		_send(dispatch(req))
	else:
		_send({"id": null, "ok": false, "error": "invalid json request"})


func _send(resp: Dictionary) -> void:
	if _peer == null:
		return
	if _peer.put_data((JSON.stringify(resp) + "\n").to_utf8_buffer()) != OK:
		_drop_peer()


func _drop_peer() -> void:
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_rxbuf = PackedByteArray()
