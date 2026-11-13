package godot

import "base:intrinsics"

// NodePath reads answered from the engine's storage, with no method call, once
// `check_node_path_layout` proved it at load: the generated `is_empty`, `is_absolute`,
// `get_name_count`, `get_subname_count`, `hash`, `get_name`, `get_subname`,
// `get_concatenated_names` and `get_concatenated_subnames` try these first
// (tools/odin_bindgen.py IN_PLACE). Each answers as NodePath does in Godot 4.7-stable
// (core/string/node_path.h, node_path.cpp). A NodePath points at its NodePath::Data, nil for the
// empty path. The names it returns are copied as the StringName copy constructor does, by adding a
// reference to the interned data in place; the engine is called instead where it would print an error (the empty path, an index out of range) or fill a
// cache (a hash or concatenated name not yet computed), so those still behave as there.

// True when a NodePath's data is NodePath::Data as the reads below take it.
// `check_node_path_layout` decides it at load; without it every read calls the engine.
@(private)
node_path_layout_known: bool

// Where NodePath::Data keeps the element pointer of its `path` Vector<StringName>: after its 32-bit
// reference count, padded to 8 bytes, and the Vector's empty write proxy, padded to 8 bytes too.
// The elements follow the copy-on-write header that packed.odin reads.
@(private)
NODE_PATH_NAMES_OFFSET :: 16

// Where NodePath::Data keeps the element pointer of its `subpath` Vector<StringName>, past the
// `path` Vector and the `subpath` write proxy.
@(private)
NODE_PATH_SUBNAMES_OFFSET :: 32

// Where NodePath::Data keeps `concatenated_path`, a StringName cache that is empty until
// `get_concatenated_names` or `hash` fills it.
@(private)
NODE_PATH_CONCAT_NAMES_OFFSET :: 40

// Where NodePath::Data keeps `concatenated_subpath`, filled as `concatenated_path` is.
@(private)
NODE_PATH_CONCAT_SUBNAMES_OFFSET :: 48

// Where NodePath::Data keeps `absolute`, then `hash_cache_valid` after it and `hash_cache` at the
// next 4-byte boundary.
@(private)
NODE_PATH_ABSOLUTE_OFFSET :: 56
@(private)
NODE_PATH_HASH_VALID_OFFSET :: 57
@(private)
NODE_PATH_HASH_OFFSET :: 60

#assert(size_of(NodePath) == size_of(rawptr))
#assert(size_of(StringName) == size_of(rawptr))

// The StringNames of the Vector<StringName> at `offset` in `p`'s data, empty for the empty path.
// Only when `node_path_layout_known`.
@(private)
node_path_stored_list :: #force_inline proc "contextless" (p: ^NodePath, offset: uintptr) -> []StringName {
	data := (^rawptr)(p)^
	if data == nil { return nil }
	d := (^rawptr)(uintptr(data) + offset)^
	if d == nil { return nil }
	return ([^]StringName)(d)[:(^i64)(uintptr(d) - PACKED_SIZE_OFFSET)^]
}

// The node name count of `p`, read from its storage. Only when `node_path_layout_known`.
node_path_stored_name_count :: #force_inline proc "contextless" (p: ^NodePath) -> i64 {
	return i64(len(node_path_stored_list(p, NODE_PATH_NAMES_OFFSET)))
}

// The subname (property) count of `p`, read from its storage. Only when `node_path_layout_known`.
node_path_stored_subname_count :: #force_inline proc "contextless" (p: ^NodePath) -> i64 {
	return i64(len(node_path_stored_list(p, NODE_PATH_SUBNAMES_OFFSET)))
}

// Whether `p` starts at the root, false for the empty path. Only when `node_path_layout_known`.
node_path_stored_absolute :: #force_inline proc "contextless" (p: ^NodePath) -> bool {
	data := (^rawptr)(p)^
	return data != nil && (^u8)(uintptr(data) + NODE_PATH_ABSOLUTE_OFFSET)^ != 0
}

// The hash of `p` as NodePath::hash gives it: 0 for the empty path, else the cached hash. False
// when the cache is not filled yet, which the engine call fills. Only when `node_path_layout_known`.
node_path_stored_hash :: #force_inline proc "contextless" (p: ^NodePath) -> (u32, bool) {
	data := (^rawptr)(p)^
	if data == nil { return 0, true }
	if (^u8)(uintptr(data) + NODE_PATH_HASH_VALID_OFFSET)^ == 0 { return 0, false }
	return (^u32)(uintptr(data) + NODE_PATH_HASH_OFFSET)^, true
}

