// Struct fields as engine properties, Odin enums as engine enums, and the per-type class lookup that
// lets a method take an instance of a registered class. Hand-written.
//
//	Def :: struct {
//		speed: f64 `range:"0,10,0.1" group:"Walk"`,
//		kind:  Kind,
//		steps: Array `array:"AudioStream"`,
//		cache: map[int]int `godot:"-"`,
//	}
//	c := godot.class(Def, "Def", "Resource")
//	godot.enumerate(c, "Kind", Kind)    // before any field or parameter of type Kind
//	godot.fields(c, &Def{speed = 2})     // `speed` and `kind` and `steps` as properties
package godot

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:reflect"
import "core:strings"
import gde "../gdextension"

// How one registered field crosses: where it sits in the instance and as which Variant type. An
// INT or FLOAT field reads and writes its own width. Lives for the process.
@(private)
Field :: struct {
	// The property name, which the class's get and set hooks match by pointer.
	name:     ^StringName,
	offset:   uintptr,
	size:     int,
	type:     gde.VariantType,
	// INT: the Odin integer is unsigned (a bit_set is), so it widens with zeros.
	unsigned: bool,
	// OBJECT: the class tag a Variant write must match. ARRAY: the element class of a typed array.
	tag:      rawptr,
	array_of: ^StringName,
	// ARRAY with `array_of`: the element type, OBJECT for a class or the builtin `array_of` names.
	// DICTIONARY with `array_of`: the value type, the same way; NIL for Variant.
	element:  gde.VariantType,
	// DICTIONARY with `array_of`: the key class (empty for a builtin key) and the key type.
	key_of:   ^StringName,
	key:      gde.VariantType,
	// OBJECT: the field's class is RefCounted or Object, so what it holds may be counted. A field of
	// any other class is held raw and never touched at store, create or free.
	counted:  bool,
	// OBJECT, tagged `godot:"new"`: the class each new instance constructs its own object of.
	fresh:    ^StringName,
	// OBJECT, tagged `class:"Name"`: the extension class a Variant write must be, which its class
	// tag cannot tell: an extension class's tag is its engine parent's.
	exact:    ^StringName,
}

// What create and free do to an instance beyond zeroing it: copy the defaults in, make every
// counted field a valid value of its own; at free, destroy them and release held objects.
@(private)
Layout :: struct {
	fields:   [dynamic]^Field,
	template: rawptr,
	// Some field needs work at create or free: an Array, Dictionary, counted builtin or counted
	// object. Without one, create only copies the template in and free does nothing.
	counted:  bool,
}

// The "Class.Enum" name each enumerated Odin enum crosses as, set by `enumerate`.
@(private)
enum_names: map[typeid]^StringName

// The bitfield name ("Class.Flags") `enumerate_flags` gave each enum, for `bit_set`s of it.
@(private)
flag_names: map[typeid]^StringName
@(private)
nil_variant: Variant

// The class registered for instance struct `T`, nil until `class` registers it.
@(private)
class_slot :: proc "contextless" ($T: typeid) -> ^rawptr {
	@(static) c: rawptr
	return &c
}

// The instance struct behind `obj` when it belongs to the registered class `c`, else nil.
@(private)
instance_raw :: proc "contextless" (obj: rawptr, c: rawptr) -> rawptr {
	if obj == nil || c == nil { return nil }
	h: ^Header
	if instance_slot != 0 {
		// The class record beside the instance is this class's only when the object is one.
		ext := (^rawptr)(c)^
		if ext == nil || (^rawptr)(uintptr(obj) + instance_slot - size_of(rawptr))^ != ext { return nil }
		h = (^^Header)(uintptr(obj) + instance_slot)^
	} else {
		h = (^Header)(gde.object_get_instance_binding(gde.ObjectPtr(obj), library, nil))
	}
	if h == nil || h.class != c { return nil }
	return rawptr(uintptr(h) + HEADER)
}

// Registers each value of enum `E` as an integer constant of `c` in enum `name`, read from
// GDScript as `Class.name.VALUE`. Fields and parameters of type `E` then cross as that enum, so
// `enumerate` runs before `fields` or `method` meets `E`.
enumerate :: proc(c: ^Class($T), name: cstring, $E: typeid) where intrinsics.type_is_enum(E) {
	enum_sn: StringName
	gde.string_name_new_with_utf8_chars(&enum_sn, name)
	for f in reflect.enum_fields_zipped(E) {
		value_sn := name_of(f.name)
		gde.classdb_register_extension_class_integer_constant(library, &c.name, &enum_sn, &value_sn, gde.Int(f.value), 0)
		destroy[.STRING_NAME](&value_sn)
	}
	destroy[.STRING_NAME](&enum_sn)
	qualified := new(StringName)
	qualified^ = name_of(fmt.tprintf("%s.%s", c.title, name))
	append(&owned, qualified)
	enum_names[E] = qualified
}

