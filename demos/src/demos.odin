// Four simulations that each run in Odin and, line for line, in GDScript (`project/*/sim.gd`), so
// a scene can switch between them and show what the same work costs in each. Every class is a
// RefCounted the scene steps once a frame and reads packed arrays back from.
package demos

import gde "../../gdextension"
import "../../godot"

@(export, link_name = "demos_init")
demos_init :: proc "c" (gpa: gde.InterfaceGetProcAddress, lib: gde.ClassLibraryPtr, init: ^gde.Initialization) -> gde.Bool {
	return godot.entry(gpa, lib, init, register)
}

register :: proc() {
	register_boids()
	register_sand()
	register_flow()
	register_terrain()
}

// Object's NOTIFICATION_PREDELETE: the object is about to be freed.
PREDELETE :: 1

// One step of xorshift32. The GDScript sims run the same generator, masked to 32 bits, so both
// draw the same numbers from the same seed. `s` must not be 0.
next_random :: #force_inline proc "contextless" (s: ^u32) -> u32 {
	x := s^
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	s^ = x
	return x
}

// A random float in [0, 1), from the top of the generator's range.
random_unit :: #force_inline proc "contextless" (s: ^u32) -> f64 {
	return f64(next_random(s)) / 4294967296.0
}

// `a` resized to `n` elements and its storage as a slice, for writing in place. The write makes
// the array unique first, so a copy the caller handed out earlier keeps its old contents.
floats_of :: proc "contextless" (a: ^godot.PackedFloat32Array, n: int) -> []f32 {
	if godot.packed_float32_array_size(a) != i64(n) { godot.packed_float32_array_resize(a, i64(n)) }
	if n == 0 { return nil }
	return ([^]f32)(gde.packed_float32_array_operator_index(a, 0))[:n]
}

bytes_of :: proc "contextless" (a: ^godot.PackedByteArray, n: int) -> []u8 {
	if godot.packed_byte_array_size(a) != i64(n) { godot.packed_byte_array_resize(a, i64(n)) }
	if n == 0 { return nil }
	return gde.packed_byte_array_operator_index(a, 0)[:n]
}

ints_of :: proc "contextless" (a: ^godot.PackedInt32Array, n: int) -> []i32 {
	if godot.packed_int32_array_size(a) != i64(n) { godot.packed_int32_array_resize(a, i64(n)) }
	if n == 0 { return nil }
	return ([^]i32)(gde.packed_int32_array_operator_index(a, 0))[:n]
}

vectors_of :: proc "contextless" (a: ^godot.PackedVector3Array, n: int) -> []godot.Vector3 {
	if godot.packed_vector3_array_size(a) != i64(n) { godot.packed_vector3_array_resize(a, i64(n)) }
	if n == 0 { return nil }
	return ([^]godot.Vector3)(gde.packed_vector3_array_operator_index(a, 0))[:n]
}

colors_of :: proc "contextless" (a: ^godot.PackedColorArray, n: int) -> []godot.Color {
	if godot.packed_color_array_size(a) != i64(n) { godot.packed_color_array_resize(a, i64(n)) }
	if n == 0 { return nil }
	return ([^]godot.Color)(gde.packed_color_array_operator_index(a, 0))[:n]
}

// Writes one 2D transform into a MultiMesh buffer at instance `i`: x axis (`ux`, `uy`), y axis its
// perpendicular, origin (`x`, `y`). The buffer's layout is the engine's, eight floats per instance.
put_transform :: #force_inline proc "contextless" (buf: []f32, i: int, ux, uy, x, y: f64) #no_bounds_check {
	o := i * 8
	buf[o + 0] = f32(ux)
	buf[o + 1] = f32(-uy)
	buf[o + 2] = 0
	buf[o + 3] = f32(x)
	buf[o + 4] = f32(uy)
	buf[o + 5] = f32(ux)
	buf[o + 6] = 0
	buf[o + 7] = f32(y)
}
