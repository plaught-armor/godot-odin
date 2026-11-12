// Lookups the generated wrappers make on first call. Hand-written; the generator calls into it.
package godot

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import gde "../gdextension"

// A StringName the engine keeps for the life of the process. `name` must be a literal.
static_name :: proc "contextless" (name: cstring) -> (sn: StringName) {
	gde.string_name_new_with_latin1_chars(&sn, name, 1)
	return
}

// Stops the process with `message` in the engine log. For a binding the engine does not have.
fail :: proc "contextless" (message: cstring, what: cstring) -> ! {
	gde.print_error(message, what, #file, #line, 1)
	intrinsics.trap()
}

// The engine method `class.method` with the API hash `hash`; stops if the engine lacks it.
method_bind :: proc "contextless" (class, method: cstring, hash: i64) -> gde.MethodBindPtr {
	class_sn := static_name(class)
	method_sn := static_name(method)
	mb := gde.classdb_get_method_bind(&class_sn, &method_sn, hash)
	if mb == nil { fail("odin: no method bind", method) }
	return mb
}

// The builtin method `method` of Variant type `type` with the API hash `hash`; stops if missing.
builtin_method :: proc "contextless" (type: gde.VariantType, method: cstring, hash: i64) -> gde.PtrBuiltInMethod {
	method_sn := static_name(method)
	fn := gde.variant_get_ptr_builtin_method(type, &method_sn, hash)
	if fn == nil { fail("odin: no builtin method", method) }
	return fn
}

// The global utility function `name` with the API hash `hash`; stops if the engine lacks it.
utility_function :: proc "contextless" (name: cstring, hash: i64) -> gde.PtrUtilityFunction {
	name_sn := static_name(name)
	fn := gde.variant_get_ptr_utility_function(&name_sn, hash)
	if fn == nil { fail("odin: no utility function", name) }
	return fn
}

// The engine singleton `name`; stops if the engine lacks it.
singleton :: proc "contextless" (name: cstring) -> gde.ObjectPtr {
	name_sn := static_name(name)
	obj := gde.global_get_singleton(&name_sn)
	if obj == nil { fail("odin: no singleton", name) }
	return obj
}

// A String for `s`, which the caller destroys.
string_of :: proc "contextless" (s: string) -> (out: String) {
	gde.string_new_with_utf8_chars_and_len(&out, cstring(raw_data(s)), gde.Int(len(s)))
	return
}

// `s` as UTF-8 in a new Odin string from `allocator`, which the caller deletes.
utf8 :: proc(s: String, allocator := context.allocator) -> string {
	t := s
	n := int(gde.string_to_utf8_chars(&t, nil, 0))
	buf := make([]u8, n, allocator)
	if n > 0 { gde.string_to_utf8_chars(&t, cstring(raw_data(buf)), gde.Int(n)) }
	return string(buf)
}

// The elements of packed array `a` as a slice over its storage, for reading in place. It stays valid
// until `a` is written, resized or destroyed. Do not write through it: the storage may be shared
// with copies of `a`. Use `packed_write` for that.
packed_read :: proc {
	packed_read_byte, packed_read_int32, packed_read_int64, packed_read_float32, packed_read_float64,
	packed_read_string, packed_read_vector2, packed_read_vector3, packed_read_vector4, packed_read_color,
}

// The elements of packed array `a` as a writable slice. The first call on a shared array gives `a`
// storage of its own, as any write does; the slice stays valid until `a` is copied, resized or
// destroyed. `a` must be an array you own, not a borrowed parameter.
packed_write :: proc {
	packed_write_byte, packed_write_int32, packed_write_int64, packed_write_float32, packed_write_float64,
	packed_write_string, packed_write_vector2, packed_write_vector3, packed_write_vector4, packed_write_color,
}

packed_read_byte :: proc "contextless" (a: ^PackedByteArray) -> []u8 { return packed_slice(u8, a, packed_byte_array_size(a), gde.packed_byte_array_operator_index_const) }
packed_read_int32 :: proc "contextless" (a: ^PackedInt32Array) -> []i32 { return packed_slice(i32, a, packed_int32_array_size(a), gde.packed_int32_array_operator_index_const) }
packed_read_int64 :: proc "contextless" (a: ^PackedInt64Array) -> []i64 { return packed_slice(i64, a, packed_int64_array_size(a), gde.packed_int64_array_operator_index_const) }
packed_read_float32 :: proc "contextless" (a: ^PackedFloat32Array) -> []f32 { return packed_slice(f32, a, packed_float32_array_size(a), gde.packed_float32_array_operator_index_const) }
packed_read_float64 :: proc "contextless" (a: ^PackedFloat64Array) -> []f64 { return packed_slice(f64, a, packed_float64_array_size(a), gde.packed_float64_array_operator_index_const) }
packed_read_string :: proc "contextless" (a: ^PackedStringArray) -> []String { return packed_slice(String, a, packed_string_array_size(a), gde.packed_string_array_operator_index_const) }
packed_read_vector2 :: proc "contextless" (a: ^PackedVector2Array) -> []Vector2 { return packed_slice(Vector2, a, packed_vector2_array_size(a), gde.packed_vector2_array_operator_index_const) }
packed_read_vector3 :: proc "contextless" (a: ^PackedVector3Array) -> []Vector3 { return packed_slice(Vector3, a, packed_vector3_array_size(a), gde.packed_vector3_array_operator_index_const) }
packed_read_vector4 :: proc "contextless" (a: ^PackedVector4Array) -> []Vector4 { return packed_slice(Vector4, a, packed_vector4_array_size(a), gde.packed_vector4_array_operator_index_const) }
packed_read_color :: proc "contextless" (a: ^PackedColorArray) -> []Color { return packed_slice(Color, a, packed_color_array_size(a), gde.packed_color_array_operator_index_const) }

packed_write_byte :: proc "contextless" (a: ^PackedByteArray) -> []u8 { return packed_slice(u8, a, packed_byte_array_size(a), gde.packed_byte_array_operator_index) }
packed_write_int32 :: proc "contextless" (a: ^PackedInt32Array) -> []i32 { return packed_slice(i32, a, packed_int32_array_size(a), gde.packed_int32_array_operator_index) }
packed_write_int64 :: proc "contextless" (a: ^PackedInt64Array) -> []i64 { return packed_slice(i64, a, packed_int64_array_size(a), gde.packed_int64_array_operator_index) }
packed_write_float32 :: proc "contextless" (a: ^PackedFloat32Array) -> []f32 { return packed_slice(f32, a, packed_float32_array_size(a), gde.packed_float32_array_operator_index) }
packed_write_float64 :: proc "contextless" (a: ^PackedFloat64Array) -> []f64 { return packed_slice(f64, a, packed_float64_array_size(a), gde.packed_float64_array_operator_index) }
packed_write_string :: proc "contextless" (a: ^PackedStringArray) -> []String { return packed_slice(String, a, packed_string_array_size(a), gde.packed_string_array_operator_index) }
packed_write_vector2 :: proc "contextless" (a: ^PackedVector2Array) -> []Vector2 { return packed_slice(Vector2, a, packed_vector2_array_size(a), gde.packed_vector2_array_operator_index) }
packed_write_vector3 :: proc "contextless" (a: ^PackedVector3Array) -> []Vector3 { return packed_slice(Vector3, a, packed_vector3_array_size(a), gde.packed_vector3_array_operator_index) }
packed_write_vector4 :: proc "contextless" (a: ^PackedVector4Array) -> []Vector4 { return packed_slice(Vector4, a, packed_vector4_array_size(a), gde.packed_vector4_array_operator_index) }
packed_write_color :: proc "contextless" (a: ^PackedColorArray) -> []Color { return packed_slice(Color, a, packed_color_array_size(a), gde.packed_color_array_operator_index) }

// `n` elements of `E` from the first one `at` finds in `a`. An empty array gives nil without asking
// `at`, which reports an error for index 0 of an empty array.
@(private)
packed_slice :: #force_inline proc "contextless" ($E: typeid, a: rawptr, n: i64, at: proc "c" (rawptr, gde.Int) -> $R) -> []E {
	if n <= 0 { return nil }
	return ([^]E)(rawptr(at(a, 0)))[:n]
}