// Registers each value `v` of enum `E` as the bitfield constant `1 << v` of `c` in `name`, read from
// GDScript as `Class.name.VALUE`, and makes a `bit_set[E]` field or parameter cross as that
// bitfield: an integer of those bits, a flags checklist in the inspector. `E`'s values run from 0,
// below 64. Runs before `fields` or `method` meets `bit_set[E]`.
enumerate_flags :: proc(c: ^Class($T), name: cstring, $E: typeid) where intrinsics.type_is_enum(E) {
	enum_sn: StringName
	gde.string_name_new_with_utf8_chars(&enum_sn, name)
	lowest := max(i64)
	for f in reflect.enum_fields_zipped(E) {
		v := i64(f.value)
		assert(v >= 0 && v < 64, "godot_odin: a flag's value is its bit, from 0 to 63")
		lowest = min(lowest, v)
		value_sn := name_of(f.name)
		gde.classdb_register_extension_class_integer_constant(library, &c.name, &enum_sn, &value_sn, gde.Int(1) << uint(v), 1)
		destroy[.STRING_NAME](&value_sn)
	}
	assert(lowest == 0, "godot_odin: a flags enum starts at 0, so bit_set bit k is value k")
	destroy[.STRING_NAME](&enum_sn)
	qualified := new(StringName)
	qualified^ = name_of(fmt.tprintf("%s.%s", c.title, name))
	append(&owned, qualified)
	flag_names[E] = qualified
}

// Makes fields and parameters of enum `E` cross as `qualified` ("Class.Enum"), an enum a script
// class declares, registering no constant: `E` must hold the script enum's values, in its order.
mirror :: proc($E: typeid, qualified: string) where intrinsics.type_is_enum(E) {
	name := new(StringName)
	name^ = name_of(qualified)
	append(&owned, name)
	enum_names[E] = name
}

// Registers `value` as an integer constant of `c` outside any enum, read from GDScript as
// `Class.name`. The engine has no float constants for an extension class.
constant :: proc(c: ^Class($T), name: string, value: i64) {
	value_sn := name_of(name)
	gde.classdb_register_extension_class_integer_constant(library, &c.name, &empty_name, &value_sn, gde.Int(value), 0)
	destroy[.STRING_NAME](&value_sn)
}

// Registers every field of `T` as a property with a `get_<field>` and `set_<field>` method (see
// `accessor_names`), in field order, and makes `template` (copied) the value each new instance starts as. Tags on a
// field: `godot:"-"` leaves it to Odin (not a property, never initialised or destroyed);
// `range:"min,max,step"` and `hint:"color_no_alpha"` set its inspector hint; `group:"Name"` and
// `subgroup:"Name"` open a group before it; `array:"Class"` types an Array field's elements to that
// class, or to the builtin it names (`array:"PackedInt32Array"`);
// `dict:"Key,Value"` types a Dictionary field's keys and values, each a builtin, a class or `Variant`;
// `class:"Name"` types an Object field to an extension class, read back through `instance_of`;
// `godot:"new"` gives each instance a new object of a RefCounted field's class, released at free.
// Array and Dictionary fields always start empty: the template's must be zero, as must a new one's.
// A `bit_set` of an enum crosses as an integer of its bits, a flags checklist in the inspector.
fields :: proc(c: ^Class($T), template: ^T = nil) {
	if template != nil {
		t := new(T)
		t^ = template^
		c.layout.template = t
	}
	for sf in reflect.struct_fields_zipped(T) {
		if reflect.struct_tag_get(sf.tag, "godot") == "-" { continue }
		f := new(Field)
		f^ = field_of(sf)
		if reflect.struct_tag_get(sf.tag, "godot") == "new" {
			assert(f.type == .OBJECT && f.counted, "godot_odin: a new tag on a field that is not a RefCounted object")
			assert(template == nil || is_zero(rawptr(uintptr(template) + sf.offset), f.size), "godot_odin: a new field's default must be zero")
			f.fresh = new(StringName)
			f.fresh^ = name_of(sf.type.variant.(runtime.Type_Info_Named).name)
			append(&owned, f.fresh)
		}
		if f.type == .ARRAY || f.type == .DICTIONARY {
			assert(template == nil || is_zero(rawptr(uintptr(template) + sf.offset), f.size), "godot_odin: an Array or Dictionary default must be zero")
		}
		if template != nil {
			// The layout keeps its own copy of each counted default; the caller destroys theirs.
			at := rawptr(uintptr(c.layout.template) + sf.offset)
			if counted(f.type) && f.type != .ARRAY && f.type != .DICTIONARY {
				src := [1]gde.ConstTypePtr{rawptr(uintptr(template) + sf.offset)}
				copy_from[f.type](at, &src[0])
			} else if f.type == .OBJECT && f.counted {
				if rc := counted_object((^rawptr)(at)^); rc != nil { ref_counted_reference(rc) }
			}
		}
		if counted(f.type) || (f.type == .OBJECT && f.counted) { c.layout.counted = true }
		append(&c.layout.fields, f)
		if g, ok := reflect.struct_tag_lookup(sf.tag, "group"); ok { open_group(&c.name, g, false) }
		if g, ok := reflect.struct_tag_lookup(sf.tag, "subgroup"); ok { open_group(&c.name, g, true) }
		register_field(&c.name, sf, f)
	}
}

