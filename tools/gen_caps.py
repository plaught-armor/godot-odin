#!/usr/bin/env python3
"""Writes godot/gen_caps.odin: the engine's case tables, for the case-insensitive String compares,
its upper and lower case letter ranges, for the methods that split words on a change of case, and
its identifier character ranges, for `is_valid_unicode_identifier`.

Usage: gen_caps.py <ucaps.h> <char_range.cpp> <out.odin> [<table name suffix>]
with both sources from core/string of the engine source at one release.

The tables differ between releases, so each release whose tables differ gets a file: gen_caps.odin
from Godot 4.7-stable, and gen_caps_48.odin with the suffix `_48` from 4.8, which added the pairs
of Unicode 18. godot/access.odin picks one by the engine's version at load.

The engine folds case through `caps_table` (to upper) and `reverse_caps_table` (to lower) in
core/string/ucaps.h, each a sorted list of character pairs searched by halving. The tables here are
the same pairs split into key and value arrays, so a search reads only keys.

The engine asks whether a character is an upper or a lower case letter of `uppercase_letter` and
`lowercase_letter` in core/string/char_range.cpp, each a sorted list of first and last characters.
The tables here are those ranges from 0x80 up as one sorted list of bounds, each range's first
character and then the one after its last, so a character is in a range when an odd number of
bounds are at or below it.

The engine asks whether a character may start or continue an identifier of `xid_start` and
`xid_continue` in the same file. The tables here are those ranges from 0x80 up as bounds in the
same way, with ranges that meet joined into one.
"""
import re
import sys


def table(source: str, name: str) -> list[tuple[int, int]]:
    match = re.search(name + r"\[\w+\]\[2\]\s*=\s*\{(.*?)\};", source, re.S)
    if match is None:
        sys.exit(f"gen_caps: no {name} in the header")
    pairs = [(int(a, 16), int(b, 16)) for a, b in re.findall(r"\{\s*(0x[0-9A-Fa-f]+)\s*,\s*(0x[0-9A-Fa-f]+)\s*\}", match.group(1))]
    keys = [a for a, _ in pairs]
    if keys != sorted(set(keys)):
        sys.exit(f"gen_caps: {name} keys are not sorted and unique")
    return pairs


def check_ascii(pairs: list[tuple[int, int]], shift: int, name: str) -> None:
    # The Odin side folds ASCII with arithmetic and searches only from 0x80, so the ASCII rows must
    # be exactly the 26 letters.
    ascii = [(a, b) for a, b in pairs if a < 0x80]
    first = ord("a") if shift < 0 else ord("A")
    want = [(first + i, first + i + shift) for i in range(26)]
    if ascii != want:
        sys.exit(f"gen_caps: {name} ASCII rows are not the 26 letters")


def bounds(source: str, name: str, first: str) -> list[int]:
    match = re.search(name + r"\[\w+\]\s*=\s*\{(.*?)\n\};", source, re.S)
    if match is None:
        sys.exit(f"gen_caps: no {name} in the source")
    ranges = [(int(a, 16), int(b, 16)) for a, b in re.findall(r"\{\s*(0x[0-9A-Fa-f]+)\s*,\s*(0x[0-9A-Fa-f]+)\s*\}", match.group(1))]
    # The Odin side tests ASCII by comparison and searches only from 0x80, so the ASCII rows must be
    # exactly the 26 letters.
    if [r for r in ranges if r[0] < 0x80] != [(ord(first), ord(first) + 25)]:
        sys.exit(f"gen_caps: {name} ASCII rows are not the 26 letters")
    flat = [v for a, b in ranges if a >= 0x80 for v in (a, b + 1)]
    # Strictly rising bounds mean the ranges are sorted, not empty, and neither meet nor overlap.
    if any(flat[i] >= flat[i + 1] for i in range(len(flat) - 1)):
        sys.exit(f"gen_caps: {name} ranges are not sorted and apart")
    return flat


def id_bounds(source: str, name: str, digits: bool) -> list[int]:
    match = re.search(name + r"\[\w+\]\s*=\s*\{(.*?)\n\};", source, re.S)
    if match is None:
        sys.exit(f"gen_caps: no {name} in the source")
    ranges = [(int(a, 16), int(b, 16)) for a, b in re.findall(r"\{\s*(0x[0-9A-Fa-f]+)\s*,\s*(0x[0-9A-Fa-f]+)\s*\}", match.group(1))]
    # The Odin side tests ASCII by comparison and searches only from 0x80, so the ASCII rows must be
    # exactly the letters and `_`, with the digits for the characters after the first.
    want = [(0x30, 0x39)] * digits + [(0x41, 0x5A), (0x5F, 0x5F), (0x61, 0x7A)]
    if [r for r in ranges if r[0] < 0x80] != want:
        sys.exit(f"gen_caps: {name} ASCII rows are not the letters and `_`")
    flat: list[int] = []
    for a, b in ranges:
        if a < 0x80:
            continue
        if flat and flat[-1] == a:
            flat[-1] = b + 1
        else:
            flat += [a, b + 1]
    # Strictly rising bounds mean the ranges are sorted, not empty, and do not overlap.
    if any(flat[i] >= flat[i + 1] for i in range(len(flat) - 1)):
        sys.exit(f"gen_caps: {name} ranges are not sorted and apart")
    return flat


def members(flat: list[int]) -> set[int]:
    return {c for i in range(0, len(flat), 2) for c in range(flat[i], flat[i + 1])}


def emit(out: list[str], name: str, values: list[int]) -> None:
    out.append(f"@(private, rodata)\n{name} := [{len(values)}]u32{{")
    for i in range(0, len(values), 12):
        out.append("\t" + " ".join(f"0x{v:05X}," for v in values[i:i + 12]))
    out.append("}\n")


def main() -> None:
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    suffix = sys.argv[4] if len(sys.argv) == 5 else ""
    source = open(sys.argv[1], encoding="utf-8").read()
    ranges = open(sys.argv[2], encoding="utf-8").read()
    upper = table(source, "caps_table")
    lower = table(source, "reverse_caps_table")
    check_ascii(upper, -32, "caps_table")
    check_ascii(lower, 32, "reverse_caps_table")
    # The Odin side trims the characters up to the space before it lowers them, which is the same
    # only when no other character lowers to one of those.
    if any(b <= 0x20 for _, b in lower):
        sys.exit("gen_caps: reverse_caps_table lowers a character to a space or a control character")
    letters_upper = bounds(ranges, "uppercase_letter", "A")
    letters_lower = bounds(ranges, "lowercase_letter", "a")
    # The Odin side gives a character one class, so no character may be in both tables.
    if members(letters_upper) & members(letters_lower):
        sys.exit("gen_caps: a character is both an upper and a lower case letter")
    out = ["// Generated by tools/gen_caps.py from the engine's core/string/ucaps.h and char_range.cpp. Do not edit.", "package godot", ""]
    for name, pairs in (("CAPS_UPPER", upper), ("CAPS_LOWER", lower)):
        rows = [(a, b) for a, b in pairs if a >= 0x80]
        emit(out, name + "_FROM" + suffix, [a for a, _ in rows])
        emit(out, name + "_TO" + suffix, [b for _, b in rows])
    emit(out, "LETTER_UPPER" + suffix, letters_upper)
    emit(out, "LETTER_LOWER" + suffix, letters_lower)
    emit(out, "XID_START" + suffix, id_bounds(ranges, "xid_start", False))
    emit(out, "XID_CONTINUE" + suffix, id_bounds(ranges, "xid_continue", True))
    open(sys.argv[3], "w", encoding="utf-8").write("\n".join(out))


main()
