#!/usr/bin/env python3

import sys
import re
import xml.etree.ElementTree as ET


TYPE_MAP = {
    "char": "u8",
    "CARD8": "u8",
    "CARD16": "u16",
    "CARD32": "u32",
    "CARD64": "u64",

    "INT8": "i8",
    "INT16": "i16",
    "INT32": "i32",
    "INT64": "i64",

    "BYTE": "u8",
    "BOOL": "bool",

    "FLOAT": "f32",
    "DOUBLE": "f64",
}


ZIG_KEYWORDS = {
    "addr",
    "align",
    "allowzero",
    "and",
    "anyframe",
    "anytype",
    "asm",
    "async",
    "await",
    "break",
    "callconv",
    "catch",
    "comptime",
    "const",
    "continue",
    "defer",
    "else",
    "enum",
    "errdefer",
    "error",
    "export",
    "extern",
    "false",
    "fn",
    "for",
    "frame",
    "if",
    "inline",
    "linksection",
    "noalias",
    "nosuspend",
    "opaque",
    "or",
    "orelse",
    "packed",
    "pub",
    "resume",
    "return",
    "struct",
    "suspend",
    "switch",
    "test",
    "threadlocal",
    "true",
    "try",
    "union",
    "unreachable",
    "usingnamespace",
    "var",
    "volatile",
    "while",
}


NAME_REPLACEMENTS = {
    "fid": "font",
    "wid": "window",
    "cid": "colormap",
    "gc": "graphics_context",
    "gcid": "graphics_context",
    "win": "window",
}


def convert_type(t):
    if t is None:
        return None

    return TYPE_MAP.get(t, t)


def q(s):
    return '"' + str(s).replace('"', '\\"') + '"'


def snake_case(name):
    if not name:
        return name

    name = NAME_REPLACEMENTS.get(
        name.lower(),
        name
    )

    name = re.sub(
        r"([a-z0-9])([A-Z])",
        r"\1_\2",
        name
    )

    name = re.sub(
        r"([A-Z]+)([A-Z][a-z])",
        r"\1_\2",
        name
    )

    name = name.lower()

    name = re.sub(
        r"[^a-z0-9_]",
        "_",
        name
    )

    name = re.sub(
        r"_+",
        "_",
        name
    )

    name = name.strip("_")

    if name == "align":
        name = "alignment"

    if name in ZIG_KEYWORDS:
        name = "@\"" + name + '"'

    return name


def normalize(obj):
    if isinstance(obj, list):
        return [
            normalize(x)
            for x in obj
        ]

    if isinstance(obj, dict):
        out = {}

        for key, value in obj.items():
            key = snake_case(key)

            if isinstance(value, str):
                value = snake_case(value)

            out[key] = normalize(value)

        return out

    return obj


def emit_value(value, level):
    if isinstance(value, bool):
        return "true" if value else "false"

    if isinstance(value, int):
        return str(value)

    if isinstance(value, str):
        return q(value)

    if isinstance(value, list):
        return emit_list(value, level)

    if isinstance(value, dict):
        return emit_object(value, level)

    return "null"


def compact_object(obj):
    if len(obj) > 3:
        return False

    for value in obj.values():
        if isinstance(value, (dict, list)):
            return False

    return True


def emit_object(obj, level):
    if compact_object(obj):
        values = []

        for key, value in obj.items():
            values.append(
                f".{key} = {emit_value(value, level)}"
            )

        return ".{ " + ", ".join(values) + " }"


    out = [".{"]

    for key, value in obj.items():
        out.append(
            "    " * (level + 1)
            + f".{key} = {emit_value(value, level + 1)},"
        )

    out.append(
        "    " * level
        + "}"
    )

    return "\n".join(out)


def emit_list(values, level):
    if not values:
        return ".{}"

    out = [".{"]

    for value in values:
        out.append(
            "    " * (level + 1)
            + emit_value(value, level + 1)
            + ","
        )

    out.append(
        "    " * level
        + "}"
    )

    return "\n".join(out)


