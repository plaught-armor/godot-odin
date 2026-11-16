// Timing loops for the paths the bindings own: engine-to-Odin method calls (driven from bench.gd)
// and Odin-to-engine calls and construction (driven here, so GDScript's own cost stays out).
package bench

import "base:intrinsics"
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
	godot.method(c, "odin_callable_plain", odin_callable_plain)
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
	godot.method(c, "dict_get_ns", dict_get_ns, {"kind", "n"})
	godot.method(c, "image_fill_ns", image_fill_ns, {"fast", "n"})
	godot.method(c, "file_read_ns", file_read_ns, {"path", "fast", "n"})
	godot.method(c, "task_ns", task_ns, {"n"})
	godot.method(c, "group_item_ns", group_item_ns, {"n"})
	godot.method(c, "callable_call_ns", callable_call_ns, {"f", "n"})
	godot.method(c, "ident_ns", ident_ns, {"kind", "n"})
	godot.method(c, "vector_ns", vector_ns, {"kind", "n"})
	godot.method(c, "vectori_ns", vectori_ns, {"kind", "n"})
	godot.method(c, "color_ns", color_ns, {"kind", "n"})
	godot.method(c, "basis_ns", basis_ns, {"kind", "n"})
	godot.method(c, "transform_ns", transform_ns, {"kind", "n"})
	godot.method(c, "string_ns", string_ns, {"kind", "n"})
	godot.method(c, "quaternion_ns", quaternion_ns, {"kind", "n"})
	godot.method(c, "plane_ns", plane_ns, {"kind", "n"})
	godot.method(c, "aabb_ns", aabb_ns, {"kind", "n"})
	godot.method(c, "rect2_ns", rect2_ns, {"kind", "n"})
	godot.method(c, "projection_ns", projection_ns, {"kind", "n"})
	godot.method(c, "packed_ns", packed_ns, {"kind", "n"})
	godot.method(c, "array_ns", array_ns, {"kind", "n"})
	godot.method(c, "dict_ns", dict_ns, {"kind", "n"})
	godot.method(c, "replaced_count", replaced_count)
	godot.method(c, "replaced_label", replaced_label, {"index", "engine"})
	godot.method(c, "replaced_ns", replaced_ns, {"index", "engine", "n"})
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
// Nanoseconds per lookup in a Dictionary of 1000 int keys, `n` rounds of 1000: by the generated
// `dictionary_get` (kind 0), `dict_get` (1) or `dict_get_into` (2).
dict_get_ns :: proc(self: ^Bench, kind: i64, n: i64) -> f64 {
	keys: [1000]i64
	for &x, i in keys { x = i64(i) }
	d := godot.dict_of(keys[:], keys[:])
	defer godot.destroy[.DICTIONARY](&d)
	sum: i64
	start := time.tick_now()
	for _ in 0 ..< n {
		for k in keys {
			key := godot.variant(k)
			out: godot.Variant
			switch kind {
			case 0:
				out = godot.dictionary_get(&d, key, {})
			case 1:
				out, _ = godot.dict_get(&d, &key)
			case:
				godot.dict_get_into(&d, &key, &out)
			}
			sum += godot.variant_int(&out)
		}
	}
	ns := f64(time.tick_since(start)) / f64(n * len(keys))
	self.total += sum
	return ns
}

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

// A Callable of `bump_one` on this instance, a proc with no parameters, for GDScript to call in a loop.
odin_callable_plain :: proc(self: ^Bench) -> godot.Callable {
	return godot.callable(self, bump_one)
}

// Adds 1 to the total.
bump_one :: proc(self: ^Bench) {
	self.total += 1
}

// Adds `x` to the total.
bump :: proc(self: ^Bench, x: i64) {
	self.total += x
}

// The Vector3 methods `vector_ns` times: each _CALL row calls the engine's method through its
// builtin method pointer, as the bindings did before godot/vector.odin replaced it, and the row
// after it the in-place proc.
Vector_Op :: enum i64 {
	LENGTH_CALL,     // the engine's Vector3.length
	LENGTH,          // vector3_length
	NORMALIZED_CALL, // the engine's Vector3.normalized
	NORMALIZED,      // vector3_normalized
	DOT_CALL,        // the engine's Vector3.dot
	DOT,             // vector3_dot
	LERP_CALL,       // the engine's Vector3.lerp at weight 0.25
	LERP,            // vector3_lerp at weight 0.25
}

// Nanoseconds per `kind` round on a Vector3 reread through a volatile load each round, so no
// result is hoisted out of the loop, over `n` rounds.
vector_ns :: proc(self: ^Bench, kind: Vector_Op, n: i64) -> f64 {
	v := godot.Vector3{1.5, -2.25, 3}
	to := godot.Vector3{-0.5, 4, 2}
	weight := f64(0.25)
	ref := &v
	length_fn := godot.builtin_method(.VECTOR3, "length", 466405837)
	normalized_fn := godot.builtin_method(.VECTOR3, "normalized", 1776574132)
	dot_fn := godot.builtin_method(.VECTOR3, "dot", 1047977935)
	lerp_fn := godot.builtin_method(.VECTOR3, "lerp", 1682608829)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .LENGTH_CALL:
		for _ in 0 ..< n {
			r: f64
			length_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += f32(r)
		}
	case .LENGTH:
		for _ in 0 ..< n { sum += f32(godot.vector3_length(intrinsics.volatile_load(&ref))) }
	case .NORMALIZED_CALL:
		for _ in 0 ..< n {
			r: godot.Vector3
			normalized_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.x
		}
	case .NORMALIZED:
		for _ in 0 ..< n { sum += godot.vector3_normalized(intrinsics.volatile_load(&ref)).x }
	case .DOT_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&to}
			r: f64
			dot_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(r)
		}
	case .DOT:
		for _ in 0 ..< n { sum += f32(godot.vector3_dot(intrinsics.volatile_load(&ref), to)) }
	case .LERP_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&to, &weight}
			r: godot.Vector3
			lerp_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += r.x
		}
	case .LERP:
		for _ in 0 ..< n { sum += godot.vector3_lerp(intrinsics.volatile_load(&ref), to, weight).x }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The identifier and text paths `ident_ns` times.
Ident :: enum i64 {
	NAME_OF,  // name_of + destroy, a StringName from Odin text
	PATH_OF,  // path_of + destroy, a NodePath from Odin text
	STRING_OF, // string_of + destroy, a String from Odin text
	UTF8,      // utf8, a String as Odin text
	INTERN,    // intern, a cached StringName
	INTERN_PATH, // intern_path, a cached NodePath
	INTERN_TEXT, // intern_text, a cached String
	TEMP_TEXT,   // temp_text in a nested engine-call scope, dropped at its end
	LENGTH,      // string_length of a String, read from its header
	EQUAL_ENGINE, // the engine's String == evaluator, two equal Strings in separate storage
	EQUAL,        // string_equal on the same pair
	EQUAL_TEXT,   // string_equal_text against the same Odin text
	EQUAL_ENGINE_COPY, // the engine's String == on a String and its copy, which share storage
	EQUAL_COPY,        // string_equal on the same pair
	EQUAL_ENGINE_TEXT, // string_of the Odin text, the engine's String ==, destroy
	BEGINS_ENGINE,     // the generated string_begins_with, its prefix a cached String
	BEGINS_TEXT,       // string_begins_with_text, its prefix Odin text
	ENDS_TEXT,         // string_ends_with_text, its suffix Odin text
	WHICH_ENGINE,      // the engine's String == over 8 cached Strings, the match last
	WHICH_LOOP,        // string_equal_text over the same 8 names
	WHICH,             // string_which on a Text_Set of them
	FIND_ENGINE,       // the generated string_find of a cached String in a 43-character sentence
	FIND_TEXT,         // string_find_text of the same Odin text
	NAME_CHAIN,        // same_name against intern of each of the 8 names in turn, the match last
	NAME_WHICH,        // name_which on a Name_Set of them
	RFIND_ENGINE,      // the generated string_rfind of a cached String near the start of the sentence
	RFIND_TEXT,        // string_rfind_text of the same Odin text
	FINDN_ENGINE,      // the generated string_findn of a cached String, in other case, in the sentence
	FINDN_TEXT,        // string_findn_text of the same Odin text
	NOCASE_ENGINE,     // string_nocasecmp_to against a cached String in other case
	EQUAL_NOCASE,      // string_equal_text_nocase of the same Odin text
	COUNT_ENGINE,      // the generated string_count of a cached String in the sentence
	COUNT_TEXT,        // string_count_text of the same Odin text
	BEGINS_NOCASE,     // string_begins_with_text_nocase of "PLAYER_" on the identifier
	REPLACE_ENGINE,    // string_replace of cached Strings in the sentence
	REPLACE_TEXT,      // string_replace_text of the same Odin text
	SPLIT_ENGINE,      // string_split of the sentence on a cached " "
	SPLIT_TEXT,        // string_split_text of the sentence on Odin " "
	SPLIT_PARTS,       // string_split_parts of the same, each part read and none made
	TO_INT_ENGINE,     // the generated string_to_int of a cached "-12345", which reads it in place
	TO_INT_RUNES,      // runes_to_int of the same String's characters
	TO_FLOAT_ENGINE,   // the generated string_to_float of a cached "-123.456e-2", which reads it in place
	TO_FLOAT_RUNES,    // runes_to_float of the same String's characters
	INT_TEXT_ENGINE,   // the engine's String.num_int64 of -1234567, made and destroyed
	INT_TEXT,          // string_of_int of the same number
	FLOAT_TEXT_ENGINE, // the engine's String.num of -123.456 at the default places
	FLOAT_TEXT,        // string_of_float of the same number
	FIND_CALL,         // the engine's String.find, called as the bindings did before string_find replaced it
	RFIND_CALL,        // the engine's String.rfind the same way
	FINDN_CALL,        // the engine's String.findn the same way
	NOCASE_CALL,       // the engine's String.nocasecmp_to the same way
	REPLACE_CALL,      // the engine's String.replace the same way
	SPLIT_CALL,        // the engine's String.split the same way
	NAME_LENGTH_CALL,  // the engine's StringName.length on the identifier, called as the bindings did before
	NAME_LENGTH,       // the generated string_name_length, read from the interned name
	NAME_HASH_CALL,    // the engine's StringName.hash the same way
	NAME_HASH,         // the generated string_name_hash, read from the interned name
	NAME_FIND_CALL,    // the engine's StringName.find of a cached String in the sentence as a StringName
	NAME_FIND,         // the generated string_name_find of the same
	TO_INT_CALL,       // the engine's String.to_int of "-12345", called as the bindings did before
	TO_FLOAT_CALL,     // the engine's String.to_float of "-123.456e-2" the same way
	VALID_FLOAT_CALL,  // the engine's String.is_valid_float of "-123.456e-2" the same way
	VALID_FLOAT,       // the generated string_is_valid_float of the same, which reads it in place
	PATH_COUNT_CALL,   // the engine's NodePath.get_name_count of "Body/Sprite:position", called as the bindings did before
	PATH_COUNT,        // the generated node_path_get_name_count of the same, read from its data
	PATH_HASH_CALL,    // the engine's NodePath.hash of the same, its cache filled, the same way
	PATH_HASH,         // the generated node_path_hash of the same, read from its data
	PATH_NAME_CALL,    // the engine's NodePath.get_name(1) of the same, the StringName destroyed, the same way
	PATH_NAME,         // the generated node_path_get_name(1), copied from its data
	NAME_GET_CALL,     // the engine's Array.get(0) of a one-StringName Array, the Variant destroyed, called as the bindings did before
	NAME_GET,          // the generated array_get(0) of the same, the StringName copied in place
	NAME_COPY_CALL,    // the engine's StringName copy constructor, string_name_new_from_string_name, the copy destroyed
	NAME_COPY,         // name_copy of the same StringName
	STRING_GET_CALL,   // the engine's Array.get(0) of a one-String Array, the Variant destroyed, called as the bindings did before
	STRING_GET,        // the generated array_get(0) of the same, the String copied in place
	STRING_COPY_CALL,  // the engine's String copy constructor, string_new_from_string, the copy destroyed
	STRING_COPY,       // string_copy of the same String
	NAME_VARIANT_CALL, // the engine's STRING_NAME Variant constructor, from_type, the Variant destroyed
	NAME_VARIANT,      // variant() of the same StringName, its reference taken in place
	STRING_VARIANT_CALL, // the engine's STRING Variant constructor, from_type, the Variant destroyed
	STRING_VARIANT,    // variant() of the same String, its reference taken in place
	TEXT_VARIANT_CALL, // an Odin string made a String and then a STRING Variant, as variant() did before
	TEXT_VARIANT,      // variant() of the same Odin string, its new String moved into the Variant
	DECODE_U32_CALL,   // the engine's PackedByteArray.decode_u32(4) of 16 bytes, called as the bindings did before
	DECODE_U32,        // the generated packed_byte_array_decode_u32 of the same, read from its storage
	DECODE_HALF_CALL,  // the engine's PackedByteArray.decode_half(4) of the same, the same way
	DECODE_HALF,       // the generated packed_byte_array_decode_half of the same
	UNICODE_AT_CALL,   // the engine's String.unicode_at(3) of "7fffABCD1234", the same way
	UNICODE_AT,        // the generated string_unicode_at of the same
	HEX_INT_CALL,      // the engine's String.hex_to_int of the same, the same way
	HEX_INT,           // the generated string_hex_to_int of the same, parsed in place
	STRING_HASH_CALL,  // the engine's String.hash of the same, the same way
	STRING_HASH,       // the generated string_hash of the same
	FILENAME_CALL,     // the engine's String.is_valid_filename of the same, the same way
	FILENAME,          // the generated string_is_valid_filename of the same
	ARRAY_TYPED_CALL,  // the engine's Array.is_typed of an empty Array, the same way
	ARRAY_TYPED,       // the generated array_is_typed of the same, read from its data
	HTML_COLOR_CALL,   // the engine's String.is_valid_html_color of "#7fffABCD", the same way
	HTML_COLOR,        // the generated string_is_valid_html_color of the same
	IP_ADDRESS_CALL,   // the engine's String.is_valid_ip_address of "2001:db8:85a3::8a2e:370:7334", the same way
	IP_ADDRESS,        // the generated string_is_valid_ip_address of the same
	ARRAY_SAME_CALL,   // the engine's Array.is_same_typed of two empty Arrays, the same way
	ARRAY_SAME,        // the generated array_is_same_typed of the same, read from their data
	DICT_SAME_CALL,    // the engine's Dictionary.is_same_typed of two empty Dictionaries, the same way
	DICT_SAME,         // the generated dictionary_is_same_typed of the same, read from their data
	CALLABLE_NULL_CALL, // the engine's Callable.is_null of a Callable naming a method, the same way
	CALLABLE_NULL,      // the generated callable_is_null of the same, read from its two words
	CALLABLE_ID_CALL,   // the engine's Callable.get_object_id of the same
	CALLABLE_ID,        // the generated callable_get_object_id of the same
	SIGNAL_NULL_CALL,   // the engine's Signal.is_null of a Signal naming a signal of an object
	SIGNAL_NULL,        // the generated signal_is_null of the same
	PACKED_SET_CALL,    // the engine's PackedInt64Array.set at index 4 of 16, the storage not shared
	PACKED_SET,         // the generated packed_int64_array_set of the same, stored in place
	PACKED_SET_V3_CALL, // the engine's PackedVector3Array.set the same way
	PACKED_SET_V3,      // the generated packed_vector3_array_set of the same
	ENCODE_U32_CALL,    // the engine's PackedByteArray.encode_u32 at offset 4 of 16 bytes, the storage not shared
	ENCODE_U32,         // the generated packed_byte_array_encode_u32 of the same, stored in place
	ENCODE_HALF_CALL,   // the engine's PackedByteArray.encode_half the same way
	ENCODE_HALF,        // the generated packed_byte_array_encode_half of the same
	BSWAP32_CALL,       // the engine's PackedByteArray.bswap32 of 2 values at offset 4 of 16 bytes, the storage not shared
	BSWAP32,            // the generated packed_byte_array_bswap32 of the same, swapped in place
	BSWAP16_LONG_CALL,  // the engine's PackedByteArray.bswap16 of all 4096 bytes, the storage not shared
	BSWAP16_LONG,       // the generated packed_byte_array_bswap16 of the same
	SLICE_COUNT_CALL,   // the engine's String.get_slice_count of "/" in "res://scenes/level_01.tscn"
	SLICE_COUNT,        // string_get_slice_count of the same
	MATCH_CALL,         // the engine's String.match of that path with "res://*level_??.tscn"
	MATCH,              // string_match of the same
	MATCHN_CALL,        // the engine's String.matchn of that path with "RES://*LEVEL_??.TSCN"
	MATCHN,             // string_matchn of the same
	SUBSEQ_CALL,        // the engine's String.is_subsequence_of of "lvl01" in that path
	SUBSEQ,             // string_is_subsequence_of of the same
	SUBSEQN_CALL,       // the engine's String.is_subsequence_ofn of "LVL01" in that path
	SUBSEQN,            // string_is_subsequence_ofn of the same
	PACKED_FILL_CALL,   // the engine's PackedInt64Array.fill of 16, the storage not shared
	PACKED_FILL,        // the generated packed_int64_array_fill of the same, stored in place
	PACKED_REVERSE_CALL, // the engine's PackedInt64Array.reverse of 16
	PACKED_REVERSE,     // the generated packed_int64_array_reverse of the same
	BYTES_FILL_CALL,    // the engine's PackedByteArray.fill of 256
	BYTES_FILL,         // the generated packed_byte_array_fill of the same
}

// Action names for the `string_which` rows, the bench's identifier last, others of its length and
// first character among them.
WHICH_NAMES :: [8]string{"player_jum", "player_run", "player_walk", "player_dash", "pause", "player_crouch", "player_jumq", "player_jump"}

// The NodePath the path rows read.
BENCH_PATH :: "Body/Sprite:position"

// The text the find rows search, for "lazy" near its end.
FIND_HAY :: "the quick brown fox jumps over the lazy dog"

// `n` calls of the engine's String method `method`, taking a String and a from and giving an int,
// through its builtin method pointer as the bindings called it before replacing it: on FIND_HAY,
// for `what` from `from`.
call_find_method :: proc(method: cstring, $what: string, from: i64, n: i64) -> (sum: i64) {
	hay := godot.string_of(FIND_HAY)
	defer godot.destroy[.STRING](&hay)
	h := &hay
	needle := godot.intern_text(what)
	fn := godot.builtin_method(.STRING, method, 1760645412)
	from := from
	for _ in 0 ..< n {
		args := [2]gde.ConstTypePtr{&needle, &from}
		r: i64
		fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
		sum += r
	}
	return
}

