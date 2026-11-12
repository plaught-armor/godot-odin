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
	// ASCII is the same in Latin-1, and the engine copies Latin-1 without decoding it.
	if is_ascii(s) {
		gde.string_new_with_latin1_chars_and_len(&out, cstring(raw_data(s)), gde.Int(len(s)))
	} else {
		gde.string_new_with_utf8_chars_and_len(&out, cstring(raw_data(s)), gde.Int(len(s)))
	}
	return
}

// A StringName for `s`, any text, which the caller destroys. For a name used again and again,
// `intern` costs about 1 ns a call after the first.
name_of :: proc "contextless" (s: string) -> (out: StringName) {
	// The engine hashes short ASCII text straight from a C string, where UTF-8 text first becomes
	// a String: about half the time. The C string needs a terminator, so it is copied.
	SHORT :: 128
	if len(s) < SHORT && is_ascii(s) {
		buf: [SHORT]u8 = ---
		copy(buf[:], s)
		buf[len(s)] = 0
		gde.string_name_new_with_latin1_chars(&out, cstring(&buf[0]), 0)
	} else {
		gde.string_name_new_with_utf8_chars_and_len(&out, cstring(raw_data(s)), gde.Int(len(s)))
	}
	return
}

// True when `s` is all ASCII, with no NUL byte to cut a C string short.
@(private)
is_ascii :: proc "contextless" (s: string) -> bool {
	for c in transmute([]u8)s {
		if c == 0 || c >= 0x80 { return false }
	}
	return true
}

// The StringName for the constant `text`, made on the first call and kept for the life of the
// process; each later call is one load, about 1 ns against 40 ns for `name_of`. Do not destroy it.
// Safe from any thread: racing first calls keep one name and drop the others.
intern :: #force_inline proc "contextless" ($text: string) -> StringName {
	@(static) cache: u64
	bits := intrinsics.atomic_load_explicit(&cache, .Acquire)
	if bits == 0 {
		made := name_of(text)
		stored: bool
		bits, stored = intern_store(&cache, transmute(u64)made)
		if !stored { destroy[.STRING_NAME](&made) }
	}
	return transmute(StringName)bits
}

// The NodePath for the constant `text`, such as "Body/Sprite", made on the first call and kept
// like `intern`'s names: about 1 ns a call after that, against 130 ns for `path_of`. Do not
// destroy it. Safe from any thread.
intern_path :: #force_inline proc "contextless" ($text: string) -> NodePath {
	@(static) cache: u64
	bits := intrinsics.atomic_load_explicit(&cache, .Acquire)
	if bits == 0 {
		made := path_of(text)
		stored: bool
		bits, stored = intern_store(&cache, transmute(u64)made)
		if !stored { destroy[.NODE_PATH](&made) }
	}
	return transmute(NodePath)bits
}

// The String for the constant `text`, such as "Score", made on the first call and kept like
// `intern`'s names: pass it to any engine call that takes a String, at about the cost of a load
// after the first call. Do not destroy it. Safe from any thread.
intern_text :: #force_inline proc "contextless" ($text: string) -> String {
	@(static) cache: u64
	bits := intrinsics.atomic_load_explicit(&cache, .Acquire)
	if bits == 0 {
		made := string_of(text)
		stored: bool
		bits, stored = intern_store(&cache, transmute(u64)made)
		if !stored { destroy[.STRING](&made) }
	}
	return transmute(String)bits
}

// A String for Odin `text` that lives until the call from the engine it was made in returns, for
// text built at run time: pass it to engine calls that take a String, and never destroy it. Only
// inside a call from the engine (a method, virtual, notification or callable), on the main thread.
temp_text :: proc "contextless" (text: string) -> String {
	context = ctx
	depth := temp_arena.temp_count
	assert(depth > 0, "godot_odin: temp_text outside a call from the engine")
	when ODIN_DEBUG {
		assert(on_main_thread, "godot_odin: temp_text off the main thread; its list is the main thread's")
	}
	// Kept off the temp arena, so a temp guard of the caller's own cannot free a record still
	// listed: the String outlives such a guard, to the end of the engine call.
	append(&temp_texts, Temp_Text{text = string_of(text), depth = depth})
	return temp_texts[len(temp_texts) - 1].text
}

