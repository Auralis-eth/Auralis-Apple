#!/usr/bin/env python3
"""Rewrite `import` lines when several modules collapse into one.

Used by the package-consolidation work. Matches whole import lines only, so a
merged module named `SwiftDataAdapters` never rewrites an `import SwiftData`.
After substitution each file is de-duplicated: a `@testable import X` wins over a
plain `import X`, and repeated identical imports collapse to the first one.

Usage: merge_module_imports.py <new-module> <old-module>[,<old-module>...] <root>...
       --strip <module> removes the import entirely (same-module callers)
"""

import os
import re
import sys

SKIP_DIRS = {".build", ".git", "DerivedData", "WalletConnectorDemo", "CodeScanner"}
IMPORT_RE = re.compile(r"^(@testable\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)\s*$")


def swift_files(roots):
    for root in roots:
        if os.path.isfile(root):
            yield root
            continue
        for base, dirs, names in os.walk(root):
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
            for name in names:
                if name.endswith(".swift"):
                    yield os.path.join(base, name)


def rewrite(path, new_module, old_modules, strip):
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    changed = False
    out = []
    for line in lines:
        match = IMPORT_RE.match(line)
        if not match:
            out.append(line)
            continue
        testable, module = match.group(1), match.group(2)
        if module not in old_modules:
            out.append(line)
            continue
        if strip:
            changed = True
            continue
        out.append(f"{testable or ''}import {new_module}")
        changed = True

    # Collapse duplicates produced by the substitution, preferring @testable.
    seen_plain = set()
    seen_testable = set()
    for line in out:
        match = IMPORT_RE.match(line)
        if not match:
            continue
        if match.group(1):
            seen_testable.add(match.group(2))
        else:
            seen_plain.add(match.group(2))

    deduped = []
    emitted = set()
    for line in out:
        match = IMPORT_RE.match(line)
        if not match:
            deduped.append(line)
            continue
        module = match.group(2)
        is_testable = bool(match.group(1))
        # Drop a plain import when the same file also imports the module @testable.
        if not is_testable and module in seen_testable:
            changed = True
            continue
        key = (module, is_testable)
        if key in emitted:
            changed = True
            continue
        emitted.add(key)
        deduped.append(line)

    if not changed:
        return False
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(deduped))
    return True


def main():
    args = sys.argv[1:]
    strip = False
    if "--strip" in args:
        strip = True
        args.remove("--strip")
    new_module, old_csv, roots = args[0], args[1], args[2:]
    old_modules = set(old_csv.split(","))

    count = 0
    for path in swift_files(roots):
        if rewrite(path, new_module, old_modules, strip):
            count += 1
            print(f"  {path}")
    print(f"rewrote {count} files")


if __name__ == "__main__":
    main()
