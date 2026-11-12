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
bump_name: godot.StringName

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
	godot.method(b, "doubled", bag_doubled, {"xs"})
	godot.method(b, "squares", bag_squares, {"n"})
	godot.method(b, "colors", bag_colors)
	godot.method(b, "vowels", bag_vowels, {"s"})
	godot.method(b, "second", bag_second, {"xs"})
	godot.method(b, "redden", bag_redden, {"img"})
	godot.method(b, "file_sum", bag_file_sum, {"path"})
	godot.method(b, "shout", bag_shout, {"s"})
	godot.method(b, "parallel_sum", bag_parallel_sum, {"n"})
	godot.method(b, "task_text", bag_task_text, {"x"})
	godot.method(b, "misuse_task", bag_misuse_task)
	godot.method(b, "bump_all", bag_bump_all, {"xs"})
	godot.method(b, "range_of", bag_range_of, {"n"})
	godot.method(b, "weighted", bag_weighted, {"d"})
	score_virtual = godot.script_virtual(b, "_score", proc(self: ^Bag, x: i64) -> i64, {"x"})

	t := godot.class(Tally, "Tally", "Object")
	godot.method(t, "bump", tally_bump)
	bump_name = godot.static_name("bump")
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
	for x in godot.packed_read(&xs) { sum += x }
	return sum
}

// A copy of `xs` with every element doubled. `xs` is borrowed, so the copy is written, not `xs`.
bag_doubled :: proc(self: ^Bag, xs: godot.PackedInt64Array) -> godot.PackedInt64Array {
	out := godot.packed_int64_array_new_from_packed_int64_array(xs)
	for &x in godot.packed_write(&out) { x *= 2 }
	return out
}

// The squares of 0 to `n - 1`, built in an Odin slice and handed over in one copy.
bag_squares :: proc(self: ^Bag, n: i64) -> godot.PackedInt64Array {
	xs := make([]i64, max(n, 0), context.temp_allocator)
	for &x, i in xs { x = i64(i * i) }
	return godot.packed_of(xs)
}

// The names of the bag's flags.
bag_colors :: proc(self: ^Bag) -> godot.PackedStringArray {
	names := [3]godot.String{godot.string_of("red"), godot.string_of("green"), godot.string_of("blue")}
	defer for &n in names { godot.destroy[.STRING](&n) }
	return godot.packed_of(names[:])
}

// The vowels in `s`, read in place, counting accented ones.
bag_vowels :: proc(self: ^Bag, s: godot.String) -> i64 {
	s := s
	n: i64
	for c in godot.string_read(&s) {
		switch c {
		case 'a', 'e', 'i', 'o', 'u', 'é', 'è', 'à': n += 1
		}
	}
	return n
}

// Element 1 of `xs`, or null when it has none.
bag_second :: proc(self: ^Bag, xs: godot.Array) -> godot.Variant {
	xs := xs
	out: godot.Variant
	if v := godot.array_at(&xs, 1); v != nil { gde.variant_new_copy(&out, v) }
	return out
}

// Sets the red of every pixel of `img`, an RGBA8 image, to full, written in place. Any other
// format is left alone.
bag_redden :: proc(self: ^Bag, img: godot.Image) {
	if godot.image_get_format(img) != .FORMAT_RGBA8 { return }
	px := godot.image_write(img)
	for i := 0; i < len(px); i += 4 { px[i] = 255 }
}

// The sum of the bytes of the file at `path`, read 64 at a time; -1 when it cannot be opened.
bag_file_sum :: proc(self: ^Bag, path: godot.String) -> i64 {
	f := godot.file_access_open(path, .READ)
	if f == nil { return -1 }
	defer godot.release(f)
	buf: [64]u8
	sum: i64
	for {
		n := godot.file_read(f, buf[:])
		for x in buf[:n] { sum += i64(x) }
		if n < len(buf) { break }
	}
	return sum
}

