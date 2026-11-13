// The class hooks beyond fields and methods: dynamic properties, revert values, property
// validation, `_to_string`, a virtual for scripts to override, flags, a typed Dictionary, an
// engine singleton, a runtime-only class and an editor plugin.
package example

import "../../godot"
import gde "../../gdextension"
import "base:intrinsics"
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
	godot.method(b, "replaced_ops", bag_replaced_ops, {"s", "part", "from", "to"})
	godot.method(b, "replaced_strs", bag_replaced_strs, {"s", "part", "with", "allow_empty", "maxsplit"})
	godot.method(b, "replaced_name_ops", bag_replaced_name_ops, {"n", "part", "from", "to"})
	godot.method(b, "replaced_numbers", bag_replaced_numbers, {"texts"})
	godot.method(b, "replaced_paths", bag_replaced_paths, {"texts"})
	godot.method(b, "replaced_name_strs", bag_replaced_name_strs, {"n", "part", "with", "allow_empty", "maxsplit"})
	godot.method(b, "replaced_vectors", bag_replaced_vectors, {"a", "b", "c", "d", "n2", "n3", "w", "x", "y", "z"})
	godot.method(b, "replaced_vectorsi", bag_replaced_vectorsi, {"a", "b", "c", "x", "y", "f"})
	godot.method(b, "replaced_colors", bag_replaced_colors, {"a", "b", "c", "x", "n"})
	godot.method(b, "replaced_color_texts", bag_replaced_color_texts, {"a", "s", "d", "x", "h", "sat", "l", "r"})
	godot.method(b, "replaced_bases", bag_replaced_bases, {"a", "b", "v", "w", "x", "n"})
	godot.method(b, "replaced_transforms2d", bag_replaced_transforms2d, {"a", "b", "p", "q", "x", "y"})
	godot.method(b, "replaced_transforms3d", bag_replaced_transforms3d, {"a", "b", "v", "w", "m", "x"})
	godot.method(b, "replaced_quaternions", bag_replaced_quaternions, {"a", "b", "c", "d", "m", "v", "w", "x", "n"})
	godot.method(b, "replaced_planes", bag_replaced_planes, {"a", "b", "c", "v", "w", "u", "x"})
	godot.method(b, "replaced_aabbs", bag_replaced_aabbs, {"a", "b", "p", "v", "w", "x", "n"})
	godot.method(b, "replaced_rect2s", bag_replaced_rect2s, {"a", "b", "c", "v", "w", "x", "n"})
	godot.method(b, "replaced_rect2is", bag_replaced_rect2is, {"a", "b", "v", "w", "n", "m"})
	godot.method(b, "replaced_projections", bag_replaced_projections, {"a", "t", "r", "box", "w", "q", "x", "y", "z", "u", "n", "m", "flip"})
	godot.method(b, "replaced_packed", bag_replaced_packed, {"arrays", "values", "index", "from", "before"})
	godot.method(b, "replaced_array", bag_replaced_array, {"arrays", "values", "index", "from"})
	godot.method(b, "replaced_dict", bag_replaced_dict, {"dicts", "keys", "key_sets", "default"})
	godot.method(b, "layouts_proven", bag_layouts_proven)
	godot.method(b, "find_text", bag_find_text, {"s", "part", "from"})
	godot.method(b, "has_text", bag_has_text, {"s", "part"})
	godot.method(b, "rfind_text", bag_rfind_text, {"s", "part", "from"})
	godot.method(b, "nocase", bag_nocase, {"s", "part", "from"})
	godot.method(b, "count_text", bag_count_text, {"s", "part", "from", "to"})
	godot.method(b, "replace_text", bag_replace_text, {"s", "part", "with", "nocase"})
	godot.method(b, "split_text", bag_split_text, {"s", "part", "allow_empty", "maxsplit"})
	godot.method(b, "split_lengths", bag_split_lengths, {"s", "part"})
	godot.method(b, "split_strip", bag_split_strip, {"s", "part", "left", "right"})
	godot.method(b, "part_ints", bag_part_ints, {"s", "part"})
	godot.method(b, "part_is", bag_part_is, {"s", "part", "word"})
	godot.method(b, "part_floats", bag_part_floats, {"s", "part"})
	godot.method(b, "int_texts", bag_int_texts, {"numbers", "base", "capitalize_hex"})
	godot.method(b, "float_texts", bag_float_texts, {"numbers", "decimals"})
	godot.method(b, "real_texts", bag_real_texts, {"numbers", "trailing"})
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

// The String procs that replace engine methods, on `s` and `part`: find, rfind, findn and rfindn
// from `from`, then contains, containsn, count and countn from `from` to `to`, begins_with and
// ends_with, booleans as 0 or 1, then casecmp_to and nocasecmp_to. test.gd builds the same array from the engine's methods.
bag_replaced_ops :: proc(self: ^Bag, s: godot.String, part: godot.String, from: i64, to: i64) -> godot.PackedInt64Array {
	s := s
	r := [12]i64{
		godot.string_find(&s, part, from),
		godot.string_rfind(&s, part, from),
		godot.string_findn(&s, part, from),
		godot.string_rfindn(&s, part, from),
		i64(godot.string_contains(&s, part)),
		i64(godot.string_containsn(&s, part)),
		godot.string_count(&s, part, from, to),
		godot.string_countn(&s, part, from, to),
		i64(godot.string_begins_with(&s, part)),
		i64(godot.string_ends_with(&s, part)),
		godot.string_casecmp_to(&s, part),
		godot.string_nocasecmp_to(&s, part),
	}
	out := godot.packed_int64_array_new()
	for v in r { godot.packed_int64_array_append(&out, v) }
	return out
}

// The String procs that replace engine methods and make Strings: replace and replacen of `part` by
// `with` in `s`, then the parts of split on `part`. test.gd builds the same array from the engine's.
bag_replaced_strs :: proc(self: ^Bag, s: godot.String, part: godot.String, with: godot.String, allow_empty: bool, maxsplit: i64) -> godot.PackedStringArray {
	s := s
	out := godot.packed_string_array_new()
	r := godot.string_replace(&s, part, with)
	godot.packed_string_array_append(&out, r)
	godot.destroy[.STRING](&r)
	r = godot.string_replacen(&s, part, with)
	godot.packed_string_array_append(&out, r)
	godot.destroy[.STRING](&r)
	parts := godot.string_split(&s, part, allow_empty, maxsplit)
	godot.packed_string_array_append_array(&out, parts)
	godot.destroy[.PACKED_STRING_ARRAY](&parts)
	return out
}

// bag_replaced_ops through the StringName methods on `n`, then its length, is_empty as 0 or 1 and
// hash. test.gd builds the same array from the engine's StringName methods.
bag_replaced_name_ops :: proc(self: ^Bag, n: godot.StringName, part: godot.String, from: i64, to: i64) -> godot.PackedInt64Array {
	n := n
	r := [15]i64{
		godot.string_name_find(&n, part, from),
		godot.string_name_rfind(&n, part, from),
		godot.string_name_findn(&n, part, from),
		godot.string_name_rfindn(&n, part, from),
		i64(godot.string_name_contains(&n, part)),
		i64(godot.string_name_containsn(&n, part)),
		godot.string_name_count(&n, part, from, to),
		godot.string_name_countn(&n, part, from, to),
		i64(godot.string_name_begins_with(&n, part)),
		i64(godot.string_name_ends_with(&n, part)),
		godot.string_name_casecmp_to(&n, part),
		godot.string_name_nocasecmp_to(&n, part),
		godot.string_name_length(&n),
		i64(godot.string_name_is_empty(&n)),
		godot.string_name_hash(&n),
	}
	out := godot.packed_int64_array_new()
	for v in r { godot.packed_int64_array_append(&out, v) }
	return out
}

// bag_replaced_strs through the StringName methods on `n`.
bag_replaced_name_strs :: proc(self: ^Bag, n: godot.StringName, part: godot.String, with: godot.String, allow_empty: bool, maxsplit: i64) -> godot.PackedStringArray {
	n := n
	out := godot.packed_string_array_new()
	r := godot.string_name_replace(&n, part, with)
	godot.packed_string_array_append(&out, r)
	godot.destroy[.STRING](&r)
	r = godot.string_name_replacen(&n, part, with)
	godot.packed_string_array_append(&out, r)
	godot.destroy[.STRING](&r)
	parts := godot.string_name_split(&n, part, allow_empty, maxsplit)
	godot.packed_string_array_append_array(&out, parts)
	godot.destroy[.PACKED_STRING_ARRAY](&parts)
	return out
}

// Floats gathered for bag_replaced_vectors, in call order.
Vector_Results :: struct {
	v: [400]f32,
	n: int,
}

// Appends `v` to `o` as floats: a vector or Basis by component (a Basis row by row), a boolean
// or an index as its number.
put_result :: proc(o: ^Vector_Results, v: $T) {
	when T == godot.Basis {
		put_result(o, v.x)
		put_result(o, v.y)
		put_result(o, v.z)
	} else when intrinsics.type_is_array(T) {
		for e in v { put_result(o, f64(e)) }
	} else when T == bool {
		put_result(o, f64(1 if v else 0))
	} else {
		o.v[o.n] = f32(v)
		o.n += 1
	}
}

