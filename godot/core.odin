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
	if gde.variant_get_type(&v) != .STRING_NAME { return }
	to_type[.STRING_NAME](&out, &v)
	return
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
	named := type_info_of(T).variant.(runtime.Type_Info_Named)
	sn: StringName
	gde.string_name_new_with_utf8_chars_and_len(&sn, cstring(raw_data(named.name)), gde.Int(len(named.name)))
	obj := gde.classdb_construct_object2(&sn)
	destroy[.STRING_NAME](&sn)
	if rc := cast_to(obj, RefCounted); rc != nil { ref_counted_init_ref(rc) }
	return T(obj)
}