@(private)
is_zero :: proc "contextless" (p: rawptr, size: int) -> bool {
	for b in ([^]u8)(p)[:size] { if b != 0 { return false } }
	return true
}


@(private)
open_group :: proc(class: ^StringName, name: string, sub: bool) {
	group := string_of(name)
	if sub {
		gde.classdb_register_extension_class_property_subgroup(library, class, &group, &empty_string)
	} else {
		gde.classdb_register_extension_class_property_group(library, class, &group, &empty_string)
	}
	destroy[.STRING](&group)
}

// The Variant type a field crosses as, from its Odin type.
@(private)
field_of :: proc(sf: reflect.Struct_Field) -> (f: Field) {
	f.offset = sf.offset
	f.size = sf.type.size
	f.type = builtin_type(sf.type.id)
	if f.type != .VARIANT_MAX { return }
	#partial switch info in runtime.type_info_base(sf.type).variant {
	case runtime.Type_Info_Boolean:
		f.type = .BOOL
	case runtime.Type_Info_Integer:
		f.type = .INT
		f.unsigned = !info.signed
	case runtime.Type_Info_Enum:
		f.type = .INT
	case runtime.Type_Info_Bit_Set:
		assert(info.lower == 0, "godot_odin: a bit_set field's enum starts at 0")
		f.type = .INT
		f.unsigned = true
	case runtime.Type_Info_Float:
		f.type = .FLOAT
	case runtime.Type_Info_Pointer:
		_, ok := sf.type.variant.(runtime.Type_Info_Named)
		assert(ok && info.elem == nil, "godot_odin: a pointer field must be an engine class")
		f.type = .OBJECT
		class_text := object_class(sf)
		class_sn := name_of(class_text)
		f.tag = gde.classdb_get_class_tag(&class_sn)
		counted_sn := name_of("RefCounted")
		f.counted = class_text == "Object" || class_db_is_parent_class(class_db_singleton(), class_sn, counted_sn)
		if c, tagged := reflect.struct_tag_lookup(sf.tag, "class"); tagged {
			f.exact = new(StringName)
			f.exact^ = name_of(c)
			append(&owned, f.exact)
		}
		destroy[.STRING_NAME](&counted_sn)
		destroy[.STRING_NAME](&class_sn)
	case:
		fmt.panicf("godot_odin: field %s has no Variant type; tag it godot:\"-\"", sf.name)
	}
	assert(f.type != .INT || f.size == 1 || f.size == 2 || f.size == 4 || f.size == 8)
	assert(f.type != .FLOAT || f.size == 4 || f.size == 8)
	return
}

// The class an object field holds: its `class:"Name"` tag, else the engine class it is typed as.
@(private)
object_class :: proc(sf: reflect.Struct_Field) -> string {
	if c, ok := reflect.struct_tag_lookup(sf.tag, "class"); ok {
		assert(sf.type.id == typeid_of(Object), "godot_odin: a class tag on a field that is not an Object")
		return c
	}
	return sf.type.variant.(runtime.Type_Info_Named).name
}

// The Variant type of a builtin struct type `id`, VARIANT_MAX for any other type. The runtime twin
// of `variant_type` for the builtins.
@(private)
builtin_type :: proc "contextless" (id: typeid) -> gde.VariantType {
	switch id {
	case String: return .STRING
	case Vector2: return .VECTOR2
	case Vector2i: return .VECTOR2I
	case Rect2: return .RECT2
	case Rect2i: return .RECT2I
	case Vector3: return .VECTOR3
	case Vector3i: return .VECTOR3I
	case Transform2D: return .TRANSFORM2D
	case Vector4: return .VECTOR4
	case Vector4i: return .VECTOR4I
	case Plane: return .PLANE
	case Quaternion: return .QUATERNION
	case AABB: return .AABB
	case Basis: return .BASIS
	case Transform3D: return .TRANSFORM3D
	case Projection: return .PROJECTION
	case Color: return .COLOR
	case StringName: return .STRING_NAME
	case NodePath: return .NODE_PATH
	case RID: return .RID
	case Callable: return .CALLABLE
	case Signal: return .SIGNAL
	case Dictionary: return .DICTIONARY
	case Array: return .ARRAY
	case PackedByteArray: return .PACKED_BYTE_ARRAY
	case PackedInt32Array: return .PACKED_INT32_ARRAY
	case PackedInt64Array: return .PACKED_INT64_ARRAY
	case PackedFloat32Array: return .PACKED_FLOAT32_ARRAY
	case PackedFloat64Array: return .PACKED_FLOAT64_ARRAY
	case PackedStringArray: return .PACKED_STRING_ARRAY
	case PackedVector2Array: return .PACKED_VECTOR2_ARRAY
	case PackedVector3Array: return .PACKED_VECTOR3_ARRAY
	case PackedColorArray: return .PACKED_COLOR_ARRAY
	case PackedVector4Array: return .PACKED_VECTOR4_ARRAY
	}
	return .VARIANT_MAX
}

