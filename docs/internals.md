# How the core works

What happens on each call path, and what it costs. The numbers come from `bench/`
(`bench/build.sh /path/to/godot`) on Linux x86_64.

## Generated and hand-written code

`tools/odin_bindgen.py` reads `api/extension_api.json` and `api/gdextension_interface.json`, which
the engine dumps, and writes:

| File | Holds |
|---|---|
| `gdextension/` | The C interface: function pointer types, structs, enums, and `load_interface`. |
| `godot/gen_types.odin` | Builtin types (`Vector2`, `String`...), engine class types and enums. |
| `godot/gen_builtins.odin` | Builtin methods, constructors, operators. |
| `godot/gen_classes.odin` | Every engine class method and singleton. |
| `godot/gen_utility.odin` | `@GlobalScope` utility functions. |
| `godot/gen_virtuals.odin` | One `override_<class>_<virtual>` per engine virtual. |
| `godot/gen_calls.odin` | Per-arity call dispatch for registered methods. |
| `godot/gen_skipped.txt` | Anything the generator could not bind (empty for 4.7). |

`tools/gen_caps.py` writes `godot/gen_caps.odin` from the engine source's
`core/string/ucaps.h`, which the API dumps do not carry: the engine's case tables, for the
case-insensitive String compares to fold characters as the engine does. Regenerate it from the
release the bindings target when that release changes the tables:
`tools/gen_caps.py ucaps.h godot/gen_caps.odin`.

The hand-written core (`core.odin`, `class.odin`, `fields.odin`, `variant.odin`, `callable.odin`,
`access.odin`, `tasks.odin`) turns Odin structs and procs into engine classes. It uses the
generated code; the generated code calls back into `core.odin` only to look up its engine pointers.

## Method calls

`method` takes the proc as a compile-time constant and reads its signature, so each method gets
its own two entry points that call the proc directly:

- **ptrcall.** A typed GDScript call, or a call from another extension, passes raw pointers to the
  arguments. The core reads each one as its Odin type and calls the proc. No Variant is built.
  It costs about the same as a call to an engine method of the same shape, or slightly less.
- **Variant call.** An untyped call passes Variants. The core checks each argument's type,
  converts where the engine's own binds would (int, float and bool into one another, an Array to
  a packed array and back, null to an object), and fills in defaults for
  missing trailing arguments. It costs about the same as the engine's own Variant call. A
  method with no Array or packed array parameter gets a leaner entry point, since none of its
  arguments can need a new value built.

Debug builds count each Variant call, method or field, in `variant_calls`, so a test can check that
a typed call site took ptrcall. Release builds skip the count.

A property read or write from GDScript, such as `b.rate` or `b.rate = x`, takes a slower path
than either. In Godot 4.7 the GDScript compiler has no fast path for properties of engine or
extension objects. Every access goes through `Object::get` or `Object::set`, which by default
looks the property up by name in the class table and then makes a Variant call to its getter or
setter. An engine class's own property costs about 30 ns read and 24 ns written on the machine
that measured these numbers.

The engine asks an extension class's `get_func` and `set_func` hooks before that lookup, so the
core registers them for every class. They compare the asked name with each field's property name
by pointer, since equal StringNames share their data, and read or write the field directly. A
field read costs about 23 ns and a write about 16 ns, the same as or less than the typed
`get_rate()` and `set_rate(x)` calls. Any other name falls through to the engine's lookup, after
the class's own `get` and `set` hooks if it has them. A value the field cannot take also falls
through, so the engine's setter reports the error as before.

## Virtual overrides

`override_node_process(c, f)` takes `f` as a compile-time constant, so each override gets its own
small trampoline that calls `f` directly. The engine asks once per object which virtuals the class
overrides, then calls the trampoline by ptrcall. An Odin `_process` costs about 3 ns over a node
with no override. A GDScript `_process` costs about 41 ns.

## Finding the struct behind an object

A method that takes `^OtherClass` needs the Odin struct behind an engine object. The engine keeps
each object's class record and extension instance pointer as a pair near the head of its
`Object`. At the first instance, the core searches the object's first 16 words for the instance
pointer it just handed the engine. If it finds it exactly once, right after a set class record,
it reads that offset from then on. If not, it falls back to an instance binding, which the
engine supports officially.

The fallback works but costs more: a binding allocates per object and takes a mutex on every
reference change. `Bench.new()` from GDScript takes about 170 ns in the editor without a binding,
and about 70 ns more with one.

The same first instance also finds the object's type record. The core compares the object's first
32 words from before and after `object_set_instance`. If exactly one word changed besides the
pair, that word is the type record. Every later instance of the class then gets the three words
written directly, which skips `object_set_instance`'s class table lookup, its lock and its
StringName copy. On a 4.7 release export template that takes `Bench.new()` from about 160 ns to
150 ns. An editor build always makes the engine's call, because there `object_set_instance` also
records each instance for hot reload.

`fields` notes whether any field needs work when an instance is made or freed: an Array, a
Dictionary, a String or other counted value, or an object it holds. A class with none, like
`Bench`, has its template copied in at create and nothing done at free, without entering the
Odin context. That takes `Bench.new()` on the release template to about 135 ns, against about
105 ns for `RefCounted.new()`.

## Variants

A Variant is 24 bytes: a type tag, then the value or a pointer to it. The core reads scalar
Variants (bool, int, float) inline, without a call into the engine. Vararg engine methods hand a
Callable or Signal to the engine in place instead of copying it, which makes
`godot.callable_call` slightly faster than GDScript's `Callable.call`. Both rely on the engine's
Variant layout, which the core checks at load and stops on if it differs.

## Temp memory

Every call from the engine into Odin runs between `enter` and `leave`. `enter` marks the temp
arena, and `leave` rolls it back when the call returns. Most calls take no temp memory, and then
the rollback is a counter change with no call. The rare real rollback sits in a call of its own,
so a proc that never reads the context does not keep a copy of it. `enter` reaches the arena through a global rather
than the runtime's thread-local lookup, which would cost a `__tls_get_addr` call per engine call
in a shared library.

## Hot reload

On reload, the engine asks the library to recreate each live instance. The core allocates a fresh
struct, sets up its fields, and the engine sets the saved properties back. Fields tagged
`godot:"-"` start over at zero.

## Unload order

1. Editor level: editor plugins leave the editor, then editor classes unregister in reverse.
2. Scene level: singletons unregister, `unload` runs, then game classes unregister in reverse.