// The Vector2, Vector3 and Vector4 procs that replace engine methods (godot/vector.odin), each on
// the leading components of `a` to `d`, with `n2` and `n3` the normals and rotation axis, `w` the
// weight and `x`, `y` and `z` the other scalars. test.gd's _vector_results calls the engine's own
// methods in the same order.
bag_replaced_vectors :: proc(self: ^Bag, a, b, c, d: godot.Vector4, n2: godot.Vector2, n3: godot.Vector3, w, x, y, z: f64) -> godot.PackedFloat32Array {
	o: Vector_Results
	a2, b2, c2, d2 := godot.Vector2(a.xy), godot.Vector2(b.xy), godot.Vector2(c.xy), godot.Vector2(d.xy)
	put_result(&o, godot.vector2_angle(&a2))
	put_result(&o, godot.vector2_angle_to(&a2, b2))
	put_result(&o, godot.vector2_angle_to_point(&a2, b2))
	put_result(&o, godot.vector2_direction_to(&a2, b2))
	put_result(&o, godot.vector2_distance_to(&a2, b2))
	put_result(&o, godot.vector2_distance_squared_to(&a2, b2))
	put_result(&o, godot.vector2_length(&a2))
	put_result(&o, godot.vector2_length_squared(&a2))
	put_result(&o, godot.vector2_limit_length(&a2, x))
	put_result(&o, godot.vector2_normalized(&a2))
	put_result(&o, godot.vector2_is_normalized(&a2))
	put_result(&o, godot.vector2_is_equal_approx(&a2, b2))
	put_result(&o, godot.vector2_is_zero_approx(&a2))
	put_result(&o, godot.vector2_is_finite(&a2))
	put_result(&o, godot.vector2_posmod(&a2, x))
	put_result(&o, godot.vector2_posmodv(&a2, b2))
	put_result(&o, godot.vector2_project(&a2, b2))
	put_result(&o, godot.vector2_lerp(&a2, b2, w))
	put_result(&o, godot.vector2_slerp(&a2, b2, w))
	put_result(&o, godot.vector2_cubic_interpolate(&a2, b2, c2, d2, w))
	put_result(&o, godot.vector2_cubic_interpolate_in_time(&a2, b2, c2, d2, w, x, y, z))
	put_result(&o, godot.vector2_bezier_interpolate(&a2, b2, c2, d2, w))
	put_result(&o, godot.vector2_bezier_derivative(&a2, b2, c2, d2, w))
	put_result(&o, godot.vector2_max_axis_index(&a2))
	put_result(&o, godot.vector2_min_axis_index(&a2))
	put_result(&o, godot.vector2_move_toward(&a2, b2, x))
	put_result(&o, godot.vector2_rotated(&a2, x))
	put_result(&o, godot.vector2_orthogonal(&a2))
	put_result(&o, godot.vector2_floor(&a2))
	put_result(&o, godot.vector2_ceil(&a2))
	put_result(&o, godot.vector2_round(&a2))
	put_result(&o, godot.vector2_aspect(&a2))
	put_result(&o, godot.vector2_dot(&a2, b2))
	put_result(&o, godot.vector2_slide(&a2, n2))
	put_result(&o, godot.vector2_bounce(&a2, n2))
	put_result(&o, godot.vector2_reflect(&a2, n2))
	put_result(&o, godot.vector2_cross(&a2, b2))
	put_result(&o, godot.vector2_abs(&a2))
	put_result(&o, godot.vector2_sign(&a2))
	put_result(&o, godot.vector2_clamp(&a2, b2, c2))
	put_result(&o, godot.vector2_clampf(&a2, y, z))
	put_result(&o, godot.vector2_snapped(&a2, b2))
	put_result(&o, godot.vector2_snappedf(&a2, x))
	put_result(&o, godot.vector2_min(&a2, b2))
	put_result(&o, godot.vector2_minf(&a2, x))
	put_result(&o, godot.vector2_max(&a2, b2))
	put_result(&o, godot.vector2_maxf(&a2, x))
	put_result(&o, godot.vector2_from_angle(x))
	put_result(&o, godot.vector2_new_from_float_float(x, y))
	put_result(&o, godot.vector2_new_from_vector2i(godot.Vector2i{i32(x), i32(y)}))

	a3, b3, c3, d3 := godot.Vector3(a.xyz), godot.Vector3(b.xyz), godot.Vector3(c.xyz), godot.Vector3(d.xyz)
	put_result(&o, godot.vector3_angle_to(&a3, b3))
	put_result(&o, godot.vector3_signed_angle_to(&a3, b3, n3))
	put_result(&o, godot.vector3_direction_to(&a3, b3))
	put_result(&o, godot.vector3_distance_to(&a3, b3))
	put_result(&o, godot.vector3_distance_squared_to(&a3, b3))
	put_result(&o, godot.vector3_length(&a3))
	put_result(&o, godot.vector3_length_squared(&a3))
	put_result(&o, godot.vector3_limit_length(&a3, x))
	put_result(&o, godot.vector3_normalized(&a3))
	put_result(&o, godot.vector3_is_normalized(&a3))
	put_result(&o, godot.vector3_is_equal_approx(&a3, b3))
	put_result(&o, godot.vector3_is_zero_approx(&a3))
	put_result(&o, godot.vector3_is_finite(&a3))
	put_result(&o, godot.vector3_inverse(&a3))
	put_result(&o, godot.vector3_clamp(&a3, b3, c3))
	put_result(&o, godot.vector3_clampf(&a3, y, z))
	put_result(&o, godot.vector3_snapped(&a3, b3))
	put_result(&o, godot.vector3_snappedf(&a3, x))
	put_result(&o, godot.vector3_rotated(&a3, n3, x))
	put_result(&o, godot.vector3_lerp(&a3, b3, w))
	put_result(&o, godot.vector3_slerp(&a3, b3, w))
	put_result(&o, godot.vector3_cubic_interpolate(&a3, b3, c3, d3, w))
	put_result(&o, godot.vector3_cubic_interpolate_in_time(&a3, b3, c3, d3, w, x, y, z))
	put_result(&o, godot.vector3_bezier_interpolate(&a3, b3, c3, d3, w))
	put_result(&o, godot.vector3_bezier_derivative(&a3, b3, c3, d3, w))
	put_result(&o, godot.vector3_move_toward(&a3, b3, x))
	put_result(&o, godot.vector3_dot(&a3, b3))
	put_result(&o, godot.vector3_cross(&a3, b3))
	put_result(&o, godot.vector3_outer(&a3, b3))
	put_result(&o, godot.vector3_abs(&a3))
	put_result(&o, godot.vector3_floor(&a3))
	put_result(&o, godot.vector3_ceil(&a3))
	put_result(&o, godot.vector3_round(&a3))
	put_result(&o, godot.vector3_posmod(&a3, x))
	put_result(&o, godot.vector3_posmodv(&a3, b3))
	put_result(&o, godot.vector3_project(&a3, b3))
	put_result(&o, godot.vector3_slide(&a3, n3))
	put_result(&o, godot.vector3_bounce(&a3, n3))
	put_result(&o, godot.vector3_reflect(&a3, n3))
	put_result(&o, godot.vector3_sign(&a3))
	put_result(&o, godot.vector3_octahedron_encode(&a3))
	put_result(&o, godot.vector3_min(&a3, b3))
	put_result(&o, godot.vector3_minf(&a3, x))
	put_result(&o, godot.vector3_max(&a3, b3))
	put_result(&o, godot.vector3_maxf(&a3, x))
	put_result(&o, godot.vector3_octahedron_decode(a2))
	put_result(&o, godot.vector3_min_axis_index(&a3))
	put_result(&o, godot.vector3_max_axis_index(&a3))
	put_result(&o, godot.vector3_new_from_float_float_float(x, y, z))
	put_result(&o, godot.vector3_new_from_vector3i(godot.Vector3i{i32(x), i32(y), i32(z)}))

	a4 := a
	put_result(&o, godot.vector4_min_axis_index(&a4))
	put_result(&o, godot.vector4_max_axis_index(&a4))
	put_result(&o, godot.vector4_length(&a4))
	put_result(&o, godot.vector4_length_squared(&a4))
	put_result(&o, godot.vector4_abs(&a4))
	put_result(&o, godot.vector4_sign(&a4))
	put_result(&o, godot.vector4_floor(&a4))
	put_result(&o, godot.vector4_ceil(&a4))
	put_result(&o, godot.vector4_round(&a4))
	put_result(&o, godot.vector4_lerp(&a4, b, w))
	put_result(&o, godot.vector4_cubic_interpolate(&a4, b, c, d, w))
	put_result(&o, godot.vector4_cubic_interpolate_in_time(&a4, b, c, d, w, x, y, z))
	put_result(&o, godot.vector4_posmod(&a4, x))
	put_result(&o, godot.vector4_posmodv(&a4, b))
	put_result(&o, godot.vector4_snapped(&a4, b))
	put_result(&o, godot.vector4_snappedf(&a4, x))
	put_result(&o, godot.vector4_clamp(&a4, b, c))
	put_result(&o, godot.vector4_clampf(&a4, y, z))
	put_result(&o, godot.vector4_normalized(&a4))
	put_result(&o, godot.vector4_is_normalized(&a4))
	put_result(&o, godot.vector4_direction_to(&a4, b))
	put_result(&o, godot.vector4_distance_to(&a4, b))
	put_result(&o, godot.vector4_distance_squared_to(&a4, b))
	put_result(&o, godot.vector4_dot(&a4, b))
	put_result(&o, godot.vector4_inverse(&a4))
	put_result(&o, godot.vector4_is_equal_approx(&a4, b))
	put_result(&o, godot.vector4_is_zero_approx(&a4))
	put_result(&o, godot.vector4_is_finite(&a4))
	put_result(&o, godot.vector4_min(&a4, b))
	put_result(&o, godot.vector4_minf(&a4, x))
	put_result(&o, godot.vector4_max(&a4, b))
	put_result(&o, godot.vector4_maxf(&a4, x))
	put_result(&o, godot.vector4_new_from_float_float_float_float(w, x, y, z))
	put_result(&o, godot.vector4_new_from_vector4i(godot.Vector4i{i32(w), i32(x), i32(y), i32(z)}))
	return godot.packed_of_float32(o.v[:o.n])
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

// The length of each part of `s` split on `part`'s text, read through `string_split_parts`.
bag_split_lengths :: proc(self: ^Bag, s: godot.String, part: godot.String) -> godot.PackedInt64Array {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	out := godot.packed_int64_array_new()
	parts := godot.string_split_parts(&s, text)
	for p in godot.split_next(&parts) {
		godot.packed_int64_array_append(&out, i64(len(p)))
	}
	return out
}

// The parts of `s` split on `part`'s text, each trimmed by `runes_strip_edges` and made a String
// by `string_of_runes`.
bag_split_strip :: proc(self: ^Bag, s: godot.String, part: godot.String, left: bool, right: bool) -> godot.PackedStringArray {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	out := godot.packed_string_array_new()
	parts := godot.string_split_parts(&s, text)
	for p in godot.split_next(&parts) {
		t := godot.string_of_runes(godot.runes_strip_edges(p, left, right))
		godot.packed_string_array_append(&out, t)
		godot.destroy[.STRING](&t)
	}
	return out
}

// `runes_to_int` of each part of `s` split on `part`'s text.
bag_part_ints :: proc(self: ^Bag, s: godot.String, part: godot.String) -> godot.PackedInt64Array {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	out := godot.packed_int64_array_new()
	parts := godot.string_split_parts(&s, text)
	for p in godot.split_next(&parts) {
		godot.packed_int64_array_append(&out, godot.runes_to_int(p))
	}
	return out
}

// The String number reads on each of `texts`, then the same through the StringName of it: to_int,
// the bits of to_float, is_valid_int and is_valid_float as 0 or 1, eight per text. test.gd builds
// the same array from the engine's methods.
bag_replaced_numbers :: proc(self: ^Bag, texts: godot.PackedStringArray) -> godot.PackedInt64Array {
	texts := texts
	out := godot.packed_int64_array_new()
	for &t in godot.packed_read_string(&texts) {
		n := godot.string_name_new_from_string(t)
		defer godot.destroy[.STRING_NAME](&n)
		r := [8]i64{
			godot.string_to_int(&t),
			transmute(i64)godot.string_to_float(&t),
			i64(godot.string_is_valid_int(&t)),
			i64(godot.string_is_valid_float(&t)),
			godot.string_name_to_int(&n),
			transmute(i64)godot.string_name_to_float(&n),
			i64(godot.string_name_is_valid_int(&n)),
			i64(godot.string_name_is_valid_float(&n)),
		}
		for v in r { godot.packed_int64_array_append(&out, v) }
	}
	return out
}

// The NodePath reads of each text's NodePath, in the order `_check_replaced_paths` repeats them:
// `is_empty`, `is_absolute`, both counts, each name, the name past the last, each subname, the
// subname before the first, the concatenated names and subnames twice each (the second read from
// the cache the first fills), then `hash` twice (likewise), then the concatenated names and
// subnames again, both caches now filled, and whether `path_copies_counted` holds.
// Whether each name, subname and filled concatenation `p` returns holds one reference of its own on
// the interned data, as the engine's copy does: the 32-bit count at the start of that data rises by
// one per live copy and falls back when it is destroyed. The count is read from the engine's
// StringName::_Data, so only the counting is checked, not the layout.
path_copies_counted :: proc(p: ^godot.NodePath, names, subnames: i64) -> bool {
	counted :: proc(read: proc(p: ^godot.NodePath) -> godot.StringName, p: ^godot.NodePath) -> bool {
		a := read(p)
		defer godot.destroy[.STRING_NAME](&a)
		if (^rawptr)(&a)^ == nil { return true }
		count := (^u32)((^rawptr)(&a)^)
		held := count^
		b := read(p)
		with_b := count^
		godot.destroy[.STRING_NAME](&b)
		return with_b == held + 1 && count^ == held
	}
	ok := counted(proc(p: ^godot.NodePath) -> godot.StringName { return godot.node_path_get_concatenated_names(p) }, p) &&
		counted(proc(p: ^godot.NodePath) -> godot.StringName { return godot.node_path_get_concatenated_subnames(p) }, p)
	if names > 0 { ok = ok && counted(proc(p: ^godot.NodePath) -> godot.StringName { return godot.node_path_get_name(p, 0) }, p) }
	if subnames > 0 { ok = ok && counted(proc(p: ^godot.NodePath) -> godot.StringName { return godot.node_path_get_subname(p, 0) }, p) }
	return ok
}

bag_replaced_paths :: proc(self: ^Bag, texts: godot.PackedStringArray) -> godot.Array {
	texts := texts
	out := godot.array_new()
	push :: proc(out: ^godot.Array, v: godot.Variant) {
		v := v
		godot.array_push_back(out, v)
		gde.variant_destroy(&v)
	}
	name :: proc(out: ^godot.Array, n: godot.StringName) {
		n := n
		push(out, godot.variant(n))
		godot.destroy[.STRING_NAME](&n)
	}
	for &t in godot.packed_read_string(&texts) {
		p := godot.node_path_new_from_string(t)
		defer godot.destroy[.NODE_PATH](&p)
		names := godot.node_path_get_name_count(&p)
		subnames := godot.node_path_get_subname_count(&p)
		push(&out, godot.variant(godot.node_path_is_empty(&p)))
		push(&out, godot.variant(godot.node_path_is_absolute(&p)))
		push(&out, godot.variant(names))
		push(&out, godot.variant(subnames))
		for k in 0 ..= names { name(&out, godot.node_path_get_name(&p, k)) }
		for k in -1 ..< subnames { name(&out, godot.node_path_get_subname(&p, k)) }
		for _ in 0 ..< 2 { name(&out, godot.node_path_get_concatenated_names(&p)) }
		for _ in 0 ..< 2 { name(&out, godot.node_path_get_concatenated_subnames(&p)) }
		for _ in 0 ..< 2 { push(&out, godot.variant(godot.node_path_hash(&p))) }
		name(&out, godot.node_path_get_concatenated_names(&p))
		name(&out, godot.node_path_get_concatenated_subnames(&p))
		push(&out, godot.variant(path_copies_counted(&p, names, subnames)))
	}
	return out
}

// `string_of_int` of each number.
bag_int_texts :: proc(self: ^Bag, numbers: godot.PackedInt64Array, base: i64, capitalize_hex: bool) -> godot.PackedStringArray {
	numbers := numbers
	values := godot.packed_read_int64(&numbers)
	out := godot.packed_string_array_new()
	godot.packed_string_array_resize(&out, i64(len(values)))
	for &slot, k in godot.packed_write_string(&out) { slot = godot.string_of_int(values[k], base, capitalize_hex) }
	return out
}

// `string_of_float` of each number.
bag_float_texts :: proc(self: ^Bag, numbers: godot.PackedFloat64Array, decimals: i64) -> godot.PackedStringArray {
	numbers := numbers
	values := godot.packed_read_float64(&numbers)
	out := godot.packed_string_array_new()
	godot.packed_string_array_resize(&out, i64(len(values)))
	for &slot, k in godot.packed_write_string(&out) { slot = godot.string_of_float(values[k], decimals) }
	return out
}

// `string_of_real` of each number.
bag_real_texts :: proc(self: ^Bag, numbers: godot.PackedFloat64Array, trailing: bool) -> godot.PackedStringArray {
	numbers := numbers
	values := godot.packed_read_float64(&numbers)
	out := godot.packed_string_array_new()
	godot.packed_string_array_resize(&out, i64(len(values)))
	for &slot, k in godot.packed_write_string(&out) { slot = godot.string_of_real(values[k], trailing) }
	return out
}

// `runes_to_float` of each part of `s` split on `part`'s text.
bag_part_floats :: proc(self: ^Bag, s: godot.String, part: godot.String) -> godot.PackedFloat64Array {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	out := godot.packed_float64_array_new()
	parts := godot.string_split_parts(&s, text)
	for p in godot.split_next(&parts) {
		godot.packed_float64_array_append(&out, godot.runes_to_float(p))
	}
	return out
}

// For each part of `s` split on `part`'s text, whether it is `word`'s text by `runes_equal_text` in
// bit 0 and by `runes_equal_text_nocase` in bit 1.
bag_part_is :: proc(self: ^Bag, s: godot.String, part: godot.String, word: godot.String) -> godot.PackedInt64Array {
	s, part, word := s, part, word
	text, w := godot.utf8(part), godot.utf8(word)
	defer delete(text)
	defer delete(w)
	out := godot.packed_int64_array_new()
	parts := godot.string_split_parts(&s, text)
	for p in godot.split_next(&parts) {
		godot.packed_int64_array_append(&out, i64(godot.runes_equal_text(p, w)) | i64(godot.runes_equal_text_nocase(p, w)) << 1)
	}
	return out
}

// `s` split on `part`'s text by `string_split_text`.
bag_split_text :: proc(self: ^Bag, s: godot.String, part: godot.String, allow_empty: bool, maxsplit: i64) -> godot.PackedStringArray {
	s, part := s, part
	text := godot.utf8(part)
	defer delete(text)
	return godot.string_split_text(&s, text, allow_empty, maxsplit)
}

// `s` with `part`'s text replaced by `with`'s, by `string_replacen_text` when `nocase`, else
// `string_replace_text`.
bag_replace_text :: proc(self: ^Bag, s: godot.String, part: godot.String, with: godot.String, nocase: bool) -> godot.String {
	s, part, with := s, part, with
	what, forwhat := godot.utf8(part), godot.utf8(with)
	defer delete(what)
	defer delete(forwhat)
	return godot.string_replacen_text(&s, what, forwhat) if nocase else godot.string_replace_text(&s, what, forwhat)
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

// Integers gathered for bag_replaced_vectorsi, in call order.
Vectori_Results :: struct {
	v: [200]i64,
	n: int,
}

// Appends `v` to `o` as integers: a vector by component, a double as its bits, an int as itself.
put_int_result :: proc(o: ^Vectori_Results, v: $T) {
	when intrinsics.type_is_array(T) {
		for e in v { put_int_result(o, i64(e)) }
	} else when T == f64 {
		put_int_result(o, transmute(i64)v)
	} else {
		o.v[o.n] = i64(v)
		o.n += 1
	}
}

// Every Vector2i, Vector3i and Vector4i proc on `a` and the other arguments, in the order
// _vectori_results in test.gd calls the engine's methods.
bag_replaced_vectorsi :: proc(self: ^Bag, a, b, c: godot.Vector4i, x, y: i64, f: godot.Vector4) -> godot.PackedInt64Array {
	o: Vectori_Results
	a2, b2, c2 := godot.Vector2i(a.xy), godot.Vector2i(b.xy), godot.Vector2i(c.xy)
	put_int_result(&o, godot.vector2i_new())
	put_int_result(&o, godot.vector2i_new_from_vector2i(a2))
	put_int_result(&o, godot.vector2i_new_from_vector2(godot.Vector2(f.xy)))
	put_int_result(&o, godot.vector2i_new_from_int_int(x, y))
	put_int_result(&o, godot.vector2i_aspect(&a2))
	put_int_result(&o, godot.vector2i_max_axis_index(&a2))
	put_int_result(&o, godot.vector2i_min_axis_index(&a2))
	put_int_result(&o, godot.vector2i_distance_to(&a2, b2))
	put_int_result(&o, godot.vector2i_distance_squared_to(&a2, b2))
	put_int_result(&o, godot.vector2i_length(&a2))
	put_int_result(&o, godot.vector2i_length_squared(&a2))
	put_int_result(&o, godot.vector2i_sign(&a2))
	put_int_result(&o, godot.vector2i_abs(&a2))
	put_int_result(&o, godot.vector2i_clamp(&a2, b2, c2))
	put_int_result(&o, godot.vector2i_clampi(&a2, x, y))
	put_int_result(&o, godot.vector2i_snapped(&a2, b2))
	put_int_result(&o, godot.vector2i_snappedi(&a2, x))
	put_int_result(&o, godot.vector2i_min(&a2, b2))
	put_int_result(&o, godot.vector2i_mini(&a2, x))
	put_int_result(&o, godot.vector2i_max(&a2, b2))
	put_int_result(&o, godot.vector2i_maxi(&a2, x))
	a3, b3, c3 := godot.Vector3i(a.xyz), godot.Vector3i(b.xyz), godot.Vector3i(c.xyz)
	put_int_result(&o, godot.vector3i_new())
	put_int_result(&o, godot.vector3i_new_from_vector3i(a3))
	put_int_result(&o, godot.vector3i_new_from_vector3(godot.Vector3(f.xyz)))
	put_int_result(&o, godot.vector3i_new_from_int_int_int(x, y, x))
	put_int_result(&o, godot.vector3i_max_axis_index(&a3))
	put_int_result(&o, godot.vector3i_min_axis_index(&a3))
	put_int_result(&o, godot.vector3i_distance_to(&a3, b3))
	put_int_result(&o, godot.vector3i_distance_squared_to(&a3, b3))
	put_int_result(&o, godot.vector3i_length(&a3))
	put_int_result(&o, godot.vector3i_length_squared(&a3))
	put_int_result(&o, godot.vector3i_sign(&a3))
	put_int_result(&o, godot.vector3i_abs(&a3))
	put_int_result(&o, godot.vector3i_clamp(&a3, b3, c3))
	put_int_result(&o, godot.vector3i_clampi(&a3, x, y))
	put_int_result(&o, godot.vector3i_snapped(&a3, b3))
	put_int_result(&o, godot.vector3i_snappedi(&a3, x))
	put_int_result(&o, godot.vector3i_min(&a3, b3))
	put_int_result(&o, godot.vector3i_mini(&a3, x))
	put_int_result(&o, godot.vector3i_max(&a3, b3))
	put_int_result(&o, godot.vector3i_maxi(&a3, x))
	a4 := a
	put_int_result(&o, godot.vector4i_new())
	put_int_result(&o, godot.vector4i_new_from_vector4i(a))
	put_int_result(&o, godot.vector4i_new_from_vector4(f))
	put_int_result(&o, godot.vector4i_new_from_int_int_int_int(x, y, y, x))
	put_int_result(&o, godot.vector4i_max_axis_index(&a4))
	put_int_result(&o, godot.vector4i_min_axis_index(&a4))
	put_int_result(&o, godot.vector4i_distance_to(&a4, b))
	put_int_result(&o, godot.vector4i_distance_squared_to(&a4, b))
	put_int_result(&o, godot.vector4i_length(&a4))
	put_int_result(&o, godot.vector4i_length_squared(&a4))
	put_int_result(&o, godot.vector4i_sign(&a4))
	put_int_result(&o, godot.vector4i_abs(&a4))
	put_int_result(&o, godot.vector4i_clamp(&a4, b, c))
	put_int_result(&o, godot.vector4i_clampi(&a4, x, y))
	put_int_result(&o, godot.vector4i_snapped(&a4, b))
	put_int_result(&o, godot.vector4i_snappedi(&a4, x))
	put_int_result(&o, godot.vector4i_min(&a4, b))
	put_int_result(&o, godot.vector4i_mini(&a4, x))
	put_int_result(&o, godot.vector4i_max(&a4, b))
	put_int_result(&o, godot.vector4i_maxi(&a4, x))
	return godot.packed_of_int64(o.v[:o.n])
}

// Integers gathered for bag_replaced_colors, in call order.
Color_Results :: struct {
	v: [128]i64,
	n: int,
}

// Appends `v` to `o` as integers: a Color by the bits of each component, a float as its bits, a
// bool or int as itself. Every NaN becomes one value, since which NaN an operation keeps depends
// on operand order in the compiled code.
put_color_result :: proc(o: ^Color_Results, v: $T) {
	when T == godot.Color {
		for e in v { put_color_result(o, i64(0x7fc00000) if e != e else i64(transmute(u32)e)) }
	} else when T == f64 {
		put_color_result(o, i64(0x7ff8000000000000) if v != v else transmute(i64)v)
	} else {
		o.v[o.n] = i64(v)
		o.n += 1
	}
}

// Every replaced Color proc on `a` and the other arguments, in the order _color_results in
// test.gd calls the engine's methods.
bag_replaced_colors :: proc(self: ^Bag, a, b, c: godot.Color, x: f64, n: i64) -> godot.PackedInt64Array {
	o: Color_Results
	a := a
	put_color_result(&o, godot.color_new())
	put_color_result(&o, godot.color_new_from_color(a))
	put_color_result(&o, godot.color_new_from_color_float(a, x))
	put_color_result(&o, godot.color_new_from_float_float_float(x, f64(b.g), f64(b.b)))
	put_color_result(&o, godot.color_new_from_float_float_float_float(x, f64(b.g), f64(b.b), f64(c.a)))
	put_color_result(&o, godot.color_to_argb32(&a))
	put_color_result(&o, godot.color_to_abgr32(&a))
	put_color_result(&o, godot.color_to_rgba32(&a))
	put_color_result(&o, godot.color_to_argb64(&a))
	put_color_result(&o, godot.color_to_abgr64(&a))
	put_color_result(&o, godot.color_to_rgba64(&a))
	put_color_result(&o, godot.color_clamp(&a, b, c))
	put_color_result(&o, godot.color_inverted(&a))
	put_color_result(&o, godot.color_lerp(&a, b, x))
	put_color_result(&o, godot.color_lightened(&a, x))
	put_color_result(&o, godot.color_darkened(&a, x))
	put_color_result(&o, godot.color_blend(&a, b))
	put_color_result(&o, godot.color_get_luminance(&a))
	put_color_result(&o, godot.color_srgb_to_linear(&a))
	put_color_result(&o, godot.color_linear_to_srgb(&a))
	put_color_result(&o, godot.color_is_equal_approx(&a, b))
	put_color_result(&o, godot.color_hex(n))
	put_color_result(&o, godot.color_hex64(n))
	put_color_result(&o, godot.color_from_hsv(x, f64(a.g), f64(a.b), f64(a.a)))
	put_color_result(&o, godot.color_from_hsv(f64(a.r), f64(b.g), f64(a.b), x))
	put_color_result(&o, godot.color_from_rgbe9995(n))
	put_color_result(&o, godot.color_from_rgba8(n, n >> 40, n % 300, -n))
	return godot.packed_of_int64(o.v[:o.n])
}

// The packed array reads of godot/packed.odin on `arrays`, one array of each packed type in the
// order of their Variant types, each with the value at the same place in `values`: size, is_empty,
// get at `index`, has, find and rfind from `from`, count and bsearch with `before`, as integers.
bag_replaced_packed :: proc(self: ^Bag, arrays: godot.Array, values: godot.Array, index, from: i64, before: bool) -> godot.PackedInt64Array {
	o: Basis_Results
	arrays, values := arrays, values
	as, vs := godot.array_read(&arrays), godot.array_read(&values)
	if len(as) != 10 || len(vs) != 10 { return {} }
	put_packed_reads(&o, godot.PackedByteArray, i64, &as[0], &vs[0], index, from, before, godot.packed_byte_array_size, godot.packed_byte_array_is_empty, godot.packed_byte_array_get, godot.packed_byte_array_has, godot.packed_byte_array_find, godot.packed_byte_array_rfind, godot.packed_byte_array_count, godot.packed_byte_array_bsearch)
	put_packed_reads(&o, godot.PackedInt32Array, i64, &as[1], &vs[1], index, from, before, godot.packed_int32_array_size, godot.packed_int32_array_is_empty, godot.packed_int32_array_get, godot.packed_int32_array_has, godot.packed_int32_array_find, godot.packed_int32_array_rfind, godot.packed_int32_array_count, godot.packed_int32_array_bsearch)
	put_packed_reads(&o, godot.PackedInt64Array, i64, &as[2], &vs[2], index, from, before, godot.packed_int64_array_size, godot.packed_int64_array_is_empty, godot.packed_int64_array_get, godot.packed_int64_array_has, godot.packed_int64_array_find, godot.packed_int64_array_rfind, godot.packed_int64_array_count, godot.packed_int64_array_bsearch)
	put_packed_reads(&o, godot.PackedFloat32Array, f64, &as[3], &vs[3], index, from, before, godot.packed_float32_array_size, godot.packed_float32_array_is_empty, godot.packed_float32_array_get, godot.packed_float32_array_has, godot.packed_float32_array_find, godot.packed_float32_array_rfind, godot.packed_float32_array_count, godot.packed_float32_array_bsearch)
	put_packed_reads(&o, godot.PackedFloat64Array, f64, &as[4], &vs[4], index, from, before, godot.packed_float64_array_size, godot.packed_float64_array_is_empty, godot.packed_float64_array_get, godot.packed_float64_array_has, godot.packed_float64_array_find, godot.packed_float64_array_rfind, godot.packed_float64_array_count, godot.packed_float64_array_bsearch)
	put_packed_reads(&o, godot.PackedStringArray, godot.String, &as[5], &vs[5], index, from, before, godot.packed_string_array_size, godot.packed_string_array_is_empty, godot.packed_string_array_get, godot.packed_string_array_has, godot.packed_string_array_find, godot.packed_string_array_rfind, godot.packed_string_array_count, godot.packed_string_array_bsearch)
	put_packed_reads(&o, godot.PackedVector2Array, godot.Vector2, &as[6], &vs[6], index, from, before, godot.packed_vector2_array_size, godot.packed_vector2_array_is_empty, godot.packed_vector2_array_get, godot.packed_vector2_array_has, godot.packed_vector2_array_find, godot.packed_vector2_array_rfind, godot.packed_vector2_array_count, godot.packed_vector2_array_bsearch)
	put_packed_reads(&o, godot.PackedVector3Array, godot.Vector3, &as[7], &vs[7], index, from, before, godot.packed_vector3_array_size, godot.packed_vector3_array_is_empty, godot.packed_vector3_array_get, godot.packed_vector3_array_has, godot.packed_vector3_array_find, godot.packed_vector3_array_rfind, godot.packed_vector3_array_count, godot.packed_vector3_array_bsearch)
	put_packed_reads(&o, godot.PackedColorArray, godot.Color, &as[8], &vs[8], index, from, before, godot.packed_color_array_size, godot.packed_color_array_is_empty, godot.packed_color_array_get, godot.packed_color_array_has, godot.packed_color_array_find, godot.packed_color_array_rfind, godot.packed_color_array_count, godot.packed_color_array_bsearch)
	put_packed_reads(&o, godot.PackedVector4Array, godot.Vector4, &as[9], &vs[9], index, from, before, godot.packed_vector4_array_size, godot.packed_vector4_array_is_empty, godot.packed_vector4_array_get, godot.packed_vector4_array_has, godot.packed_vector4_array_find, godot.packed_vector4_array_rfind, godot.packed_vector4_array_count, godot.packed_vector4_array_bsearch)
	return godot.packed_of(o.v[:o.n])
}

// The Array reads of godot/array.odin through the generated procs that try them first, in the order
// _array_read_results in test.gd calls the engine's: per array, size, is_empty, get(index), front
// and back, then per value find(value, from), rfind(value, from), count and has.
bag_replaced_array :: proc(self: ^Bag, arrays: godot.Array, values: godot.Array, index, from: i64) -> godot.Array {
	arrays, values := arrays, values
	out := godot.array_new()
	for &e in godot.array_read(&arrays) {
		a := godot.from_variant(godot.Array, &e)
		godot.array_push_back(&out, godot.variant(godot.array_size(&a)))
		godot.array_push_back(&out, godot.variant(godot.array_is_empty(&a)))
		got := [3]godot.Variant{godot.array_get(&a, index), godot.array_front(&a), godot.array_back(&a)}
		for &g in got {
			godot.array_push_back(&out, g)
			gde.variant_destroy(&g)
		}
		for &v in godot.array_read(&values) {
			godot.array_push_back(&out, godot.variant(godot.array_find(&a, v, from)))
			godot.array_push_back(&out, godot.variant(godot.array_rfind(&a, v, from)))
			godot.array_push_back(&out, godot.variant(godot.array_count(&a, v)))
			godot.array_push_back(&out, godot.variant(godot.array_has(&a, v)))
		}
	}
	return out
}

// Whether the layout checks at load all passed, so the in-place reads are on.
bag_layouts_proven :: proc(self: ^Bag) -> bool {
	return godot.layouts_proven()
}

// The Dictionary reads of godot/dictionary.odin on each Dictionary of `dicts`, in the order
// test.gd's `_dict_read_results` makes them: size, is_empty, has_all of each Array of `key_sets`,
// keys and values, then has, get with `default`, the found flag and value of dict_get, and
// find_key of each of `keys`.
bag_replaced_dict :: proc(self: ^Bag, dicts: godot.Array, keys: godot.Array, key_sets: godot.Array, default: godot.Variant) -> godot.Array {
	dicts, keys, key_sets := dicts, keys, key_sets
	out := godot.array_new()
	for &e in godot.array_read(&dicts) {
		d := godot.from_variant(godot.Dictionary, &e)
		godot.array_push_back(&out, godot.variant(godot.dictionary_size(&d)))
		godot.array_push_back(&out, godot.variant(godot.dictionary_is_empty(&d)))
		for &ks in godot.array_read(&key_sets) {
			godot.array_push_back(&out, godot.variant(godot.dictionary_has_all(&d, godot.from_variant(godot.Array, &ks))))
		}
		ks, vs := godot.dictionary_keys(&d), godot.dictionary_values(&d)
		kv, vv := godot.variant(ks), godot.variant(vs)
		godot.array_push_back(&out, kv)
		godot.array_push_back(&out, vv)
		gde.variant_destroy(&kv)
		gde.variant_destroy(&vv)
		godot.destroy[.ARRAY](&ks)
		godot.destroy[.ARRAY](&vs)
		for &k in godot.array_read(&keys) {
			godot.array_push_back(&out, godot.variant(godot.dictionary_has(&d, k)))
			got := godot.dictionary_get(&d, k, default)
			godot.array_push_back(&out, got)
			gde.variant_destroy(&got)
			value, found := godot.dict_get(&d, k)
			godot.array_push_back(&out, godot.variant(found))
			godot.array_push_back(&out, value)
			gde.variant_destroy(&value)
			key := godot.dictionary_find_key(&d, k)
			godot.array_push_back(&out, key)
			gde.variant_destroy(&key)
		}
	}
	return out
}

// Appends the eight reads of `bag_replaced_packed` on the array `a` holds, with the value `v` holds.
// A String from `get` goes in by its hash, a Color by its components.
put_packed_reads :: proc(o: ^Basis_Results, $A, $V: typeid, a, v: ^godot.Variant, index, from: i64, before: bool,
	size: proc "contextless" (^A) -> i64, empty: proc "contextless" (^A) -> bool, get: proc "contextless" (^A, i64) -> $G,
	has: proc "contextless" (^A, V) -> bool, find, rfind: proc "contextless" (^A, V, i64) -> i64,
	count: proc "contextless" (^A, V) -> i64, bsearch: proc "contextless" (^A, V, bool) -> i64) {
	x, y := godot.from_variant(A, a), godot.from_variant(V, v)
	put_basis_result(o, size(&x))
	put_basis_result(o, empty(&x))
	g := get(&x, index)
	when G == godot.String {
		put_basis_result(o, godot.string_hash(&g))
		godot.destroy[.STRING](&g)
	} else when G == godot.Color {
		put_basis_result(o, godot.Vector4(g))
	} else {
		put_basis_result(o, g)
	}
	put_basis_result(o, has(&x, y))
	put_basis_result(o, find(&x, y, from))
	put_basis_result(o, rfind(&x, y, from))
	put_basis_result(o, count(&x, y))
	put_basis_result(o, bsearch(&x, y, before))
}

// The Color String procs and from_ok_hsl, then the RID procs, in the order _color_text_results
// in test.gd calls the engine's: a String by its length and then its characters.
bag_replaced_color_texts :: proc(self: ^Bag, a: godot.Color, s: godot.String, d: godot.Color, x, h, sat, l: f64, r: godot.RID) -> godot.PackedInt64Array {
	o: Color_Results
	a, r := a, r
	for alpha in ([2]bool{false, true}) {
		t := godot.color_to_html(&a, alpha)
		defer godot.destroy[.STRING](&t)
		chars := godot.string_read(&t)
		put_color_result(&o, len(chars))
		for c in chars { put_color_result(&o, c) }
	}
	put_color_result(&o, godot.color_html(s))
	put_color_result(&o, godot.color_html_is_valid(s))
	put_color_result(&o, godot.color_from_string(s, d))
	put_color_result(&o, godot.color_new_from_string(s))
	put_color_result(&o, godot.color_new_from_string_float(s, x))
	put_color_result(&o, godot.color_from_ok_hsl(h, sat, l, x))
	put_color_result(&o, godot.rid_is_valid(&r))
	put_color_result(&o, godot.rid_get_id(&r))
	empty, copied := godot.rid_new(), godot.rid_new_from_rid(r)
	put_color_result(&o, godot.rid_is_valid(&empty))
	put_color_result(&o, godot.rid_get_id(&empty))
	put_color_result(&o, godot.rid_get_id(&copied))
	return godot.packed_of_int64(o.v[:o.n])
}

// Integers gathered for bag_replaced_bases and the transform bags, in call order.
Basis_Results :: struct {
	v: [512]i64,
	n: int,
}

// Appends `v` to `o` as integers: floats by their bits with NaNs made one quiet NaN, a Basis by
// its columns (the axes GDScript indexes), a transform by its basis columns and then its origin,
// a Projection by its columns, a vector or quaternion by component, an AABB or Rect2 or Rect2i by position and then size, a Plane by its normal and then its distance as a double.
put_basis_result :: proc(o: ^Basis_Results, v: $T) {
	when T == godot.Basis {
		for c in 0 ..< 3 { put_basis_result(o, godot.Vector3{v.x[c], v.y[c], v.z[c]}) }
	} else when T == godot.Transform3D {
		put_basis_result(o, v.basis)
		put_basis_result(o, v.origin)
	} else when T == godot.Transform2D {
		for e in ([3]godot.Vector2{v.x, v.y, v.origin}) { put_basis_result(o, e) }
	} else when T == godot.AABB || T == godot.Rect2 || T == godot.Rect2i {
		put_basis_result(o, v.position)
		put_basis_result(o, v.size)
	} else when T == godot.Plane {
		put_basis_result(o, v.normal)
		put_basis_result(o, f64(v.d))
	} else when T == godot.Variant {
		// An intersection result: its type tag, then the Vector3 it holds, if any.
		v := v
		put_basis_result(o, i64(godot.variant_tag(&v)))
		if godot.variant_tag(&v) == .VECTOR3 { put_basis_result(o, (^godot.Vector3)(&v._opaque[8])^) }
	} else when T == godot.Projection {
		for e in ([4]godot.Vector4{v.x, v.y, v.z, v.w}) { put_basis_result(o, e) }
	} else when T == godot.Vector2 || T == godot.Vector3 || T == godot.Vector4 || T == godot.Quaternion || T == godot.Vector2i {
		for e in v { put_basis_result(o, e) }
	} else when T == f32 {
		put_basis_result(o, i64(0x7fc00000) if v != v else i64(transmute(u32)v))
	} else when T == f64 {
		put_basis_result(o, i64(0x7ff8000000000000) if v != v else transmute(i64)v)
	} else when T == i32 {
		put_basis_result(o, i64(v))
	} else when T == bool {
		put_basis_result(o, i64(1 if v else 0))
	} else {
		o.v[o.n] = v
		o.n += 1
	}
}

// The Basis procs that replace engine methods (godot/basis.odin) on `a` and `b`, with `v` and `w`
// the vector arguments, `x` the angle or weight and `n` the Euler order. test.gd's
// _basis_results calls the engine's own methods in the same order.
bag_replaced_bases :: proc(self: ^Bag, a, b: godot.Basis, v, w: godot.Vector3, x: f64, n: i64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.basis_new())
	put_basis_result(&o, godot.basis_new_from_basis(a))
	put_basis_result(&o, godot.basis_new_from_quaternion(godot.Quaternion{v.x, v.y, v.z, f32(x)}))
	put_basis_result(&o, godot.basis_new_from_vector3_float(v, x))
	put_basis_result(&o, godot.basis_new_from_vector3_vector3_vector3(w, v, w))
	put_basis_result(&o, godot.basis_inverse(&a))
	put_basis_result(&o, godot.basis_transposed(&a))
	put_basis_result(&o, godot.basis_orthonormalized(&a))
	put_basis_result(&o, godot.basis_determinant(&a))
	put_basis_result(&o, godot.basis_rotated(&a, v, x))
	put_basis_result(&o, godot.basis_scaled(&a, v))
	put_basis_result(&o, godot.basis_scaled_local(&a, v))
	put_basis_result(&o, godot.basis_get_scale(&a))
	put_basis_result(&o, godot.basis_get_euler(&a, n))
	for k in i64(0) ..< 6 { put_basis_result(&o, godot.basis_get_euler(&a, k)) }
	put_basis_result(&o, godot.basis_tdotx(&a, v))
	put_basis_result(&o, godot.basis_tdoty(&a, v))
	put_basis_result(&o, godot.basis_tdotz(&a, v))
	put_basis_result(&o, godot.basis_slerp(&a, b, x))
	put_basis_result(&o, godot.basis_is_conformal(&a))
	put_basis_result(&o, godot.basis_is_equal_approx(&a, b))
	put_basis_result(&o, godot.basis_is_finite(&a))
	put_basis_result(&o, godot.basis_is_orthonormal(&a))
	put_basis_result(&o, godot.basis_get_rotation_quaternion(&a))
	put_basis_result(&o, godot.basis_looking_at(v, w, false))
	put_basis_result(&o, godot.basis_looking_at(v, w, true))
	put_basis_result(&o, godot.basis_from_scale(v))
	put_basis_result(&o, godot.basis_from_euler(v, n))
	for k in i64(0) ..< 6 { put_basis_result(&o, godot.basis_from_euler(v, k)) }
	return godot.packed_of_int64(o.v[:o.n])
}

// The Transform2D procs that replace engine methods (godot/transform.odin) on `a` and `b`, with
// `p` and `q` the vector arguments, `x` the angle or weight and `y` the skew. test.gd's
// _transform2d_results calls the engine's own methods in the same order.
bag_replaced_transforms2d :: proc(self: ^Bag, a, b: godot.Transform2D, p, q: godot.Vector2, x, y: f64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.transform2d_new())
	put_basis_result(&o, godot.transform2d_new_from_transform2d(a))
	put_basis_result(&o, godot.transform2d_new_from_float_vector2(x, p))
	put_basis_result(&o, godot.transform2d_new_from_float_vector2_float_vector2(x, p, y, q))
	put_basis_result(&o, godot.transform2d_new_from_vector2_vector2_vector2(p, q, p))
	put_basis_result(&o, godot.transform2d_inverse(&a))
	put_basis_result(&o, godot.transform2d_affine_inverse(&a))
	put_basis_result(&o, godot.transform2d_get_rotation(&a))
	put_basis_result(&o, godot.transform2d_get_origin(&a))
	put_basis_result(&o, godot.transform2d_get_scale(&a))
	put_basis_result(&o, godot.transform2d_get_skew(&a))
	put_basis_result(&o, godot.transform2d_orthonormalized(&a))
	put_basis_result(&o, godot.transform2d_rotated(&a, x))
	put_basis_result(&o, godot.transform2d_rotated_local(&a, x))
	put_basis_result(&o, godot.transform2d_scaled(&a, p))
	put_basis_result(&o, godot.transform2d_scaled_local(&a, p))
	put_basis_result(&o, godot.transform2d_translated(&a, p))
	put_basis_result(&o, godot.transform2d_translated_local(&a, p))
	put_basis_result(&o, godot.transform2d_determinant(&a))
	put_basis_result(&o, godot.transform2d_basis_xform(&a, p))
	put_basis_result(&o, godot.transform2d_basis_xform_inv(&a, p))
	put_basis_result(&o, godot.transform2d_interpolate_with(&a, b, x))
	put_basis_result(&o, godot.transform2d_is_conformal(&a))
	put_basis_result(&o, godot.transform2d_is_equal_approx(&a, b))
	put_basis_result(&o, godot.transform2d_is_finite(&a))
	put_basis_result(&o, godot.transform2d_looking_at(&a, p))
	return godot.packed_of_int64(o.v[:o.n])
}

