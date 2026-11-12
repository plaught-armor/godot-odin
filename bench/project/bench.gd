extends SceneTree

# Prints nanoseconds per call for each binding path, best of ROUNDS runs of N calls.
#   godot --headless --path bench/project -s bench.gd

const N: int = 1_000_000
const ROUNDS: int = 5


# The GDScript side of the `_process` comparison.
class GdTicker extends Node:
	var ticks: int = 0

	func _process(_delta: float) -> void:
		ticks += 1


func _initialize() -> void:
	var b: Bench = Bench.new()
	var u: Variant = b
	_report("GDScript -> Odin, typed, 1 arg", func() -> float: return _typed(b))
	_report("GDScript -> Odin, typed, 3 args", func() -> float: return _typed3(b))
	_report("GDScript -> Odin, untyped, 1 arg", func() -> float: return _untyped(u))
	_report("GDScript -> Odin, untyped, 3 args", func() -> float: return _untyped3(u))
	_report("GDScript loop only (baseline)", func() -> float: return _empty())
	var c: Curve = Curve.new()
	var cu: Variant = c
	_report("GDScript -> engine, typed, 1 arg", func() -> float: return _native(c))
	_report("GDScript -> engine, untyped, 1 arg", func() -> float: return _native_untyped(cu))
	_report("Odin -> engine ptrcall", func() -> float: return b.engine_call_ns(N))
	_report("Odin construct + release", func() -> float: return b.construct_ns(N))
	var xs := PackedInt64Array()
	xs.resize(1000)
	_report("Odin sum PackedInt64Array, get(), per element", func() -> float: return b.packed_get_ns(xs, N / 1000))
	_report("Odin sum PackedInt64Array, packed_read, per element", func() -> float: return b.packed_read_ns(xs, N / 1000))
	_report("Odin build PackedInt64Array, set(), per element", func() -> float: return b.packed_build_ns(false, N / 1000))
	_report("Odin build PackedInt64Array, packed_of, per element", func() -> float: return b.packed_build_ns(true, N / 1000))
	var text := "the quick brown fox jumps over the lazy dog, ".repeat(20)
	_report("Odin scan String, unicode_at(), per char", func() -> float: return b.string_scan_ns(text, false, N / 1000))
	_report("Odin scan String, string_read, per char", func() -> float: return b.string_scan_ns(text, true, N / 1000))
	var words: Array = []
	for i in 1000:
		words.append("word %d" % i)
	_report("Odin read Array of Strings, get(), per element", func() -> float: return b.array_read_ns(words, false, N / 1000))
	_report("Odin read Array of Strings, array_at, per element", func() -> float: return b.array_read_ns(words, true, N / 1000))
	_report("Odin build Array of ints, push_back(), per element", func() -> float: return b.array_build_ns(false, false, N / 1000))
	_report("Odin build Array of ints, array_of, per element", func() -> float: return b.array_build_ns(false, true, N / 1000))
	_report("Odin build Array[int], push_back(), per element", func() -> float: return b.array_build_ns(true, false, N / 1000))
	_report("Odin build Array[int], array_typed_of, per element", func() -> float: return b.array_build_ns(true, true, N / 1000))
	_report("Odin build Dictionary of ints, set(), per entry", func() -> float: return b.dict_build_ns(false, N / 1000))
	_report("Odin build Dictionary of ints, dict_of, per entry", func() -> float: return b.dict_build_ns(true, N / 1000))
	_report("Odin Dictionary get, dictionary_get", func() -> float: return b.dict_get_ns(0, N / 1000))
	_report("Odin Dictionary get, dict_get", func() -> float: return b.dict_get_ns(1, N / 1000))
	_report("Odin Dictionary get, dict_get_into", func() -> float: return b.dict_get_ns(2, N / 1000))
	_report("Odin set Array of ints, set(), per element", func() -> float: return b.array_write_ns(false, false, N / 1000))
	_report("Odin set Array of ints, array_write, per element", func() -> float: return b.array_write_ns(false, true, N / 1000))
	_report("Odin set Array[int], set(), per element", func() -> float: return b.array_write_ns(true, false, N / 1000))
	_report("Odin set Array[int], array_write_typed, per element", func() -> float: return b.array_write_ns(true, true, N / 1000))
	_report("Odin name_of + destroy, short identifier", func() -> float: return b.ident_ns(0, N))
	_report("Odin path_of + destroy, short path", func() -> float: return b.ident_ns(1, N))
	_report("Odin string_of + destroy, short identifier", func() -> float: return b.ident_ns(2, N))
	_report("Odin utf8, short identifier", func() -> float: return b.ident_ns(3, N))
	_report("Odin intern, short identifier", func() -> float: return b.ident_ns(4, N))
	_report("Odin intern_path, short path", func() -> float: return b.ident_ns(5, N))
	_report("Odin intern_text, short identifier", func() -> float: return b.ident_ns(6, N))
	_report("Odin temp_text in an engine-call scope", func() -> float: return b.ident_ns(7, N))
	_report("Odin string_length, short String", func() -> float: return b.ident_ns(8, N))
	_report("engine String ==, short equal Strings", func() -> float: return b.ident_ns(9, N))
	_report("Odin string_equal, short equal Strings", func() -> float: return b.ident_ns(10, N))
	_report("engine String ==, String and its copy", func() -> float: return b.ident_ns(12, N))
	_report("Odin string_equal, String and its copy", func() -> float: return b.ident_ns(13, N))
	_report("engine string_of + String == + destroy, short text", func() -> float: return b.ident_ns(14, N))
	_report("Odin string_equal_text, short equal text", func() -> float: return b.ident_ns(11, N))
	_report("Odin string_begins_with, cached String prefix", func() -> float: return b.ident_ns(15, N))
	_report("Odin string_begins_with_text, Odin text prefix", func() -> float: return b.ident_ns(16, N))
	_report("Odin string_ends_with_text, Odin text suffix", func() -> float: return b.ident_ns(17, N))
	_report("engine String == over 8 names, match last", func() -> float: return b.ident_ns(18, N))
	_report("Odin string_equal_text over 8 names, match last", func() -> float: return b.ident_ns(19, N))
	_report("Odin string_which over 8 names, match last", func() -> float: return b.ident_ns(20, N))
	_report("Odin string_find, cached String in a sentence", func() -> float: return b.ident_ns(21, N))
	_report("Odin string_find_text, Odin text in a sentence", func() -> float: return b.ident_ns(22, N))
	_report("Odin same_name on intern of 8 names, match last", func() -> float: return b.ident_ns(23, N))
	_report("Odin name_which over 8 names, match last", func() -> float: return b.ident_ns(24, N))
	_report("Odin string_rfind, cached String in a sentence", func() -> float: return b.ident_ns(25, N))
	_report("Odin string_rfind_text, Odin text in a sentence", func() -> float: return b.ident_ns(26, N))
	_report("Odin string_findn, cached String in a sentence", func() -> float: return b.ident_ns(27, N))
	_report("Odin string_findn_text, Odin text in a sentence", func() -> float: return b.ident_ns(28, N))
	_report("Odin string_nocasecmp_to, cached String", func() -> float: return b.ident_ns(29, N))
	_report("Odin string_equal_text_nocase, Odin text", func() -> float: return b.ident_ns(30, N))
	_report("Odin string_count, cached String in a sentence", func() -> float: return b.ident_ns(31, N))
	_report("Odin string_count_text, Odin text in a sentence", func() -> float: return b.ident_ns(32, N))
	_report("Odin string_begins_with_text_nocase, Odin text", func() -> float: return b.ident_ns(33, N))
	_report("Generated string_replace, cached Strings in a sentence", func() -> float: return b.ident_ns(34, N))
	_report("Odin string_replace_text, Odin text in a sentence", func() -> float: return b.ident_ns(35, N))
	_report("Generated string_split, cached String on a sentence", func() -> float: return b.ident_ns(36, N))
	_report("Odin string_split_text, Odin text on a sentence", func() -> float: return b.ident_ns(37, N))
	_report("Odin string_split_parts, each part read in place", func() -> float: return b.ident_ns(38, N))
	_report("Generated string_to_int, cached String", func() -> float: return b.ident_ns(39, N))
	_report("Odin runes_to_int, the String read in place", func() -> float: return b.ident_ns(40, N))
	_report("Generated string_to_float, cached String", func() -> float: return b.ident_ns(41, N))
	_report("Odin runes_to_float, the String read in place", func() -> float: return b.ident_ns(42, N))
	_report("Generated string_num_int64, made and destroyed", func() -> float: return b.ident_ns(43, N))
	_report("Odin string_of_int, made and destroyed", func() -> float: return b.ident_ns(44, N))
	_report("Generated string_num, made and destroyed", func() -> float: return b.ident_ns(45, N))
	_report("Odin string_of_float, made and destroyed", func() -> float: return b.ident_ns(46, N))
	_report("GDScript -> Odin, typed, String param", func() -> float: return _string_param(b, false))
	_report("GDScript -> Odin, typed, string param", func() -> float: return _string_param(b, true))
	var table: Dictionary = {}
	for i in 1000:
		table["key %d" % i] = i
	_report("Odin sum Dictionary values, keys() + get(), per entry", func() -> float: return b.dict_iter_ns(table, false, N / 1000))
	_report("Odin sum Dictionary values, dict_items, per entry", func() -> float: return b.dict_iter_ns(table, true, N / 1000))
	_report("Odin fill Image, set_pixel(), per pixel", func() -> float: return b.image_fill_ns(false, N / 4096))
	_report("Odin fill Image, image_write, per pixel", func() -> float: return b.image_fill_ns(true, N / 4096))
	var data := PackedByteArray()
	data.resize(1 << 20)
	var fw: FileAccess = FileAccess.open("user://bench_read.bin", FileAccess.WRITE)
	fw.store_buffer(data)
	fw.close()
	_report("Odin read file, get_buffer(), per 4 KiB", func() -> float: return b.file_read_ns("user://bench_read.bin", false, N / 100000))
	_report("Odin read file, file_read, per 4 KiB", func() -> float: return b.file_read_ns("user://bench_read.bin", true, N / 100000))
	_report("Odin run_task + wait_task, per task", func() -> float: return b.task_ns(N / 1000))
	_report("GDScript add_task + wait, per task (Callable)", func() -> float: return _gd_tasks())
	_report("Odin run_group of 1024 + wait, per call", func() -> float: return b.group_item_ns(N / 10000))
	_report("GDScript add_group_task of 1024 + wait, per call", func() -> float: return _gd_groups())
	var bump: Callable = func(x: int) -> int: return x + 1
	_report("Odin -> Callable.call (GDScript lambda)", func() -> float: return b.callable_call_ns(bump, N))
	_report("GDScript -> Callable.call (same lambda)", func() -> float: return _callable_calls(bump))
	_report("Odin emit, 1 arg, no connections", func() -> float: return b.emit_ns(N))
	_report("GDScript emit (same signal)", func() -> float: return _emits(b))
	_report("GDScript -> Odin field get, typed", func() -> float: return _field_get(b))
	_report("GDScript -> Odin field set, typed", func() -> float: return _field_set(b))
	var timer: Timer = Timer.new()
	_report("GDScript -> engine property get, typed", func() -> float: return _prop_get(timer))
	_report("GDScript -> engine property set, typed", func() -> float: return _prop_set(timer))
	timer.free()
	_report("GDScript Bench.new() + release", func() -> float: return _new_bench())
	_report("GDScript RefCounted.new() + release", func() -> float: return _new_refcounted())
	_report("GDScript -> Callable.call (Odin proc)", func() -> float: return _callable_calls(b.odin_callable()))
	var plain: Node = Node.new()
	var odin: Node = BenchTicker.new()
	var gd: Node = GdTicker.new()
	_report("Node._process, no override (baseline)", func() -> float: return _process_calls(plain))
	_report("Node._process, Odin override", func() -> float: return _process_calls(odin))
	_report("Node._process, GDScript override", func() -> float: return _process_calls(gd))
	plain.free()
	odin.free()
	gd.free()
	quit(0)


