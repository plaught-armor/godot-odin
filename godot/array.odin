package godot

import gde "../gdextension"

// Array reads answered from the engine's storage, with no call, once `check_array_layout` proved it
// at load: the generated `size`, `is_empty`, `get`, `front`, `back`, `find`, `rfind`, `count` and
// `has` try these first (tools/odin_bindgen.py IN_PLACE) and make the engine call only when they
// return false. Each answers as Array does in Godot 4.7-stable (core/variant/array.cpp,
// variant_call.cpp): elements compare with StringLikeVariantComparator, which is
// Variant::hash_compare (the same type, then the value, a float NaN equal to a NaN and -0 to 0) with
// a String equal to a StringName of the same text. The in-place search handles a value of the types
// whose comparison it computes; any other value, a value a typed array would convert or reject, or a
// String met by a StringName (and the reverse) goes to the engine. `get`, `front` and `back` copy the
// element in place, and leave an out-of-range index or an empty array, and its error, to the engine.

// True when an Array is the engine's ArrayPrivate as `array_stored` reads it. `check_array_layout`
// decides it at load; without it every read calls the engine.
@(private)
array_layout_known: bool

// Where ArrayPrivate keeps the pointer to its elements: after its 32-bit reference count, padded to
// 8 bytes, and the empty write proxy of its Vector<Variant>, padded to 8 bytes too. The elements
// follow the copy-on-write header that packed.odin reads, so the count sits PACKED_SIZE_OFFSET bytes
// before them.
@(private)
ARRAY_DATA_OFFSET :: 16

// Where ArrayPrivate keeps the element type of a typed array, the first field of its
// ContainerTypeValidate, after the pointer to the elements and the read-only pointer. NIL when the
// array is untyped.
@(private)
ARRAY_TYPED_OFFSET :: 32

#assert(size_of(Array) == size_of(rawptr))
#assert(size_of(Variant) == 24)

// The elements of `a`, read from its storage. Only when `array_layout_known`.
@(private)
array_stored :: #force_inline proc "contextless" (a: ^Array) -> []Variant {
	d := (^rawptr)(uintptr((^rawptr)(a)^) + ARRAY_DATA_OFFSET)^
	if d == nil { return nil }
	return ([^]Variant)(d)[:(^i64)(uintptr(d) - PACKED_SIZE_OFFSET)^]
}

// The element count of `a`, read from its storage. Only when `array_layout_known`; the generated
// `size` and `is_empty` use it then.
array_stored_size :: #force_inline proc "contextless" (a: ^Array) -> i64 {
	d := (^rawptr)(uintptr((^rawptr)(a)^) + ARRAY_DATA_OFFSET)^
	if d == nil { return 0 }
	return (^i64)(uintptr(d) - PACKED_SIZE_OFFSET)^
}

// The element type `a` is typed with, NIL when untyped. Only when `array_layout_known`.
@(private)
array_stored_type :: #force_inline proc "contextless" (a: ^Array) -> gde.VariantType {
	return gde.VariantType((^i32)(uintptr((^rawptr)(a)^) + ARRAY_TYPED_OFFSET)^)
}