// The Transform3D procs that replace engine methods (godot/transform.odin) on `a` and `b`, with
// `v` and `w` the vector arguments, `m` the projection and `x` the angle or weight. test.gd's
// _transform3d_results calls the engine's own methods in the same order.
bag_replaced_transforms3d :: proc(self: ^Bag, a, b: godot.Transform3D, v, w: godot.Vector3, m: godot.Projection, x: f64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.transform3d_new())
	put_basis_result(&o, godot.transform3d_new_from_transform3d(a))
	put_basis_result(&o, godot.transform3d_new_from_basis_vector3(b.basis, v))
	put_basis_result(&o, godot.transform3d_new_from_vector3_vector3_vector3_vector3(v, w, a.origin, b.origin))
	put_basis_result(&o, godot.transform3d_new_from_projection(m))
	put_basis_result(&o, godot.transform3d_inverse(&a))
	put_basis_result(&o, godot.transform3d_affine_inverse(&a))
	put_basis_result(&o, godot.transform3d_orthonormalized(&a))
	put_basis_result(&o, godot.transform3d_rotated(&a, v, x))
	put_basis_result(&o, godot.transform3d_rotated_local(&a, v, x))
	put_basis_result(&o, godot.transform3d_scaled(&a, v))
	put_basis_result(&o, godot.transform3d_scaled_local(&a, v))
	put_basis_result(&o, godot.transform3d_translated(&a, v))
	put_basis_result(&o, godot.transform3d_translated_local(&a, v))
	put_basis_result(&o, godot.transform3d_looking_at(&a, v, w, false))
	put_basis_result(&o, godot.transform3d_looking_at(&a, v, w, true))
	put_basis_result(&o, godot.transform3d_interpolate_with(&a, b, x))
	put_basis_result(&o, godot.transform3d_is_equal_approx(&a, b))
	put_basis_result(&o, godot.transform3d_is_finite(&a))
	return godot.packed_of_int64(o.v[:o.n])
}

