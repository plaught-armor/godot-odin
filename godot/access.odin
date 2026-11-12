// Direct access to engine storage: packed arrays, Strings, Arrays, Images and files read and written
// through the pointers the interface hands out, instead of one builtin or method call per element.
package godot

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
