# API outline

Every public proc and type in the `godot` package, grouped by job. The doc comment above each one
in the source is the full contract. This page tells you which one to reach for. See
[Getting started](getting-started.md) for a walkthrough.

`c` below is the `^Class(T)` that `class` returns, and `self` is a `^T`.

- [Entry](#entry)
- [Classes](#classes)
- [Options](#options)
- [Methods and properties](#methods-and-properties)
- [Fields](#fields)
- [Enums, flags and constants](#enums-flags-and-constants)
- [Signals and Callables](#signals-and-callables)
- [Engine virtuals](#engine-virtuals)
- [Script virtuals](#script-virtuals)
- [Editor and singletons](#editor-and-singletons)
- [Instances and objects](#instances-and-objects)
- [Variants](#variants)
- [Strings and names](#strings-and-names)
- [Packed arrays](#packed-arrays)
- [Temp memory and threads](#temp-memory-and-threads)
- [Errors](#errors)
- [Generated bindings](#generated-bindings)
- [Type mapping](#type-mapping)

## Entry

| Proc | Use |
|---|---|
| `entry(gpa, lib, init, register, unload = nil, docs = "", editor = nil) -> gde.Bool` | Return it from your exported init proc. `register` registers the game classes at the scene level. `unload` frees what the library holds. `docs` is help XML. `editor` registers editor-only classes. |

## Classes

| Proc / type | Use |
|---|---|
| `class(T, name, parent, notification = nil) -> ^Class(T)` | Registers `name` extending engine class `parent`. Each instance carries a `T`. `notification: proc(self: ^T, what: i64)` receives the object's notifications. |
| `class(T, name, parent, notification, options: Options(T))` | The same, with the hooks in [Options](#options). Pass `nil` for `notification` if you have none. |
| `Static` | Use as `T` for an abstract class of static methods only. |
| `Class(T)` | The registered class. Pass it to everything below. |
| `MAX_ARGS` | 13, the most parameters a method or signal takes. |

## Options

`Options(T)` is a struct of optional hooks. The engine calls into Odin only for the hooks you set.

| Field | GDScript equivalent | Use |
|---|---|---|
| `runtime: bool` | a script without `@tool` | The class runs only in a game. In the editor its instances are placeholders. |
| `get: proc(self, name: StringName) -> (Variant, bool)` | `_get` | Reads a property that is not a field. Returns false for a name it does not own. |
| `set: proc(self, name: StringName, value: ^Variant) -> bool` | `_set` | Writes one. `value` is borrowed. |
| `property_list: proc(self, list: ^[dynamic]Property)` | `_get_property_list` | Appends the properties `get` and `set` serve. |
| `can_revert: proc(self, name) -> bool` | `_property_can_revert` | Shows the inspector's revert arrow. |
| `get_revert: proc(self, name) -> (Variant, bool)` | `_property_get_revert` | The value the arrow reverts to. |
| `validate: proc(self, info: ^gde.PropertyInfo)` | `_validate_property` | Changes how any property shows: `info.usage`, `info.hint`, or the hint text through `set_hint_string`. |
| `to_string: proc(self) -> string` | `_to_string` | The object's text for `print` and `str`. Temp memory is fine. |

| Helper | Use |
|---|---|
| `Property{name, type, hint, hint_string, usage, class_name}` | One entry of `property_list`. The text can be temp memory. `usage` 0 means `PROPERTY_USAGE_DEFAULT`. |
| `set_hint_string(info, text)` | Replaces a property's hint text inside `validate`. |

## Methods and properties

| Proc | Use |
|---|---|
| `method(c, name, f, args = nil, defaults = nil)` | Registers `f`, a compile-time constant proc (a named proc or a proc literal). If its first parameter is `^T`, it is an instance method; otherwise it is static. `args` names the parameters after `self`. `defaults` fills the last ones (bool, integer, float, string or a Variant) when a Variant call leaves them out. A last parameter `rest: []Variant` makes the method vararg: it gets the arguments past the others, borrowed for the call (`variant_copy` one to keep it), and has no ptrcall. |
| `property(c, name, get, set, hint = .PROPERTY_HINT_NONE, hint_string = "", usage = DEFAULT)` | A property from a getter and a setter, registered as the methods `get_<name>` and `set_<name>`. Its type is the getter's return type. |
| `property_indexed(c, base, names, get, set, hint, hint_string, usage)` | One property per entry of `names`, such as `{"tint_r", "tint_g", "tint_b"}`, all served by `get(self, index: i64) -> V` and `set(self, index: i64, value: V)`, registered as `get_<base>` and `set_<base>`. The engine passes the name's position in `names` as `index`. |
| `library_path() -> String` | The absolute path of this library's file, to find data shipped beside it. You destroy it, or return it. |

Counted parameters (String, Array...) are borrowed for the call. A return is handed to the caller.
An Odin `string` parameter is a UTF-8 copy in temp memory, valid until the call returns; keep it
past that with `strings.clone`. An Odin `string` return is copied into a new String, so temp memory
(`fmt.tprintf`) is fine to return. Each crossing costs a copy, about 20 ns more than a `String`
for a short name: take `String` on a hot path.

## Fields

| Proc | Use |
|---|---|
| `fields(c, template = nil)` | Makes every field of `T` a property, in field order, with `get_<field>` and `set_<field>`. `template` (copied) is the value each new instance starts as. |
| `hold(&self.field, obj)` | Writes an object field from Odin. It takes a reference to `obj` if RefCounted and drops the old one. Null clears. |
| `hold_name(&self.field, name)` | The same for a StringName field. |

### Field tags

| Tag | Effect |
|---|---|
| `range:"min,max,step"` | An inspector slider. |
| `hint:"color_no_alpha"` | A Color with no alpha channel. |
| `group:"Name"`, `subgroup:"Name"` | Opens an inspector group before this field. |
| `array:"Class"` | Types an `Array` field's elements to a class or a builtin (`array:"PackedInt32Array"`). |
| `dict:"Key,Value"` | Types a `Dictionary` field. Each side is a builtin, a class or `Variant`. |
| `class:"Name"` | Types an Object field to an extension class. Read it back with `instance_of`. |
| `godot:"new"` | Gives each instance a new object of a RefCounted field's class, released at free. |
| `godot:"-"` | Odin only: not a property, never set up or destroyed by the core. |

Integers `u8` to `u64` read back unsigned. A `bit_set` field crosses as an integer of its bits and
shows as a flags checklist. Array and Dictionary fields always start empty.

## Enums, flags and constants

| Proc | Use |
|---|---|
| `enumerate(c, name, E)` | Registers enum `E` as `Class.name.VALUE`. Fields and parameters of type `E` then cross as that enum. Call it before `fields` or `method` meets `E`. |
| `enumerate_flags(c, name, E)` | Registers each value `v` of `E` as the bitfield constant `1 << v`, and makes `bit_set[E]` cross as that bitfield. `E` starts at 0 and stays below 64. |
| `mirror(E, "Class.Enum")` | Makes `E` cross as an enum a script class declares. It registers no constants. |
| `constant(c, name, value: i64)` | An integer constant `Class.name`. The engine has no float constants for extension classes. |
| `bits_of(set) -> i64`, `set_of(bit_set[E], bits) -> bit_set[E]` | Converts between a `bit_set` and its engine integer. |

## Signals and Callables

| Proc / type | Use |
|---|---|
| `Arg{name, type}` | One signal argument. |
| `signal(c, name, ..Arg) -> ^StringName` | Registers a signal. Keep the returned name for `emit`. |
| `emit(self, signal, ..Variant)` | Emits from `self`'s object. It destroys the args. |
| `callable(self, f, binds: ..Variant) -> Callable` | A Callable that calls `f(self, args..., binds...)`, for `connect`. The binds move in. The engine drops the connection when `self`'s object is freed. Destroy the Callable once it is connected. |
| `callable(f, binds: ..Variant) -> Callable` | The same for a plain proc with no instance. It lives as long as the Callable. |
| `call_deferred(self, f, binds: ..Variant)`, `call_deferred(f, binds: ..Variant)` | Calls `f` once at the end of the frame with `binds` as all its arguments, as GDScript's `call_deferred` does. The binds move in. The instance form is skipped if `self`'s object is freed first. |

## Engine virtuals

| Proc | Use |
|---|---|
| `override_<class>_<virtual>(c, f)` | Generated, one per engine virtual: `override_node_process`, `override_node_ready`, `override_editor_plugin_get_plugin_name`... The compiler checks `f`'s signature against the virtual. |
| `override(c, name, hash, f)` | The raw form the generated procs call. |

## Script virtuals

| Proc | Use |
|---|---|
| `script_virtual(c, name, P, args = nil, required = false) -> ^StringName` | Declares a virtual that a script extending the class can override, as `GDVIRTUAL` does in godot-cpp. `P` is its proc type, with `^T` first. The editor lists it with the overridable methods. `required` makes the engine warn if a script leaves it out. |
| `call_script(self, name, ..Variant) -> (ret: Variant, found: bool)` | Calls the script's override. It destroys the args. `found` is false when the script has none. You own `ret`. |

## Editor and singletons

| Proc | Use |
|---|---|
| `editor_plugin(c)` | Adds an EditorPlugin class to the editor. Call it from `entry`'s `editor` proc. |
| `register_singleton(name, object)` | Makes `object` a global in GDScript. Call it from `register`. The name is taken back at unload, and the object stays yours to free. |
| `singleton(name) -> gde.ObjectPtr` | Looks up an engine singleton by name. The generated `<class>_singleton()` procs are the usual way. |

## Instances and objects

| Proc | Use |
|---|---|
| `object_of(self) -> Object` | The engine object behind `self`. |
| `instance_of(obj, c) -> ^T` | The struct behind `obj` if it is an instance of `c`, else nil. |
| `make_instance(T) -> ^T` | A new instance of your class. A RefCounted one starts with one reference. Return it from a method or `release` it. |
| `share(self) -> ^T` | `self` with one more reference, for returning an instance you keep. |
| `construct(T) -> T` | A new engine object of class `T`. RefCounted: `release`. Otherwise `gde.object_destroy`. |
| `get_node(node, "Path", T) -> T` | The node at the path, as engine class `T`. Nil if there is no node there or it is not a `T`. Pass `object_of(self)` from your own Node class. |
| `get_node(node, "Path", c) -> ^T` | The same for a registered class `c`: the struct behind the node, or nil. |
| `get_node(node, path: NodePath, T or c)` | Either form with a NodePath, such as `intern_path("Body/Sprite")`, which skips parsing the path on each call. |
| `load(path, T) -> T` | The resource at `path` (`"res://..."` or `"user://..."`), as engine class `T`, through the resource cache. Nil, and the engine logs an error, if nothing loads there; nil if what loads is not a `T`. RefCounted: `release`. |
| `load(path, c) -> ^T` | The same for a resource of registered class `c`. Release it with `release(object_of(r))`. |
| `cast_to(obj, T) -> T` | `obj` as engine class `T` if it is one, else nil. Engine classes only. Use `instance_of` for yours. |
| `share_object(obj) -> T` | `obj` with one more reference, for returning an engine object you keep. |
| `release(obj)` | Drops one reference, and frees the object if that was the last. |
| `is_live(id: u64) -> bool` | Whether the object with that instance id still exists. |

## Variants

| Proc | Use |
|---|---|
| `variant(value) -> Variant` | A new Variant. Counted values are copied. An instance goes in as its object. Destroy it with `gde.variant_destroy`. |
| `variant_into(&out, value)` | The same, written in place. |
| `variant_int(&v)`, `variant_float(&v)`, `variant_bool(&v)` | Reads a Variant, converting between int, float and bool. |
| `from_variant(A, &v) -> A` | Reads any mapped type. |
| `variant_tag(&v) -> gde.VariantType` | The type a Variant holds. |
| `variant_type(A)`, `variant_meta(A)` | The Variant type and the width metadata an Odin type crosses as. |
| `converts(have, want)`, `reshapes(have, want)`, `reshape(&v, want, &out)` | The conversion rules a Variant call follows. |
| `destroy[type]` | Destructors by Variant type, for builtins: `destroy[.STRING](&s)`. |
| `array_at(&a, i) -> ^Variant` | Element `i` of an Array, borrowed: no copy, and you do not destroy it. Nil when `i` is out of range. About 2.7 ns for a String element, against 15 ns for `array_get` and its destroy. |
| `array_read(&a) -> []Variant` | An Array's elements as a slice over its storage, borrowed: valid until `a` changes. Do not write through it or destroy its elements. |
| `array_write(&a) -> []Variant` | The same, writable: about 1.8 ns per int element, against 10.5 ns for `array_set`. Nil for a typed or read-only Array, whose checks a direct write would skip; `array_write_typed` covers typed ones. Every holder of `a` sees the writes, as with `set`. Destroy an element before storing a new one in its place. |
| `array_of(xs) -> Array` | A new untyped Array from an Odin slice, each element converted as `variant` does, in one resize: about 0.9 ns per int, against 13 ns for one `push_back` each. You destroy it, or return it. |
| `array_typed_of(xs) -> Array` | A new Array typed to the slice's element type, as GDScript's `Array[T]`: an integer slice makes `Array[int]`, a float slice `Array[float]`, a slice of an engine class `Array[Node]`, a slice of `^S` for a registered struct `S` the Array of that class, and so on. Built in one resize, as `array_of` is: about 1.4 ns per int, against 13 ns for one `push_back` each. A registered class must register before its first typed Array. You destroy it, or return it. |
| `array_write_typed(&a, T) -> []Variant` | `array_write` for a typed Array: the slice when `a` is typed exactly to `T` and writable, else nil: about 1.7 ns per int element, against 10 ns for `set`. Store only `T` values in it, since the direct write skips the engine's type check. An `Array[Node]` takes `T` Node, not a subclass, and an Array typed to a script class gives nil. `T` may be `^S` of a registered struct `S`; read an element with `from_variant(^S, &v)`. |
| `dict_items(&d) -> (keys, values)` | A Dictionary's keys and values as two new Arrays in matching order, for reading with `array_read`: about 11 ns per entry to sum the values, against 36 ns for `keys()` and one `get` per key. You destroy both. |
| `dict_get(&d, key) -> (Variant, bool)` | The value `key` maps to, and whether `d` has it; `key` is a `^Variant`, a Variant or any Odin value `variant` converts. One hash lookup: about 27 ns for an int key against 33 for `dictionary_get`, which also cannot tell a missing key from its default. You destroy the value. |
| `dict_get_into(&d, key, &out) -> bool` | The same, writing the value to `out` (which holds nothing): about 21 ns, as it skips copying the result back. |
| `dict_set(&d, key, value) -> bool` | `d[key] = value`, each side a Variant or any Odin value. False when `d` is read-only, or typed and a side does not fit. |
| `variant_get(&v, key) -> (Variant, bool)` / `variant_set(&v, key, value) -> bool` | `v[key]` on any Variant as GDScript reads and writes it: a Dictionary's value, an Array's element, an Object's property, a Vector2's `"x"`. A Dictionary, Array or Object shares its storage, so a set reaches every holder. You destroy what `variant_get` answers. |
| `dict_of(keys, values) -> Dictionary` | A new untyped Dictionary mapping `keys[i]` to `values[i]`, from two Odin slices of the same length. A repeated key keeps its last value. About as fast as one `set` per entry (58 against 62 ns per int entry), since the engine's hashing dominates. You destroy it, or return it. |
| `dict_typed_of(keys, values) -> Dictionary` | The same, typed as GDScript's `Dictionary[K, V]`. Each side is a builtin, an engine class, or `Variant` for an untyped side. |

## Strings and names

| Proc | Use |
|---|---|
| `string_of(s: string) -> String` | A new engine String. You destroy it, or return it. |
| `utf8(s: String / StringName / NodePath, allocator) -> string` | Engine text as Odin UTF-8, encoded in Odin from the String's characters read in place (layout checked at load): about 14 ns for a short String, most of it the allocation. A StringName or NodePath goes through a temporary String first. You delete it. |
| `intern("literal") -> StringName` | The StringName for a constant, made on the first call and kept for the life of the process. Each later call is one load, about 0.4 ns against 31 ns for `name_of`, so use it inline: `input_is_action_pressed(input, intern("jump"), false)`. Do not destroy it. Safe from any thread. |
| `intern_path("Body/Sprite") -> NodePath` | The same for a constant NodePath: about 0.2 ns against 110 ns for `path_of`. Pass it to `get_node`. Do not destroy it. |
| `intern_text("literal") -> String` | The same for a constant String, such as an editor description or a label passed as a String parameter. Do not destroy it. |
| `temp_text(s: string) -> String` | A new String destroyed when the current call from the engine returns (or the innermost `enter()` scope ends), for passing run-time text, such as `fmt.tprintf` output, to a String parameter without a `defer destroy`. Only inside a call from the engine; asserts otherwise. Do not destroy it or keep it past the call. |
| `temp_texts_live() -> int` | The number of `temp_text` Strings not yet dropped; 0 between calls. For tests. |
| `static_name("literal") -> StringName` | A new StringName the engine keeps for the life of the process, made on each call. `intern` is the cached form. |
| `name_of(s: string) -> StringName` | A new StringName from any Odin text, about 31 ns for a short ASCII name (a hash lookup in the engine). You destroy it, or return it. For a constant, use `intern`. |
| `path_of(s: string) -> NodePath` | A new NodePath, such as `"Body/Sprite"` or `"Body:position"`, parsed each call (about 110 ns). You destroy it, or return it. For a constant, use `intern_path`. |
| `same_name(a, b) -> bool` | StringName equality. Names are interned, so this is one compare. |
| `array_name_at(&array, i) -> StringName` | Element `i` as a StringName, which you destroy. |
| `string_read(&s) -> []rune` | A String's characters as a slice over its storage, read in place: about 0.07 ns per character, against 4.4 ns for `unicode_at`. Valid until `s` changes. Do not write through it. |
| `string_equal(&a, &b) -> bool` | String equality. A String and its copy share storage and answer in about 1 ns; others reject on length from their headers, then compare four characters at a time: about 3.1 ns for a short identifier, against 3.7 for the engine's `==`. |
| `string_equal_text(&s, text) -> bool` | Whether `s` holds the characters of Odin text `text`, compared in place with no String made: about 1.9 ns for a short ASCII identifier, against 20 ns to build a String and use the engine's `==`. Invalid UTF-8 in `text` reads as U+FFFD. |
| `string_begins_with_text(&s, text) -> bool` / `string_ends_with_text(&s, text) -> bool` | Whether `s` starts or ends with Odin text `text`, compared in place: about 1.6 ns for a short ASCII part, against 10.7 for the generated `string_begins_with` even with its String cached. ASCII text compares with no branch per character; other text decodes. |
| `string_find_text(&s, text, from = 0) -> i64` / `string_rfind_text(&s, text, from = -1) -> i64` / `string_contains_text(&s, text) -> bool` | The character index of the first `text` in `s` at or after `from` (or the last at or before it, for `rfind`), or -1, searched in place with the engine's rules: a negative `from` counts back from the last place `text` fits, a `from` past that place gives -1, and empty `text` gives -1. The scan tests four characters at a time for the first character of `text`: about 9 ns to find a short word in a 43-character sentence, against 75 to 80 for the generated `string_find` and `string_rfind` even with their String cached. |
| `string_equal_text_nocase(&s, text) -> bool` / `string_findn_text(&s, text, from = 0) -> i64` / `string_rfindn_text(&s, text, from = -1) -> i64` / `string_containsn_text(&s, text) -> bool` | The same ignoring case, folding each character through the engine's Unicode case tables as `nocasecmp_to`, `findn`, `rfindn` and `containsn` do, so `"\u0130stanbul"` matches `"istanbul"`. ASCII folds with arithmetic, four characters a step, other characters by a table search. About 3.2 ns to compare an 11-character name against 366 for the generated `string_nocasecmp_to`, and 14 ns to find a word in a sentence against 706 for `string_findn`, both with their String cached. |
| `string_begins_with_text_nocase(&s, text) -> bool` / `string_ends_with_text_nocase(&s, text) -> bool` | Whether `s` starts or ends with `text` ignoring case, folding to lower case as `findn` does: the same answer as `s.to_lower().begins_with(text.to_lower())` with no String made. The engine has no such method. About 2.2 ns for a short ASCII part. |
| `string_count_text(&s, text, from = 0, to = 0) -> i64` / `string_countn_text(&s, text, from = 0, to = 0) -> i64` | How many times `text` appears in `s` between characters `from` and `to`, not overlapping, with case or without: the engine's `count` and `countn`, compared in place on the find scan. As there, `to` 0 means the end, and empty `text`, a negative bound or `from` at or past `to` gives 0. About 13 to 24 ns for a short word in a 43-character sentence, against 85 to 110 for the generated `string_count` with its String cached. |
| `string_replace_text(&s, what, forwhat) -> String` / `string_replacen_text(&s, what, forwhat) -> String` | A copy of `s` with every `what` replaced by `forwhat`, both Odin text, as `replace` and `replacen` do. Matches are found in place and the result is written once into a String made at its final length, with no String made for `what` or `forwhat`. About 33 ns to replace a word in a sentence, against 114 for the generated `string_replace` with its Strings cached. The caller destroys the result. |
| `string_split_text(&s, delimiter, allow_empty = true, maxsplit = 0) -> PackedStringArray` | The parts of `s` between each Odin text `delimiter`, as `split` gives them, with the same empty-delimiter, `allow_empty` and `maxsplit` rules. The parts are counted first so the array is sized once, and each part is copied straight from `s` without the check a String made from outside characters gets. About 197 ns to split a nine-word sentence on spaces, against 253 for the generated `string_split` with its delimiter cached; making the nine Strings is most of both. The caller destroys the result. |
| `string_split_parts(&s, delimiter) -> Split_Parts` / `split_next(&parts) -> ([]rune, bool)` | The parts `split` would give with `allow_empty` true, read one at a time as slices over `s`'s characters: `for part in godot.split_next(&parts)`. No String or array is made, so a parsing loop that never hands its parts to the engine pays only for the search: about 28 ns for the nine words of a sentence, against 197 for `string_split_text`. The slices stay valid until `s` is written or destroyed; `parts.chars[parts.from:]` is the rest after the part just read. |
| `runes_strip_edges(chars, left = true, right = true) -> []rune` / `string_of_runes(chars) -> String` | `runes_strip_edges` trims whitespace (any character up to 32, as `strip_edges` counts it) from either end of a part, as a slice of it, with no String made. `string_of_runes` makes a String from a part once one must go to the engine, copying the characters as they are without the check a String made from outside characters gets. The caller destroys the String. |
| `runes_equal_text(chars, text) -> bool` / `runes_equal_text_nocase(chars, text) -> bool` / `runes_to_int(chars) -> i64` | `string_equal_text` and its case-insensitive form on characters already read, such as a part from `split_next`, and the engine's `to_int` on them: up to the first `.`, every ASCII digit taken and anything else skipped, a `-` before the first nonzero digit flipping the sign, and a value past the 64-bit range clamped (the engine also prints an error there). `runes_to_int` takes about 3.4 ns for `"-12345"` read in place, against 8 for the generated `string_to_int`. |
| `runes_to_float(chars) -> f64` | The engine's `to_float` on characters already read, to the same bits: leading space, tab and newline skipped, a sign, digits with at most one `.`, then an exponent, reading stopping at the first character that does not fit. Mantissa digits past 18 are dropped and an exponent past 511 is taken as 511, as there. `runes_to_float` takes about 12 ns for `"-123.456e-2"` read in place, against 17 for the generated `string_to_float`. |
| `text_set(names) -> Text_Set(N)` / `string_which(&s, &set) -> int` | The index of the name `s` holds among a fixed `[N]string`, or -1: for mapping a String to an action or command. Each name keys on its length and first and last characters, so a lookup compares one integer per name and the characters of only the names that key matches: about 5 ns over 8 `player_*` names, against 23 for the engine's `==` on each in turn. Build the set once; it holds the names, which must outlive it. |
| `name_set(names) -> Name_Set(N)` / `name_which(name, &set) -> int` / `name_set_destroy(&set)` | The same for a StringName: the index of `name` among a fixed `[N]string`, or -1. The set holds its own reference to each name, so a lookup compares one integer per name: about 0.8 ns over 8 names, against 3.1 for `same_name` with `intern` on each in turn. Build it once, about 31 ns a name, and release it with `name_set_destroy`. |
| `string_write(&s) -> []rune` | The same, writable. A shared String gets storage of its own first. Only on a String you own. |
| `string_append(&s, x)` | Appends Odin text, a String or a rune to `s` in place. Text goes through the engine's UTF-8 parser, as `string_of` does, so the result matches a String built from the same bytes. Only on a String you own. |

## Packed arrays

| Proc | Use |
|---|---|
| `packed_read(&a) -> []E` | A packed array's elements as a slice over its storage, read in place: about 0.05 ns per element in a sum loop, against 3.2 ns for `packed_int64_array_get`. Valid until `a` changes. Do not write through it, since the storage may be shared. |
| `packed_write(&a) -> []E` | The same, writable. A shared array gets storage of its own first. Use it only on an array you own, such as a copy made with `packed_<type>_array_new_from_packed_<type>_array`, never on a borrowed parameter. |
| `packed_of(xs) -> PackedX` | A new packed array copied from an Odin slice in one resize and one copy, for any of the ten element types: about 0.14 ns per element, against 2 ns for one `set` each. A String element is copied as a new reference. You destroy it, or return it. |

## Images and files

| Proc | Use |
|---|---|
| `image_read(img) -> []u8` | An Image's pixel bytes, read in place, laid out as `image_get_format` says. Valid until `img` changes. Do not write through it. |
| `image_write(img) -> []u8` | The same, writable: about 0.6 ns per RGBA8 pixel, against 5 ns for `image_set_pixel`. A texture made from `img` sees the writes only once updated from it. |
| `file_read(f, dst) -> int` | Reads up to `len(dst)` bytes of `f` into `dst` and returns how many it read, without a PackedByteArray: about 470 ns per 4 KiB, against 535 ns for `get_buffer`. |
| `file_write(f, src)` | Writes `src` to `f`. `file_access_get_error` reports a failure. |

## Worker threads

| Proc | Use |
|---|---|
| `run_task(f, &data) -> id` | Runs `f(&data)` once on the engine's WorkerThreadPool. `f` is a compile-time constant proc. |
| `run_group(f, &data, count) -> id` | Runs `f(&data, i)` for `i` in `0 ..< count`, spread over the pool. `tasks` caps the threads; -1 lets the engine choose. |
| `wait_task(id)` / `wait_group(id)` | Waits for a task or group to finish. Wait before `data` goes out of scope. |

Each worker call runs with the core's allocator and that worker thread's own temp allocator, rolled
back when `f` returns. Once a thread's outermost call returns, its temp arena is emptied, down to one
4 MiB block, or to none after a call that needed more, so a large task does not keep its memory. It does not run `enter`: Odin class callbacks and engine calls the engine
does not allow off the main thread must not be made from `f`, and `f` must not touch what the main
thread is changing. A debug build stops with `godot_odin: a run_task or run_group proc called into
an Odin class` when a task does, directly or through an engine call that reaches one; a release
build does not check, and the call races the main thread's temp memory. Queueing and waiting cost the same as the engine's own `add_task` with a
Callable, about 4 µs for one task and 23 ns per group call; `f` itself runs as plain Odin, with no
Variant or Callable in between.

## Temp memory and threads

| Proc | Use |
|---|---|
| `enter()` / `leave(mark)` | Marks and rolls back the temp arena. Every engine call into Odin already does this. Call them yourself only from your own `proc "c"` callbacks, after `context = ...`. |
| `temp_used() -> i64` | Bytes the temp arena holds now, for tests that check a call frees its temp. |

## Errors

| Proc | Use |
|---|---|
| `print(format, ..args)` | Prints a formatted line to the engine's output, as GDScript's `print` does. `fmt.println` reaches stdout only, not the editor's Output panel. |
| `error(format, ..args)` | `push_error` with the Odin file and line. It shows in the log and the debugger. |
| `warn(format, ..args)` | `push_warning`, the same way. |
| `fail(message, what) -> !` | Stops the process with a message. For a binding the engine lacks. |

## Generated bindings

| Pattern | Example |
|---|---|
| Engine classes are `distinct rawptr` | `godot.Node`, `godot.InputEventKey` |
| Class methods are `<class>_<method>(self, ...)` | `godot.node_add_child(node, child, false, .INTERNAL_MODE_DISABLED)` |
| Singletons are `<class>_singleton()` | `godot.engine_singleton()` |
| Builtin methods are `<type>_<method>(&self, ...)` | `godot.callable_call(&f, arg)` |
| Vararg methods end in `rest: ..Variant`, which the caller keeps | `godot.object_call(obj, name, a, b)` |
| Utility functions are `utility_<name>` | `godot.utility_print(v)`, the `@GlobalScope` functions |
| Enums are `<Class>_<Enum>` | `godot.Node_InternalMode` |
| Raw interface | `gde.*` in `gdextension/`: function pointers and C types |

Each binding resolves its engine pointer on its first call and caches it.

## Type mapping

How an Odin type crosses to the engine, for parameters, returns and fields:

| Odin | Engine |
|---|---|
| `bool` | `bool` |
| any integer | `int`. `u8` to `u64` are flagged unsigned. |
| an enum | `int`, or the enum `enumerate` registered |
| `bit_set[E]` | `int`, or the bitfield `enumerate_flags` registered |
| `f32`, `f64` | `float` |
| `string` | `String`, copied each way (see Methods and properties) |
| `String`, `StringName`, `NodePath`, `Vector2`...`Projection`, `Color`, `RID`, `Callable`, `Signal`, `Dictionary`, `Array`, packed arrays | the builtin of the same name |
| an engine class (`Node`...) or any `distinct rawptr` | `Object` |
| `^T` of a registered class | `Object` of that class |
| `Variant` | any value |

Anything else, such as a slice or a map, has no engine type and fails to compile with
`godot_odin: this Odin type has no Variant type`. Fields take `String`, not `string`: a field is
stored in the engine's layout, and an Odin `string` field panics at register time.