// The Quaternion procs that replace engine methods (godot/quaternion.odin) on `a` and `b`, with
// `c` and `d` the cubic's pre and post quaternions, `m` the basis to convert, `v` and `w` the
// vector arguments (`w` also the cubic's three times), `x` the angle or weight and `n` the Euler
// order. test.gd's _quaternion_results calls the engine's own methods in the same order.
bag_replaced_quaternions :: proc(self: ^Bag, a, b, c, d: godot.Quaternion, m: godot.Basis, v, w: godot.Vector3, x: f64, n: i64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.quaternion_new())
	put_basis_result(&o, godot.quaternion_new_from_quaternion(a))
	put_basis_result(&o, godot.quaternion_new_from_basis(m))
	put_basis_result(&o, godot.quaternion_new_from_vector3_float(v, x))
	put_basis_result(&o, godot.quaternion_new_from_vector3_vector3(v, w))
	put_basis_result(&o, godot.quaternion_new_from_float_float_float_float(x, f64(v.x), f64(v.y), f64(v.z)))
	put_basis_result(&o, godot.quaternion_length(&a))
	put_basis_result(&o, godot.quaternion_length_squared(&a))
	put_basis_result(&o, godot.quaternion_normalized(&a))
	put_basis_result(&o, godot.quaternion_is_normalized(&a))
	put_basis_result(&o, godot.quaternion_is_equal_approx(&a, b))
	put_basis_result(&o, godot.quaternion_is_finite(&a))
	put_basis_result(&o, godot.quaternion_inverse(&a))
	put_basis_result(&o, godot.quaternion_log(&a))
	put_basis_result(&o, godot.quaternion_exp(&a))
	put_basis_result(&o, godot.quaternion_angle_to(&a, b))
	put_basis_result(&o, godot.quaternion_dot(&a, b))
	put_basis_result(&o, godot.quaternion_slerp(&a, b, x))
	put_basis_result(&o, godot.quaternion_slerpni(&a, b, x))
	put_basis_result(&o, godot.quaternion_spherical_cubic_interpolate(&a, b, c, d, x))
	put_basis_result(&o, godot.quaternion_spherical_cubic_interpolate_in_time(&a, b, c, d, x, f64(w.x), f64(w.y), f64(w.z)))
	put_basis_result(&o, godot.quaternion_get_euler(&a, n))
	for k in i64(0) ..< 6 { put_basis_result(&o, godot.quaternion_get_euler(&a, k)) }
	put_basis_result(&o, godot.quaternion_from_euler(v))
	put_basis_result(&o, godot.quaternion_get_axis(&a))
	put_basis_result(&o, godot.quaternion_get_angle(&a))
	return godot.packed_of_int64(o.v[:o.n])
}

