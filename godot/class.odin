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
	// The engine's type record for this class, read from its first instance; nil until then, or
	// when `gdtype_slot` is 0. With it set, `attach` writes the three words `object_set_instance`
	// would, without its class lookup and lock.
	gdtype:       rawptr,
	name:         StringName,
	title:        string,
	parent:       StringName,
	notification: proc(self: ^T, what: i64),
	options:      Options(T),
	layout:       Layout,
	// Engine virtuals this class overrides, which `override` adds.
	virtuals:     [dynamic]^Virtual,
}

// What a class does beyond its fields and methods, given to `class`. Every hook is optional, and the
// engine calls into Odin only for the ones set.
Options :: struct($T: typeid) {
	// The class runs only in a running game: in the editor its instances are placeholders, and its
	// overrides and `notification` stay off, as for a script without `@tool`.
	runtime:       bool,
	// Reads property `name`, one `property_list` names, as `Object._get` does. False for a name it
	// does not own, and the engine goes on to the class's registered properties.
	get:           proc(self: ^T, name: StringName) -> (Variant, bool),
	// Writes property `name`, as `Object._set` does; `value` is borrowed. False for a name it does
	// not own.
	set:           proc(self: ^T, name: StringName, value: ^Variant) -> bool,
	// Appends the properties `get` and `set` serve, as `Object._get_property_list` does. Asked
	// whenever the inspector or a save walks the object's properties.
	property_list: proc(self: ^T, list: ^[dynamic]Property),
	// Whether property `name` has a value to revert to, and that value, for the inspector's revert
	// arrow, as `Object._property_can_revert` and `_property_get_revert` do.
	can_revert:    proc(self: ^T, name: StringName) -> bool,
	get_revert:    proc(self: ^T, name: StringName) -> (Variant, bool),
	// Edits how any property of the object shows, its registered fields included, as
	// `Object._validate_property` does: change `info.usage` or `info.hint`, or the hint text
	// through `set_hint_string`.
	validate:      proc(self: ^T, info: ^gde.PropertyInfo),
	// The object's text for `print` and `str`, as `Object._to_string` does. Temp memory will do.
	to_string:     proc(self: ^T) -> string,
}