// The getter and setter names of field `field` on `class`: `get_<field>` and `set_<field>`, or
// `_get_<field>` and `_set_<field>` when an inherited method already takes either name (a
// Resource's `name` field meets `Resource.get_name`). The caller destroys both.
@(private)
accessor_names :: proc(class: StringName, field: string) -> (get_sn, set_sn: StringName) {
	db := class_db_singleton()
	get_sn = name_of(fmt.tprintf("get_%s", field))
	set_sn = name_of(fmt.tprintf("set_%s", field))
	if !class_db_class_has_method(db, class, get_sn, false) && !class_db_class_has_method(db, class, set_sn, false) { return }
	destroy[.STRING_NAME](&get_sn)
	destroy[.STRING_NAME](&set_sn)
	get_sn = name_of(fmt.tprintf("_get_%s", field))
	set_sn = name_of(fmt.tprintf("_set_%s", field))
	taken := class_db_class_has_method(db, class, get_sn, false) || class_db_class_has_method(db, class, set_sn, false)
	assert(!taken, "godot_odin: a field's accessor names are both taken by inherited methods")
	return
}

// Registers field `sf`, crossing as `f`, as a property of `class` with its getter and setter.
@(private)
register_field :: proc(class: ^StringName, sf: reflect.Struct_Field, f: ^Field) {
	prop_sn := new(StringName)
	prop_sn^ = name_of(sf.name)
	append(&owned, prop_sn)
	f.name = prop_sn
	info := gde.PropertyInfo {
		type_       = f.type,
		name        = prop_sn,
		class_name  = &empty_name,
		hint_string = &empty_string,
		usage       = u32(PropertyUsageFlags_PROPERTY_USAGE_DEFAULT),
	}
	hint_text := ""
	if r, has_range := reflect.struct_tag_lookup(sf.tag, "range"); has_range {
		info.hint = u32(PropertyHint.PROPERTY_HINT_RANGE)
		hint_text = r
	} else if h, has_hint := reflect.struct_tag_lookup(sf.tag, "hint"); has_hint {
		assert(h == "color_no_alpha", "godot_odin: the only hint tag is color_no_alpha")
		info.hint = u32(PropertyHint.PROPERTY_HINT_COLOR_NO_ALPHA)
	} else if a, has_array := reflect.struct_tag_lookup(sf.tag, "array"); has_array {
		assert(f.type == .ARRAY, "godot_odin: an array tag on a field that is not an Array")
		f.array_of = new(StringName)
		f.array_of^ = name_of(a)
		append(&owned, f.array_of)
		f.element = builtin_named(a)
		if f.element == .NIL {
			f.element = .OBJECT
			info.hint, hint_text = array_hint(f.array_of^, a)
		} else {
			info.hint, hint_text = u32(PropertyHint.PROPERTY_HINT_ARRAY_TYPE), a
		}
	} else if element := packed_element(f.type); element != .NIL {
		// The element type, as GDScript states it for an exported packed array.
		info.hint = u32(PropertyHint.PROPERTY_HINT_TYPE_STRING)
		hint_text = fmt.tprintf("%d:", int(element))
	} else if f.type == .OBJECT {
		class_text := object_class(sf)
		class_sn := new(StringName)
		class_sn^ = name_of(class_text)
		// A Resource class shows as a resource picker, a Node class as a node picker, as the
		// engine's own properties do; any other object has no hint.
		resource_sn := name_of("Resource")
		node_sn := name_of("Node")
		db := class_db_singleton()
		if class_db_is_parent_class(db, class_sn^, resource_sn) {
			info.hint = u32(PropertyHint.PROPERTY_HINT_RESOURCE_TYPE)
			hint_text = class_text
		} else if class_db_is_parent_class(db, class_sn^, node_sn) {
			info.hint = u32(PropertyHint.PROPERTY_HINT_NODE_TYPE)
			hint_text = class_text
		}
		destroy[.STRING_NAME](&resource_sn)
		destroy[.STRING_NAME](&node_sn)
		append(&owned, class_sn)
		info.class_name = class_sn
	} else if d, has_dict := reflect.struct_tag_lookup(sf.tag, "dict"); has_dict {
		assert(f.type == .DICTIONARY, "godot_odin: a dict tag on a field that is not a Dictionary")
		info.hint, hint_text = dict_types(f, d)
	} else if set, is_set := runtime.type_info_base(sf.type).variant.(runtime.Type_Info_Bit_Set); is_set {
		info.hint = u32(PropertyHint.PROPERTY_HINT_FLAGS)
		hint_text = enum_hint(set.elem.id, flags = true)
		if qualified, named := flag_names[set.elem.id]; named {
			info.class_name = qualified
			info.usage |= u32(PropertyUsageFlags_PROPERTY_USAGE_CLASS_IS_BITFIELD)
		}
	} else if _, is_enum := runtime.type_info_base(sf.type).variant.(runtime.Type_Info_Enum); is_enum {
		info.hint = u32(PropertyHint.PROPERTY_HINT_ENUM)
		hint_text = enum_hint(sf.type.id)
		if qualified, has_qualified := enum_names[sf.type.id]; has_qualified {
			info.class_name = qualified
			info.usage |= u32(PropertyUsageFlags_PROPERTY_USAGE_CLASS_IS_ENUM)
		}
	}
	hint_string := new(String)
	hint_string^ = string_of(hint_text)
	info.hint_string = hint_string

	get_sn, set_sn := accessor_names(class^, sf.name)
	meta := field_meta(f)
	ret_info := info
	ret_info.name = &empty_name
	arg_name := name_of("value")
	arg_info := info
	arg_info.name = &arg_name
	getter := gde.ClassMethodInfo {
		name                  = &get_sn,
		method_userdata       = f,
		call_func             = field_get_call,
		ptrcall_func          = field_get_ptr,
		method_flags          = u32(gde.FLAG_NORMAL | gde.FLAG_CONST),
		has_return_value      = 1,
		return_value_info     = &ret_info,
		return_value_metadata = meta,
	}
	setter := gde.ClassMethodInfo {
		name               = &set_sn,
		method_userdata    = f,
		call_func          = field_set_call,
		ptrcall_func       = field_set_ptr,
		method_flags       = u32(gde.FLAG_NORMAL),
		argument_count     = 1,
		arguments_info     = &arg_info,
		arguments_metadata = &meta,
	}
	gde.classdb_register_extension_class_method(library, class, &getter)
	gde.classdb_register_extension_class_method(library, class, &setter)
	gde.classdb_register_extension_class_property(library, class, &info, &set_sn, &get_sn)
	destroy[.STRING_NAME](&get_sn)
	destroy[.STRING_NAME](&set_sn)
	destroy[.STRING_NAME](&arg_name)
	destroy[.STRING](hint_string)
	free(hint_string)
}