// How many `temp_text` Strings are alive now: 0 once every call from the engine has returned. For
// debug lanes that prove a call drops its own.
temp_texts_live :: proc "contextless" () -> int {
	return len(temp_texts)
}

// One `temp_text` String and the temp arena depth it was made at.
@(private)
Temp_Text :: struct {
	text:  String,
	depth: uint,
}

// The live `temp_text` Strings, oldest first: a call's own are at the end. While any is live,
// `leave` goes to `roll_back`, which drops them.
@(private)
temp_texts: [dynamic]Temp_Text

// Destroys the `temp_text` Strings made at temp arena depth `depth` or deeper: those of the call
// now returning and of any it made.
@(private)
drop_temp_texts :: proc "contextless" (depth: uint) {
	// Each pass drops one, so the list's length bounds the loop.
	for _ in 0 ..< len(temp_texts) {
		last := len(temp_texts) - 1
		if temp_texts[last].depth < depth { return }
		destroy[.STRING](&temp_texts[last].text)
		(^runtime.Raw_Dynamic_Array)(&temp_texts).len = last
	}
}

// Stores `made`, a new StringName or NodePath as its one pointer word, in the empty `cache`.
// False when another thread stored one first: the caller drops `made` and uses the stored word.
// An empty name or path is the null word, made again on each call, and holds nothing to drop.
@(private)
intern_store :: proc "contextless" (cache: ^u64, made: u64) -> (bits: u64, stored: bool) {
	#assert(size_of(StringName) == size_of(u64) && size_of(NodePath) == size_of(u64))
	old, ok := intrinsics.atomic_compare_exchange_strong_explicit(cache, 0, made, .Acq_Rel, .Acquire)
	if ok { return made, true }
	return old, false
}

// A NodePath for `s`, such as "Body/Sprite" or "Body:position", which the caller destroys.
path_of :: proc "contextless" (s: string) -> NodePath {
	str := string_of(s)
	defer destroy[.STRING](&str)
	return node_path_new_from_string(str)
}

// A String, StringName or NodePath as UTF-8 in a new Odin string from `allocator`, which the
// caller deletes.
utf8 :: proc{utf8_string, utf8_name, utf8_path}

utf8_name :: proc(s: StringName, allocator := context.allocator) -> string {
	t := string_new_from_string_name(s)
	defer destroy[.STRING](&t)
	return utf8_string(t, allocator)
}

utf8_path :: proc(s: NodePath, allocator := context.allocator) -> string {
	t := string_new_from_node_path(s)
	defer destroy[.STRING](&t)
	return utf8_string(t, allocator)
}

utf8_string :: proc(s: String, allocator := context.allocator) -> string {
	// Encoded here from the characters read in place: the engine's own encoder takes two calls,
	// one to measure and one to write, about 47 ns for a short name.
	t := s
	chars := string_read(&t)
	n := 0
	for r in chars {
		switch {
		case r < 0x80: n += 1
		case r < 0x800: n += 2
		case r >= 0xd800 && r < 0xe000, r > 0x10ffff: return utf8_engine(s, allocator)
		case r < 0x10000: n += 3
		case: n += 4
		}
	}
	// Every byte is written below, so the buffer need not be zeroed first.
	buf, err := runtime.mem_alloc_non_zeroed(n, 1, allocator)
	if err != nil || len(buf) < n { return "" }
	i := 0
	for r in chars {
		c := u32(r)
		switch {
		case c < 0x80:
			buf[i] = u8(c)
			i += 1
		case c < 0x800:
			buf[i] = u8(0xc0 | c >> 6)
			buf[i + 1] = u8(0x80 | c & 0x3f)
			i += 2
		case c < 0x10000:
			buf[i] = u8(0xe0 | c >> 12)
			buf[i + 1] = u8(0x80 | (c >> 6) & 0x3f)
			buf[i + 2] = u8(0x80 | c & 0x3f)
			i += 3
		case:
			buf[i] = u8(0xf0 | c >> 18)
			buf[i + 1] = u8(0x80 | (c >> 12) & 0x3f)
			buf[i + 2] = u8(0x80 | (c >> 6) & 0x3f)
			buf[i + 3] = u8(0x80 | c & 0x3f)
			i += 4
		}
	}
	return string(buf)
}

