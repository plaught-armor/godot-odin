// Extension classes from plain Odin: an entry point, classes with an instance struct, methods taken
// from typed procs, properties, signals. Hand-written; the per-arity call dispatch is generated into
// gen_calls.odin.
//
//	@(export, link_name = "my_init")
//	my_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
//		return godot.entry(gpa, lib, init, register)
//	}
//	Walker :: struct { speed: f64 }
//	register :: proc() {
//		c := godot.class(Walker, "Walker", "Node3D")
//		godot.method(c, "walk", walk, {"time"}, {1.0})        // walk :: proc(self: ^Walker, time: f64) -> bool
//		godot.property(c, "speed", get_speed, set_speed)        // registers get_speed and set_speed
//	}
package godot

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:reflect"
import gde "../gdextension"

// The library handle the engine gave `entry`.
library: gde.ClassLibraryPtr

// The context every call from the engine runs in: methods, notifications and callables may allocate.
ctx: runtime.Context

// Calls that entered a registered method through the Variant path since load. A typed GDScript call
// site arrives by ptrcall and leaves it unchanged, so a rise shows an untyped call.
variant_calls: i64

// Most parameters a registered method takes, not counting `self`.
MAX_ARGS :: 13

// Marks a class with no instances: its methods are all static, and the engine cannot create one.
Static :: struct {}

// A registered class whose instances carry a `T`. Lives for the process.
Class :: struct($T: typeid) {
	// The engine's record of this class, which every instance's Object points to beside the
	// instance (`instance_slot`). Set by each instance made; first, so `instance_raw` reads it
	// without knowing `T`.
	extension:    rawptr,
	name:         StringName,
	title:        string,
	parent:       StringName,
	notification: proc(self: ^T, what: i64),
	layout:       Layout,
	// Engine virtuals this class overrides, which `override` adds.
	virtuals:     [dynamic]^Virtual,
}

// One override of an engine virtual: the name and API hash the engine asks for it by, and the
// trampoline that calls the Odin proc from ptrcall slots. Lives for the process.
@(private)
Virtual :: struct {
	name: StringName,
	hash: u32,
	call: gde.ClassCallVirtual,
}

// One registered method: the Odin proc and what the Variant path needs to check and fill its
// arguments. Lives for the process.
@(private)
Method :: struct {
	f:        rawptr,
	types:    [MAX_ARGS]gde.VariantType,
	count:    i32,
	required: i32,
	defaults: [MAX_ARGS]Variant,
}

// The allocation behind every instance: this header, then the `T` at HEADER bytes.
@(private)
Header :: struct {
	object: Object,
	class:  rawptr,
}
@(private)
HEADER :: 16

@(private)
registered: [dynamic]^StringName
// Names that live until unload: class, parent, signal and argument class names.
@(private)
owned: [dynamic]^StringName
@(private)
on_register: proc()
@(private)
on_unload: proc()
@(private)
class_docs: string
@(private)
empty_name: StringName
@(private)
empty_string: String
@(private)
emit_bind: gde.MethodBindPtr
// Binding callbacks for an instance: the header is freed with the instance, not the binding.
@(private)
no_binding: gde.InstanceBindingCallbacks
// Bytes into an engine Object where it keeps the instance `object_set_instance` gave it, with its
// class record in the word before; 0 when `find_instance_slot` could not prove that layout, and
// every instance then carries an instance binding instead. An instance binding costs the engine an
// allocation per object and a mutex on every reference change, so the slot is read when it can be.
@(private)
instance_slot: uintptr
@(private)
slot_checked: bool