// The hint for an Array of `class` elements, as GDScript states it for an exported typed array: a
// The builtin Variant type the engine names `name` ("PackedInt32Array"), or NIL for a class name.
@(private)
builtin_named :: proc(name: string) -> gde.VariantType {
	for t in gde.VariantType.BOOL ..< gde.VariantType.VARIANT_MAX {
		if t == .OBJECT { continue }
		s: String
		gde.variant_get_type_name(t, &s)
		text := utf8(s, context.temp_allocator)
		destroy[.STRING](&s)
		if text == name { return t }
	}
	return .NIL
}

// TYPE_STRING of a resource or node picker per element, or ARRAY_TYPE for any other class.
@(private)
array_hint :: proc(class: StringName, name: string) -> (u32, string) {
	resource_sn := name_of("Resource")
	defer destroy[.STRING_NAME](&resource_sn)
	node_sn := name_of("Node")
	defer destroy[.STRING_NAME](&node_sn)
	db := class_db_singleton()
	picker := PropertyHint.PROPERTY_HINT_NONE
	if class_db_is_parent_class(db, class, resource_sn) {
		picker = .PROPERTY_HINT_RESOURCE_TYPE
	} else if class_db_is_parent_class(db, class, node_sn) {
		picker = .PROPERTY_HINT_NODE_TYPE
	}
	if picker == .PROPERTY_HINT_NONE { return u32(PropertyHint.PROPERTY_HINT_ARRAY_TYPE), name }
	element := fmt.tprintf("%d/%d:%s", int(gde.VariantType.OBJECT), int(picker), name)
	return u32(PropertyHint.PROPERTY_HINT_TYPE_STRING), element
}

// Types a Dictionary field by its `dict:"Key,Value"` tag, each a builtin type name, a class, or
// `Variant`, and returns its DICTIONARY_TYPE hint.
@(private)
dict_types :: proc(f: ^Field, tag: string) -> (u32, string) {
	comma := strings.index_byte(tag, ',')
	assert(comma > 0, "godot_odin: a dict tag is \"Key,Value\"")
	key_text := strings.trim_space(tag[:comma])
	value_text := strings.trim_space(tag[comma + 1:])
	f.key, f.key_of = dict_side(key_text)
	f.element, f.array_of = dict_side(value_text)
	return u32(PropertyHint.PROPERTY_HINT_DICTIONARY_TYPE), fmt.tprintf("%s;%s", key_text, value_text)
}

// One side of a typed dictionary: its Variant type, and its class name, empty for a builtin.
@(private)
dict_side :: proc(text: string) -> (gde.VariantType, ^StringName) {
	if text == "Variant" { return .NIL, &empty_name }
	t := builtin_named(text)
	if t != .NIL { return t, &empty_name }
	class_sn := new(StringName)
	class_sn^ = name_of(text)
	append(&owned, class_sn)
	return .OBJECT, class_sn
}