// Nanoseconds per `kind` round on a short identifier, over `n` rounds.
ident_ns :: proc(self: ^Bench, kind: Ident, n: i64) -> f64 {
	text := "player_jump"
	str := godot.string_of(text)
	defer godot.destroy[.STRING](&str)
	// Read through a volatile load each round, so the compare is not hoisted out of the loop.
	ref := &str
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
	case .INTERN_TEXT:
		for _ in 0 ..< n {
			t := godot.intern_text("player_jump")
			sum += i64(t._opaque[0])
		}
	case .TEMP_TEXT:
		for _ in 0 ..< n {
			godot.enter()
			t := godot.temp_text(text)
			sum += i64(t._opaque[0])
		}
	case .LENGTH:
		t := godot.intern_text("player_jump")
		for _ in 0 ..< n {
			sum += godot.string_length(&t)
		}
	case .EQUAL_ENGINE:
		eq := gde.variant_get_ptr_operator_evaluator(.EQUAL, .STRING, .STRING)
		other := godot.string_of(text)
		defer godot.destroy[.STRING](&other)
		for _ in 0 ..< n {
			r: u8
			eq(intrinsics.volatile_load(&ref), &other, &r)
			sum += i64(r)
		}
	case .EQUAL:
		other := godot.string_of(text)
		defer godot.destroy[.STRING](&other)
		for _ in 0 ..< n {
			sum += i64(godot.string_equal(intrinsics.volatile_load(&ref), &other))
		}
	case .EQUAL_TEXT:
		for _ in 0 ..< n {
			sum += i64(godot.string_equal_text(intrinsics.volatile_load(&ref), text))
		}
	case .EQUAL_ENGINE_COPY:
		eq := gde.variant_get_ptr_operator_evaluator(.EQUAL, .STRING, .STRING)
		copied := godot.string_new_from_string(str)
		defer godot.destroy[.STRING](&copied)
		for _ in 0 ..< n {
			r: u8
			eq(intrinsics.volatile_load(&ref), &copied, &r)
			sum += i64(r)
		}
	case .EQUAL_COPY:
		copied := godot.string_new_from_string(str)
		defer godot.destroy[.STRING](&copied)
		for _ in 0 ..< n {
			sum += i64(godot.string_equal(intrinsics.volatile_load(&ref), &copied))
		}
	case .EQUAL_ENGINE_TEXT:
		eq := gde.variant_get_ptr_operator_evaluator(.EQUAL, .STRING, .STRING)
		for _ in 0 ..< n {
			other := godot.string_of(text)
			r: u8
			eq(intrinsics.volatile_load(&ref), &other, &r)
			sum += i64(r)
			godot.destroy[.STRING](&other)
		}
	case .BEGINS_ENGINE:
		prefix := godot.intern_text("player_")
		for _ in 0 ..< n {
			sum += i64(godot.string_begins_with(intrinsics.volatile_load(&ref), prefix))
		}
	case .BEGINS_TEXT:
		for _ in 0 ..< n {
			sum += i64(godot.string_begins_with_text(intrinsics.volatile_load(&ref), "player_"))
		}
	case .ENDS_TEXT:
		for _ in 0 ..< n {
			sum += i64(godot.string_ends_with_text(intrinsics.volatile_load(&ref), "_jump"))
		}
	case .WHICH_ENGINE:
		eq := gde.variant_get_ptr_operator_evaluator(.EQUAL, .STRING, .STRING)
		cached: [len(WHICH_NAMES)]godot.String
		for name, i in WHICH_NAMES { cached[i] = godot.string_of(name) }
		defer for &c in cached { godot.destroy[.STRING](&c) }
		for _ in 0 ..< n {
			r := intrinsics.volatile_load(&ref)
			for &c, i in cached {
				hit: u8
				eq(r, &c, &hit)
				if hit != 0 { sum += i64(i); break }
			}
		}
	case .WHICH_LOOP:
		for _ in 0 ..< n {
			r := intrinsics.volatile_load(&ref)
			for name, i in WHICH_NAMES {
				if godot.string_equal_text(r, name) { sum += i64(i); break }
			}
		}
	case .WHICH:
		set := godot.text_set(WHICH_NAMES)
		for _ in 0 ..< n {
			sum += i64(godot.string_which(intrinsics.volatile_load(&ref), &set))
		}
	case .FIND_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		needle := godot.intern_text("lazy")
		for _ in 0 ..< n {
			sum += godot.string_find(intrinsics.volatile_load(&h), needle, 0)
		}
	case .FIND_CALL:
		sum += call_find_method("find", "lazy", 0, n)
	case .NAME_LENGTH_CALL, .NAME_HASH_CALL:
		name := godot.name_of(text)
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		fn := godot.builtin_method(.STRING_NAME, "length" if kind == .NAME_LENGTH_CALL else "hash", 3173160232)
		for _ in 0 ..< n {
			v: i64
			fn(intrinsics.volatile_load(&r), nil, &v, 0)
			sum += v
		}
	case .NAME_LENGTH:
		name := godot.name_of(text)
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		for _ in 0 ..< n { sum += godot.string_name_length(intrinsics.volatile_load(&r)) }
	case .NAME_HASH:
		name := godot.name_of(text)
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		for _ in 0 ..< n { sum += godot.string_name_hash(intrinsics.volatile_load(&r)) }
	case .NAME_FIND_CALL:
		hay := godot.name_of(FIND_HAY)
		defer godot.destroy[.STRING_NAME](&hay)
		h := &hay
		needle := godot.intern_text("lazy")
		fn := godot.builtin_method(.STRING_NAME, "find", 1760645412)
		from := i64(0)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&needle, &from}
			r: i64
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += r
		}
	case .NAME_FIND:
		hay := godot.name_of(FIND_HAY)
		defer godot.destroy[.STRING_NAME](&hay)
		h := &hay
		needle := godot.intern_text("lazy")
		for _ in 0 ..< n {
			sum += godot.string_name_find(intrinsics.volatile_load(&h), needle, 0)
		}
	case .RFIND_CALL:
		sum += call_find_method("rfind", "quick", -1, n)
	case .FINDN_CALL:
		sum += call_find_method("findn", "LAZY", 0, n)
	case .NOCASE_CALL:
		other := godot.intern_text("PLAYER_JUMP")
		fn := godot.builtin_method(.STRING, "nocasecmp_to", 2920860731)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&other}
			r: i64
			fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r
		}
	case .REPLACE_CALL:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		what, with := godot.string_of("the"), godot.string_of("a")
		defer godot.destroy[.STRING](&what)
		defer godot.destroy[.STRING](&with)
		fn := godot.builtin_method(.STRING, "replace", 1340436205)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&what, &with}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SPLIT_CALL:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		space := godot.string_of(" ")
		defer godot.destroy[.STRING](&space)
		allow_empty, maxsplit := u8(1), i64(0)
		fn := godot.builtin_method(.STRING, "split", 1252735785)
		for _ in 0 ..< n {
			args := [3]gde.ConstTypePtr{&space, &allow_empty, &maxsplit}
			r: godot.PackedStringArray
			fn(intrinsics.volatile_load(&h), &args[0], &r, 3)
			sum += godot.packed_string_array_size(&r)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .FIND_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			sum += godot.string_find_text(intrinsics.volatile_load(&h), "lazy")
		}
	case .RFIND_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		needle := godot.intern_text("quick")
		for _ in 0 ..< n {
			sum += godot.string_rfind(intrinsics.volatile_load(&h), needle, -1)
		}
	case .RFIND_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			sum += godot.string_rfind_text(intrinsics.volatile_load(&h), "quick")
		}
	case .FINDN_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		needle := godot.intern_text("LAZY")
		for _ in 0 ..< n {
			sum += godot.string_findn(intrinsics.volatile_load(&h), needle, 0)
		}
	case .FINDN_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			sum += godot.string_findn_text(intrinsics.volatile_load(&h), "LAZY")
		}
	case .NOCASE_ENGINE:
		other := godot.intern_text("PLAYER_JUMP")
		for _ in 0 ..< n {
			sum += godot.string_nocasecmp_to(intrinsics.volatile_load(&ref), other)
		}
	case .EQUAL_NOCASE:
		for _ in 0 ..< n {
			sum += i64(godot.string_equal_text_nocase(intrinsics.volatile_load(&ref), "PLAYER_JUMP"))
		}
	case .COUNT_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		needle := godot.intern_text("the")
		for _ in 0 ..< n {
			sum += godot.string_count(intrinsics.volatile_load(&h), needle, 0, 0)
		}
	case .COUNT_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			sum += godot.string_count_text(intrinsics.volatile_load(&h), "the")
		}
	case .BEGINS_NOCASE:
		for _ in 0 ..< n {
			sum += i64(godot.string_begins_with_text_nocase(intrinsics.volatile_load(&ref), "PLAYER_"))
		}
	case .REPLACE_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		what, with := godot.string_of("the"), godot.string_of("a")
		defer godot.destroy[.STRING](&what)
		defer godot.destroy[.STRING](&with)
		for _ in 0 ..< n {
			r := godot.string_replace(intrinsics.volatile_load(&h), what, with)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .REPLACE_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			r := godot.string_replace_text(intrinsics.volatile_load(&h), "the", "a")
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SPLIT_ENGINE:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		space := godot.string_of(" ")
		defer godot.destroy[.STRING](&space)
		for _ in 0 ..< n {
			r := godot.string_split(intrinsics.volatile_load(&h), space, true, 0)
			sum += godot.packed_string_array_size(&r)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .SPLIT_TEXT:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			r := godot.string_split_text(intrinsics.volatile_load(&h), " ")
			sum += godot.packed_string_array_size(&r)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .SPLIT_PARTS:
		hay := godot.string_of(FIND_HAY)
		defer godot.destroy[.STRING](&hay)
		h := &hay
		for _ in 0 ..< n {
			parts := godot.string_split_parts(intrinsics.volatile_load(&h), " ")
			for p in godot.split_next(&parts) { sum += i64(len(p)) }
		}
	case .TO_INT_ENGINE:
		num := godot.string_of("-12345")
		defer godot.destroy[.STRING](&num)
		p := &num
		for _ in 0 ..< n { sum += godot.string_to_int(intrinsics.volatile_load(&p)) }
	case .TO_INT_CALL:
		num := godot.string_of("-12345")
		defer godot.destroy[.STRING](&num)
		p := &num
		fn := godot.builtin_method(.STRING, "to_int", 3173160232)
		for _ in 0 ..< n {
			v: i64
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += v
		}
	case .TO_FLOAT_CALL:
		num := godot.string_of("-123.456e-2")
		defer godot.destroy[.STRING](&num)
		p := &num
		fn := godot.builtin_method(.STRING, "to_float", 466405837)
		for _ in 0 ..< n {
			v: f64
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += i64(v)
		}
	case .PATH_COUNT_CALL, .PATH_HASH_CALL:
		path := godot.path_of(BENCH_PATH)
		defer godot.destroy[.NODE_PATH](&path)
		r := &path
		fn := godot.builtin_method(.NODE_PATH, "get_name_count" if kind == .PATH_COUNT_CALL else "hash", 3173160232)
		for _ in 0 ..< n {
			v: i64
			fn(intrinsics.volatile_load(&r), nil, &v, 0)
			sum += v
		}
	case .PATH_COUNT:
		path := godot.path_of(BENCH_PATH)
		defer godot.destroy[.NODE_PATH](&path)
		r := &path
		for _ in 0 ..< n { sum += godot.node_path_get_name_count(intrinsics.volatile_load(&r)) }
	case .PATH_HASH:
		path := godot.path_of(BENCH_PATH)
		defer godot.destroy[.NODE_PATH](&path)
		r := &path
		godot.node_path_hash(r)
		for _ in 0 ..< n { sum += godot.node_path_hash(intrinsics.volatile_load(&r)) }
	case .PATH_NAME_CALL:
		path := godot.path_of(BENCH_PATH)
		defer godot.destroy[.NODE_PATH](&path)
		r := &path
		fn := godot.builtin_method(.NODE_PATH, "get_name", 2948586938)
		idx := i64(1)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&idx}
			v: godot.StringName
			fn(intrinsics.volatile_load(&r), &args[0], &v, 1)
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING_NAME](&v)
		}
	case .PATH_NAME:
		path := godot.path_of(BENCH_PATH)
		defer godot.destroy[.NODE_PATH](&path)
		r := &path
		for _ in 0 ..< n {
			v := godot.node_path_get_name(intrinsics.volatile_load(&r), 1)
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING_NAME](&v)
		}
	case .NAME_GET_CALL, .NAME_GET, .STRING_GET_CALL, .STRING_GET:
		a := godot.array_new()
		defer godot.destroy[.ARRAY](&a)
		nv: godot.Variant
		if kind == .NAME_GET_CALL || kind == .NAME_GET {
			name := godot.name_of("player_jump")
			nv = godot.variant(name)
			godot.destroy[.STRING_NAME](&name)
		} else {
			text := godot.string_of("player_jump")
			nv = godot.variant(text)
			godot.destroy[.STRING](&text)
		}
		godot.array_push_back(&a, nv)
		gde.variant_destroy(&nv)
		r := &a
		fn := godot.builtin_method(.ARRAY, "get", 708700221)
		idx := i64(0)
		for _ in 0 ..< n {
			v: godot.Variant
			if kind == .NAME_GET_CALL || kind == .STRING_GET_CALL {
				args := [1]gde.ConstTypePtr{&idx}
				fn(intrinsics.volatile_load(&r), &args[0], &v, 1)
			} else {
				v = godot.array_get(intrinsics.volatile_load(&r), idx)
			}
			sum += i64(v._opaque[8] & 1)
			gde.variant_destroy(&v)
		}
	case .NAME_COPY_CALL:
		name := godot.name_of("player_jump")
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		for _ in 0 ..< n {
			v := godot.string_name_new_from_string_name(intrinsics.volatile_load(&r)^)
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING_NAME](&v)
		}
	case .NAME_COPY:
		name := godot.name_of("player_jump")
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		for _ in 0 ..< n {
			v := godot.name_copy(intrinsics.volatile_load(&r))
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING_NAME](&v)
		}
	case .STRING_COPY_CALL:
		text := godot.string_of("player_jump")
		defer godot.destroy[.STRING](&text)
		r := &text
		for _ in 0 ..< n {
			v := godot.string_new_from_string(intrinsics.volatile_load(&r)^)
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING](&v)
		}
	case .NAME_VARIANT_CALL, .NAME_VARIANT:
		name := godot.name_of("player_jump")
		defer godot.destroy[.STRING_NAME](&name)
		r := &name
		for _ in 0 ..< n {
			v: godot.Variant
			if kind == .NAME_VARIANT_CALL {
				godot.from_type[.STRING_NAME](&v, intrinsics.volatile_load(&r))
			} else {
				v = godot.variant(intrinsics.volatile_load(&r)^)
			}
			sum += i64(v._opaque[8] & 1)
			gde.variant_destroy(&v)
		}
	case .STRING_VARIANT_CALL, .STRING_VARIANT:
		text := godot.string_of("player_jump")
		defer godot.destroy[.STRING](&text)
		r := &text
		for _ in 0 ..< n {
			v: godot.Variant
			if kind == .STRING_VARIANT_CALL {
				godot.from_type[.STRING](&v, intrinsics.volatile_load(&r))
			} else {
				v = godot.variant(intrinsics.volatile_load(&r)^)
			}
			sum += i64(v._opaque[8] & 1)
			gde.variant_destroy(&v)
		}
	case .TEXT_VARIANT_CALL, .TEXT_VARIANT:
		text := "player_jump"
		r := &text
		for _ in 0 ..< n {
			v: godot.Variant
			if kind == .TEXT_VARIANT_CALL {
				s := godot.string_of(intrinsics.volatile_load(&r)^)
				godot.from_type[.STRING](&v, &s)
				godot.destroy[.STRING](&s)
			} else {
				v = godot.variant(intrinsics.volatile_load(&r)^)
			}
			sum += i64(v._opaque[8] & 1)
			gde.variant_destroy(&v)
		}
	case .STRING_COPY:
		text := godot.string_of("player_jump")
		defer godot.destroy[.STRING](&text)
		r := &text
		for _ in 0 ..< n {
			v := godot.string_copy(intrinsics.volatile_load(&r))
			sum += i64(uintptr((^rawptr)(&v)^) & 1)
			godot.destroy[.STRING](&v)
		}
	case .DECODE_U32_CALL, .DECODE_HALF_CALL:
		bytes := godot.packed_byte_array_new()
		defer godot.destroy[.PACKED_BYTE_ARRAY](&bytes)
		for k in 0 ..< 16 { godot.packed_byte_array_append(&bytes, i64(k * 17)) }
		p := &bytes
		at := i64(4)
		args := [1]gde.ConstTypePtr{&at}
		if kind == .DECODE_U32_CALL {
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, "decode_u32", 4103005248)
			for _ in 0 ..< n {
				v: i64
				fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
				sum += v
			}
		} else {
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, "decode_half", 1401583798)
			for _ in 0 ..< n {
				v: f64
				fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
				sum += i64(v)
			}
		}
	case .DECODE_U32, .DECODE_HALF:
		bytes := godot.packed_byte_array_new()
		defer godot.destroy[.PACKED_BYTE_ARRAY](&bytes)
		for k in 0 ..< 16 { godot.packed_byte_array_append(&bytes, i64(k * 17)) }
		p := &bytes
		if kind == .DECODE_U32 {
			for _ in 0 ..< n { sum += godot.packed_byte_array_decode_u32(intrinsics.volatile_load(&p), 4) }
		} else {
			for _ in 0 ..< n { sum += i64(godot.packed_byte_array_decode_half(intrinsics.volatile_load(&p), 4)) }
		}
	case .UNICODE_AT_CALL, .HEX_INT_CALL, .STRING_HASH_CALL:
		text := godot.string_of("7fffABCD1234")
		defer godot.destroy[.STRING](&text)
		p := &text
		at := i64(3)
		args := [1]gde.ConstTypePtr{&at}
		if kind == .UNICODE_AT_CALL {
			fn := godot.builtin_method(.STRING, "unicode_at", 4103005248)
			for _ in 0 ..< n {
				v: i64
				fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
				sum += v
			}
		} else {
			fn := godot.builtin_method(.STRING, "hex_to_int" if kind == .HEX_INT_CALL else "hash", 3173160232)
			for _ in 0 ..< n {
				v: i64
				fn(intrinsics.volatile_load(&p), nil, &v, 0)
				sum += v
			}
		}
	case .UNICODE_AT, .HEX_INT, .STRING_HASH:
		text := godot.string_of("7fffABCD1234")
		defer godot.destroy[.STRING](&text)
		p := &text
		#partial switch kind {
		case .UNICODE_AT:
			for _ in 0 ..< n { sum += godot.string_unicode_at(intrinsics.volatile_load(&p), 3) }
		case .HEX_INT:
			for _ in 0 ..< n { sum += godot.string_hex_to_int(intrinsics.volatile_load(&p)) }
		case:
			for _ in 0 ..< n { sum += godot.string_hash(intrinsics.volatile_load(&p)) }
		}
	case .FILENAME_CALL:
		text := godot.string_of("7fffABCD1234")
		defer godot.destroy[.STRING](&text)
		p := &text
		fn := godot.builtin_method(.STRING, "is_valid_filename", 3918633141)
		for _ in 0 ..< n {
			v: u8
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += i64(v)
		}
	case .FILENAME:
		text := godot.string_of("7fffABCD1234")
		defer godot.destroy[.STRING](&text)
		p := &text
		for _ in 0 ..< n { sum += i64(godot.string_is_valid_filename(intrinsics.volatile_load(&p))) }
	case .ARRAY_TYPED_CALL:
		a := godot.array_new()
		defer godot.destroy[.ARRAY](&a)
		p := &a
		fn := godot.builtin_method(.ARRAY, "is_typed", 3918633141)
		for _ in 0 ..< n {
			v: u8
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += i64(v)
		}
	case .ARRAY_TYPED:
		a := godot.array_new()
		defer godot.destroy[.ARRAY](&a)
		p := &a
		for _ in 0 ..< n { sum += i64(godot.array_is_typed(intrinsics.volatile_load(&p))) }
	case .HTML_COLOR_CALL, .IP_ADDRESS_CALL:
		text := godot.string_of("#7fffABCD" if kind == .HTML_COLOR_CALL else "2001:db8:85a3::8a2e:370:7334")
		defer godot.destroy[.STRING](&text)
		p := &text
		fn := godot.builtin_method(.STRING, "is_valid_html_color" if kind == .HTML_COLOR_CALL else "is_valid_ip_address", 3918633141)
		for _ in 0 ..< n {
			v: u8
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += i64(v)
		}
	case .ARRAY_SAME_CALL, .ARRAY_SAME:
		a, o := godot.array_new(), godot.array_new()
		defer godot.destroy[.ARRAY](&a)
		defer godot.destroy[.ARRAY](&o)
		p, q := &a, &o
		if kind == .ARRAY_SAME {
			for _ in 0 ..< n { sum += i64(godot.array_is_same_typed(intrinsics.volatile_load(&p), intrinsics.volatile_load(&q)^)) }
			break
		}
		fn := godot.builtin_method(.ARRAY, "is_same_typed", 2988181878)
		for _ in 0 ..< n {
			v: u8
			args := [1]gde.ConstTypePtr{intrinsics.volatile_load(&q)}
			fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
			sum += i64(v)
		}
	case .CALLABLE_NULL_CALL, .CALLABLE_NULL, .CALLABLE_ID_CALL, .CALLABLE_ID, .SIGNAL_NULL_CALL, .SIGNAL_NULL:
		obj := godot.construct(godot.Object)
		defer gde.object_destroy(gde.ObjectPtr(obj))
		name := godot.name_of("free")
		defer godot.destroy[.STRING_NAME](&name)
		c := godot.callable_new_from_object_string_name(obj, name)
		defer godot.destroy[.CALLABLE](&c)
		s := godot.signal_new_from_object_string_name(obj, name)
		defer godot.destroy[.SIGNAL](&s)
		p, q := &c, &s
		#partial switch kind {
		case .CALLABLE_NULL:
			for _ in 0 ..< n { sum += i64(godot.callable_is_null(intrinsics.volatile_load(&p))) }
		case .CALLABLE_ID:
			for _ in 0 ..< n { sum += godot.callable_get_object_id(intrinsics.volatile_load(&p)) & 1 }
		case .SIGNAL_NULL:
			for _ in 0 ..< n { sum += i64(godot.signal_is_null(intrinsics.volatile_load(&q))) }
		case .CALLABLE_ID_CALL:
			fn := godot.builtin_method(.CALLABLE, "get_object_id", 3173160232)
			for _ in 0 ..< n {
				v: i64
				fn(intrinsics.volatile_load(&p), nil, &v, 0)
				sum += v & 1
			}
		case:
			of: rawptr = p if kind == .CALLABLE_NULL_CALL else q
			fn := godot.builtin_method(.CALLABLE if kind == .CALLABLE_NULL_CALL else .SIGNAL, "is_null", 3918633141)
			for _ in 0 ..< n {
				v: u8
				fn(intrinsics.volatile_load(&of), nil, &v, 0)
				sum += i64(v)
			}
		}
	case .PACKED_SET_CALL, .PACKED_SET:
		a := godot.packed_int64_array_new()
		defer godot.packed_int64_array_destroy(&a)
		godot.packed_int64_array_resize(&a, 16)
		p := &a
		if kind == .PACKED_SET {
			for i in 0 ..< n { godot.packed_int64_array_set(intrinsics.volatile_load(&p), 4, i) }
		} else {
			fn := godot.builtin_method(.PACKED_INT64_ARRAY, "set", 3638975848)
			for i in 0 ..< n {
				index, value: i64 = 4, i
				args := [2]gde.ConstTypePtr{&index, &value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 2)
			}
		}
		sum += godot.packed_int64_array_get(&a, 4)
	case .PACKED_FILL_CALL, .PACKED_FILL, .PACKED_REVERSE_CALL, .PACKED_REVERSE:
		a := godot.packed_int64_array_new()
		defer godot.packed_int64_array_destroy(&a)
		godot.packed_int64_array_resize(&a, 16)
		godot.packed_int64_array_set(&a, 3, 9)
		p := &a
		#partial switch kind {
		case .PACKED_FILL:
			for i in 0 ..< n { godot.packed_int64_array_fill(intrinsics.volatile_load(&p), i) }
		case .PACKED_FILL_CALL:
			fn := godot.builtin_method(.PACKED_INT64_ARRAY, "fill", 2823966027)
			for i in 0 ..< n {
				value := i
				args := [1]gde.ConstTypePtr{&value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 1)
			}
		case .PACKED_REVERSE:
			for _ in 0 ..< n { godot.packed_int64_array_reverse(intrinsics.volatile_load(&p)) }
		case:
			fn := godot.builtin_method(.PACKED_INT64_ARRAY, "reverse", 3218959716)
			for _ in 0 ..< n { fn(intrinsics.volatile_load(&p), nil, nil, 0) }
		}
		sum += godot.packed_int64_array_get(&a, 4)
	case .BYTES_FILL_CALL, .BYTES_FILL:
		a := godot.packed_byte_array_new()
		defer godot.packed_byte_array_destroy(&a)
		godot.packed_byte_array_resize(&a, 256)
		p := &a
		if kind == .BYTES_FILL {
			for i in 0 ..< n { godot.packed_byte_array_fill(intrinsics.volatile_load(&p), i) }
		} else {
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, "fill", 2823966027)
			for i in 0 ..< n {
				value := i
				args := [1]gde.ConstTypePtr{&value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 1)
			}
		}
		sum += godot.packed_byte_array_get(&a, 4)
	case .PACKED_SET_V3_CALL, .PACKED_SET_V3:
		a := godot.packed_vector3_array_new()
		defer godot.packed_vector3_array_destroy(&a)
		godot.packed_vector3_array_resize(&a, 16)
		p := &a
		if kind == .PACKED_SET_V3 {
			for i in 0 ..< n { godot.packed_vector3_array_set(intrinsics.volatile_load(&p), 4, godot.Vector3{f32(i), 1, 2}) }
		} else {
			fn := godot.builtin_method(.PACKED_VECTOR3_ARRAY, "set", 3975343409)
			for i in 0 ..< n {
				index: i64 = 4
				value := godot.Vector3{f32(i), 1, 2}
				args := [2]gde.ConstTypePtr{&index, &value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 2)
			}
		}
		sum += i64(godot.packed_vector3_array_get(&a, 4)[0])
	case .ENCODE_U32_CALL, .ENCODE_U32:
		a := godot.packed_byte_array_new()
		defer godot.packed_byte_array_destroy(&a)
		godot.packed_byte_array_resize(&a, 16)
		p := &a
		if kind == .ENCODE_U32 {
			for i in 0 ..< n { godot.packed_byte_array_encode_u32(intrinsics.volatile_load(&p), 4, i) }
		} else {
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, "encode_u32", 3638975848)
			for i in 0 ..< n {
				at, value: i64 = 4, i
				args := [2]gde.ConstTypePtr{&at, &value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 2)
			}
		}
		sum += godot.packed_byte_array_decode_u32(&a, 4)
	case .ENCODE_HALF_CALL, .ENCODE_HALF:
		a := godot.packed_byte_array_new()
		defer godot.packed_byte_array_destroy(&a)
		godot.packed_byte_array_resize(&a, 16)
		p := &a
		if kind == .ENCODE_HALF {
			for i in 0 ..< n { godot.packed_byte_array_encode_half(intrinsics.volatile_load(&p), 4, f64(i & 1023)) }
		} else {
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, "encode_half", 1113000516)
			for i in 0 ..< n {
				at: i64 = 4
				value := f64(i & 1023)
				args := [2]gde.ConstTypePtr{&at, &value}
				fn(intrinsics.volatile_load(&p), &args[0], nil, 2)
			}
		}
		sum += godot.packed_byte_array_decode_u16(&a, 4)
	case .BSWAP32_CALL, .BSWAP32, .BSWAP16_LONG_CALL, .BSWAP16_LONG:
		long := kind == .BSWAP16_LONG_CALL || kind == .BSWAP16_LONG
		a := godot.packed_byte_array_new()
		defer godot.packed_byte_array_destroy(&a)
		godot.packed_byte_array_resize(&a, long ? 4096 : 16)
		godot.packed_byte_array_encode_u32(&a, 4, 0x01020304)
		p := &a
		offset, count: i64 = long ? 0 : 4, long ? -1 : 2
		#partial switch kind {
		case .BSWAP32:
			for _ in 0 ..< n { godot.packed_byte_array_bswap32(intrinsics.volatile_load(&p), offset, count) }
		case .BSWAP16_LONG:
			for _ in 0 ..< n { godot.packed_byte_array_bswap16(intrinsics.volatile_load(&p), offset, count) }
		case:
			fn := godot.builtin_method(.PACKED_BYTE_ARRAY, long ? "bswap16" : "bswap32", 3638975848)
			args := [2]gde.ConstTypePtr{&offset, &count}
			for _ in 0 ..< n { fn(intrinsics.volatile_load(&p), &args[0], nil, 2) }
		}
		sum += godot.packed_byte_array_decode_u32(&a, 4)
	case .SLICE_COUNT_CALL, .SLICE_COUNT, .MATCH_CALL, .MATCH, .MATCHN_CALL, .MATCHN, .SUBSEQ_CALL, .SUBSEQ, .SUBSEQN_CALL, .SUBSEQN:
		path := godot.string_of("res://scenes/level_01.tscn")
		defer godot.destroy[.STRING](&path)
		// The Strings each row takes: the one the method is called on, then its argument.
		other: string
		name: cstring
		on_path := true
		#partial switch kind {
		case .SLICE_COUNT_CALL, .SLICE_COUNT: other, name = "/", "get_slice_count"
		case .MATCH_CALL, .MATCH:             other, name = "res://*level_??.tscn", "match"
		case .MATCHN_CALL, .MATCHN:           other, name = "RES://*LEVEL_??.TSCN", "matchn"
		case .SUBSEQ_CALL, .SUBSEQ:           other, name, on_path = "lvl01", "is_subsequence_of", false
		case:                                 other, name, on_path = "LVL01", "is_subsequence_ofn", false
		}
		arg := godot.string_of(other)
		defer godot.destroy[.STRING](&arg)
		self_text, arg_text := path, arg
		if !on_path { self_text, arg_text = arg, path }
		p := &self_text
		#partial switch kind {
		case .SLICE_COUNT:
			for _ in 0 ..< n { sum += godot.string_get_slice_count(intrinsics.volatile_load(&p), arg_text) }
		case .MATCH:
			for _ in 0 ..< n { sum += i64(godot.string_match(intrinsics.volatile_load(&p), arg_text)) }
		case .MATCHN:
			for _ in 0 ..< n { sum += i64(godot.string_matchn(intrinsics.volatile_load(&p), arg_text)) }
		case .SUBSEQ:
			for _ in 0 ..< n { sum += i64(godot.string_is_subsequence_of(intrinsics.volatile_load(&p), arg_text)) }
		case .SUBSEQN:
			for _ in 0 ..< n { sum += i64(godot.string_is_subsequence_ofn(intrinsics.volatile_load(&p), arg_text)) }
		case .SLICE_COUNT_CALL:
			fn := godot.builtin_method(.STRING, "get_slice_count", 2920860731)
			args := [1]gde.ConstTypePtr{&arg_text}
			for _ in 0 ..< n {
				v: i64
				fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
				sum += v
			}
		case:
			fn := godot.builtin_method(.STRING, name, 2566493496)
			args := [1]gde.ConstTypePtr{&arg_text}
			for _ in 0 ..< n {
				v: bool
				fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
				sum += i64(v)
			}
		}
	case .DICT_SAME_CALL, .DICT_SAME:
		a, o := godot.dictionary_new(), godot.dictionary_new()
		defer godot.destroy[.DICTIONARY](&a)
		defer godot.destroy[.DICTIONARY](&o)
		p, q := &a, &o
		if kind == .DICT_SAME {
			for _ in 0 ..< n { sum += i64(godot.dictionary_is_same_typed(intrinsics.volatile_load(&p), intrinsics.volatile_load(&q)^)) }
			break
		}
		fn := godot.builtin_method(.DICTIONARY, "is_same_typed", 3471775634)
		for _ in 0 ..< n {
			v: u8
			args := [1]gde.ConstTypePtr{intrinsics.volatile_load(&q)}
			fn(intrinsics.volatile_load(&p), &args[0], &v, 1)
			sum += i64(v)
		}
	case .HTML_COLOR, .IP_ADDRESS:
		text := godot.string_of("#7fffABCD" if kind == .HTML_COLOR else "2001:db8:85a3::8a2e:370:7334")
		defer godot.destroy[.STRING](&text)
		p := &text
		if kind == .HTML_COLOR {
			for _ in 0 ..< n { sum += i64(godot.string_is_valid_html_color(intrinsics.volatile_load(&p))) }
		} else {
			for _ in 0 ..< n { sum += i64(godot.string_is_valid_ip_address(intrinsics.volatile_load(&p))) }
		}
	case .VALID_FLOAT_CALL:
		num := godot.string_of("-123.456e-2")
		defer godot.destroy[.STRING](&num)
		p := &num
		fn := godot.builtin_method(.STRING, "is_valid_float", 3918633141)
		for _ in 0 ..< n {
			v: u8
			fn(intrinsics.volatile_load(&p), nil, &v, 0)
			sum += i64(v)
		}
	case .VALID_FLOAT:
		num := godot.string_of("-123.456e-2")
		defer godot.destroy[.STRING](&num)
		p := &num
		for _ in 0 ..< n { sum += i64(godot.string_is_valid_float(intrinsics.volatile_load(&p))) }
	case .TO_INT_RUNES:
		num := godot.string_of("-12345")
		defer godot.destroy[.STRING](&num)
		p := &num
		for _ in 0 ..< n { sum += godot.runes_to_int(godot.string_read(intrinsics.volatile_load(&p))) }
	case .TO_FLOAT_ENGINE:
		num := godot.string_of("-123.456e-2")
		defer godot.destroy[.STRING](&num)
		p := &num
		for _ in 0 ..< n { sum += i64(godot.string_to_float(intrinsics.volatile_load(&p))) }
	case .TO_FLOAT_RUNES:
		num := godot.string_of("-123.456e-2")
		defer godot.destroy[.STRING](&num)
		p := &num
		for _ in 0 ..< n { sum += i64(godot.runes_to_float(godot.string_read(intrinsics.volatile_load(&p)))) }
	case .INT_TEXT_ENGINE:
		v, base, caps := i64(-1234567), i64(10), u8(0)
		args := [3]gde.ConstTypePtr{&v, &base, &caps}
		fn := godot.builtin_method(.STRING, "num_int64", 2111271071)
		for _ in 0 ..< n {
			s: godot.String
			fn(nil, &args[0], &s, 3)
			sum += i64(godot.string_length(&s))
			godot.destroy[.STRING](&s)
		}
	case .INT_TEXT:
		v := i64(-1234567)
		for _ in 0 ..< n {
			s := godot.string_of_int(intrinsics.volatile_load(&v))
			sum += i64(godot.string_length(&s))
			godot.destroy[.STRING](&s)
		}
	case .FLOAT_TEXT_ENGINE:
		v, places := -123.456, i64(-1)
		args := [2]gde.ConstTypePtr{&v, &places}
		fn := godot.builtin_method(.STRING, "num", 1555901022)
		for _ in 0 ..< n {
			s: godot.String
			fn(nil, &args[0], &s, 2)
			sum += i64(godot.string_length(&s))
			godot.destroy[.STRING](&s)
		}
	case .FLOAT_TEXT:
		v := -123.456
		for _ in 0 ..< n {
			s := godot.string_of_float(intrinsics.volatile_load(&v))
			sum += i64(godot.string_length(&s))
			godot.destroy[.STRING](&s)
		}
	case .NAME_CHAIN:
		sn := godot.name_of(text)
		defer godot.destroy[.STRING_NAME](&sn)
		r := &sn
		for _ in 0 ..< n {
			name := intrinsics.volatile_load(&r)^
			switch {
			case godot.same_name(name, godot.intern("player_jum")):    sum += 0
			case godot.same_name(name, godot.intern("player_run")):    sum += 1
			case godot.same_name(name, godot.intern("player_walk")):   sum += 2
			case godot.same_name(name, godot.intern("player_dash")):   sum += 3
			case godot.same_name(name, godot.intern("pause")):         sum += 4
			case godot.same_name(name, godot.intern("player_crouch")): sum += 5
			case godot.same_name(name, godot.intern("player_jumq")):   sum += 6
			case godot.same_name(name, godot.intern("player_jump")):   sum += 7
			}
		}
	case .NAME_WHICH:
		sn := godot.name_of(text)
		defer godot.destroy[.STRING_NAME](&sn)
		r := &sn
		set := godot.name_set(WHICH_NAMES)
		defer godot.name_set_destroy(&set)
		for _ in 0 ..< n {
			sum += i64(godot.name_which(intrinsics.volatile_load(&r)^, &set))
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

// The Vector3i methods `vectori_ns` times, paired the same way as Vector_Op.
Vectori_Op :: enum i64 {
	LENGTH_CALL,        // the engine's Vector3i.length
	LENGTH,             // vector3i_length
	DISTANCE_SQ_CALL,   // the engine's Vector3i.distance_squared_to
	DISTANCE_SQ,        // vector3i_distance_squared_to
	SNAPPED_CALL,       // the engine's Vector3i.snapped
	SNAPPED,            // vector3i_snapped
}

// Nanoseconds per `kind` round on a Vector3i reread through a volatile load each round, as in
// vector_ns.
vectori_ns :: proc(self: ^Bench, kind: Vectori_Op, n: i64) -> f64 {
	v := godot.Vector3i{7, -12, 30}
	to := godot.Vector3i{-5, 4, 2}
	step := godot.Vector3i{4, 5, 6}
	ref := &v
	length_fn := godot.builtin_method(.VECTOR3I, "length", 466405837)
	distance_fn := godot.builtin_method(.VECTOR3I, "distance_squared_to", 2947717320)
	snapped_fn := godot.builtin_method(.VECTOR3I, "snapped", 1989319750)
	sum: i64
	start := time.tick_now()
	switch kind {
	case .LENGTH_CALL:
		for _ in 0 ..< n {
			r: f64
			length_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += i64(r)
		}
	case .LENGTH:
		for _ in 0 ..< n { sum += i64(godot.vector3i_length(intrinsics.volatile_load(&ref))) }
	case .DISTANCE_SQ_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&to}
			r: i64
			distance_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r
		}
	case .DISTANCE_SQ:
		for _ in 0 ..< n { sum += godot.vector3i_distance_squared_to(intrinsics.volatile_load(&ref), to) }
	case .SNAPPED_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&step}
			r: godot.Vector3i
			snapped_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += i64(r.x)
		}
	case .SNAPPED:
		for _ in 0 ..< n { sum += i64(godot.vector3i_snapped(intrinsics.volatile_load(&ref), step).x) }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The Color methods `color_ns` times, paired the same way as Vector_Op.