// One property `Options.property_list` reports. Text may be temp memory: the core copies it.
// `usage` 0 stands for PROPERTY_USAGE_DEFAULT, since a property with no usage would not show.
Property :: struct {
	name:        string,
	type:        gde.VariantType,
	hint:        PropertyHint,
	hint_string: string,
	usage:       PropertyUsageFlags,
	// The class an OBJECT property holds, or the "Class.Enum" an enum property names.
	class_name:  string,
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
// How many of `registered` came from `register`; the rest came from `editor`, at the editor level.
@(private)
scene_classes: int
// Classes `editor_plugin` added to the editor, removed at the editor level's deinit.
@(private)
plugins: [dynamic]^StringName
// Names `register_singleton` gave the engine, unregistered at unload before `unload` runs.
@(private)
singletons: [dynamic]^StringName
@(private)
on_editor: proc()
@(private)
registering_editor: bool
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
// Bytes into an engine Object where it keeps its type record, which `object_set_instance` also
// sets; 0 when `find_instance_slot` could not prove it, or in an editor build, whose
// `object_set_instance` also tracks each instance for hot reload, and every instance then takes
// the engine's call.
@(private)
gdtype_slot: uintptr

// The extension's entry point: loads the interface and calls `register` at the scene level, where
// every game class registers. `editor` runs at the editor level, only in the editor, for classes the
// editor alone uses: an EditorPlugin (see `editor_plugin`), an inspector plugin. At unload the editor
// classes unregister first; then `register_singleton`'s names go, `unload` runs, to release what the
// library holds, and the scene classes unregister in reverse. `docs` is class reference XML
// (tools/odin_docgen.py), handed to the editor's help at the editor level; empty loads none.
entry :: proc "contextless" (
	get_proc_address: gde.InterfaceGetProcAddress,
	lib: gde.ClassLibraryPtr,
	init: ^gde.Initialization,
	register: proc(),
	unload: proc() = nil,
	docs: string = "",
	editor: proc() = nil,
) -> gde.Bool {
	context = runtime.default_context()
	ctx = context
	temp_arena = &(^runtime.Default_Temp_Allocator)(ctx.temp_allocator.data).arena
	on_main_thread = true
	gde.load_interface(get_proc_address)
	library = lib
	on_register = register
	on_unload = unload
	on_editor = editor
	class_docs = docs
	init.minimum_initialization_level = .INITIALIZATION_SCENE
	init.initialize = initialize
	init.deinitialize = deinitialize
	return 1
}

@(private)
initialize :: proc "c" (userdata: rawptr, level: gde.InitializationLevel) {
	if level == .INITIALIZATION_EDITOR {
		if class_docs != "" && gde.editor_help_load_xml_from_utf8_chars_and_len != nil {
			gde.editor_help_load_xml_from_utf8_chars_and_len(cstring(raw_data(class_docs)), gde.Int(len(class_docs)))
		}
		if on_editor == nil { return }
		context = ctx
		registering_editor = true
		on_editor()
		registering_editor = false
		return
	}
	if level != .INITIALIZATION_SCENE { return }
	context = ctx
	load_variants()
	empty_name = static_name("")
	gde.string_new_with_latin1_chars(&empty_string, "")
	emit_bind = method_bind("Object", "emit_signal", 4047867050)
	on_register()
	scene_classes = len(registered)
}

@(private)
deinitialize :: proc "c" (userdata: rawptr, level: gde.InitializationLevel) {
	context = ctx
	if level == .INITIALIZATION_EDITOR {
		for i := len(plugins) - 1; i >= 0; i -= 1 { gde.editor_remove_plugin(plugins[i]) }
		clear(&plugins)
		for i := len(registered) - 1; i >= scene_classes; i -= 1 {
			gde.classdb_unregister_extension_class(library, registered[i])
		}
		resize(&registered, scene_classes)
		return
	}
	if level != .INITIALIZATION_SCENE { return }
	engine := engine_singleton()
	for i := len(singletons) - 1; i >= 0; i -= 1 { engine_unregister_singleton(engine, singletons[i]^) }
	if on_unload != nil { on_unload() }
	for i := len(registered) - 1; i >= 0; i -= 1 {
		gde.classdb_unregister_extension_class(library, registered[i])
	}
	for name in owned { destroy[.STRING_NAME](name) }
}

// Registers class `name` extending the engine class `parent`. Each instance carries a `T`, zeroed
// or as `fields` sets it, freed with the object; `notification` receives the object's notifications.
// `options`, when given, sets the class's other hooks (`Options`). `T` = `Static` registers an
// abstract class for static methods only.
class :: proc {
	class_plain,
	class_options,
}

@(private)
class_plain :: proc($T: typeid, name, parent: cstring, notification: proc(self: ^T, what: i64) = nil) -> ^Class(T) {
	return class_options(T, name, parent, notification, Options(T){})
}

@(private)
class_options :: proc($T: typeid, name, parent: cstring, notification: proc(self: ^T, what: i64), options: Options(T)) -> ^Class(T) {
	#assert(align_of(T) <= HEADER)
	c := new(Class(T))
	gde.string_name_new_with_utf8_chars(&c.name, name)
	gde.string_name_new_with_utf8_chars(&c.parent, parent)
	c.title = string(name)
	c.notification = notification
	c.options = options
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
		if c.gdtype != nil {
			put_instance(object, c.extension, h, c.gdtype)
			return h
		}
		before := ([^][SCAN_WORDS]rawptr)(object)[0]
		gde.object_set_instance(object, &c.name, h)
		if !slot_checked { find_instance_slot(object, h, &before) }
		if instance_slot == 0 {
			gde.object_set_instance_binding(object, library, h, &no_binding)
			return h
		}
		c.extension = (^rawptr)(uintptr(object) + instance_slot - size_of(rawptr))^
		if gdtype_slot != 0 { c.gdtype = (^rawptr)(uintptr(object) + gdtype_slot)^ }
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
		is_runtime     = gde.Bool(options.runtime),
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
		hook_properties(&info, options)
		hook_inspector(&info, options)
	}
	gde.classdb_register_extension_class6(library, &c.name, &c.parent, &info)
	append(&registered, &c.name)
	append(&owned, &c.name, &c.parent)
	return c
}

// The `Options` of the class `instance` belongs to.
@(private)
options_of :: #force_inline proc "contextless" ($T: typeid, instance: gde.ClassInstancePtr) -> ^Options(T) {
	return &(^Class(T))((^Header)(instance).class).options
}

