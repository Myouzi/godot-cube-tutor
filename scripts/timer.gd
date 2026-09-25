extends RefCounted
## 计时器(PLAN §15.1/§15.2):四态状态机 + 成绩存储/AO 统计,纯逻辑无 UI。
## 状态机:idle → scrambled(enter_scrambled,打乱按钮/scramble 命令/WCA 标记入口统一走这里,
## 由 UI 接线)→ running(首次玩家转层,键盘/拖层)→ solved(is_solved 为真瞬间)。
## 作废(不记成绩,§15.1):计时中切模式、restore/reset/退出 → invalidate();
## running 中再次打乱(enter_scrambled)= 作废当前计时后开新轮。
## UndoBtn 不起表(修正不是转层):on_undo() 为显式空入口,不改状态不打断计时。

enum State { IDLE, SCRAMBLED, RUNNING, SOLVED }

const AO5_N := 5
const AO12_N := 12
const INVALID := -1  # 不足条数/空表时 AO 与 best 的返回值

var state: int = State.IDLE
var store_path: String = "user://times.cfg"  # 测试重定向到临时目录,避免污染真实成绩
var clock := Callable()  # 毫秒计时钟注入点(测试假钟);空 = Time.get_ticks_msec

var _start_ticks := 0
var _last_elapsed := 0


## 打乱入口(任何来源):running 中调用即隐式作废旧计时(成绩只可能在 on_solved 入账)。
func enter_scrambled() -> void:
	state = State.SCRAMBLED


## 玩家转层(键盘/拖层)入口:仅 scrambled 态起表;其余态忽略(idle 复原态转层不计)。
func on_player_turn() -> void:
	if state != State.SCRAMBLED:
		return
	_start_ticks = _ticks()
	state = State.RUNNING


## UndoBtn 入口:撤销是修正不是转层,不起表、不打断计时(§15.1)。
func on_undo() -> void:
	pass


## is_solved 为真瞬间由 UI 调用:仅 running 态停表入账;其余态忽略(自由模式本就常为 solved)。
func on_solved() -> void:
	if state != State.RUNNING:
		return
	_last_elapsed = _ticks() - _start_ticks
	state = State.SOLVED
	_store(_last_elapsed)


## 作废当前计时(切模式/restore/reset/退出后由 UI 调用):任何态 → idle,读数归零。
func invalidate() -> void:
	state = State.IDLE


## 计时 running 的查询接口:UI 据此禁 PlayBtn(竞速不播公式,§15.1)。
func is_running() -> bool:
	return state == State.RUNNING


## 大字计时读数:running 实时;solved 冻结在成绩;其余 0(作废即归零)。
func elapsed_msec() -> int:
	if state == State.RUNNING:
		return _ticks() - _start_ticks
	if state == State.SOLVED:
		return _last_elapsed
	return 0


func _ticks() -> int:
	return Time.get_ticks_msec() if clock.is_null() else clock.call()


# ---- 成绩存储与统计(§15.2) ----

## 入账:section=YYYY-MM-DD,key=unix毫秒_序号(同毫秒多条第序号防撞),value=毫秒。
func _store(ms: int) -> void:
	var cf := ConfigFile.new()
	cf.load(store_path)  # 文件不存在视为空表
	var day := Time.get_date_string_from_system()
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var max_seq := -1
	if cf.has_section(day):
		for k in cf.get_section_keys(day):
			var p := str(k).split("_")
			if p.size() == 2 and int(p[0]) == now_ms and int(p[1]) > max_seq:
				max_seq = int(p[1])
	cf.set_value(day, "%d_%d" % [now_ms, max_seq + 1], ms)
	cf.save(store_path)


## 历史读取:{日期 -> 毫秒数组}。key 字符串排序 ≈ 时间升序(同毫秒序号并列,顺序无谓)。
func load_all() -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(store_path)
	var out := {}
	for day in cf.get_sections():
		var arr := []
		var keys := cf.get_section_keys(day)
		keys.sort()
		for k in keys:
			arr.append(int(cf.get_value(day, k)))
		out[day] = arr
	return out


## AO 纯函数:取最近 n 条,排序去最好最差,平均中间 n-2 条;不足 n 条(或 n<3)返回 INVALID。
static func ao(times: Array, n: int) -> float:
	if times.size() < n or n < 3:
		return INVALID
	var s := times.slice(times.size() - n)
	s.sort()
	var sum := 0.0
	for i in range(1, n - 1):
		sum += s[i]
	return sum / float(n - 2)


static func ao5(times: Array) -> float:
	return ao(times, AO5_N)


static func ao12(times: Array) -> float:
	return ao(times, AO12_N)


## 单次最佳;空表返回 INVALID。
static func best(times: Array) -> int:
	var b := INVALID
	for t in times:
		if b == INVALID or t < b:
			b = t
	return b
