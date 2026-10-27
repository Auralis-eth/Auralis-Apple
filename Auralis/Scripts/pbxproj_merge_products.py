#!/usr/bin/env python3
"""Collapse several Swift package products into one inside a project.pbxproj.

When a local package merges its targets into a single module, every Xcode target
that linked the old products must link the surviving one instead -- exactly once.
Leaving two `XCSwiftPackageProductDependency` entries that resolve to the same
product makes the target link it twice; leaving a reference to a product the
manifest no longer vends fails the build with "Missing package product".

The work is per-target, because each target owns its own `PBXBuildFile` for a
product. For a target that already links the surviving product, the old entries
are dropped. For one that does not, a single old entry is retargeted onto the
survivor and the rest are dropped.

Usage: pbxproj_merge_products.py <project.pbxproj> <new-product> <old,old,...>
"""

import re
import sys

PRODUCT_DEP_RE = re.compile(
    r"^\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{\n"
    r"\t\t\tisa = XCSwiftPackageProductDependency;\n"
    r"(\t\t\tpackage = ([0-9A-F]{24}) /\* (.+?) \*/;\n)?"
    r"\t\t\tproductName = (.+?);\n"
    r"\t\t\};\n",
    re.MULTILINE,
)

BUILD_FILE_RE = re.compile(
    r"^\t\t([0-9A-F]{24}) /\* (.+?) in Frameworks \*/ = \{isa = PBXBuildFile; "
    r"productRef = ([0-9A-F]{24}) /\* (.+?) \*/; \};\n",
    re.MULTILINE,
)

TARGET_RE = re.compile(
    r"^\t\t([0-9A-F]{24}) /\* (.+?) \*/ = \{\n\t\t\tisa = PBXNativeTarget;.*?^\t\t\};\n",
    re.MULTILINE | re.DOTALL,
)


def main():
    path, new_product, old_csv = sys.argv[1], sys.argv[2], sys.argv[3]
    old_products = set(old_csv.split(","))
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    # Map every product-dependency object to its product name and owning package.
    deps = {}
    for match in PRODUCT_DEP_RE.finditer(text):
        deps[match.group(1)] = {"name": match.group(6), "package": match.group(4)}

    old_dep_uuids = {uuid for uuid, info in deps.items() if info["name"] in old_products}
    new_dep_uuids = {uuid for uuid, info in deps.items() if info["name"] == new_product}
    if not old_dep_uuids:
        print("no matching product dependencies; nothing to do")
        return

    # Map build files to the product dependency they wrap.
    build_files = {}
    for match in BUILD_FILE_RE.finditer(text):
        build_files[match.group(1)] = match.group(3)

    package_ref = next(
        (deps[u]["package"] for u in sorted(old_dep_uuids | new_dep_uuids) if deps[u]["package"]),
        None,
    )

    # Choose one surviving product-dependency object, renaming an old one if needed.
    if new_dep_uuids:
        survivor = sorted(new_dep_uuids)[0]
        renamed = None
    else:
        survivor = sorted(old_dep_uuids)[0]
        renamed = survivor

    retired_deps = (old_dep_uuids | new_dep_uuids) - {survivor}
    retired_build_files = set()
    kept_build_file = {}

    # Per target: keep at most one build file / dependency entry for the survivor.
    def rewrite_target(match):
        block = match.group(0)
        uuids = re.findall(r"([0-9A-F]{24}) /\* .+? \*/,", block)
        touched = [u for u in uuids if u in old_dep_uuids or u in new_dep_uuids]
        if not touched:
            return block
        keep = survivor if survivor in touched else touched[0]
        kept_build_file[match.group(1)] = keep
        lines = []
        emitted = False
        for line in block.split("\n"):
            found = re.search(r"([0-9A-F]{24}) /\* (.+?) \*/,", line)
            if found and (found.group(1) in old_dep_uuids or found.group(1) in new_dep_uuids):
                if emitted:
                    continue
                emitted = True
                indent = line[: len(line) - len(line.lstrip())]
                lines.append(f"{indent}{keep} /* {new_product} */,")
                continue
            lines.append(line)
        return "\n".join(lines)

    text = TARGET_RE.sub(rewrite_target, text)

    # The surviving dependency per target implies which build file survives.
    survivors_per_target = set(kept_build_file.values())
    retired_deps = (old_dep_uuids | new_dep_uuids) - survivors_per_target

    def rewrite_frameworks(match):
        block = match.group(0)
        lines = []
        emitted = set()
        for line in block.split("\n"):
            found = re.search(r"([0-9A-F]{24}) /\* (.+?) in Frameworks \*/,", line)
            if not found:
                lines.append(line)
                continue
            product_ref = build_files.get(found.group(1))
            if product_ref not in old_dep_uuids and product_ref not in new_dep_uuids:
                lines.append(line)
                continue
            if product_ref in retired_deps:
                retired_build_files.add(found.group(1))
                continue
            if product_ref in emitted:
                retired_build_files.add(found.group(1))
                continue
            emitted.add(product_ref)
            indent = line[: len(line) - len(line.lstrip())]
            lines.append(f"{indent}{found.group(1)} /* {new_product} in Frameworks */,")
        return "\n".join(lines)

    text = re.sub(
        r"^\t\t[0-9A-F]{24} /\* Frameworks \*/ = \{\n\t\t\tisa = PBXFrameworksBuildPhase;.*?^\t\t\};\n",
        rewrite_frameworks,
        text,
        flags=re.MULTILINE | re.DOTALL,
    )

    # Drop the objects nothing references any more.
    def drop_dep(match):
        uuid = match.group(1)
        if uuid in retired_deps:
            return ""
        # Every surviving object must now name the merged product. A target that
        # linked only an old product keeps its own dependency object, so renaming
        # just the one reused object would leave the rest pointing at a product
        # the manifest no longer vends.
        if uuid in old_dep_uuids:
            pkg = match.group(3) or (
                f"\t\t\tpackage = {package_ref} /* XCLocalSwiftPackageReference */;\n"
                if package_ref
                else ""
            )
            return (
                f"\t\t{uuid} /* {new_product} */ = {{\n"
                f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
                f"{pkg}"
                f"\t\t\tproductName = {new_product};\n"
                f"\t\t}};\n"
            )
        return match.group(0)

    text = PRODUCT_DEP_RE.sub(drop_dep, text)

    def drop_build_file(match):
        if match.group(1) in retired_build_files:
            return ""
        if match.group(3) in old_dep_uuids or match.group(3) in new_dep_uuids:
            return (
                f"\t\t{match.group(1)} /* {new_product} in Frameworks */ = {{isa = PBXBuildFile; "
                f"productRef = {match.group(3)} /* {new_product} */; }};\n"
            )
        return match.group(0)

    text = BUILD_FILE_RE.sub(drop_build_file, text)

    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)

    print(f"survivor product dependency: {survivor} ({new_product})")
    print(f"retired {len(retired_deps)} product dependencies, {len(retired_build_files)} build files")


if __name__ == "__main__":
    main()
