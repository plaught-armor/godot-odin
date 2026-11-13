package godot

import "base:intrinsics"
import gde "../gdextension"

// StringName copies made in place, as the copy constructor makes them in Godot 4.7-stable
// (core/string/string_name.cpp), once `check_name_layout` proved the layout at load. A StringName
// points at its interned StringName::_Data, nil for the empty name; the data starts with its 32-bit
// SafeRefCount, and a copy is one more reference on it.

// True when a StringName's data keeps its reference count at byte 0, and a STRING_NAME Variant
// keeps its StringName at byte 8. `check_name_layout` decides it at load; without it every copy
// calls the engine.
@(private)
name_layout_known: bool

// Where a STRING_NAME Variant keeps its StringName: past the 8 bytes of the type tag and padding.
@(private)
VARIANT_NAME_OFFSET :: 8

// A copy of StringName `n`, which you destroy, made as StringName's copy constructor does: one more
// reference on its interned data. `n` is a live StringName holding its own reference, so the count
// is at least 1 and cannot reach 0 meanwhile, which is why the constructor's conditional increment
// is a plain one here. The engine copies it before `check_name_layout` proved the layout.
name_copy :: #force_inline proc "contextless" (n: ^StringName) -> StringName {
	if !name_layout_known { return string_name_new_from_string_name(n^) }
	return name_ref(n)
}

// `name_copy` without the check that the layout is proven, for `check_name_layout` to prove and for
// callers that checked `name_layout_known` themselves.
@(private)
name_ref :: #force_inline proc "contextless" (n: ^StringName) -> StringName {
	p := (^rawptr)(n)^
	if p != nil { intrinsics.atomic_add_explicit((^u32)(p), 1, .Acq_Rel) }
	return n^
}

// Sets `name_layout_known` from a StringName of known reference count: one engine copy and one
// `name_ref` must each add one reference at byte 0 of its data, and each destroy take one away.
// A STRING_NAME Variant made from it must hold the same data at `VARIANT_NAME_OFFSET`, and the empty
// StringName must have no data.
check_name_layout :: proc "contextless" () {
	name_layout_known = false
	n := name_of("check_name_layout")
	defer destroy[.STRING_NAME](&n)
	data := (^rawptr)(&n)^
	if data == nil { return }
	count := (^u32)(data)
	held := count^
	e := string_name_new_from_string_name(n)
	engine_copy := count^
	destroy[.STRING_NAME](&e)
	engine_gone := count^
	c := name_ref(&n)
	copied := count^
	same := (^rawptr)(&c)^ == data
	destroy[.STRING_NAME](&c)
	v: Variant
	from_type[.STRING_NAME](&v, &n)
	in_variant := internal[.STRING_NAME](&v) == rawptr(&v._opaque[VARIANT_NAME_OFFSET]) &&
		(^rawptr)(&v._opaque[VARIANT_NAME_OFFSET])^ == data && count^ == held + 1
	gde.variant_destroy(&v)
	empty: StringName
	empty_copy := name_ref(&empty)
	name_layout_known = held >= 1 && engine_copy == held + 1 && engine_gone == held && copied == held + 1 &&
		same && count^ == held && in_variant && (^rawptr)(&empty_copy)^ == nil
}