// The extension's entry point: loads the interface and calls `register` at the scene level, where
// every class registers. At unload `unload` runs first, to release what the library holds, then
// classes unregister in reverse. `docs` is class reference XML (tools/odin_docgen.py), handed to the
// editor's help at the editor level; empty loads none, and a build with no editor never reaches it.
entry :: proc "contextless" (
	get_proc_address: gde.InterfaceGetProcAddress,
	lib: gde.ClassLibraryPtr,
	init: ^gde.Initialization,
	register: proc(),
	unload: proc() = nil,
	docs: string = "",
) -> gde.Bool {
	context = runtime.default_context()
	ctx = context
	temp_arena = &(^runtime.Default_Temp_Allocator)(ctx.temp_allocator.data).arena
	on_main_thread = true
	gde.load_interface(get_proc_address)
	library = lib
	on_register = register
	on_unload = unload
	class_docs = docs
	init.minimum_initialization_level = .INITIALIZATION_SCENE
	init.initialize = initialize
	init.deinitialize = deinitialize
	return 1
}

@(private)
initialize :: proc "c" (userdata: rawptr, level: gde.InitializationLevel) {
	if level == .INITIALIZATION_EDITOR && class_docs != "" && gde.editor_help_load_xml_from_utf8_chars_and_len != nil {
		gde.editor_help_load_xml_from_utf8_chars_and_len(cstring(raw_data(class_docs)), gde.Int(len(class_docs)))
	}
	if level != .INITIALIZATION_SCENE { return }
	context = ctx
	load_variants()
	empty_name = static_name("")
	gde.string_new_with_latin1_chars(&empty_string, "")
	emit_bind = method_bind("Object", "emit_signal", 4047867050)
	on_register()
}

@(private)
deinitialize :: proc "c" (userdata: rawptr, level: gde.InitializationLevel) {
	if level != .INITIALIZATION_SCENE { return }
	context = ctx
	if on_unload != nil { on_unload() }
	for i := len(registered) - 1; i >= 0; i -= 1 {
		gde.classdb_unregister_extension_class(library, registered[i])
	}
	for name in owned { destroy[.STRING_NAME](name) }
}

// Registers class `name` extending the engine class `parent`. Each instance carries a `T`, zeroed
// or as `fields` sets it, freed with the object; `notification` receives the object's notifications. `T` = `Static`
// registers an abstract class for static methods only.
class :: proc($T: typeid, name, parent: cstring, notification: proc(self: ^T, what: i64) = nil) -> ^Class(T) {
	#assert(align_of(T) <= HEADER)
	c := new(Class(T))
	gde.string_name_new_with_utf8_chars(&c.name, name)
	gde.string_name_new_with_utf8_chars(&c.parent, parent)
	c.title = string(name)
	c.notification = notification
	class_slot(T)^ = c

