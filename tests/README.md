# Test Suite

This directory contains tests for the coverage_reloaded project.

## Running Tests

To run all tests:
```bash
pytest tests/
```

To run tests with verbose output:
```bash
pytest tests/ -v
```

To run a specific test file:
```bash
pytest tests/test_parse_version.py -v
```

## Adding New Test Cases

The tests are designed to be easily extendable. To add new test cases:

### For `__npm_satisfies`

Add new tuples to the `test_cases` list in the `TestNpmSatisfies` class:

```python
test_cases = [
    # ... existing test cases ...
    ("3.0.0", ">=2.0.0", True),  # (probe_version, range_str, expected)
    ("1.0.0", ">=2.0.0", False),
]
```

### For `parse_node_version`

Add new tuples to the `test_cases` list in the `TestParseNodeVersion` class:

```python
test_cases = [
    # ... existing test cases ...
    ("20.0.0", False, "20.0.0"),  # (version_string, use_first, expected)
]
```

Each test case is automatically executed by pytest's parametrize decorator.