// A new packed array holding a copy of `xs`, which the caller destroys or returns. A String element
// is copied as a new reference; the others are copied as bytes.
packed_of :: proc {
	packed_of_byte, packed_of_int32, packed_of_int64, packed_of_float32, packed_of_float64,
	packed_of_string, packed_of_vector2, packed_of_vector3, packed_of_vector4, packed_of_color,
}

packed_of_byte :: proc "contextless" (xs: []u8) -> (out: PackedByteArray) { out = packed_byte_array_new(); packed_fill(&out, xs, packed_byte_array_resize, packed_write_byte); return }
packed_of_int32 :: proc "contextless" (xs: []i32) -> (out: PackedInt32Array) { out = packed_int32_array_new(); packed_fill(&out, xs, packed_int32_array_resize, packed_write_int32); return }
packed_of_int64 :: proc "contextless" (xs: []i64) -> (out: PackedInt64Array) { out = packed_int64_array_new(); packed_fill(&out, xs, packed_int64_array_resize, packed_write_int64); return }
packed_of_float32 :: proc "contextless" (xs: []f32) -> (out: PackedFloat32Array) { out = packed_float32_array_new(); packed_fill(&out, xs, packed_float32_array_resize, packed_write_float32); return }
packed_of_float64 :: proc "contextless" (xs: []f64) -> (out: PackedFloat64Array) { out = packed_float64_array_new(); packed_fill(&out, xs, packed_float64_array_resize, packed_write_float64); return }
packed_of_vector2 :: proc "contextless" (xs: []Vector2) -> (out: PackedVector2Array) { out = packed_vector2_array_new(); packed_fill(&out, xs, packed_vector2_array_resize, packed_write_vector2); return }
packed_of_vector3 :: proc "contextless" (xs: []Vector3) -> (out: PackedVector3Array) { out = packed_vector3_array_new(); packed_fill(&out, xs, packed_vector3_array_resize, packed_write_vector3); return }
packed_of_vector4 :: proc "contextless" (xs: []Vector4) -> (out: PackedVector4Array) { out = packed_vector4_array_new(); packed_fill(&out, xs, packed_vector4_array_resize, packed_write_vector4); return }
packed_of_color :: proc "contextless" (xs: []Color) -> (out: PackedColorArray) { out = packed_color_array_new(); packed_fill(&out, xs, packed_color_array_resize, packed_write_color); return }