// The stored name `idx` of the Vector<StringName> at `offset` in `p`'s data, nil when `idx` is out
// of range or `p` is empty, where the engine prints an error. Only when `node_path_layout_known`.
@(private)
node_path_stored_name :: #force_inline proc "contextless" (p: ^NodePath, offset: uintptr, idx: i64) -> ^StringName {
	names := node_path_stored_list(p, offset)
	if idx < 0 || idx >= i64(len(names)) { return nil }
	return &names[idx]
}

// The concatenated-name cache at `offset` in `p`'s data, nil while it is empty or `p` is empty,
// where the engine fills it or prints an error. Only when `node_path_layout_known`.
@(private)
node_path_stored_concat :: #force_inline proc "contextless" (p: ^NodePath, offset: uintptr) -> ^StringName {
	data := (^rawptr)(p)^
	if data == nil { return nil }
	n := (^StringName)(uintptr(data) + offset)
	if (^rawptr)(n)^ == nil { return nil }
	return n
}

// A copy of the StringName `n` that a NodePath holds, made as StringName's copy constructor does:
// one more reference on its interned data, whose 32-bit SafeRefCount sits at byte 0. The NodePath
// keeps its own reference, so the count is at least 1 and cannot reach 0 meanwhile, which is why
// the constructor's conditional increment is a plain one here. Only when `node_path_layout_known`.
node_path_name_copy :: #force_inline proc "contextless" (n: ^StringName) -> StringName {
	intrinsics.atomic_add_explicit((^u32)((^rawptr)(n)^), 1, .Acq_Rel)
	return n^
}

// Sets `node_path_layout_known` from NodePaths of known contents: an absolute one with three names
// and two subnames, a relative one with one name and none, and "/" with neither; each read is
// compared with the engine's answer, the names and caches by their interned data.
check_node_path_layout :: proc "contextless" () {
	node_path_layout_known = false
	if !packed_layout_known { return }
	// The stored name is the engine's, and its reference count is one more while the engine's copy
	// lives, and again while one `node_path_name_copy` made lives: the count it adds to.
	same_name :: proc "contextless" (stored: ^StringName, engine: StringName) -> bool {
		e := engine
		if stored == nil || (^rawptr)(stored)^ == nil || (^rawptr)(stored)^ != (^rawptr)(&e)^ {
			destroy[.STRING_NAME](&e)
			return false
		}
		count := (^u32)((^rawptr)(stored)^)
		with_copy := count^
		destroy[.STRING_NAME](&e)
		held := count^
		c := node_path_name_copy(stored)
		copied := count^
		destroy[.STRING_NAME](&c)
		return with_copy == held + 1 && copied == held + 1 && count^ == held
	}
	holds :: proc "contextless" (p: ^NodePath, names, subnames: i64, absolute: bool) -> bool {
		if (^rawptr)(p)^ == nil { return false }
		if node_path_stored_name_count(p) != names || node_path_get_name_count(p) != names { return false }
		if node_path_stored_subname_count(p) != subnames || node_path_get_subname_count(p) != subnames { return false }
		if node_path_stored_absolute(p) != absolute || node_path_is_absolute(p) != absolute { return false }
		for k in 0 ..< names {
			if !same_name(node_path_stored_name(p, NODE_PATH_NAMES_OFFSET, k), node_path_get_name(p, k)) { return false }
		}
		for k in 0 ..< subnames {
			if !same_name(node_path_stored_name(p, NODE_PATH_SUBNAMES_OFFSET, k), node_path_get_subname(p, k)) { return false }
		}
		if _, cached := node_path_stored_hash(p); cached { return false }
		engine_hash := u32(node_path_hash(p))
		h, ok := node_path_stored_hash(p)
		if !ok || h != engine_hash { return false }
		if names > 0 && !same_name(node_path_stored_concat(p, NODE_PATH_CONCAT_NAMES_OFFSET), node_path_get_concatenated_names(p)) { return false }
		if subnames > 0 && !same_name(node_path_stored_concat(p, NODE_PATH_CONCAT_SUBNAMES_OFFSET), node_path_get_concatenated_subnames(p)) { return false }
		return true
	}
	a := path_of("/root/check_node_path/layout:position:x")
	defer destroy[.NODE_PATH](&a)
	b := path_of("check_node_path")
	defer destroy[.NODE_PATH](&b)
	r := path_of("/")
	defer destroy[.NODE_PATH](&r)
	e := node_path_new()
	defer destroy[.NODE_PATH](&e)
	node_path_layout_known = holds(&a, 3, 2, true) && holds(&b, 1, 0, false) && holds(&r, 0, 0, true) &&
		(^rawptr)(&e)^ == nil && node_path_is_empty(&e)
}
