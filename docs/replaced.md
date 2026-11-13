# Replaced builtin methods

`tools/odin_bindgen.py` leaves the builtin methods in its `REPLACED` set out of
`godot/gen_builtins.odin`. Each is defined instead in `godot/access.odin` under the same name and
signature, reading the String's storage in place, so callers see no change except speed.

Every replacement has a check in `example/project/test.gd` that compares it with the engine's own
method, called from GDScript, which does not go through these bindings: fixed edge cases plus a
seeded random run. When upgrading the engine, regenerate the bindings, run `example/build.sh`, and
update the "Checked against" column once it passes. A failure there means the engine changed the
method's behaviour, and the replacement must follow it or be dropped from `REPLACED`.

| Method | Replacement | Checked against | Engine call | Replacement |
|---|---|---|---|---|
| `String.find` | `string_find` | Godot 4.7-stable | 81 ns | 15 ns |

Timings are from `bench/build.sh`: a short word found in a 43-character sentence, the String
searched for already made.
