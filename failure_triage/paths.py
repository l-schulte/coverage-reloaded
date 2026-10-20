"""Repository-relative paths used by the v2 toolchain.

Canonical layout (v2):

    projects/<p>/label_analysis/
        failure_patterns.json          # live config (read + written by v2)
        failure_labels_project_min.csv # human labels, deduped by fp_min
        failure_labels_project_max.csv # human labels, deduped by fp_max
        failure_labels_jev_min.csv     # Jev labels (independent)
        failure_labels_v2.db           # failures / labels / runs / meta
        <p>_min.jsonl                  # family cards
        v1/                            # retired v1 artifacts (gitignored)
            failure_labels_project.csv
            failure_labels_jev.csv
            <p>_v2_doublecheck.md      # double-check pass artifact

Unmigrated projects still keep `failure_patterns.json` and the v1 label CSVs
at the project root; the resolvers below fall back to the root location so
both layouts work during the transition.
"""

import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def project_dir(project):
    return os.path.join(REPO_ROOT, "projects", project)


def analysis_dir(project):
    return os.path.join(project_dir(project), "label_analysis")


def csv_path(project, window):
    name = "min" if window == 2 else "max"
    return os.path.join(analysis_dir(project), f"failure_labels_project_{name}.csv")


def db_path(project):
    return os.path.join(analysis_dir(project), "failure_labels_v2.db")


def patterns_path(project):
    """failure_patterns.json: label_analysis first, project root as fallback."""
    new = os.path.join(analysis_dir(project), "failure_patterns.json")
    if os.path.isfile(new):
        return new
    return os.path.join(project_dir(project), "failure_patterns.json")


def v1_dir(project):
    return os.path.join(analysis_dir(project), "v1")


def v1_labels_path(project):
    """v1 failure_labels_project.csv: label_analysis/v1 first, root fallback."""
    new = os.path.join(v1_dir(project), "failure_labels_project.csv")
    if os.path.isfile(new):
        return new
    return os.path.join(project_dir(project), "failure_labels_project.csv")


def v1_jev_labels_path(project):
    """v1 failure_labels_jev.csv: label_analysis/v1 first, root fallback."""
    new = os.path.join(v1_dir(project), "failure_labels_jev.csv")
    if os.path.isfile(new):
        return new
    return os.path.join(project_dir(project), "failure_labels_jev.csv")


def doublecheck_path(project):
    """Where the double-check pass artifact lives (gitignored)."""
    return os.path.join(v1_dir(project), f"{project}_v2_doublecheck.md")


def logs_dir(project):
    return os.path.join(project_dir(project), "logs")