packed_of_string :: proc "contextless" (xs: []String) -> (out: PackedStringArray) {
	out = packed_string_array_new()
	packed_string_array_resize(&out, i64(len(xs)))
	// Each new slot is an empty String, which holds nothing to release before it is overwritten.
	for &s, i in packed_write_string(&out) { s = string_new_from_string(xs[i]) }
	return
}

// Sizes `out` to `xs` and copies `xs` into it as bytes.
@(private)
packed_fill :: #force_inline proc "contextless" (out: ^$A, xs: []$E, resize: proc "contextless" (^A, i64) -> i64, write: proc "contextless" (^A) -> []E) {
	resize(out, i64(len(xs)))
	copy(write(out), xs)
}

// The characters of `s` as a slice over its storage, read in place. It stays valid until `s` is
// written or destroyed. Do not write through it: the storage may be shared with copies of `s`.
string_read :: proc "contextless" (s: ^String) -> []rune {
	n := string_length(s)
	if n <= 0 { return nil }
	return gde.string_operator_index_const(s, 0)[:n]
}

// Element `i` of `a`, borrowed: valid until `a` changes or is destroyed, and not to be destroyed.
// Nil when `i` is out of range.
array_at :: proc "contextless" (a: ^Array, i: i64) -> ^Variant {
	return (^Variant)(gde.array_operator_index_const(a, i))
}

// Drops one reference to the counted object `obj` and frees it when that was the last.
release :: proc "contextless" (obj: $T) where intrinsics.type_base_type(T) == rawptr {
	if obj == nil { return }
	if ref_counted_unreference(RefCounted(obj)) { gde.object_destroy(gde.ObjectPtr(obj)) }
}

// `obj` as engine class `T` when it is one (or inherits it), else nil. `T` must be an engine
// class, not an extension class: those have no class tag of their own here.
cast_to :: proc(obj: $O, $T: typeid) -> T where intrinsics.type_base_type(O) == rawptr && intrinsics.type_base_type(T) == rawptr {
	@(static) tag: rawptr
	if obj == nil { return nil }
	if tag == nil {
		named := type_info_of(T).variant.(runtime.Type_Info_Named)
		sn: StringName
		gde.string_name_new_with_utf8_chars_and_len(&sn, cstring(raw_data(named.name)), gde.Int(len(named.name)))
		tag = gde.classdb_get_class_tag(&sn)
		destroy[.STRING_NAME](&sn)
	}
	return T(gde.object_cast_to(gde.ConstObjectPtr(obj), tag))
}

// True while the object with instance id `id` exists.
is_live :: proc "contextless" (id: u64) -> bool {
	return id != 0 && gde.object_get_instance_from_id(gde.ObjectInstanceID(id)) != nil
}

// Whether `a` and `b` are the same name, as StringName's `==` is: the engine interns names, so
// equal text is one handle. Two empty names are the same.
same_name :: proc "contextless" (a, b: StringName) -> bool {
	return a._opaque == b._opaque
}

