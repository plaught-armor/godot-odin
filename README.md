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
- **Platforms:** developed and tested on Linux x86_64. CI builds the core and the example on
  Windows and macOS too, but they are untested there: no one has loaded the library in Godot
  on either.
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
| `docs/` | Getting started, the API outline, how the core works. |
| `api/` | The API dumps the generated files come from. |
| `tools/odin_bindgen.py` | Regenerates `gdextension/` and `godot/gen_*` from `api/`. |
| `tools/dump_api.sh` | Dumps `api/` from a Godot binary, then runs the bindgen. |
| `tools/odin_docgen.py` | Turns a package's comments into class reference XML for the editor's help. |
| `example/` | A minimal extension, a project that loads it, and a test. |
| `addons/odin_build/` | An editor plugin that rebuilds and reloads the extension when its Odin sources change. |
| `bench/` | Timing loops for the call paths the core owns. `bench/build.sh /path/to/godot` runs them. |
| `demos/` | Four in-game demos, each one algorithm written twice, in Odin and in GDScript, switchable at runtime. |

## Quick start

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
}

walk :: proc(self: ^Walker, time: f64) -> f64 {
	self.steps += 1
	return self.speed * time
}
```

```sh
odin build my_ext -build-mode:shared -out:bin/libmy_ext.linux.x86_64.so
```

Point a `.gdextension` file at the library, and `Walker` is an engine class GDScript can use.
[Getting started](docs/getting-started.md) walks through the whole setup.

## Docs

| Doc | For |
|---|---|
| [Getting started](docs/getting-started.md) | Setting up a project, the entry point, building, your first class, ownership rules, editor classes, hot reload, build on save, help pages, troubleshooting. |
| [API outline](docs/api.md) | Every public proc grouped by job, field tags, and how Odin types map to engine types. |
| [How the core works](docs/internals.md) | The call paths and what they cost, the generated files, temp memory, unload order. |

## Features

- Classes from plain structs, methods from typed procs, properties from struct fields with tags
  for hints, groups, typed arrays and typed dictionaries.
- Typed GDScript calls reach the proc by ptrcall with no Variant boxing.
- Engine virtual overrides, checked against the virtual's signature at compile time.
- Enums, bitfields (`bit_set`), constants, signals, Callables from Odin procs.
- Class hooks: dynamic properties, revert values, property validation, `_to_string`,
  runtime-only classes.
- Virtuals that scripts override, engine singletons, editor plugins.
- Hot reload, a build-on-save editor plugin, and editor help pages from your comments.
- Errors and warnings logged with the Odin file and line.

## Demos

`demos/project` is a Godot project with four scenes behind a menu. Every scene runs one algorithm
in Odin (`demos/src`) and the same algorithm in GDScript, from the same seed and in the same
operation order, so the two produce identical output. Tab switches between them and the readout
shows the time each frame's work took.

```sh
demos/build.sh /path/to/godot   # builds the extension, then checks both backends match and times them
godot --path demos/project      # runs the menu
```

In every demo: Tab switches Odin/GDScript, R resets, Esc goes back to the menu (Esc there quits).

| Demo | What it exercises | Controls |
|---|---|---|
| Boids swarm | Float math in a tight loop: neighbours through a uniform grid | Up/Down double/halve the flock, left mouse pushes, right mouse pulls |
| Falling sand | Byte reads and writes over a 480 by 270 grid, every cell every frame | Left mouse paints, right mouse erases, 1-4 pick sand/water/wall/erase, wheel sets the radius, E toggles the emitters |
| Pathfinding swarm | Dijkstra over 37 000 cells with a heap, rebuilt while the target moves | Hold left mouse to drag the target, Up/Down double/halve the units |
| Procedural terrain | Fractal Perlin noise, normals and colours for up to 262 000 vertices | Right mouse drag orbits, wheel zooms, sliders rebuild, M morphs every frame |

What `demos/build.sh` measured here (`-o:aggressive`, output identical bit for bit on both sides):

| Demo | Work | Odin | GDScript | Ratio |
|---|---|---|---|---|
| Boids | 2000 boids, 60 steps | 14.8 ms | 381 ms | 26x |
| Falling sand | 120 steps | 14.0 ms | 3054 ms | 218x |
| Pathfinding | 4000 units, 120 steps | 18.8 ms | 1699 ms | 90x |
| Terrain | 256 by 256 vertices, 6 octaves | 4.14 ms | 340 ms | 82x |

## Another engine version or a custom build

`tools/dump_api.sh /path/to/godot` regenerates the bindings from that binary. See
[Getting started](docs/getting-started.md#another-engine-version).

## Prior art

[dresswithpockets/odin-godot](https://github.com/dresswithpockets/odin-godot) is the other Odin
binding. This one differs in three ways:

- it is generated from the interface JSON that Godot 4.6 and later dump, rather than from the C
  header;
- it needs no class preprocessor;
- it registers classes from plain structs and procs at runtime.

## License

MIT. See `LICENSE`.
