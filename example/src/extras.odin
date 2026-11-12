// The class hooks beyond fields and methods: dynamic properties, revert values, property
// validation, `_to_string`, a virtual for scripts to override, flags, a typed Dictionary, an
// engine singleton, a runtime-only class and an editor plugin.
package example

import "../../godot"
import gde "../../gdextension"
import "core:fmt"

// The flags a Bag can carry; bit_set[Mark] crosses as their bitfield.
Mark :: enum {
	RED,
	GREEN,
	BLUE,
}

SLOTS :: 4

// A bag of four numbered slots, read and written as the properties `slot_0` to `slot_3`.
Bag :: struct {
	// Flags, a checklist in the inspector.
	marks:  bit_set[Mark],
	// Names to counts.
	counts: godot.Dictionary `dict:"String,int"`,
	// An unsigned byte, which reads back past 127.
	level:  u8,
	// Shown in the inspector only while `show_note` is set.
	note:   i64,
	show_note: bool,
	// An object of its own, made with the bag and released with it.
	box:    godot.RefCounted `godot:"new"`,
	slots:  [SLOTS]i64 `godot:"-"`,
}

slot_names: [SLOTS]godot.StringName
note_name: godot.StringName
score_virtual: ^godot.StringName
tally: gde.ObjectPtr

// An Object the extension makes once and gives the engine as the singleton `ExampleTally`.
Tally :: struct {
	calls: i64 `godot:"-"`,
}

// A Node that exists only in a running game: in the editor its instances are placeholders.
Ghost :: struct {
	seen: i64,
}

// The editor plugin the extension adds to the editor.
ExamplePlugin :: struct {}

register_extras :: proc() {
	for i in 0 ..< SLOTS { slot_names[i] = godot.static_name(fmt.ctprintf("slot_%d", i)) }
	note_name = godot.static_name("note")
	b := godot.class(Bag, "Bag", "RefCounted", nil, godot.Options(Bag){
		get = bag_get,
		set = bag_set,
		property_list = bag_property_list,
		can_revert = bag_can_revert,
		get_revert = bag_get_revert,
		validate = bag_validate,
		to_string = bag_to_string,
	})
	godot.enumerate_flags(b, "Mark", Mark)
	godot.fields(b)
	godot.method(b, "score", bag_score, {"x"})
	godot.method(b, "has_marks", bag_has_marks, {"marks"})
	godot.method(b, "total", bag_total, {"xs"})
	score_virtual = godot.script_virtual(b, "_score", proc(self: ^Bag, x: i64) -> i64, {"x"})

	t := godot.class(Tally, "Tally", "Object")
	godot.method(t, "bump", tally_bump)
	tally_name := godot.static_name("Tally")
	tally = gde.classdb_construct_object3(&tally_name)
	godot.object_notification(godot.Object(tally), 0, false)
	godot.register_singleton("ExampleTally", godot.Object(tally))

	g := godot.class(Ghost, "Ghost", "Node", nil, godot.Options(Ghost){runtime = true})
	godot.fields(g)
}

unload_extras :: proc() {
	gde.object_destroy(tally)
}

register_editor :: proc() {
	p := godot.class(ExamplePlugin, "ExamplePlugin", "EditorPlugin")
	godot.override_editor_plugin_get_plugin_name(p, plugin_name)
	godot.override_node_enter_tree(p, plugin_entered)
	godot.editor_plugin(p)
}

// Logs that the editor took the plugin, which example/build.sh checks for.
plugin_entered :: proc(self: ^ExamplePlugin) {
	text := godot.string_of("ExamplePlugin: in the editor")
	defer godot.destroy[.STRING](&text)
	v := godot.variant(text)
	defer gde.variant_destroy(&v)
	godot.utility_print(v)
}

plugin_name :: proc(self: ^ExamplePlugin) -> godot.String {
	return godot.string_of("Example")
}

slot_of :: proc(name: godot.StringName) -> int {
	for i in 0 ..< SLOTS {
		if godot.same_name(name, slot_names[i]) { return i }
	}
	return -1
}

bag_get :: proc(self: ^Bag, name: godot.StringName) -> (godot.Variant, bool) {
	i := slot_of(name)
	if i < 0 { return {}, false }
	return godot.variant(self.slots[i]), true
}

bag_set :: proc(self: ^Bag, name: godot.StringName, value: ^godot.Variant) -> bool {
	i := slot_of(name)
	if i < 0 { return false }
	self.slots[i] = godot.variant_int(value)
	return true
}

bag_property_list :: proc(self: ^Bag, list: ^[dynamic]godot.Property) {
	for i in 0 ..< SLOTS {
		append(list, godot.Property{name = fmt.tprintf("slot_%d", i), type = .INT})
	}
}

// A slot reverts to 0.
bag_can_revert :: proc(self: ^Bag, name: godot.StringName) -> bool {
	i := slot_of(name)
	return i >= 0 && self.slots[i] != 0
}

bag_get_revert :: proc(self: ^Bag, name: godot.StringName) -> (godot.Variant, bool) {
	if slot_of(name) < 0 { return {}, false }
	return godot.variant(i64(0)), true
}

// Hides `note` from the inspector unless `show_note` is set, and gives it a hint text.
bag_validate :: proc(self: ^Bag, info: ^gde.PropertyInfo) {
	if !godot.same_name((^godot.StringName)(info.name)^, note_name) { return }
	if !self.show_note { info.usage &~= u32(godot.PropertyUsageFlags_PROPERTY_USAGE_EDITOR) }
	godot.set_hint_string(info, "a note")
}

bag_to_string :: proc(self: ^Bag) -> string {
	return fmt.tprintf("Bag(%d, %d, %d, %d)", self.slots[0], self.slots[1], self.slots[2], self.slots[3])
}

// The script's `_score(x)`, or -1 when the script has none.
bag_score :: proc(self: ^Bag, x: i64) -> i64 {
	ret, found := godot.call_script(self, score_virtual, godot.variant(x))
	defer gde.variant_destroy(&ret)
	if !found { return -1 }
	return godot.variant_int(&ret)
}

// Whether the bag carries every flag in `marks`.
bag_has_marks :: proc(self: ^Bag, marks: bit_set[Mark]) -> bool {
	return marks <= self.marks
}

// The sum of `xs`. An untyped call may pass an Array, which arrives converted.
bag_total :: proc(self: ^Bag, xs: godot.PackedInt64Array) -> i64 {
	xs := xs
	sum: i64
	for i in 0 ..< godot.packed_int64_array_size(&xs) { sum += godot.packed_int64_array_get(&xs, i) }
	return sum
}

// Calls so far, counting this one.
tally_bump :: proc(self: ^Tally) -> i64 {
	self.calls += 1
	return self.calls
}