// Points `info` at the trampolines of the property hooks `options` sets (`get`, `set`,
// `property_list`); the engine skips the ones left nil.
@(private)
hook_properties :: proc(info: ^gde.ClassCreationInfo6, options: Options($T)) {
	// A field answers here, before the engine's own lookup: the class table search and the method
	// wrapper behind a property's getter and setter cost more than the field read itself.
	get :: proc "c" (instance: gde.ClassInstancePtr, name: gde.ConstStringNamePtr, ret: gde.VariantPtr) -> gde.Bool {
		want := (^StringName)(name)^
		for f in (^Class(T))((^Header)(instance).class).layout.fields {
			if !same_name(f.name^, want) { continue }
			err: gde.CallError
			field_get_call(f, instance, nil, 0, ret, &err)
			return 1
		}
		o := options_of(T, instance)
		if o.get == nil { return 0 }
		context = ctx
		enter()
		v, ok := o.get(self_of(T, instance), want)
		if !ok { return 0 }
		// The engine's `ret` holds null, which needs no destroy.
		(^Variant)(ret)^ = v
		return 1
	}
	set :: proc "c" (instance: gde.ClassInstancePtr, name: gde.ConstStringNamePtr, value: gde.ConstVariantPtr) -> gde.Bool {
		want := (^StringName)(name)^
		for f in (^Class(T))((^Header)(instance).class).layout.fields {
			if !same_name(f.name^, want) { continue }
			// A value the field cannot take falls through to the engine's setter, which fails the
			// same way and reports it.
			args := [1]gde.ConstVariantPtr{value}
			err: gde.CallError
			field_set_call(f, instance, &args[0], 1, nil, &err)
			return gde.Bool(err.error == .OK)
		}
		o := options_of(T, instance)
		if o.set == nil { return 0 }
		context = ctx
		enter()
		return gde.Bool(o.set(self_of(T, instance), want, (^Variant)(value)))
	}
	list :: proc "c" (instance: gde.ClassInstancePtr, count: [^]u32) -> ^gde.PropertyInfo {
		context = ctx
		enter()
		props := make([dynamic]Property, context.temp_allocator)
		options_of(T, instance).property_list(self_of(T, instance), &props)
		count[0] = u32(len(props))
		return property_infos(props[:])
	}
	free_list :: proc "c" (instance: gde.ClassInstancePtr, list: ^gde.PropertyInfo, count: u32) {
		context = ctx
		free_property_infos(list, int(count))
	}
	// The fields are not known yet (`fields` comes after `class`), so every class takes the hooks;
	// one with no fields pays a pointer compare loop of length zero on each engine property.
	info.get_func = get
	info.set_func = set
	if options.property_list != nil {
		info.get_property_list_func = list
		info.free_property_list_func = free_list
	}
}

// Points `info` at the trampolines of the inspector and text hooks `options` sets (`can_revert`,
// `get_revert`, `validate`, `to_string`); the engine skips the ones left nil.
@(private)
hook_inspector :: proc(info: ^gde.ClassCreationInfo6, options: Options($T)) {
	can_revert :: proc "c" (instance: gde.ClassInstancePtr, name: gde.ConstStringNamePtr) -> gde.Bool {
		context = ctx
		enter()
		return gde.Bool(options_of(T, instance).can_revert(self_of(T, instance), (^StringName)(name)^))
	}
	get_revert :: proc "c" (instance: gde.ClassInstancePtr, name: gde.ConstStringNamePtr, ret: gde.VariantPtr) -> gde.Bool {
		context = ctx
		enter()
		v, ok := options_of(T, instance).get_revert(self_of(T, instance), (^StringName)(name)^)
		if !ok { return 0 }
		(^Variant)(ret)^ = v
		return 1
	}
	validate :: proc "c" (instance: gde.ClassInstancePtr, info: ^gde.PropertyInfo) -> gde.Bool {
		context = ctx
		enter()
		options_of(T, instance).validate(self_of(T, instance), info)
		return 1
	}
	to_string :: proc "c" (instance: gde.ClassInstancePtr, valid: ^gde.Bool, out: gde.StringPtr) {
		context = ctx
		enter()
		text := options_of(T, instance).to_string(self_of(T, instance))
		// The engine's `out` is an empty String, which needs no destroy.
		gde.string_new_with_utf8_chars_and_len(out, cstring(raw_data(text)), gde.Int(len(text)))
		valid^ = 1
	}
	if options.can_revert != nil { info.property_can_revert_func = can_revert }
	if options.get_revert != nil { info.property_get_revert_func = get_revert }
	if options.validate != nil { info.validate_property_func = validate }
	if options.to_string != nil { info.to_string_func = to_string }
}

