// Odin values in and out of Variants and ptrcall slots, chosen by the Odin type at compile time.
// Hand-written; the class registration in class.odin builds its call paths from these.
package godot

import "base:intrinsics"
import gde "../gdextension"

// Variant <-> typed value conversions, fetched once by `load_variants` for every Variant type.
to_type: [gde.VariantType]gde.TypeFromVariantConstructorFunc
from_type: [gde.VariantType]gde.VariantFromTypeConstructorFunc
make_empty: [gde.VariantType]gde.PtrConstructor
destroy: [gde.VariantType]gde.PtrDestructor
copy_from: [gde.VariantType]gde.PtrConstructor
internal: [gde.VariantType]gde.VariantGetInternalPtrFunc

// Fills the conversion tables. Called once at load, before any class registers.
load_variants :: proc "contextless" () {
	for type in gde.VariantType {
		if type == .NIL || type == .VARIANT_MAX { continue }
		to_type[type] = gde.get_variant_to_type_constructor(type)
		from_type[type] = gde.get_variant_from_type_constructor(type)
		make_empty[type] = gde.variant_get_ptr_constructor(type, 0)
		destroy[type] = gde.variant_get_ptr_destructor(type)
		copy_from[type] = gde.variant_get_ptr_constructor(type, 1)
		internal[type] = gde.variant_get_ptr_internal_getter(type)
	}
	check_borrow_layout()
	check_string_layout()
	check_packed_layout()
	check_array_layout()
}

// The Variant type an Odin type crosses as: bool, any integer, enum or bit_set, any float, a builtin struct,
// an engine class (any `distinct rawptr`) or a pointer to a registered class's struct as OBJECT,
// an Odin `string` as STRING, and Variant itself as NIL.
variant_type :: proc "contextless" ($A: typeid) -> gde.VariantType {
	when A == bool { return .BOOL }
	else when intrinsics.type_is_integer(A) || intrinsics.type_is_enum(A) || intrinsics.type_is_bit_set(A) { return .INT }
	else when intrinsics.type_is_float(A) { return .FLOAT }
	else when A == String || A == string { return .STRING }
	else when A == Vector2 { return .VECTOR2 }
	else when A == Vector2i { return .VECTOR2I }
	else when A == Rect2 { return .RECT2 }
	else when A == Rect2i { return .RECT2I }
	else when A == Vector3 { return .VECTOR3 }
	else when A == Vector3i { return .VECTOR3I }
	else when A == Transform2D { return .TRANSFORM2D }
	else when A == Vector4 { return .VECTOR4 }
	else when A == Vector4i { return .VECTOR4I }
	else when A == Plane { return .PLANE }
	else when A == Quaternion { return .QUATERNION }
	else when A == AABB { return .AABB }
	else when A == Basis { return .BASIS }
	else when A == Transform3D { return .TRANSFORM3D }
	else when A == Projection { return .PROJECTION }
	else when A == Color { return .COLOR }
	else when A == StringName { return .STRING_NAME }
	else when A == NodePath { return .NODE_PATH }
	else when A == RID { return .RID }
	else when A == Callable { return .CALLABLE }
	else when A == Signal { return .SIGNAL }
	else when A == Dictionary { return .DICTIONARY }
	else when A == Array { return .ARRAY }
	else when A == PackedByteArray { return .PACKED_BYTE_ARRAY }
	else when A == PackedInt32Array { return .PACKED_INT32_ARRAY }
	else when A == PackedInt64Array { return .PACKED_INT64_ARRAY }
	else when A == PackedFloat32Array { return .PACKED_FLOAT32_ARRAY }
	else when A == PackedFloat64Array { return .PACKED_FLOAT64_ARRAY }
	else when A == PackedStringArray { return .PACKED_STRING_ARRAY }
	else when A == PackedVector2Array { return .PACKED_VECTOR2_ARRAY }
	else when A == PackedVector3Array { return .PACKED_VECTOR3_ARRAY }
	else when A == PackedColorArray { return .PACKED_COLOR_ARRAY }
	else when A == PackedVector4Array { return .PACKED_VECTOR4_ARRAY }
	else when A == Variant { return .NIL }
	else when intrinsics.type_base_type(A) == rawptr { return .OBJECT }
	else when intrinsics.type_is_pointer(A) && intrinsics.type_is_struct(intrinsics.type_elem_type(A)) { return .OBJECT }
	else { #panic("godot_odin: this Odin type has no Variant type") }
}

// The argument metadata the engine shows for an Odin type: the integer or float width.
variant_meta :: proc "contextless" ($A: typeid) -> gde.ClassMethodArgumentMetadata {
	when A == i8 { return .INT_IS_INT8 }
	else when A == i16 { return .INT_IS_INT16 }
	else when A == i32 { return .INT_IS_INT32 }
	else when A == i64 || A == int { return .INT_IS_INT64 }
	else when A == u8 { return .INT_IS_UINT8 }
	else when A == u16 { return .INT_IS_UINT16 }
	else when A == u32 { return .INT_IS_UINT32 }
	else when A == u64 || A == uint { return .INT_IS_UINT64 }
	else when A == f32 { return .REAL_IS_FLOAT }
	else when A == f64 { return .REAL_IS_DOUBLE }
	else { return .NONE }
}

// True for the Variant types that own a reference: copying one bitwise borrows it, and a copy made
// by a constructor must be destroyed.
counted :: proc "contextless" (type: gde.VariantType) -> bool {
	#partial switch type {
	case .STRING, .STRING_NAME, .NODE_PATH, .CALLABLE, .SIGNAL, .DICTIONARY, .ARRAY, .NIL:
		return true
	}
	return type >= .PACKED_BYTE_ARRAY && type < .VARIANT_MAX
}

