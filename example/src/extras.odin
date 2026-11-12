// The class hooks beyond fields and methods: dynamic properties, revert values, property
// validation, `_to_string`, a virtual for scripts to override, flags, a typed Dictionary, an
// engine singleton, a runtime-only class and an editor plugin.
package example

import "../../godot"
import gde "../../gdextension"
import "base:runtime"
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
	// A tint, read and written as the indexed properties `tint_r`, `tint_g` and `tint_b`.
	tint:   [3]f64 `godot:"-"`,
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

// The registered Ghost class, for `get_node` to find Ghost structs.
ghost_class: ^godot.Class(Ghost)

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
	godot.method(b, "worker_temp_freed", bag_worker_temp_freed)
	godot.method(b, "task_text", bag_task_text, {"x"})
	godot.method(b, "misuse_task", bag_misuse_task)
	godot.method(b, "bump_all", bag_bump_all, {"xs"})
	godot.method(b, "range_of", bag_range_of, {"n"})
	godot.method(b, "weighted", bag_weighted, {"d"})
	godot.method(b, "typed_range", bag_typed_range, {"n"})
	godot.method(b, "typed_words", bag_typed_words)
	godot.method(b, "typed_nodes", bag_typed_nodes, {"n"})
	godot.method(b, "typed_bump", bag_typed_bump, {"xs"})
	godot.method(b, "typed_shout", bag_typed_shout, {"xs"})
	godot.method(b, "named", bag_named, {"s"})
	godot.method(b, "pathed", bag_pathed, {"s"})
	godot.method(b, "find_2d", bag_find_2d, {"root", "path"})
	godot.method(b, "find_ghost", bag_find_ghost, {"root", "path"})
	godot.method(b, "ghost_seen", bag_ghost_seen, {"root"})
	godot.method(b, "is_jump", bag_is_jump, {"name"})
	godot.method(b, "texts", bag_texts, {"name", "path"})
	godot.method(b, "say", bag_say, {"n"})
	godot.method(b, "adder", bag_adder, {"n"})
	godot.method(b, "slot_adder", bag_slot_adder, {"slot"})
	godot.method(b, "defer", bag_defer, {"n"})
	godot.method(b, "proc_total", bag_proc_total)
	godot.method(b, "dict_squares", bag_dict_squares, {"n"})
	godot.method(b, "dict_words", bag_dict_words)
	godot.method(b, "dict_loose", bag_dict_loose)
	godot.method(b, "load_kinds", bag_load_kinds, {"path"})
	godot.method(b, "load_speed", bag_load_speed, {"path"})
	godot.method(b, "greet", bag_greet, {"name"})
	godot.method(b, "kinds", bag_kinds, {"label"})
	godot.method(b, "describe", bag_describe, {"node", "n"})
	godot.method(b, "text_size", bag_text_size, {"s"})
	godot.method(b, "same_text", bag_same_text, {"a", "b"})
	godot.method(b, "lone_byte_matches", bag_lone_byte_matches)
	godot.method(b, "text_ends", bag_text_ends, {"s", "part"})
	godot.method(b, "which", bag_which, {"s"})
	godot.method(b, "which_name", bag_which_name, {"name"})
	godot.method(b, "find_text", bag_find_text, {"s", "part", "from"})
	godot.method(b, "has_text", bag_has_text, {"s", "part"})
	godot.method(b, "rfind_text", bag_rfind_text, {"s", "part", "from"})
	godot.method(b, "nocase", bag_nocase, {"s", "part", "from"})
	godot.method(b, "count_text", bag_count_text, {"s", "part", "from", "to"})
	godot.property_indexed(b, "tint", {"tint_r", "tint_g", "tint_b"}, bag_get_tint, bag_set_tint, .PROPERTY_HINT_RANGE, "0,1")
	godot.method(b, "lib_path", bag_lib_path)
	godot.method(b, "lookup", bag_lookup, {"d", "key"})
	godot.method(b, "tally", bag_tally, {"d", "word"})
	godot.method(b, "put", bag_put, {"d", "key", "value"})
	godot.method(b, "member", bag_member, {"v", "key"})
	godot.property(b, "brightness", bag_get_brightness, bag_set_brightness)
	godot.method(b, "temp_live", bag_temp_live)
	godot.method(b, "count", bag_count)
	score_virtual = godot.script_virtual(b, "_score", proc(self: ^Bag, x: i64) -> i64, {"x"})

	t := godot.class(Tally, "Tally", "Object")
	godot.method(t, "bump", tally_bump)
	bump_name = godot.static_name("bump")
	tally_name := godot.static_name("Tally")
	tally = gde.classdb_construct_object3(&tally_name)
	godot.object_notification(godot.Object(tally), 0, false)
	godot.register_singleton("ExampleTally", godot.Object(tally))

	ghost_class = godot.class(Ghost, "Ghost", "Node", nil, godot.Options(Ghost){runtime = true})
	godot.fields(ghost_class)
	// Bag methods that take or make Ghosts register after Ghost.
	godot.method(b, "typed_ghosts", bag_typed_ghosts, {"g", "n"})
	godot.method(b, "ghost_total", bag_ghost_total, {"xs"})
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
	godot.print("ExamplePlugin: in the %s", "editor")
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

