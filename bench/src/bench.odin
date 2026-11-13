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
	godot.method(c, "quaternion_ns", quaternion_ns, {"kind", "n"})
	godot.method(c, "plane_ns", plane_ns, {"kind", "n"})
	godot.method(c, "aabb_ns", aabb_ns, {"kind", "n"})
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
	TO_INT_ENGINE,     // the generated string_to_int of a cached "-12345"
	TO_INT_RUNES,      // runes_to_int of the same String's characters
	TO_FLOAT_ENGINE,   // the generated string_to_float of a cached "-123.456e-2"
	TO_FLOAT_RUNES,    // runes_to_float of the same String's characters
	INT_TEXT_ENGINE,   // the generated string_num_int64 of -1234567, made and destroyed
	INT_TEXT,          // string_of_int of the same number
	FLOAT_TEXT_ENGINE, // the generated string_num of -123.456 at the default places
	FLOAT_TEXT,        // string_of_float of the same number
	FIND_CALL,         // the engine's String.find, called as the bindings did before string_find replaced it
	RFIND_CALL,        // the engine's String.rfind the same way
	FINDN_CALL,        // the engine's String.findn the same way
	NOCASE_CALL,       // the engine's String.nocasecmp_to the same way
	REPLACE_CALL,      // the engine's String.replace the same way
	SPLIT_CALL,        // the engine's String.split the same way
}

// Action names for the `string_which` rows, the bench's identifier last, others of its length and
// first character among them.
WHICH_NAMES :: [8]string{"player_jum", "player_run", "player_walk", "player_dash", "pause", "player_crouch", "player_jumq", "player_jump"}

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
		v := i64(-1234567)
		for _ in 0 ..< n {
			s := godot.string_num_int64(intrinsics.volatile_load(&v), 10, false)
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
		v := -123.456
		for _ in 0 ..< n {
			s := godot.string_num(intrinsics.volatile_load(&v), -1)
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
		for _ in 0 ..< n { sum += godot.transform2d_interpolate_with(intrinsics.volatile_load(&ref2), b2, weight).x.x }
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
		for _ in 0 ..< n { sum += godot.transform3d_interpolate_with(intrinsics.volatile_load(&ref3), b3, weight).basis.x.x }
	}
	ns := f64(time.tick_since(start)) / f64(n)
	self.total += i64(sum)
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