// Sets `array_layout_known` from Arrays of known contents: one of three ints shared by two
// references, one grown by pushes so its capacity differs from its size, one emptied by a resize,
// and two typed ones.
check_array_layout :: proc "contextless" () {
	// The elements where the engine indexes them, after the header of reference count 1 (the
	// Vector is not shared, the ArrayPrivate is), capacity and size `n`.
	holds :: proc "contextless" (a: ^Array, n: i64) -> bool {
		d := (^rawptr)(uintptr((^rawptr)(a)^) + ARRAY_DATA_OFFSET)^
		if d == nil || d != rawptr(gde.array_operator_index_const(a, 0)) { return false }
		if rawptr(&([^]Variant)(d)[n - 1]) != rawptr(gde.array_operator_index_const(a, n - 1)) { return false }
		h := ([^]i64)(uintptr(d) - PACKED_DATA_OFFSET)
		return h[0] == 1 && h[1] >= n && h[2] == n && array_stored_type(a) == .NIL
	}
	a := array_new()
	for k in 0 ..< 3 { array_push_back(&a, variant(i64(k))) }
	b := array_new_from_array(a)
	c := array_new()
	for k in 0 ..< 37 { array_push_back(&c, variant(i64(k))) }
	e := array_new()
	array_resize(&e, 2)
	array_resize(&e, 0)
	no_class: StringName
	no_script: Variant
	ti := array_new()
	gde.array_set_typed(&ti, .INT, &no_class, &no_script)
	tn := array_new()
	gde.array_set_typed(&tn, .STRING_NAME, &no_class, &no_script)
	array_layout_known =
		holds(&a, 3) && holds(&b, 3) && holds(&c, 37) &&
		(^rawptr)(uintptr((^rawptr)(&e)^) + ARRAY_DATA_OFFSET)^ == nil && array_size(&e) == 0 &&
		array_stored_type(&ti) == .INT && array_stored_type(&tn) == .STRING_NAME
	for x in ([?]^Array{&tn, &ti, &e, &c, &b, &a}) { destroy[.ARRAY](x) }
}

// How the in-place reads compare and copy a Variant of each type: by its value at byte 8 (as
// `check_borrow_layout` proves) when it holds nothing counted or allocated, each float component
// equal to the same or to -0 for 0, NaN for NaN; a String by its text; a StringName by its name
// pointer, as StringName's `==` does; and ENGINE for a type the engine compares and copies.
@(private)
Array_Elem :: enum u8 {
	ENGINE,
	NIL,
	BOOL,
	WORD,
	DOUBLE,
	REAL_2,
	REAL_3,
	REAL_4,
	INT_2,
	INT_3,
	INT_4,
	STRING,
	NAME,
}

@(private)
ARRAY_ELEM := [gde.VariantType]Array_Elem {
	.NIL = .NIL, .BOOL = .BOOL, .INT = .WORD, .FLOAT = .DOUBLE, .STRING = .STRING,
	.VECTOR2 = .REAL_2, .VECTOR2I = .INT_2, .RECT2 = .REAL_4, .RECT2I = .INT_4,
	.VECTOR3 = .REAL_3, .VECTOR3I = .INT_3, .TRANSFORM2D = .ENGINE, .VECTOR4 = .REAL_4,
	.VECTOR4I = .INT_4, .PLANE = .REAL_4, .QUATERNION = .REAL_4, .AABB = .ENGINE, .BASIS = .ENGINE,
	.TRANSFORM3D = .ENGINE, .PROJECTION = .ENGINE, .COLOR = .REAL_4, .STRING_NAME = .NAME,
	.NODE_PATH = .ENGINE, .RID = .WORD, .OBJECT = .ENGINE, .CALLABLE = .ENGINE, .SIGNAL = .ENGINE,
	.DICTIONARY = .ENGINE, .ARRAY = .ENGINE, .PACKED_BYTE_ARRAY = .ENGINE,
	.PACKED_INT32_ARRAY = .ENGINE, .PACKED_INT64_ARRAY = .ENGINE, .PACKED_FLOAT32_ARRAY = .ENGINE,
	.PACKED_FLOAT64_ARRAY = .ENGINE, .PACKED_STRING_ARRAY = .ENGINE, .PACKED_VECTOR2_ARRAY = .ENGINE,
	.PACKED_VECTOR3_ARRAY = .ENGINE, .PACKED_COLOR_ARRAY = .ENGINE, .PACKED_VECTOR4_ARRAY = .ENGINE,
	.VARIANT_MAX = .ENGINE,
}

// The kind of `t`; ENGINE for a tag outside the table.
@(private)
array_elem :: #force_inline proc "contextless" (t: gde.VariantType) -> Array_Elem {
	return ARRAY_ELEM[t] if u32(t) < u32(gde.VariantType.VARIANT_MAX) else .ENGINE
}

