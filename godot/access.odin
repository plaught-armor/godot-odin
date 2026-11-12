// Direct access to engine storage: packed arrays, Strings, Arrays, Images and files read and written
// through the pointers the interface hands out, instead of one builtin or method call per element.
package godot

import "base:intrinsics"
import "base:runtime"
import gde "../gdextension"

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

// The elements of `a` as a slice over its storage, read in place: valid until `a` changes or is
// destroyed. Do not write through it or destroy its elements.
array_read :: proc "contextless" (a: ^Array) -> []Variant {
	n := array_size(a)
	if n <= 0 { return nil }
	return ([^]Variant)(gde.array_operator_index_const(a, 0))[:n]
}

// The elements of `a` as a writable slice, or nil when `a` is typed or read-only, whose checks a
// direct write would skip: use `array_write_typed` or `array_set` for those. An Array is shared, not copied on write, so
// every holder of `a` sees the writes, as with `array_set`. Each element is a Variant `a` owns:
// destroy the old one before storing a new one. Valid until `a` is resized, duplicated or destroyed.
array_write :: proc "contextless" (a: ^Array) -> []Variant {
	n := array_size(a)
	if n <= 0 || array_is_typed(a) || array_is_read_only(a) { return nil }
	return ([^]Variant)(gde.array_operator_index(a, 0))[:n]
}

// A new untyped Array holding `xs`, each element converted as `variant` does, in one resize. You
// destroy it, or return it.
array_of :: proc "contextless" (xs: []$T) -> (out: Array) {
	out = array_new()
	if len(xs) == 0 { return }
	array_resize(&out, i64(len(xs)))
	// The resize fills with nulls, which hold nothing to destroy.
	slots := ([^]Variant)(gde.array_operator_index(&out, 0))
	for x, i in xs { variant_into(&slots[i], x) }
	return
}

// A new Array typed to `T`, as GDScript's `Array[T]`, holding `xs`, in one resize as `array_of`
// builds. `T` is a builtin type or an engine class; an integer type makes `Array[int]` and a float type
// `Array[float]`. You destroy it, or return it.
array_typed_of :: proc "contextless" (xs: []$T) -> (out: Array) {
	out = array_new()
	array_type_as(&out, variant_type(T), typed_class(T))
	if len(xs) == 0 { return }
	array_resize(&out, i64(len(xs)))
	// The resize fills a typed Array with its type's default value: nothing to destroy for a
	// scalar or an object, which starts null, but a counted value for the rest.
	slots := ([^]Variant)(gde.array_operator_index(&out, 0))
	for x, i in xs {
		when !(T == bool || intrinsics.type_is_integer(T) || intrinsics.type_is_enum(T) || intrinsics.type_is_bit_set(T) || intrinsics.type_is_float(T) || intrinsics.type_base_type(T) == rawptr) {
			gde.variant_destroy(&slots[i])
		}
		variant_into(&slots[i], x)
	}
	return
}

// The elements of `a` as a writable slice, as `array_write` gives, when `a` is typed exactly to
// `T` and writable; else nil. Store only `T` values in it, since the direct write skips the
// engine's type check: an `Array[Node]` takes `T` Node, not a subclass, and an `Array` typed to a
// script class gives nil. Destroy an element before storing a new one in its place.
array_write_typed :: proc "contextless" (a: ^Array, $T: typeid) -> []Variant {
	n := array_size(a)
	if n <= 0 || array_is_read_only(a) || !array_typed_as(a, variant_type(T), typed_class(T)) { return nil }
	return ([^]Variant)(gde.array_operator_index(a, 0))[:n]
}

// The class name an `Array[T]` carries: `T`'s own for an engine class, else empty. Looked up once
// per `T`, and kept for the life of the process.
@(private)
typed_class :: proc "contextless" ($T: typeid) -> ^StringName {
	#assert(T != Variant, "godot_odin: a typed Array needs a type; use array_of for an untyped one")
	#assert(!(intrinsics.type_is_pointer(T) && intrinsics.type_base_type(T) != rawptr), "godot_odin: a typed Array of a registered class is not supported")
	@(static) name: StringName
	@(static) known: bool
	when intrinsics.type_base_type(T) == rawptr {
		if !known {
			name_of_type(&name, type_info_of(T))
			known = true
		}
	}
	return &name
}

// `out` set to the name of the named type `info`, an engine class's.
@(private)
name_of_type :: proc "contextless" (out: ^StringName, info: ^runtime.Type_Info) {
	named := info.variant.(runtime.Type_Info_Named)
	gde.string_name_new_with_utf8_chars_and_len(out, cstring(raw_data(named.name)), gde.Int(len(named.name)))
}

// Types the empty Array `a` to Variant type `type` and class `class` (empty unless `type` is
// OBJECT), with no script.
@(private)
array_type_as :: proc "contextless" (a: ^Array, type: gde.VariantType, class: ^StringName) {
	script: Variant
	gde.array_set_typed(a, type, class, &script)
}

