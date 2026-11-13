# Replaced builtin methods

`tools/odin_bindgen.py` leaves the builtin methods in its `REPLACED` set out of
`godot/gen_builtins.odin`. Each is defined instead in `godot/access.odin` under the same name and
signature, reading the String's storage in place, so callers see no change except speed.

Every replacement is checked in `example/project/test.gd` against the engine's own method, called
from GDScript, which does not go through these bindings: `_check_replaced_ops` and
`_check_replaced_strs` run every method in the table on fixed edge cases and on 3000 seeded random
Strings. When upgrading the engine,
regenerate the bindings, run `example/build.sh`, and update the "Checked against" column once it
passes. A failure there means the engine changed the method's behaviour, and the replacement must
follow it or be dropped from `REPLACED`.

| Method | Replacement | Checked against | Engine call | Replacement |
|---|---|---|---|---|
| `String.find` | `string_find` | Godot 4.7-stable | 75 ns | 12 ns |
| `String.rfind` | `string_rfind` | Godot 4.7-stable | 80 ns | 13 ns |
| `String.findn` | `string_findn` | Godot 4.7-stable | 700 ns | 19 ns |
| `String.rfindn` | `string_rfindn` | Godot 4.7-stable | | |
| `String.contains` | `string_contains` | Godot 4.7-stable | | |
| `String.containsn` | `string_containsn` | Godot 4.7-stable | | |
| `String.count` | `string_count` | Godot 4.7-stable | | |
| `String.countn` | `string_countn` | Godot 4.7-stable | | |
| `String.begins_with` | `string_begins_with` | Godot 4.7-stable | | |
| `String.ends_with` | `string_ends_with` | Godot 4.7-stable | | |
| `String.casecmp_to` | `string_casecmp_to` | Godot 4.7-stable | | |
| `String.nocasecmp_to` | `string_nocasecmp_to` | Godot 4.7-stable | 360 ns | 18 ns |
| `String.replace` | `string_replace` | Godot 4.7-stable | 109 ns | 37 ns |
| `String.replacen` | `string_replacen` | Godot 4.7-stable | | |
| `String.split` | `string_split` | Godot 4.7-stable | 235 ns | 144 ns |

Timings are from `bench/build.sh`, the argument Strings already made: a short word found in, or
replaced in, a 43-character sentence; an 11-character name compared in the other case; the
sentence split on spaces into nine Strings, which making those Strings dominates. Blank timings are not benched; the methods share the scans above.

## Vector2, Vector3 and Vector4

`REPLACED_TYPES` in `tools/odin_bindgen.py` leaves out every method and constructor of `Vector2`,
`Vector3` and `Vector4`. `godot/vector.odin` defines all 140 under the same names and signatures
as plain `f32` arithmetic that copies the engine's operation order, so results match bit for bit.
Checked against Godot 4.7-stable by `_check_replaced_vectors`, which calls every method from
GDScript and from `Bag.replaced_vectors` on edge cases (signed zeros, units, halves, infinities,
NaNs, tiny and huge values, normals that are not normalized, zero and normal lengths) and on 2000
seeded random cases, and compares the float bits.

| Method | Engine call | Replacement |
|---|---|---|
| `Vector3.length` | 2.9 ns | 1.1 ns |
| `Vector3.normalized` | 4.9 ns | 1.9 to 2.6 ns |
| `Vector3.dot` | 2.7 ns | 0.6 ns |
| `Vector3.lerp` | 3.5 ns | 0.6 ns |

Known differences from the engine, all deliberate:

- Error messages, such as a `slide` or `reflect` normal that is not normalized, are fixed text.
  The engine's message also prints the vector's value.
- A NaN result may carry a different sign bit. Which NaN survives an operation depends on operand
  order in the compiled code, so the test accepts any NaN for a NaN.