	create :: proc "c" (userdata: rawptr, notify_postinitialize: gde.Bool) -> gde.ObjectPtr {
		c := (^Class(T))(userdata)
		// A RefCounted object returns holding the one reference its caller takes over.
		object := gde.classdb_construct_object3(&c.parent)
		attach(c, object)
		if notify_postinitialize != 0 { object_notification(Object(object), 0, false) }
		return object
	}
	// A hot reload freed the instance of `object` and re-registered the class: give the live object
	// a fresh `T`. The engine sets the saved properties back afterwards.
	recreate :: proc "c" (userdata: rawptr, object: gde.ObjectPtr) -> gde.ClassInstancePtr {
		return attach((^Class(T))(userdata), object)
	}
	// Makes the instance behind `object`: the header and a `T` as `fields` sets it.
	attach :: proc "contextless" (c: ^Class(T), object: gde.ObjectPtr) -> gde.ClassInstancePtr {
		h := (^Header)(gde.mem_alloc2(uint(HEADER + size_of(T)), 0))
		intrinsics.mem_zero(h, HEADER + size_of(T))
		context = ctx
		enter()
		fields_init(&c.layout, rawptr(uintptr(h) + HEADER), size_of(T))
		h.object = Object(object)
		h.class = c
		gde.object_set_instance(object, &c.name, h)
		if !slot_checked { find_instance_slot(object, h) }
		if instance_slot == 0 {
			gde.object_set_instance_binding(object, library, h, &no_binding)
		} else {
			c.extension = (^rawptr)(uintptr(object) + instance_slot - size_of(rawptr))^
		}
		return h
	}
	free :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr) {
		context = ctx
		enter()
		fields_release(&(^Class(T))(userdata).layout, rawptr(uintptr(instance) + HEADER))
		gde.mem_free2(instance, 0)
	}
	notify :: proc "c" (instance: gde.ClassInstancePtr, what: i32, reversed: gde.Bool) {
		context = ctx
		enter()
		h := (^Header)(instance)
		c := (^Class(T))(h.class)
		if c.notification != nil { c.notification(self_of(T, instance), i64(what)) }
	}

	// The engine asks once per object and virtual, then calls the trampoline it got directly: the
	// search is off the per-call path.
	virtual_func :: proc "c" (userdata: rawptr, name: gde.ConstStringNamePtr, hash: u32) -> gde.ClassCallVirtual {
		want := (^StringName)(name)^
		for v in (^Class(T))(userdata).virtuals {
			if same_name(v.name, want) && v.hash == hash { return v.call }
		}
		return nil
	}

	info := gde.ClassCreationInfo6 {
		is_exposed     = 1,
		class_userdata = c,
	}
	when T == Static {
		info.is_abstract = 1
	} else {
		info.create_instance_func = create
		info.free_instance_func = free
		info.recreate_instance_func = recreate
		info.get_virtual_func = virtual_func
		// Every notification the object gets would cross into `notify`: only a class with a handler pays.
		if notification != nil { info.notification_func = notify }
	}
	gde.classdb_register_extension_class6(library, &c.name, &c.parent, &info)
	append(&registered, &c.name)
	append(&owned, &c.name, &c.parent)
	return c
}

// Makes `f` class `c`'s override of the engine virtual `name` with API hash `hash`. The generated
// `override_<class><virtual>` procs call this with the hash and a signature checked against the
// virtual's; arguments and the return cross as they do for a method's ptrcall. `f` is a constant, so
// each override gets its own trampoline that calls `f` directly, and the engine calls that.
override :: proc(c: ^Class($T), name: cstring, hash: u32, $f: $P) where intrinsics.type_is_proc(P) {
	#assert(intrinsics.type_proc_parameter_count(P) >= 1 && intrinsics.type_proc_parameter_type(P, 0) == ^T)
	RET :: intrinsics.type_proc_return_count(P)
	call :: proc "c" (instance: gde.ClassInstancePtr, args: [^]gde.ConstTypePtr, ret: gde.TypePtr) {
		context = ctx
		enter()
		c := Call{self = self_of(T, instance), slots = args}
		when RET == 1 {
			R :: intrinsics.type_proc_return_type(P, 0)
			to_slot(ret, invoke_ret(f, R, true, true, &c))
		} else {
			invoke_void(f, true, true, &c)
		}
	}
	v := new(Virtual)
	gde.string_name_new_with_utf8_chars(&v.name, name)
	v.hash = hash
	v.call = call
	append(&c.virtuals, v)
	append(&owned, &v.name)
}

// The engine object behind an instance's `self`.
object_of :: #force_inline proc "contextless" (self: ^$T) -> Object {
	return (^Header)(uintptr(self) - HEADER).object
}

// A new instance of the registered class `T`. A RefCounted one starts with one reference, which
// the caller owns: returning it from a method hands it over, else drop it with `release`.
make_instance :: proc "contextless" ($T: typeid) -> ^T {
	c := (^Class(T))(class_slot(T)^)
	if c == nil { return nil }
	return (^T)(instance_raw(rawptr(gde.classdb_construct_object3(&c.name)), c))
}

// `self` with one more reference when it is RefCounted, for returning an instance that is kept.
share :: proc "contextless" (self: ^$T) -> ^T {
	if self == nil { return nil }
	context = ctx
	if rc := counted_object(rawptr(object_of(self))); rc != nil { ref_counted_reference(rc) }
	return self
}

