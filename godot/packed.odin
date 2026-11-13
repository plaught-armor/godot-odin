package godot

import "base:intrinsics"
import gde "../gdextension"

// Packed array reads computed in place, under the names and signatures the bindings generated
// before: `get`, `has`, `find`, `rfind`, `count` and `bsearch` of the ten packed array types, read
// from the elements `packed_read` hands out with no engine call once `check_packed_layout` proved
// the storage at load. The generated `size` and `is_empty` read the size from the same header then
// (tools/odin_bindgen.py IN_PLACE). Each answers as Vector<T> does in Godot 4.7-stable
// (core/templates/vector.h, span.h, core/variant/variant_call.cpp): the value is converted to the
// element type first, as the ptrcall does (an integer truncated to a byte or 32 bits, a float
// rounded to single precision), elements compare with the element type's `==`, so a NaN is never
// found, and `bsearch` orders with its `<`. tools/odin_bindgen.py REPLACED leaves these names out of
// godot/gen_builtins.odin.

// True when a packed array is the engine's Vector<T> as `packed_stored` reads it: a pointer to the
// elements in its second 64-bit word, null when empty, after the copy-on-write header of 64-bit
// reference count, capacity and size, the size an element count 16 bytes before the elements.
// `check_packed_layout` decides it at load; without it the reads ask the engine for the size and
// the elements.
@(private)
packed_layout_known: bool

// The word of a packed array that holds its element pointer: Vector<T> keeps an empty write
// proxy, padded to 8 bytes, before its CowData.
@(private)
PACKED_DATA_WORD :: 1

// Where the size sits before a packed array's elements.
@(private)
PACKED_SIZE_OFFSET :: 16

// Where a packed array's elements sit after the start of its storage: the reference count, capacity
// and size, each 64 bits, padded to 16 bytes.
@(private)
PACKED_DATA_OFFSET :: 32
// Elements `packed_find` and `packed_rfind` test per block before looking for which one matched.
@(private)
PACKED_BLOCK :: 8

#assert(size_of(PackedByteArray) == 2 * size_of(rawptr))

// The elements of packed array `a` read from its storage, as `check_packed_layout` proved it. Only
// when `packed_layout_known`.
@(private)
packed_stored :: #force_inline proc "contextless" ($E: typeid, a: rawptr) -> []E {
	p := ([^]rawptr)(a)[PACKED_DATA_WORD]
	if p == nil { return nil }
	return ([^]E)(p)[:(^i64)(uintptr(p) - PACKED_SIZE_OFFSET)^]
}

// The element count of packed array `a`, read from its storage's header. Only when
// `packed_layout_known`; the generated `size` and `is_empty` use it then, and ask the engine
// otherwise.
packed_stored_size :: #force_inline proc "contextless" (a: rawptr) -> i64 {
	p := ([^]rawptr)(a)[PACKED_DATA_WORD]
	if p == nil { return 0 }
	return (^i64)(uintptr(p) - PACKED_SIZE_OFFSET)^
}

// Sets `packed_layout_known` from packed arrays of known size: one shared by two references, one
// grown by a push so its capacity differs from its size, and one emptied by a resize.
check_packed_layout :: proc "contextless" () {
	// The header before the elements: the reference count, the capacity, then the size.
	holds :: proc "contextless" (a: rawptr, data: rawptr, n: i64, refs: i64) -> bool {
		p := ([^]rawptr)(a)[PACKED_DATA_WORD]
		if p == nil || p != data { return false }
		h := ([^]i64)(uintptr(p) - PACKED_DATA_OFFSET)
		return h[0] == refs && h[1] >= n && h[2] == n && uintptr(p) - PACKED_SIZE_OFFSET == uintptr(&h[2])
	}
	a := packed_byte_array_new()
	packed_byte_array_resize(&a, 3)
	b := packed_byte_array_new_from_packed_byte_array(a)
	c := packed_vector3_array_new()
	packed_vector3_array_resize(&c, 37)
	packed_vector3_array_push_back(&c, Vector3{})
	e := packed_int64_array_new()
	packed_int64_array_resize(&e, 2)
	packed_int64_array_resize(&e, 0)
	packed_layout_known =
		holds(&a, gde.packed_byte_array_operator_index_const(&a, 0), 3, 2) &&
		holds(&b, gde.packed_byte_array_operator_index_const(&b, 0), 3, 2) &&
		holds(&c, gde.packed_vector3_array_operator_index_const(&c, 0), 38, 1) &&
		([^]rawptr)(&e)[PACKED_DATA_WORD] == nil
	destroy[.PACKED_INT64_ARRAY](&e)
	destroy[.PACKED_VECTOR3_ARRAY](&c)
	destroy[.PACKED_BYTE_ARRAY](&b)
	destroy[.PACKED_BYTE_ARRAY](&a)
}

