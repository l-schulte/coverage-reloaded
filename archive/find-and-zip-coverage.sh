PATTERNS=('coverage/**' 'packages/**/coverage/**' 'packages/**/**/coverage/**' "apps/**/coverage/**")
IGNORE_PATTERNS=('*/node_modules/*')

# Build the find command's ignore arguments
ignore_args=()
for ignore in "${IGNORE_PATTERNS[@]}"; do
    ignore_args+=(-not -path "$ignore")
done

lcov_count=0
for pattern in "${PATTERNS[@]}"; do
    lcov_count=$((lcov_count + $(find . -path "./$pattern" -name "lcov.info" "${ignore_args[@]}" | wc -l)))
done

if [ "$lcov_count" -eq 0 ]; then
    echo "Error: No lcov.info files found in any of the specified paths"
    exit 1
fi

zip_file="../coverage/$(date -d @$timestamp '+%Y-%m-%d')-$revision.zip"
zip -r "$zip_file" . -i "${PATTERNS[@]}" -x "${IGNORE_PATTERNS[@]}"