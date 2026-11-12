# godot-odin

Godot 4 GDExtension bindings for [Odin](https://odin-lang.org), with no C or C++ shim.

GDExtension is a C ABI, and Odin speaks C natively. These bindings are generated from the engine's
own API dumps (`extension_api.json` and `gdextension_interface.json`) by `tools/odin_bindgen.py`,
and a small hand-written core turns plain Odin structs and procs into engine classes.

They were built for, and run in, a shipping-bound Godot game. Its simulation layer has about
14k lines of Odin across 80 registered classes.

## Status

- **Engine:** Godot **4.7** or later. The core uses interface functions that 4.7 added
  (`classdb_construct_object3`, `classdb_register_extension_class6`, `variant_get_type_by_name`),
  so 4.6 and older will not load it. The bindings in `godot/gen_*` are generated from
  **4.7.2-stable**.
- **Build configuration:** `float_64`, which means single-precision `real_t` and 64-bit pointers,
  the default engine build. A double-precision build needs a change to `CONFIG` in
  `tools/odin_bindgen.py`.
- **Platforms:** developed and tested on Linux x86_64. Nothing in the core is Linux-specific,
  but Windows and macOS have not been built.
- **Coverage:** every class, builtin and utility method in the API is bound. The bindgen lists
  anything it cannot bind in `godot/gen_skipped.txt`, which is empty for 4.7.
- **Known engine issue:** in Godot 4.7, the first `--import` of a project with no
  `.godot/extension_list.cfg` crashes at the end of the scan if any GDExtension registers an
  exposed class. A godot-cpp extension crashes at the same place. The import still writes
  `extension_list.cfg`, and every later run is clean, so `example/build.sh` and `bench/build.sh`
  run the import once and ignore its exit status.

## Layout

| Path | What |
|---|---|
| `gdextension/` | The raw interface: function pointers and C types. Generated. |
| `godot/gen_*.odin` | Builtin types, engine classes, utility functions, per-arity call dispatch. Generated. |
| `godot/class.odin`, `fields.odin`, `variant.odin`, `callable.odin`, `core.odin` | The hand-written core: entry point, class registration, methods, properties, signals, Variant conversion. |
| `api/` | The API dumps the generated files come from. |
| `tools/odin_bindgen.py` | Regenerates `gdextension/` and `godot/gen_*` from `api/`. |
| `tools/dump_api.sh` | Dumps `api/` from a Godot binary, then runs the bindgen. |
| `tools/odin_docgen.py` | Turns a package's comments into class reference XML for the editor's help. |
| `example/` | A minimal extension, a project that loads it, and a test. |
| `addons/odin_build/` | An editor plugin that rebuilds and reloads the extension when its Odin sources change. |
| `bench/` | Timing loops for the call paths the core owns. `bench/build.sh /path/to/godot` runs them. |

## Use

Copy or submodule this repo next to your extension and import both packages:

```odin
package my_ext

import gde "../godot-odin/gdextension"
import "../godot-odin/godot"

@(export, link_name = "my_ext_init")
my_ext_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register)
}

Walker :: struct {
	speed: f64 `range:"0,10,0.1"`,
	steps: i64,
}

register :: proc() {
	c := godot.class(Walker, "Walker", "Resource")
	godot.fields(c, &Walker{speed = 1.5})              // struct fields become properties
	godot.method(c, "walk", walk, {"time"}, {1.0})    // arg names, then defaults

	m := godot.class(godot.Static, "WalkMath", "Object") // a class of static methods
	godot.method(m, "distance", distance, {"speed", "time"})
}

walk :: proc(self: ^Walker, time: f64) -> f64 {
	self.steps += 1
	return distance(self.speed, time)
}

distance :: proc "contextless" (speed, time: f64) -> f64 {
	return speed * time
}
```

Build it as a shared library and point a `.gdextension` file at it:

```sh
odin build my_ext -build-mode:shared -out:bin/libmy_ext.linux.x86_64.so
```

```ini
[configuration]
entry_symbol = "my_ext_init"
compatibility_minimum = "4.7"

[libraries]
linux.debug.x86_64 = "res://bin/libmy_ext.linux.x86_64.so"
linux.release.x86_64 = "res://bin/libmy_ext.linux.x86_64.so"
```

`example/` is the same thing complete. `example/build.sh /path/to/godot` builds it and runs its test.

## What the core does

- **Methods from typed procs.** The parameter and return types come from the proc's signature.
  A typed GDScript call reaches the proc by ptrcall, with no Variant boxing, at the cost of a call
  to an engine method of the same shape. An untyped call takes the Variant path, which checks and
  converts each argument and fills in defaults, about 5 ns over the engine's own (`bench/`).
- **Engine virtual overrides.** `godot.override_node_process(c, process)` makes `process` the
  class's `_process`. There is one generated `override_<class><virtual>` proc per engine virtual,
  so the override's signature is checked at compile time. The engine finds an override once per
  object, then calls it by ptrcall, about 5 ns over a node with no override. A GDScript `_process`
  costs about 41 ns over that node (`bench/`).
- **Vararg methods** (`godot.callable_call`, `godot.signal_emit`, `godot.object_call` and the
  rest). They take their fixed arguments, then `rest: ..Variant`, which the caller keeps and
  destroys. A Callable or Signal is handed to the engine in place, with no copy, so
  `godot.callable_call` is a little faster than GDScript's `Callable.call`. This relies on the
  engine's Variant layout, which the core checks when it loads.
- **Hot reload.** Set `reloadable = true` in the `.gdextension` file, and the editor reloads the
  library when it changes. Live instances get a fresh struct, and the engine sets their saved
  properties back.
- **Build on save** (`addons/odin_build/`). Copy it into your project's `addons/` and enable it.
  It watches the `.odin` files under `odin_build/watch_dir`. When one changes, it runs
  `odin_build/command` on a worker thread, prints the output in the Output panel, and reloads
  `odin_build/extension` after a good build. Set these under Project Settings.
- **Struct fields as properties** (`godot.fields`). They take these tags:
  - `range:"min,max,step"`, `hint:"..."`, `group:"..."` and `subgroup:"..."`;
  - `array:"Class"` for a typed array;
  - `class:"Name"` for an extension-class field;
  - `godot:"new"` to construct a fresh object per instance;
  - `godot:"-"` to keep a field off the engine.
  
  Defaults come from a template struct.
- **Properties from a getter and setter** (`godot.property`).
- **Enums and constants** (`godot.enumerate`, `godot.constant`). An Odin enum crosses as an
  engine enum.
- **Signals** (`godot.signal` and `godot.emit`).
- **Callables from Odin procs** (`godot.callable`), with bound arguments.
- **Instances of your own classes as arguments.** A method can take `^OtherClass`, as long as
  `OtherClass` registers before that method does.
- **Editor help from comments.** Run `tools/odin_docgen.py path/to/my_ext` to write
  `doc_classes.gen.xml` from the comments on your classes, fields and methods. Embed it, then
  pass it to `godot.entry`'s `docs` parameter.

## Another engine version or a custom build

```sh
tools/dump_api.sh /path/to/godot
```

This rewrites `api/` and every `gen_*` file. The generated code is plain and diffable, so a review
of the diff shows what changed in the engine's API.

## Prior art

[dresswithpockets/odin-godot](https://github.com/dresswithpockets/odin-godot) is the other Odin
binding. This one differs in three ways:

- it is generated from the interface JSON that Godot 4.6 and later dump, rather than from the C
  header;
- it needs no class preprocessor;
- it registers classes from plain structs and procs at runtime.

## License

MIT. See `LICENSE`.
