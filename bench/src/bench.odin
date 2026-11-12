// Timing loops for the paths the bindings own: engine-to-Odin method calls (driven from bench.gd)
// and Odin-to-engine calls and construction (driven here, so GDScript's own cost stays out).
package bench

import "core:time"
import gde "../../gdextension"
import "../../godot"

@(export, link_name = "bench_init")
bench_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register)
}

// A counter GDScript calls in a loop, typed (ptrcall) and untyped (Variant call).
Bench :: struct {
	total: i64,
	// A float property GDScript reads and writes in a loop.
	rate:  f64,
}

// `Bench.ping(x)`, emitted from Odin with no connections.
ping: ^godot.StringName

// A node whose `_process` override counts calls, for timing the engine's virtual dispatch into Odin.
Ticker :: struct {
	ticks: i64,
}

register :: proc() {
	t := godot.class(Ticker, "BenchTicker", "Node")
	godot.override_node_process(t, tick)
	c := godot.class(Bench, "Bench", "RefCounted")
	godot.fields(c)
	ping = godot.signal(c, "ping", godot.Arg{name = "x", type = .INT})
	godot.method(c, "emit_ns", emit_ns, {"n"})
	godot.method(c, "odin_callable", odin_callable)
	godot.method(c, "add", add, {"x"})
	godot.method(c, "add3", add3, {"a", "b", "c"})
	godot.method(c, "construct_ns", construct_ns, {"n"})
	godot.method(c, "engine_call_ns", engine_call_ns, {"n"})
	godot.method(c, "packed_get_ns", packed_get_ns, {"xs", "n"})
	godot.method(c, "packed_read_ns", packed_read_ns, {"xs", "n"})
	godot.method(c, "packed_build_ns", packed_build_ns, {"fast", "n"})
	godot.method(c, "string_scan_ns", string_scan_ns, {"s", "fast", "n"})
	godot.method(c, "array_read_ns", array_read_ns, {"xs", "fast", "n"})
	godot.method(c, "callable_call_ns", callable_call_ns, {"f", "n"})
}

// Adds `x` to the total and answers the new total.
add :: proc(self: ^Bench, x: i64) -> i64 {
	self.total += x
	return self.total
}

// Adds `a`, `b` and `c` to the total and answers the new total.
add3 :: proc(self: ^Bench, a, b, c: i64) -> i64 {
	self.total += a + b + c
	return self.total
}

// Nanoseconds per `godot.construct` of a RefCounted and its release, over `n` rounds.
construct_ns :: proc(self: ^Bench, n: i64) -> f64 {
	start := time.tick_now()
	for _ in 0 ..< n {
		godot.release(godot.construct(godot.RefCounted))
	}
	return f64(time.tick_since(start)) / f64(n)
}

// Nanoseconds per engine method call by ptrcall (RefCounted.get_reference_count), over `n` rounds.
engine_call_ns :: proc(self: ^Bench, n: i64) -> f64 {
	rc := godot.construct(godot.RefCounted)
	defer godot.release(rc)
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		sum += godot.ref_counted_get_reference_count(rc)
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// Nanoseconds per element to sum `xs` with `packed_int64_array_get`, over `n` rounds.
packed_get_ns :: proc(self: ^Bench, xs: godot.PackedInt64Array, n: i64) -> f64 {
	xs := xs
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		for i in 0 ..< godot.packed_int64_array_size(&xs) { sum += godot.packed_int64_array_get(&xs, i) }
	}
	ns := f64(time.tick_since(start)) / f64(n * godot.packed_int64_array_size(&xs))
	self.total += sum
	return ns
}

// Nanoseconds per element to sum `xs` through `packed_read`, over `n` rounds.
packed_read_ns :: proc(self: ^Bench, xs: godot.PackedInt64Array, n: i64) -> f64 {
	xs := xs
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		for x in godot.packed_read(&xs) { sum += x }
	}
	ns := f64(time.tick_since(start)) / f64(n * godot.packed_int64_array_size(&xs))
	self.total += sum
	return ns
}

// Nanoseconds per element to build a 1000-element PackedInt64Array: from a slice with `packed_of`
// when `fast`, else by `resize` and one `set` per element. Over `n` rounds.
packed_build_ns :: proc(self: ^Bench, fast: bool, n: i64) -> f64 {
	src: [1000]i64
	for &x, i in src { x = i64(i) }
	start := time.tick_now()
	for _ in 0 ..< n {
		out: godot.PackedInt64Array
		if fast {
			out = godot.packed_of(src[:])
		} else {
			out = godot.packed_int64_array_new()
			godot.packed_int64_array_resize(&out, len(src))
			for x, i in src { godot.packed_int64_array_set(&out, i64(i), x) }
		}
		self.total += godot.packed_int64_array_size(&out)
		godot.packed_int64_array_destroy(&out)
	}
	return f64(time.tick_since(start)) / f64(n * len(src))
}

// Nanoseconds per character to sum the code points of `s`: in place with `string_read` when `fast`,
// else by one `unicode_at` per character. Over `n` rounds.
string_scan_ns :: proc(self: ^Bench, s: godot.String, fast: bool, n: i64) -> f64 {
	s := s
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		if fast {
			for c in godot.string_read(&s) { sum += i64(c) }
		} else {
			for i in 0 ..< godot.string_length(&s) { sum += godot.string_unicode_at(&s, i) }
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * godot.string_length(&s))
	self.total += sum
	return ns
}

// Nanoseconds per element to read each element of `xs`: borrowed with `array_at` when `fast`, else
// as a copy from `array_get`, destroyed after. Over `n` rounds.
array_read_ns :: proc(self: ^Bench, xs: godot.Array, fast: bool, n: i64) -> f64 {
	xs := xs
	count := godot.array_size(&xs)
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		for i in 0 ..< count {
			if fast {
				sum += i64(godot.variant_tag(godot.array_at(&xs, i)))
			} else {
				v := godot.array_get(&xs, i)
				sum += i64(godot.variant_tag(&v))
				gde.variant_destroy(&v)
			}
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * count)
	self.total += sum
	return ns
}

// Counts one `_process` call.
tick :: proc(self: ^Ticker, delta: f64) {
	self.ticks += 1
}

// Nanoseconds per Callable.call of `f` with one int argument, over `n` rounds.
callable_call_ns :: proc(self: ^Bench, f: godot.Callable, n: i64) -> f64 {
	f := f
	arg := godot.variant(i64(1))
	start := time.tick_now()
	for _ in 0 ..< n {
		r := godot.callable_call(&f, arg)
		gde.variant_destroy(&r)
	}
	return f64(time.tick_since(start)) / f64(n)
}



// Nanoseconds per `godot.emit` of `ping` with one int argument and no connections, over `n` rounds.
emit_ns :: proc(self: ^Bench, n: i64) -> f64 {
	start := time.tick_now()
	for i in 0 ..< n {
		godot.emit(self, ping, godot.variant(i))
	}
	return f64(time.tick_since(start)) / f64(n)
}

// A Callable of `bump` on this instance, for GDScript to call in a loop.
odin_callable :: proc(self: ^Bench) -> godot.Callable {
	return godot.callable(self, bump)
}

// Adds `x` to the total.
bump :: proc(self: ^Bench, x: i64) {
	self.total += x
}