// The Plane procs that replace engine methods (godot/plane.odin) on `a`, with `b` and `c` the
// other planes, `v`, `w` and `u` the vector arguments and `x` the distance or tolerance. test.gd's
// _plane_results calls the engine's own methods in the same order.
bag_replaced_planes :: proc(self: ^Bag, a, b, c: godot.Plane, v, w, u: godot.Vector3, x: f64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.plane_new())
	put_basis_result(&o, godot.plane_new_from_plane(a))
	put_basis_result(&o, godot.plane_new_from_vector3(v))
	put_basis_result(&o, godot.plane_new_from_vector3_float(v, x))
	put_basis_result(&o, godot.plane_new_from_vector3_vector3(v, w))
	put_basis_result(&o, godot.plane_new_from_vector3_vector3_vector3(v, w, u))
	put_basis_result(&o, godot.plane_new_from_float_float_float_float(x, f64(v.x), f64(v.y), f64(v.z)))
	put_basis_result(&o, godot.plane_normalized(&a))
	put_basis_result(&o, godot.plane_get_center(&a))
	put_basis_result(&o, godot.plane_is_equal_approx(&a, b))
	put_basis_result(&o, godot.plane_is_finite(&a))
	put_basis_result(&o, godot.plane_is_point_over(&a, v))
	put_basis_result(&o, godot.plane_distance_to(&a, v))
	put_basis_result(&o, godot.plane_has_point(&a, v, x))
	put_basis_result(&o, godot.plane_has_point(&a, v, 1e-05))
	put_basis_result(&o, godot.plane_project(&a, v))
	put_basis_result(&o, godot.plane_intersect_3(&a, b, c))
	put_basis_result(&o, godot.plane_intersects_ray(&a, v, w))
	put_basis_result(&o, godot.plane_intersects_segment(&a, v, w))
	return godot.packed_of_int64(o.v[:o.n])
}

