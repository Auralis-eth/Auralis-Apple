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

        chosen = {}
        order = []
        for entry in body:
            text = normalize(entry)
            if not text:
                continue
            key = dependency_key(text)
            if key not in chosen:
                chosen[key] = text
                order.append(key)
                continue
            changed = True
            # Same module named twice: keep the explicit `.product` spelling.
            if is_explicit(text) and not is_explicit(chosen[key]):
                chosen[key] = text

        kept = [chosen[key] for key in order]
        if kept != [normalize(entry) for entry in body if normalize(entry)]:
            changed = True

        out.append(line)
        for position, entry in enumerate(kept):
            suffix = "," if position < len(kept) - 1 else ""
            out.append(f"{indent}    {entry}{suffix}")
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
