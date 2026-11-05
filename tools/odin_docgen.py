#!/usr/bin/env python3
"""Generate the editor class reference for one Odin extension package from its source comments.

Reads every .odin file of the package directory <pkg>, finds each register proc's godot.class call, and writes the
descriptions of the class, its struct fields, its methods and its constants to
<pkg>/doc_classes.gen.xml. The library embeds that file and hands it to the editor's help
(godot.entry's `docs`), which merges each description by name onto the docs it generates from
ClassDB, so types and signatures come from the registration and only the prose comes from here.
Comment lines starting `WHY:` and a trailing ` WHY: ...` are left out: the marker is for a reader
of the source, not for a tooltip.

    tools/odin_docgen.py path/to/my_extension
"""
import pathlib
import re
import sys
from xml.sax.saxutils import escape, quoteattr

OUT = "doc_classes.gen.xml"

# `name :: value` or `name: type : value`; not a variable's `name: type`.
DECL = re.compile(r"^(\w+)\s*(?:::|:\s*[^:=]+:)\s*(struct|enum|proc|\S)")
FIELD = re.compile(r"^\t(\w+)\s*:\s*[^=]")
ENUM_VALUE = re.compile(r"^\t(\w+)\s*(=[^,]*)?,")
REGISTER = re.compile(r"^(register_\w+)\s*::\s*proc\(\)\s*\{")
CLASS = re.compile(r'godot\.class\(([\w.]+),\s*"(\w+)",\s*"(\w+)"')
METHOD = re.compile(r'godot\.method\(\w+,\s*"(\w+)",\s*(proc[^{]*\{\s*return (?:[\w.]+\()?(\w+)\)?\s*\}|\w+)')
CONSTANT = re.compile(r'godot\.constant\(\w+,\s*"(\w+)",\s*(\w+)\)')
ENUMERATE = re.compile(r'godot\.enumerate\(\w+,\s*"(\w+)",\s*(\w+)\)')


def prose(block):
    """One paragraph from comment lines: WHY lines and trailing WHY markers dropped, `x` as code."""
    kept = []
    for line in block:
        if line.startswith("WHY:"):
            continue
        kept.append(line.split(" WHY:")[0].strip())
    text = " ".join(t for t in kept if t)
    return re.sub(r"`([^`]+)`", r"[code]\1[/code]", text)


def parse(files):
    """Docs of top-level declarations, struct fields and enum values, and every register proc's body.
    An uncommented declaration on the line straight after another shares its doc, as a grouped
    comment over a run of constants means."""
    decls, fields, values, registers = {}, {}, {}, {}
    for path in files:
        lines = path.read_text().split("\n")
        block, inside, kind, body = [], None, None, None
        previous = None
        for line in lines:
            stripped = line.strip()
            if body is not None:
                if line.startswith("}"):
                    registers[inside] = body
                    body, inside = None, None
                else:
                    body.append(stripped)
                continue
            if inside is not None:
                if line.startswith("}"):
                    inside, kind, block = None, None, []
                    continue
                if stripped.startswith("//"):
                    block.append(stripped[2:].strip())
                    continue
                match = (FIELD if kind == "struct" else ENUM_VALUE).match(line)
                if match and 'godot:"-"' not in line:
                    (fields if kind == "struct" else values).setdefault(inside, {})[match.group(1)] = prose(block)
                block = []
                continue
            if stripped.startswith("//"):
                block.append(stripped[2:].strip())
                continue
            register = REGISTER.match(line)
            if register:
                decls[register.group(1)] = prose(block)
                inside, body, block = register.group(1), [], []
                continue
            decl = DECL.match(line)
            if decl:
                doc = prose(block)
                if not block and previous is not None:
                    doc = previous
                decls[decl.group(1)] = doc
                previous = doc
                if decl.group(2) in ("struct", "enum") and line.rstrip().endswith("{"):
                    inside, kind = decl.group(1), decl.group(2)
            else:
                previous = None
            block = []
    return decls, fields, values, registers


def class_xml(register, body, decls, fields, values):
    """The <class> element for the one class a register proc creates, or None when it creates none."""
    text = "\n".join(body)
    found = CLASS.search(text)
    if not found:
        return None
    struct, name, parent = found.groups()
    brief = decls.get(struct, "") if struct != "godot.Static" else decls.get(register, "")
    out = ["<class name=%s inherits=%s>" % (quoteattr(name), quoteattr(parent))]
    out.append("\t<brief_description>%s</brief_description>" % escape(brief))
    out.append("\t<description></description>")
    methods = [(m.group(1), decls.get(m.group(3) or m.group(2), "")) for m in METHOD.finditer(text)]
    out.append("\t<methods>")
    for method, doc in methods:
        out.append("\t\t<method name=%s>\n\t\t\t<description>%s</description>\n\t\t</method>" % (quoteattr(method), escape(doc)))
    out.append("\t</methods>")
    if "godot.fields(" in text:
        out.append("\t<members>")
        for field, doc in fields.get(struct, {}).items():
            out.append("\t\t<member name=%s type=\"\">%s</member>" % (quoteattr(field), escape(doc)))
        out.append("\t</members>")
    out.append("\t<constants>")
    for constant in CONSTANT.finditer(text):
        doc = decls.get(constant.group(2), "")
        out.append("\t\t<constant name=%s value=\"0\">%s</constant>" % (quoteattr(constant.group(1)), escape(doc)))
    for enum in ENUMERATE.finditer(text):
        for value, doc in values.get(enum.group(2), {}).items():
            out.append("\t\t<constant name=%s value=\"0\" enum=%s>%s</constant>" % (quoteattr(value), quoteattr(enum.group(1)), escape(doc)))
    out.append("\t</constants>")
    out.append("</class>")
    return "\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: tools/odin_docgen.py <package>")
    package = pathlib.Path(sys.argv[1]).resolve()
    files = sorted(package.glob("*.odin"))
    if not files:
        sys.exit("odin_docgen: no .odin files in %s" % package)
    decls, fields, values, registers = parse(files)
    classes = [class_xml(r, b, decls, fields, values) for r, b in sorted(registers.items())]
    xml = '<?xml version="1.0" encoding="UTF-8" ?>\n' + "\n".join(c for c in classes if c) + "\n"
    (package / OUT).write_text(xml)
    print("odin_docgen: %s, %d classes" % (package / OUT, sum(1 for c in classes if c)))


main()