// A bit_set as the engine's flags integer: bit `k` set for element value `k`. The set's lowest
// element must be 0 (`enumerate_flags` and `fields` check), so its bits are the engine's.
bits_of :: #force_inline proc "contextless" (value: $A) -> i64 where intrinsics.type_is_bit_set(A) {
	return i64(transmute(intrinsics.type_bit_set_underlying_type(A))value)
}

// The bit_set `A` for the engine's flags integer `bits`; bits past the set's width are dropped.
set_of :: #force_inline proc "contextless" ($A: typeid, bits: i64) -> A where intrinsics.type_is_bit_set(A) {
	return transmute(A)intrinsics.type_bit_set_underlying_type(A)(bits)
}

// A ptrcall argument as Odin type `A`, borrowed for the call when it owns a reference. The engine
// passes every integer as int64, every float as double, a bool as one byte, an object by pointer.
// A pointer to a registered class's struct is the object's instance, nil when the object is null
// or of another class. A null object may arrive as a nil slot rather than a slot holding nil. An
// Odin `string` is a UTF-8 copy in the temp allocator, valid until the engine call returns.
from_slot :: #force_inline proc "contextless" ($A: typeid, p: gde.ConstTypePtr) -> A {
	when A == bool { return (^u8)(p)^ != 0 }
	else when intrinsics.type_is_integer(A) || intrinsics.type_is_enum(A) { return A((^i64)(p)^) }
	else when intrinsics.type_is_bit_set(A) { return set_of(A, (^i64)(p)^) }
	else when intrinsics.type_is_float(A) { return A((^f64)(p)^) }
	else when intrinsics.type_base_type(A) == rawptr { return nil if p == nil else A((^rawptr)(p)^) }
	else when intrinsics.type_is_pointer(A) {
		if p == nil { return nil }
		return A(instance_raw((^rawptr)(p)^, class_slot(intrinsics.type_elem_type(A))^))
	}
	else when A == string {
		context = ctx
		return utf8((^String)(p)^, context.temp_allocator)
	}
	else { return (^A)(p)^ }
}

