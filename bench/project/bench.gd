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
	var bump: Callable = func(x: int) -> int: return x + 1
	_report("Odin -> Callable.call (GDScript lambda)", func() -> float: return b.callable_call_ns(bump, N))
	_report("GDScript -> Callable.call (same lambda)", func() -> float: return _callable_calls(bump))
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
	print("%-40s %8.1f ns" % [label, best])


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
