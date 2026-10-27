#!/usr/bin/env python3
"""Remove duplicate entries from `dependencies:` arrays in a Package.swift.

Collapsing several products into one leaves a target depending on the same
product twice. SPM rejects that, and even where it does not the duplicate is
noise. Entries are compared by their text with whitespace and a trailing comma
stripped, so formatting differences do not hide a duplicate. Comma placement on
the surviving entries is rewritten so the last one in each array has none.

Usage: dedupe_manifest_dependencies.py <Package.swift>...
"""

import re
import sys

DEPENDENCIES_START = re.compile(r"^(\s*)dependencies:\s*\[\s*$")


BYNAME_RE = re.compile(r'^"([A-Za-z_][A-Za-z0-9_.]*)"$')
PRODUCT_RE = re.compile(r'^\.product\(\s*name:\s*"([A-Za-z_][A-Za-z0-9_.]*)"')
TARGET_RE = re.compile(r'^\.target\(\s*name:\s*"([A-Za-z_][A-Za-z0-9_.]*)"')


def normalize(line):
    return line.strip().rstrip(",").strip()


def dependency_key(entry):
    """Identify a dependency by the module it names, not by its spelling.

    `"Foo"` and `.product(name: "Foo", package: "Bar")` are the same dependency;
    SPM resolves a bare string against same-package targets *and* dependency
    products. Keying on text alone leaves that pair in place as a duplicate.
    """
    for pattern in (BYNAME_RE, PRODUCT_RE, TARGET_RE):
        match = pattern.match(entry)
        if match:
            return match.group(1)
    return entry


def is_explicit(entry):
    """Prefer `.product(name:package:)` over a bare string.

    A by-name dependency silently stops resolving when the product moves to
    another package, so the explicit spelling is the one worth keeping.
    """
    return bool(PRODUCT_RE.match(entry))


def dedupe(path):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    out = []
    index = 0
    changed = False

    while index < len(lines):
        line = lines[index]
        match = DEPENDENCIES_START.match(line)
        if not match:
            out.append(line)
            index += 1
            continue

        indent = match.group(1)
        closing = f"{indent}]"
        body = []
        cursor = index + 1
        depth = 0
        while cursor < len(lines):
            current = lines[cursor]
            stripped = current.strip()
            if depth == 0 and (stripped == "]" or stripped == "],"):
                break
            depth += current.count("[") + current.count("(")
            depth -= current.count("]") + current.count(")")
            body.append(current)
            cursor += 1

        if cursor >= len(lines):
            out.append(line)
            index += 1
            continue

        # Walk the array once, preserving order and any comment lines exactly where they sit. A
        # comment is not a dependency entry: treating it as one appends a stray comma to the prose
        # and can move it away from the entry it documents.
        kept = []
        seen = {}
        for entry in body:
            text = normalize(entry)
            if not text:
                continue
            if text.startswith("//"):
                kept.append(("comment", entry.rstrip()))
                continue
            key = dependency_key(text)
            if key not in seen:
                seen[key] = len(kept)
                kept.append(("entry", text))
                continue
            changed = True
            # Same module named twice: keep the explicit `.product` spelling.
            position = seen[key]
            if is_explicit(text) and not is_explicit(kept[position][1]):
                kept[position] = ("entry", text)

        out.append(line)
        last_entry = max(
            (position for position, (kind, _) in enumerate(kept) if kind == "entry"),
            default=-1,
        )
        for position, (kind, text) in enumerate(kept):
            if kind == "comment":
                out.append(text)
                continue
            suffix = "," if position < last_entry else ""
            out.append(f"{indent}    {text}{suffix}")
        out.append(lines[cursor])
        index = cursor + 1

    if not changed:
        return False
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(out))
    return True


if __name__ == "__main__":
    for target in sys.argv[1:]:
        if dedupe(target):
            print(f"deduped {target}")