// Returns `obj` into a ptrcall slot, handing over the one reference a counted object's return carries.
@(private)
object_to_slot :: proc "contextless" (p: gde.TypePtr, obj: rawptr) {
	if obj == nil {
		(^rawptr)(p)^ = nil
		return
	}
	context = ctx
	if rc := counted_object(obj); rc != nil {
		gde.ref_set_object(p, gde.ObjectPtr(obj))
		ref_counted_unreference(rc)
	} else {
		(^rawptr)(p)^ = obj
	}
}

// Writes `value` into a ptrcall return slot, which the engine has already constructed; a counted
// value moves in, so the caller gives up its reference. An instance goes in as its object and a
// RefCounted one moves in too: return a kept instance through `share`.
to_slot :: #force_inline proc "contextless" (p: gde.TypePtr, value: $A) {
	when A == bool { (^u8)(p)^ = 1 if value else 0 }
	else when intrinsics.type_is_integer(A) || intrinsics.type_is_enum(A) { (^i64)(p)^ = i64(value) }
	else when intrinsics.type_is_bit_set(A) { (^i64)(p)^ = bits_of(value) }
	else when intrinsics.type_is_float(A) { (^f64)(p)^ = f64(value) }
	else when intrinsics.type_base_type(A) == rawptr { object_to_slot(p, rawptr(value)) }
	else when intrinsics.type_is_pointer(A) { object_to_slot(p, rawptr(object_of(value)) if value != nil else nil) }
	else when A == Variant {
		gde.variant_destroy(auto_cast p)
		(^A)(p)^ = value
	} else when A == string {
		destroy[.STRING](auto_cast p)
		(^String)(p)^ = string_of(value)
	} else {
		if counted(variant_type(A)) { destroy[variant_type(A)](auto_cast p) }
		(^A)(p)^ = value
	}
}

// True when a Variant of type `have` reads as `want` the way the engine's own binds convert:
// int, float and bool into one another, null into an object, anything into a Variant.
converts :: proc "contextless" (have, want: gde.VariantType) -> bool {
	if have == want || want == .NIL { return true }
	#partial switch want {
	case .INT, .FLOAT, .BOOL:
		return have == .INT || have == .FLOAT || have == .BOOL
	case .OBJECT:
		return have == .NIL
	}
	return false
}

// True when a Variant of type `have` becomes `want` only through a new value, as the engine's strict
// conversion allows: an Array to a packed array, or a packed array to an Array. The caller builds it
// with `reshape`.
reshapes :: proc "contextless" (have, want: gde.VariantType) -> bool {
	packed :: proc "contextless" (t: gde.VariantType) -> bool {
		return t >= .PACKED_BYTE_ARRAY && t <= .PACKED_VECTOR4_ARRAY
	}
	return (have == .ARRAY && packed(want)) || (packed(have) && want == .ARRAY)
}

// Constructs into `out` the `want` that `v` converts to, for a `v` that passed `reshapes`; the caller
// destroys `out`. False when the engine refuses, as an Array holding a value the packed type cannot.
reshape :: proc "contextless" (v: gde.ConstVariantPtr, want: gde.VariantType, out: ^Variant) -> bool {
	arg := v
	err: gde.CallError
	gde.variant_construct(want, out, &arg, 1, &err)
	return err.error == .OK
}

// A Variant argument as Odin type `A`, converted as `converts` allows and borrowed for the call
// when it owns a reference, or for an Odin `string` a UTF-8 copy in the temp allocator, valid until
// the engine call returns. `v` must already have passed `converts`.
from_variant :: proc "contextless" ($A: typeid, v: gde.ConstVariantPtr) -> A {
	when A == bool { return variant_bool(v) }
	else when intrinsics.type_is_integer(A) || intrinsics.type_is_enum(A) { return A(variant_int(v)) }
	else when intrinsics.type_is_bit_set(A) { return set_of(A, variant_int(v)) }
	else when intrinsics.type_is_float(A) { return A(variant_float(v)) }
	else when intrinsics.type_base_type(A) == rawptr || intrinsics.type_is_pointer(A) {
		if variant_tag(v) == .NIL { return nil }
		out: rawptr
		to_type[.OBJECT](&out, auto_cast v)
		when intrinsics.type_base_type(A) == rawptr {
			return A(out)
		} else {
			return A(instance_raw(out, class_slot(intrinsics.type_elem_type(A))^))
		}
	} else when A == Variant { return (^Variant)(v)^ }
	else when A == string {
		context = ctx
		return utf8((^String)(internal[.STRING](auto_cast v))^, context.temp_allocator)
	}
	else { return (^A)(internal[variant_type(A)](auto_cast v))^ }
}