Two engine behaviours are copied on purpose: `Vector3.rotated` with an axis that is not normalized
reports the error and transforms by the identity Basis, so an infinite component yields NaN, and
`snapped` and `snappedf` divide in double precision.

When writing tests for these, note that GDScript pools equal constants: a literal `-0.0` in a
script that also uses `0.0` becomes `+0.0`. Build a negative zero at run time, as the test does.

## Vector2i, Vector3i and Vector4i

`REPLACED_TYPES` also leaves out every method and constructor of `Vector2i`, `Vector3i` and
`Vector4i`. `godot/vectori.odin` defines them under the same names and signatures with the
engine's `int32` semantics: components wrap, `int` arguments truncate to `int32`, and `length`,
`distance_to` and `aspect` take the engine's precision steps (`int64` squares, a `double` square
root, `float` division for `aspect`). Checked against Godot 4.7-stable by
`_check_replaced_vectorsi`, which compares every result from GDScript and from
`Bag.replaced_vectorsi` on edge cases (zero, `int32` limits, wrapping sums, out-of-range `int`
scalars, infinite, NaN and out-of-range float sources) and on 2000 seeded random cases.

| Method | Engine call | Replacement |
|---|---|---|
| `Vector3i.length` | 2.9 ns | 1.9 ns |
| `Vector3i.distance_squared_to` | 2.9 ns | 1.2 to 1.3 ns |
| `Vector3i.snapped` | 7.4 ns | 1.0 to 1.1 ns |

Float to `int32` conversion, in the constructors from float vectors and in `snapped`, follows the
x86-64 engine build: a value outside the `int32` range, or NaN, becomes `-2147483648`. Odin's own
conversion saturates or wraps instead, so `i_of_double` checks the range first.

## Color

The `Color` methods and constructors are all defined in `godot/color.odin` under the same names
and signatures: the constructors from floats, from another Color and from a String, the `to_*32`
and `to_*64` packings, `clamp`, `inverted`, `lerp`, `lightened`,
`darkened`, `blend`, `get_luminance`, `srgb_to_linear`, `linear_to_srgb`, `is_equal_approx`, `hex`,
`hex64`, `from_hsv`, `from_rgbe9995`, `from_rgba8`, `to_html`, `html`, `html_is_valid`,
`from_string` and `from_ok_hsl`. Each copies the engine's single-precision
operation order and its libm calls (`powf`, `fmodf`, `floorf`), so results match bit for bit.
Checked against Godot 4.7-stable by `_check_replaced_colors`, which compares every result from
GDScript and from `Bag.replaced_colors` on edge cases (signed zeros, values outside 0 to 1 and past
`int32` once scaled, infinities, NaNs, the sRGB thresholds, channels half a step from a byte,
transparent colors) and on 2000 seeded random cases. `_check_replaced_color_texts` does the same
for the String methods and `from_ok_hsl` against `Bag.replaced_color_texts`, on edge codes and names
and on 500 seeded random Strings and OkHSL inputs.

| Method | Engine call | Replacement |
|---|---|---|
| `Color.to_rgba32` | 7.5 ns | 1.2 ns |
| `Color.lerp` | 2.5 ns | 0.6 ns |
| `Color.linear_to_srgb` | 15.0 ns | 11.7 ns |
| `Color.from_hsv` | 12.8 ns | 2.4 ns |
| `Color.to_html` | 21.1 ns | 10.8 ns |
| `Color.from_string` | 172 ns | 77 ns |
| `Color.from_ok_hsl` | 116 ns | 105 ns |

The packings round each channel half away from zero as `roundf` does, but inline: within the
`int32` range the fraction `x - trunc(x)` is exact, and the result matches `roundf` on every one of
the 2^32 floats. Like the engine's x86-64 build, they convert through a 32-bit integer and keep the
low byte or word, so a channel outside 0 to 1 wraps instead of clamping, and a NaN, an infinity or
anything past the `int32` range packs as 0. `linear_to_srgb` keeps most of its cost because the
engine's `powf` call dominates it.

