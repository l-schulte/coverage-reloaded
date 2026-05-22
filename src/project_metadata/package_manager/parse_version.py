import re


def sanitize_package_manager_version(version: str) -> str:
    """
    Sanitizes the package manager version string by removing any build metadata or pre-release identifiers.
    For example, "14.17.0+build.123" becomes "14.17.0", and "14.17.0-beta" becomes "14.17.0".
    """

    # Remove build metadata (anything after '+')
    version = version.split("+")[0]

    # Remove pre-release identifiers (anything after '-')
    version = version.split("-")[0]

    return version.strip()


def parse_package_manager_version(
    version_string: str, major_only: bool = False
) -> str | None:
    """
    Extracts version from string, e.g.;
    "14.17.0" -> "14.17", but also "15" -> "15"
    "14.17.9" -> "14.17"
    "^14.17.0" -> "14.17", but also "^15" -> "15"
    "v14.17.0" -> "14.17", but also "v15" -> "15"
    ">=14.17.0 <18" -> "14.17"
    ">=12.3 <14 || >=14.17.0" -> "14.17"
    ">=14.17.4 and <17" -> "14.17"
    """

    re_version_match = re.compile(
        r"(?:v|>=|>|\^|^)+ ?(\d+)(?:\.(\d+|\*))?(?:\.(\d+|\*))?"
    )
    version_match = re.findall(re_version_match, version_string)
    if version_match:
        major, minor, patch = version_match[-1]
        if major_only or (minor == "0" and patch in ["0", "*"]):
            return major

        return sanitize_package_manager_version(
            ".".join([v for v in [major, minor, patch] if v != ""])
        )
    return None
