#!/usr/bin/env python3
"""Report imports of a local Auralis module that the importing package cannot resolve.

SwiftPM resolves an import against the build products directory, so a stale `.build` can satisfy an
import that no manifest provides. The package then compiles locally and fails on a clean checkout --
which is exactly how two unused imports (`ArtifactCore` in the playbook tests, `AuralisPrimaryModels`
in the autopilot tests) survived in this repo. This reads only manifests and sources, so a stale
build directory cannot hide a missing dependency from it.

A module resolves from a package when it is one of that package's own targets, or a product vended
by a package it declares a path dependency on.

Exits non-zero when anything is unresolvable.
"""

import os
import re
import sys

LIBRARY_RE = re.compile(r'\.library\(\s*name:\s*"([A-Za-z_][A-Za-z0-9_]*)"')
TARGET_RE = re.compile(r'\.(?:testTarget|target)\(\s*name:\s*"([A-Za-z_][A-Za-z0-9_]*)"')
PATH_DEP_RE = re.compile(r'\.package\(\s*path:\s*"\.\./([A-Za-z_][A-Za-z0-9_]*)"')
IMPORT_RE = re.compile(
    r"^(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*import\s+([A-Za-z_][A-Za-z0-9_]*)\s*$"
)
VENDORED = {"CodeScanner"}


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def manifests():
    return sorted(
        name for name in os.listdir(".")
        if os.path.isfile(os.path.join(name, "Package.swift"))
    )


def main():
    packages = manifests()
    products = {p: set(LIBRARY_RE.findall(read(f"{p}/Package.swift"))) for p in packages}
    targets = {p: set(TARGET_RE.findall(read(f"{p}/Package.swift"))) for p in packages}

    # Only imports of modules some local package vends are in scope.
    local_modules = set()
    for names in products.values():
        local_modules |= names
    for names in targets.values():
        local_modules |= names

    status = 0
    for package in packages:
        if package in VENDORED:
            continue
        text = read(f"{package}/Package.swift")
        resolvable = set(targets[package])
        for dependency in PATH_DEP_RE.findall(text):
            resolvable |= products.get(dependency, set())

        for root in (f"{package}/Sources", f"{package}/Tests"):
            for base, dirs, names in os.walk(root):
                dirs[:] = [d for d in dirs if d != ".build"]
                for name in names:
                    if not name.endswith(".swift"):
                        continue
                    path = os.path.join(base, name)
                    for line in read(path).split("\n"):
                        match = IMPORT_RE.match(line)
                        if not match:
                            continue
                        module = match.group(1)
                        if module in local_modules and module not in resolvable:
                            print(f"{path}: imports '{module}', unresolvable from {package}")
                            status = 1

    if status == 0:
        print("All local-module imports resolve against a declared dependency.")
    return status


if __name__ == "__main__":
    sys.exit(main())
