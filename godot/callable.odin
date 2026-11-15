// Odin procs as engine Callables, for connecting to engine signals. Hand-written.
package godot

import "base:intrinsics"
import gde "../gdextension"

// What one Callable made by `callable` carries: the proc, the instance, the bound values, and the
// count and types of every parameter after the instance.
@(private)
Hook :: struct {
	f:     rawptr,
	self:  rawptr,
	binds: [MAX_ARGS]Variant,
	n:     i32,
	args:  i32,
	types: [MAX_ARGS]gde.VariantType,
}

// A Callable for an Odin proc, for `connect`, tweens and timers. It calls `f` with the caller's
// arguments followed by `binds`, as Callable.bind does; `f` returns nothing. The binds move in.
// Destroy the returned Callable with `destroy[.CALLABLE]` once it is connected.
//
// `callable(self, f, binds..)`: `f`'s first parameter is `^T` and gets `self`. The engine drops
// the connection when `self`'s object is freed.
// `callable(f, binds..)`: a plain proc with no instance, which lives as long as the Callable.
callable :: proc{callable_method, callable_proc}

@(private)
callable_method :: proc(self: ^$T, f: $P, binds: ..Variant) -> Callable where intrinsics.type_is_proc(P) {
	#assert(intrinsics.type_proc_parameter_count(P) >= 1 && intrinsics.type_proc_parameter_type(P, 0) == ^T, "godot_odin: a callable's first parameter is the instance")
	id := u64(gde.object_get_instance_id(gde.ConstObjectPtr(object_of(self))))
	return make_hook(f, true, self, id, binds)
}

@(private)
callable_proc :: proc(f: $P, binds: ..Variant) -> Callable where intrinsics.type_is_proc(P) {
	return make_hook(f, false, nil, 0, binds)
}

// Calls `f` once on the main thread at the end of this frame, as GDScript's `call_deferred` does,
// with `binds` as its arguments, which move in. The forms are `callable`'s: `call_deferred(self,
// f, binds..)` for an instance method, which the engine skips if `self`'s object is freed first,
// and `call_deferred(f, binds..)` for a plain proc.
call_deferred :: proc{call_deferred_method, call_deferred_proc}

@(private)
call_deferred_method :: proc(self: ^$T, f: $P, binds: ..Variant) where intrinsics.type_is_proc(P) {
	assert(len(binds) == intrinsics.type_proc_parameter_count(P) - 1, "godot_odin: call_deferred takes one bind per parameter after self")
	c := callable_method(self, f, ..binds)
	callable_call_deferred(&c)
	destroy[.CALLABLE](&c)
}

@(private)
call_deferred_proc :: proc(f: $P, binds: ..Variant) where intrinsics.type_is_proc(P) {
	assert(len(binds) == intrinsics.type_proc_parameter_count(P), "godot_odin: call_deferred takes one bind per parameter")
	c := callable_proc(f, ..binds)
	callable_call_deferred(&c)
	destroy[.CALLABLE](&c)
}

// The custom Callable both forms of `callable` make. `SELF` says `f`'s first parameter is the
// instance `self`, whose object has instance id `id`; else `self` is nil and `id` 0.
@(private)
make_hook :: proc(f: $P, $SELF: bool, self: rawptr, id: u64, binds: []Variant) -> (out: Callable) {
	FIRST :: 1 when SELF else 0
	N :: intrinsics.type_proc_parameter_count(P) - FIRST
	#assert(intrinsics.type_proc_return_count(P) == 0, "godot_odin: a callable returns nothing")
	#assert(N <= MAX_ARGS, "godot_odin: too many parameters")
	assert(len(binds) <= N, "godot_odin: more binds than parameters")

	call :: proc "c" (userdata: rawptr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {
		context = ctx
		enter()
		h := (^Hook)(userdata)
		want := i32(N) - h.n
		if i32(count) != want {
			err.error = .ERROR_TOO_MANY_ARGUMENTS if i32(count) > want else .ERROR_TOO_FEW_ARGUMENTS
			err.expected = want
			return
		}
		filled: [MAX_ARGS]gde.ConstVariantPtr
		for i in 0 ..< h.args {
			filled[i] = args[i] if i < want else &h.binds[i - want]
			if !converts(variant_tag(filled[i]), h.types[i]) {
				err.error = .ERROR_INVALID_ARGUMENT
				err.argument = i
				err.expected = i32(h.types[i])
				return
			}
		}
		c := Call{self = h.self, variants = &filled[0]}
		invoke_void(P(h.f), SELF, false, &c)
		err.error = .OK
	}

	h := new(Hook)
	h.f = rawptr(f)
	h.self = self
	h.n = i32(len(binds))
	h.args = i32(N)
	for b, i in binds { h.binds[i] = b }
	d: Params
	describe_params(P, FIRST, &d)
	// A proc with no parameters past `self` has nothing to check, and Odin rejects the empty range.
	when N > 0 {
		for i in 0 ..< N { assert(d.types[i] != .VARIANT_MAX, "godot_odin: a callable cannot take []Variant") }
	}
	h.types = d.types
	info := gde.CallableCustomInfo2 {
		callable_userdata       = h,
		token                   = library,
		object_id               = gde.ObjectInstanceID(id),
		call_func               = call,
		free_func               = hook_free,
		hash_func               = hook_hash,
		equal_func              = hook_equal,
		get_argument_count_func = hook_argument_count,
	}
	gde.callable_custom_create2(&out, &info)
	return
}

// Callable and Signal reads answered from the value itself, with no call, once
// `check_callable_layout` proved it at load: the generated Callable `is_null`, `is_custom`,
// `is_standard` and `get_object_id` and Signal `is_null` and `get_object_id` try these first
// (tools/odin_bindgen.py IN_PLACE). Each answers as Godot 4.7-stable does
// (core/variant/callable.h, callable.cpp). A Callable is two words: its method name, nil for none,
// then the instance id of its object or, with no method name, the pointer to its custom callable.
// A Signal is its name, then the instance id of its object.

// True when a Callable and a Signal are the two words the reads below take them for.
// `check_callable_layout` decides it at load; without it every read calls the engine.
@(private)
callable_layout_known: bool

// Whether `c` has neither a method nor an object. Only when `callable_layout_known`.
@(private)
callable_stored_is_null :: #force_inline proc "contextless" (c: ^Callable) -> bool {
	w := (^[2]uintptr)(c)
	return w[0] == 0 && w[1] == 0
}

