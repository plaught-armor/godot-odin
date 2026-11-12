// A minimal extension: one Resource class with typed fields, a method, a static class and a signal,
// and a Node that overrides engine virtuals. extras.odin has the rest of the class hooks.
package example

import gde "../../gdextension"
import "../../godot"

@(export, link_name = "example_init")
example_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register, unload_extras, editor = register_editor)
}

// A walker's tuning, shown in the inspector.
Walker :: struct {
	// Metres per second.
	speed:    f64 `range:"0,10,0.1"`,
	// Steps taken so far.
	steps:    i64,
	// Where the walker stands.
	position: godot.Vector3,
}

arrived: ^godot.StringName
walker_class: ^godot.Class(Walker)

// A node that counts the engine's calls into its virtual overrides.
Ticker :: struct {
	// Whether `_ready` ran.
	readied:  bool,
	// `_process` calls so far.
	ticks:    i64,
	// The keycode of the last key event `_input` received; 0 before one.
	last_key: i64,
}

register :: proc() {
	c := godot.class(Walker, "Walker", "Resource")
	walker_class = c
	godot.fields(c, &Walker{speed = 1.5})
	godot.method(c, "walk", walk, {"direction", "time"}, {1.0})
	arrived = godot.signal(c, "arrived", godot.Arg{name = "steps", type = .INT})

	t := godot.class(Ticker, "Ticker", "Node")
	godot.fields(t)
	godot.override_node_ready(t, ticker_ready)
	godot.override_node_process(t, ticker_process)
	godot.override_node_input(t, ticker_input)

	m := godot.class(godot.Static, "WalkMath", "Object")
	godot.method(m, "distance", distance, {"speed", "time"})
	godot.method(m, "apply", apply, {"f", "x"})
	godot.method(m, "call_float", call_float, {"target", "method", "x"})
	godot.method(m, "is_walker", is_walker, {"obj"})
	godot.method(m, "speed_of", speed_of, {"walker"})
	godot.method(m, "scratch", scratch, {"bytes"})
	godot.method(m, "temp_in_use", temp_in_use)

	register_extras()
}

// Moves the walker along `direction` (normalised by the caller) for `time` seconds at its speed,
// counts one step, and emits `arrived` with the step count. Answers the distance moved (m).
walk :: proc(self: ^Walker, direction: godot.Vector3, time: f64) -> f64 {
	d := distance(self.speed, time)
	self.position = {self.position.x + direction.x * f32(d), self.position.y + direction.y * f32(d), self.position.z + direction.z * f32(d)}
	self.steps += 1
	godot.emit(self, arrived, godot.variant(self.steps))
	return d
}

// Metres covered at `speed` (m/s) over `time` (s).
distance :: proc "contextless" (speed, time: f64) -> f64 {
	return speed * time
}

// Whether `obj` is a Walker, or a script that extends one.
is_walker :: proc(obj: godot.Object) -> bool {
	return godot.instance_of(obj, walker_class) != nil
}

// The walker's speed (m/s); -1 for null.
speed_of :: proc(walker: ^Walker) -> f64 {
	return -1 if walker == nil else walker.speed
}

// Takes `bytes` of temp memory and touches it; the call gives it back when it returns.
scratch :: proc(bytes: i64) -> i64 {
	buf := make([]u8, int(bytes), context.temp_allocator)
	buf[len(buf) - 1] = 1
	return i64(len(buf))
}

// Bytes of temp memory held now, between calls.
temp_in_use :: proc() -> i64 {
	return godot.temp_used()
}

ticker_ready :: proc(self: ^Ticker) {
	self.readied = true
}

ticker_process :: proc(self: ^Ticker, delta: f64) {
	self.ticks += 1
}

ticker_input :: proc(self: ^Ticker, event: godot.InputEvent) {
	if key := godot.cast_to(event, godot.InputEventKey); key != nil {
		self.last_key = i64(godot.input_event_key_get_keycode(key))
	}
}

// `f(x)` as a float, through Callable.call.
apply :: proc(f: godot.Callable, x: f64) -> f64 {
	f := f
	arg := godot.variant(x)
	r := godot.callable_call(&f, arg)
	defer gde.variant_destroy(&r)
	defer gde.variant_destroy(&arg)
	return godot.variant_float(&r)
}

// `target.method(x)` as a float, through Object.call.
call_float :: proc(target: godot.Object, method: godot.StringName, x: f64) -> f64 {
	arg := godot.variant(x)
	r := godot.object_call(target, method, arg)
	defer gde.variant_destroy(&r)
	defer gde.variant_destroy(&arg)
	return godot.variant_float(&r)
}