// The `T` behind `obj` when it is an instance of class `c`, else nil.
instance_of :: proc "contextless" (obj: $O, c: ^Class($T)) -> ^T where intrinsics.type_base_type(O) == rawptr {
	return (^T)(instance_raw(rawptr(obj), c))
}

@(private)
self_of :: #force_inline proc "contextless" ($T: typeid, instance: gde.ClassInstancePtr) -> ^T {
	return (^T)(uintptr(instance) + HEADER)
}

// Registers `f` as method `name`. A proc whose first parameter is `^T` is an instance method and
// gets the instance's `self`; any other proc is static. Parameters and the return cross as
// `variant_type` maps them; counted ones (strings, arrays) are borrowed for the call. `args` names
// the parameters after `self`; `defaults` fills the last ones (bool, integer, float, string or a
// Variant) when a Variant call leaves them out.
method :: proc(c: ^Class($T), name: cstring, f: $P, args: []cstring = nil, defaults: []any = nil) where intrinsics.type_is_proc(P) {
	N :: intrinsics.type_proc_parameter_count(P)
	PT :: ^T
	when N > 0 { SELF :: intrinsics.type_proc_parameter_type(P, 0) == PT } else { SELF :: false }
	when SELF { FIRST :: 1 } else { FIRST :: 0 }
	ARGS :: N - FIRST
	RET :: intrinsics.type_proc_return_count(P)
	#assert(ARGS <= MAX_ARGS, "godot_odin: too many parameters")
	#assert(RET <= 1, "godot_odin: a method returns one value at most")
	assert(args == nil || len(args) == ARGS, "godot_odin: one name per parameter")
	assert(len(defaults) <= ARGS, "godot_odin: more defaults than parameters")

	ptrcall :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstTypePtr, ret: gde.TypePtr) {
		context = ctx
		enter()
		m := (^Method)(userdata)
		c := Call{self = self_of(T, instance) if SELF else nil, slots = args}
		when RET == 1 {
			R :: intrinsics.type_proc_return_type(P, 0)
			to_slot(ret, invoke_ret(P(m.f), R, SELF, true, &c))
		} else {
			invoke_void(P(m.f), SELF, true, &c)
		}
	}
	call :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {
		context = ctx
		enter()
		variant_calls += 1
		m := (^Method)(userdata)
		// fill_args writes `filled` for every parameter and `made[i]` only where it sets `built[i]`,
		// so only `built` needs zeroing.
		filled: [MAX_ARGS + 1]gde.ConstVariantPtr = ---
		made: [MAX_ARGS + 1]Variant = ---
		built: [MAX_ARGS + 1]bool
		defer for i in 0 ..< m.count {
			if built[i] { gde.variant_destroy(&made[i]) }
		}
		if !fill_args(m, args, count, &filled[0], &made[0], &built[0], err) { return }
		c := Call{self = self_of(T, instance) if SELF else nil, variants = &filled[0]}
		when RET == 1 {
			R :: intrinsics.type_proc_return_type(P, 0)
			put_return(ret, invoke_ret(P(m.f), R, SELF, false, &c))
		} else {
			invoke_void(P(m.f), SELF, false, &c)
		}
		err.error = .OK
	}

	m := new(Method)
	m.f = rawptr(f)
	m.count = ARGS
	m.required = i32(ARGS - len(defaults))
	d: Params
	defaults_at: [MAX_ARGS]gde.VariantPtr
	for i in 0 ..< int(m.count) {
		arg_name := args[i] if args != nil else fmt.ctprintf("arg%d", i)
		gde.string_name_new_with_utf8_chars(&d.names[i], arg_name)
	}
	describe_params(P, FIRST, &d)
	m.types = d.types
	for d, k in defaults {
		at := int(m.required) + k
		m.defaults[at] = default_variant(d, m.types[at])
		defaults_at[k] = &m.defaults[at]
	}
	ret_info: gde.PropertyInfo
	ret_meta: gde.ClassMethodArgumentMetadata
	when RET == 1 {
		R :: intrinsics.type_proc_return_type(P, 0)
		ret_info = info_of(R, &empty_name)
		ret_meta = variant_meta(R)
	}
	method_name: StringName
	gde.string_name_new_with_utf8_chars(&method_name, name)
	flags := gde.FLAG_NORMAL if SELF else gde.FLAG_NORMAL | gde.FLAG_STATIC
	info := gde.ClassMethodInfo {
		name                   = &method_name,
		method_userdata        = m,
		call_func              = call,
		ptrcall_func           = ptrcall,
		method_flags           = u32(flags),
		has_return_value       = gde.Bool(RET),
		return_value_info      = &ret_info,
		return_value_metadata  = ret_meta,
		argument_count         = u32(ARGS),
		arguments_info         = &d.infos[0],
		arguments_metadata     = &d.metas[0],
		default_argument_count = u32(len(defaults)),
		default_arguments      = &defaults_at[0],
	}
	gde.classdb_register_extension_class_method(library, &c.name, &info)
	destroy[.STRING_NAME](&method_name)
	for i in 0 ..< int(m.count) { destroy[.STRING_NAME](&d.names[i]) }
}

