#!/usr/bin/env python3
"""Generate Dart data classes from the committed OpenAPI schema.

The Flutter app parses these responses by hand. That is fine code — it handles
things a generator would not, like telling a transport failure apart from an
answer — but it means every field name exists twice, in two languages, with
nothing connecting them. Rename ``answered_by`` in a Pydantic model and the
Dart side keeps compiling, keeps running, and silently reads null forever.

So the field names get a single source of truth. The schema is generated from
the app, the Dart models are generated from the schema, and CI regenerates both
and fails on a diff. A rename now has to touch three files in one commit, which
is the point: the drift becomes impossible to do quietly rather than merely
discouraged.

These are DTOs, deliberately. Nothing here calls the network, so the existing
hand-written service keeps its behaviour and can adopt the types where they
help.

    venv/bin/python tools/generate_dart_client.py
    venv/bin/python tools/generate_dart_client.py --check
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
SCHEMA = ROOT / "openapi.json"
OUT = REPO / "lib" / "services" / "generated" / "inventory_api.g.dart"

# FastAPI's own error envelopes; the client has no use for them as typed models.
SKIP = {"HTTPValidationError", "ValidationError"}


def camel(name: str) -> str:
    head, *rest = name.split("_")
    return head + "".join(p[:1].upper() + p[1:] for p in rest)


def _unwrap_nullable(schema: Dict[str, Any]) -> Tuple[Dict[str, Any], bool]:
    """Pydantic renders ``Optional[X]`` as ``anyOf: [X, null]``."""
    any_of = schema.get("anyOf")
    if not any_of:
        return schema, False
    non_null = [s for s in any_of if s.get("type") != "null"]
    nullable = len(non_null) != len(any_of)
    if len(non_null) == 1:
        return non_null[0], nullable
    # A genuine union of shapes has no useful Dart type but `dynamic`.
    return {}, True


def dart_type(schema: Dict[str, Any]) -> str:
    inner, _ = _unwrap_nullable(schema)
    if not inner:
        return "dynamic"

    ref = inner.get("$ref")
    if ref:
        return ref.rsplit("/", 1)[-1]

    kind = inner.get("type")
    if kind == "string":
        return "String"
    if kind == "integer":
        return "int"
    if kind == "number":
        return "double"
    if kind == "boolean":
        return "bool"
    if kind == "array":
        return f"List<{dart_type(inner.get('items', {}))}>"
    if kind == "object":
        return "Map<String, dynamic>"
    return "dynamic"


def _default_literal(value: Any, type_name: str) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list) and not value:
        return "const []"
    if isinstance(value, dict) and not value:
        return "const {}"
    return "null"


def _from_json_expr(key: str, type_name: str, nullable: bool, default: Any) -> str:
    """How one field is read out of a decoded JSON map."""
    src = f"json['{key}']"

    if type_name.startswith("List<"):
        element = type_name[5:-1]
        if element in ("String", "int", "double", "bool"):
            cast = f"($e as {element})"
        elif element == "Map<String, dynamic>":
            cast = "Map<String, dynamic>.from($e as Map)"
        elif element == "dynamic":
            cast = "$e"
        else:
            cast = f"{element}.fromJson(Map<String, dynamic>.from($e as Map))"
        body = (
            f"({src} as List<dynamic>?)"
            f"?.map((dynamic e) => {cast.replace('$e', 'e')}).toList()"
        )
        if not nullable or default is not None:
            body += f" ?? {_default_literal(default, type_name) if default is not None else 'const []'}"
        return body

    if type_name == "Map<String, dynamic>":
        body = f"{src} == null ? null : Map<String, dynamic>.from({src} as Map)"
        return body if nullable else f"({body}) ?? const {{}}"

    if type_name == "dynamic":
        return src

    if type_name in ("String", "int", "double", "bool"):
        # A required field with no default is non-nullable in Dart, so it must
        # be cast without the `?` — otherwise the generated code assigns a
        # `String?` to a `String` and does not compile. Letting that cast throw
        # on a malformed payload is correct: the contract says the field is
        # always present, and a silent empty string would hide the breach.
        if not nullable and default is None:
            return (
                f"({src} as num).toDouble()"
                if type_name == "double"
                else f"{src} as {type_name}"
            )
        # `num` covers JSON handing back an int where a double is declared,
        # which is what an untyped decode actually produces.
        cast = (
            f"({src} as num?)?.toDouble()"
            if type_name == "double"
            else f"{src} as {type_name}?"
        )
        fallback = _default_literal(default, type_name) if default is not None else None
        if fallback and fallback != "null":
            return f"{cast} ?? {fallback}"
        return cast

    # A referenced model.
    if not nullable and default is None:
        return f"{type_name}.fromJson(Map<String, dynamic>.from({src} as Map))"
    return (
        f"{src} == null ? null : "
        f"{type_name}.fromJson(Map<String, dynamic>.from({src} as Map))"
    )


def _to_json_expr(field: str, type_name: str, nullable: bool) -> str:
    """Serialise one field.

    Nullability is threaded through because Dart's analyzer rejects `?.` on a
    receiver that cannot be null — a generator that ignores it produces code
    that compiles with warnings, and warnings in generated code get ignored,
    which is how the real ones get missed.
    """
    access = "?." if nullable else "."
    _PASSTHROUGH = ("String", "int", "double", "bool", "dynamic", "Map<String, dynamic>")

    if type_name.startswith("List<"):
        element = type_name[5:-1]
        if element in _PASSTHROUGH:
            return field
        return f"{field}{access}map((e) => e.toJson()).toList()"
    if type_name in _PASSTHROUGH:
        return field
    return f"{field}{access}toJson()"


def render_class(name: str, schema: Dict[str, Any]) -> str:
    props: Dict[str, Any] = schema.get("properties", {})
    required = set(schema.get("required", []))

    fields: List[Tuple[str, str, str, bool, Any]] = []
    for key, prop in props.items():
        base_type = dart_type(prop)
        _, any_of_nullable = _unwrap_nullable(prop)
        default = prop.get("default")
        # Nullable unless the schema requires it and never admits null. A
        # default does not make a field non-nullable in Dart — it makes the
        # constructor parameter optional, which is a different thing.
        nullable = any_of_nullable or key not in required
        if default is not None and default != []:
            nullable = nullable and default is None
        if base_type.startswith("List<") and default == []:
            nullable = False
        if base_type == "Map<String, dynamic>" and default == {}:
            nullable = False
        if key in required and not any_of_nullable:
            nullable = False
        fields.append((key, camel(key), base_type, nullable, default))

    lines: List[str] = []
    title = schema.get("description") or f"`{name}` from the API contract."
    lines.append(f"/// {title.strip().splitlines()[0]}")
    lines.append(f"class {name} {{")

    for key, field, type_name, nullable, _ in fields:
        suffix = "?" if nullable else ""
        lines.append(f"  final {type_name}{suffix} {field};")
    lines.append("")

    lines.append(f"  const {name}({{")
    for key, field, type_name, nullable, default in fields:
        if not nullable and default is None:
            lines.append(f"    required this.{field},")
        elif default is not None and default != [] and default != {}:
            lines.append(f"    this.{field} = {_default_literal(default, type_name)},")
        elif not nullable:
            empty = "const {}" if type_name.startswith("Map<") else "const []"
            lines.append(f"    this.{field} = {empty},")
        else:
            lines.append(f"    this.{field},")
    lines.append("  });")
    lines.append("")

    lines.append(f"  factory {name}.fromJson(Map<String, dynamic> json) => {name}(")
    for key, field, type_name, nullable, default in fields:
        expr = _from_json_expr(key, type_name, nullable, default)
        lines.append(f"        {field}: {expr},")
    lines.append("      );")
    lines.append("")

    lines.append("  Map<String, dynamic> toJson() => <String, dynamic>{")
    for key, field, type_name, nullable, _ in fields:
        lines.append(f"        '{key}': {_to_json_expr(field, type_name, nullable)},")
    lines.append("      };")

    lines.append("")
    lines.append("  /// Every wire key this model reads, so a contract test can")
    lines.append("  /// assert the hand-written parser reads the same ones.")
    lines.append("  static const List<String> wireKeys = <String>[")
    for key, *_ in fields:
        lines.append(f"    '{key}',")
    lines.append("  ];")
    lines.append("}")
    return "\n".join(lines)


def render(schema: Dict[str, Any]) -> str:
    components = schema.get("components", {}).get("schemas", {})
    version = schema.get("info", {}).get("version", "0.0.0")

    header = f'''// GENERATED — DO NOT EDIT BY HAND.
//
// Source: rag_backend/openapi.json (API version {version})
// Regenerate: cd rag_backend && venv/bin/python tools/generate_dart_client.py
//
// These are data classes for the inventory agent API, generated so that the
// field names on the wire exist in exactly one place. CI regenerates this file
// and fails if the result differs from what is committed, which is what stops
// a field renamed on the server from becoming a silent null here.
//
// ignore_for_file: type=lint

'''

    body = [
        render_class(name, defn)
        for name, defn in sorted(components.items())
        if name not in SKIP
    ]
    return header + "\n\n".join(body) + "\n"


def main_cli() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if not SCHEMA.exists():
        print(f"{SCHEMA} is missing — run tools/export_openapi.py first.")
        return 1

    rendered = render(json.loads(SCHEMA.read_text()))

    if args.check:
        if not OUT.exists() or OUT.read_text() != rendered:
            print(
                f"{OUT.relative_to(REPO)} is out of date with openapi.json.\n"
                "Regenerate it and commit the result:\n"
                "    cd rag_backend && venv/bin/python tools/generate_dart_client.py"
            )
            return 1
        print(f"{OUT.name} matches the schema.")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(rendered)
    count = rendered.count("\nclass ")
    print(f"wrote {OUT.relative_to(REPO)} ({count} classes)")
    return 0


if __name__ == "__main__":
    sys.exit(main_cli())