// The ENUM hint text for enum type `id`: "Name:value" for each value, comma-separated, each
// UPPER_SNAKE name capitalized as the engine's String.capitalize does ("HOLE_UP" reads "Hole Up").
// `flags` gives the FLAGS hint text instead, each value as its bit, `1 << value`.
@(private)
enum_hint :: proc(id: typeid, flags := false) -> string {
	b := strings.builder_make(context.temp_allocator)
	for f, i in reflect.enum_fields_zipped(id) {
		if i > 0 { strings.write_byte(&b, ',') }
		word_start := true
		for c in transmute([]u8)f.name {
			assert((c >= 'A' && c <= 'Z') || c == '_', "godot_odin: enum names are UPPER_SNAKE")
			if c == '_' {
				strings.write_byte(&b, ' ')
				word_start = true
				continue
			}
			strings.write_byte(&b, c if word_start else c + ('a' - 'A'))
			word_start = false
		}
		fmt.sbprintf(&b, ":%d", i64(1) << uint(f.value) if flags else i64(f.value))
	}
	return strings.to_string(b)
}

// The element type of packed array type `t`; NIL for any other type.
@(private)
packed_element :: proc "contextless" (t: gde.VariantType) -> gde.VariantType {
	#partial switch t {
	case .PACKED_BYTE_ARRAY, .PACKED_INT32_ARRAY, .PACKED_INT64_ARRAY: return .INT
	case .PACKED_FLOAT32_ARRAY, .PACKED_FLOAT64_ARRAY: return .FLOAT
	case .PACKED_STRING_ARRAY: return .STRING
	case .PACKED_VECTOR2_ARRAY: return .VECTOR2
	case .PACKED_VECTOR3_ARRAY: return .VECTOR3
	case .PACKED_COLOR_ARRAY: return .COLOR
	case .PACKED_VECTOR4_ARRAY: return .VECTOR4
	}
	return .NIL
}

@(private)
field_meta :: proc "contextless" (f: ^Field) -> gde.ClassMethodArgumentMetadata {
	#partial switch f.type {
	case .INT:
		if f.unsigned {
			switch f.size {
			case 1: return .INT_IS_UINT8
			case 2: return .INT_IS_UINT16
			case 4: return .INT_IS_UINT32
			}
			return .INT_IS_UINT64
		}
		switch f.size {
		case 1: return .INT_IS_INT8
		case 2: return .INT_IS_INT16
		case 4: return .INT_IS_INT32
		}
		return .INT_IS_INT64
	case .FLOAT:
		return .REAL_IS_FLOAT if f.size == 4 else .REAL_IS_DOUBLE
	}
	return .NONE
}

@(private)
read_int :: #force_inline proc "contextless" (p: rawptr, size: int, unsigned: bool) -> i64 {
	if unsigned {
		switch size {
		case 1: return i64((^u8)(p)^)
		case 2: return i64((^u16)(p)^)
		case 4: return i64((^u32)(p)^)
		}
		return (^i64)(p)^
	}
	switch size {
	case 1: return i64((^i8)(p)^)
	case 2: return i64((^i16)(p)^)
	case 4: return i64((^i32)(p)^)
	}
	return (^i64)(p)^
}

@(private)
write_int :: #force_inline proc "contextless" (p: rawptr, size: int, value: i64) {
	switch size {
	case 1: (^i8)(p)^ = i8(value)
	case 2: (^i16)(p)^ = i16(value)
	case 4: (^i32)(p)^ = i32(value)
	case: (^i64)(p)^ = value
	}
}

@(private)
read_float :: #force_inline proc "contextless" (p: rawptr, size: int) -> f64 {
	return f64((^f32)(p)^) if size == 4 else (^f64)(p)^
}

@(private)
write_float :: #force_inline proc "contextless" (p: rawptr, size: int, value: f64) {
	if size == 4 { (^f32)(p)^ = f32(value) } else { (^f64)(p)^ = value }
}

@(private)
field_at :: #force_inline proc "contextless" (instance: gde.ClassInstancePtr, f: ^Field) -> rawptr {
	return rawptr(uintptr(instance) + HEADER + f.offset)
}

// `obj` as a RefCounted when it is one, else nil.
@(private)
counted_object :: proc(obj: rawptr) -> RefCounted {
	return cast_to(Object(obj), RefCounted)
}

// Stores `obj` in the object field `f` at `p`, holding a reference when it is RefCounted and
// releasing the one the field held.
@(private)
store_object :: proc(f: ^Field, p: rawptr, obj: rawptr) {
	old := (^rawptr)(p)^
	if obj == old { return }
	if !f.counted {
		(^rawptr)(p)^ = obj
		return
	}
	if rc := counted_object(obj); rc != nil { ref_counted_reference(rc) }
	(^rawptr)(p)^ = obj
	if rc := counted_object(old); rc != nil { release(rc) }
}

// `obj` with one more reference when it is RefCounted, for returning an engine object that is kept:
// a method's return hands its caller one reference.
share_object :: proc "contextless" (obj: $T) -> T where intrinsics.type_base_type(T) == rawptr {
	context = runtime.default_context()
	if rc := counted_object(rawptr(obj)); rc != nil { ref_counted_reference(rc) }
	return obj
}

// Native code's write to an object field of a record at `slot`: holds a reference to `obj` when it is
// RefCounted and releases the one the field held, as a script's assignment does. Null clears.
hold :: proc "contextless" (slot: ^$T, obj: T) where intrinsics.type_base_type(T) == rawptr {
	context = runtime.default_context()
	if obj == slot^ { return }
	if rc := counted_object(rawptr(obj)); rc != nil { ref_counted_reference(rc) }
	old := slot^
	slot^ = obj
	if rc := counted_object(rawptr(old)); rc != nil { release(rc) }
}