// Whether `c` is a custom callable: no method name, and a pointer. Only when
// `callable_layout_known`.
@(private)
callable_stored_is_custom :: #force_inline proc "contextless" (c: ^Callable) -> bool {
	w := (^[2]uintptr)(c)
	return w[0] == 0 && w[1] != 0
}

// Whether `c` names a method of an object. Only when `callable_layout_known`.
@(private)
callable_stored_is_standard :: #force_inline proc "contextless" (c: ^Callable) -> bool {
	return (^[2]uintptr)(c)[0] != 0
}

// The instance id of `c`'s object, 0 for a null Callable. False for a custom one, which the engine
// asks for its object. Only when `callable_layout_known`.
@(private)
callable_stored_object_id :: #force_inline proc "contextless" (c: ^Callable) -> (id: i64, ok: bool) {
	w := (^[2]uintptr)(c)
	if w[0] == 0 && w[1] != 0 { return 0, false }
	return i64(w[1]), true
}

// Whether `s` has neither a name nor an object. Only when `callable_layout_known`.
@(private)
signal_stored_is_null :: #force_inline proc "contextless" (s: ^Signal) -> bool {
	w := (^[2]uintptr)(s)
	return w[0] == 0 && w[1] == 0
}

// The instance id of `s`'s object, 0 for none. Only when `callable_layout_known`.
@(private)
signal_stored_object_id :: #force_inline proc "contextless" (s: ^Signal) -> i64 {
	return i64((^[2]uintptr)(s)[1])
}

// Sets `callable_layout_known` from Callables and Signals of known contents: a null one of each,
// one of each naming a member of a new Object, and a custom Callable.
check_callable_layout :: proc "contextless" () {
	callable_layout_known = false
	class := name_of("Object")
	obj := gde.classdb_construct_object3(&class)
	destroy[.STRING_NAME](&class)
	if obj == nil { return }
	defer gde.object_destroy(obj)
	object_notification(Object(obj), 0, false)
	id := uintptr(gde.object_get_instance_id(gde.ConstObjectPtr(obj)))
	name := name_of("check_callable_layout")
	defer destroy[.STRING_NAME](&name)
	text := uintptr((^rawptr)(&name)^)

	none := callable_new()
	defer destroy[.CALLABLE](&none)
	standard := callable_new_from_object_string_name(Object(obj), name)
	defer destroy[.CALLABLE](&standard)
	// A custom callable that is never called and owns nothing.
	never :: proc "c" (userdata: rawptr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {}
	custom: Callable
	info := gde.CallableCustomInfo2{token = library, call_func = never}
	gde.callable_custom_create2(&custom, &info)
	defer destroy[.CALLABLE](&custom)
	no_signal := signal_new()
	defer destroy[.SIGNAL](&no_signal)
	signal := signal_new_from_object_string_name(Object(obj), name)
	defer destroy[.SIGNAL](&signal)

	// The engine's answers, which the generated methods give while the layout is not known.
	callable_layout_known = id != 0 && text != 0 &&
		(^[2]uintptr)(&none)^ == {0, 0} && callable_is_null(&none) &&
		(^[2]uintptr)(&standard)^ == {text, id} && callable_is_standard(&standard) && uintptr(callable_get_object_id(&standard)) == id &&
		callable_stored_is_custom(&custom) && callable_is_custom(&custom) && !callable_is_null(&custom) && !callable_is_standard(&custom) &&
		(^[2]uintptr)(&no_signal)^ == {0, 0} && signal_is_null(&no_signal) &&
		(^[2]uintptr)(&signal)^ == {text, id} && !signal_is_null(&signal) && uintptr(signal_get_object_id(&signal)) == id
}

@(private)
hook_free :: proc "c" (userdata: rawptr) {
	context = ctx
	enter()
	h := (^Hook)(userdata)
	for i in 0 ..< h.n { gde.variant_destroy(&h.binds[i]) }
	free(h)
}

@(private)
hook_hash :: proc "c" (userdata: rawptr) -> u32 {
	h := (^Hook)(userdata)
	x := u64(uintptr(h.f)) * 31 + u64(uintptr(h.self))
	for i in 0 ..< h.n { x = x * 31 + u64(gde.variant_hash(&h.binds[i])) }
	return u32(x ~ (x >> 32))
}

@(private)
hook_equal :: proc "c" (a, b: rawptr) -> gde.Bool {
	ha, hb := (^Hook)(a), (^Hook)(b)
	if ha.f != hb.f || ha.self != hb.self || ha.n != hb.n { return 0 }
	for i in 0 ..< ha.n {
		if gde.variant_hash_compare(&ha.binds[i], &hb.binds[i]) == 0 { return 0 }
	}
	return 1
}

@(private)
hook_argument_count :: proc "c" (userdata: rawptr, valid: ^gde.Bool) -> gde.Int {
	h := (^Hook)(userdata)
	valid^ = 1
	return gde.Int(h.args - h.n)
}
