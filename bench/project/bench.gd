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