A NaN result may carry a different sign or payload than the engine's, so the test treats every
NaN as one value. `srgb_to_linear` depends on the last bit of the double constant
`1.0 / (1.0 + 0.055)`; the edge cases include 17700158, the least float where a one-bit change
shows.

`html` reads each digit as the engine's `_parse_col4` does, through a `char`, so only a
character's low byte counts: U+0130 reads as `0`, though `html_is_valid`, which tests whole
characters, rejects it. A valid first digit of a pair before an invalid second still gives a
positive value, as in the engine; only a negative component, or a digit count other than 3, 4, 6
or 8 after an optional `#`, is an error. Names are looked up as the engine does, without the
characters `" -_'."` and upper-cased by the engine's case table, so U+0131 and U+017F match `I`
and `S`; the table is the engine's `color_names.inc` with `_` removed, sorted for a binary search.
The errors the engine prints for an invalid code (`Invalid color code: ...`) or, from the String
constructors, an invalid name (`Invalid color name: ...`) are printed by the same methods here,
encoded to UTF-8 as the engine encodes them, and the result is then `Color()`; the test checks
that every message is printed as often by the replacements as by the engine. The benched name is
`"Dark Olive Green"`.

`from_ok_hsl` follows `thirdparty/misc/ok_color.h` operation for operation, with glibc's `cosf`,
`sinf` and `powf` as the engine imports them. The engine links its own `cbrtf`, FreeBSD's as musl
carries it (two Newton steps in double), not glibc's, so `godot/color.odin` carries the same one;
`fmin` and `fmax` follow the engine's inlined form, which returns the second argument when the
first is NaN. The constants the engine folds in single precision (`2 * pi`, `(1 + 0.206) / (1 +
0.03)`) are written by their bits. Its cost stays near the engine's because those libm calls
dominate it.

## RID

The `RID` methods and constructors are defined in `godot/rid.odin`: an RID is one 64-bit id, so
`is_valid` tests it against zero, `get_id` returns it, and the constructors give zero or a copy.
`_check_replaced_color_texts` checks them against the engine's on zero, one, -1 and the extremes
of `int64` and on random ids. They are not benched; each is a load and at most a compare.

## Basis

The `Basis` entries in `REPLACED`, and the constructors in `REPLACED_CONSTRUCTORS`, are defined in
`godot/basis.odin` under the same names and signatures: the constructors (empty, from a Basis, a
Quaternion, an axis and angle, three columns), `inverse`, `transposed`, `orthonormalized`,
`determinant`, `rotated`, `scaled`, `scaled_local`, `get_scale`, `get_euler`, `tdotx`, `tdoty`,
`tdotz`, `slerp`, `is_conformal`, `is_equal_approx`, `is_finite`, `is_orthonormal`,
`get_rotation_quaternion`, `looking_at`, `from_scale` and `from_euler`. Each follows
`core/math/basis.cpp` and `quaternion.cpp` of Godot 4.7-stable: the same single-precision
operation order, the same matrix product order in `from_euler`, the same branches and thresholds in
the six `get_euler` orders, and the one double step in `Quaternion::slerp`. Checked against Godot
4.7-stable by `_check_replaced_bases`, which compares every result from GDScript and from
`Bag.replaced_bases` on edge cases (the identity, zero and singular bases, rotations about one axis
that take the `get_euler` shortcuts, gimbal-locked and half-turn rotations, scaled and reflected
rotations, signed zeros, huge entries, infinities and NaNs, zero, parallel and unnormalized
vectors, every Euler order and invalid ones) and on 1500 seeded random cases. `Vector3.rotated`
now builds its rotation with the same `b_axis_angle` helper.

| Method | Engine call | Replacement |
|---|---|---|
| `Basis.inverse` | 6.6 ns | 1.8 ns |
| `Basis.rotated` | 16.7 ns | 4.4 ns |
| `Basis.get_euler` | 23 to 29 ns | 17.5 ns |
| `Basis.slerp` | 66 ns | 45 ns |