// A Variant of type `type` that aliases `value^` with no copy and no new reference, for handing a
// Callable, Signal, Dictionary or Array to an engine call that only reads it, such as `variant_call`. The caller must
// not destroy it or let the engine keep it. Built from the engine's Variant layout: the type tag in
// the first 4 bytes, the value inline at byte 8. `check_borrow_layout` proves that layout at load.
// It saves a copy and two atomic reference counts per call, about 9 ns per Callable.call (bench/).
borrowed :: #force_inline proc "contextless" (type: gde.VariantType, value: ^$A) -> (v: Variant) where size_of(A) <= 16 {
	(^u32)(&v._opaque[0])^ = u32(type)
	(^A)(&v._opaque[8])^ = value^
	return
}

// Writes a scalar Variant of type `type` holding `value` (an int, float or bool) to `out`, in the
// engine's layout: the type tag in the first 4 bytes, the value inline at byte 8, the rest zero.
// `check_borrow_layout` proves that layout at load. It writes whole words in place: copying a
// Variant built as a local splits into byte stores, and the engine's 16-byte load of the result
// then stalls until they land.
@(private)
scalar_into :: #force_inline proc "contextless" (out: ^Variant, type: gde.VariantType, value: $A) where size_of(A) <= 8 {
	w := (^[3]u64)(out)
	w[0] = u64(u32(type))
	w[1] = transmute(u64)value when size_of(A) == 8 else u64(value)
	w[2] = 0
}

// The Variant the engine's Plane and AABB intersection binds return: a Vector3 when `found`, else
// nil. A Vector3 needs no construction, so it is written in place in the layout
// `check_borrow_layout` proves: the type tag in the first 4 bytes, the value at byte 8, the rest
// zero. A zeroed Variant is nil.
@(private) vector3_hit :: #force_inline proc "contextless" (found: bool, v: Vector3) -> (out: Variant) {
	if found {
		(^u32)(&out._opaque[0])^ = u32(gde.VariantType.VECTOR3)
		(^Vector3)(&out._opaque[8])^ = v
	}
	return
}

// The type of the Variant at `v`, read from its tag as `gde.variant_get_type` answers it, with no
// call. `check_borrow_layout` proves the layout at load.
variant_tag :: #force_inline proc "contextless" (v: gde.ConstVariantPtr) -> gde.VariantType {
	return gde.VariantType((^u32)(v)^)
}

// The scalar inside the Variant at `v`, which holds an int (`i64`), a float (`f64`) or a bool (`u8`)
// as `variant_tag` says. Read at byte 8 with no call; `check_borrow_layout` proves it at load.
@(private)
variant_value :: #force_inline proc "contextless" ($A: typeid, v: gde.ConstVariantPtr) -> A {
	return (^A)(uintptr(v) + 8)^
}

