"""Read-only Git queries for mainline metadata.

Definitions:
  mainline commit   — a commit on the first-parent chain of the default branch,
                      i.e. one state the main branch passed through. One commit
                      per integration event (squash landing, merge commit, or
                      direct push).
  default branch    — resolved via refs/remotes/origin/HEAD (project-specific:
                      main, master, v14-dev, ...).
"""

import subprocess
from pathlib import Path


def _git(repo_path: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_path), *args],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed in {repo_path}: {result.stderr.strip()}"
        )
    return result.stdout


def default_branch(repo_path: Path) -> str:
    """Name of the default branch (origin/HEAD), falling back to main/master/HEAD."""
    try:
        ref = _git(repo_path, "symbolic-ref", "--short", "refs/remotes/origin/HEAD").strip()
        return ref.split("/", 1)[1] if "/" in ref else ref
    except RuntimeError:
        pass
    for name in ("main", "master", "HEAD"):
        try:
            _git(repo_path, "rev-parse", "--verify", "--quiet", f"refs/heads/{name}")
            return name
        except RuntimeError:
            continue
    raise RuntimeError(f"cannot determine default branch of {repo_path}")


def mainline_shas(repo_path: Path) -> set:
    """Full SHAs of every commit on the first-parent chain of the default branch."""
    name = default_branch(repo_path)
    for ref in (name, f"origin/{name}"):
        try:
            out = _git(repo_path, "rev-list", "--first-parent", ref)
            return set(out.split())
        except RuntimeError:
            continue
    raise RuntimeError(f"cannot list mainline commits of {repo_path} ({name})")