`get_euler` and `slerp` keep most of their cost in the libm calls (`atan2f`, `asinf`, `acosf`,
`sin`). The editor and debug builds of the engine compile with `MATH_CHECKS`, and the replacements
reproduce those checks: `inverse` of a singular basis prints an error and returns the basis
unchanged, `Basis(axis, angle)` with an unnormalized axis gives the identity, `slerp` between
bases that are not rotations prints an error and falls back the way the engine does, `looking_at`
with a zero target or up gives the identity, and an invalid Euler order prints an error and
returns the identity or a zero vector. The `Basis.x`, `y` and `z` fields in Odin are rows, as the
engine stores them; GDScript's `.x`, `.y` and `.z` are columns.

## Transform2D and Transform3D

The `Transform2D` and `Transform3D` entries in `REPLACED`, and their constructors in
`REPLACED_CONSTRUCTORS`, are defined in `godot/transform.odin` under the same names and
signatures. For Transform2D: the constructors (empty, from a Transform2D, a rotation and position,
a rotation, scale, skew and position, three columns), `inverse`, `affine_inverse`,
`get_rotation`, `get_origin`, `get_scale`, `get_skew`, `orthonormalized`, `rotated`,
`rotated_local`, `scaled`, `scaled_local`, `translated`, `translated_local`, `determinant`,
`basis_xform`, `basis_xform_inv`, `interpolate_with`, `is_conformal`, `is_equal_approx`,
`is_finite` and `looking_at`. For Transform3D: the constructors (empty, from a Transform3D, a
basis and origin, four columns, a Projection), `inverse`, `affine_inverse`, `orthonormalized`,
`rotated`, `rotated_local`, `scaled`, `scaled_local`, `translated`, `translated_local`,
`looking_at`, `interpolate_with`, `is_equal_approx` and `is_finite`. Each follows
`core/math/transform_2d.cpp` and `transform_3d.cpp` of Godot 4.7-stable with the same
single-precision operation order and libm calls, including `Math::acos`'s clamp in `get_skew` and
the two `fmodf` calls of `Math::lerp_angle`; the Transform3D methods reuse the Basis helpers in
`godot/basis.odin`. Checked against Godot 4.7-stable by `_check_replaced_transforms`, which
compares every result from GDScript and from `Bag.replaced_transforms2d` and
`Bag.replaced_transforms3d` on edge cases (the identity, zero and singular bases, exact rotations,
skewed, scaled and flipped bases, signed zeros including a determinant of -0, huge entries,
infinities and NaNs in the basis and the origin, columns whose normalized dot rounds past 1 and
-1 so the acos clamp applies, skews exactly PI apart, targets at or near the origin, colinear up
vectors) and on 1500 seeded random cases of each type.

| Method | Engine call | Replacement |
|---|---|---|
| `Transform2D.affine_inverse` | 3.9 ns | 0.8 ns |
| `Transform2D.interpolate_with` | 75 ns | 26 ns |
| `Transform3D.affine_inverse` | 9.5 ns | 1.8 ns |
| `Transform3D.interpolate_with` | 144 ns | 111 ns |

`Transform3D.interpolate_with` keeps most of its cost in two serial chains of square roots and
divisions, one per basis, as each is orthonormalized and turned into a quaternion, and in the
slerp's libm calls. Both chains are inlined so they run side by side, which also speeds up
`Basis.slerp`. The replacements reproduce the engine's `MATH_CHECKS`:
`affine_inverse` of a singular Transform2D prints an error and returns the transform unchanged,
that of a singular Transform3D prints an error, keeps the basis and still carries the origin
through it, and `Transform3D.looking_at` with a target approximately at the origin prints an
error and returns the identity. The Transform2D fields `x`, `y` and `origin` are the engine's
columns; the Transform3D basis keeps the engine's rows, as `Basis` does.

