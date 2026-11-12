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

The hand-written core (`core.odin`, `class.odin`, `fields.odin`, `variant.odin`, `callable.odin`)
turns Odin structs and procs into engine classes. It uses the generated code; the generated code
calls back into `core.odin` only to look up its engine pointers.

## Method calls

`method` reads the proc's signature at compile time and registers two entry points:

- **ptrcall.** A typed GDScript call, or a call from another extension, passes raw pointers to the
  arguments. The core reads each one as its Odin type and calls the proc. No Variant is built.
  It costs about the same as a call to an engine method of the same shape.
- **Variant call.** An untyped call passes Variants. The core checks each argument's type,
  converts where the engine's own binds would (int, float and bool into one another, an Array to
  a packed array and back, null to an object), and fills in defaults for
  missing trailing arguments. It costs about 3 ns more than the engine's own Variant call.

A property read or write from GDScript, such as `b.rate` or `b.rate = x`, takes a slower path
than either. In Godot 4.7 the GDScript compiler has no fast path for properties of engine or
extension objects: every access looks the property up by name and then makes a Variant call to
its getter or setter. A property of an engine class costs the same, about 30 ns on the machine
that measured these numbers. In a hot loop, call the accessor instead: `b.get_rate()` and
`b.set_rate(x)` are typed calls and take the ptrcall path, about 23 ns and 20 ns against 31 ns
and 27 ns for the property.

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
reference change. `Bench.new()` from GDScript takes about 190 ns without a binding and 260 ns with
one.

## Variants

A Variant is 24 bytes: a type tag, then the value or a pointer to it. The core reads scalar
Variants (bool, int, float) inline, without a call into the engine. Vararg engine methods hand a
Callable or Signal to the engine in place instead of copying it, which makes
`godot.callable_call` slightly faster than GDScript's `Callable.call`. Both rely on the engine's
Variant layout, which the core checks at load and stops on if it differs.

## Temp memory

Every call from the engine into Odin runs between `enter` and `leave`. `enter` marks the temp
arena, and `leave` rolls it back when the call returns. Most calls take no temp memory, and then
the rollback is a counter change with no call. `enter` reaches the arena through a global rather
than the runtime's thread-local lookup, which would cost a `__tls_get_addr` call per engine call
in a shared library.

## Hot reload

On reload, the engine asks the library to recreate each live instance. The core allocates a fresh
struct, sets up its fields, and the engine sets the saved properties back. Fields tagged
`godot:"-"` start over at zero.

## Unload order

1. Editor level: editor plugins leave the editor, then editor classes unregister in reverse.
2. Scene level: singletons unregister, `unload` runs, then game classes unregister in reverse.
