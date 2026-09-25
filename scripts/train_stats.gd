extends RefCounted
## 训练每案例统计(A-8):按 case id 聚合出现次数/best/mean,ConfigFile 持久化。
## 参照 timer.gd times.cfg 模式:纯逻辑无 UI;store_path 可注入(测试重定向临时目录)。
## case id 由调用方构造(main.gd = 训练分类 + case 名,跨分类同名防串)。

var store_path: String = "user://train_stats.cfg"  # 测试重定向到临时目录,避免污染真实数据
var clock := Callable()  # 毫秒时钟注入点(测试假钟,同 timer.gd 口径);空 = 系统真实时间


## 入账:key=unix毫秒_序号(同毫秒多条第序号防撞,同 timer.gd 口径),value=毫秒。
func record(case_id: String, elapsed_ms: int) -> void:
	if case_id.is_empty():
		return
	var cf := ConfigFile.new()
	cf.load(store_path)  # 文件不存在视为空表
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0) if clock.is_null() \
			else int(clock.call())
	var max_seq := -1
	if cf.has_section(case_id):
		for k in cf.get_section_keys(case_id):
			var p := str(k).split("_")
			if p.size() == 2 and int(p[0]) == now_ms and int(p[1]) > max_seq:
				max_seq = int(p[1])
	cf.set_value(case_id, "%d_%d" % [now_ms, max_seq + 1], elapsed_ms)
	cf.save(store_path)


## 聚合:{"count": int, "best_ms": int, "mean_ms": float};无记录 best/mean 为 -1/-1.0。
func stats(case_id: String) -> Dictionary:
	var cf := ConfigFile.new()
	cf.load(store_path)
	var times := []
	if cf.has_section(case_id):
		for k in cf.get_section_keys(case_id):
			times.append(int(cf.get_value(case_id, k)))
	var out := {"count": times.size(), "best_ms": -1, "mean_ms": -1.0}
	if times.is_empty():
		return out
	var sum := 0
	for t in times:
		sum += t
	out.best_ms = times.min()
	out.mean_ms = sum / float(times.size())
	return out
