#!/usr/bin/env python3
"""Write bench/src/gen_replaced.odin: one engine-against-Odin timing pair for every builtin method
the bindings replace (odin_bindgen's REPLACED and REPLACED_TYPES) that bench/project/bench.gd has
no hand-written "Engine T.m call" row for.

    tools/bench_gen.py            # from the repository root

Each pair calls the method on the same sample value with the same arguments, once through the
engine's ptrcall and once through the Odin proc; bench.gd lists them from `replaced_count`.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import odin_bindgen as bg  # noqa: E402

# How many elements the sample packed arrays hold, and which one the searches look for.
PACKED_LEN = 64
PACKED_HIT = 40

# The value each method runs on, by type.
SELF = {
    "Vector2": "godot.Vector2{1.5, -2.25}",
    "Vector2i": "godot.Vector2i{7, -3}",
    "Vector3": "godot.Vector3{0.3, -1.2, 2.0}",
    "Vector3i": "godot.Vector3i{7, -3, 5}",
    "Vector4": "godot.Vector4{0.3, -1.2, 2.0, 0.7}",
    "Vector4i": "godot.Vector4i{7, -3, 5, 2}",
    "Rect2": "godot.Rect2{{1, 2}, {8, 6}}",
    "Rect2i": "godot.Rect2i{{1, 2}, {8, 6}}",
    "Transform2D": "godot.Transform2D{{0.8, 0.6}, {-0.6, 0.8}, {3, 4}}",
    "Plane": "godot.Plane{{0.48, 0.6, 0.64}, 1.5}",
    "Quaternion": "godot.Quaternion{0.5, 0.5, 0.5, 0.5}",
    "AABB": "godot.AABB{{-1, -2, -3}, {4, 5, 6}}",
    "Basis": "godot.Basis{{0.8, -0.6, 0}, {0.6, 0.8, 0}, {0, 0, 1}}",
    "Transform3D": "godot.Transform3D{{{0.8, -0.6, 0}, {0.6, 0.8, 0}, {0, 0, 1}}, {1, 2, 3}}",
    "Projection": "godot.projection_create_perspective(60, 1.5, 0.1, 100, false)",
    "Color": "godot.Color{0.2, 0.4, 0.6, 0.8}",
    "RID": "transmute(godot.RID)i64(42)",
}

# Element `i` of each sample packed array, ascending so bsearch has a sorted array, and the
# argument that names element PACKED_HIT.
PACKED = {
    "PackedByteArray": ("u8", "u8(i * 3)", f"i64({PACKED_HIT * 3})"),
    "PackedInt32Array": ("i32", "i32(i * 3)", f"i64({PACKED_HIT * 3})"),
    "PackedInt64Array": ("i64", "i64(i * 3)", f"i64({PACKED_HIT * 3})"),
    "PackedFloat32Array": ("f32", "f32(i) * 0.5", f"f64({PACKED_HIT * 0.5})"),
    "PackedFloat64Array": ("f64", "f64(i) * 0.5", f"f64({PACKED_HIT * 0.5})"),
    "PackedStringArray": ("godot.String", "godot.string_of(string([]u8{u8('a' + i / 8), u8('a' + i % 8)}))",
                          'godot.string_of("fa")'),
    "PackedVector2Array": ("godot.Vector2", "godot.Vector2{f32(i), 1}", f"godot.Vector2{{{PACKED_HIT}, 1}}"),
    "PackedVector3Array": ("godot.Vector3", "godot.Vector3{f32(i), 1, 2}", f"godot.Vector3{{{PACKED_HIT}, 1, 2}}"),
    "PackedVector4Array": ("godot.Vector4", "godot.Vector4{f32(i), 1, 2, 3}", f"godot.Vector4{{{PACKED_HIT}, 1, 2, 3}}"),
    "PackedColorArray": ("godot.Color", "godot.Color{f32(i), 0.5, 0.25, 1}", f"godot.Color{{{PACKED_HIT}, 0.5, 0.25, 1}}"),
}

FLOATS = {
    "min": -0.5, "max": 0.5, "angle": 0.7, "length": 1.0, "delta": 0.25, "step": 0.25, "mod": 0.75,
    "z_near": 0.1, "z_far": 100, "fovy": 60, "fovx": 60, "aspect": 1.5, "left": -1, "right": 1,
    "bottom": -1, "top": 1, "size": 2, "new_znear": 0.2, "intraocular_dist": 0.065,
    "convergence_dist": 1, "display_width": 0.14, "display_to_lens": 0.04, "oversample": 1.5,
    "tolerance": 0.001, "by": 0.5, "b_t": 1.0, "pre_a_t": -0.5, "post_b_t": 1.5,
}
INTS = {
    "min": -2, "max": 4, "step": 2, "index": PACKED_HIT, "from": 0, "idx": 3, "side": 1,
    "hex": 0x336699CC, "order": 2, "rgbe": 0x12345678, "r8": 51, "g8": 102, "b8": 153, "a8": 204,
    "eye": 1, "for_pixel_width": 1920, "plane": 2,
}
BOOLS = {"before": "true"}

# Vector arguments by position, the first of each a unit vector for the methods that want a
# normal or an axis.
BY_POSITION = {
    "Vector2": ["{0.6, 0.8}", "{0, 1}", "{-0.8, 0.6}", "{1, 2}"],
    "Vector3": ["{0.48, 0.6, 0.64}", "{0, 1, 0}", "{0.6, 0, -0.8}", "{1, 2, 3}"],
    "Vector4": ["{0.5, 0.5, 0.5, 0.5}", "{1, 0, 0, 0}", "{0, 0.6, 0.8, 0}", "{1, 2, 3, 4}"],
    "Vector2i": ["{2, 3}", "{5, 6}"],
    "Vector3i": ["{2, 3, 4}", "{5, 6, 7}"],
    "Vector4i": ["{2, 3, 4, 5}", "{5, 6, 7, 8}"],
}
WIDTH = {"Vector2": 2, "Vector3": 3, "Vector4": 4, "Vector2i": 2, "Vector3i": 3, "Vector4i": 4}
BY_NAME = {"min": (-0.5, -2), "max": (0.5, 4), "step": (0.25, 2), "modv": (0.75, 3)}
OTHER = {
    "Rect2": "godot.Rect2{{3, 4}, {8, 6}}",
    "Rect2i": "godot.Rect2i{{3, 4}, {8, 6}}",
    "AABB": "godot.AABB{{0, 0, 0}, {2, 2, 2}}",
    "Plane": "godot.Plane{{0, 1, 0}, -0.5}",
    "Quaternion": "godot.Quaternion{0.5, -0.5, 0.5, 0.5}",
    "Basis": "godot.Basis{{1, 0, 0}, {0, 0.8, -0.6}, {0, 0.6, 0.8}}",
    "Transform2D": "godot.Transform2D{{0.6, 0.8}, {-0.8, 0.6}, {1, 2}}",
    "Transform3D": "godot.Transform3D{{{1, 0, 0}, {0, 0.8, -0.6}, {0, 0.6, 0.8}}, {3, 2, 1}}",
    "String": 'godot.string_of("#336699cc")',
}
# Arguments the defaults would send somewhere dull: these make the segments cross.
OVERRIDE = {
    ("Plane", "intersects_segment", "to"): "godot.Vector3{3, 4, 5}",
    ("AABB", "intersects_segment", "from"): "godot.Vector3{-5, -5, -5}",
    ("AABB", "intersects_segment", "to"): "godot.Vector3{5, 5, 5}",
    ("PackedByteArray", "rfind", "from"): "i64(-1)",
}
for _p in PACKED:
    OVERRIDE[(_p, "rfind", "from")] = "i64(-1)"

ODIN_TYPE = {"float": "f64", "int": "i64", "bool": "bool"}


def odin_type(t):
    return ODIN_TYPE.get(t, "godot." + t)


def arg_value(btype, method, arg, position):
    t, name = arg["type"], arg["name"]
    if (btype, method, name) in OVERRIDE:
        return OVERRIDE[(btype, method, name)]
    if btype in PACKED and name == "value":
        return PACKED[btype][2]
    if t == "float":
        return f"f64({FLOATS.get(name, 0.35)})"
    if t == "int":
        return f"i64({INTS.get(name, 1)})"
    if t == "bool":
        return BOOLS.get(name, "false")
    if t in WIDTH:
        if name in BY_NAME:
            v = BY_NAME[name][t.endswith("i")]
            return f"godot.{t}{{{', '.join([str(v)] * WIDTH[t])}}}"
        values = BY_POSITION[t]
        return f"godot.{t}{values[min(position, len(values) - 1)]}"
    if t == "Color":
        return {"min": "godot.Color{0, 0, 0, 0}", "max": "godot.Color{1, 1, 1, 1}"}.get(name, "godot.Color{0.9, 0.1, 0.3, 1}")
    if t in OTHER:
        return OTHER[t]
    return None


def benched_by_hand():
    text = (ROOT / "bench/project/bench.gd").read_text()
    return set(re.findall(r'_report\("Engine ([A-Za-z0-9_]+)\.([A-Za-z0-9_]+)', text))


def pair(index, btype, m):
    """The proc timing one method both ways, or None when a type has no sample value."""
    name, args = m["name"], m.get("arguments", [])
    ret = m.get("return_type")
    static = m.get("is_static", False)
    if ret is None or (static and not args):
        return None
    values = [arg_value(btype, name, a, i) for i, a in enumerate(args)]
    if None in values or (not static and btype not in SELF and btype not in PACKED):
        return None
    out = [f"@(private = \"file\")\nrb_{index} :: proc(engine: bool, n: i64) -> f64 {{"]
    if static:
        self_ptr = "nil"
        out.append("\tref: ^" + odin_type(args[0]["type"]))
    elif btype in PACKED:
        elem, expr, _ = PACKED[btype]
        out.append(f"\tsrc: [{PACKED_LEN}]{elem}")
        out.append(f"\tfor i in 0 ..< {PACKED_LEN} {{ src[i] = {expr} }}")
        out.append("\tself_v := godot.packed_of(src[:])")
        out.append(f"\tdefer godot.{bg.snake(btype)}_destroy(&self_v)")
        if elem == "godot.String":
            out.append("\tdefer for &s in src { godot.string_destroy(&s) }")
        out.append("\tref := &self_v")
        self_ptr = "intrinsics.volatile_load(&ref)"
    else:
        out.append(f"\tself_v := {SELF[btype]}")
        out.append("\tref := &self_v")
        self_ptr = "intrinsics.volatile_load(&ref)"
    for i, (a, v) in enumerate(zip(args, values)):
        out.append(f"\ta{i}: {odin_type(a['type'])} = {v}")
        if a["type"] == "String":
            out.append(f"\tdefer godot.string_destroy(&a{i})")
        # Reread once, so the Odin side cannot fold a constant argument into the method.
        out.append(f"\ta{i} = intrinsics.volatile_load(&a{i})")
    if static:
        out.append("\tref = &a0")
    rt = odin_type(ret)
    drop = "\t\t\tgodot.string_destroy(&r)\n" if ret == "String" else ""
    ptrs = ", ".join(f"&a{i}" for i in range(len(args)))
    argv = "&args[0]" if args else "nil"
    out.append(f"\tsink: {rt}")
    out.append("\tstart: time.Tick")
    out.append("\tif engine {")
    out.append(f"\t\tfn := godot.builtin_method(.{bg.VARIANT_TYPE[btype]}, \"{name}\", {m['hash']})")
    out.append("\t\tstart = time.tick_now()")
    out.append("\t\tfor _ in 0 ..< n {")
    if args:
        out.append(f"\t\t\targs := [{len(args)}]gde.ConstTypePtr{{{ptrs}}}")
    out.append(f"\t\t\tr: {rt}")
    out.append(f"\t\t\tfn({self_ptr}, {argv}, &r, {len(args)})")
    out.append("\t\t\tintrinsics.volatile_store(&sink, r)")
    out.append(drop + "\t\t}")
    out.append("\t} else {")
    out.append("\t\tstart = time.tick_now()")
    out.append("\t\tfor _ in 0 ..< n {")
    call = [f"a{i}" for i in range(len(args))]
    if static:
        # A static method has no value to reread, so reach its first argument through a pointer
        # reread each round.
        call[0] = "intrinsics.volatile_load(&ref)^"
    else:
        call.insert(0, self_ptr)
    out.append(f"\t\t\tr := godot.{bg.snake(btype)}_{name}({', '.join(call)})")
    out.append("\t\t\tintrinsics.volatile_store(&sink, r)")
    out.append(drop + "\t\t}")
    out.append("\t}")
    out.append("\treturn f64(time.tick_since(start)) / f64(n)")
    out.append("}\n")
    return "\n".join(out)


def main():
    api = json.loads((ROOT / "api/extension_api.json").read_text())
    by_hand = benched_by_hand()
    procs, rows, skipped = [], [], []
    for b in api["builtin_classes"]:
        btype = b["name"]
        for m in b.get("methods", []):
            if not ((btype, m["name"]) in bg.REPLACED or btype in bg.REPLACED_TYPES):
                continue
            if (btype, m["name"]) in by_hand:
                continue
            text = pair(len(procs), btype, m)
            if text is None:
                skipped.append(f"{btype}.{m['name']}")
                continue
            rows.append(f'\t{{"{btype}.{m["name"]}", "{bg.snake(btype)}_{m["name"]}", rb_{len(procs)}}},')
            procs.append(text)
    head = (
        "// Generated by tools/bench_gen.py; do not edit. One engine-against-Odin timing pair for each\n"
        "// replaced builtin method bench.gd has no hand-written row for.\n"
        "package bench\n\n"
        'import "base:intrinsics"\nimport "core:time"\nimport gde "../../gdextension"\nimport "../../godot"\n\n'
        "// A replaced method, as the engine names it and as the bindings do, and the proc that times\n"
        "// `n` rounds of it through the engine's ptrcall or through the Odin proc.\n"
        "Replaced_Bench :: struct {\n\tengine: string,\n\todin:   string,\n\trun:    proc(engine: bool, n: i64) -> f64,\n}\n\n"
        "replaced_benches := [?]Replaced_Bench {\n" + "\n".join(rows) + "\n}\n\n"
    )
    (ROOT / "bench/src/gen_replaced.odin").write_text(head + "\n".join(procs))
    print(f"bench_gen: {len(procs)} pairs", file=sys.stderr)
    if skipped:
        print("bench_gen: no pair for " + " ".join(skipped), file=sys.stderr)


if __name__ == "__main__":
    main()