## Quaternion

The `Quaternion` methods and constructors are defined in `godot/quaternion.odin` under the same
names and signatures: the constructors (empty, from a Quaternion, a Basis, an axis and angle, the
shortest arc between two vectors, four components), `length`, `length_squared`, `normalized`,
`is_normalized`, `is_equal_approx`, `is_finite`, `inverse`, `log`, `exp`, `angle_to`, `dot`,
`slerp`, `slerpni`, `spherical_cubic_interpolate`, `spherical_cubic_interpolate_in_time`,
`get_euler`, `from_euler`, `get_axis` and `get_angle`. Each follows `core/math/quaternion.cpp` and
`quaternion.h` of Godot 4.7-stable with the same single-precision operation order and libm calls.
The engine's `CMP_EPSILON` is a double literal, so `get_axis`'s `1 - CMP_EPSILON` and `exp`'s
`theta < CMP_EPSILON` compare in double here too, and division by a length multiplies by its
reciprocal as the engine's `operator/` does. The spherical cubic first replaces each quaternion
by the rotation of its own basis, with the Basis helpers in `godot/basis.odin`, then makes the
engine's sign flips, including the `<= 0` test that applies only after the second flip. Checked
against Godot 4.7-stable by `_check_replaced_quaternions`, which compares every result from
GDScript and from `Bag.replaced_quaternions` on edge cases (the identity, zero, unnormalized and
opposite quaternions, signed zeros, huge components, infinities and NaNs, `w` a float either side
of `1 - CMP_EPSILON`, a vector part either side of `CMP_EPSILON`, dots a float either side of
`slerpni`'s 0.9999 and the shortest arc's `ALMOST_ONE`, parallel and opposite arcs along each axis,
every Euler order and invalid ones) and on 1500 seeded random cases.

| Method | Engine call | Replacement |
|---|---|---|
| `Quaternion.inverse` | 2.7 ns | 1.1 ns |
| `Quaternion.slerp` | 20 ns | 18 ns |
| `Quaternion.get_euler` | 23 ns | 20 ns |
| `Quaternion.spherical_cubic_interpolate` | 355 ns | 270 ns |

`slerp`, `get_euler` and the spherical cubic keep most of their cost in libm (`sinf`, `cosf`,
`acosf`, `atan2f`, `asinf`, and `sin` in double for `slerp`), so the gain is the call overhead and
the inlined Basis round trips. The replacements reproduce the engine's `MATH_CHECKS`: `inverse`,
`slerpni`, `exp`'s axis and both quaternion arguments of the spherical cubic print an error and give
the identity when not normalized, `get_euler` gives a zero vector, `Quaternion(axis, angle)` with an
unnormalized axis gives the identity, the shortest arc from or to a zero vector prints an error and
gives the identity, and an arc that cannot be normalized prints the engine's warning.

## Plane

The `Plane` methods and constructors are defined in `godot/plane.odin` under the same names and
signatures: the constructors (empty, from a Plane, a normal, a normal and distance, a normal and a
point, three points, four components), `normalized`, `get_center`, `is_equal_approx`, `is_finite`,
`is_point_over`, `distance_to`, `has_point`, `project`, `intersect_3`, `intersects_ray` and
`intersects_segment`. Each follows `core/math/plane.cpp` and `plane.h` of Godot 4.7-stable with the
same single-precision operation order. `normalized` divides the normal and the distance by the
normal's length, as the engine does, rather than multiplying by a reciprocal. The three-point
constructor takes the clockwise cross product and normalizes it as `Vector3::normalize` does. The
ray and segment tests compare against `CMP_EPSILON` and `1 + CMP_EPSILON` in single precision, and a
NaN distance passes them, as in the engine. The intersection methods return a Variant holding the
Vector3 found, written in place in the layout `check_borrow_layout` proves at load, or a nil
Variant when there is none. Checked against Godot 4.7-stable by `_check_replaced_planes`, which
compares every result from GDScript and from `Bag.replaced_planes` on edge cases (zero, unnormalized
and axis planes, signed zeros, huge and tiny components, infinities and NaNs, collinear and
coincident points, a ray start and a segment crossing a float either side of `CMP_EPSILON`,
`-CMP_EPSILON` and `1 + CMP_EPSILON`, denominators a float either side of `is_zero_approx`'s bound,
and a `has_point` tolerance equal to the distance and a float either side) and on 1500 seeded random
cases.