Color_Op :: enum i64 {
	TO_RGBA32_CALL,      // the engine's Color.to_rgba32
	TO_RGBA32,           // color_to_rgba32
	LERP_CALL,           // the engine's Color.lerp at weight 0.25
	LERP,                // color_lerp at weight 0.25
	LINEAR_TO_SRGB_CALL, // the engine's Color.linear_to_srgb
	LINEAR_TO_SRGB,      // color_linear_to_srgb
	FROM_HSV_CALL,       // the engine's Color.from_hsv
	FROM_HSV,            // color_from_hsv
	TO_HTML_CALL,        // the engine's Color.to_html with alpha
	TO_HTML,             // color_to_html with alpha
	FROM_STRING_CALL,    // the engine's Color.from_string on a name with spaces
	FROM_STRING,         // color_from_string on a name with spaces
	FROM_OK_HSL_CALL,    // the engine's Color.from_ok_hsl
	FROM_OK_HSL,         // color_from_ok_hsl
}

// Nanoseconds per `kind` round on a Color reread through a volatile load each round, as in
// vector_ns.
color_ns :: proc(self: ^Bench, kind: Color_Op, n: i64) -> f64 {
	v := godot.Color{0.25, 0.5, 0.75, 1}
	to := godot.Color{0.9, 0.1, 0.4, 0.5}
	weight, h, s, val, alpha := f64(0.25), f64(0.6), f64(0.5), f64(0.8), f64(1)
	ref := &v
	rgba_fn := godot.builtin_method(.COLOR, "to_rgba32", 3173160232)
	lerp_fn := godot.builtin_method(.COLOR, "lerp", 402949615)
	srgb_fn := godot.builtin_method(.COLOR, "linear_to_srgb", 3334027602)
	hsv_fn := godot.builtin_method(.COLOR, "from_hsv", 1573799446)
	html_fn := godot.builtin_method(.COLOR, "to_html", 3429816538)
	from_string_fn := godot.builtin_method(.COLOR, "from_string", 3755044230)
	ok_hsl_fn := godot.builtin_method(.COLOR, "from_ok_hsl", 1573799446)
	with_alpha := true
	name := godot.string_of("Dark Olive Green")
	defer godot.destroy[.STRING](&name)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .TO_RGBA32_CALL:
		for _ in 0 ..< n {
			r: i64
			rgba_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += f32(r & 0xFF)
		}
	case .TO_RGBA32:
		for _ in 0 ..< n { sum += f32(godot.color_to_rgba32(intrinsics.volatile_load(&ref)) & 0xFF) }
	case .LERP_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&to, &weight}
			r: godot.Color
			lerp_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += r.r
		}
	case .LERP:
		for _ in 0 ..< n { sum += godot.color_lerp(intrinsics.volatile_load(&ref), to, weight).r }
	case .LINEAR_TO_SRGB_CALL:
		for _ in 0 ..< n {
			r: godot.Color
			srgb_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.r
		}
	case .LINEAR_TO_SRGB:
		for _ in 0 ..< n { sum += godot.color_linear_to_srgb(intrinsics.volatile_load(&ref)).r }
	case .FROM_HSV_CALL:
		for _ in 0 ..< n {
			hue := f64(intrinsics.volatile_load(&ref).r) + h
			args := [4]gde.ConstTypePtr{&hue, &s, &val, &alpha}
			r: godot.Color
			hsv_fn(nil, &args[0], &r, 4)
			sum += r.r
		}
	case .FROM_HSV:
		for _ in 0 ..< n { sum += godot.color_from_hsv(f64(intrinsics.volatile_load(&ref).r) + h, s, val, alpha).r }
	case .TO_HTML_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&with_alpha}
			r: godot.String
			html_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(godot.string_read(&r)[1])
			godot.destroy[.STRING](&r)
		}
	case .TO_HTML:
		for _ in 0 ..< n {
			r := godot.color_to_html(intrinsics.volatile_load(&ref), with_alpha)
			sum += f32(godot.string_read(&r)[1])
			godot.destroy[.STRING](&r)
		}
	case .FROM_STRING_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&name, intrinsics.volatile_load(&ref)}
			r: godot.Color
			from_string_fn(nil, &args[0], &r, 2)
			sum += r.r
		}
	case .FROM_STRING:
		for _ in 0 ..< n { sum += godot.color_from_string(name, intrinsics.volatile_load(&ref)^).r }
	case .FROM_OK_HSL_CALL:
		for _ in 0 ..< n {
			hue := f64(intrinsics.volatile_load(&ref).r) + h
			args := [4]gde.ConstTypePtr{&hue, &s, &val, &alpha}
			r: godot.Color
			ok_hsl_fn(nil, &args[0], &r, 4)
			sum += r.r
		}
	case .FROM_OK_HSL:
		for _ in 0 ..< n { sum += godot.color_from_ok_hsl(f64(intrinsics.volatile_load(&ref).r) + h, s, val, alpha).r }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The Basis methods `basis_ns` times, paired the same way as Vector_Op.