// Element `index` of `array` as a new StringName, which the caller destroys; the empty name when
// the element is not a StringName, so a search for the empty name in an untyped Array also
// matches other element types. `index` must be in range.
array_name_at :: proc "contextless" (array: ^Array, index: i64) -> (out: StringName) {
	v := array_get(array, index)
	defer gde.variant_destroy(&v)
	if variant_tag(&v) != .STRING_NAME { return }
	to_type[.STRING_NAME](&out, &v)
	return
}

// True only on the thread `entry` ran on, the engine's main thread; debug builds assert every call
// arrives on it.
@(thread_local)
on_main_thread: bool

// Opens a call from the engine, after `context = ctx`. Marks this library's temp arena, `temp_arena`; the deferred
// `leave` rolls it back at scope exit, so the call frees the temp it took and nothing older. Debug
// builds assert the call is on the main thread.
@(deferred_out = leave)
enter :: #force_inline proc(loc := #caller_location) -> runtime.Arena_Temp {
	when ODIN_DEBUG {
		assert(on_main_thread, "godot_odin: an engine call off the main thread", loc)
	}
	// `runtime.arena_temp_begin`, inline: it is a call, on every call from the engine.
	a := temp_arena
	temp := runtime.Arena_Temp{arena = a, block = a.curr_block}
	if a.curr_block != nil { temp.used = a.curr_block.used }
	a.temp_count += 1
	return temp
}

// The arena behind `ctx.temp_allocator`, the main thread's, which `entry` sets. `enter` marks it
// directly: the runtime's own temp_begin finds it through a thread-local lookup, a `__tls_get_addr`
// call per engine call in a shared library.
temp_arena: ^runtime.Arena

// Rolls the temp arena back to `temp`, the mark `enter` took. Most calls take no temp, and then
// only the mark's count changes: the runtime's rollback, which is a call, runs when there is
// something to roll back.
leave :: #force_inline proc(temp: runtime.Arena_Temp) {
	a := temp.arena
	if a.curr_block == temp.block && (temp.block == nil || temp.block.used == temp.used) {
		when ODIN_DEBUG {
			assert(a.temp_count > 0, "godot_odin: leave without enter")
		}
		a.temp_count -= 1
		return
	}
	roll_back(temp)
}

// The runtime's rollback, in a call of its own that sets `ctx`: inline in `leave`, it would make
// every engine call keep its copy of the context alive for it, even one whose proc never reads it.
@(private)
roll_back :: #force_no_inline proc "contextless" (temp: runtime.Arena_Temp) {
	context = ctx
	runtime.default_temp_allocator_temp_end(temp)
}

// Bytes the temp arena of `ctx`, the context every engine call runs in, holds now. For debug lanes
// that prove a call frees its temp use.
temp_used :: proc "contextless" () -> i64 {
	// The sum over the arena's live blocks. The arena's own `total_used` keeps counting a block it
	// frees on rollback, so it only grows after a take that needed a new block.
	MAX_BLOCKS :: 1 << 16
	n: uint
	block := (^runtime.Default_Temp_Allocator)(ctx.temp_allocator.data).arena.curr_block
	for _ in 0 ..< MAX_BLOCKS {
		if block == nil { break }
		n += block.used
		block = block.prev
	}
	return i64(n)
}

// Logs a formatted warning in the engine's log and editor, as `push_warning` does.
warn :: proc(format: string, args: ..any, loc := #caller_location) {
	gde.print_warning(fmt.ctprintf(format, ..args), fmt.ctprintf("%s", loc.procedure), fmt.ctprintf("%s", loc.file_path), loc.line, 1)
}

// Logs a formatted error in the engine's log and editor, as `push_error` does.
error :: proc(format: string, args: ..any, loc := #caller_location) {
	gde.print_error(fmt.ctprintf(format, ..args), fmt.ctprintf("%s", loc.procedure), fmt.ctprintf("%s", loc.file_path), loc.line, 1)
}

// A new instance of engine class `T`, which the caller owns: a RefCounted one starts with one
// reference, dropped with `release`; any other is freed with `gde.object_destroy`.
construct :: proc($T: typeid) -> T where intrinsics.type_base_type(T) == rawptr {
	// The class name and whether it is RefCounted are fixed per `T`: looked up on the first call.
	@(static) sn: StringName
	@(static) known: bool
	if !known {
		named := type_info_of(T).variant.(runtime.Type_Info_Named)
		gde.string_name_new_with_latin1_chars(&sn, fmt.ctprintf("%s", named.name), 1)
		known = true
	}
	// A RefCounted object returns holding the one reference the caller takes over.
	obj := gde.classdb_construct_object3(&sn)
	object_notification(Object(obj), 0, false)
	return T(obj)
}