| Method | Engine call | Replacement |
|---|---|---|
| `Plane.distance_to` | 2.8 ns | 0.6 ns |
| `Plane.intersects_ray` | 5.0 ns | 1.4 ns |
| `Plane.intersect_3` | 7.0 ns | 2.3 ns |
| `Plane.normalized` | 14.5 ns | 1.7 ns |

The intersection replacements also skip the engine's Variant construction and assignment of the
result. `normalized` reproduces the engine's `MATH_CHECKS` warning for a non-finite plane, and the
three-point constructor the Vector3 warning for a normal that cannot be normalized.

## AABB

The `AABB` methods and constructors are defined in `godot/aabb.odin` under the same names and
signatures: the constructors (empty, from an AABB, from a position and a size), `abs`,
`get_center`, `get_volume`, `has_volume`, `has_surface`, `has_point`, `is_equal_approx`,
`is_finite`, `intersects`, `encloses`, `intersects_plane`, `intersection`, `merge`, `expand`,
`grow`, `get_support`, the longest and shortest axis, index and size, `get_endpoint`,
`intersects_segment` and `intersects_ray`. Each follows `core/math/aabb.cpp` and `aabb.h` of Godot
4.7-stable with the same single-precision operation order and the same comparisons, so ties and
NaNs fall the same way: the longest and shortest axis keep the first of equal sizes, the ray test
treats only an exact zero direction component as parallel and lets a later axis win a tie in entry
distance, and it sets the entry point exactly onto the face it crosses. `get_endpoint` reads its
index as the engine's 32-bit `int`. The segment and ray tests return a Variant holding the Vector3
found, written in place as the Plane intersections are, or a nil Variant when there is none; the
ray returns its start when it begins inside the box, as the engine's bind does. Checked against
Godot 4.7-stable by `_check_replaced_aabbs`, which compares every result from GDScript and from
`Bag.replaced_aabbs` on edge cases (empty, flat, negative-size, signed-zero, huge and tiny,
infinite and NaN boxes, touching and nested pairs, every endpoint index and ones out of range,
segments and rays along each axis from just outside each face, and ray directions with a
component as small as 1e-38), on 1500 seeded random cases with points often on a face, and on 500
rays aimed at a box corner, where the axes' entry distances tie.

| Method | Engine call | Replacement |
|---|---|---|
| `AABB.merge` | 4.1 ns | 1.0 ns |
| `AABB.intersects` | 3.1 ns | 1.9 ns |
| `AABB.intersects_plane` | 7.9 ns | 3.2 ns |
| `AABB.intersects_ray` | 11.9 ns | 5.1 ns |

The ray replacement also skips the engine's Variant construction and assignment of the result.
The error the engine prints under `MATH_CHECKS` for a negative size is printed by the same methods
here (once for a two-box method, whichever box is negative), as is `get_endpoint`'s error for an
index outside 0 to 7.

## Rect2 and Rect2i