// The AABB procs that replace engine methods (godot/aabb.odin) on `a` and `b`, with `p` the plane,
// `v` and `w` the vector arguments, `x` the growth and `n` the endpoint index. test.gd's
// _aabb_results calls the engine's own methods in the same order.
bag_replaced_aabbs :: proc(self: ^Bag, a, b: godot.AABB, p: godot.Plane, v, w: godot.Vector3, x: f64, n: i64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.aabb_new())
	put_basis_result(&o, godot.aabb_new_from_aabb(a))
	put_basis_result(&o, godot.aabb_new_from_vector3_vector3(v, w))
	put_basis_result(&o, godot.aabb_abs(&a))
	put_basis_result(&o, godot.aabb_get_center(&a))
	put_basis_result(&o, godot.aabb_get_volume(&a))
	put_basis_result(&o, godot.aabb_has_volume(&a))
	put_basis_result(&o, godot.aabb_has_surface(&a))
	put_basis_result(&o, godot.aabb_has_point(&a, v))
	put_basis_result(&o, godot.aabb_is_equal_approx(&a, b))
	put_basis_result(&o, godot.aabb_is_finite(&a))
	put_basis_result(&o, godot.aabb_intersects(&a, b))
	put_basis_result(&o, godot.aabb_encloses(&a, b))
	put_basis_result(&o, godot.aabb_intersects_plane(&a, p))
	put_basis_result(&o, godot.aabb_intersection(&a, b))
	put_basis_result(&o, godot.aabb_merge(&a, b))
	put_basis_result(&o, godot.aabb_expand(&a, v))
	put_basis_result(&o, godot.aabb_grow(&a, x))
	put_basis_result(&o, godot.aabb_get_support(&a, w))
	put_basis_result(&o, godot.aabb_get_longest_axis(&a))
	put_basis_result(&o, godot.aabb_get_longest_axis_index(&a))
	put_basis_result(&o, godot.aabb_get_longest_axis_size(&a))
	put_basis_result(&o, godot.aabb_get_shortest_axis(&a))
	put_basis_result(&o, godot.aabb_get_shortest_axis_index(&a))
	put_basis_result(&o, godot.aabb_get_shortest_axis_size(&a))
	put_basis_result(&o, godot.aabb_get_endpoint(&a, n))
	put_basis_result(&o, godot.aabb_intersects_segment(&a, v, w))
	put_basis_result(&o, godot.aabb_intersects_ray(&a, v, w))
	return godot.packed_of_int64(o.v[:o.n])
}