// Native code's write to a StringName field of a record at `slot`: the field keeps its own reference
// to `name`, released at the record's free or the next write.
hold_name :: proc "contextless" (slot: ^StringName, name: StringName) {
	name := name
	copy := name_copy(&name)
	string_name_destroy(slot)
	slot^ = copy
}

@(private)
field_get_ptr :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstTypePtr, ret: gde.TypePtr) {
	f := (^Field)(userdata)
	p := field_at(instance, f)
	#partial switch f.type {
	case .BOOL:
		(^u8)(ret)^ = (^u8)(p)^
	case .INT:
		(^i64)(ret)^ = read_int(p, f.size, f.unsigned)
	case .FLOAT:
		(^f64)(ret)^ = read_float(p, f.size)
	case .OBJECT:
		// The slot is a Ref or a Variant's object, either unreferenced on destroy.
		context = ctx
		enter()
		obj := (^rawptr)(p)^
		if f.counted && counted_object(obj) != nil {
			gde.ref_set_object(ret, gde.ObjectPtr(obj))
		} else {
			(^rawptr)(ret)^ = obj
		}
	case:
		if counted(f.type) {
			destroy[f.type](ret)
			src := [1]gde.ConstTypePtr{p}
			copy_from[f.type](ret, &src[0])
		} else {
			intrinsics.mem_copy(ret, p, f.size)
		}
	}
}

@(private)
field_get_call :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {
	if count != 0 {
		err.error = .ERROR_TOO_MANY_ARGUMENTS
		err.expected = 0
		return
	}
	f := (^Field)(userdata)
	p := field_at(instance, f)
	#partial switch f.type {
	case .BOOL:
		variant_into((^Variant)(ret), (^u8)(p)^ != 0)
	case .INT:
		variant_into((^Variant)(ret), read_int(p, f.size, f.unsigned))
	case .FLOAT:
		variant_into((^Variant)(ret), read_float(p, f.size))
	case .OBJECT:
		if (^rawptr)(p)^ == nil { gde.variant_new_nil(ret) } else { from_type[.OBJECT](ret, p) }
	case:
		from_type[f.type](ret, p)
	}
	err.error = .OK
}

@(private)
field_set_ptr :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstTypePtr, ret: gde.TypePtr) {
	f := (^Field)(userdata)
	p := field_at(instance, f)
	a := args[0]
	#partial switch f.type {
	case .BOOL:
		(^u8)(p)^ = 1 if (^u8)(a)^ != 0 else 0
	case .INT:
		write_int(p, f.size, (^i64)(a)^)
	case .FLOAT:
		write_float(p, f.size, (^f64)(a)^)
	case .OBJECT:
		context = ctx
		enter()
		store_object(f, p, (^rawptr)(a)^)
	case .DICTIONARY:
		// As a typed Array: assign converts the entries or refuses and leaves the field.
		if f.array_of != nil {
			dictionary_assign((^Dictionary)(p), (^Dictionary)(a)^)
		} else {
			tmp: Dictionary
			src := [1]gde.ConstTypePtr{a}
			copy_from[.DICTIONARY](&tmp, &src[0])
			destroy[.DICTIONARY](p)
			(^Dictionary)(p)^ = tmp
		}
	case .ARRAY:
		// A typed field keeps its type: assign converts the elements or refuses and leaves it.
		if f.array_of != nil {
			array_assign((^Array)(p), (^Array)(a)^)
		} else {
			tmp: Array
			src := [1]gde.ConstTypePtr{a}
			copy_from[.ARRAY](&tmp, &src[0])
			destroy[.ARRAY](p)
			(^Array)(p)^ = tmp
		}
	case:
		if counted(f.type) {
			// Copy first: `a` may be this field.
			tmp: [MOST_FIELD]u8
			src := [1]gde.ConstTypePtr{a}
			copy_from[f.type](&tmp, &src[0])
			destroy[f.type](p)
			intrinsics.mem_copy(p, &tmp, f.size)
		} else {
			intrinsics.mem_copy(p, a, f.size)
		}
	}
}

// Bytes of the largest counted builtin a field can be: a packed array.
@(private)
MOST_FIELD :: 16

// Bytes of the largest builtin a field can be: a Projection.
@(private)
MOST_VALUE :: 64

@(private)
field_set_call :: proc "c" (userdata: rawptr, instance: gde.ClassInstancePtr, args: [^]gde.ConstVariantPtr, count: gde.Int, ret: gde.VariantPtr, err: ^gde.CallError) {
	f := (^Field)(userdata)
	// A bool, int or float of the field's own type needs no conversion, context or temp memory.
	if count == 1 && variant_tag(args[0]) == f.type && field_set_scalar(f, field_at(instance, f), args[0]) {
		err.error = .OK
		return
	}
	field_set_slow(f, instance, args, count, err)
}