// Whether worker threads give back the temp memory a task used: one group takes 8 MiB of temp per
// call, twice the default block, then a second group finds every worker's temp arena empty and
// no bigger than one default block.
bag_worker_temp_freed :: proc(self: ^Bag) -> bool {
	CALLS :: 64
	job := Temp_Job{kept = make([]uint, CALLS, context.temp_allocator)}
	godot.wait_group(godot.run_group(take_temp, &job, CALLS))
	godot.wait_group(godot.run_group(check_temp, &job, CALLS))
	for k in job.kept {
		if k > runtime.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE { return false }
	}
	return true
}

Temp_Job :: struct {
	// Per call of `check_temp`: its thread's temp capacity, or max(uint) when bytes stayed in use.
	kept: []uint,
}

take_temp :: proc(job: ^Temp_Job, i: int) {
	buf := make([]u8, 8 << 20, context.temp_allocator)
	buf[len(buf) - 1] = u8(i)
}

check_temp :: proc(job: ^Temp_Job, i: int) {
	// The arena as the call found it: the trampoline's mark is the only one on it.
	a := &(^runtime.Default_Temp_Allocator)(context.temp_allocator.data).arena
	used := a.curr_block.used if a.curr_block != nil else 0
	job.kept[i] = max(uint) if used != 0 else a.total_capacity
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

// The ints 0 to `n - 1` in a new Array[int].
bag_typed_range :: proc(self: ^Bag, n: i64) -> godot.Array {
	xs := make([]i32, max(n, 0), context.temp_allocator)
	for &x, i in xs { x = i32(i) }
	return godot.array_typed_of(xs)
}

// ["a", "bc"] as a new Array[String].
bag_typed_words :: proc(self: ^Bag) -> godot.Array {
	words := [2]godot.String{godot.string_of("a"), godot.string_of("bc")}
	defer for &w in words { godot.destroy[.STRING](&w) }
	return godot.array_typed_of(words[:])
}

// `n` nulls in a new Array[Node].
bag_typed_nodes :: proc(self: ^Bag, n: i64) -> godot.Array {
	xs := make([]godot.Node, max(n, 0), context.temp_allocator)
	return godot.array_typed_of(xs)
}

// `g`, `n` times, in a new Array[Ghost]: a typed Array of a registered class.
bag_typed_ghosts :: proc(self: ^Bag, g: ^Ghost, n: i64) -> godot.Array {
	xs := make([]^Ghost, max(n, 0), context.temp_allocator)
	for &x in xs { x = g }
	return godot.array_typed_of(xs)
}

// The sum of `seen` over the Array[Ghost] `xs`; -1 for any other Array.
bag_ghost_total :: proc(self: ^Bag, xs: godot.Array) -> i64 {
	xs := xs
	if godot.array_size(&xs) == 0 { return 0 }
	slots := godot.array_write_typed(&xs, ^Ghost)
	if slots == nil { return -1 }
	total: i64
	for &v in slots {
		if g := godot.from_variant(^Ghost, &v); g != nil { total += g.seen }
	}
	return total
}

// Adds 1 to every element of the Array[int] `xs` in place. False, with `xs` untouched, for any
// other Array.
bag_typed_bump :: proc(self: ^Bag, xs: godot.Array) -> bool {
	xs := xs
	if godot.array_size(&xs) == 0 { return true }
	slots := godot.array_write_typed(&xs, i64)
	if slots == nil { return false }
	for &v in slots { godot.variant_into(&v, godot.variant_int(&v) + 1) }
	return true
}

// Appends "!" to every element of the Array[String] `xs` in place. False, with `xs` untouched,
// for any other Array.
bag_typed_shout :: proc(self: ^Bag, xs: godot.Array) -> bool {
	xs := xs
	if godot.array_size(&xs) == 0 { return true }
	slots := godot.array_write_typed(&xs, godot.String)
	if slots == nil { return false }
	for &v in slots {
		s: godot.String
		godot.to_type[.STRING](&s, &v)
		defer godot.destroy[.STRING](&s)
		godot.string_append(&s, "!")
		gde.variant_destroy(&v)
		godot.variant_into(&v, s)
	}
	return true
}

// `s` made into a StringName from Odin text.
bag_named :: proc(self: ^Bag, s: string) -> godot.StringName {
	return godot.name_of(s)
}

// `s` made into a NodePath from Odin text.
bag_pathed :: proc(self: ^Bag, s: string) -> godot.NodePath {
	return godot.path_of(s)
}

// Whether `root` has a Node2D at `path`.
bag_find_2d :: proc(self: ^Bag, root: godot.Node, path: string) -> bool {
	return godot.get_node(root, path, godot.Node2D) != nil
}

// The `seen` of the Ghost at `path` from `root`, or -1 when there is none.
bag_find_ghost :: proc(self: ^Bag, root: godot.Node, path: string) -> i64 {
	g := godot.get_node(root, path, ghost_class)
	return g.seen if g != nil else -1
}

// The `seen` of the Ghost at the fixed path "Sprite/Ghost", or -1, through an interned NodePath;
// and whether "Sprite" is a Node2D the same way.
bag_ghost_seen :: proc(self: ^Bag, root: godot.Node) -> i64 {
	if godot.get_node(root, godot.intern_path("Sprite"), godot.Node2D) == nil { return -2 }
	g := godot.get_node(root, godot.intern_path("Sprite/Ghost"), ghost_class)
	return g.seen if g != nil else -1
}

// `name` and `path` as Odin text, joined by "|".
bag_texts :: proc(self: ^Bag, name: godot.StringName, path: godot.NodePath) -> string {
	return fmt.tprintf("%s|%s", godot.utf8(name, context.temp_allocator), godot.utf8(path, context.temp_allocator))
}

// Sets `node`'s editor description from Odin text: a cached constant for `n` = 0, else text built
// at run time. Answers the live temp_text count, and for `n` != 0 first the count inside a nested
// engine-call scope times 10: 0, or 21 when the nested scope's own text ended with it.
bag_describe :: proc(self: ^Bag, node: godot.Node, n: i64) -> i64 {
	if n == 0 {
		godot.node_set_editor_description(node, godot.intern_text("fixed"))
		return i64(godot.temp_texts_live())
	}
	godot.node_set_editor_description(node, godot.temp_text(fmt.tprintf("item %d", n)))
	inner: int
	{
		godot.enter()
		_ = godot.temp_text("inner")
		inner = godot.temp_texts_live()
	}
	return i64(inner * 10 + godot.temp_texts_live())
}

// `s`'s length, or -1 when it is empty, through the generated `string_length` and `string_is_empty`.
bag_text_size :: proc(self: ^Bag, s: godot.String) -> i64 {
	s := s
	if godot.string_is_empty(&s) { return -1 }
	return godot.string_length(&s)
}

// Whether `a` and `b` are equal by `string_equal`, as bit 0, and `a` matches `b`'s text by
// `string_equal_text`, as bit 1.
bag_same_text :: proc(self: ^Bag, a: godot.String, b: godot.String) -> i64 {
	a, b := a, b
	text := godot.utf8(b)
	defer delete(text)
	return i64(godot.string_equal(&a, &b)) | i64(godot.string_equal_text(&a, text)) << 1
}

// Whether "é" matches the lone byte 0xE9, its code but invalid UTF-8; it must not. GDScript cannot
// pass invalid UTF-8, so the text is fixed here.
bag_lone_byte_matches :: proc(self: ^Bag) -> bool {
	s := godot.string_of("é")
	defer godot.destroy[.STRING](&s)
	return godot.string_equal_text(&s, "\xE9")
}

// Whether `s` begins with `part`'s text, as bit 0, and ends with it, as bit 1: by
// `string_begins_with_text` and `string_ends_with_text`. Bits 2 and 3 are the same ignoring case.
bag_text_ends :: proc(self: ^Bag, s: godot.String, part: godot.String) -> i64 {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	r := i64(godot.string_begins_with_text(&s, text)) | i64(godot.string_ends_with_text(&s, text)) << 1
	r |= i64(godot.string_begins_with_text_nocase(&s, text)) << 2 | i64(godot.string_ends_with_text_nocase(&s, text)) << 3
	return r
}

// The index of `s` among a fixed set of names by `string_which`, or -1. "jump" and "jo-p" share a
// key, so the full compare picks between them; "rin", "jamp" and "jo本p" match a key and no name.
bag_which :: proc(self: ^Bag, s: godot.String) -> i64 {
	@(static) set: godot.Text_Set(7)
	@(static) built: bool
	if !built {
		set = godot.text_set([7]string{"jump", "run", "walk", "日本", "", "runs", "jo-p"})
		built = true
	}
	s := s
	return i64(godot.string_which(&s, &set))
}

// The index of `name` among a fixed set of names by `name_which`, or -1.
bag_which_name :: proc(self: ^Bag, name: godot.StringName) -> i64 {
	set := godot.name_set([4]string{"jump", "run", "日本", ""})
	defer godot.name_set_destroy(&set)
	return i64(godot.name_which(name, &set))
}

// Where `part`'s text first appears in `s` at or after `from`, by `string_find_text`.
bag_find_text :: proc(self: ^Bag, s: godot.String, part: godot.String, from: i64) -> i64 {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	return godot.string_find_text(&s, text, from)
}

// The case-insensitive compares of `part`'s text against `s`, packed for one call: bits 0 to 15
// hold `string_findn_text` + 1, bits 16 to 31 `string_rfindn_text` + 1, bit 32
// `string_containsn_text` and bit 33 `string_equal_text_nocase`.
bag_nocase :: proc(self: ^Bag, s: godot.String, part: godot.String, from: i64) -> i64 {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	r := (godot.string_findn_text(&s, text, from) + 1) & 0xFFFF
	r |= ((godot.string_rfindn_text(&s, text, from) + 1) & 0xFFFF) << 16
	r |= i64(godot.string_containsn_text(&s, text)) << 32
	r |= i64(godot.string_equal_text_nocase(&s, text)) << 33
	return r
}

// `string_count_text` of `part`'s text in `s` between `from` and `to` in bits 0 to 31, and
// `string_countn_text` in bits 32 and up.
bag_count_text :: proc(self: ^Bag, s: godot.String, part: godot.String, from: i64, to: i64) -> i64 {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	return godot.string_count_text(&s, text, from, to) | godot.string_countn_text(&s, text, from, to) << 32
}

// Where `part`'s text last appears in `s` at or before `from`, by `string_rfind_text`.
bag_rfind_text :: proc(self: ^Bag, s: godot.String, part: godot.String, from: i64) -> i64 {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	return godot.string_rfind_text(&s, text, from)
}

// Whether `part`'s text appears in `s`, by `string_contains_text`.
bag_has_text :: proc(self: ^Bag, s: godot.String, part: godot.String) -> bool {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	return godot.string_contains_text(&s, text)
}

// One channel of the tint, 0 to 2; 0 for any other index.
bag_get_tint :: proc(self: ^Bag, index: i64) -> f64 {
	if index < 0 || index >= len(self.tint) { return 0 }
	return self.tint[index]
}

// Sets one channel of the tint; ignores any other index.
bag_set_tint :: proc(self: ^Bag, index: i64, value: f64) {
	if index < 0 || index >= len(self.tint) { return }
	self.tint[index] = value
}

// The tint's mean channel.
bag_get_brightness :: proc(self: ^Bag) -> f64 {
	return (self.tint[0] + self.tint[1] + self.tint[2]) / 3
}

// Sets every channel of the tint to `value`.
bag_set_brightness :: proc(self: ^Bag, value: f64) {
	self.tint = value
}

// `d[key]`, or "missing" when `d` has no such key.
bag_lookup :: proc(self: ^Bag, d: godot.Dictionary, key: godot.Variant) -> godot.Variant {
	d := d
	value, found := godot.dict_get(&d, key)
	if !found { return godot.variant("missing") }
	return value
}

// Counts `word` in `d`, a Dictionary of words to counts, through an Odin string key. False when `d`
// does not take it.
bag_tally :: proc(self: ^Bag, d: godot.Dictionary, word: string) -> bool {
	d := d
	n: i64
	if v, found := godot.dict_get(&d, word); found {
		n = godot.variant_int(&v)
		gde.variant_destroy(&v)
	}
	return godot.dict_set(&d, word, n + 1)
}

// `d[key] = value`, or false when `d` does not take them.
bag_put :: proc(self: ^Bag, d: godot.Dictionary, key, value: godot.Variant) -> bool {
	d := d
	return godot.dict_set(&d, key, value)
}

// `v[key]` for any Variant, or "missing".
bag_member :: proc(self: ^Bag, v: godot.Variant, key: string) -> godot.Variant {
	v := v
	value, found := godot.variant_get(&v, key)
	if !found { return godot.variant("missing") }
	return value
}

// This library's path, as the engine reports it.
bag_lib_path :: proc() -> godot.String {
	return godot.library_path()
}

// The live temp_text count between calls: 0.
bag_temp_live :: proc() -> i64 {
	return i64(godot.temp_texts_live())
}

// `label`, then the Variant type of each extra argument: a vararg method.
bag_kinds :: proc(self: ^Bag, label: string, rest: []godot.Variant) -> string {
	out := fmt.tprintf("%s:", label)
	for &v, i in rest {
		out = fmt.tprintf("%s%s%d", out, "," if i > 0 else "", int(godot.variant_tag(&v)))
	}
	return out
}

// How many arguments it got: a static vararg method with no other parameters.
bag_count :: proc(rest: []godot.Variant) -> i64 {
	return i64(len(rest))
}

// Whether `name` is "jump", compared against an interned name; and the interned name itself, the
// same one on every call.
bag_is_jump :: proc(self: ^Bag, name: godot.StringName) -> bool {
	return godot.same_name(name, godot.intern("jump")) && godot.same_name(godot.intern("jump"), godot.intern("jump"))
}

// Prints "Bag says `n`" to the engine's output.
bag_say :: proc(self: ^Bag, n: i64) {
	godot.print("Bag says %d", n)
}

// What `add_scaled` has added up, for the plain-proc Callables to show they ran.
proc_total: i64

// Adds `x * n` to `proc_total`: a plain proc with no instance, for `callable(f, binds..)`.
add_scaled :: proc(x, n: i64) {
	proc_total += x * n
}

// Adds `x` to slot `slot`, ignoring a slot out of range.
bag_add_to_slot :: proc(self: ^Bag, x, slot: i64) {
	if slot < 0 || slot >= SLOTS { return }
	self.slots[slot] += x
}

// A Callable `c` whose `c.call(x)` adds `x * n` to `proc_total`.
bag_adder :: proc(self: ^Bag, n: i64) -> godot.Callable {
	return godot.callable(add_scaled, godot.variant(n))
}

// A Callable `c` whose `c.call(x)` adds `x` to this bag's slot `slot`.
bag_slot_adder :: proc(self: ^Bag, slot: i64) -> godot.Callable {
	return godot.callable(self, bag_add_to_slot, godot.variant(slot))
}

// At the end of the frame, adds `n` to `proc_total` and to slot 2.
bag_defer :: proc(self: ^Bag, n: i64) {
	godot.call_deferred(add_scaled, godot.variant(n), godot.variant(i64(1)))
	godot.call_deferred(self, bag_add_to_slot, godot.variant(n), godot.variant(i64(2)))
}

// `proc_total`, a static method.
bag_proc_total :: proc() -> i64 {
	return proc_total
}

// {0: 0, 1: 1, 2: 4...} up to `n - 1`, untyped.
bag_dict_squares :: proc(self: ^Bag, n: i64) -> godot.Dictionary {
	keys := make([]i64, max(n, 0), context.temp_allocator)
	values := make([]f64, max(n, 0), context.temp_allocator)
	for i in 0 ..< len(keys) {
		keys[i] = i64(i)
		values[i] = f64(i * i)
	}
	return godot.dict_of(keys, values)
}

// {"a": 3, "bc": 2} as a Dictionary[String, int], from a key list that repeats "a".
bag_dict_words :: proc(self: ^Bag) -> godot.Dictionary {
	keys := [3]godot.String{godot.string_of("a"), godot.string_of("bc"), godot.string_of("a")}
	defer for &k in keys { godot.destroy[.STRING](&k) }
	values := [3]i32{1, 2, 3}
	return godot.dict_typed_of(keys[:], values[:])
}

// {1: "x", 2: null} as a Dictionary[int, Variant].
bag_dict_loose :: proc(self: ^Bag) -> godot.Dictionary {
	x := godot.string_of("x")
	defer godot.destroy[.STRING](&x)
	keys := [2]i64{1, 2}
	values := [2]godot.Variant{godot.variant(x), {}}
	defer for &v in values { gde.variant_destroy(&v) }
	return godot.dict_typed_of(keys[:], values[:])
}

// Which of Resource, Texture2D and Walker `load` finds at `path`, as the bits 1, 2 and 4.
bag_load_kinds :: proc(self: ^Bag, path: string) -> i64 {
	kinds: i64
	if r := godot.load(path, godot.Resource); r != nil {
		kinds |= 1
		godot.release(r)
	}
	if t := godot.load(path, godot.Texture2D); t != nil {
		kinds |= 2
		godot.release(t)
	}
	if w := godot.load(path, walker_class); w != nil {
		kinds |= 4
		godot.release(godot.object_of(w))
	}
	return kinds
}

// The speed of the Walker resource at `path`, or -1 when there is none.
bag_load_speed :: proc(self: ^Bag, path: string) -> f64 {
	w := godot.load(path, walker_class)
	if w == nil { return -1 }
	defer godot.release(godot.object_of(w))
	return w.speed
}

// "hi, `name`" with its byte count: Odin strings in and out, copied at the call boundary.
bag_greet :: proc(self: ^Bag, name: string) -> string {
	return fmt.tprintf("hi, %s (%d bytes)", name, len(name))
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
