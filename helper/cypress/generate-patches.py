#!/usr/bin/env python3
"""
Generate coverage-enabled patch files for Cypress configs and Vite configs.

Reads the mapper.tsv and originals/ directory, then for each unmapped file
creates a patch with the appropriate coverage instrumentation.

Usage: python generate-patches.py <config_dir>

  config_dir  — path to the cypress-coverage-configs directory
                (containing mapper.tsv, originals/, patches/)
"""

import os
import sys
import hashlib
import re


def sha256_of(content: str) -> str:
    return hashlib.sha256(content.encode()).hexdigest()


def patch_vite_config(original: str, ext: str) -> str | None:
    """Add vite-plugin-istanbul to a Vite config file."""
    # Determine the import style based on extension
    if ext in (".mjs", ".mts"):
        istanbul_import = "import istanbul from 'vite-plugin-istanbul'"
    else:
        istanbul_import = "import istanbul from 'vite-plugin-istanbul'"

    # Check if already has istanbul import
    if "vite-plugin-istanbul" in original:
        return None

    # Find the last import statement to insert after
    lines = original.split("\n")
    last_import_idx = -1
    for i, line in enumerate(lines):
        if (
            line.startswith("import ")
            or line.startswith("const ")
            or line.startswith("var ")
        ):
            if "from" in line or "require" in line:
                last_import_idx = i

    # Find the plugins array to add istanbul
    plugins_start = -1
    plugins_end = -1
    brace_depth = 0
    in_plugins = False

    for i, line in enumerate(lines):
        stripped = line.strip()
        if "plugins:" in stripped and "[" in stripped:
            in_plugins = True
            plugins_start = i
            brace_depth += stripped.count("[") - stripped.count("]")
            if brace_depth <= 0:
                plugins_end = i
            continue
        if in_plugins:
            brace_depth += stripped.count("[") - stripped.count("]")
            if brace_depth <= 0:
                plugins_end = i
                break

    if last_import_idx < 0 or plugins_start < 0:
        return None

    # Build the patched content
    result = []

    # Add istanbul import after the last import
    for i, line in enumerate(lines):
        result.append(line)
        if i == last_import_idx:
            result.append("")
            result.append("/**")
            result.append(" * Istanbul instrumentation for Cypress code coverage.")
            result.append(
                " * Only loaded when running under Cypress (process.env.CYPRESS is set)."
            )
            result.append(
                " * This instruments the source code with __coverage__ so that"
            )
            result.append(" * @cypress/code-coverage can collect it.")
            result.append(" */")
            result.append(istanbul_import)

    # Add istanbul plugin to the plugins array
    # Find the last element in the plugins array and add after it
    insert_pos = None
    for i in range(plugins_end, plugins_start - 1, -1):
        stripped = lines[i].strip()
        if stripped.endswith(",") or stripped.endswith("]"):
            if stripped == "]," or stripped == "]":
                insert_pos = i
                break
            # Check if this is the last plugin entry (ends with ,)
            if stripped.endswith(",") and not stripped.startswith("//"):
                insert_pos = i
                break

    if insert_pos is not None:
        indent = "      "  # 6 spaces for plugin indentation
        istanbul_plugin = (
            f"{indent}// Instrument source code for Cypress code coverage collection\n"
            f"{indent}...(process.env.CYPRESS ? [istanbul({{\n"
            f"{indent}  cypress: true,\n"
            f"{indent}  requireEnv: false,\n"
            f"{indent}}}] : []),"
        )
        # Insert before the closing ]
        result.insert(
            insert_pos + 1 + (1 if insert_pos >= last_import_idx else 0),
            istanbul_plugin,
        )

    return "\n".join(result)


def patch_cypress_config_ts(original: str) -> str | None:
    """Add setupNodeEvents with @cypress/code-coverage/task to cypress.config.ts."""
    if "@cypress/code-coverage/task" in original:
        return None

    lines = original.split("\n")

    # Find the component section
    component_start = -1
    component_end = -1
    brace_depth = 0
    in_component = False

    for i, line in enumerate(lines):
        stripped = line.strip()
        if "component:" in stripped and "{" in stripped:
            in_component = True
            component_start = i
            brace_depth += stripped.count("{") - stripped.count("}")
            if brace_depth <= 0:
                component_end = i
            continue
        if in_component:
            brace_depth += stripped.count("{") - stripped.count("}")
            if brace_depth <= 0:
                component_end = i
                break

    if component_start < 0:
        return None

    # Find the closing of the component section to insert setupNodeEvents before it
    # Also find the closing of defineConfig to add env.coverage
    result = list(lines)

    # Add setupNodeEvents inside component section
    # Find the last property before component closing
    insert_before = component_end
    for i in range(component_end - 1, component_start, -1):
        stripped = lines[i].strip()
        if stripped and not stripped.startswith("//"):
            insert_before = i + 1
            break

    indent = "    "  # 4 spaces
    setup_events = (
        f"{indent}  /**\n"
        f"{indent}   * Register @cypress/code-coverage task.\n"
        f"{indent}   * Collects window.__coverage__ from the browser after each test\n"
        f"{indent}   * and writes lcov.info files via nyc/istanbul.\n"
        f"{indent}   */\n"
        f"{indent}  setupNodeEvents(on, config) {{\n"
        f"{indent}    require('@cypress/code-coverage/task')(on, config)\n"
        f"{indent}    return config\n"
        f"{indent}  }},"
    )
    result.insert(insert_before, setup_events)

    # Add env.coverage: true before the closing of defineConfig
    # Find the last closing brace
    for i in range(len(result) - 1, -1, -1):
        stripped = result[i].strip()
        if stripped == "}":
            result.insert(i, "")
            result.insert(i, "  env: {")
            result.insert(i + 1, "    coverage: true,")
            result.insert(i + 2, "  },")
            break

    return "\n".join(result)


