"""Compatibility entry point: TASK010/011 checks superseded by TASK011.1.

Historical TASK010 results remain in evidence/task010 and Git history.
Current clipping invariants live in height_layout_check.py.
"""

from orbit_layout_check import check

if __name__ == "__main__":
    check()