// The Rect2 procs that replace engine methods (godot/rect2.odin) on `a` and `b`, with `c` the
// Rect2i to convert, `v` and `w` the vector arguments, `x` the growth and `n` the side. test.gd's
// _rect2_results calls the engine's own methods in the same order.
bag_replaced_rect2s :: proc(self: ^Bag, a, b: godot.Rect2, c: godot.Rect2i, v, w: godot.Vector2, x: f64, n: i64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.rect2_new())
	put_basis_result(&o, godot.rect2_new_from_rect2(a))
	put_basis_result(&o, godot.rect2_new_from_rect2i(c))
	put_basis_result(&o, godot.rect2_new_from_vector2_vector2(v, w))
	put_basis_result(&o, godot.rect2_new_from_float_float_float_float(x, f64(v.x), f64(w.y), -x))
	put_basis_result(&o, godot.rect2_get_center(&a))
	put_basis_result(&o, godot.rect2_get_area(&a))
	put_basis_result(&o, godot.rect2_has_area(&a))
	put_basis_result(&o, godot.rect2_has_point(&a, v))
	put_basis_result(&o, godot.rect2_is_equal_approx(&a, b))
	put_basis_result(&o, godot.rect2_is_finite(&a))
	put_basis_result(&o, godot.rect2_intersects(&a, b, false))
	put_basis_result(&o, godot.rect2_intersects(&a, b, true))
	put_basis_result(&o, godot.rect2_encloses(&a, b))
	put_basis_result(&o, godot.rect2_intersection(&a, b))
	put_basis_result(&o, godot.rect2_merge(&a, b))
	put_basis_result(&o, godot.rect2_expand(&a, v))
	put_basis_result(&o, godot.rect2_get_support(&a, w))
	put_basis_result(&o, godot.rect2_grow(&a, x))
	put_basis_result(&o, godot.rect2_grow_side(&a, n, x))
	put_basis_result(&o, godot.rect2_grow_individual(&a, x, f64(v.x), f64(w.y), -x))
	put_basis_result(&o, godot.rect2_abs(&a))
	put_basis_result(&o, godot.rect2i_new_from_rect2(a))
	return godot.packed_of_int64(o.v[:o.n])
}