// The value of a NIL Variant: none, so two NILs are always equal.
@(private)
Array_Nil :: struct {}

// Which search `array_search` runs.
@(private)
Array_Search :: enum u8 { FIND, RFIND, COUNT }

// Whether `a` and `b` are the same float under Math::is_same.
@(private)
float_same :: #force_inline proc "contextless" (a, b: $F) -> bool {
	return a == b || (a != a && b != b)
}

// Whether the values of Variants `x` and `v`, both of the type whose value is an `E`, compare equal
// under Variant::hash_compare.
@(private)
array_value_same :: #force_inline proc "contextless" ($E: typeid, x, v: ^Variant) -> bool {
	p, q := (^E)(&x._opaque[8]), (^E)(&v._opaque[8])
	when E == String {
		return elem_eq(p, q)
	} else when E == f64 {
		return float_same(p^, q^)
	} else when E == [2]f32 || E == [3]f32 || E == [4]f32 {
		#unroll for k in 0 ..< len(p^) { if !float_same(p[k], q[k]) { return false } }
		return true
	} else {
		return p^ == q^
	}
}

// The search `op` for `v` over `xs`, whose values compare as `E`s: the first index from `from` up
// for FIND, the last from `from` down for RFIND, both -1 when none matches, or the count of matches
// for COUNT. False when an element of type `cross`, which StringLikeVariantComparator compares by
// text, is met first: the engine answers then.
@(private)
array_scan :: proc "contextless" ($E: typeid, xs: []Variant, v: ^Variant, cross: gde.VariantType, from: i64, $OP: Array_Search) -> (i64, bool) {
	tag := variant_tag(v)
	n := i64(len(xs))
	when OP == .RFIND {
		for k in 0 ..= from {
			x := &xs[from - k]
			t := variant_tag(x)
			if t == cross { return 0, false }
			hit := t == tag
			when E != Array_Nil { hit = hit && array_value_same(E, x, v) }
			if hit { return from - k, true }
		}
		return -1, true
	} else {
		found := i64(0)
		for i in from ..< n {
			x := &xs[i]
			t := variant_tag(x)
			if t == cross { return 0, false }
			hit := t == tag
			when E != Array_Nil { hit = hit && array_value_same(E, x, v) }
			when OP == .FIND {
				if hit { return i, true }
			} else {
				found += i64(hit)
			}
		}
		when OP == .FIND { return -1, true } else { return found, true }
	}
}

// `array_scan` for the kind of `v`. False for a kind the engine compares.
@(private)
array_search :: proc "contextless" (xs: []Variant, v: ^Variant, from: i64, $OP: Array_Search) -> (i64, bool) {
	no := gde.VariantType.VARIANT_MAX
	switch array_elem(variant_tag(v)) {
	case .ENGINE: return 0, false
	case .NIL:    return array_scan(Array_Nil, xs, v, no, from, OP)
	case .BOOL:   return array_scan(u8, xs, v, no, from, OP)
	case .WORD:   return array_scan(i64, xs, v, no, from, OP)
	case .DOUBLE: return array_scan(f64, xs, v, no, from, OP)
	case .REAL_2: return array_scan([2]f32, xs, v, no, from, OP)
	case .REAL_3: return array_scan([3]f32, xs, v, no, from, OP)
	case .REAL_4: return array_scan([4]f32, xs, v, no, from, OP)
	case .INT_2:  return array_scan([2]i32, xs, v, no, from, OP)
	case .INT_3:  return array_scan([3]i32, xs, v, no, from, OP)
	case .INT_4:  return array_scan([4]i32, xs, v, no, from, OP)
	case .STRING: return array_scan(String, xs, v, .STRING_NAME, from, OP)
	case .NAME:   return array_scan(rawptr, xs, v, .STRING, from, OP)
	}
	return 0, false
}