Basis_Op :: enum i64 {
	INVERSE_CALL,   // the engine's Basis.inverse
	INVERSE,        // basis_inverse
	ROTATED_CALL,   // the engine's Basis.rotated about a unit axis
	ROTATED,        // basis_rotated about a unit axis
	GET_EULER_CALL, // the engine's Basis.get_euler in YXZ order
	GET_EULER,      // basis_get_euler in YXZ order
	SLERP_CALL,     // the engine's Basis.slerp at weight 0.25
	SLERP,          // basis_slerp at weight 0.25
}

// Nanoseconds per `kind` round on a rotation reread through a volatile load each round, as in
// vector_ns.
basis_ns :: proc(self: ^Bench, kind: Basis_Op, n: i64) -> f64 {
	v := godot.basis_from_euler(godot.Vector3{0.3, -1.2, 2.0}, 2)
	to := godot.basis_from_euler(godot.Vector3{-0.7, 0.4, 1.1}, 2)
	axis := godot.Vector3{0.6, 0, 0.8}
	angle, weight, order := f64(0.7), f64(0.25), i64(2)
	ref := &v
	inverse_fn := godot.builtin_method(.BASIS, "inverse", 594669093)
	rotated_fn := godot.builtin_method(.BASIS, "rotated", 1998708965)
	euler_fn := godot.builtin_method(.BASIS, "get_euler", 1394941017)
	slerp_fn := godot.builtin_method(.BASIS, "slerp", 3118673011)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .INVERSE_CALL:
		for _ in 0 ..< n {
			r: godot.Basis
			inverse_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.x.x
		}
	case .INVERSE:
		for _ in 0 ..< n { sum += godot.basis_inverse(intrinsics.volatile_load(&ref)).x.x }
	case .ROTATED_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&axis, &angle}
			r: godot.Basis
			rotated_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += r.x.x
		}
	case .ROTATED:
		// The angle is reread too, or the compiler hoists the sine and cosine out of the loop.
		ang := &angle
		for _ in 0 ..< n { sum += godot.basis_rotated(intrinsics.volatile_load(&ref), axis, intrinsics.volatile_load(ang)).x.x }
	case .GET_EULER_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&order}
			r: godot.Vector3
			euler_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.x
		}
	case .GET_EULER:
		for _ in 0 ..< n { sum += godot.basis_get_euler(intrinsics.volatile_load(&ref), order).x }
	case .SLERP_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&to, &weight}
			r: godot.Basis
			slerp_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += r.x.x
		}
	case .SLERP:
		for _ in 0 ..< n { sum += godot.basis_slerp(intrinsics.volatile_load(&ref), to, weight).x.x }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The Transform2D and Transform3D methods `transform_ns` times, paired the same way as Vector_Op.
Transform_Op :: enum i64 {
	T2_AFFINE_INVERSE_CALL, // the engine's Transform2D.affine_inverse
	T2_AFFINE_INVERSE,      // transform2d_affine_inverse
	T2_INTERPOLATE_CALL,    // the engine's Transform2D.interpolate_with at weight 0.25
	T2_INTERPOLATE,         // transform2d_interpolate_with at weight 0.25
	T3_AFFINE_INVERSE_CALL, // the engine's Transform3D.affine_inverse
	T3_AFFINE_INVERSE,      // transform3d_affine_inverse
	T3_INTERPOLATE_CALL,    // the engine's Transform3D.interpolate_with at weight 0.25
	T3_INTERPOLATE,         // transform3d_interpolate_with at weight 0.25
}

// Nanoseconds per `kind` round on a scaled, skewed transform reread through a volatile load each
// round, as in vector_ns.
transform_ns :: proc(self: ^Bench, kind: Transform_Op, n: i64) -> f64 {
	a2 := godot.transform2d_new_from_float_vector2_float_vector2(0.7, {2, -0.5}, 0.3, {1, 2})
	b2 := godot.transform2d_new_from_float_vector2_float_vector2(-1.1, {1.5, 0.8}, -0.2, {-3, 0.5})
	r := godot.basis_from_euler(godot.Vector3{0.3, -1.2, 2.0}, 2)
	a3 := godot.Transform3D{godot.basis_scaled(&r, {2, 0.5, 3}), {1, 2, 3}}
	b3 := godot.Transform3D{godot.basis_from_euler(godot.Vector3{-0.7, 0.4, 1.1}, 2), {-2, 0, 1}}
	weight := f64(0.25)
	ref2, ref3 := &a2, &a3
	to2, to3 := &b2, &b3
	inv2_fn := godot.builtin_method(.TRANSFORM2D, "affine_inverse", 1420440541)
	lerp2_fn := godot.builtin_method(.TRANSFORM2D, "interpolate_with", 359399686)
	inv3_fn := godot.builtin_method(.TRANSFORM3D, "affine_inverse", 3816817146)
	lerp3_fn := godot.builtin_method(.TRANSFORM3D, "interpolate_with", 1786453358)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .T2_AFFINE_INVERSE_CALL:
		for _ in 0 ..< n {
			t: godot.Transform2D
			inv2_fn(intrinsics.volatile_load(&ref2), nil, &t, 0)
			sum += t.x.x
		}
	case .T2_AFFINE_INVERSE:
		for _ in 0 ..< n { sum += godot.transform2d_affine_inverse(intrinsics.volatile_load(&ref2)).x.x }
	case .T2_INTERPOLATE_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&b2, &weight}
			t: godot.Transform2D
			lerp2_fn(intrinsics.volatile_load(&ref2), &args[0], &t, 2)
			sum += t.x.x
		}
	case .T2_INTERPOLATE:
		for _ in 0 ..< n { sum += godot.transform2d_interpolate_with(intrinsics.volatile_load(&ref2), intrinsics.volatile_load(&to2)^, weight).x.x }
	case .T3_AFFINE_INVERSE_CALL:
		for _ in 0 ..< n {
			t: godot.Transform3D
			inv3_fn(intrinsics.volatile_load(&ref3), nil, &t, 0)
			sum += t.basis.x.x
		}
	case .T3_AFFINE_INVERSE:
		for _ in 0 ..< n { sum += godot.transform3d_affine_inverse(intrinsics.volatile_load(&ref3)).basis.x.x }
	case .T3_INTERPOLATE_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&b3, &weight}
			t: godot.Transform3D
			lerp3_fn(intrinsics.volatile_load(&ref3), &args[0], &t, 2)
			sum += t.basis.x.x
		}
	case .T3_INTERPOLATE:
		for _ in 0 ..< n { sum += godot.transform3d_interpolate_with(intrinsics.volatile_load(&ref3), intrinsics.volatile_load(&to3)^, weight).basis.x.x }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The String methods `string_ns` times that `ident_ns` does not, paired the same way as Vector_Op:
// the engine's method through its builtin method pointer, as the bindings called it before, then
// its replacement on the same Strings.
String_Op :: enum i64 {
	RFINDN_CALL,    // the engine's String.rfindn of "QUICK" in the sentence
	RFINDN,         // string_rfindn of the same
	CONTAINS_CALL,  // the engine's String.contains of "lazy" in the sentence
	CONTAINS,       // string_contains of the same
	CONTAINSN_CALL, // the engine's String.containsn of "LAZY" in the sentence
	CONTAINSN,      // string_containsn of the same
	COUNT_CALL,     // the engine's String.count of "the" in the sentence
	COUNT,          // string_count of the same
	COUNTN_CALL,    // the engine's String.countn of "THE" in the sentence
	COUNTN,         // string_countn of the same
	BEGINS_CALL,    // the engine's String.begins_with of "the quick" on the sentence
	BEGINS,         // string_begins_with of the same
	ENDS_CALL,      // the engine's String.ends_with of "lazy dog" on the sentence
	ENDS,           // string_ends_with of the same
	CASECMP_CALL,   // the engine's String.casecmp_to of the sentence and a copy in separate storage
	CASECMP,        // string_casecmp_to of the same
	REPLACEN_CALL,  // the engine's String.replacen of "THE" by "a" in the sentence, the result destroyed
	REPLACEN,       // string_replacen of the same
	SUBSTR_CALL,    // the engine's String.substr of 5 characters from 4 of the sentence, the result destroyed
	SUBSTR,         // string_substr of the same
	LEFT_CALL,      // the engine's String.left of 9 characters of the sentence, the result destroyed
	LEFT,           // string_left of the same
	RIGHT_CALL,     // the engine's String.right of 8 characters of the sentence, the result destroyed
	RIGHT,          // string_right of the same
	TO_UPPER_CALL,  // the engine's String.to_upper of the sentence, the result destroyed
	TO_UPPER,       // string_to_upper of the same
	TO_LOWER_CALL,  // the engine's String.to_lower of the sentence, the result destroyed
	TO_LOWER,       // string_to_lower of the same
	GET_SLICE_CALL,   // the engine's String.get_slice of part 3 of the sentence split on spaces, the result destroyed
	GET_SLICE,        // string_get_slice of the same
	TRIM_PREFIX_CALL, // the engine's String.trim_prefix of the sentence's first two words, the result destroyed
	TRIM_PREFIX,      // string_trim_prefix of the same
	TRIM_SUFFIX_CALL, // the engine's String.trim_suffix of the sentence's last two words, the result destroyed
	TRIM_SUFFIX,      // string_trim_suffix of the same
	STRIP_EDGES_CALL, // the engine's String.strip_edges of the sentence with two spaces before it and a tab and a newline after, the result destroyed
	STRIP_EDGES,      // string_strip_edges of the same
	LSTRIP_CALL,      // the engine's String.lstrip of the characters of "the " from the sentence, the result destroyed
	LSTRIP,           // string_lstrip of the same
	RSTRIP_CALL,      // the engine's String.rstrip of the characters of "dog " from the sentence, the result destroyed
	RSTRIP,           // string_rstrip of the same
	CAPITALIZE_CALL, // the engine's String.capitalize of the sentence, the result destroyed
	CAPITALIZE, // string_capitalize of the same
	CAMEL_CALL, // the engine's String.to_camel_case of the sentence, the result destroyed
	CAMEL, // string_to_camel_case of the same
	PASCAL_CALL, // the engine's String.to_pascal_case of the sentence, the result destroyed
	PASCAL, // string_to_pascal_case of the same
	SNAKE_CALL, // the engine's String.to_snake_case of the sentence, the result destroyed
	SNAKE, // string_to_snake_case of the same
	KEBAB_CALL, // the engine's String.to_kebab_case of the sentence, the result destroyed
	KEBAB, // string_to_kebab_case of the same
	EXTENSION_CALL, // the engine's String.get_extension of "res://scenes/level_01.tscn", the result destroyed
	EXTENSION, // string_get_extension of the same
	BASENAME_CALL, // the engine's String.get_basename of "res://scenes/level_01.tscn", the result destroyed
	BASENAME, // string_get_basename of the same
	FILE_CALL, // the engine's String.get_file of "res://scenes/level_01.tscn", the result destroyed
	FILE, // string_get_file of the same
	BASE_DIR_CALL, // the engine's String.get_base_dir of "res://scenes/level_01.tscn", the result destroyed
	BASE_DIR, // string_get_base_dir of the same
	NATURAL_CALL, // the engine's String.naturalcasecmp_to of "_scene_010_boss_fight.tscn" to "_scene_10_boss_fight.tscn"
	NATURAL, // string_naturalcasecmp_to of the same
	NATURALN_CALL, // the engine's String.naturalnocasecmp_to of "_scene_010_boss_fight.tscn" to "_scene_10_boss_fight.tscn"
	NATURALN, // string_naturalnocasecmp_to of the same
	FILECMP_CALL, // the engine's String.filecasecmp_to of "_scene_010_boss_fight.tscn" to "_scene_10_boss_fight.tscn"
	FILECMP, // string_filecasecmp_to of the same
	FILECMPN_CALL, // the engine's String.filenocasecmp_to of "_scene_010_boss_fight.tscn" to "_scene_10_boss_fight.tscn"
	FILECMPN, // string_filenocasecmp_to of the same
	PATH_JOIN_CALL, // the engine's String.path_join of "res://scenes" and "level_01.tscn", the result destroyed
	PATH_JOIN, // string_path_join of the same
	SIMPLIFY_CALL, // the engine's String.simplify_path of "res://scenes/../levels/./level_01.tscn", the result destroyed
	SIMPLIFY, // string_simplify_path of the same
	SIMPLIFY_SAME_CALL, // the engine's String.simplify_path of "res://scenes/level_01.tscn", which is simple already
	SIMPLIFY_SAME, // string_simplify_path of the same
	REPEAT_CALL, // the engine's String.repeat of "res://scenes/level_01.tscn" 4 times, the result destroyed
	REPEAT, // string_repeat of the same
	REVERSE_CALL, // the engine's String.reverse of "res://scenes/level_01.tscn", the result destroyed
	REVERSE, // string_reverse of the same
	INSERT_CALL, // the engine's String.insert of "level_01.tscn" at 6 of "res://scenes/level_01.tscn", the result destroyed
	INSERT, // string_insert of the same
	ERASE_CALL, // the engine's String.erase of 7 characters at 6 of "res://scenes/level_01.tscn", the result destroyed
	ERASE, // string_erase of the same
	REPLACE_CHAR_CALL, // the engine's String.replace_char of '/' by '\' in "res://scenes/level_01.tscn", the result destroyed
	REPLACE_CHAR, // string_replace_char of the same
	REMOVE_CHAR_CALL, // the engine's String.remove_char of '/' from "res://scenes/level_01.tscn", the result destroyed
	REMOVE_CHAR, // string_remove_char of the same
	REPLACE_CHARS_CALL, // the engine's String.replace_chars of "/_" by '-' in "res://scenes/level_01.tscn", the result destroyed
	REPLACE_CHARS, // string_replace_chars of the same
	REMOVE_CHARS_CALL, // the engine's String.remove_chars of "/_" from "res://scenes/level_01.tscn", the result destroyed
	REMOVE_CHARS, // string_remove_chars of the same
	REMOVE_CHARS_LONG_CALL, // the engine's String.remove_chars of "/_" from that path 40 times over, 1040 characters
	REMOVE_CHARS_LONG, // string_remove_chars of the same
	REMOVE_CHAR_LONG_CALL, // the engine's String.remove_char of '/' from the same 1040 characters
	REMOVE_CHAR_LONG, // string_remove_char of the same
	LPAD_CALL, // the engine's String.lpad of "12.5" to 10 characters with "0", the result destroyed
	LPAD, // string_lpad of the same
	RPAD_CALL, // the engine's String.rpad of "12.5" to 10 characters with "0", the result destroyed
	RPAD, // string_rpad of the same
	PAD_ZEROS_CALL, // the engine's String.pad_zeros of "12.5" to 6 digits, the result destroyed
	PAD_ZEROS, // string_pad_zeros of the same
	PAD_DECIMALS_CALL, // the engine's String.pad_decimals of "12.5" to 4 digits, the result destroyed
	PAD_DECIMALS, // string_pad_decimals of the same
	INDENT_CALL, // the engine's String.indent of four lines of code with a tab, the result destroyed
	INDENT, // string_indent of the same
	DEDENT_CALL, // the engine's String.dedent of the four lines, the result destroyed
	DEDENT, // string_dedent of the same
	STRIP_ESCAPES_CALL, // the engine's String.strip_escapes of the four lines, the result destroyed
	STRIP_ESCAPES, // string_strip_escapes of the same
	GET_SLICEC_CALL, // the engine's String.get_slicec of part 3 of the scene path split on `/`, the result destroyed
	GET_SLICEC, // string_get_slicec of the same
	INDENT_LONG_CALL, // the engine's String.indent of the four lines 40 times over, the result destroyed
	INDENT_LONG, // string_indent of the same
	DEDENT_LONG_CALL, // the engine's String.dedent of the four lines 40 times over, the result destroyed
	DEDENT_LONG, // string_dedent of the same
	STRIP_ESCAPES_LONG_CALL, // the engine's String.strip_escapes of the four lines 40 times over, the result destroyed
	STRIP_ESCAPES_LONG, // string_strip_escapes of the same
	BIGRAMS_CALL, // the engine's String.bigrams of the file name, the result destroyed
	BIGRAMS, // string_bigrams of the same
	SIMILARITY_CALL, // the engine's String.similarity of the scene path to the file name
	SIMILARITY, // string_similarity of the same
	RSPLIT_CALL, // the engine's String.rsplit of the sentence on " ", the result destroyed
	RSPLIT, // string_rsplit of the same
	SPLIT_FLOATS_CALL, // the engine's String.split_floats of five numbers on ","
	SPLIT_FLOATS, // string_split_floats of the same
	JOIN_CALL, // the engine's String.join of the sentence's nine words with ", "
	JOIN, // string_join of the same
	VALIDATE_NODE_CALL, // the engine's String.validate_node_name of a name it keeps
	VALIDATE_NODE, // string_validate_node_name of the same
	VALIDATE_NODE_BAD_CALL, // the engine's String.validate_node_name of a name with 2 characters to replace
	VALIDATE_NODE_BAD, // string_validate_node_name of the same
	VALIDATE_FILE_CALL, // the engine's String.validate_filename of a padded name with 2 characters to replace
	VALIDATE_FILE, // string_validate_filename of the same
	UNICODE_ID_CALL, // the engine's String.is_valid_unicode_identifier of a name with 2 accented letters
	UNICODE_ID, // string_is_valid_unicode_identifier of the same
	NUM_INT_CALL, // the engine's String.num_int64 of -1234567 in base 16, made and destroyed
	NUM_INT, // string_num_int64 of the same
	NUM_UINT_CALL, // the engine's String.num_uint64 of the same number, which is 16 digits
	NUM_UINT, // string_num_uint64 of the same
	NUM_CALL, // the engine's String.num of -123.456 at the default places
	NUM, // string_num of the same
	CHR_CALL, // the engine's String.chr of U+00E9
	CHR, // string_chr of the same
	NUM_SCI_CALL, // the engine's String.num_scientific of -123.456
	NUM_SCI, // string_num_scientific of the same
	C_ESCAPE_CALL, // the engine's String.c_escape of a line with 5 characters to escape
	C_ESCAPE, // string_c_escape of the same
	JSON_ESCAPE_CALL, // the engine's String.json_escape of the same line
	JSON_ESCAPE, // string_json_escape of the same
	XML_ESCAPE_CALL, // the engine's String.xml_escape, quotes too, of a tag with 8 characters to escape
	XML_ESCAPE, // string_xml_escape of the same
	C_UNESCAPE_CALL, // the engine's String.c_unescape of a line with 5 escapes
	C_UNESCAPE, // string_c_unescape of the same
	XML_UNESCAPE_CALL, // the engine's String.xml_unescape of a tag with 8 entities
	XML_UNESCAPE, // string_xml_unescape of the same
	URI_ENCODE_CALL, // the engine's String.uri_encode of a file name with 7 characters to encode
	URI_ENCODE, // string_uri_encode of the same
	URI_DECODE_CALL, // the engine's String.uri_decode of a file name with 7 escapes
	URI_DECODE, // string_uri_decode of the same
	URI_FILE_DECODE_CALL, // the engine's String.uri_file_decode of the same file name
	URI_FILE_DECODE, // string_uri_file_decode of the same
	HEX_DECODE_CALL, // the engine's String.hex_decode of 24 digits
	HEX_DECODE, // string_hex_decode of the same
	ASCII_BUFFER_CALL, // the engine's String.to_ascii_buffer of a 24-character ASCII line
	ASCII_BUFFER, // string_to_ascii_buffer of the same
	UTF8_BUFFER_CALL, // the engine's String.to_utf8_buffer of a 24-character line, 3 of them not ASCII
	UTF8_BUFFER, // string_to_utf8_buffer of the same
	UTF16_BUFFER_CALL, // the engine's String.to_utf16_buffer of the same line
	UTF16_BUFFER, // string_to_utf16_buffer of the same
	UTF32_BUFFER_CALL, // the engine's String.to_utf32_buffer of the same line
	UTF32_BUFFER, // string_to_utf32_buffer of the same
	WCHAR_BUFFER_CALL, // the engine's String.to_wchar_buffer of the same line
	WCHAR_BUFFER, // string_to_wchar_buffer of the same
	BYTES_ASCII_CALL, // the engine's PackedByteArray.get_string_from_ascii of a 24-character ASCII line
	BYTES_ASCII, // packed_byte_array_get_string_from_ascii of the same
	BYTES_UTF8_CALL, // the engine's PackedByteArray.get_string_from_utf8 of a 24-character line, 3 of them not ASCII
	BYTES_UTF8, // packed_byte_array_get_string_from_utf8 of the same
	BYTES_UTF16_CALL, // the engine's PackedByteArray.get_string_from_utf16 of the same line
	BYTES_UTF16, // packed_byte_array_get_string_from_utf16 of the same
	BYTES_UTF32_CALL, // the engine's PackedByteArray.get_string_from_utf32 of the same line
	BYTES_UTF32, // packed_byte_array_get_string_from_utf32 of the same
	BYTES_WCHAR_CALL, // the engine's PackedByteArray.get_string_from_wchar of the same line
	BYTES_WCHAR, // packed_byte_array_get_string_from_wchar of the same
	BYTES_HEX_CALL, // the engine's PackedByteArray.hex_encode of 12 bytes
	BYTES_HEX, // packed_byte_array_hex_encode of the same
}

