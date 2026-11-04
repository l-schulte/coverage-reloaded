"""Error-block fingerprints: fp_min (3 lines) and fp_max (6 lines)."""

import hashlib

from .normalize import collapse_blanks, normalize_line


def window_block(lines, fail_line, n_following):
    """Normalized block: trigger (1-based fail_line) + n_following lines."""
    start = fail_line - 1
    raw = lines[start:start + 1 + n_following]
    return "\n".join(collapse_blanks([normalize_line(l) for l in raw]))


def compute_fingerprints(lines, fail_line):
    """Return (fp_min, fp_max, block_min, block_max)."""
    bmin = window_block(lines, fail_line, 2)
    bmax = window_block(lines, fail_line, 5)
    fp_min = hashlib.sha1(("min:" + bmin).encode("utf-8", "replace")).hexdigest()[:16]
    fp_max = hashlib.sha1(("max:" + bmax).encode("utf-8", "replace")).hexdigest()[:16]
    return fp_min, fp_max, bmin, bmax
