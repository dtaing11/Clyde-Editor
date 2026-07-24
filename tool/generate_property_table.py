#!/usr/bin/env python3
"""Generates lib/src/riv/riv_property_table.g.dart from rive-runtime.

The Rive runtime's CoreRegistry knows the serialized field type of every
core property key. Our editor-side parser needs the same table to skip
unknown properties safely. This script extracts it from the generated
C++ headers so it can be refreshed whenever rive-runtime updates.

Usage:
  python3 tool/generate_property_table.py [path-to-rive-runtime]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

FIELD_TYPES = {
    "CoreUintType": 0,
    "CoreStringType": 1,
    "CoreDoubleType": 2,
    "CoreColorType": 3,
    "CoreBytesType": 1,  # Bytes share the string field encoding.
    "CoreBoolType": 0,   # Bools are encoded as varuint bytes.
    "CoreCallbackType": -1,  # Not serialized.
}

def collect_property_keys(runtime: Path) -> dict[str, int]:
    """Maps 'ClassBase::somePropertyKey' -> numeric key."""
    keys: dict[str, int] = {}
    pattern = re.compile(
        r"static const uint16_t (\w+PropertyKey) = (\d+);")
    for header in (runtime / "include" / "rive").rglob("*_base.hpp"):
        class_match = re.search(r"class (\w+Base)\b", header.read_text())
        if not class_match:
            continue
        cls = class_match.group(1)
        for m in pattern.finditer(header.read_text()):
            keys[f"{cls}::{m.group(1)}"] = int(m.group(2))
    return keys


def parse_registry(runtime: Path, keys: dict[str, int]) -> dict[int, int]:
    """Parses CoreRegistry::propertyFieldId's switch statement."""
    text = (runtime / "include" / "rive" / "generated" /
            "core_registry.hpp").read_text()
    start = text.index("static int propertyFieldId(int propertyKey)")
    # The function ends at 'return -1;' + closing braces.
    end = text.index("return -1;", start)
    body = text[start:end]
    # Collapse line breaks inside qualified names split by clang-format.
    body = re.sub(r"::\s*\n\s*", "::", body)
    body = re.sub(r"(\w)\s*\n\s*(\w)", r"\1 \2", body)

    result: dict[int, int] = {}
    pending: list[str] = []
    token = re.compile(r"case (\w+Base::\w+PropertyKey):|return (\w+)::id;")
    for m in token.finditer(body):
        if m.group(1):
            pending.append(m.group(1))
        else:
            type_name = m.group(2)
            field_id = FIELD_TYPES[type_name]
            for name in pending:
                if name not in keys:
                    print(f"warning: unresolved {name}", file=sys.stderr)
                    continue
                if field_id >= 0:
                    result[keys[name]] = field_id
            pending = []
    return result


def emit_dart(table: dict[int, int]) -> str:
    lines = [
        "// GENERATED FILE - do not edit by hand.",
        "// Regenerate with: python3 tool/generate_property_table.py",
        "//",
        "// Field types of all core Rive property keys, extracted from",
        "// rive-runtime's CoreRegistry::propertyFieldId.",
        "// 0 = varuint, 1 = string/bytes, 2 = float32, 3 = color.",
        "",
        "const Map<int, int> rivCorePropertyFieldTypes = {",
    ]
    for key in sorted(table):
        lines.append(f"  {key}: {table[key]},")
    lines.append("};")
    return "\n".join(lines) + "\n"


def main() -> None:
    runtime = Path(sys.argv[1] if len(sys.argv) > 1
                   else Path.home() / "Documents" / "rive-runtime")
    if not runtime.exists():
        sys.exit(f"rive-runtime not found at {runtime}")
    keys = collect_property_keys(runtime)
    table = parse_registry(runtime, keys)
    out = Path(__file__).resolve().parent.parent / "lib" / "src" / "riv" / \
        "riv_property_table.g.dart"
    out.write_text(emit_dart(table))
    print(f"Wrote {len(table)} property keys to {out}")


if __name__ == "__main__":
    main()