// Nanoseconds per `kind` round on FIND_HAY, reread through a volatile load each round, over `n`
// rounds.
string_ns :: proc(self: ^Bench, kind: String_Op, n: i64) -> f64 {
	hay, same := godot.string_of(FIND_HAY), godot.string_of(FIND_HAY)
	defer godot.destroy[.STRING](&hay)
	defer godot.destroy[.STRING](&same)
	h := &hay
	quick, lazy, lazy_upper := godot.intern_text("QUICK"), godot.intern_text("lazy"), godot.intern_text("LAZY")
	the, the_upper, a := godot.intern_text("the"), godot.intern_text("THE"), godot.intern_text("a")
	head, tail := godot.intern_text("the quick"), godot.intern_text("lazy dog")
	from, to := i64(0), i64(0)
	last := i64(-1)
	slice_from, slice_len, left_len, right_len := i64(4), i64(5), i64(9), i64(8)
	padded := godot.string_of("  " + FIND_HAY + "\t\n")
	defer godot.destroy[.STRING](&padded)
	p := &padded
	space := godot.intern_text(" ")
	part := i64(3)
	both := true
	the_set, dog_set := godot.intern_text("the "), godot.intern_text("dog ")
	scene := godot.string_of("res://scenes/level_01.tscn")
	defer godot.destroy[.STRING](&scene)
	sc := &scene
	numbered, numbered_to := godot.string_of("_scene_010_boss_fight.tscn"), godot.string_of("_scene_10_boss_fight.tscn")
	defer godot.destroy[.STRING](&numbered)
	defer godot.destroy[.STRING](&numbered_to)
	nu := &numbered
	dir, leaf := godot.string_of("res://scenes"), godot.string_of("level_01.tscn")
	defer godot.destroy[.STRING](&dir)
	defer godot.destroy[.STRING](&leaf)
	keys := godot.string_of("/_")
	number, zero := godot.string_of("12.5"), godot.string_of("0")
	defer godot.destroy[.STRING](&number)
	defer godot.destroy[.STRING](&zero)
	code, tab := godot.string_of("\t\tif ready:\n\t\t\tstart()\n\n\t\treturn total\n"), godot.string_of("\t")
	code_long := godot.string_repeat(&code, 40)
	defer godot.destroy[.STRING](&code)
	defer godot.destroy[.STRING](&tab)
	defer godot.destroy[.STRING](&code_long)
	long := godot.string_repeat(sc, 40)
	defer godot.destroy[.STRING](&long)
	defer godot.destroy[.STRING](&keys)
	d := &dir
	dotted := godot.string_of("res://scenes/../levels/./level_01.tscn")
	defer godot.destroy[.STRING](&dotted)
	dt := &dotted
	sum: i64
	start := time.tick_now()
	switch kind {
	case .RFINDN_CALL:
		fn := godot.builtin_method(.STRING, "rfindn", 1760645412)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&quick, &last}
			r: i64
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += r
		}
	case .RFINDN:
		for _ in 0 ..< n { sum += godot.string_rfindn(intrinsics.volatile_load(&h), quick, last) }
	case .CONTAINS_CALL, .CONTAINSN_CALL, .BEGINS_CALL, .ENDS_CALL:
		method: cstring
		what: ^godot.String
		#partial switch kind {
		case .CONTAINS_CALL:  method, what = "contains", &lazy
		case .CONTAINSN_CALL: method, what = "containsn", &lazy_upper
		case .BEGINS_CALL:    method, what = "begins_with", &head
		case .ENDS_CALL:      method, what = "ends_with", &tail
		}
		fn := godot.builtin_method(.STRING, method, 2566493496)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{what}
			r: u8
			fn(intrinsics.volatile_load(&h), &args[0], &r, 1)
			sum += i64(r)
		}
	case .CONTAINS:
		for _ in 0 ..< n { sum += i64(godot.string_contains(intrinsics.volatile_load(&h), lazy)) }
	case .CONTAINSN:
		for _ in 0 ..< n { sum += i64(godot.string_containsn(intrinsics.volatile_load(&h), lazy_upper)) }
	case .COUNT_CALL, .COUNTN_CALL:
		what := &the if kind == .COUNT_CALL else &the_upper
		fn := godot.builtin_method(.STRING, "count" if kind == .COUNT_CALL else "countn", 2343087891)
		for _ in 0 ..< n {
			args := [3]gde.ConstTypePtr{what, &from, &to}
			r: i64
			fn(intrinsics.volatile_load(&h), &args[0], &r, 3)
			sum += r
		}
	case .COUNT:
		for _ in 0 ..< n { sum += godot.string_count(intrinsics.volatile_load(&h), the, from, to) }
	case .COUNTN:
		for _ in 0 ..< n { sum += godot.string_countn(intrinsics.volatile_load(&h), the_upper, from, to) }
	case .BEGINS:
		for _ in 0 ..< n { sum += i64(godot.string_begins_with(intrinsics.volatile_load(&h), head)) }
	case .ENDS:
		for _ in 0 ..< n { sum += i64(godot.string_ends_with(intrinsics.volatile_load(&h), tail)) }
	case .CASECMP_CALL:
		fn := godot.builtin_method(.STRING, "casecmp_to", 2920860731)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&same}
			r: i64
			fn(intrinsics.volatile_load(&h), &args[0], &r, 1)
			sum += r
		}
	case .CASECMP:
		for _ in 0 ..< n { sum += godot.string_casecmp_to(intrinsics.volatile_load(&h), same) }
	case .REPLACEN_CALL:
		fn := godot.builtin_method(.STRING, "replacen", 1340436205)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&the_upper, &a}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .REPLACEN:
		for _ in 0 ..< n {
			r := godot.string_replacen(intrinsics.volatile_load(&h), the_upper, a)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SUBSTR_CALL:
		fn := godot.builtin_method(.STRING, "substr", 787537301)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&slice_from, &slice_len}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SUBSTR:
		for _ in 0 ..< n {
			r := godot.string_substr(intrinsics.volatile_load(&h), slice_from, slice_len)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LEFT_CALL, .RIGHT_CALL:
		count := &left_len if kind == .LEFT_CALL else &right_len
		fn := godot.builtin_method(.STRING, "left" if kind == .LEFT_CALL else "right", 2162347432)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{count}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 1)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LEFT:
		for _ in 0 ..< n {
			r := godot.string_left(intrinsics.volatile_load(&h), left_len)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .RIGHT:
		for _ in 0 ..< n {
			r := godot.string_right(intrinsics.volatile_load(&h), right_len)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TO_UPPER_CALL, .TO_LOWER_CALL:
		fn := godot.builtin_method(.STRING, "to_upper" if kind == .TO_UPPER_CALL else "to_lower", 3942272618)
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&h), nil, &r, 0)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TO_UPPER:
		for _ in 0 ..< n {
			r := godot.string_to_upper(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TO_LOWER:
		for _ in 0 ..< n {
			r := godot.string_to_lower(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .GET_SLICE_CALL:
		fn := godot.builtin_method(.STRING, "get_slice", 3535100402)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&space, &part}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 2)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .GET_SLICE:
		for _ in 0 ..< n {
			r := godot.string_get_slice(intrinsics.volatile_load(&h), space, part)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TRIM_PREFIX_CALL, .TRIM_SUFFIX_CALL:
		other := &head if kind == .TRIM_PREFIX_CALL else &tail
		fn := godot.builtin_method(.STRING, "trim_prefix" if kind == .TRIM_PREFIX_CALL else "trim_suffix", 3134094431)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{other}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 1)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TRIM_PREFIX:
		for _ in 0 ..< n {
			r := godot.string_trim_prefix(intrinsics.volatile_load(&h), head)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .TRIM_SUFFIX:
		for _ in 0 ..< n {
			r := godot.string_trim_suffix(intrinsics.volatile_load(&h), tail)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .STRIP_EDGES_CALL:
		fn := godot.builtin_method(.STRING, "strip_edges", 907855311)
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&both, &both}
			r: godot.String
			fn(intrinsics.volatile_load(&p), &args[0], &r, 2)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .STRIP_EDGES:
		for _ in 0 ..< n {
			r := godot.string_strip_edges(intrinsics.volatile_load(&p), both, both)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LSTRIP_CALL, .RSTRIP_CALL:
		set := &the_set if kind == .LSTRIP_CALL else &dog_set
		fn := godot.builtin_method(.STRING, "lstrip" if kind == .LSTRIP_CALL else "rstrip", 3134094431)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{set}
			r: godot.String
			fn(intrinsics.volatile_load(&h), &args[0], &r, 1)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LSTRIP:
		for _ in 0 ..< n {
			r := godot.string_lstrip(intrinsics.volatile_load(&h), the_set)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .RSTRIP:
		for _ in 0 ..< n {
			r := godot.string_rstrip(intrinsics.volatile_load(&h), dog_set)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .CAPITALIZE_CALL, .CAMEL_CALL, .PASCAL_CALL, .SNAKE_CALL, .KEBAB_CALL:
		name: cstring
		#partial switch kind {
		case .CAPITALIZE_CALL: name = "capitalize"
		case .CAMEL_CALL: name = "to_camel_case"
		case .PASCAL_CALL: name = "to_pascal_case"
		case .SNAKE_CALL: name = "to_snake_case"
		case .KEBAB_CALL: name = "to_kebab_case"
		}
		fn := godot.builtin_method(.STRING, name, 3942272618)
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&h), nil, &r, 0)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .CAPITALIZE:
		for _ in 0 ..< n {
			r := godot.string_capitalize(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .CAMEL:
		for _ in 0 ..< n {
			r := godot.string_to_camel_case(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .PASCAL:
		for _ in 0 ..< n {
			r := godot.string_to_pascal_case(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SNAKE:
		for _ in 0 ..< n {
			r := godot.string_to_snake_case(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .KEBAB:
		for _ in 0 ..< n {
			r := godot.string_to_kebab_case(intrinsics.volatile_load(&h))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .NATURAL_CALL, .NATURALN_CALL, .FILECMP_CALL, .FILECMPN_CALL:
		name: cstring
		#partial switch kind {
		case .NATURAL_CALL: name = "naturalcasecmp_to"
		case .NATURALN_CALL: name = "naturalnocasecmp_to"
		case .FILECMP_CALL: name = "filecasecmp_to"
		case .FILECMPN_CALL: name = "filenocasecmp_to"
		}
		fn := godot.builtin_method(.STRING, name, 2920860731)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&numbered_to}
			r: i64
			fn(intrinsics.volatile_load(&nu), &args[0], &r, 1)
			sum += r
		}
	case .NATURAL:
		for _ in 0 ..< n { sum += godot.string_naturalcasecmp_to(intrinsics.volatile_load(&nu), numbered_to) }
	case .NATURALN:
		for _ in 0 ..< n { sum += godot.string_naturalnocasecmp_to(intrinsics.volatile_load(&nu), numbered_to) }
	case .FILECMP:
		for _ in 0 ..< n { sum += godot.string_filecasecmp_to(intrinsics.volatile_load(&nu), numbered_to) }
	case .FILECMPN:
		for _ in 0 ..< n { sum += godot.string_filenocasecmp_to(intrinsics.volatile_load(&nu), numbered_to) }
	case .SIMPLIFY_CALL, .SIMPLIFY_SAME_CALL:
		fn := godot.builtin_method(.STRING, "simplify_path", 3942272618)
		p := dt if kind == .SIMPLIFY_CALL else sc
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&p), nil, &r, 0)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .SIMPLIFY, .SIMPLIFY_SAME:
		p := dt if kind == .SIMPLIFY else sc
		for _ in 0 ..< n {
			r := godot.string_simplify_path(intrinsics.volatile_load(&p))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .PATH_JOIN_CALL:
		fn := godot.builtin_method(.STRING, "path_join", 3134094431)
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&leaf}
			r: godot.String
			fn(intrinsics.volatile_load(&d), &args[0], &r, 1)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .PATH_JOIN:
		for _ in 0 ..< n {
			r := godot.string_path_join(intrinsics.volatile_load(&d), leaf)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .REPEAT_CALL, .REVERSE_CALL, .INSERT_CALL, .ERASE_CALL, .REPLACE_CHAR_CALL, .REMOVE_CHAR_CALL, .REPLACE_CHARS_CALL,
	     .REMOVE_CHARS_CALL, .REMOVE_CHARS_LONG_CALL, .REMOVE_CHAR_LONG_CALL:
		x, y: i64 = 6, 7
		args := [2]gde.ConstTypePtr{&x, &y}
		name: cstring
		hash: i64
		argc: i32
		#partial switch kind {
		case .REPEAT_CALL: name, hash, argc, x = "repeat", 2162347432, 1, 4
		case .REVERSE_CALL: name, hash, argc = "reverse", 3942272618, 0
		case .INSERT_CALL:
			name, hash, argc = "insert", 248737229, 2
			args[1] = &leaf
		case .ERASE_CALL: name, hash, argc = "erase", 787537301, 2
		case .REPLACE_CHAR_CALL: name, hash, argc, x, y = "replace_char", 787537301, 2, '/', '\\'
		case .REMOVE_CHAR_CALL, .REMOVE_CHAR_LONG_CALL: name, hash, argc, x = "remove_char", 2162347432, 1, '/'
		case .REPLACE_CHARS_CALL:
			name, hash, argc, y = "replace_chars", 3535100402, 2, '-'
			args[0] = &keys
		case .REMOVE_CHARS_CALL, .REMOVE_CHARS_LONG_CALL:
			name, hash, argc = "remove_chars", 3134094431, 1
			args[0] = &keys
		}
		fn := godot.builtin_method(.STRING, name, hash)
		text := &long if kind == .REMOVE_CHARS_LONG_CALL || kind == .REMOVE_CHAR_LONG_CALL else sc
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&text), &args[0], &r, argc)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .REPEAT, .REVERSE, .INSERT, .ERASE, .REPLACE_CHAR, .REMOVE_CHAR, .REPLACE_CHARS, .REMOVE_CHARS, .REMOVE_CHARS_LONG,
	     .REMOVE_CHAR_LONG:
		text := &long if kind == .REMOVE_CHARS_LONG || kind == .REMOVE_CHAR_LONG else sc
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.String
			#partial switch kind {
			case .REPEAT: r = godot.string_repeat(s, 4)
			case .REVERSE: r = godot.string_reverse(s)
			case .INSERT: r = godot.string_insert(s, 6, leaf)
			case .ERASE: r = godot.string_erase(s, 6, 7)
			case .REPLACE_CHAR: r = godot.string_replace_char(s, '/', '\\')
			case .REMOVE_CHAR, .REMOVE_CHAR_LONG: r = godot.string_remove_char(s, '/')
			case .REPLACE_CHARS: r = godot.string_replace_chars(s, keys, '-')
			case .REMOVE_CHARS, .REMOVE_CHARS_LONG: r = godot.string_remove_chars(s, keys)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .INDENT_CALL, .DEDENT_CALL, .STRIP_ESCAPES_CALL, .GET_SLICEC_CALL, .INDENT_LONG_CALL, .DEDENT_LONG_CALL,
	     .STRIP_ESCAPES_LONG_CALL:
		x, y: i64 = '/', 3
		args := [2]gde.ConstTypePtr{&x, &y}
		name: cstring = "get_slicec"
		hash: i64 = 787537301
		argc: i32 = 2
		text := sc
		#partial switch kind {
		case .INDENT_CALL, .INDENT_LONG_CALL: name, hash, argc, args[0] = "indent", 3134094431, 1, &tab
		case .DEDENT_CALL, .DEDENT_LONG_CALL: name, hash, argc = "dedent", 3942272618, 0
		case .STRIP_ESCAPES_CALL, .STRIP_ESCAPES_LONG_CALL: name, hash, argc = "strip_escapes", 3942272618, 0
		}
		#partial switch kind {
		case .INDENT_CALL, .DEDENT_CALL, .STRIP_ESCAPES_CALL: text = &code
		case .INDENT_LONG_CALL, .DEDENT_LONG_CALL, .STRIP_ESCAPES_LONG_CALL: text = &code_long
		}
		fn := godot.builtin_method(.STRING, name, hash)
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&text), &args[0], &r, argc)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .INDENT, .DEDENT, .STRIP_ESCAPES, .GET_SLICEC, .INDENT_LONG, .DEDENT_LONG, .STRIP_ESCAPES_LONG:
		text := sc
		#partial switch kind {
		case .INDENT, .DEDENT, .STRIP_ESCAPES: text = &code
		case .INDENT_LONG, .DEDENT_LONG, .STRIP_ESCAPES_LONG: text = &code_long
		}
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.String
			#partial switch kind {
			case .INDENT, .INDENT_LONG: r = godot.string_indent(s, tab)
			case .DEDENT, .DEDENT_LONG: r = godot.string_dedent(s)
			case .STRIP_ESCAPES, .STRIP_ESCAPES_LONG: r = godot.string_strip_escapes(s)
			case .GET_SLICEC: r = godot.string_get_slicec(s, '/', 3)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .BIGRAMS_CALL:
		fn := godot.builtin_method(.STRING, "bigrams", 747180633)
		text := &leaf
		for _ in 0 ..< n {
			r: godot.PackedStringArray
			fn(intrinsics.volatile_load(&text), nil, &r, 0)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .BIGRAMS:
		text := &leaf
		for _ in 0 ..< n {
			r := godot.string_bigrams(intrinsics.volatile_load(&text))
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .SIMILARITY_CALL:
		fn := godot.builtin_method(.STRING, "similarity", 2697460964)
		text := sc
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&leaf}
			r: f64
			fn(intrinsics.volatile_load(&text), &args[0], &r, 1)
			sum += i64(r * 100)
		}
	case .SIMILARITY:
		text := sc
		for _ in 0 ..< n { sum += i64(godot.string_similarity(intrinsics.volatile_load(&text), leaf) * 100) }
	case .VALIDATE_NODE_CALL, .VALIDATE_NODE, .VALIDATE_NODE_BAD_CALL, .VALIDATE_NODE_BAD, .VALIDATE_FILE_CALL, .VALIDATE_FILE:
		source := "PlayerCharacter2D"
		name: cstring = "validate_node_name"
		#partial switch kind {
		case .VALIDATE_NODE_BAD_CALL, .VALIDATE_NODE_BAD: source = "Player.Body:1"
		case .VALIDATE_FILE_CALL, .VALIDATE_FILE: source, name = " my file: draft?.txt ", "validate_filename"
		}
		subject := godot.string_of(source)
		defer godot.destroy[.STRING](&subject)
		text := &subject
		fn := godot.builtin_method(.STRING, name, 3942272618)
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.String
			#partial switch kind {
			case .VALIDATE_NODE, .VALIDATE_NODE_BAD: r = godot.string_validate_node_name(s)
			case .VALIDATE_FILE: r = godot.string_validate_filename(s)
			case: fn(s, nil, &r, 0)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .NUM_INT_CALL, .NUM_INT, .NUM_UINT_CALL, .NUM_UINT:
		v, base, caps := i64(-1234567), i64(16), u8(0)
		args := [3]gde.ConstTypePtr{&v, &base, &caps}
		unsigned := kind == .NUM_UINT_CALL || kind == .NUM_UINT
		fn := godot.builtin_method(.STRING, "num_uint64" if unsigned else "num_int64", 2111271071)
		for _ in 0 ..< n {
			r: godot.String
			#partial switch kind {
			case .NUM_INT: r = godot.string_num_int64(intrinsics.volatile_load(&v), intrinsics.volatile_load(&base), false)
			case .NUM_UINT: r = godot.string_num_uint64(intrinsics.volatile_load(&v), intrinsics.volatile_load(&base), false)
			case: fn(nil, &args[0], &r, 3)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .NUM_CALL, .NUM:
		v, places := -123.456, i64(-1)
		args := [2]gde.ConstTypePtr{&v, &places}
		fn := godot.builtin_method(.STRING, "num", 1555901022)
		for _ in 0 ..< n {
			r: godot.String
			if kind == .NUM {
				r = godot.string_num(intrinsics.volatile_load(&v), intrinsics.volatile_load(&places))
			} else {
				fn(nil, &args[0], &r, 2)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .C_ESCAPE_CALL, .C_ESCAPE, .JSON_ESCAPE_CALL, .JSON_ESCAPE, .XML_ESCAPE_CALL, .XML_ESCAPE, .C_UNESCAPE_CALL,
	     .C_UNESCAPE, .XML_UNESCAPE_CALL, .XML_UNESCAPE, .URI_ENCODE_CALL, .URI_ENCODE, .URI_DECODE_CALL, .URI_DECODE,
	     .URI_FILE_DECODE_CALL, .URI_FILE_DECODE:
		source := "a line\twith \"quotes\" and a \\ in it\n"
		name: cstring = "c_escape"
		#partial switch kind {
		case .JSON_ESCAPE_CALL, .JSON_ESCAPE: name = "json_escape"
		case .XML_ESCAPE_CALL, .XML_ESCAPE: source, name = "<a href=\"x\">Tom & Jerry's</a>", "xml_escape"
		case .C_UNESCAPE_CALL, .C_UNESCAPE: source, name = "a line\\twith \\\"quotes\\\" and a \\\\ in it\\n", "c_unescape"
		case .XML_UNESCAPE_CALL, .XML_UNESCAPE:
			source, name = "&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;", "xml_unescape"
		case .URI_ENCODE_CALL, .URI_ENCODE: source, name = "a file name (1) \u00e9.txt", "uri_encode"
		case .URI_DECODE_CALL, .URI_DECODE: source, name = "a%20file%20name%20%281%29%20%C3%A9.txt", "uri_decode"
		case .URI_FILE_DECODE_CALL, .URI_FILE_DECODE:
			source, name = "a%20file%20name%20%281%29%20%C3%A9.txt", "uri_file_decode"
		}
		subject := godot.string_of(source)
		defer godot.destroy[.STRING](&subject)
		text := &subject
		quotes := u8(1)
		args := [1]gde.ConstTypePtr{&quotes}
		fn: gde.PtrBuiltInMethod
		argc := i32(0)
		if kind == .XML_ESCAPE_CALL || kind == .XML_ESCAPE {
			fn, argc = godot.builtin_method(.STRING, name, 3429816538), 1
		} else {
			fn = godot.builtin_method(.STRING, name, 3942272618)
		}
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.String
			#partial switch kind {
			case .C_ESCAPE: r = godot.string_c_escape(s)
			case .JSON_ESCAPE: r = godot.string_json_escape(s)
			case .XML_ESCAPE: r = godot.string_xml_escape(s, true)
			case .C_UNESCAPE: r = godot.string_c_unescape(s)
			case .XML_UNESCAPE: r = godot.string_xml_unescape(s)
			case .URI_ENCODE: r = godot.string_uri_encode(s)
			case .URI_DECODE: r = godot.string_uri_decode(s)
			case .URI_FILE_DECODE: r = godot.string_uri_file_decode(s)
			case: fn(s, &args[0], &r, argc)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .HEX_DECODE_CALL, .HEX_DECODE, .ASCII_BUFFER_CALL, .ASCII_BUFFER, .UTF8_BUFFER_CALL, .UTF8_BUFFER, .UTF16_BUFFER_CALL,
	     .UTF16_BUFFER, .UTF32_BUFFER_CALL, .UTF32_BUFFER, .WCHAR_BUFFER_CALL, .WCHAR_BUFFER:
		source := "a line of text, na\u00efve \u65e5\u672c"
		name: cstring = "to_utf8_buffer"
		#partial switch kind {
		case .HEX_DECODE_CALL, .HEX_DECODE: source, name = "00112233445566778899aAbB", "hex_decode"
		case .ASCII_BUFFER_CALL, .ASCII_BUFFER: source, name = "a line of text, as ASCII", "to_ascii_buffer"
		case .UTF16_BUFFER_CALL, .UTF16_BUFFER: name = "to_utf16_buffer"
		case .UTF32_BUFFER_CALL, .UTF32_BUFFER: name = "to_utf32_buffer"
		case .WCHAR_BUFFER_CALL, .WCHAR_BUFFER: name = "to_wchar_buffer"
		}
		subject := godot.string_of(source)
		defer godot.destroy[.STRING](&subject)
		text := &subject
		fn := godot.builtin_method(.STRING, name, 247621236)
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.PackedByteArray
			#partial switch kind {
			case .HEX_DECODE: r = godot.string_hex_decode(s)
			case .ASCII_BUFFER: r = godot.string_to_ascii_buffer(s)
			case .UTF8_BUFFER: r = godot.string_to_utf8_buffer(s)
			case .UTF16_BUFFER: r = godot.string_to_utf16_buffer(s)
			case .UTF32_BUFFER: r = godot.string_to_utf32_buffer(s)
			case .WCHAR_BUFFER: r = godot.string_to_wchar_buffer(s)
			case: fn(s, nil, &r, 0)
			}
			sum += godot.packed_stored_size(&r)
			godot.destroy[.PACKED_BYTE_ARRAY](&r)
		}
	case .BYTES_ASCII_CALL, .BYTES_ASCII, .BYTES_UTF8_CALL, .BYTES_UTF8, .BYTES_UTF16_CALL, .BYTES_UTF16, .BYTES_UTF32_CALL,
	     .BYTES_UTF32, .BYTES_WCHAR_CALL, .BYTES_WCHAR, .BYTES_HEX_CALL, .BYTES_HEX:
		line := godot.string_of("a line of text, na\u00efve \u65e5\u672c")
		defer godot.destroy[.STRING](&line)
		subject: godot.PackedByteArray
		name: cstring
		#partial switch kind {
		case .BYTES_ASCII_CALL, .BYTES_ASCII:
			plain := godot.string_of("a line of text, as ASCII")
			subject, name = godot.string_to_ascii_buffer(&plain), "get_string_from_ascii"
			godot.destroy[.STRING](&plain)
		case .BYTES_UTF8_CALL, .BYTES_UTF8: subject, name = godot.string_to_utf8_buffer(&line), "get_string_from_utf8"
		case .BYTES_UTF16_CALL, .BYTES_UTF16: subject, name = godot.string_to_utf16_buffer(&line), "get_string_from_utf16"
		case .BYTES_UTF32_CALL, .BYTES_UTF32: subject, name = godot.string_to_utf32_buffer(&line), "get_string_from_utf32"
		case .BYTES_WCHAR_CALL, .BYTES_WCHAR: subject, name = godot.string_to_wchar_buffer(&line), "get_string_from_wchar"
		case:
			digits := godot.string_of("00112233445566778899aAbB")
			subject, name = godot.string_hex_decode(&digits), "hex_encode"
			godot.destroy[.STRING](&digits)
		}
		defer godot.destroy[.PACKED_BYTE_ARRAY](&subject)
		bytes := &subject
		fn := godot.builtin_method(.PACKED_BYTE_ARRAY, name, 3942272618)
		for _ in 0 ..< n {
			a := intrinsics.volatile_load(&bytes)
			r: godot.String
			#partial switch kind {
			case .BYTES_ASCII: r = godot.packed_byte_array_get_string_from_ascii(a)
			case .BYTES_UTF8: r = godot.packed_byte_array_get_string_from_utf8(a)
			case .BYTES_UTF16: r = godot.packed_byte_array_get_string_from_utf16(a)
			case .BYTES_UTF32: r = godot.packed_byte_array_get_string_from_utf32(a)
			case .BYTES_WCHAR: r = godot.packed_byte_array_get_string_from_wchar(a)
			case .BYTES_HEX: r = godot.packed_byte_array_hex_encode(a)
			case: fn(a, nil, &r, 0)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .NUM_SCI_CALL, .NUM_SCI:
		v := -123.456
		args := [1]gde.ConstTypePtr{&v}
		fn := godot.builtin_method(.STRING, "num_scientific", 2710373411)
		for _ in 0 ..< n {
			r: godot.String
			if kind == .NUM_SCI {
				r = godot.string_num_scientific(intrinsics.volatile_load(&v))
			} else {
				fn(nil, &args[0], &r, 1)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .CHR_CALL, .CHR:
		code := i64(0xE9)
		args := [1]gde.ConstTypePtr{&code}
		fn := godot.builtin_method(.STRING, "chr", 897497541)
		for _ in 0 ..< n {
			r: godot.String
			if kind == .CHR {
				r = godot.string_chr(intrinsics.volatile_load(&code))
			} else {
				fn(nil, &args[0], &r, 1)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .UNICODE_ID_CALL, .UNICODE_ID:
		subject := godot.string_of("héllo_wörld2")
		defer godot.destroy[.STRING](&subject)
		text := &subject
		fn := godot.builtin_method(.STRING, "is_valid_unicode_identifier", 3918633141)
		for _ in 0 ..< n {
			if kind == .UNICODE_ID_CALL {
				r: u8
				fn(intrinsics.volatile_load(&text), nil, &r, 0)
				sum += i64(r)
			} else {
				sum += i64(godot.string_is_valid_unicode_identifier(intrinsics.volatile_load(&text)))
			}
		}
	case .RSPLIT_CALL:
		allow_empty, maxsplit := u8(1), i64(0)
		fn := godot.builtin_method(.STRING, "rsplit", 1252735785)
		for _ in 0 ..< n {
			args := [3]gde.ConstTypePtr{&space, &allow_empty, &maxsplit}
			r: godot.PackedStringArray
			fn(intrinsics.volatile_load(&h), &args[0], &r, 3)
			sum += godot.packed_string_array_size(&r)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .RSPLIT:
		for _ in 0 ..< n {
			r := godot.string_rsplit(intrinsics.volatile_load(&h), space, true, 0)
			sum += godot.packed_string_array_size(&r)
			godot.destroy[.PACKED_STRING_ARRAY](&r)
		}
	case .SPLIT_FLOATS_CALL, .SPLIT_FLOATS:
		numbers, comma := godot.string_of("1.5,2,3.25,-4e2,0.125"), godot.string_of(",")
		defer godot.destroy[.STRING](&numbers)
		defer godot.destroy[.STRING](&comma)
		text := &numbers
		allow_empty := u8(1)
		fn := godot.builtin_method(.STRING, "split_floats", 2092079095)
		for _ in 0 ..< n {
			r: godot.PackedFloat64Array
			if kind == .SPLIT_FLOATS_CALL {
				args := [2]gde.ConstTypePtr{&comma, &allow_empty}
				fn(intrinsics.volatile_load(&text), &args[0], &r, 2)
			} else {
				r = godot.string_split_floats(intrinsics.volatile_load(&text), comma, true)
			}
			sum += godot.packed_float64_array_size(&r)
			godot.destroy[.PACKED_FLOAT64_ARRAY](&r)
		}
	case .JOIN_CALL, .JOIN:
		words, between := godot.string_split(h, space, true, 0), godot.string_of(", ")
		defer godot.destroy[.PACKED_STRING_ARRAY](&words)
		defer godot.destroy[.STRING](&between)
		text := &between
		fn := godot.builtin_method(.STRING, "join", 3595973238)
		for _ in 0 ..< n {
			r: godot.String
			if kind == .JOIN_CALL {
				args := [1]gde.ConstTypePtr{&words}
				fn(intrinsics.volatile_load(&text), &args[0], &r, 1)
			} else {
				r = godot.string_join(intrinsics.volatile_load(&text), words)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LPAD_CALL, .RPAD_CALL, .PAD_ZEROS_CALL, .PAD_DECIMALS_CALL:
		x: i64 = 10
		args := [2]gde.ConstTypePtr{&x, &zero}
		name: cstring
		hash: i64 = 248737229
		argc: i32 = 2
		#partial switch kind {
		case .LPAD_CALL: name = "lpad"
		case .RPAD_CALL: name = "rpad"
		case .PAD_ZEROS_CALL: name, hash, argc, x = "pad_zeros", 2162347432, 1, 6
		case .PAD_DECIMALS_CALL: name, hash, argc, x = "pad_decimals", 2162347432, 1, 4
		}
		fn := godot.builtin_method(.STRING, name, hash)
		text := &number
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&text), &args[0], &r, argc)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .LPAD, .RPAD, .PAD_ZEROS, .PAD_DECIMALS:
		text := &number
		for _ in 0 ..< n {
			s := intrinsics.volatile_load(&text)
			r: godot.String
			#partial switch kind {
			case .LPAD: r = godot.string_lpad(s, 10, zero)
			case .RPAD: r = godot.string_rpad(s, 10, zero)
			case .PAD_ZEROS: r = godot.string_pad_zeros(s, 6)
			case .PAD_DECIMALS: r = godot.string_pad_decimals(s, 4)
			}
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .EXTENSION_CALL, .BASENAME_CALL, .FILE_CALL, .BASE_DIR_CALL:
		name: cstring
		#partial switch kind {
		case .EXTENSION_CALL: name = "get_extension"
		case .BASENAME_CALL: name = "get_basename"
		case .FILE_CALL: name = "get_file"
		case .BASE_DIR_CALL: name = "get_base_dir"
		}
		fn := godot.builtin_method(.STRING, name, 3942272618)
		for _ in 0 ..< n {
			r: godot.String
			fn(intrinsics.volatile_load(&sc), nil, &r, 0)
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .EXTENSION:
		for _ in 0 ..< n {
			r := godot.string_get_extension(intrinsics.volatile_load(&sc))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .BASENAME:
		for _ in 0 ..< n {
			r := godot.string_get_basename(intrinsics.volatile_load(&sc))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .FILE:
		for _ in 0 ..< n {
			r := godot.string_get_file(intrinsics.volatile_load(&sc))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	case .BASE_DIR:
		for _ in 0 ..< n {
			r := godot.string_get_base_dir(intrinsics.volatile_load(&sc))
			sum += godot.string_stored_length(&r)
			godot.destroy[.STRING](&r)
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The Quaternion methods `quaternion_ns` times, paired the same way as Vector_Op.
Quaternion_Op :: enum i64 {
	SLERP_CALL,     // the engine's Quaternion.slerp at weight 0.25
	SLERP,          // quaternion_slerp at weight 0.25
	CUBIC_CALL,     // the engine's Quaternion.spherical_cubic_interpolate at weight 0.25
	CUBIC,          // quaternion_spherical_cubic_interpolate at weight 0.25
	GET_EULER_CALL, // the engine's Quaternion.get_euler in YXZ order
	GET_EULER,      // quaternion_get_euler in YXZ order
	INVERSE_CALL,   // the engine's Quaternion.inverse
	INVERSE,        // quaternion_inverse
	LOG_CALL,       // the engine's Quaternion.log
	LOG,            // quaternion_log
	EXP_CALL,       // the engine's Quaternion.exp of that logarithm
	EXP,            // quaternion_exp of the same
	CUBIC_TIME_CALL, // the engine's Quaternion.spherical_cubic_interpolate_in_time at weight 0.25
	CUBIC_TIME,     // quaternion_spherical_cubic_interpolate_in_time at weight 0.25
}

// Nanoseconds per `kind` round on a unit quaternion reread through a volatile load each round, as
// in vector_ns.
quaternion_ns :: proc(self: ^Bench, kind: Quaternion_Op, n: i64) -> f64 {
	a := godot.quaternion_from_euler(godot.Vector3{0.3, -1.2, 2.0})
	b := godot.quaternion_from_euler(godot.Vector3{-0.7, 0.4, 1.1})
	pre := godot.quaternion_from_euler(godot.Vector3{0.1, -1.0, 2.4})
	post := godot.quaternion_from_euler(godot.Vector3{-0.9, 0.6, 0.8})
	weight := f64(0.25)
	order := i64(2)
	ref := &a
	slerp_fn := godot.builtin_method(.QUATERNION, "slerp", 1773590316)
	cubic_fn := godot.builtin_method(.QUATERNION, "spherical_cubic_interpolate", 2150967576)
	euler_fn := godot.builtin_method(.QUATERNION, "get_euler", 1394941017)
	inverse_fn := godot.builtin_method(.QUATERNION, "inverse", 4274879941)
	ln := godot.quaternion_log(&a)
	b_t, pre_t, post_t := f64(0.1), f64(-0.1), f64(0.2)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .SLERP_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&b, &weight}
			r: godot.Quaternion
			slerp_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += r.x
		}
	case .SLERP:
		for _ in 0 ..< n { sum += godot.quaternion_slerp(intrinsics.volatile_load(&ref), b, weight).x }
	case .CUBIC_CALL:
		for _ in 0 ..< n {
			args := [4]gde.ConstTypePtr{&b, &pre, &post, &weight}
			r: godot.Quaternion
			cubic_fn(intrinsics.volatile_load(&ref), &args[0], &r, 4)
			sum += r.x
		}
	case .CUBIC:
		for _ in 0 ..< n { sum += godot.quaternion_spherical_cubic_interpolate(intrinsics.volatile_load(&ref), b, pre, post, weight).x }
	case .GET_EULER_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&order}
			r: godot.Vector3
			euler_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.x
		}
	case .GET_EULER:
		for _ in 0 ..< n { sum += godot.quaternion_get_euler(intrinsics.volatile_load(&ref), order).x }
	case .INVERSE_CALL:
		for _ in 0 ..< n {
			r: godot.Quaternion
			inverse_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.x
		}
	case .INVERSE:
		for _ in 0 ..< n { sum += godot.quaternion_inverse(intrinsics.volatile_load(&ref)).x }
	case .LOG_CALL, .EXP_CALL:
		if kind == .EXP_CALL { ref = &ln }
		fn := godot.builtin_method(.QUATERNION, "log" if kind == .LOG_CALL else "exp", 4274879941)
		for _ in 0 ..< n {
			r: godot.Quaternion
			fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.x
		}
	case .LOG:
		for _ in 0 ..< n { sum += godot.quaternion_log(intrinsics.volatile_load(&ref)).x }
	case .EXP:
		ref = &ln
		for _ in 0 ..< n { sum += godot.quaternion_exp(intrinsics.volatile_load(&ref)).x }
	case .CUBIC_TIME_CALL:
		fn := godot.builtin_method(.QUATERNION, "spherical_cubic_interpolate_in_time", 1436023539)
		for _ in 0 ..< n {
			args := [7]gde.ConstTypePtr{&b, &pre, &post, &weight, &b_t, &pre_t, &post_t}
			r: godot.Quaternion
			fn(intrinsics.volatile_load(&ref), &args[0], &r, 7)
			sum += r.x
		}
	case .CUBIC_TIME:
		for _ in 0 ..< n {
			sum += godot.quaternion_spherical_cubic_interpolate_in_time(intrinsics.volatile_load(&ref), b, pre, post, weight, b_t, pre_t, post_t).x
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The Plane methods `plane_ns` times, paired the same way as Vector_Op.
Plane_Op :: enum i64 {
	NORMALIZED_CALL,     // the engine's Plane.normalized
	NORMALIZED,          // plane_normalized
	DISTANCE_TO_CALL,    // the engine's Plane.distance_to
	DISTANCE_TO,         // plane_distance_to
	INTERSECT_3_CALL,    // the engine's Plane.intersect_3
	INTERSECT_3,         // plane_intersect_3
	INTERSECTS_RAY_CALL, // the engine's Plane.intersects_ray
	INTERSECTS_RAY,      // plane_intersects_ray
}

// Nanoseconds per `kind` round on a plane reread through a volatile load each round, as in
// vector_ns. The intersections hit, so each returns a Vector3 Variant.
plane_ns :: proc(self: ^Bench, kind: Plane_Op, n: i64) -> f64 {
	a := godot.Plane{{0.48, 0.6, 0.64}, 1.5}
	b := godot.Plane{{0, 1, 0}, -0.5}
	c := godot.Plane{{0.6, 0, -0.8}, 0.25}
	point := godot.Vector3{0.3, -1.2, 2.0}
	dir := -a.normal
	ref := &a
	normalized_fn := godot.builtin_method(.PLANE, "normalized", 1051796340)
	distance_fn := godot.builtin_method(.PLANE, "distance_to", 1047977935)
	intersect_fn := godot.builtin_method(.PLANE, "intersect_3", 2012052692)
	ray_fn := godot.builtin_method(.PLANE, "intersects_ray", 2048133369)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .NORMALIZED_CALL:
		for _ in 0 ..< n {
			r: godot.Plane
			normalized_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.d
		}
	case .NORMALIZED:
		for _ in 0 ..< n { sum += godot.plane_normalized(intrinsics.volatile_load(&ref)).d }
	case .DISTANCE_TO_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&point}
			r: f64
			distance_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(r)
		}
	case .DISTANCE_TO:
		for _ in 0 ..< n { sum += f32(godot.plane_distance_to(intrinsics.volatile_load(&ref), point)) }
	case .INTERSECT_3_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&b, &c}
			r: godot.Variant
			intersect_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += f32(r._opaque[8])
		}
	case .INTERSECT_3:
		for _ in 0 ..< n {
			r := godot.plane_intersect_3(intrinsics.volatile_load(&ref), b, c)
			sum += f32(r._opaque[8])
		}
	case .INTERSECTS_RAY_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&point, &dir}
			r: godot.Variant
			ray_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += f32(r._opaque[8])
		}
	case .INTERSECTS_RAY:
		for _ in 0 ..< n {
			r := godot.plane_intersects_ray(intrinsics.volatile_load(&ref), point, dir)
			sum += f32(r._opaque[8])
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The AABB methods `aabb_ns` times, paired the same way as Vector_Op.
AABB_Op :: enum i64 {
	MERGE_CALL,            // the engine's AABB.merge
	MERGE,                 // aabb_merge
	INTERSECTS_CALL,       // the engine's AABB.intersects
	INTERSECTS,            // aabb_intersects
	INTERSECTS_PLANE_CALL, // the engine's AABB.intersects_plane
	INTERSECTS_PLANE,      // aabb_intersects_plane
	INTERSECTS_RAY_CALL,   // the engine's AABB.intersects_ray
	INTERSECTS_RAY,        // aabb_intersects_ray
}

// Nanoseconds per `kind` round on a box reread through a volatile load each round, as in
// vector_ns. The tests all pass, and the ray hits from outside, so it returns a Vector3 Variant.
aabb_ns :: proc(self: ^Bench, kind: AABB_Op, n: i64) -> f64 {
	a := godot.AABB{{-1, -2, -3}, {2, 4, 6}}
	b := godot.AABB{{0.5, 0.5, 0.5}, {3, 1, 2}}
	plane := godot.Plane{{0.48, 0.6, 0.64}, 0.5}
	from := godot.Vector3{-4, 0.5, 1}
	dir := godot.Vector3{1, 0.1, -0.2}
	ref := &a
	merge_fn := godot.builtin_method(.AABB, "merge", 1271470306)
	intersects_fn := godot.builtin_method(.AABB, "intersects", 299946684)
	plane_fn := godot.builtin_method(.AABB, "intersects_plane", 1150170233)
	ray_fn := godot.builtin_method(.AABB, "intersects_ray", 2048133369)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .MERGE_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&b}
			r: godot.AABB
			merge_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.size.x
		}
	case .MERGE:
		for _ in 0 ..< n { sum += godot.aabb_merge(intrinsics.volatile_load(&ref), b).size.x }
	case .INTERSECTS_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&b}
			r: bool
			intersects_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(int(r))
		}
	case .INTERSECTS:
		for _ in 0 ..< n { sum += f32(int(godot.aabb_intersects(intrinsics.volatile_load(&ref), b))) }
	case .INTERSECTS_PLANE_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&plane}
			r: bool
			plane_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(int(r))
		}
	case .INTERSECTS_PLANE:
		for _ in 0 ..< n { sum += f32(int(godot.aabb_intersects_plane(intrinsics.volatile_load(&ref), plane))) }
	case .INTERSECTS_RAY_CALL:
		for _ in 0 ..< n {
			args := [2]gde.ConstTypePtr{&from, &dir}
			r: godot.Variant
			ray_fn(intrinsics.volatile_load(&ref), &args[0], &r, 2)
			sum += f32(r._opaque[8])
		}
	case .INTERSECTS_RAY:
		for _ in 0 ..< n {
			r := godot.aabb_intersects_ray(intrinsics.volatile_load(&ref), from, dir)
			sum += f32(r._opaque[8])
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The Rect2 and Rect2i methods `rect2_ns` times, paired the same way as Vector_Op.
Rect2_Op :: enum i64 {
	HAS_POINT_CALL,      // the engine's Rect2.has_point
	HAS_POINT,           // rect2_has_point
	INTERSECTION_CALL,   // the engine's Rect2.intersection
	INTERSECTION,        // rect2_intersection
	MERGE_CALL,          // the engine's Rect2.merge
	MERGE,               // rect2_merge
	I_INTERSECTION_CALL, // the engine's Rect2i.intersection
	I_INTERSECTION,      // rect2i_intersection
}

// Nanoseconds per `kind` round on a rect reread through a volatile load each round, as in
// vector_ns. The point lies inside and the rects overlap, so every test passes.
rect2_ns :: proc(self: ^Bench, kind: Rect2_Op, n: i64) -> f64 {
	a := godot.Rect2{{-1, -2}, {2, 4}}
	b := godot.Rect2{{0.5, 0.5}, {3, 1}}
	ai := godot.Rect2i{{-1, -2}, {2, 4}}
	bi := godot.Rect2i{{0, 1}, {3, 1}}
	point := godot.Vector2{0.25, 1}
	ref, refi := &a, &ai
	has_point_fn := godot.builtin_method(.RECT2, "has_point", 3190634762)
	intersection_fn := godot.builtin_method(.RECT2, "intersection", 2282977743)
	merge_fn := godot.builtin_method(.RECT2, "merge", 2282977743)
	i_intersection_fn := godot.builtin_method(.RECT2I, "intersection", 717431873)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .HAS_POINT_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&point}
			r: bool
			has_point_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += f32(int(r))
		}
	case .HAS_POINT:
		for _ in 0 ..< n { sum += f32(int(godot.rect2_has_point(intrinsics.volatile_load(&ref), point))) }
	case .INTERSECTION_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&b}
			r: godot.Rect2
			intersection_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.size.x
		}
	case .INTERSECTION:
		for _ in 0 ..< n { sum += godot.rect2_intersection(intrinsics.volatile_load(&ref), b).size.x }
	case .MERGE_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&b}
			r: godot.Rect2
			merge_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.size.x
		}
	case .MERGE:
		for _ in 0 ..< n { sum += godot.rect2_merge(intrinsics.volatile_load(&ref), b).size.x }
	case .I_INTERSECTION_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&bi}
			r: godot.Rect2i
			i_intersection_fn(intrinsics.volatile_load(&refi), &args[0], &r, 1)
			sum += f32(r.size.x)
		}
	case .I_INTERSECTION:
		for _ in 0 ..< n { sum += f32(godot.rect2i_intersection(intrinsics.volatile_load(&refi), bi).size.x) }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// The packed array reads `packed_ns` times, paired the same way as Vector_Op.