The `Rect2` and `Rect2i` methods and constructors are defined in `godot/rect2.odin` under the same
names and signatures: the constructors (empty, from either rect type, from a position and a size,
from four numbers), `get_center`, `get_area`, `has_area`, `has_point`, `intersects`, `encloses`,
`intersection`, `merge`, `expand`, `grow`, `grow_side`, `grow_individual` and `abs`, and for
`Rect2` also `is_equal_approx`, `is_finite` and `get_support`. Each follows `core/math/rect2.h`,
`rect2.cpp`, `rect2i.h` and `rect2i.cpp` of Godot 4.7-stable with the same operation order and the
same comparisons. `Rect2` results match bit for bit, NaN and signed zero included: a point with a
NaN coordinate counts as inside, as in the engine, and `grow_individual` adds left and right
together before adding them to the width. `Rect2i` arithmetic wraps on 32-bit overflow, as the
engine's `int` arithmetic does on x86-64, and `get_center` halves the size with truncation toward
zero. Integer arguments keep only their low 32 bits, as the engine's `int` and `uint32_t`
parameters do, so a `grow_side` side outside 0 to 3 grows nothing. `Rect2i(Rect2)` converts each
component as x86-64's `cvttss2si` does: toward zero, and `INT32_MIN` for NaN or a value outside
the `int32` range. Checked against Godot 4.7-stable by `_check_replaced_rect2s` and
`_check_replaced_rect2is`, which compare every result from GDScript and from
`Bag.replaced_rect2s` and `Bag.replaced_rect2is` on edge cases (empty, flat, negative-size,
signed-zero, huge, infinite and NaN rects, `int32` limits that overflow, touching and nested
pairs, every side and ones out of range) and on 1500 seeded random cases for each type, with
points often on an edge.

| Method | Engine call | Replacement |
|---|---|---|
| `Rect2.has_point` | 2.7 ns | 1.1 ns |
| `Rect2.intersection` | 3.3 ns | 1.0 ns |
| `Rect2.merge` | 2.9 ns | 0.8 ns |
| `Rect2i.intersection` | 3.1 ns | 0.9 ns |

The error the engine prints under `MATH_CHECKS` for a negative size is printed by the same methods
here, once for a two-rect method, whichever rect is negative. `intersection` prints it through its
intersection test, as the engine's does.

## Projection

The `Projection` methods and constructors are defined in `godot/projection.odin` under the same
names and signatures: the constructors (identity, from a projection, from a `Transform3D`, from
four columns), the static `create_depth_correction`, `create_light_atlas_rect`,
`create_perspective`, `create_perspective_hmd`, `create_for_hmd`, `create_orthogonal`,
`create_orthogonal_aspect`, `create_frustum`, `create_frustum_aspect`, `create_fit_aabb` and
`get_fovy`, and `determinant`, `perspective_znear_adjusted`, `get_projection_plane`, `flipped_y`,
`jitter_offseted`, `get_z_far`, `get_z_near`, `get_aspect`, `get_fov`, `is_orthogonal`,
`get_viewport_half_extents`, `get_far_plane_half_extents`, `inverse`, `get_pixels_per_meter` and
`get_lod_multiplier`. Each follows `core/math/projection.cpp` and `projection.h` of Godot
4.7-stable with the same operation order, so results match bit for bit, NaN and signed zero
included. Where a double literal in the engine's code widens an expression to double (`/ 2.0`,
`* 0.5`, `1.0 /`, the double overload of `Math::deg_to_rad`), the replacement computes that step
in double too, and it calls the same libm functions: `sinf`, `cosf` and `atan2f` on floats, `tan`
and `atan` on doubles. Products such as `-2 * far * near` keep the engine's order, since the first
product can overflow on its own. Plane and eye indices keep only their low 32 bits, as the engine's
`int` parameters do: a plane outside the enum gives the zero plane, and an eye other than 1 or 2
gives the mono projection, or the identity from `create_for_hmd`.
`get_pixels_per_meter` truncates to `int` as x86-64's `cvttss2si` does. `inverse` runs the
engine's Gauss-Jordan elimination with the same pivot swaps and the same skipped zero entries,
holding each row as two four-lane values swapped by value rather than through row pointers, so
the rows stay in registers. Checked against Godot 4.7-stable by `_check_replaced_projections`,
which compares every result from GDScript and from `Bag.replaced_projections` on edge cases (the
identity, the zero matrix, perspective, orthogonal and asymmetric frustums, a permutation that
needs every pivot swap, matrices singular at each pivot, signed-zero, infinite, NaN and huge
entries, refused frustums, zero aspects and depth ranges, far planes and sizes that overflow in
one order of operations but not another, subnormal sizes, every plane and eye and ones out of
range, pixel widths beyond a C `int`) and on 1500 seeded random cases. One random case in five
takes most matrix entries from 0, -0, ±1 and ±2, so pivot candidates tie in magnitude.