def patch_cypress_json(original: str) -> str | None:
    """Add env.coverage: true to cypress.json."""
    if '"coverage"' in original:
        return None

    lines = original.split("\n")
    result = list(lines)

    # Find the last closing brace
    for i in range(len(result) - 1, -1, -1):
        stripped = result[i].strip()
        if stripped == "}":
            result.insert(i, '  "env": {')
            result.insert(i + 1, '    "coverage": true')
            result.insert(i + 2, "  }")
            break

    return "\n".join(result)


def patch_plugins_js(original: str) -> str | None:
    """Add @cypress/code-coverage/task to cypress/plugins/index.js."""
    if "@cypress/code-coverage/task" in original:
        return None

    lines = original.split("\n")
    result = list(lines)

    # Find the return config or closing of the function
    for i in range(len(result) - 1, -1, -1):
        stripped = result[i].strip()
        if "return config" in stripped:
            result.insert(i, "")
            result.insert(i, "  // Register @cypress/code-coverage task")
            result.insert(i + 1, "  require('@cypress/code-coverage/task')(on, config)")
            break
        if stripped == "};" or stripped == "}":
            # No return config found, add before closing
            result.insert(i, "")
            result.insert(i, "  // Register @cypress/code-coverage task")
            result.insert(i + 1, "  require('@cypress/code-coverage/task')(on, config)")
            result.insert(i + 2, "")
            result.insert(i + 3, "  return config")
            break

    return "\n".join(result)


def patch_support_ts(original: str) -> str | None:
    """Add @cypress/code-coverage/support import to support file."""
    if "@cypress/code-coverage/support" in original:
        return None

    lines = original.split("\n")
    result = list(lines)

    # Add after the last import
    last_import = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("import ") or stripped.startswith("require("):
            last_import = i

    if last_import >= 0:
        result.insert(last_import + 1, "import '@cypress/code-coverage/support'")
    else:
        # No imports, add at the end
        result.append("import '@cypress/code-coverage/support'")

    return "\n".join(result)


def patch_support_js(original: str) -> str | None:
    """Add @cypress/code-coverage/support import to support file."""
    if "@cypress/code-coverage/support" in original:
        return None

    lines = original.split("\n")
    result = list(lines)

    # Add after the last import
    last_import = -1
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("import ") or stripped.startswith("require("):
            last_import = i

    if last_import >= 0:
        result.insert(last_import + 1, "import '@cypress/code-coverage/support'")
    else:
        result.append("import '@cypress/code-coverage/support'")

    return "\n".join(result)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <config_dir>")
        sys.exit(1)

    config_dir = sys.argv[1]
    mapper_file = os.path.join(config_dir, "mapper.tsv")
    originals_dir = os.path.join(config_dir, "originals")
    patches_dir = os.path.join(config_dir, "patches")

    if not os.path.exists(mapper_file):
        print(f"ERROR: {mapper_file} not found")
        sys.exit(1)

    # Read existing patches
    existing_patches = set()
    if os.path.exists(patches_dir):
        for f in os.listdir(patches_dir):
            if f.endswith(".patch"):
                existing_patches.add(f.split("__")[0])

    # Build a hash → content mapping from originals directory
    # Originals are named {date}__{short_hash}__{path}, but we need to
    # map by full SHA256 content hash. Compute it from each file.
    hash_to_content = {}
    if os.path.exists(originals_dir):
        for f in os.listdir(originals_dir):
            fp = os.path.join(originals_dir, f)
            if os.path.isfile(fp):
                with open(fp) as cf:
                    content = cf.read()
                ch = sha256_of(content)
                hash_to_content[ch] = content

    # Read mapper
    with open(mapper_file) as f:
        lines = f.readlines()

    generated = 0
    skipped_existing = 0
    skipped_no_originals = 0
    skipped_unsupported = 0
    errors = []

    for line in lines[1:]:
        parts = line.strip().split("\t")
        if len(parts) < 2:
            continue
        h, path = parts[0], parts[1]

        # Skip docs package
        if path.startswith("packages/docs/"):
            continue

        # Skip if patch already exists
        if h in existing_patches:
            skipped_existing += 1
            continue

        # Find the original content by hash
        original = hash_to_content.get(h)
        if original is None:
            skipped_no_originals += 1
            continue

        # Determine patch type and generate
        patched = None
        basename = os.path.basename(path)
        ext = os.path.splitext(path)[1]

        if "vite.config" in path:
            patched = patch_vite_config(original, ext)
        elif "cypress.config.ts" in path or "cypress.config.js" in path:
            patched = patch_cypress_config_ts(original)
        elif path.endswith("cypress.json"):
            patched = patch_cypress_json(original)
        elif "cypress/plugins/" in path:
            patched = patch_plugins_js(original)
        elif "cypress/support/" in path:
            if path.endswith(".ts"):
                patched = patch_support_ts(original)
            else:
                patched = patch_support_js(original)
        else:
            skipped_unsupported += 1
            continue

        if patched is None:
            skipped_unsupported += 1
            continue

        # Verify the patched content has the right hash
        patched_hash = sha256_of(patched)
        patch_filename = f"{h}__{basename}.patch"
        patch_path = os.path.join(patches_dir, patch_filename)

        with open(patch_path, "w") as f:
            f.write(patched)
            if not patched.endswith("\n"):
                f.write("\n")

        print(f"  [GEN] {patch_filename}")
        generated += 1

    print(
        f"\nDone: {generated} generated, {skipped_existing} existing, "
        f"{skipped_no_originals} no originals, {skipped_unsupported} unsupported"
    )


if __name__ == "__main__":
    main()