Packed_Op :: enum i64 {
	SIZE_CALL,        // the engine's PackedInt64Array.size
	SIZE,             // packed_int64_array_size
	GET_CALL,         // the engine's PackedInt64Array.get
	GET,              // packed_int64_array_get
	FIND_CALL,        // the engine's PackedInt64Array.find
	FIND,             // packed_int64_array_find
	STRING_FIND_CALL, // the engine's PackedStringArray.find
	STRING_FIND,      // packed_string_array_find
	SLICE_CALL,       // the engine's PackedInt64Array.slice of elements 8 to 40
	SLICE,            // packed_int64_array_slice of the same
	PUSH_CALL,        // the engine's PackedInt64Array.push_back within the capacity
	PUSH,             // packed_int64_array_push_back of the same
	RESIZE_CALL,      // the engine's PackedInt64Array.resize between 32 and 40 within the capacity
	RESIZE,           // packed_int64_array_resize of the same
	APPEND_ARRAY_CALL, // the engine's PackedInt64Array.append_array of 8 elements within the capacity
	APPEND_ARRAY,     // packed_int64_array_append_array of the same
}

// Nanoseconds per `kind` round on 0 to 63 in a PackedInt64Array and "0" to "15" in a
// PackedStringArray: get reads index 40, find looks for 40 and for "12", the index or value reread
// through a volatile load each round, as in vector_ns.
packed_ns :: proc(self: ^Bench, kind: Packed_Op, n: i64) -> f64 {
	xs: [64]i64
	for &x, i in xs { x = i64(i) }
	a := godot.packed_of(xs[:])
	defer godot.destroy[.PACKED_INT64_ARRAY](&a)
	words: [16]godot.String
	for &w, i in words { w = godot.string_of_int(i64(i)) }
	sa := godot.packed_of(words[:])
	defer godot.destroy[.PACKED_STRING_ARRAY](&sa)
	for &w in words { godot.destroy[.STRING](&w) }
	key := godot.string_of_int(12)
	defer godot.destroy[.STRING](&key)
	ref := &a
	at, from := i64(40), i64(0)
	size_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "size", 3173160232)
	get_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "get", 4103005248)
	find_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "find", 2984303840)
	string_find_fn := godot.builtin_method(.PACKED_STRING_ARRAY, "find", 1760645412)
	sum: i64
	start := time.tick_now()
	switch kind {
	case .SIZE_CALL:
		for _ in 0 ..< n {
			r: i64
			size_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r
		}
	case .SIZE:
		for _ in 0 ..< n { sum += godot.packed_int64_array_size(intrinsics.volatile_load(&ref)) }
	case .GET_CALL:
		for _ in 0 ..< n {
			i := intrinsics.volatile_load(&at)
			args := [1]gde.ConstTypePtr{&i}
			r: i64
			get_fn(&a, &args[0], &r, 1)
			sum += r
		}
	case .GET:
		for _ in 0 ..< n { sum += godot.packed_int64_array_get(&a, intrinsics.volatile_load(&at)) }
	case .FIND_CALL:
		for _ in 0 ..< n {
			v := intrinsics.volatile_load(&at)
			args := [2]gde.ConstTypePtr{&v, &from}
			r: i64
			find_fn(&a, &args[0], &r, 2)
			sum += r
		}
	case .FIND:
		for _ in 0 ..< n { sum += godot.packed_int64_array_find(&a, intrinsics.volatile_load(&at), from) }
	case .STRING_FIND_CALL:
		for _ in 0 ..< n {
			f := intrinsics.volatile_load(&from)
			args := [2]gde.ConstTypePtr{&key, &f}
			r: i64
			string_find_fn(&sa, &args[0], &r, 2)
			sum += r
		}
	case .STRING_FIND:
		for _ in 0 ..< n { sum += godot.packed_string_array_find(&sa, key, intrinsics.volatile_load(&from)) }
	case .SLICE_CALL, .SLICE:
		slice_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "slice", 1726550804)
		for _ in 0 ..< n {
			p := intrinsics.volatile_load(&ref)
			begin, end := i64(8), intrinsics.volatile_load(&at)
			r: godot.PackedInt64Array
			if kind == .SLICE {
				r = godot.packed_int64_array_slice(p, begin, end)
			} else {
				args := [2]gde.ConstTypePtr{&begin, &end}
				slice_fn(p, &args[0], &r, 2)
			}
			sum += godot.packed_stored_size(&r)
			godot.destroy[.PACKED_INT64_ARRAY](&r)
		}
	case .PUSH_CALL, .PUSH, .RESIZE_CALL, .RESIZE, .APPEND_ARRAY_CALL, .APPEND_ARRAY:
		// The written array holds 32 to 64 elements in storage for 64, so no round allocates. One
		// that reaches an end is resized back by the bindings, the same for both rows of a pair.
		w := godot.packed_of(xs[:])
		defer godot.destroy[.PACKED_INT64_ARRAY](&w)
		godot.packed_int64_array_resize(&w, 32)
		eight := godot.packed_of(xs[:8])
		defer godot.destroy[.PACKED_INT64_ARRAY](&eight)
		subject := &w
		push_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "push_back", 694024632)
		resize_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "resize", 848867239)
		append_array_fn := godot.builtin_method(.PACKED_INT64_ARRAY, "append_array", 2090311302)
		for i in 0 ..< n {
			p := intrinsics.volatile_load(&subject)
			value := i
			#partial switch kind {
			case .PUSH_CALL, .PUSH:
				if godot.packed_stored_size(p) == 64 { godot.packed_int64_array_resize(p, 32) }
				if kind == .PUSH {
					sum += i64(godot.packed_int64_array_push_back(p, value))
				} else {
					r: u8
					args := [1]gde.ConstTypePtr{&value}
					push_fn(p, &args[0], &r, 1)
					sum += i64(r)
				}
			case .RESIZE_CALL, .RESIZE:
				size := 32 + 8 * (i & 1)
				if kind == .RESIZE {
					sum += godot.packed_int64_array_resize(p, size)
				} else {
					r: i64
					args := [1]gde.ConstTypePtr{&size}
					resize_fn(p, &args[0], &r, 1)
					sum += r
				}
			case .APPEND_ARRAY_CALL, .APPEND_ARRAY:
				if godot.packed_stored_size(p) == 64 { godot.packed_int64_array_resize(p, 32) }
				if kind == .APPEND_ARRAY {
					godot.packed_int64_array_append_array(p, eight)
				} else {
					args := [1]gde.ConstTypePtr{&eight}
					append_array_fn(p, &args[0], nil, 1)
				}
			}
			sum += godot.packed_stored_size(p)
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The Array reads `array_ns` times, paired the same way as Vector_Op.
Array_Op :: enum i64 {
	SIZE_CALL,        // the engine's Array.size
	SIZE,             // array_size
	GET_CALL,         // the engine's Array.get
	GET,              // array_get
	FIND_CALL,        // the engine's Array.find, on ints
	FIND,             // array_find, on ints
	STRING_FIND_CALL, // the engine's Array.find, on Strings
	STRING_FIND,      // array_find, on Strings
	SET_CALL,         // the engine's Array.set, an int over an int
	SET,              // array_set of the same
	SET_STRING_CALL,  // the engine's Array.set, a String over an int and then the int back
	SET_STRING,       // array_set of the same; the int back releases the String, so the engine stores it
	SET_NAME_CALL,    // the engine's Array.set, a StringName over an int and then the int back
	SET_NAME,         // array_set of the same
	FILL_CALL,        // the engine's Array.fill, an int over 64 ints
	FILL,             // array_fill of the same
	FILL_LATE_CALL,   // the engine's Array.fill of an int after a String was set as the last of the 64
	FILL_LATE,        // array_fill of the same, which releases the String through the engine
	REVERSE_CALL,     // the engine's Array.reverse of 64 ints
	REVERSE,          // array_reverse of the same
}

