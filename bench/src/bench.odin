// Timing loops for the paths the bindings own: engine-to-Odin method calls (driven from bench.gd)
// and Odin-to-engine calls and construction (driven here, so GDScript's own cost stays out).
package bench

import "core:mem"
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
	godot.method(c, "array_build_ns", array_build_ns, {"typed", "fast", "n"})
	godot.method(c, "array_write_ns", array_write_ns, {"typed", "fast", "n"})
	godot.method(c, "dict_iter_ns", dict_iter_ns, {"d", "fast", "n"})
	godot.method(c, "dict_build_ns", dict_build_ns, {"fast", "n"})
	godot.method(c, "image_fill_ns", image_fill_ns, {"fast", "n"})
	godot.method(c, "file_read_ns", file_read_ns, {"path", "fast", "n"})
	godot.method(c, "task_ns", task_ns, {"n"})
	godot.method(c, "group_item_ns", group_item_ns, {"n"})
	godot.method(c, "callable_call_ns", callable_call_ns, {"f", "n"})
	godot.method(c, "ident_ns", ident_ns, {"kind", "n"})
	godot.method(c, "text_len", text_len, {"s"})
	godot.method(c, "string_len", string_len, {"s"})
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

// Nanoseconds per element to build a 1000-int Array, an Array[int] when `typed`: from a slice with
// Nanoseconds per entry to build a Dictionary of 1000 int keys to int values, `n` times: one
// `set` per entry, or `dict_of`.
dict_build_ns :: proc(self: ^Bench, fast: bool, n: i64) -> f64 {
	keys: [1000]i64
	for &x, i in keys { x = i64(i) }
	start := time.tick_now()
	for _ in 0 ..< n {
		out: godot.Dictionary
		if fast {
			out = godot.dict_of(keys[:], keys[:])
		} else {
			out = godot.dictionary_new()
			for x in keys { godot.dictionary_set(&out, godot.variant(x), godot.variant(x)) }
		}
		self.total += godot.dictionary_size(&out)
		godot.destroy[.DICTIONARY](&out)
	}
	return f64(time.tick_since(start)) / f64(n * len(keys))
}

// `array_of` or `array_typed_of` when `fast`, else by one `push_back` each. Over `n` rounds.
array_build_ns :: proc(self: ^Bench, typed, fast: bool, n: i64) -> f64 {
	src: [1000]i64
	for &x, i in src { x = i64(i) }
	start := time.tick_now()
	for _ in 0 ..< n {
		out: godot.Array
		if fast && typed {
			out = godot.array_typed_of(src[:])
		} else if fast {
			out = godot.array_of(src[:])
		} else {
			out = godot.array_new()
			if typed { type_ints(&out) }
			for x in src { godot.array_push_back(&out, godot.variant(x)) }
		}
		self.total += godot.array_size(&out)
		godot.array_destroy(&out)
	}
	return f64(time.tick_since(start)) / f64(n * len(src))
}

