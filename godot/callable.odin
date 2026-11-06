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

// A Callable that calls `f(self, ...)` with the caller's arguments followed by `binds`, as
// Callable.bind does. `f`'s first parameter is `^T`; it returns nothing. The binds move in. The
// engine drops the connection when `self`'s object is freed. Destroy the returned Callable with
// `destroy[.CALLABLE]` once it is connected.
callable :: proc(self: ^$T, f: $P, binds: ..Variant) -> (out: Callable) where intrinsics.type_is_proc(P) {
	N :: intrinsics.type_proc_parameter_count(P)
	#assert(N >= 1 && intrinsics.type_proc_parameter_type(P, 0) == ^T, "godot_odin: a callable's first parameter is the instance")
	#assert(intrinsics.type_proc_return_count(P) == 0, "godot_odin: a callable returns nothing")
	#assert(N - 1 <= MAX_ARGS, "godot_odin: too many parameters")
	assert(len(binds) <= N - 1, "godot_odin: more binds than parameters")

	call :: proc "c" (userdata: rawptr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {
		context = ctx
		enter()
		h := (^Hook)(userdata)
		want := i32(N - 1) - h.n
		if i32(count) != want {
			err.error = .ERROR_TOO_MANY_ARGUMENTS if i32(count) > want else .ERROR_TOO_FEW_ARGUMENTS
			err.expected = want
			return
		}
		filled: [MAX_ARGS]gde.ConstVariantPtr
		for i in 0 ..< h.args {
			filled[i] = args[i] if i < want else &h.binds[i - want]
			if !converts(gde.variant_get_type(filled[i]), h.types[i]) {
				err.error = .ERROR_INVALID_ARGUMENT
				err.argument = i
				err.expected = i32(h.types[i])
				return
			}
		}
		c := Call{self = h.self, variants = &filled[0]}
		invoke_void(P(h.f), true, false, &c)
		err.error = .OK
	}

	h := new(Hook)
	h.f = rawptr(f)
	h.self = self
	h.n = i32(len(binds))
	h.args = i32(N - 1)
	for b, i in binds { h.binds[i] = b }
	d: Params
	describe_params(P, 1, &d)
	h.types = d.types
	info := gde.CallableCustomInfo2 {
		callable_userdata       = h,
		token                   = library,
		object_id               = gde.ObjectInstanceID(gde.object_get_instance_id(gde.ConstObjectPtr(object_of(self)))),
		call_func               = call,
		free_func               = hook_free,
		hash_func               = hook_hash,
		equal_func              = hook_equal,
		get_argument_count_func = hook_argument_count,
	}
	gde.callable_custom_create2(&out, &info)
	return
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