// `s`, then "!¡", '?' and `s` again, appended in place to one new String.
bag_shout :: proc(self: ^Bag, s: godot.String) -> godot.String {
	out := godot.string_new_from_string(s)
	godot.string_append(&out, "!¡")
	godot.string_append(&out, '?')
	godot.string_append(&out, s)
	return out
}

SUM_CHUNK :: 1024

// A sum split into chunks, one per worker call; each call writes only its own part.
Sum_Job :: struct {
	n:     int,
	parts: []i64,
}

// The sum of 0 to `n - 1`, in chunks spread over the engine's worker threads.
bag_parallel_sum :: proc(self: ^Bag, n: i64) -> i64 {
	count := int(max(n, 0))
	job := Sum_Job{n = count, parts = make([]i64, (count + SUM_CHUNK - 1) / SUM_CHUNK, context.temp_allocator)}
	if len(job.parts) == 0 { return 0 }
	godot.wait_group(godot.run_group(sum_chunk, &job, len(job.parts), description = "Bag.parallel_sum"))
	sum: i64
	for p in job.parts { sum += p }
	return sum
}

sum_chunk :: proc(job: ^Sum_Job, i: int) {
	for k in i * SUM_CHUNK ..< min((i + 1) * SUM_CHUNK, job.n) { job.parts[i] += i64(k) }
}

// The input and result of one worker task.
Text_Job :: struct {
	x:   i64,
	len: int,
}

// The length of "task <x>", formatted on a worker thread in that thread's temp memory.
bag_task_text :: proc(self: ^Bag, x: i64) -> i64 {
	job := Text_Job{x = x}
	godot.wait_task(godot.run_task(text_task, &job))
	return i64(job.len)
}

text_task :: proc(job: ^Text_Job) {
	job.len = len(fmt.tprintf("task %d", job.x))
}

// Adds 1 to every int element of `xs` in place, which the caller sees, as with `xs[i] += 1` in
// GDScript. False, with `xs` untouched, when it is typed or read-only.
bag_bump_all :: proc(self: ^Bag, xs: godot.Array) -> bool {
	xs := xs
	if godot.array_size(&xs) == 0 { return true }
	slots := godot.array_write(&xs)
	if slots == nil { return false }
	for &v in slots {
		if godot.variant_tag(&v) != .INT { continue }
		n := godot.variant_int(&v)
		// An int holds nothing to destroy, so it is overwritten as is.
		godot.variant_into(&v, n + 1)
	}
	return true
}

// The ints 0 to `n - 1` in a new Array, built in an Odin slice and copied over in one resize.
bag_range_of :: proc(self: ^Bag, n: i64) -> godot.Array {
	xs := make([]i64, max(n, 0), context.temp_allocator)
	for &x, i in xs { x = i64(i) }
	return godot.array_of(xs)
}

// The sum of key times value over the int entries of `d`.
bag_weighted :: proc(self: ^Bag, d: godot.Dictionary) -> i64 {
	d := d
	keys, values := godot.dict_items(&d)
	defer godot.array_destroy(&keys)
	defer godot.array_destroy(&values)
	sum: i64
	vs := godot.array_read(&values)
	for &k, i in godot.array_read(&keys) {
		if godot.variant_tag(&k) != .INT || godot.variant_tag(&vs[i]) != .INT { continue }
		sum += godot.variant_int(&k) * godot.variant_int(&vs[i])
	}
	return sum
}

// Calls `ExampleTally.bump` from a worker task, which tasks must not do. A debug build stops the
// process there, as example/build.sh checks; it does not return.
bag_misuse_task :: proc(self: ^Bag) {
	godot.wait_task(godot.run_task(bump_from_task, &tally))
}

bump_from_task :: proc(t: ^gde.ObjectPtr) {
	v := godot.object_call(godot.Object(t^), bump_name)
	gde.variant_destroy(&v)
}

// Calls so far, counting this one.
tally_bump :: proc(self: ^Tally) -> i64 {
	self.calls += 1
	return self.calls
}