| Method | Engine call | Replacement |
|---|---|---|
| `Projection.inverse` | 34.9 ns | 13.7 ns |
| `Projection.determinant` | 11.3 ns | 8.6 ns |
| `Projection.get_projection_plane` | 15.2 ns | 2.5 ns |
| `Projection.create_perspective` | 13.2 ns | 3.4 ns |

The errors the engine prints when it refuses a frustum (`p_right <= p_left`, `p_top <= p_bottom`,
`p_far <= p_near`) or meets a zero pivot in `inverse` (`0.0 == r0[0]` to `0.0 == r3[3]`) are
printed by the same methods here, and the result is then what the engine returns: the matrix as
it stood before the frustum was set, or the matrix itself for a singular inverse.

## Packed arrays

The reads of all ten packed array types are defined in `godot/packed.odin` under the same names
and signatures: `get`, `has`, `find`, `rfind`, `count` and `bsearch`. Each reads the array's
storage in place through `packed_read`, following `core/templates/vector.h` and `span.h` of Godot
4.7-stable: `find` and `rfind` count a negative `from` back from the end and answer -1 for a start
still outside the array, `has` is `find` from 0, and `bsearch` is the engine's bisection, before or
after the elements equal to the value. Elements compare as the engine's `==` and `<` do: floats by
IEEE rules, so -0 equals 0 and NaN equals nothing; vectors and Colors per component, a later
component deciding `<` only when the earlier ones are equal; Strings by character code. Arguments
are converted as the ptrcall converts them, so a byte array searched for 300 looks for 44, an
`int32` one keeps the low 32 bits, and a `float32` one rounds the double to float. `get` out of
range prints the engine's `Index p_index = ... is out of bounds (p_instance->size() = ...).` error
and returns the type's default: zero, an empty String, or opaque black for a Color, as `Color()`
is. A String result is a new reference the caller destroys.

The generated `size` and `is_empty` of the packed types read the element count from the storage
header, as the String `length` does. `check_packed_layout`, run at load, proves that header on a
shared array, a pushed one whose capacity differs from its size, and an emptied one; when it fails,
these and `packed_read` fall back to engine calls.

`find` and `rfind` test whole blocks of eight elements with no branch per element, so the
compares vectorize, and search the block holding a match one by one. Checked against Godot
4.7-stable by `_check_replaced_packed`, which compares every read of every type from GDScript and
from `Bag.replaced_packed`, the out-of-range errors included, on empty, sorted and unsorted arrays
holding repeats, NaN, -0 and the extremes; on values that hit, miss, or hit only after the ptrcall
conversion; on indices and starts either side of 0, of each end, and the `int64` extremes; on 600
seeded random sets, half of them of up to 40 elements with a value set at random places.

| Method | Engine call | Replacement |
|---|---|---|
| `PackedInt64Array.size` | 2.4 ns | 1.2 ns |
| `PackedInt64Array.get` | 1.8 ns | 1.4 ns |
| `PackedInt64Array.find` | 12.0 ns | 5.1 ns |
| `PackedStringArray.find` | 13.3 ns | 11.7 ns |

Timings are from `bench/build.sh`: `get` of element 40 and `find` of 40 in an array of 0 to 63,
and `find` of "12" in a PackedStringArray of "0" to "15".