// Element `index` of `xs`, or the engine's out-of-bounds error and false, as `get` reports it.
@(private)
packed_at :: #force_inline proc "contextless" (xs: []$E, index: i64) -> (E, bool) {
	if index < 0 || index >= i64(len(xs)) {
		packed_index_error(index, i64(len(xs)))
		return {}, false
	}
	return xs[index], true
}

// Logs ERR_FAIL_INDEX_V's message for `get` at `index` of an array of `n` elements.
@(private)
packed_index_error :: proc "contextless" (index, n: i64) {
	buf: [128]u8
	k := copy(buf[:], "Index p_index = ")
	k += decimal_into(buf[k:], index)
	k += copy(buf[k:], " is out of bounds (p_instance->size() = ")
	k += decimal_into(buf[k:], n)
	k += copy(buf[k:], ").")
	buf[k] = 0
	gde.print_error(cstring(&buf[0]), "", #file, #line, 1)
}

// Writes `v` in decimal at the start of `buf`, which holds 20 bytes or more, and returns the count.
@(private)
decimal_into :: proc "contextless" (buf: []u8, v: i64) -> int {
	digits: [20]u8
	m := u64(v) if v >= 0 else u64(0) - u64(v)
	d := len(digits)
	for _ in 0 ..< len(digits) {
		d -= 1
		digits[d] = u8('0' + m % 10)
		m /= 10
		if m == 0 { break }
	}
	k := 0
	if v < 0 { buf[0] = '-'; k = 1 }
	return k + copy(buf[k:], digits[d:])
}

// Whether two elements are equal under their type's `==`: per component for the vectors and Color,
// so -0 equals 0 and a NaN equals nothing.
@(private)
elem_eq :: #force_inline proc "contextless" (a, b: ^$E) -> bool {
	when E == String {
		// string_equal's in-place test, inlined so a search checks the layout once, not per element.
		if !string_layout_known { return string_equal(a, b) }
		pa, pb := (^rawptr)(a)^, (^rawptr)(b)^
		if pa == pb { return true }
		n := string_stored_length(a)
		return n == string_stored_length(b) && runes_equal(([^]rune)(pa), ([^]rune)(pb), int(n))
	} else when E == Vector4 || E == Color {
		// Four floats compared as one vector: the same `==` per component, in one instruction.
		x := intrinsics.unaligned_load((^#simd[4]f32)(a))
		y := intrinsics.unaligned_load((^#simd[4]f32)(b))
		return intrinsics.simd_reduce_and(intrinsics.simd_lanes_eq(x, y)) != 0
	} else when intrinsics.type_is_array(E) {
		// Every component compared and the answers combined, so a search has no branch per component.
		eq := true
		#unroll for i in 0 ..< len(E) { eq &= a[i] == b[i] }
		return eq
	} else {
		return a^ == b^
	}
}

// Whether `a` sorts before `b` under their type's `<`: the vectors and Color compare a component
// only when the ones before it are `==`, and Strings by character code up to the first difference
// or terminator.
@(private)
elem_less :: #force_inline proc "contextless" (a, b: ^$E) -> bool {
	when E == String {
		return string_less(a, b)
	} else when intrinsics.type_is_array(E) {
		when len(E) == 2 {
			// Two components with no branch: the first is less, or equal with the second less. A
			// NaN is neither, so it ends the comparison as false. Slower than branches from three
			// components up.
			return (a[0] < b[0]) | ((a[0] == b[0]) & (a[1] < b[1]))
		} else {
			#unroll for i in 0 ..< len(E) - 1 { if a[i] != b[i] { return a[i] < b[i] } }
			return a[len(E) - 1] < b[len(E) - 1]
		}
	} else {
		return a^ < b^
	}
}

// String's `<`: the characters compared as unsigned codes until one differs or `a` ends, its end
// read as the terminator 0, as str_compare reads it.
@(private)
string_less :: #force_inline proc "contextless" (a, b: ^String) -> bool {
	x, y := string_read(a), string_read(b)
	n := min(len(x), len(y))
	#no_bounds_check for i in 0 ..< n {
		l, r := u32(x[i]), u32(y[i])
		if l == 0 || l != r { return l < r }
	}
	// Equal so far: `a` is less only when it ends here and `b` goes on with a character.
	#no_bounds_check return len(x) == n && n < len(y) && y[n] != 0
}

// Vector::find: the first `v` at or after `from`, a negative `from` counting back from the end, or
// -1, also for a `from` outside the array.
@(private)
packed_find :: proc "contextless" (xs: []$E, v: ^E, from: i64) -> i64 {
	n := i64(len(xs))
	from := from + n if from < 0 else from
	if from < 0 || from >= n { return -1 }
	start := from
	when E != String && E != Vector4 && E != Color {
		// Whole blocks of PACKED_BLOCK tested with no branch per element, so the compares vectorize;
		// the block holding the first `v` is then searched one by one. Not for Vector4 and Color:
		// one of those is a whole vector compare already, and searching a block twice costs more.
		#no_bounds_check for _ in 0 ..< (n - from) / PACKED_BLOCK {
			hit := false
			#unroll for k in 0 ..< PACKED_BLOCK { hit |= elem_eq(&xs[start + i64(k)], v) }
			if hit { break }
			start += PACKED_BLOCK
		}
	}
	#no_bounds_check for i in start ..< n { if elem_eq(&xs[i], v) { return i } }
	return -1
}

