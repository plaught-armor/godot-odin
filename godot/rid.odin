package godot

// RID methods and constructors computed in place, under the names and signatures the bindings
// generated before. An RID is the engine's one 64-bit id (core/templates/rid.h of Godot
// 4.7-stable): zero is the invalid RID, and get_id returns the id as is. tools/odin_bindgen.py
// leaves these names out of godot/gen_builtins.odin.

#assert(size_of(RID) == size_of(u64))

rid_new :: proc "contextless" () -> (__r: RID) { return }
rid_new_from_rid :: proc "contextless" (from: RID) -> (__r: RID) { return from }
rid_is_valid :: proc "contextless" (self: ^RID) -> bool { return (^u64)(self)^ != 0 }
rid_get_id :: proc "contextless" (self: ^RID) -> i64 { return (^i64)(self)^ }
