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
| `String.replace` | `string_replace` | Godot 4.7-stable | 113 ns | 43 ns |
| `String.replacen` | `string_replacen` | Godot 4.7-stable | | |
| `String.split` | `string_split` | Godot 4.7-stable | 336 ns | 215 ns |

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

The `Color` entries in `REPLACED`, and the constructors in `REPLACED_CONSTRUCTORS`, are defined in
`godot/color.odin` under the same names and signatures: the constructors from floats and from
another Color, the `to_*32` and `to_*64` packings, `clamp`, `inverted`, `lerp`, `lightened`,
`darkened`, `blend`, `get_luminance`, `srgb_to_linear`, `linear_to_srgb`, `is_equal_approx`, `hex`,
`hex64`, `from_hsv`, `from_rgbe9995` and `from_rgba8`. Each copies the engine's single-precision
operation order and its libm calls (`powf`, `fmodf`, `floorf`), so results match bit for bit.
Checked against Godot 4.7-stable by `_check_replaced_colors`, which compares every result from
GDScript and from `Bag.replaced_colors` on edge cases (signed zeros, values outside 0 to 1 and past
`int32` once scaled, infinities, NaNs, the sRGB thresholds, channels half a step from a byte,
transparent colors) and on 2000 seeded random cases. The String methods (`to_html`, `html`,
`html_is_valid`, `from_string`, the String constructors) and `from_ok_hsl` still call the engine.

| Method | Engine call | Replacement |
|---|---|---|
| `Color.to_rgba32` | 7.5 ns | 1.2 ns |
| `Color.lerp` | 2.5 ns | 0.6 ns |
| `Color.linear_to_srgb` | 15.0 ns | 11.7 ns |
| `Color.from_hsv` | 12.8 ns | 2.4 ns |

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