// Nanoseconds per `kind` round on the ints 0 to 63 in one Array and the Strings "0" to "15" in
// another: get reads index 40, find looks for 40 and for "12", the index, value or start reread
// through a volatile load each round, as in packed_ns.
array_ns :: proc(self: ^Bench, kind: Array_Op, n: i64) -> f64 {
	xs: [64]i64
	for &x, i in xs { x = i64(i) }
	a := godot.array_of(xs[:])
	defer godot.destroy[.ARRAY](&a)
	words: [16]godot.String
	for &w, i in words { w = godot.string_of_int(i64(i)) }
	sa := godot.array_of(words[:])
	defer godot.destroy[.ARRAY](&sa)
	for &w in words { godot.destroy[.STRING](&w) }
	key := godot.string_of_int(12)
	defer godot.destroy[.STRING](&key)
	kv := godot.variant(key)
	defer gde.variant_destroy(&kv)
	ref := &a
	at, from := i64(40), i64(0)
	size_fn := godot.builtin_method(.ARRAY, "size", 3173160232)
	get_fn := godot.builtin_method(.ARRAY, "get", 708700221)
	find_fn := godot.builtin_method(.ARRAY, "find", 2336346817)
	sum: i64
	start := time.tick_now()
	switch kind {
	case .SIZE_CALL:
		for _ in 0 ..< n {
			r: i64
			size_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r
		}
	case .SIZE:
		for _ in 0 ..< n { sum += godot.array_size(intrinsics.volatile_load(&ref)) }
	case .GET_CALL:
		for _ in 0 ..< n {
			i := intrinsics.volatile_load(&at)
			args := [1]gde.ConstTypePtr{&i}
			r: godot.Variant
			get_fn(&a, &args[0], &r, 1)
			sum += godot.from_variant(i64, &r)
		}
	case .GET:
		for _ in 0 ..< n {
			r := godot.array_get(&a, intrinsics.volatile_load(&at))
			sum += godot.from_variant(i64, &r)
		}
	case .FIND_CALL:
		for _ in 0 ..< n {
			v := godot.variant(intrinsics.volatile_load(&at))
			args := [2]gde.ConstTypePtr{&v, &from}
			r: i64
			find_fn(&a, &args[0], &r, 2)
			sum += r
		}
	case .FIND:
		for _ in 0 ..< n { sum += godot.array_find(&a, godot.variant(intrinsics.volatile_load(&at)), from) }
	case .STRING_FIND_CALL:
		for _ in 0 ..< n {
			f := intrinsics.volatile_load(&from)
			args := [2]gde.ConstTypePtr{&kv, &f}
			r: i64
			find_fn(&sa, &args[0], &r, 2)
			sum += r
		}
	case .STRING_FIND:
		for _ in 0 ..< n { sum += godot.array_find(&sa, kv, intrinsics.volatile_load(&from)) }
	case .SET_CALL:
		set_fn := godot.builtin_method(.ARRAY, "set", 3798478031)
		for _ in 0 ..< n {
			i := intrinsics.volatile_load(&at)
			v := godot.variant(i)
			args := [2]gde.ConstTypePtr{&i, &v}
			set_fn(intrinsics.volatile_load(&ref), &args[0], nil, 2)
		}
		sum += godot.array_size(&a)
	case .SET:
		for _ in 0 ..< n {
			i := intrinsics.volatile_load(&at)
			godot.array_set(intrinsics.volatile_load(&ref), i, godot.variant(i))
		}
		sum += godot.array_size(&a)
	case .SET_STRING_CALL, .SET_STRING, .SET_NAME_CALL, .SET_NAME:
		name := godot.name_of("12")
		defer godot.destroy[.STRING_NAME](&name)
		nv := godot.variant(name)
		defer gde.variant_destroy(&nv)
		held := nv if kind == .SET_NAME_CALL || kind == .SET_NAME else kv
		if kind == .SET_STRING_CALL || kind == .SET_NAME_CALL {
			set_fn := godot.builtin_method(.ARRAY, "set", 3798478031)
			for _ in 0 ..< n {
				i := intrinsics.volatile_load(&at)
				v := godot.variant(i)
				args := [2]gde.ConstTypePtr{&i, &held}
				set_fn(intrinsics.volatile_load(&ref), &args[0], nil, 2)
				args[1] = &v
				set_fn(intrinsics.volatile_load(&ref), &args[0], nil, 2)
			}
		} else {
			for _ in 0 ..< n {
				i := intrinsics.volatile_load(&at)
				godot.array_set(intrinsics.volatile_load(&ref), i, held)
				godot.array_set(intrinsics.volatile_load(&ref), i, godot.variant(i))
			}
		}
		sum += godot.array_size(&a)
	case .FILL_CALL, .FILL, .FILL_LATE_CALL, .FILL_LATE:
		fill_fn := godot.builtin_method(.ARRAY, "fill", 3316032543)
		late := kind == .FILL_LATE_CALL || kind == .FILL_LATE
		for i in 0 ..< n {
			if late { godot.array_set(&a, 63, kv) }
			v := godot.variant(i)
			if kind == .FILL || kind == .FILL_LATE {
				godot.array_fill(intrinsics.volatile_load(&ref), v)
			} else {
				args := [1]gde.ConstTypePtr{&v}
				fill_fn(intrinsics.volatile_load(&ref), &args[0], nil, 1)
			}
		}
		sum += godot.array_size(&a)
	case .REVERSE_CALL:
		reverse_fn := godot.builtin_method(.ARRAY, "reverse", 3218959716)
		for _ in 0 ..< n { reverse_fn(intrinsics.volatile_load(&ref), nil, nil, 0) }
		sum += godot.array_size(&a)
	case .REVERSE:
		for _ in 0 ..< n { godot.array_reverse(intrinsics.volatile_load(&ref)) }
		sum += godot.array_size(&a)
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The Dictionary reads `dict_ns` times, paired the same way as Vector_Op.
Dict_Op :: enum i64 {
	SIZE_CALL,       // the engine's Dictionary.size
	SIZE,            // dictionary_size
	HAS_CALL,        // the engine's Dictionary.has, on ints
	HAS,             // dictionary_has, on ints
	GET_CALL,        // the engine's Dictionary.get, on ints
	GET,             // dictionary_get, on ints
	STRING_HAS_CALL, // the engine's Dictionary.has, on Strings
	STRING_HAS,      // dictionary_has, on Strings
	KEYS_CALL,       // the engine's Dictionary.keys, of 64 ints
	KEYS,            // dictionary_keys, of 64 ints
	VALUES_CALL,     // the engine's Dictionary.values, of 64 ints
	VALUES,          // dictionary_values, of 64 ints
	FIND_KEY_CALL,   // the engine's Dictionary.find_key, of the 41st value of 64 ints
	FIND_KEY,        // dictionary_find_key, of the 41st value of 64 ints
	SET_CALL,        // the engine's Dictionary.set, of an int at a key present
	SET,             // dictionary_set, of an int at a key present
	GET_OR_ADD_CALL, // the engine's Dictionary.get_or_add, at a key present
	GET_OR_ADD,      // dictionary_get_or_add, at a key present
}

// Nanoseconds per `kind` round on a Dictionary of the ints 0 to 63, each mapped to three times
// itself, and one of the Strings "0" to "15": has and get look up 40 and "12", the key reread
// through a volatile load each round, as in packed_ns.
dict_ns :: proc(self: ^Bench, kind: Dict_Op, n: i64) -> f64 {
	d := godot.dictionary_new()
	defer godot.destroy[.DICTIONARY](&d)
	for i in 0 ..< i64(64) { godot.dict_set(&d, i, i * 3) }
	sd := godot.dictionary_new()
	defer godot.destroy[.DICTIONARY](&sd)
	for i in 0 ..< i64(16) {
		w := godot.string_of_int(i)
		godot.dict_set(&sd, w, i)
		godot.destroy[.STRING](&w)
	}
	key := godot.string_of_int(12)
	defer godot.destroy[.STRING](&key)
	kv := godot.variant(key)
	defer gde.variant_destroy(&kv)
	skey := &kv
	ref := &d
	at := i64(40)
	nothing: godot.Variant
	size_fn := godot.builtin_method(.DICTIONARY, "size", 3173160232)
	has_fn := godot.builtin_method(.DICTIONARY, "has", 3680194679)
	get_fn := godot.builtin_method(.DICTIONARY, "get", 2205440559)
	keys_fn := godot.builtin_method(.DICTIONARY, "keys", 4144163970)
	values_fn := godot.builtin_method(.DICTIONARY, "values", 4144163970)
	find_key_fn := godot.builtin_method(.DICTIONARY, "find_key", 1988825835)
	set_fn := godot.builtin_method(.DICTIONARY, "set", 2175348267)
	get_or_add_fn := godot.builtin_method(.DICTIONARY, "get_or_add", 1052551076)
	value := i64(120)
	sum: i64
	start := time.tick_now()
	switch kind {
	case .SIZE_CALL:
		for _ in 0 ..< n {
			r: i64
			size_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r
		}
	case .SIZE:
		for _ in 0 ..< n { sum += godot.dictionary_size(intrinsics.volatile_load(&ref)) }
	case .HAS_CALL:
		for _ in 0 ..< n {
			v := godot.variant(intrinsics.volatile_load(&at))
			args := [1]gde.ConstTypePtr{&v}
			r: bool
			has_fn(&d, &args[0], &r, 1)
			sum += i64(r)
		}
	case .HAS:
		for _ in 0 ..< n { sum += i64(godot.dictionary_has(&d, godot.variant(intrinsics.volatile_load(&at)))) }
	case .GET_CALL:
		for _ in 0 ..< n {
			v := godot.variant(intrinsics.volatile_load(&at))
			args := [2]gde.ConstTypePtr{&v, &nothing}
			r: godot.Variant
			get_fn(&d, &args[0], &r, 2)
			sum += godot.from_variant(i64, &r)
		}
	case .GET:
		for _ in 0 ..< n {
			r := godot.dictionary_get(&d, godot.variant(intrinsics.volatile_load(&at)), nothing)
			sum += godot.from_variant(i64, &r)
		}
	case .STRING_HAS_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{intrinsics.volatile_load(&skey)}
			r: bool
			has_fn(&sd, &args[0], &r, 1)
			sum += i64(r)
		}
	case .STRING_HAS:
		for _ in 0 ..< n { sum += i64(godot.dictionary_has(&sd, intrinsics.volatile_load(&skey)^)) }
	case .KEYS_CALL, .VALUES_CALL:
		fn := keys_fn if kind == .KEYS_CALL else values_fn
		for _ in 0 ..< n {
			r: godot.Array
			fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += godot.array_size(&r)
			godot.destroy[.ARRAY](&r)
		}
	case .KEYS, .VALUES:
		for _ in 0 ..< n {
			r := godot.dictionary_keys(intrinsics.volatile_load(&ref)) if kind == .KEYS else godot.dictionary_values(intrinsics.volatile_load(&ref))
			sum += godot.array_size(&r)
			godot.destroy[.ARRAY](&r)
		}
	case .FIND_KEY_CALL:
		for _ in 0 ..< n {
			v := godot.variant(intrinsics.volatile_load(&value))
			args := [1]gde.ConstTypePtr{&v}
			r: godot.Variant
			find_key_fn(&d, &args[0], &r, 1)
			sum += godot.from_variant(i64, &r)
		}
	case .FIND_KEY:
		for _ in 0 ..< n {
			r := godot.dictionary_find_key(&d, godot.variant(intrinsics.volatile_load(&value)))
			sum += godot.from_variant(i64, &r)
		}
	case .SET_CALL:
		for i in 0 ..< n {
			k, v := godot.variant(intrinsics.volatile_load(&at)), godot.variant(i)
			args := [2]gde.ConstTypePtr{&k, &v}
			r: u8
			set_fn(&d, &args[0], &r, 2)
			sum += i64(r)
		}
	case .SET:
		for i in 0 ..< n {
			sum += i64(godot.dictionary_set(&d, godot.variant(intrinsics.volatile_load(&at)), godot.variant(i)))
		}
	case .GET_OR_ADD_CALL:
		for _ in 0 ..< n {
			v := godot.variant(intrinsics.volatile_load(&at))
			args := [2]gde.ConstTypePtr{&v, &nothing}
			r: godot.Variant
			get_or_add_fn(&d, &args[0], &r, 2)
			sum += godot.from_variant(i64, &r)
		}
	case .GET_OR_ADD:
		for _ in 0 ..< n {
			r := godot.dictionary_get_or_add(&d, godot.variant(intrinsics.volatile_load(&at)), nothing)
			sum += godot.from_variant(i64, &r)
		}
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += sum
	return ns
}

// The Projection methods `projection_ns` times, paired the same way as Vector_Op.
Projection_Op :: enum i64 {
	INVERSE_CALL,     // the engine's Projection.inverse
	INVERSE,          // projection_inverse
	DETERMINANT_CALL, // the engine's Projection.determinant
	DETERMINANT,      // projection_determinant
	PLANE_CALL,       // the engine's Projection.get_projection_plane
	PLANE,            // projection_get_projection_plane
	PERSPECTIVE_CALL, // the engine's Projection.create_perspective
	PERSPECTIVE,      // projection_create_perspective
}

// Nanoseconds per `kind` round on a perspective projection reread through a volatile load each
// round, as in vector_ns. create_perspective rereads its field of view the same way.
projection_ns :: proc(self: ^Bench, kind: Projection_Op, n: i64) -> f64 {
	p := godot.projection_create_perspective(75, 16.0 / 9.0, 0.05, 4000, false)
	ref := &p
	fov, aspect, near, far := f64(75), f64(16.0 / 9.0), f64(0.05), f64(4000)
	flip := u8(0)
	plane := i64(godot.Projection_Planes.PLANE_LEFT)
	inverse_fn := godot.builtin_method(.PROJECTION, "inverse", 4212530932)
	determinant_fn := godot.builtin_method(.PROJECTION, "determinant", 466405837)
	plane_fn := godot.builtin_method(.PROJECTION, "get_projection_plane", 1551184160)
	perspective_fn := godot.builtin_method(.PROJECTION, "create_perspective", 390915442)
	sum: f32
	start := time.tick_now()
	switch kind {
	case .INVERSE_CALL:
		for _ in 0 ..< n {
			r: godot.Projection
			inverse_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += r.x.x
		}
	case .INVERSE:
		for _ in 0 ..< n { sum += godot.projection_inverse(intrinsics.volatile_load(&ref)).x.x }
	case .DETERMINANT_CALL:
		for _ in 0 ..< n {
			r: f64
			determinant_fn(intrinsics.volatile_load(&ref), nil, &r, 0)
			sum += f32(r)
		}
	case .DETERMINANT:
		for _ in 0 ..< n { sum += f32(godot.projection_determinant(intrinsics.volatile_load(&ref))) }
	case .PLANE_CALL:
		for _ in 0 ..< n {
			args := [1]gde.ConstTypePtr{&plane}
			r: godot.Plane
			plane_fn(intrinsics.volatile_load(&ref), &args[0], &r, 1)
			sum += r.d
		}
	case .PLANE:
		for _ in 0 ..< n { sum += godot.projection_get_projection_plane(intrinsics.volatile_load(&ref), plane).d }
	case .PERSPECTIVE_CALL:
		for _ in 0 ..< n {
			f := intrinsics.volatile_load(&fov)
			args := [5]gde.ConstTypePtr{&f, &aspect, &near, &far, &flip}
			r: godot.Projection
			perspective_fn(nil, &args[0], &r, 5)
			sum += r.x.x
		}
	case .PERSPECTIVE:
		for _ in 0 ..< n { sum += godot.projection_create_perspective(intrinsics.volatile_load(&fov), aspect, near, far, false).x.x }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
	return ns
}

// How many replaced methods gen_replaced.odin times, for bench.gd to list.
replaced_count :: proc(self: ^Bench) -> i64 {
	return len(replaced_benches)
}

// The name of replaced method `index`: the engine's, as "Vector2.angle", or the Odin proc's.
replaced_label :: proc(self: ^Bench, index: i64, engine: bool) -> godot.String {
	if index < 0 || index >= len(replaced_benches) { return {} }
	b := replaced_benches[index]
	return godot.string_of(b.engine if engine else b.odin)
}

// Nanoseconds per call of replaced method `index` over `n` rounds, through the engine's ptrcall
// or through the Odin proc, on a value reread through a volatile load each round.
replaced_ns :: proc(self: ^Bench, index: i64, engine: bool, n: i64) -> f64 {
	if index < 0 || index >= len(replaced_benches) { return 0 }
	return replaced_benches[index].run(engine, n)
}