// The Rect2i procs that replace engine methods (godot/rect2.odin) on `a` and `b`, with `v` and `w`
// the vector arguments, `n` the side and `m` the growth. test.gd's _rect2i_results calls the
// engine's own methods in the same order.
bag_replaced_rect2is :: proc(self: ^Bag, a, b: godot.Rect2i, v, w: godot.Vector2i, n, m: i64) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	put_basis_result(&o, godot.rect2i_new())
	put_basis_result(&o, godot.rect2i_new_from_rect2i(a))
	put_basis_result(&o, godot.rect2i_new_from_vector2i_vector2i(v, w))
	put_basis_result(&o, godot.rect2i_new_from_int_int_int_int(m, i64(v.x), i64(w.y), -m))
	put_basis_result(&o, godot.rect2i_get_center(&a))
	put_basis_result(&o, godot.rect2i_get_area(&a))
	put_basis_result(&o, godot.rect2i_has_area(&a))
	put_basis_result(&o, godot.rect2i_has_point(&a, v))
	put_basis_result(&o, godot.rect2i_intersects(&a, b))
	put_basis_result(&o, godot.rect2i_encloses(&a, b))
	put_basis_result(&o, godot.rect2i_intersection(&a, b))
	put_basis_result(&o, godot.rect2i_merge(&a, b))
	put_basis_result(&o, godot.rect2i_expand(&a, v))
	put_basis_result(&o, godot.rect2i_grow(&a, m))
	put_basis_result(&o, godot.rect2i_grow_side(&a, n, m))
	put_basis_result(&o, godot.rect2i_grow_individual(&a, m, i64(v.x), i64(w.y), -m))
	put_basis_result(&o, godot.rect2i_abs(&a))
	return godot.packed_of_int64(o.v[:o.n])
}

// Each Projection proc that replaces an engine method, in the order test.gd calls the engine's.
bag_replaced_projections :: proc(self: ^Bag, a: godot.Projection, t: godot.Transform3D, r: godot.Rect2, box: godot.AABB, w, q: godot.Vector2, x, y, z, u: f64, n, m: i64, flip: bool) -> godot.PackedInt64Array {
	o: Basis_Results
	a := a
	wx, wy, qx, qy := f64(w.x), f64(w.y), f64(q.x), f64(q.y)
	put_basis_result(&o, godot.projection_new())
	put_basis_result(&o, godot.projection_new_from_projection(a))
	put_basis_result(&o, godot.projection_new_from_transform3d(t))
	put_basis_result(&o, godot.projection_new_from_vector4_vector4_vector4_vector4(a.w, a.z, a.y, a.x))
	put_basis_result(&o, godot.projection_create_depth_correction(flip))
	put_basis_result(&o, godot.projection_create_light_atlas_rect(r))
	put_basis_result(&o, godot.projection_create_perspective(x, y, z, u, flip))
	put_basis_result(&o, godot.projection_create_perspective_hmd(x, y, z, u, flip, n, wx, wy))
	put_basis_result(&o, godot.projection_create_for_hmd(n, y, wx, qx, qy, x, z, u))
	put_basis_result(&o, godot.projection_create_orthogonal(wx, qx, wy, qy, z, u))
	put_basis_result(&o, godot.projection_create_orthogonal_aspect(x, y, z, u, flip))
	put_basis_result(&o, godot.projection_create_frustum(wx, qx, wy, qy, z, u))
	put_basis_result(&o, godot.projection_create_frustum_aspect(x, y, w, z, u, flip))
	put_basis_result(&o, godot.projection_create_fit_aabb(box))
	put_basis_result(&o, godot.projection_get_fovy(x, y))
	put_basis_result(&o, godot.projection_determinant(&a))
	put_basis_result(&o, godot.projection_perspective_znear_adjusted(&a, z))
	put_basis_result(&o, godot.projection_get_projection_plane(&a, n))
	put_basis_result(&o, godot.projection_flipped_y(&a))
	put_basis_result(&o, godot.projection_jitter_offseted(&a, w))
	put_basis_result(&o, godot.projection_get_z_far(&a))
	put_basis_result(&o, godot.projection_get_z_near(&a))
	put_basis_result(&o, godot.projection_get_aspect(&a))
	put_basis_result(&o, godot.projection_get_fov(&a))
	put_basis_result(&o, godot.projection_is_orthogonal(&a))
	put_basis_result(&o, godot.projection_get_viewport_half_extents(&a))
	put_basis_result(&o, godot.projection_get_far_plane_half_extents(&a))
	put_basis_result(&o, godot.projection_inverse(&a))
	put_basis_result(&o, godot.projection_get_pixels_per_meter(&a, m))
	put_basis_result(&o, godot.projection_get_lod_multiplier(&a))
	return godot.packed_of_int64(o.v[:o.n])
}