// `utf8` by the engine's encoder, for a String holding a surrogate or a value past U+10FFFF,
// which the engine encodes its own way.
@(private)
utf8_engine :: proc(s: String, allocator := context.allocator) -> string {
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

// The node at `path` from `node`, as `get_node_or_null` finds it. Pass an engine class `T` to get
// it as that class, or a registered class `c` to get its struct; either is nil when there is no
// node there or it is not of that class. `node` is any engine Node, or `object_of(self)`. The path
// is Odin text, parsed on each call (about 130 ns), or a NodePath such as `intern_path("Body")`.
get_node :: proc{get_node_as, get_node_instance, get_node_path_as, get_node_path_instance}

@(private)
get_node_as :: proc(node: $N, path: string, $T: typeid) -> T where intrinsics.type_base_type(N) == rawptr && intrinsics.type_base_type(T) == rawptr {
	return cast_to(node_at(rawptr(node), path), T)
}

@(private)
get_node_instance :: proc "contextless" (node: $N, path: string, c: ^Class($T)) -> ^T where intrinsics.type_base_type(N) == rawptr {
	return instance_of(node_at(rawptr(node), path), c)
}

@(private)
get_node_path_as :: proc(node: $N, path: NodePath, $T: typeid) -> T where intrinsics.type_base_type(N) == rawptr && intrinsics.type_base_type(T) == rawptr {
	return cast_to(node_at_path(rawptr(node), path), T)
}

@(private)
get_node_path_instance :: proc "contextless" (node: $N, path: NodePath, c: ^Class($T)) -> ^T where intrinsics.type_base_type(N) == rawptr {
	return instance_of(node_at_path(rawptr(node), path), c)
}

@(private)
node_at :: proc "contextless" (node: rawptr, path: string) -> Node {
	if node == nil { return nil }
	p := path_of(path)
	defer destroy[.NODE_PATH](&p)
	return node_get_node_or_null(Node(node), p)
}

@(private)
node_at_path :: proc "contextless" (node: rawptr, path: NodePath) -> Node {
	if node == nil { return nil }
	return node_get_node_or_null(Node(node), path)
}

// The resource at `path`, such as "res://icon.png", loaded as GDScript's `load` does: from the
// engine's cache when it is there. Pass an engine class `T` to get it as that class, or a
// registered class `c` to get its struct; either is nil when the load fails or the resource is not
// of that class. You own one reference: `release` it, or `release(object_of(r))` for a struct.
load :: proc{load_as, load_instance}

@(private)
load_as :: proc(path: string, $T: typeid) -> T where intrinsics.type_base_type(T) == rawptr {
	res := load_resource(path)
	out := cast_to(res, T)
	if out == nil { release(res) }
	return out
}

@(private)
load_instance :: proc "contextless" (path: string, c: ^Class($T)) -> ^T {
	res := load_resource(path)
	out := instance_of(res, c)
	if out == nil { release(res) }
	return out
}

@(private)
load_resource :: proc "contextless" (path: string) -> Resource {
	p := string_of(path)
	defer destroy[.STRING](&p)
	hint: String
	return resource_loader_load(resource_loader_singleton(), p, hint, .CACHE_MODE_REUSE)
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
	if variant_tag(&v) != .STRING_NAME { return }
	to_type[.STRING_NAME](&out, &v)
	return
}

// True only on the thread `entry` ran on, the engine's main thread; debug builds assert every call
// arrives on it.
@(thread_local)
on_main_thread: bool

// True while this thread runs a `run_task` or `run_group` proc. Set in debug builds only, where
// `enter` stops on it: a worker task must not call into an Odin class.
@(thread_local)
in_task: bool

// Opens a call from the engine, after `context = ctx`. Marks this library's temp arena, `temp_arena`; the deferred
// `leave` rolls it back at scope exit, so the call frees the temp it took and nothing older. Debug
// builds assert the call is on the main thread.
@(deferred_out = leave)
enter :: #force_inline proc(loc := #caller_location) -> runtime.Arena_Temp {
	when ODIN_DEBUG {
		assert(!in_task, "godot_odin: a run_task or run_group proc called into an Odin class, which worker tasks must not do", loc)
		assert(on_main_thread, "godot_odin: an engine call off the main thread", loc)
	}
	// `runtime.arena_temp_begin`, inline: it is a call, on every call from the engine.
	a := temp_arena
	temp := runtime.Arena_Temp{arena = a, block = a.curr_block}
	if a.curr_block != nil { temp.used = a.curr_block.used }
	a.temp_count += 1
	return temp
}

