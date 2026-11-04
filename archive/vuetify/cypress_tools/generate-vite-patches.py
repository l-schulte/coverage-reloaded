#!/usr/bin/env python3
"""
Generate coverage-enabled patch files for Vite configs only.

This is a focused, well-tested script that handles the specific structure
of vuetify's vite.config.ts/js/mjs/mts files. It adds:
  1. An import for 'vite-plugin-istanbul'
  2. The istanbul plugin conditionally in the plugins array

Usage: python generate-vite-patches.py <config_dir>

  config_dir  — path to the cypress-coverage-configs directory
"""

import os
import sys
import hashlib
import re


def sha256_of(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()


def find_plugins_end(lines: list[str]) -> int:
    """Find the line index where the plugins array closes (']' or '],')."""
    depth = 0
    in_plugins = False
    for i, line in enumerate(lines):
        s = line.strip()
        if "plugins:" in s and "[" in s:
            in_plugins = True
            depth = s.count("[") - s.count("]")
            if depth <= 0:
                return i
            continue
        if in_plugins:
            depth += s.count("[") - s.count("]")
            if depth <= 0:
                return i
    return -1


def find_last_import_line(lines: list[str]) -> int:
    """Find the last import statement line index."""
    last = -1
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("import ") and "from" in s:
            last = i
    return last


def patch_vite_config(original: str) -> str | None:
    """Add vite-plugin-istanbul to a Vite config file."""
    if "vite-plugin-istanbul" in original:
        return None

    lines = original.split("\n")
    plugins_end = find_plugins_end(lines)
    last_import = find_last_import_line(lines)

    if plugins_end < 0 or last_import < 0:
        return None

    result = list(lines)

    # 1. Add istanbul import after the last import
    istanbul_import = "import istanbul from 'vite-plugin-istanbul'"
    result.insert(last_import + 1, "")
    result.insert(last_import + 2, "/**")
    result.insert(
        last_import + 3, " * Istanbul instrumentation for Cypress code coverage."
    )
    result.insert(
        last_import + 4,
        " * Only loaded when running under Cypress (process.env.CYPRESS is set).",
    )
    result.insert(
        last_import + 5, " * This instruments the source code with __coverage__ so that"
    )
    result.insert(last_import + 6, " * @cypress/code-coverage can collect it.")
    result.insert(last_import + 7, " */")
    result.insert(last_import + 8, istanbul_import)

    # Adjust plugins_end for the inserted lines
    plugins_end += 8  # We inserted 8 lines after last_import

    # 2. Add istanbul plugin before the closing of the plugins array
    indent = "      "  # 6 spaces
    istanbul_plugin = (
        f"{indent}// Instrument source code for Cypress code coverage collection\n"
        f"{indent}...(process.env.CYPRESS ? [istanbul({{\n"
        f"{indent}  cypress: true,\n"
        f"{indent}  requireEnv: false,\n"
        f"{indent}}}] : []),"
    )
    result.insert(plugins_end, istanbul_plugin)

    return "\n".join(result)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <config_dir>")
        sys.exit(1)

    config_dir = sys.argv[1]
    mapper_file = os.path.join(config_dir, "mapper.tsv")
    originals_dir = os.path.join(config_dir, "originals")
    patches_dir = os.path.join(config_dir, "patches")

    # Build hash -> content map from originals
    hash_to_content = {}
    if os.path.exists(originals_dir):
        for f in os.listdir(originals_dir):
            fp = os.path.join(originals_dir, f)
            if os.path.isfile(fp):
                with open(fp) as cf:
                    content = cf.read()
                ch = sha256_of(content)
                hash_to_content[ch] = content

    # Read existing patches
    existing_patches = set()
    if os.path.exists(patches_dir):
        for f in os.listdir(patches_dir):
            if f.endswith(".patch"):
                existing_patches.add(f.split("__")[0])

    with open(mapper_file) as f:
        lines = f.readlines()

    generated = 0
    skipped = 0
    errors = []

    for line in lines[1:]:
        parts = line.strip().split("\t")
        if len(parts) < 2:
            continue
        h, path = parts[0], parts[1]

        # Only handle vite configs
        if "vite.config" not in path:
            continue
        # Skip docs and vuetify-rollup
        if path.startswith("packages/docs/") or path.startswith(
            "packages/vuetify-rollup/"
        ):
            continue

        if h in existing_patches:
            skipped += 1
            continue

        original = hash_to_content.get(h)
        if original is None:
            errors.append(f"{h[:16]}  {path}  (no original)")
            continue

        patched = patch_vite_config(original)
        if patched is None:
            errors.append(f"{h[:16]}  {path}  (patch failed)")
            continue

        # Verify the patched content is valid
        if "vite-plugin-istanbul" not in patched:
            errors.append(f"{h[:16]}  {path}  (istanbul not found in output)")
            continue

        basename = os.path.basename(path)
        patch_filename = f"{h}__{basename}.patch"
        patch_path = os.path.join(patches_dir, patch_filename)

        with open(patch_path, "w") as f:
            f.write(patched)
            if not patched.endswith("\n"):
                f.write("\n")

        print(f"  [GEN] {patch_filename}")
        generated += 1

    print(f"\nDone: {generated} generated, {skipped} skipped (existing)")
    if errors:
        print(f"Errors ({len(errors)}):")
        for e in errors:
            print(f"  {e}")


if __name__ == "__main__":
    main()