// What registering a method tells the engine about its parameters, filled by `describe_params`.
@(private)
Params :: struct {
	types: [MAX_ARGS]gde.VariantType,
	metas: [MAX_ARGS]gde.ClassMethodArgumentMetadata,
	infos: [MAX_ARGS]gde.PropertyInfo,
	names: [MAX_ARGS]StringName,
}

@(private)
describe_param :: proc($A: typeid, k: int, d: ^Params) {
	d.types[k] = variant_type(A)
	d.metas[k] = variant_meta(A)
	d.infos[k] = info_of(A, &d.names[k])
}

// Registers property `name` read by `get` and written by `set`, both registered as the methods
// `get_<name>` and `set_<name>`. Its type is `get`'s return type.
property :: proc(
	c: ^Class($T),
	name: cstring,
	get: $G,
	set: $S,
	hint := PropertyHint.PROPERTY_HINT_NONE,
	hint_string: cstring = "",
	usage := PropertyUsageFlags_PROPERTY_USAGE_DEFAULT,
) {
	getter := fmt.ctprintf("get_%s", name)
	setter := fmt.ctprintf("set_%s", name)
	method(c, getter, get)
	method(c, setter, set, {"value"})
	prop_name, get_name, set_name: StringName
	hint_text: String
	gde.string_name_new_with_utf8_chars(&prop_name, name)
	gde.string_name_new_with_utf8_chars(&get_name, getter)
	gde.string_name_new_with_utf8_chars(&set_name, setter)
	gde.string_new_with_utf8_chars(&hint_text, hint_string)
	info := info_of(intrinsics.type_proc_return_type(G, 0), &prop_name)
	info.hint = u32(hint)
	info.hint_string = &hint_text
	info.usage = u32(usage)
	gde.classdb_register_extension_class_property(library, &c.name, &info, &set_name, &get_name)
	destroy[.STRING_NAME](&prop_name)
	destroy[.STRING_NAME](&get_name)
	destroy[.STRING_NAME](&set_name)
	destroy[.STRING](&hint_text)
}

// One signal argument: its name and Variant type.
Arg :: struct {
	name: cstring,
	type: gde.VariantType,
}

// Registers signal `name` with `args`; the name it returns is what `emit` takes.
signal :: proc(c: ^Class($T), name: cstring, args: ..Arg) -> ^StringName {
	signal_name := new(StringName)
	gde.string_name_new_with_utf8_chars(signal_name, name)
	infos: [MAX_ARGS]gde.PropertyInfo
	names: [MAX_ARGS]StringName
	assert(len(args) <= MAX_ARGS, "godot_odin: too many signal arguments")
	for a, i in args {
		gde.string_name_new_with_utf8_chars(&names[i], a.name)
		infos[i] = {type_ = a.type, name = &names[i], class_name = &empty_name, hint_string = &empty_string, usage = u32(PropertyUsageFlags_PROPERTY_USAGE_DEFAULT)}
	}
	gde.classdb_register_extension_class_signal(library, &c.name, signal_name, &infos[0], gde.Int(len(args)))
	for i in 0 ..< len(args) { destroy[.STRING_NAME](&names[i]) }
	append(&owned, signal_name)
	return signal_name
}