// Writes `v`, a Variant of `f`'s own type, to the field at `p` when that type is a bool, int or
// float. Reports whether it did.
@(private = "file")
field_set_scalar :: #force_inline proc "contextless" (f: ^Field, p: rawptr, v: gde.ConstVariantPtr) -> bool {
	#partial switch f.type {
	case .BOOL:
		(^u8)(p)^ = 1 if variant_value(u8, v) != 0 else 0
	case .INT:
		write_int(p, f.size, variant_value(i64, v))
	case .FLOAT:
		write_float(p, f.size, variant_value(f64, v))
	case:
		return false
	}
	return true
}

// Every other set: converts the argument, checks object classes and copies builtins.
@(private = "file")
field_set_slow :: proc "contextless" (f: ^Field, instance: gde.ClassInstancePtr, args: [^]gde.ConstVariantPtr, count: gde.Int, err: ^gde.CallError) {
	context = ctx
	enter()
	if count != 1 {
		err.error = .ERROR_TOO_MANY_ARGUMENTS if count > 1 else .ERROR_TOO_FEW_ARGUMENTS
		err.expected = 1
		return
	}
	v := args[0]
	have := variant_tag(v)
	made: Variant
	reshaped := reshapes(have, f.type) && reshape(v, f.type, &made)
	defer if reshaped { gde.variant_destroy(&made) }
	if reshaped {
		v = &made
		have = f.type
	}
	fits := converts(have, f.type) || (f.type == .OBJECT && have == .OBJECT)
	obj: rawptr
	if fits && have == .OBJECT {
		to_type[.OBJECT](&obj, auto_cast v)
		fits = obj == nil || f.tag == nil || gde.object_cast_to(gde.ConstObjectPtr(obj), f.tag) != nil
		fits = fits && (obj == nil || f.exact == nil || object_is_class(Object(obj), f.exact^))
	}
	if !fits {
		err.error = .ERROR_INVALID_ARGUMENT
		err.argument = 0
		err.expected = i32(f.type)
		return
	}
	p := field_at(instance, f)
	#partial switch f.type {
	case .BOOL:
		(^u8)(p)^ = 1 if variant_bool(v) else 0
	case .INT:
		write_int(p, f.size, variant_int(v))
	case .FLOAT:
		write_float(p, f.size, variant_float(v))
	case .OBJECT:
		store_object(f, p, obj)
	case:
		// Holds any builtin a field can be, counted or not.
		tmp: [MOST_VALUE]u8
		#assert(MOST_VALUE >= size_of(Projection))
		to_type[f.type](&tmp, auto_cast v)
		if f.type == .ARRAY && f.array_of != nil {
			array_assign((^Array)(p), (^Array)(&tmp)^)
			destroy[.ARRAY](&tmp)
		} else if f.type == .DICTIONARY && f.array_of != nil {
			dictionary_assign((^Dictionary)(p), (^Dictionary)(&tmp)^)
			destroy[.DICTIONARY](&tmp)
		} else {
			if counted(f.type) { destroy[f.type](p) }
			intrinsics.mem_copy(p, &tmp, f.size)
		}
	}
	err.error = .OK
}

// Makes the counted fields of a new instance at `self`, which holds a bitwise copy of the template,
// valid: the template's counted values copied and objects referenced; Array and Dictionary fields
// empty, typed as their tag says; a new field its own object.
@(private)
fields_init :: proc(l: ^Layout, self: rawptr) {
	for f in l.fields {
		p := rawptr(uintptr(self) + f.offset)
		#partial switch f.type {
		case .ARRAY, .DICTIONARY:
			make_empty[f.type](p, nil)
			if f.array_of == nil { continue }
			if f.type == .DICTIONARY {
				gde.dictionary_set_typed(p, f.key, f.key_of, &nil_variant, f.element, f.array_of, &nil_variant)
				continue
			}
			class := f.array_of if f.element == .OBJECT else &empty_name
			gde.array_set_typed(p, f.element, class, &nil_variant)
		case .OBJECT:
			if !f.counted { continue }
			if f.fresh != nil {
				// A RefCounted object returns holding the one reference the field takes over.
				obj := gde.classdb_construct_object3(f.fresh)
				object_notification(Object(obj), 0, false)
				(^rawptr)(p)^ = rawptr(obj)
				continue
			}
			if rc := counted_object((^rawptr)(p)^); rc != nil { ref_counted_reference(rc) }
		case:
			if l.template != nil && counted(f.type) {
				src := [1]gde.ConstTypePtr{rawptr(uintptr(l.template) + f.offset)}
				copy_from[f.type](p, &src[0])
			}
		}
	}
}

// Destroys an instance's counted fields and releases the objects it holds.
@(private)
fields_release :: proc(l: ^Layout, self: rawptr) {
	for f in l.fields {
		p := rawptr(uintptr(self) + f.offset)
		if f.type == .OBJECT {
			if !f.counted { continue }
			if rc := counted_object((^rawptr)(p)^); rc != nil { release(rc) }
		} else if counted(f.type) {
			destroy[f.type](p)
		}
	}
}