// The engine's copy of `props`: one allocation holding the PropertyInfos and, after them, the names
// and hint texts they point to, which `free_property_infos` destroys. Nil for none.
@(private)
property_infos :: proc(props: []Property) -> ^gde.PropertyInfo {
	n := len(props)
	if n == 0 { return nil }
	Text :: struct {
		name, class: StringName,
		hint:        String,
	}
	block := ([^]u8)(gde.mem_alloc2(uint(n * (size_of(gde.PropertyInfo) + size_of(Text))), 0))
	infos := ([^]gde.PropertyInfo)(block)
	texts := ([^]Text)(&block[n * size_of(gde.PropertyInfo)])
	for p, i in props {
		texts[i] = {name = name_of(p.name), class = name_of(p.class_name), hint = string_of(p.hint_string)}
		usage := p.usage if p.usage != {} else PropertyUsageFlags_PROPERTY_USAGE_DEFAULT
		infos[i] = {
			type_       = p.type,
			name        = &texts[i].name,
			class_name  = &texts[i].class,
			hint        = u32(p.hint),
			hint_string = &texts[i].hint,
			usage       = u32(usage),
		}
	}
	return &infos[0]
}

@(private)
free_property_infos :: proc "contextless" (list: ^gde.PropertyInfo, count: int) {
	if list == nil { return }
	infos := ([^]gde.PropertyInfo)(list)
	for i in 0 ..< count {
		destroy[.STRING_NAME](infos[i].name)
		destroy[.STRING_NAME](infos[i].class_name)
		destroy[.STRING](infos[i].hint_string)
	}
	gde.mem_free2(list, 0)
}