// Emits `signal` from `self`'s object with `args`, which it destroys. A Variant call: per emission,
// not per tick.
emit :: proc "contextless" (self: ^$T, signal: ^StringName, args: ..Variant) {
	MOST :: 31
	if len(args) > MOST { fail("odin: too many arguments", "emit") }
	n := len(args)
	at: [MOST + 1]gde.ConstVariantPtr = ---
	name := variant(signal^)
	at[0] = &name
	for i in 0 ..< n { at[i + 1] = &args[i] }
	ret: Variant
	err: gde.CallError
	gde.object_method_bind_call(emit_bind, rawptr(object_of(self)), &at[0], gde.Int(n + 1), &ret, &err)
	gde.variant_destroy(&ret)
	gde.variant_destroy(&name)
	for i in 0 ..< len(args) { gde.variant_destroy(&args[i]) }
}

// A PropertyInfo for Odin type `A` named `name`; an engine class argument names its class.
@(private)
info_of :: proc($A: typeid, name: ^StringName) -> gde.PropertyInfo {
	info := gde.PropertyInfo {
		type_       = variant_type(A),
		name        = name,
		class_name  = &empty_name,
		hint_string = &empty_string,
		usage       = u32(PropertyUsageFlags_PROPERTY_USAGE_DEFAULT),
	}
	when A == Variant {
		info.usage |= u32(PropertyUsageFlags_PROPERTY_USAGE_NIL_IS_VARIANT)
	} else when intrinsics.type_is_enum(A) {
		if qualified, ok := enum_names[A]; ok {
			info.class_name = qualified
			info.usage |= u32(PropertyUsageFlags_PROPERTY_USAGE_CLASS_IS_ENUM)
		}
	} else when intrinsics.type_is_pointer(A) && intrinsics.type_base_type(A) != rawptr {
		c := (^Class(intrinsics.type_elem_type(A)))(class_slot(intrinsics.type_elem_type(A))^)
		assert(c != nil, "godot_odin: a parameter's class must register before the method")
		info.class_name = &c.name
	} else when intrinsics.type_base_type(A) == rawptr && A != Object && A != rawptr {
		// The engine keeps class names it is given; one per class, made once.
		@(static) class_sn: StringName
		@(static) made: bool
		if !made {
			named := type_info_of(A).variant.(runtime.Type_Info_Named)
			gde.string_name_new_with_utf8_chars(&class_sn, fmt.ctprintf("%s", named.name))
			append(&owned, &class_sn)
			made = true
		}
		info.class_name = &class_sn
	}
	return info
}

// The Variant for a default value `d` given to `method`, converted to the parameter's type `type`.
@(private)
default_variant :: proc(d: any, type: gde.VariantType) -> Variant {
	switch v in d {
	case Variant:
		return variant(v)
	case bool:
		return variant(v)
	case string:
		s: String
		gde.string_new_with_utf8_chars_and_len(&s, cstring(raw_data(v)), gde.Int(len(v)))
		out := variant(s)
		destroy[.STRING](&s)
		return out
	}
	x: f64
	ti := runtime.type_info_base(type_info_of(d.id))
	#partial switch info in ti.variant {
	case runtime.Type_Info_Integer:
		x = f64(reflect.as_i64(d) or_else 0)
	case runtime.Type_Info_Enum:
		x = f64(reflect.as_i64(any{d.data, info.base.id}) or_else 0)
	case runtime.Type_Info_Float:
		x = reflect.as_f64(d) or_else 0
	case:
		panic("godot_odin: a default must be bool, integer, enum, float, string or Variant")
	}
	if type == .INT { return variant(i64(x)) }
	if type == .BOOL { return variant(x != 0) }
	return variant(x)
}

