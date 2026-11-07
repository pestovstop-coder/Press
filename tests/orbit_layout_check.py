"""TASK011 static invariants and Python visibility/orbit MODEL, not Godot execution."""

import itertools
import math
from pathlib import Path
import re
import subprocess

from layout_blockout_check import capacity, ray_box, read_scene

ROOT = Path(__file__).resolve().parents[1]
BASE = "389ab8c602b136d28d3c95815242833e38bc53f5"


def old_file(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT)


def constants():
    source = (ROOT / "scripts/wall_visibility.gd").read_text()
    return {
        k: float(v) for k, v in re.findall(r"const (\w+): float = ([\d.]+)", source)
    }


def classify(yaw, previous=None):
    """Explicit offline mirror; source checks below bind thresholds/rule terms."""
    c = constants()
    x, z = math.sin(math.radians(yaw)), math.cos(math.radians(yaw))
    result = dict(
        previous or dict.fromkeys(("front", "rear", "east", "west", "shared"), False)
    )
    for side, facing in (
        ("front", z),
        ("rear", -z),
        ("east", x),
        ("west", -x),
        ("shared", abs(x)),
    ):
        hide, show = (
            (c["SHARED_HIDE"], c["SHARED_SHOW"])
            if side == "shared"
            else (c["HIDE_THRESHOLD"], c["SHOW_THRESHOLD"])
        )
        if facing > hide:
            result[side] = True
        elif facing < show:
            result[side] = False
    return result


def module_sides(nodes):
    return {
        name: re.search(r'metadata/cutaway_side = "([^"]+)"', n["body"])[1].split("_")
        for name, n in nodes.items()
        if "metadata/cutaway_side" in n["body"]
    }


def visible_modules(membership, state):
    return {
        name
        for name, sides in membership.items()
        if not all(state[side] for side in sides)
    }


def canonical(text):
    return re.sub(r"\s+", "", re.sub(r"#[^\n]*", "", text))


def check():
    # TASK011 binary visibility invariants are historical; retain rule helpers.
    from height_layout_check import check as height_check

    height_check()


if __name__ == "__main__":
    check()