// Vector::rfind: the last `v` at or before `from`, `from` read as in `packed_find`.
@(private)
packed_rfind :: proc "contextless" (xs: []$E, v: ^E, from: i64) -> i64 {
	n := i64(len(xs))
	from := from + n if from < 0 else from
	if from < 0 || from >= n { return -1 }
	last := from
	when E != String && E != Vector4 && E != Color {
		// Blocks ending at `last`, tested as in `packed_find`, going down.
		#no_bounds_check for _ in 0 ..< (from + 1) / PACKED_BLOCK {
			hit := false
			#unroll for k in 0 ..< PACKED_BLOCK { hit |= elem_eq(&xs[last - i64(k)], v) }
			if hit { break }
			last -= PACKED_BLOCK
		}
	}
	#no_bounds_check for i := last; i >= 0; i -= 1 {
		if elem_eq(&xs[i], v) { return i }
	}
	return -1
}

// Vector::count: how many elements equal `v`.
@(private)
packed_count :: proc "contextless" (xs: []$E, v: ^E) -> (c: i64) {
	when size_of(E) == 1 {
		// Bytes are counted 255 at a time into a byte, so the compares stay sixteen to an
		// instruction and are not widened to the 64-bit total one by one.
		CHUNK :: 255
		rest := xs
		for _ in 0 ..= len(xs) / CHUNK {
			part := rest[:min(len(rest), CHUNK)]
			hits: u8
			for &x in part { hits += u8(elem_eq(&x, v)) }
			c += i64(hits)
			rest = rest[len(part):]
		}
	} else {
		for &x in xs { if elem_eq(&x, v) { c += 1 } }
	}
	return
}

// Span::bisect: where `v` goes in sorted `xs`, before the elements equal to it when `before`, after
// them otherwise.
@(private)
packed_bsearch :: proc "contextless" (xs: []$E, v: ^E, before: bool) -> i64 {
	lo, hi := 0, len(xs)
	// Each step halves hi - lo, so 64 steps cover any length. One loop per `before`, so the choice
	// is made once, and mid is always below len(xs).
	if before {
		#no_bounds_check for _ in 0 ..< 64 {
			if lo >= hi { break }
			mid := int(uint(lo + hi) >> 1)
			if elem_less(&xs[mid], v) { lo = mid + 1 } else { hi = mid }
		}
	} else {
		#no_bounds_check for _ in 0 ..< 64 {
			if lo >= hi { break }
			mid := int(uint(lo + hi) >> 1)
			if !elem_less(v, &xs[mid]) { lo = mid + 1 } else { hi = mid }
		}
	}
	return i64(lo)
}