// The elements of `a` when the engine would search them for `v` without converting it: the array
// untyped or typed as `v`'s type. False otherwise, or before `check_array_layout` proved the layout.
@(private)
array_searchable :: #force_inline proc "contextless" (a: ^Array, v: ^Variant) -> ([]Variant, bool) {
	if !array_layout_known { return nil, false }
	typed := array_stored_type(a)
	if typed != .NIL && typed != variant_tag(v) { return nil, false }
	return array_stored(a), true
}

// Array.find in place: the first index from `from` up of an element equal to `v`, or -1. The start
// is the engine's int, so the low 32 bits of `from`, and a negative one finds nothing. False when the
// engine answers.
array_stored_find :: #force_inline proc "contextless" (a: ^Array, v: Variant, from: i64) -> (i64, bool) {
	v := v
	xs, ok := array_searchable(a, &v)
	if !ok { return 0, false }
	from := i64(i32(from))
	if len(xs) == 0 || from < 0 { return -1, true }
	return array_search(xs, &v, from, .FIND)
}

// Array.rfind in place: the last index from `from` down of an element equal to `v`, or -1. A
// negative start counts from the end, and one still outside the array starts at the last element.
// The start is the engine's int, so the low 32 bits of `from`. False when the engine answers.
array_stored_rfind :: #force_inline proc "contextless" (a: ^Array, v: Variant, from: i64) -> (i64, bool) {
	v := v
	xs, ok := array_searchable(a, &v)
	if !ok { return 0, false }
	n := i64(len(xs))
	if n == 0 { return -1, true }
	from := i64(i32(from))
	if from < 0 { from += n }
	if from < 0 || from >= n { from = n - 1 }
	return array_search(xs, &v, from, .RFIND)
}

// Array.count in place: how many elements equal `v`. False when the engine answers.
array_stored_count :: #force_inline proc "contextless" (a: ^Array, v: Variant) -> (i64, bool) {
	v := v
	xs, ok := array_searchable(a, &v)
	if !ok { return 0, false }
	return array_search(xs, &v, 0, .COUNT)
}

// Array.has in place: whether an element equals `v`. False when the engine answers.
array_stored_has :: #force_inline proc "contextless" (a: ^Array, v: Variant) -> (bool, bool) {
	at, ok := array_stored_find(a, v, 0)
	return at != -1, ok
}

// Array.get in place: a copy of element `index`, its value copied as is when it holds nothing
// counted or allocated and through the engine's Variant copy otherwise. False when the engine
// answers, as it does for an index out of range, with its error.
array_stored_get :: #force_inline proc "contextless" (a: ^Array, index: i64) -> (out: Variant, ok: bool) {
	if !array_layout_known { return }
	xs := array_stored(a)
	if index < 0 || index >= i64(len(xs)) { return }
	return stored_copy(&xs[index]), true
}

// A copy of `x`, its value copied as is when it holds nothing counted or allocated and through the
// engine's Variant copy otherwise. You destroy it.
@(private)
stored_copy :: #force_inline proc "contextless" (x: ^Variant) -> (out: Variant) {
	switch array_elem(variant_tag(x)) {
	case .ENGINE, .STRING, .NAME: gde.variant_new_copy(&out, x)
	case .NIL, .BOOL, .WORD, .DOUBLE, .REAL_2, .REAL_3, .REAL_4, .INT_2, .INT_3, .INT_4: out = x^
	}
	return
}

// Array.front in place: a copy of the first element. False when the engine answers, as it does for
// an empty array, with its error.
array_stored_front :: #force_inline proc "contextless" (a: ^Array) -> (Variant, bool) {
	return array_stored_get(a, 0)
}

// Array.back in place: a copy of the last element. False when the engine answers, as it does for an
// empty array, with its error.
array_stored_back :: #force_inline proc "contextless" (a: ^Array) -> (Variant, bool) {
	if !array_layout_known { return {}, false }
	return array_stored_get(a, array_stored_size(a) - 1)
}
