# Getting started

This guide takes you from an empty folder to an extension that loads in the editor, rebuilds on
save and shows its own help pages. `example/` is the same thing finished, so keep it open beside
this guide.

- [What you need](#what-you-need)
- [Set up a project](#set-up-a-project)
- [The entry point](#the-entry-point)
- [Build and load it](#build-and-load-it)
- [Your first class](#your-first-class)
- [Call it from GDScript](#call-it-from-gdscript)
- [Call the engine from Odin](#call-the-engine-from-odin)
- [Memory and ownership](#memory-and-ownership)
- [Editor-only classes](#editor-only-classes)
- [Hot reload and build on save](#hot-reload-and-build-on-save)
- [Help pages from comments](#help-pages-from-comments)
- [The example, the benchmarks and the demos](#the-example-the-benchmarks-and-the-demos)
- [Another engine version](#another-engine-version)
- [Troubleshooting](#troubleshooting)

## What you need

- **Godot 4.7 or later**, the standard build (single-precision floats, 64-bit). The core uses
  interface functions that 4.7 added, so 4.6 will not load it.
- **Odin**, a recent `dev-` release.
- **Linux x86_64** is the tested platform. CI builds on Windows and macOS, but the library has
  not been loaded in Godot there, so treat them as untested. Elsewhere, change the library name and the
  `[libraries]` keys below to match your platform.

## Set up a project

Put this repo beside your extension's sources, as a copy or a git submodule. Then add a Godot
project to hold the built library:

```
my_game/
├── godot-odin/              this repo
├── src/                     your extension's Odin package
│   └── my_ext.odin
└── project/                 the Godot project
    ├── project.godot
    ├── my_ext.gdextension
    └── bin/                 the built library goes here
```

Your package imports two packages from the repo:

- `godot-odin/gdextension` is the raw C interface: function pointers and C types.
- `godot-odin/godot` is everything else: the builtin types, every engine class and its methods,
  and the core that registers your classes.

```odin
import gde "../godot-odin/gdextension"
import "../godot-odin/godot"
```

## The entry point

The engine loads the library and calls one exported C function. That function hands everything
to `godot.entry`:

```odin
package my_ext

import gde "../godot-odin/gdextension"
import "../godot-odin/godot"

@(export, link_name = "my_ext_init")
my_ext_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register)
}

register :: proc() {
	// Register classes here.
}
```

`godot.entry` takes these arguments:

| Argument | When it runs | What goes there |
|---|---|---|
| `register` | Once at load, at the scene level | Every class the game uses. |
| `unload` (optional) | At unload, before the classes go | Free whatever the library made: objects it constructed, memory it holds. |
| `docs` (optional) | At load, only in the editor | The help XML from `tools/odin_docgen.py`. See [Help pages](#help-pages-from-comments). |
| `editor` (optional) | At load, only in the editor | Classes only the editor uses, such as an EditorPlugin. See [Editor-only classes](#editor-only-classes). |

At unload the order is reversed: the editor classes go first, then the singletons, then `unload`
runs, then the game classes unregister in reverse order.

## Build and load it

Build a shared library into the project:

```sh
odin build src -build-mode:shared -out:project/bin/libmy_ext.linux.x86_64.so
```

Add `-debug` while you develop. For release builds, `-o:speed` is good, and `-o:aggressive` is
what the demos use. On their tight loops it was 6 to 12% faster than `-o:speed`.

Then tell the engine where the library is in `project/my_ext.gdextension`:

```ini
[configuration]
entry_symbol = "my_ext_init"
compatibility_minimum = "4.7"
reloadable = true

[libraries]
linux.debug.x86_64 = "res://bin/libmy_ext.linux.x86_64.so"
linux.release.x86_64 = "res://bin/libmy_ext.linux.x86_64.so"
```

`entry_symbol` must match the `link_name` of your exported proc. `reloadable = true` lets the
editor reload the library when it changes; see [Hot reload](#hot-reload-and-build-on-save).

Open the project once to import it. In 4.7 the very first `--import` of a fresh project can crash
at the end of its scan (see [Troubleshooting](#troubleshooting)). Run it again and it is fine.

## Your first class

A class is a plain Odin struct plus a `godot.class` call. Each instance carries one copy of the
struct, and the engine frees it with the object.

```odin
// A walker that counts its steps.
Walker :: struct {
	// Metres per second.
	speed: f64 `range:"0,10,0.1"`,
	steps: i64,
	// Odin-only scratch: not a property, never saved.
	trail: [dynamic]godot.Vector2 `godot:"-"`,
}

arrived: ^godot.StringName

register :: proc() {
	c := godot.class(Walker, "Walker", "Node")
	godot.fields(c, &Walker{speed = 1.5})           // fields become properties; the template sets defaults
	godot.method(c, "walk", walk, {"time"}, {1.0})  // parameter names, then defaults for the last ones
	arrived = godot.signal(c, "arrived", godot.Arg{name = "steps", type = .INT})
	godot.override_node_process(c, process)         // the class's _process
}

walk :: proc(self: ^Walker, time: f64) -> f64 {
	self.steps += 1
	godot.emit(self, arrived, godot.variant(self.steps))
	return self.speed * time
}

process :: proc(self: ^Walker, delta: f64) {
	walk(self, delta)
}
```

What each call does:

- **`godot.class(T, name, parent)`** registers `name` as a subclass of the engine class `parent`.
  The struct starts zeroed, or as the `fields` template sets it. An optional fourth argument
  receives the object's notifications. A fifth, `godot.Options(T){...}`, sets the extra hooks:
  dynamic properties, revert values, `_to_string` and runtime-only. See the
  [API outline](api.md#options).
- **`godot.fields(c, &template)`** makes every struct field a property, with a `get_<field>` and
  `set_<field>` method each, in field order. Tags change how a field shows. See
  [Field tags](api.md#field-tags).
- **`godot.method(c, name, proc, args, defaults)`** registers a method. If the proc's first
  parameter is `^Walker`, it is an instance method; otherwise it is static. The parameter and
  return types come from the signature.
- **`godot.signal` / `godot.emit`** register a signal and emit it.
- **`godot.override_<class>_<virtual>`** procs, one per engine virtual (`override_node_process`,
  `override_node_ready`, `override_node_input`...), make your proc the override. The compiler
  checks its signature.

Register a class before any method that takes it as a parameter (`^Walker`), and run
`godot.enumerate` before `fields` or `method` meets that enum.

A class that only holds static functions takes `godot.Static` as its type:

```odin
m := godot.class(godot.Static, "WalkMath", "Object")
godot.method(m, "distance", distance, {"speed", "time"})

distance :: proc "contextless" (speed, time: f64) -> f64 { return speed * time }
```

## Call it from GDScript

Once the library loads, the classes are ordinary engine classes:

```gdscript
var w := Walker.new()
add_child(w)
w.arrived.connect(func(steps: int): print("steps: ", steps))
print(w.walk(2.0))       # typed call: goes straight to the Odin proc
print(w.walk())          # leaves out `time`, so the default 1.0 fills it
print(WalkMath.distance(3.0, 4.0))
```

A typed GDScript call reaches the proc with no Variant boxing. An untyped call (a `Variant`
receiver, or `call("walk", ...)`) takes the Variant path, which checks and converts each argument
and fills in the defaults. Both work. The typed path is faster.

## Call the engine from Odin

Every engine class is a `distinct rawptr` (`godot.Node`, `godot.Resource`...). Its methods are
procs named `<class>_<method>`, and singletons are `<class>_singleton()`:

```odin
count := godot.node_get_child_count(node, false)
engine := godot.engine_singleton()
```

Methods take the class they were declared on, so pass a subclass with a cast:
`godot.node_get_child_count(godot.Node(my_node3d), false)`.

To get your struct from inside a method: `self` is the struct; `godot.object_of(self)` is its
engine object. Going the other way, `godot.instance_of(obj, c)` gives the struct behind an object
of class `c`, or nil. To check an engine class, `godot.cast_to(obj, godot.InputEventKey)` gives
the object typed as that class, or nil.

Vararg engine methods, such as `godot.object_call`, `godot.callable_call` and
`godot.signal_emit`, take their fixed arguments, then `..Variant`.

## Memory and ownership

Engine values such as `String`, `StringName`, `Array`, `Dictionary` and packed arrays are
reference counted inside the engine. Odin does not track them, so these rules say who destroys
what:

- **Method parameters are borrowed.** A `String` that a method receives belongs to the caller.
  Don't destroy it.
- **Method returns are handed over.** Return a new `String` (`godot.string_of("text")`) and the
  engine takes it.
- **Values you make, you destroy.** `godot.string_of`, a Variant from `godot.variant(x)`, the
  return of a vararg engine call: destroy each with `gde.variant_destroy(&v)`, or
  `godot.destroy[.STRING](&s)` and the like, unless you hand it on.
- **`emit` and `call_script` destroy the Variants you give them.** The vararg engine methods
  (`object_call`, `callable_call`) do not: you keep yours and destroy them.
- **RefCounted objects.** `godot.construct(T)` and `godot.make_instance(T)` give you one
  reference. Drop it with `godot.release(obj)`, or return it from a method to hand it over. Use
  `godot.share(self)` or `godot.share_object(obj)` to return an object you are keeping.
- **Object fields written from Odin** go through `godot.hold(&self.field, obj)`, which takes a
  reference and drops the old one, as a script's assignment does. `godot.hold_name` does the
  same for StringName fields.

**Temp memory is free to use.** Every call from the engine runs inside an `enter`/`leave` pair
that rolls the temp arena back when the call returns. So `fmt.tprintf` and
`context.temp_allocator` are safe inside any method, override or hook, with no cleanup. Don't
keep temp memory past the call.

**Threads.** The core assumes the engine's main thread. Debug builds assert each call arrives on
it.

## Editor-only classes

Some classes belong only in the editor: an EditorPlugin, an inspector plugin. Register them in
`entry`'s `editor` proc, which runs only when the editor loads the library:

```odin
return godot.entry(gpa, lib, init, register, editor = register_editor)

MyPlugin :: struct {}

register_editor :: proc() {
	p := godot.class(MyPlugin, "MyPlugin", "EditorPlugin")
	godot.override_editor_plugin_get_plugin_name(p, plugin_name)
	godot.editor_plugin(p)    // adds it to the editor; removed again at unload
}

plugin_name :: proc(self: ^MyPlugin) -> godot.String {
	return godot.string_of("Mine")
}
```

The opposite case is a class that must not run in the editor, as a script without `@tool`:
pass `godot.Options(T){runtime = true}` to `class`. In the editor its instances are placeholders.

## Hot reload and build on save

**Hot reload.** With `reloadable = true` in the `.gdextension` file, the editor reloads the
library whenever the file changes. Live instances get a fresh struct, and the engine sets their
saved properties back. Fields with `godot:"-"` start over as zero, since the engine never saw them.

**Build on save.** `addons/odin_build/` is an editor plugin that rebuilds the library when its
sources change:

1. Copy `addons/odin_build/` into your project's `addons/` folder.
2. Enable it under Project Settings, Plugins.
3. Set its three settings under Project Settings, General, `odin_build`:

| Setting | Default | Meaning |
|---|---|---|
| `odin_build/watch_dir` | `src` | The Odin sources to watch, relative to the project or absolute. |
| `odin_build/command` | `odin build src -build-mode:shared -out:bin/libextension.so` | The build, run by the shell in the project folder. |
| `odin_build/extension` | empty | The `.gdextension` to reload after a good build. Empty reloads none. |

When a `.odin` file changes, the plugin runs the command on a worker thread, prints the output
in the Output panel and, if the build succeeds, reloads the extension.

## Help pages from comments

The editor's help (F1, and the tooltips in the inspector) can show your own comments:

1. Write a comment above each class struct, field and registered proc.
2. Run `tools/odin_docgen.py src`. It writes `src/doc_classes.gen.xml`.
3. Embed the file and pass it to `entry`:

```odin
return godot.entry(gpa, lib, init, register, docs = #load("doc_classes.gen.xml", string))
```

Run the script again after you change the comments.

## The example, the benchmarks and the demos

Each folder has a `build.sh` that takes the path to a Godot binary:

| Command | What it does |
|---|---|
| `example/build.sh /path/to/godot` | Regenerates the example's help XML, builds `example/`, runs `test.gd` (which checks every feature of the core), then checks in the editor that the plugin loads with no errors and that hot reload keeps state. Prints `example: PASS`, `editor: PASS` and `reload: PASS`. |
| `bench/build.sh /path/to/godot` | Times the call paths the core owns against the engine's own: ptrcall, Variant calls, virtual overrides, object creation. |
| `demos/build.sh /path/to/godot` | Builds the demos, checks the Odin and GDScript versions give identical output, and times both. |
| `godot --path demos/project` | Runs the demo menu. |

`example/src/` is the best reference for real use. `example.odin` covers the basics, and
`extras.odin` covers the class hooks, flags, a typed Dictionary, script virtuals, a singleton, a
runtime-only class and an editor plugin.

## Another engine version

The bindings come from the engine's API dumps in `api/`. To match another engine version or a
custom build:

```sh
tools/dump_api.sh /path/to/godot
```

This dumps `api/` from that binary and regenerates `gdextension/` and every `godot/gen_*` file.
The generated code is plain, so the diff shows what changed in the engine's API.
`godot/gen_skipped.txt` lists anything the generator could not bind. It is empty for 4.7.

A double-precision engine build (`precision=double`) also needs `CONFIG` changed in
`tools/odin_bindgen.py`.

## Troubleshooting

**The first `--import` of a new project crashes.** This is a Godot 4.7 bug. It hits any extension
that registers a class, and godot-cpp extensions too. The import still writes
`.godot/extension_list.cfg`, and every later run is clean. The build scripts run the import once
and ignore its exit status.

**`godot_odin: this Odin type has no Variant type`.** A method parameter, return or field has a
type the engine cannot hold: a slice, a map, an Odin `string`. Use the engine type instead
(`godot.String`, `godot.Array`, a packed array), or tag the field `godot:"-"`.

**A field or parameter of my enum shows as a plain int.** Run `godot.enumerate(c, "Name", E)`
(or `enumerate_flags` for a `bit_set`) before the `fields` or `method` call that uses it.

**A method taking `^OtherClass` fails to register.** Register `OtherClass` first.

**Nothing loads, and the log says the entry symbol was not found.** The `entry_symbol` in the
`.gdextension` must equal the proc's `link_name`, and the proc needs `@(export)`.

**Changes don't show after a rebuild.** Set `reloadable = true`, or restart the editor. A running
game never reloads; restart it.