def parse_fields(node):
    fields = []

    for child in node:

        if child.tag == "field":

            field = {
                "name": child.attrib.get("name"),
                "type": convert_type(
                    child.attrib.get("type")
                ),
            }

            if "enum" in child.attrib:
                field["enum"] = child.attrib["enum"]

            fields.append(field)


        elif child.tag == "pad":

            pad = {}

            if "bytes" in child.attrib:
                pad["pad"] = int(child.attrib["bytes"])

            if "align" in child.attrib:
                pad["alignment"] = int(child.attrib["align"])

            if pad:
                fields.append(pad)


        elif child.tag == "list":

            item = {
                "name": child.attrib.get("name"),
                "type": convert_type(
                    child.attrib.get("type")
                ),
                "list": True,
            }

            ref = child.find("fieldref")

            if ref is not None:
                item["fieldref"] = ref.text.strip()

            fields.append(item)
        
        elif child.tag == "switch":
            ref = child.find("fieldref")

            fields.append({
                "name": child.attrib["name"],
                "type": "u32",
                "list": True,
                "fieldref": ref.text.strip() if ref is not None else None,
            })

    return fields


def parse_enums(root):

    normal = []
    bitmasks = []
    all_enums = {}

    for enum in root.findall("enum"):

        fields = []
        is_bits = False

        for item in enum.findall("item"):

            value = None

            v = item.find("value")
            b = item.find("bit")

            if v is not None:
                value = int(v.text.strip())

            elif b is not None:
                is_bits = True
                value = 1 << int(b.text.strip())

            fields.append({
                "name": item.attrib["name"],
                "value": value,
            })

        result = {
            "name": enum.attrib["name"],
            "fields": fields,
        }

        all_enums[enum.attrib["name"]] = result

        if is_bits:
            bitmasks.append(result)
        else:
            normal.append(result)

    return all_enums, normal, bitmasks


def convert(path):

    root = ET.parse(path).getroot()

    enums, normal_enums, bitmasks = parse_enums(root)

    result = {
        "xids": [],
        "xidunions": [],
        "typedefs": [],
        "enums": normal_enums,
        "bitmasks": bitmasks,
        "structs": [],
        "unions": [],
        "requests": [],
        "replies": [],
        "events": [],
        "errors": [],
    }

    for node in root:

        if node.tag == "xidtype":

            result["xids"].append({
                "name": node.attrib["name"],
            })


        elif node.tag == "xidunion":

            result["xidunions"].append({
                "name": node.attrib["name"],
                "types": [
                    t.text.strip()
                    for t in node.findall("type")
                ],
            })


        elif node.tag == "typedef":

            result["typedefs"].append({
                "old": convert_type(
                    node.attrib["oldname"]
                ),
                "new": convert_type(
                    node.attrib["newname"]
                ),
            })


        elif node.tag == "struct":

            result["structs"].append({
                "name": node.attrib["name"],
                "fields": parse_fields(node),
            })


        elif node.tag == "union":

            result["unions"].append({
                "name": node.attrib["name"],
                "fields": parse_fields(node),
            })


        elif node.tag == "request":

            req = {
                "name": node.attrib["name"],
                "params": parse_fields(node),
            }

            reply = node.find("reply")

            if reply is not None:
                reply_name = snake_case(node.attrib["name"] + "Reply")

                req["returns"] = reply_name

                result["replies"].append({
                    "name": reply_name,
                    "fields": parse_fields(reply),
                })

            result["requests"].append(req)


        elif node.tag == "event":
            
            result["events"].append({
                "name": node.attrib["name"],
                "number": int(node.attrib["number"]),
                "fields": parse_fields(node),
            })


        elif node.tag == "eventcopy":

            ref = next(
                (
                    event
                    for event in result["events"]
                    if event["name"] == node.attrib["ref"]
                ),
                None
            )

            if ref is not None:
                result["events"].append({
                    "name": node.attrib["name"],
                    "number": int(node.attrib["number"]),
                    "fields": ref["fields"],
                })

        elif node.tag == "error":

            result["errors"].append({
                "name": node.attrib["name"],
                "fields": parse_fields(node),
            })


    return normalize(result)


def emit(data):

    out = [".{"]

    for key, value in data.items():

        out.append(
            "    "
            + f".{key} = "
            + emit_value(value, 1)
            + ","
        )

    out.append("}")

    return "\n".join(out)


if __name__ == "__main__":

    if len(sys.argv) != 3:
        print(
            "usage: python xcbxml_to_zon.py input.xml output.zon"
        )
        sys.exit(1)

    data = convert(sys.argv[1])

    with open(sys.argv[2], "w") as f:
        f.write(emit(data))