// The arguments of one call: the instance and either the ptrcall slots or the Variants.
@(private)
Call :: struct {
	self:     rawptr,
	slots:    [^]gde.ConstTypePtr,
	variants: [^]gde.ConstVariantPtr,
}

// Checks a Variant call's `args` against `m` and fills `filled` with them and the defaults past
// `count`. An argument that `reshapes` to its parameter is built into `made`, its `built` flag set;
// the caller destroys those after the call, on either result. False, with `err` naming the first
// misfit, when they do not fit.
@(private)
fill_args :: proc "contextless" (m: ^Method, args: [^]gde.ConstVariantPtr, count: gde.Int, filled: [^]gde.ConstVariantPtr, made: [^]Variant, built: [^]bool, err: ^gde.CallError) -> bool {
	n := i32(count)
	if n > m.count || n < m.required {
		err.error = .ERROR_TOO_MANY_ARGUMENTS if n > m.count else .ERROR_TOO_FEW_ARGUMENTS
		err.expected = m.count if n > m.count else m.required
		return false
	}
	for i in 0 ..< m.count {
		if i >= n {
			filled[i] = &m.defaults[i]
			continue
		}
		have := variant_tag(args[i])
		if converts(have, m.types[i]) {
			filled[i] = args[i]
			continue
		}
		if reshapes(have, m.types[i]) {
			built[i] = reshape(args[i], m.types[i], &made[i])
			filled[i] = &made[i]
			if built[i] { continue }
		}
		err.error = .ERROR_INVALID_ARGUMENT
		err.argument = i
		err.expected = i32(m.types[i])
		return false
	}
	return true
}

// Moves a returned value into a Variant call's return, which the engine constructed as null.
@(private)
put_return :: #force_inline proc "contextless" (ret: gde.VariantPtr, value: $A) {
	when A == Variant {
		(^Variant)(ret)^ = value
	} else {
		variant_into((^Variant)(ret), value)
		when intrinsics.type_is_pointer(A) && intrinsics.type_base_type(A) != rawptr {
			if value != nil {
				context = ctx
				release(counted_object(rawptr(object_of(value))))
			}
		} else when intrinsics.type_base_type(A) == rawptr {
			if rc := counted_engine_object(rawptr(value)); rc != nil { release(rc) }
		} else {
			if counted(variant_type(A)) {
				v := value
				destroy[variant_type(A)](&v)
			}
		}
	}
}

@(private)
counted_engine_object :: proc "contextless" (obj: rawptr) -> RefCounted {
	context = ctx
	return counted_object(obj)
}

// Parameter `I`, of type `A`, for one call: `self`, a ptrcall slot or a Variant.
@(private)
arg :: #force_inline proc($A: typeid, $I: int, $SELF, $PTR: bool, c: ^Call) -> A {
	when SELF && I == 0 {
		return A(c.self)
	} else {
		when SELF { K :: I - 1 } else { K :: I }
		when PTR {
			return from_slot(A, c.slots[K])
		} else {
			return from_variant(A, c.variants[K])
		}
	}
}

// Finds `instance_slot` from the first instance made: `instance` must sit in exactly one of the
// object's first words, after a set class record. The engine keeps the pair at the head of Object.
@(private)
find_instance_slot :: proc "contextless" (object: gde.ObjectPtr, instance: rawptr) {
	SCAN :: 16
	slot_checked = true
	words := ([^]rawptr)(object)
	found := 0
	for i in 1 ..< SCAN {
		if words[i] != instance { continue }
		if found != 0 || words[i - 1] == nil { return }
		found = i
	}
	instance_slot = uintptr(found * size_of(rawptr))
}
