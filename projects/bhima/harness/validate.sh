COMMIT=$(git rev-parse HEAD)
LCOV=/coverage_reloaded/harness/output/lcov.info

test -f "$LCOV" || { echo "FATAL: lcov.info not produced"; exit 1; }

line_count=$(wc -l < "$LCOV")
echo "Line count: $line_count"
[ "$line_count" -lt 50 ] && { echo "FATAL: suspiciously small"; exit 1; }

sf_count=$(grep -c "^SF:" "$LCOV")
echo "Source files: $sf_count"
[ "$sf_count" -eq 0 ] && { echo "FATAL: no SF entries"; exit 1; }

echo "--- First 10 SF paths ---"
grep "^SF:" "$LCOV" | head -10

unresolvable=0
while IFS= read -r line; do
  path="${line#SF:}"
  [ -f "$path" ] || { echo "UNRESOLVABLE: $path"; unresolvable=$((unresolvable+1)); }
done < <(grep "^SF:" "$LCOV" | head -20)
echo "Unresolvable paths (sample of 20): $unresolvable"

da_nonzero=$(grep -c "^DA:.*,[1-9]" "$LCOV" || echo 0)
echo "Hit lines: $da_nonzero"
[ "$da_nonzero" -eq 0 ] && { echo "FATAL: all DA entries zero"; exit 1; }

echo "VALIDATION PASSED"