// Whether `a` is typed exactly to Variant type `type` and class `class`, with no script.
@(private)
array_typed_as :: proc "contextless" (a: ^Array, type: gde.VariantType, class: ^StringName) -> bool {
	if !array_is_typed(a) || array_get_typed_builtin(a) != i64(type) { return false }
	if type != .OBJECT { return true }
	got := array_get_typed_class_name(a)
	defer destroy[.STRING_NAME](&got)
	script := array_get_typed_script(a)
	defer gde.variant_destroy(&script)
	return same_name(got, class^) && variant_tag(&script) == .NIL
}

// The keys and the values of `d`, as two new Arrays in matching order: `keys[i]` maps to
// `values[i]`. Read them in place with `array_read`. You destroy both.
dict_items :: proc "contextless" (d: ^Dictionary) -> (keys, values: Array) {
	return dictionary_keys(d), dictionary_values(d)
}

// A new untyped Dictionary mapping `keys[i]` to `values[i]`, each converted as `variant` does. A
// repeated key keeps its last value. `keys` and `values` have the same length. You destroy it, or
// return it.
dict_of :: proc "contextless" (keys: []$K, values: []$V) -> (out: Dictionary) {
	out = dictionary_new()
	dict_fill(&out, keys, values)
	return
}

// A new Dictionary typed to `K` and `V`, as GDScript's `Dictionary[K, V]`, built as `dict_of`
// builds. Each side is a builtin type, an engine class, or `Variant` for an untyped side.
dict_typed_of :: proc "contextless" (keys: []$K, values: []$V) -> (out: Dictionary) {
	out = dictionary_new()
	// An untyped side, `Variant`, has no class: the empty name.
	script: Variant
	when K == Variant { key_none: StringName; key_class := &key_none } else { key_class := typed_class(K) }
	when V == Variant { value_none: StringName; value_class := &value_none } else { value_class := typed_class(V) }
	gde.dictionary_set_typed(&out, variant_type(K), key_class, &script, variant_type(V), value_class, &script)
	dict_fill(&out, keys, values)
	return
}

// Adds `keys[i]` mapped to `values[i]` to `d`, writing each value in place: the engine's index
// inserts a null for a new key and returns the existing value for a repeated one.
@(private)
dict_fill :: proc "contextless" (d: ^Dictionary, keys: []$K, values: []$V) {
	if len(keys) != len(values) { fail("godot_odin: dict_of needs as many values as keys", "dict_of") }
	for key, i in keys {
		k := variant(key)
		slot := (^Variant)(gde.dictionary_operator_index(d, &k))
		gde.variant_destroy(&k)
		gde.variant_destroy(slot)
		variant_into(slot, values[i])
	}
}


// The characters of `s` as a writable slice. A shared String gets storage of its own first, as any
// write does; the slice stays valid until `s` is copied, resized or destroyed. `s` must be a String
// you own, not a borrowed parameter.
string_write :: proc "contextless" (s: ^String) -> []rune {
	n := string_length(s)
	if n <= 0 { return nil }
	return gde.string_operator_index(s, 0)[:n]
}

// Appends to `s` in place, growing its storage rather than building a new String: Odin UTF-8 text,
// another String, or one character. `s` must be a String you own.
string_append :: proc {string_append_text, string_append_string, string_append_rune}

string_append_text :: proc "contextless" (s: ^String, text: string) {
	// Parsed by the engine, as `string_of` is, so malformed bytes become what any other String
	// made from them holds.
	if len(text) == 0 { return }
	t := string_of(text)
	defer destroy[.STRING](&t)
	gde.string_operator_plus_eq_string(s, &t)
}

string_append_string :: proc "contextless" (s: ^String, b: String) {
	b := b
	gde.string_operator_plus_eq_string(s, &b)
}

string_append_rune :: proc "contextless" (s: ^String, r: rune) {
	gde.string_operator_plus_eq_char(s, r)
}

// The pixel bytes of `img`, read in place, laid out as its format (`image_get_format`) says. Valid
// until `img` is changed or freed. Do not write through it: the storage may be shared with copies.
image_read :: proc "contextless" (img: Image) -> []u8 {
	n := image_get_data_size(img)
	if n <= 0 { return nil }
	return gde.image_ptr(gde.ObjectPtr(img))[:n]
}

// The pixel bytes of `img` as a writable slice. Shared storage is copied first, as any write does.
// Valid until `img` is resized, converted or freed. A texture made from `img` does not see the
// writes until it is updated from it.
image_write :: proc "contextless" (img: Image) -> []u8 {
	n := image_get_data_size(img)
	if n <= 0 { return nil }
	return gde.image_ptrw(gde.ObjectPtr(img))[:n]
}

// Reads the next bytes of `f` into `dst`, up to its length, and returns how many it read: fewer at
// the end of the file.
file_read :: proc "contextless" (f: FileAccess, dst: []u8) -> int {
	if len(dst) == 0 { return 0 }
	return int(gde.file_access_get_buffer(gde.ConstObjectPtr(f), raw_data(dst), u64(len(dst))))
}

// Writes `src` to `f` at its position. `file_access_get_error` reports a failed write.
file_write :: proc "contextless" (f: FileAccess, src: []u8) {
	if len(src) == 0 { return }
	gde.file_access_store_buffer(gde.ObjectPtr(f), raw_data(src), u64(len(src)))
}
