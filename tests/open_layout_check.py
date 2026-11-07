"""Compatibility entry point: TASK010 low-border checks superseded by TASK011.

Historical TASK010 results remain in evidence/task010 and Git history.
Current full-wall invariants live in orbit_layout_check.py.
"""

from orbit_layout_check import check

if __name__ == "__main__":
    check()