func _report(label: String, run: Callable) -> void:
	var best: float = INF
	for i in ROUNDS:
		best = minf(best, run.call())
	print("%-52s %8.2f ns" % [label, best])


func _typed(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.add(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _typed3(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.add3(i, i, i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _untyped(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.add(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _untyped3(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.add3(i, i, i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# An engine method of the same shape (one float in, one float out), for the cost the engine's
# own call machinery adds before any binding runs.
func _native(c: Curve) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		c.sample_baked(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _native_untyped(u: Variant) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		u.sample_baked(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _empty() -> float:
	var t: int = Time.get_ticks_usec()
	var s: int = 0
	for i in N:
		s += i
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# One NOTIFICATION_PROCESS reaches `_process` through the engine's virtual call, as a frame does.
func _process_calls(n: Node) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		n.notification(Node.NOTIFICATION_PROCESS)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _callable_calls(f: Callable) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		f.call(1)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


# Queues one empty task on the pool and waits for it, N / 1000 times.
func _gd_tasks() -> float:
	var f: Callable = func() -> void: pass
	var t: int = Time.get_ticks_usec()
	for i in N / 1000:
		WorkerThreadPool.wait_for_task_completion(WorkerThreadPool.add_task(f))
	return float(Time.get_ticks_usec() - t) * 1000.0 / (N / 1000)


# Queues a 1024-call group of empty calls and waits for it, N / 10000 times.
func _gd_groups() -> float:
	var f: Callable = func(_i: int) -> void: pass
	var t: int = Time.get_ticks_usec()
	for i in N / 10000:
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(f, 1024))
	return float(Time.get_ticks_usec() - t) * 1000.0 / (N / 10000 * 1024)


func _emits(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.ping.emit(i)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _field_get(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	var s: float = 0.0
	for i in N:
		s += b.rate
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _field_set(b: Bench) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		b.rate = 1.5
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _prop_get(timer: Timer) -> float:
	var t: int = Time.get_ticks_usec()
	var s: float = 0.0
	for i in N:
		s += timer.wait_time
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _prop_set(timer: Timer) -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		timer.wait_time = 1.5
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _new_bench() -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		var x: Bench = Bench.new()
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _new_refcounted() -> float:
	var t: int = Time.get_ticks_usec()
	for i in N:
		var x: RefCounted = RefCounted.new()
	return float(Time.get_ticks_usec() - t) * 1000.0 / N


func _string_param(b: Bench, odin_text: bool) -> float:
	var s: String = "player_jump"
	var sum: int = 0
	var t: int = Time.get_ticks_usec()
	if odin_text:
		for i in N:
			sum += b.text_len(s)
	else:
		for i in N:
			sum += b.string_len(s)
	return float(Time.get_ticks_usec() - t) * 1000.0 / N
