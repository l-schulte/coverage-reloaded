import subprocess
import re


def file_exists_in_commit(repo_path, commit_hash, file_path) -> bool:
    cmd = ["git", "-C", repo_path, "cat-file", "-e", f"{commit_hash}:{file_path}"]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0


def get_file_at_commit(repo_path, commit_hash, file_path):
    cmd = ["git", "-C", repo_path, "show", f"{commit_hash}:{file_path}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


def parse_version_string(version_string: str, major_only: bool = False) -> str | None:
    """
    Extracts version from string, e.g.;
    "14.17.0" -> "14.17", but also "15" -> "15"
    "14.17.9" -> "14.17"
    "^14.17.0" -> "14.17", but also "^15" -> "15"
    "v14.17.0" -> "14.17", but also "v15" -> "15"
    ">=14.17.0 <18" -> "14.17"
    ">=12.3 <14 || >=14.17.0" -> "14.17"
    """

    re_version_match = re.compile(r"(?:v|>=|<=|\^|^)+(\d+)(?:\.(\d+))?(?:\.(\d+))?")
    version_match = re.findall(re_version_match, version_string)
    if version_match:
        major, minor, _ = version_match[-1]
        if minor and not major_only:
            return f"{major}.{minor}"
        return major
    return None
