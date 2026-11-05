// A minimal extension: one Resource class with typed fields, a method, a static class and a signal.
package example

import gde "../../gdextension"
import "../../godot"

@(export, link_name = "example_init")
example_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register)
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

register :: proc() {
	c := godot.class(Walker, "Walker", "Resource")
	godot.fields(c, &Walker{speed = 1.5})
	godot.method(c, "walk", walk, {"direction", "time"}, {1.0})
	arrived = godot.signal(c, "arrived", godot.Arg{name = "steps", type = .INT})

	m := godot.class(godot.Static, "WalkMath", "Object")
	godot.method(m, "distance", distance, {"speed", "time"})
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
