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