// Nanoseconds per element to overwrite every element of a 1000-int Array, an Array[int] when
// `typed`, with an int: through `array_write` or `array_write_typed` when `fast`, else by one `set`
// each. Over `n` rounds.
array_write_ns :: proc(self: ^Bench, typed, fast: bool, n: i64) -> f64 {
	src: [1000]i64
	a := godot.array_typed_of(src[:]) if typed else godot.array_of(src[:])
	defer godot.array_destroy(&a)
	start := time.tick_now()
	for r in 0 ..< n {
		if fast {
			slots := godot.array_write_typed(&a, i64) if typed else godot.array_write(&a)
			for &v in slots {
				gde.variant_destroy(&v)
				godot.variant_into(&v, r)
			}
		} else {
			for i in 0 ..< i64(len(src)) { godot.array_set(&a, i, godot.variant(r)) }
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * len(src))
	self.total += godot.variant_int(godot.array_at(&a, 0))
	return ns
}

// Types the empty Array `a` to int, as `Array[int]`.
type_ints :: proc "contextless" (a: ^godot.Array) {
	class: godot.StringName
	script: godot.Variant
	gde.array_set_typed(a, .INT, &class, &script)
}

// Nanoseconds per entry to sum the int values of `d`: over `dict_items` read in place when `fast`,
// else by `keys()` and one `get` per key. Over `n` rounds.
dict_iter_ns :: proc(self: ^Bench, d: godot.Dictionary, fast: bool, n: i64) -> f64 {
	d := d
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		if fast {
			keys, values := godot.dict_items(&d)
			for &v in godot.array_read(&values) { sum += godot.variant_int(&v) }
			godot.array_destroy(&keys)
			godot.array_destroy(&values)
		} else {
			keys := godot.dictionary_keys(&d)
			for &k in godot.array_read(&keys) {
				v := godot.dictionary_get(&d, k, {})
				sum += godot.variant_int(&v)
				gde.variant_destroy(&v)
			}
			godot.array_destroy(&keys)
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * godot.dictionary_size(&d))
	self.total += sum
	return ns
}

// Nanoseconds per pixel to fill a 64x64 RGBA8 Image: through `image_write` when `fast`, else by
// one `set_pixel` per pixel. Over `n` rounds.
image_fill_ns :: proc(self: ^Bench, fast: bool, n: i64) -> f64 {
	SIDE :: 64
	img := godot.image_create_empty(SIDE, SIDE, false, .FORMAT_RGBA8)
	defer godot.release(img)
	start := time.tick_now()
	for r in 0 ..< n {
		if fast {
			px := godot.image_write(img)
			for i := 0; i < len(px); i += 4 { px[i], px[i + 1], px[i + 2], px[i + 3] = u8(r), 0, 0, 255 }
		} else {
			c := godot.Color{f32(r & 255) / 255, 0, 0, 1}
			for y in 0 ..< i64(SIDE) {
				for x in 0 ..< i64(SIDE) { godot.image_set_pixel(img, x, y, c) }
			}
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * SIDE * SIDE)
	self.total += godot.image_get_data_size(img)
	return ns
}

// Nanoseconds per 4 KiB chunk to read the file at `path` from start to end: into an Odin buffer with
// `file_read` when `fast`, else as a new PackedByteArray from `get_buffer`, read in place and
// destroyed. Over `n` rounds.
file_read_ns :: proc(self: ^Bench, path: godot.String, fast: bool, n: i64) -> f64 {
	CHUNK :: 4096
	f := godot.file_access_open(path, .READ)
	if f == nil { return -1 }
	defer godot.release(f)
	buf: [CHUNK]u8
	sum, chunks: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		godot.file_access_seek(f, 0)
		for {
			got: int
			if fast {
				got = godot.file_read(f, buf[:])
				sum += i64(buf[0])
			} else {
				b := godot.file_access_get_buffer(f, CHUNK)
				bytes := godot.packed_read(&b)
				got = len(bytes)
				if got > 0 { sum += i64(bytes[0]) }
				godot.packed_byte_array_destroy(&b)
			}
			chunks += 1
			if got < CHUNK { break }
		}
	}
	ns := f64(time.tick_since(start)) / f64(chunks)
	self.total += sum
	return ns
}

// Bumps one counter, as a worker task.
bump_task :: proc(x: ^i64) { x^ += 1 }

// Bumps the counter for index `i`, as one call of a group.
bump_item :: proc(xs: ^[1024]i64, i: int) { xs[i] += 1 }

// Nanoseconds per task to queue one `run_task` and wait for it, `n` times in a row.
task_ns :: proc(self: ^Bench, n: i64) -> f64 {
	x: i64
	start := time.tick_now()
	for _ in 0 ..< n { godot.wait_task(godot.run_task(bump_task, &x)) }
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += x
	return ns
}

// Nanoseconds per call of a 1024-call `run_group`, waited for, over `n` groups.
group_item_ns :: proc(self: ^Bench, n: i64) -> f64 {
	xs: [1024]i64
	start := time.tick_now()
	for _ in 0 ..< n { godot.wait_group(godot.run_group(bump_item, &xs, len(xs))) }
	ns := f64(time.tick_since(start)) / f64(n * len(xs))
	self.total += xs[0]
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

// The identifier and text paths `ident_ns` times.
Ident :: enum i64 {
	NAME_OF,  // name_of + destroy, a StringName from Odin text
	PATH_OF,  // path_of + destroy, a NodePath from Odin text
	STRING_OF, // string_of + destroy, a String from Odin text
	UTF8,      // utf8, a String as Odin text
	INTERN,    // intern, a cached StringName
	INTERN_PATH, // intern_path, a cached NodePath
}

// Nanoseconds per `kind` round on a short identifier, over `n` rounds.
ident_ns :: proc(self: ^Bench, kind: Ident, n: i64) -> f64 {
	text := "player_jump"
	str := godot.string_of(text)
	defer godot.destroy[.STRING](&str)
	buf: [64]u8
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	sum: i64
	start := time.tick_now()
	switch kind {
	case .NAME_OF:
		for _ in 0 ..< n {
			sn := godot.name_of(text)
			sum += i64(sn._opaque[0])
			godot.destroy[.STRING_NAME](&sn)
		}
	case .PATH_OF:
		for _ in 0 ..< n {
			np := godot.path_of("Body/Sprite")
			sum += i64(np._opaque[0])
			godot.destroy[.NODE_PATH](&np)
		}
	case .STRING_OF:
		for _ in 0 ..< n {
			s := godot.string_of(text)
			sum += i64(s._opaque[0])
			godot.destroy[.STRING](&s)
		}
	case .UTF8:
		for _ in 0 ..< n {
			free_all(mem.arena_allocator(&arena))
			sum += i64(len(godot.utf8(str, mem.arena_allocator(&arena))))
		}
	case .INTERN:
		for _ in 0 ..< n {
			sn := godot.intern("player_jump")
			sum += i64(sn._opaque[0])
		}
	case .INTERN_PATH:
		for _ in 0 ..< n {
			np := godot.intern_path("Body/Sprite")
			sum += i64(np._opaque[0])
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The byte length of `s`, taken as Odin text: the cost of a string parameter.
text_len :: proc(self: ^Bench, s: string) -> i64 {
	return i64(len(s))
}

// The length of `s`, taken as an engine String.
string_len :: proc(self: ^Bench, s: godot.String) -> i64 {
	s := s
	return godot.string_length(&s)
}