packed_byte_array_get :: proc "contextless" (self: ^PackedByteArray, index: i64) -> i64 { v, _ := packed_at(packed_read(self), index); return i64(v) }
packed_byte_array_has :: proc "contextless" (self: ^PackedByteArray, value: i64) -> bool { v := u8(value); return packed_find(packed_read(self), &v, 0) != -1 }
packed_byte_array_find :: proc "contextless" (self: ^PackedByteArray, value: i64, from: i64) -> i64 { v := u8(value); return packed_find(packed_read(self), &v, from) }
packed_byte_array_rfind :: proc "contextless" (self: ^PackedByteArray, value: i64, from: i64) -> i64 { v := u8(value); return packed_rfind(packed_read(self), &v, from) }
packed_byte_array_count :: proc "contextless" (self: ^PackedByteArray, value: i64) -> i64 { v := u8(value); return packed_count(packed_read(self), &v) }
packed_byte_array_bsearch :: proc "contextless" (self: ^PackedByteArray, value: i64, before: bool) -> i64 { v := u8(value); return packed_bsearch(packed_read(self), &v, before) }

packed_int32_array_get :: proc "contextless" (self: ^PackedInt32Array, index: i64) -> i64 { v, _ := packed_at(packed_read(self), index); return i64(v) }
packed_int32_array_has :: proc "contextless" (self: ^PackedInt32Array, value: i64) -> bool { v := i32(value); return packed_find(packed_read(self), &v, 0) != -1 }
packed_int32_array_find :: proc "contextless" (self: ^PackedInt32Array, value: i64, from: i64) -> i64 { v := i32(value); return packed_find(packed_read(self), &v, from) }
packed_int32_array_rfind :: proc "contextless" (self: ^PackedInt32Array, value: i64, from: i64) -> i64 { v := i32(value); return packed_rfind(packed_read(self), &v, from) }
packed_int32_array_count :: proc "contextless" (self: ^PackedInt32Array, value: i64) -> i64 { v := i32(value); return packed_count(packed_read(self), &v) }
packed_int32_array_bsearch :: proc "contextless" (self: ^PackedInt32Array, value: i64, before: bool) -> i64 { v := i32(value); return packed_bsearch(packed_read(self), &v, before) }