// Stops the load when the engine's Variant layout is not the one `borrowed`, `scalar_into`,
// `variant_tag` and `variant_value` read, and plane.odin writes: the type tag first, an int's, a
// float's, a bool's and a Vector3's value at byte 8, and a Callable's, a Signal's, a Dictionary's
// and an Array's value at byte 8.
@(private)
check_borrow_layout :: proc "contextless" () {
	n := i64(0x0123_4567_89ab_cdef)
	v: Variant
	from_type[.INT](&v, &n)
	if variant_tag(&v) != gde.variant_get_type(&v) || variant_tag(&v) != .INT || variant_value(i64, &v) != n {
		fail("odin: unexpected Variant layout", "INT")
	}
	x := f64(-1.0e300)
	from_type[.FLOAT](&v, &x)
	if variant_tag(&v) != .FLOAT || variant_value(f64, &v) != x {
		fail("odin: unexpected Variant layout", "FLOAT")
	}
	for b in ([2]gde.Bool{1, 0}) {
		b := b
		from_type[.BOOL](&v, &b)
		if variant_tag(&v) != .BOOL || variant_value(u8, &v) != u8(b) {
			fail("odin: unexpected Variant layout", "BOOL")
		}
	}
	p := Vector3{1.5, -2.25, 3.125}
	from_type[.VECTOR3](&v, &p)
	if variant_tag(&v) != .VECTOR3 || variant_value(Vector3, &v) != p {
		fail("odin: unexpected Variant layout", "VECTOR3")
	}
	for type in ([4]gde.VariantType{.CALLABLE, .SIGNAL, .DICTIONARY, .ARRAY}) {
		e: Variant
		if rawptr(internal[type](&e)) != rawptr(&e._opaque[8]) {
			fail("odin: unexpected Variant layout", "CALLABLE, SIGNAL, DICTIONARY or ARRAY")
		}
	}
}

// A new Variant holding `value`; a counted value is copied, so the caller keeps its own reference.
// An instance goes in as its object, which the Variant references when it is RefCounted.
variant :: proc "contextless" (value: $A) -> (out: Variant) {
	variant_into(&out, value)
	return
}

// Constructs `out`, which holds nothing that needs destroying, as `variant(value)` would. Writing
// straight into the destination saves a 24-byte copy that would read the engine's narrower stores
// back as one wide load.
variant_into :: proc "contextless" (out: ^Variant, value: $A) {
	// A scalar is written in place, in the layout `check_borrow_layout` proves: it holds nothing to
	// construct.
	when A == bool {
		scalar_into(out, .BOOL, u8(1 if value else 0))
	} else when intrinsics.type_is_integer(A) || intrinsics.type_is_enum(A) {
		scalar_into(out, .INT, i64(value))
	} else when intrinsics.type_is_bit_set(A) {
		scalar_into(out, .INT, bits_of(value))
	} else when intrinsics.type_is_float(A) {
		scalar_into(out, .FLOAT, f64(value))
	} else when intrinsics.type_is_pointer(A) && intrinsics.type_base_type(A) != rawptr {
		if value == nil {
			gde.variant_new_nil(out)
		} else {
			o := rawptr(object_of(value))
			from_type[.OBJECT](out, &o)
		}
	} else when intrinsics.type_base_type(A) == rawptr {
		if value == nil {
			gde.variant_new_nil(out)
		} else {
			o := rawptr(value)
			from_type[.OBJECT](out, &o)
		}
	} else when A == Variant {
		v := value
		gde.variant_new_copy(out, &v)
	} else when A == string {
		s := string_of(value)
		from_type[.STRING](out, &s)
		destroy[.STRING](&s)
	} else {
		v := value
		from_type[variant_type(A)](out, &v)
	}
}

// The Variant `v` read as int64, float64 or bool, converting between the three.
variant_int :: proc "contextless" (v: gde.ConstVariantPtr) -> (out: i64) {
	#partial switch variant_tag(v) {
	case .INT:
		return variant_value(i64, v)
	case .FLOAT:
		return i64(variant_float(v))
	case .BOOL:
		return 1 if variant_bool(v) else 0
	}
	return
}

variant_float :: proc "contextless" (v: gde.ConstVariantPtr) -> (out: f64) {
	#partial switch variant_tag(v) {
	case .FLOAT:
		return variant_value(f64, v)
	case .INT:
		return f64(variant_int(v))
	case .BOOL:
		return 1.0 if variant_bool(v) else 0.0
	}
	return
}

variant_bool :: proc "contextless" (v: gde.ConstVariantPtr) -> bool {
	#partial switch variant_tag(v) {
	case .BOOL:
		return variant_value(u8, v) != 0
	case .INT:
		return variant_int(v) != 0
	case .FLOAT:
		return variant_float(v) != 0.0
	}
	return false
}