// Replaces the hint text of `info`, a property `Options.validate` is editing, with `text`.
set_hint_string :: proc "contextless" (info: ^gde.PropertyInfo, text: string) {
	destroy[.STRING](info.hint_string)
	(^String)(info.hint_string)^ = string_of(text)
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

// Registers `name` as a virtual a script extending class `c` can override, as `GDVIRTUAL` does in
// godot-cpp. `P` is the virtual's shape, a proc type whose first parameter is `^T`; `args` names
// the rest. The editor lists it among the overridable methods, and `required` makes the engine warn
// about a script that leaves it out. Odin calls it with `call_script` and the name returned.
script_virtual :: proc(c: ^Class($T), name: cstring, $P: typeid, args: []cstring = nil, required := false) -> ^StringName
	where intrinsics.type_is_proc(P) {
	#assert(intrinsics.type_proc_parameter_count(P) >= 1 && intrinsics.type_proc_parameter_type(P, 0) == ^T)
	ARGS :: intrinsics.type_proc_parameter_count(P) - 1
	RET :: intrinsics.type_proc_return_count(P)
	#assert(ARGS <= MAX_ARGS && RET <= 1)
	assert(args == nil || len(args) == ARGS, "godot_odin: one name per parameter")
	d: Params
	for i in 0 ..< ARGS {
		arg_name := args[i] if args != nil else fmt.ctprintf("arg%d", i)
		gde.string_name_new_with_utf8_chars(&d.names[i], arg_name)
	}
	describe_params(P, 1, &d)
	virtual_name := new(StringName)
	gde.string_name_new_with_utf8_chars(virtual_name, name)
	flags := gde.FLAG_NORMAL | gde.FLAG_VIRTUAL
	if required { flags |= gde.FLAG_VIRTUAL_REQUIRED }
	info := gde.ClassVirtualMethodInfo {
		name               = virtual_name,
		method_flags       = u32(flags),
		return_value       = {name = &empty_name, class_name = &empty_name, hint_string = &empty_string},
		argument_count     = u32(ARGS),
		arguments          = &d.infos[0],
		arguments_metadata = &d.metas[0],
	}
	when RET == 1 {
		R :: intrinsics.type_proc_return_type(P, 0)
		info.return_value = info_of(R, &empty_name)
		info.return_value_metadata = variant_meta(R)
	}
	gde.classdb_register_extension_class_virtual_method(library, &c.name, &info)
	for i in 0 ..< ARGS { destroy[.STRING_NAME](&d.names[i]) }
	append(&owned, virtual_name)
	return virtual_name
}

// Calls `self`'s script's override of the virtual `name` (from `script_virtual`) with `args`, which
// it destroys. `found` is false, and `ret` null, when the object's script does not define it. The
// caller owns `ret`. A Variant call, as GDScript's own calls to a script method are.
call_script :: proc "contextless" (self: ^$T, name: ^StringName, args: ..Variant, loc := #caller_location) -> (ret: Variant, found: bool) {
	MOST :: 31
	if len(args) > MOST { fail("odin: too many arguments", "call_script") }
	defer for i in 0 ..< len(args) { gde.variant_destroy(&args[i]) }
	object := rawptr(object_of(self))
	if gde.object_has_script_method(object, name) == 0 { return }
	at: [MOST]gde.ConstVariantPtr = ---
	for i in 0 ..< len(args) { at[i] = &args[i] }
	err: gde.CallError
	gde.object_call_script_method(object, name, &at[0], gde.Int(len(args)), &ret, &err)
	if err.error != .OK {
		context = ctx
		error("call_script: the script's override failed (call error %v)", err.error, loc = loc)
	}
	return ret, true
}

// Gives class `c` to the editor as a plugin; `c` must extend EditorPlugin. Call it from `entry`'s
// `editor` proc, after `class`. It leaves the editor before the class unregisters.
editor_plugin :: proc(c: ^Class($T)) {
	assert(registering_editor, "godot_odin: editor_plugin runs in entry's editor proc")
	gde.editor_add_plugin(&c.name)
	append(&plugins, &c.name)
}

// Makes `object` the engine singleton `name`, which GDScript reaches as a global and Odin through
// `singleton`. Call it from `register`. The name is taken back at unload, before `unload` runs;
// the object stays the caller's to free, in `unload` or after.
register_singleton :: proc(name: cstring, object: Object) {
	assert(object != nil, "godot_odin: a singleton needs an object")
	singleton_name := new(StringName)
	gde.string_name_new_with_utf8_chars(singleton_name, name)
	engine_register_singleton(engine_singleton(), singleton_name^, object)
	append(&owned, singleton_name)
	append(&singletons, singleton_name)
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
	} else when intrinsics.type_is_bit_set(A) {
		if qualified, ok := flag_names[intrinsics.type_bit_set_elem_type(A)]; ok {
			info.class_name = qualified
			info.usage |= u32(PropertyUsageFlags_PROPERTY_USAGE_CLASS_IS_BITFIELD)
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

// Words of an Object that `find_instance_slot` compares before and after `object_set_instance`:
// 256 bytes, the size of a 4.7 release Object (an editor build's is larger), so the scan never
// reads past it. The type record sits at byte 184.
@(private)
SCAN_WORDS :: 32

// Finds `instance_slot` from the first instance made: `instance` must sit in exactly one of the
// object's first words, after a set class record. The engine keeps the pair at the head of Object.
// Then `gdtype_slot`: `object_set_instance` must have changed exactly one word of `before` (the
// object's words before the call) besides that pair, the type record, or `gdtype_slot` stays 0.
@(private)
find_instance_slot :: proc(object: gde.ObjectPtr, instance: rawptr, before: ^[SCAN_WORDS]rawptr) {
	slot_checked = true
	words := ([^]rawptr)(object)
	found := 0
	for i in 1 ..< 16 {
		if words[i] != instance { continue }
		if found != 0 || words[i - 1] == nil { return }
		found = i
	}
	instance_slot = uintptr(found * size_of(rawptr))
	if found == 0 { return }
	other := 0
	for i in 0 ..< SCAN_WORDS {
		if i == found || i == found - 1 || words[i] == before[i] { continue }
		if other != 0 { return }
		other = i
	}
	if other == 0 || words[other] == nil { return }
	editor := string_of("editor")
	defer destroy[.STRING](&editor)
	if os_has_feature(os_singleton(), editor) { return }
	gdtype_slot = uintptr(other * size_of(rawptr))
}

// Does what `object_set_instance` does to `object` once its class is known: points it at the class
// record `extension`, the instance and the type record `gdtype`.
@(private)
put_instance :: #force_inline proc "contextless" (object: gde.ObjectPtr, extension, instance, gdtype: rawptr) {
	(^rawptr)(uintptr(object) + instance_slot - size_of(rawptr))^ = extension
	(^rawptr)(uintptr(object) + instance_slot)^ = instance
	(^rawptr)(uintptr(object) + gdtype_slot)^ = gdtype
}