// The arena behind `ctx.temp_allocator`, the main thread's, which `entry` sets. `enter` marks it
// directly: the runtime's own temp_begin finds it through a thread-local lookup, a `__tls_get_addr`
// call per engine call in a shared library.
temp_arena: ^runtime.Arena

// Rolls the temp arena back to `temp`, the mark `enter` took. Most calls take no temp, and then
// only the mark's count changes: the runtime's rollback, which is a call, runs when there is
// something to roll back or a `temp_text` String to drop.
leave :: #force_inline proc(temp: runtime.Arena_Temp) {
	a := temp.arena
	if a.curr_block == temp.block && (temp.block == nil || temp.block.used == temp.used) && len(temp_texts) == 0 {
		when ODIN_DEBUG {
			assert(a.temp_count > 0, "godot_odin: leave without enter")
		}
		a.temp_count -= 1
		return
	}
	roll_back(temp)
}

// The runtime's rollback, in a call of its own that sets `ctx`: inline in `leave`, it would make
// every engine call keep its copy of the context alive for it, even one whose proc never reads it.
@(private)
roll_back :: #force_no_inline proc "contextless" (temp: runtime.Arena_Temp) {
	context = ctx
	// A call that took temp, or made a `temp_text`, gets here.
	if len(temp_texts) > 0 { drop_temp_texts(temp.arena.temp_count) }
	runtime.default_temp_allocator_temp_end(temp)
}

// Bytes the temp arena of `ctx`, the context every engine call runs in, holds now. For debug lanes
// that prove a call frees its temp use.
temp_used :: proc "contextless" () -> i64 {
	// The sum over the arena's live blocks. The arena's own `total_used` keeps counting a block it
	// frees on rollback, so it only grows after a take that needed a new block.
	MAX_BLOCKS :: 1 << 16
	n: uint
	block := (^runtime.Default_Temp_Allocator)(ctx.temp_allocator.data).arena.curr_block
	for _ in 0 ..< MAX_BLOCKS {
		if block == nil { break }
		n += block.used
		block = block.prev
	}
	return i64(n)
}

// Prints a formatted line to the engine's output, as GDScript's `print` does: stdout and the
// editor's Output panel. `fmt.println` reaches stdout only.
print :: proc(format: string, args: ..any) {
	s := string_of(fmt.tprintf(format, ..args))
	defer destroy[.STRING](&s)
	v := variant(s)
	defer gde.variant_destroy(&v)
	utility_print(v)
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
	// The class name and whether it is RefCounted are fixed per `T`: looked up on the first call.
	@(static) sn: StringName
	@(static) known: bool
	if !known {
		named := type_info_of(T).variant.(runtime.Type_Info_Named)
		gde.string_name_new_with_latin1_chars(&sn, fmt.ctprintf("%s", named.name), 1)
		known = true
	}
	// A RefCounted object returns holding the one reference the caller takes over.
	obj := gde.classdb_construct_object3(&sn)
	object_notification(Object(obj), 0, false)
	return T(obj)
}
