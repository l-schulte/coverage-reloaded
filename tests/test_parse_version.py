import pytest
import sys
from pathlib import Path

# Add src directory to path
src_path = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(src_path))

from src.src.helpers.versions.node.parse_version import parse_node_version
from src.src.helpers.versions.node.parse_version import __npm_satisfies as npm_satisfies


class TestNpmSatisfies:
    """Tests for the __npm_satisfies function."""

    # Test cases: (probe_version, range_str, expected_result)
    test_cases = [
        # Exact version matches
        ("1.0.0", "1.0.0", True),
        ("1.0.0", "1.0.1", False),
        ("2.5.3", "2.5.3", True),
        # Wildcard
        ("1.0.0", "*", True),
        ("99.99.99", "*", True),
        # Greater than
        ("2.0.0", ">1.0.0", True),
        ("1.0.0", ">1.0.0", False),
        ("1.0.1", ">1.0.0", True),
        # Greater than or equal
        ("2.0.0", ">=1.0.0", True),
        ("1.0.0", ">=1.0.0", True),
        ("0.9.9", ">=1.0.0", False),
        # Less than
        ("1.0.0", "<2.0.0", True),
        ("2.0.0", "<2.0.0", False),
        ("1.9.9", "<2.0.0", True),
        # Less than or equal
        ("1.0.0", "<=2.0.0", True),
        ("2.0.0", "<=2.0.0", True),
        ("2.0.1", "<=2.0.0", False),
        # Tilde (~) operator - patch level changes
        ("1.2.3", "~1.2.0", True),
        ("1.3.0", "~1.2.0", False),
        ("1.2.5", "~1.2.0", True),
        # Caret (^) operator - minor/patch level changes
        ("1.2.3", "^1.0.0", True),
        ("1.5.0", "^1.0.0", True),
        ("2.0.0", "^1.0.0", False),
        # OR conditions (||)
        ("1.0.0", "1.0.0 || 2.0.0", True),
        ("2.0.0", "1.0.0 || 2.0.0", True),
        ("3.0.0", "1.0.0 || 2.0.0", False),
        ("5.0.0", "<2.0.0 || >4.0.0", True),
        ("3.0.0", "<2.0.0 || >4.0.0", False),
        # AND conditions (space or comma separated)
        ("1.5.0", ">=1.0.0 <=2.0.0", True),
        ("2.5.0", ">=1.0.0 <=2.0.0", False),
        ("1.5.0", ">=1.0.0,<=2.0.0", True),
        # Complex ranges
        ("1.2.3", ">=1.0.0 <2.0.0", True),
        ("2.0.0", ">=1.0.0 <2.0.0", False),
        ("0.9.9", ">=1.0.0 <2.0.0", False),
        # Partial versions
        ("1.2.3", "1", True),
        ("2.0.0", "1", False),
        ("1.2.3", "1.2", True),
        ("1.3.0", "1.2", False),
        # Edge cases
        ("0.0.0", "0.0.0", True),
        ("0.0.1", ">0.0.0", True),
    ]

    @pytest.mark.parametrize("probe_version,range_str,expected", test_cases)
    def test_npm_satisfies(self, probe_version, range_str, expected):
        """Test __npm_satisfies with various version ranges."""
        result = npm_satisfies(probe_version, range_str)
        assert result == expected, (
            f"npm_satisfies('{probe_version}', '{range_str}') "
            f"returned {result}, expected {expected}"
        )


class TestParseNodeVersion:
    """Tests for the parse_node_version function."""

    # Test cases: (version_string, use_first, expected_result)
    # Note: These tests depend on the NODE_RELEASES data being available
    # and will return the major version that matches the range
    test_cases = [
        # Concrete versions should be returned as-is
        ("14.17.0", False, "14.17.0"),
        ("16.13.0", False, "16.13.0"),
        ("18", False, "18"),
        ("16.13", False, "16.13"),
        # Single major version
        ("14", False, "14"),
        ("16", False, "16"),
        (">=16", True, "16"),
        # Version ranges - these will find matching major versions
        # The actual results depend on what's in NODE_RELEASES
        # Uncomment and adjust these based on your actual data
        # (">=14.0.0", False, None),  # Returns last matching version
        # (">=14.0.0", True, None),   # Returns first matching version
        # (">14.0.0 <18.0.0", False, None),
        # ("^14.0.0", False, None),
    ]

    @pytest.mark.parametrize("version_string,use_first,expected", test_cases)
    def test_parse_node_version(self, version_string, use_first, expected):
        """Test parse_node_version with various version strings."""
        result = parse_node_version(version_string, use_first)
        assert result == expected, (
            f"parse_node_version('{version_string}', use_first={use_first}) "
            f"returned {result}, expected {expected}"
        )

    def test_parse_node_version_invalid(self):
        """Test parse_node_version with invalid input."""
        # This test depends on the actual implementation behavior
        # Adjust based on expected error handling
        pass


# Additional test cases can be easily added to the test_cases lists above
# Example of how to add new test cases:
#
# For __npm_satisfies:
# TestNpmSatisfies.test_cases.extend([
#     ("3.0.0", ">=2.0.0", True),
#     ("1.0.0", ">=2.0.0", False),
# ])
#
# For parse_node_version:
# TestParseNodeVersion.test_cases.extend([
#     ("20.0.0", False, "20.0.0"),
# ])


if __name__ == "__main__":
    # Run tests with pytest
    pytest.main([__file__, "-v"])