packed_int64_array_get :: proc "contextless" (self: ^PackedInt64Array, index: i64) -> i64 { v, _ := packed_at(packed_read(self), index); return v }
packed_int64_array_has :: proc "contextless" (self: ^PackedInt64Array, value: i64) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_int64_array_find :: proc "contextless" (self: ^PackedInt64Array, value: i64, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_int64_array_rfind :: proc "contextless" (self: ^PackedInt64Array, value: i64, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_int64_array_count :: proc "contextless" (self: ^PackedInt64Array, value: i64) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_int64_array_bsearch :: proc "contextless" (self: ^PackedInt64Array, value: i64, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

packed_float32_array_get :: proc "contextless" (self: ^PackedFloat32Array, index: i64) -> f64 { v, _ := packed_at(packed_read(self), index); return f64(v) }
packed_float32_array_has :: proc "contextless" (self: ^PackedFloat32Array, value: f64) -> bool { v := f32(value); return packed_find(packed_read(self), &v, 0) != -1 }
packed_float32_array_find :: proc "contextless" (self: ^PackedFloat32Array, value: f64, from: i64) -> i64 { v := f32(value); return packed_find(packed_read(self), &v, from) }
packed_float32_array_rfind :: proc "contextless" (self: ^PackedFloat32Array, value: f64, from: i64) -> i64 { v := f32(value); return packed_rfind(packed_read(self), &v, from) }
packed_float32_array_count :: proc "contextless" (self: ^PackedFloat32Array, value: f64) -> i64 { v := f32(value); return packed_count(packed_read(self), &v) }
packed_float32_array_bsearch :: proc "contextless" (self: ^PackedFloat32Array, value: f64, before: bool) -> i64 { v := f32(value); return packed_bsearch(packed_read(self), &v, before) }

packed_float64_array_get :: proc "contextless" (self: ^PackedFloat64Array, index: i64) -> f64 { v, _ := packed_at(packed_read(self), index); return v }
packed_float64_array_has :: proc "contextless" (self: ^PackedFloat64Array, value: f64) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_float64_array_find :: proc "contextless" (self: ^PackedFloat64Array, value: f64, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_float64_array_rfind :: proc "contextless" (self: ^PackedFloat64Array, value: f64, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_float64_array_count :: proc "contextless" (self: ^PackedFloat64Array, value: f64) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_float64_array_bsearch :: proc "contextless" (self: ^PackedFloat64Array, value: f64, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

// Owns what it answers: destroy it. Out of bounds, an empty String.
packed_string_array_get :: proc "contextless" (self: ^PackedStringArray, index: i64) -> String {
	v, ok := packed_at(packed_read(self), index)
	if !ok { return {} }
	return string_copy(&v)
}
packed_string_array_has :: proc "contextless" (self: ^PackedStringArray, value: String) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_string_array_find :: proc "contextless" (self: ^PackedStringArray, value: String, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_string_array_rfind :: proc "contextless" (self: ^PackedStringArray, value: String, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_string_array_count :: proc "contextless" (self: ^PackedStringArray, value: String) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_string_array_bsearch :: proc "contextless" (self: ^PackedStringArray, value: String, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

packed_vector2_array_get :: proc "contextless" (self: ^PackedVector2Array, index: i64) -> Vector2 { v, _ := packed_at(packed_read(self), index); return v }
packed_vector2_array_has :: proc "contextless" (self: ^PackedVector2Array, value: Vector2) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_vector2_array_find :: proc "contextless" (self: ^PackedVector2Array, value: Vector2, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_vector2_array_rfind :: proc "contextless" (self: ^PackedVector2Array, value: Vector2, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_vector2_array_count :: proc "contextless" (self: ^PackedVector2Array, value: Vector2) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_vector2_array_bsearch :: proc "contextless" (self: ^PackedVector2Array, value: Vector2, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

packed_vector3_array_get :: proc "contextless" (self: ^PackedVector3Array, index: i64) -> Vector3 { v, _ := packed_at(packed_read(self), index); return v }
packed_vector3_array_has :: proc "contextless" (self: ^PackedVector3Array, value: Vector3) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_vector3_array_find :: proc "contextless" (self: ^PackedVector3Array, value: Vector3, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_vector3_array_rfind :: proc "contextless" (self: ^PackedVector3Array, value: Vector3, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_vector3_array_count :: proc "contextless" (self: ^PackedVector3Array, value: Vector3) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_vector3_array_bsearch :: proc "contextless" (self: ^PackedVector3Array, value: Vector3, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

packed_vector4_array_get :: proc "contextless" (self: ^PackedVector4Array, index: i64) -> Vector4 { v, _ := packed_at(packed_read(self), index); return v }
packed_vector4_array_has :: proc "contextless" (self: ^PackedVector4Array, value: Vector4) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_vector4_array_find :: proc "contextless" (self: ^PackedVector4Array, value: Vector4, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_vector4_array_rfind :: proc "contextless" (self: ^PackedVector4Array, value: Vector4, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_vector4_array_count :: proc "contextless" (self: ^PackedVector4Array, value: Vector4) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_vector4_array_bsearch :: proc "contextless" (self: ^PackedVector4Array, value: Vector4, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }

// Out of range, the engine returns Color(), which is opaque black, not zero.
packed_color_array_get :: proc "contextless" (self: ^PackedColorArray, index: i64) -> Color {
	v, ok := packed_at(packed_read(self), index)
	return v if ok else Color{0, 0, 0, 1}
}
packed_color_array_has :: proc "contextless" (self: ^PackedColorArray, value: Color) -> bool { v := value; return packed_find(packed_read(self), &v, 0) != -1 }
packed_color_array_find :: proc "contextless" (self: ^PackedColorArray, value: Color, from: i64) -> i64 { v := value; return packed_find(packed_read(self), &v, from) }
packed_color_array_rfind :: proc "contextless" (self: ^PackedColorArray, value: Color, from: i64) -> i64 { v := value; return packed_rfind(packed_read(self), &v, from) }
packed_color_array_count :: proc "contextless" (self: ^PackedColorArray, value: Color) -> i64 { v := value; return packed_count(packed_read(self), &v) }
packed_color_array_bsearch :: proc "contextless" (self: ^PackedColorArray, value: Color, before: bool) -> i64 { v := value; return packed_bsearch(packed_read(self), &v, before) }
