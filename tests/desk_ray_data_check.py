# Independent offline check of the real exported triangle data, not Godot runtime.
import json, struct, math
from pathlib import Path

b = Path("assets/models/furniture/desks/office_desk.glb").read_bytes()
n = struct.unpack_from("<I", b, 12)[0]
d = json.loads(b[20 : 20 + n])
offset = 20 + n
length, tag = struct.unpack_from("<II", b, offset)
data = b[offset + 8 : offset + 8 + length]
assert tag == 0x004E4942
assert all(
    not any(k in node for k in ["matrix", "translation", "rotation", "scale"])
    for node in d["nodes"]
)


def access(i):
    a = d["accessors"][i]
    v = d["bufferViews"][a["bufferView"]]
    w = {"SCALAR": 1, "VEC3": 3}[a["type"]]
    fmt = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[a["componentType"]]
    size = struct.calcsize(fmt) * w
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", size)
    return [
        struct.unpack_from("<" + fmt * w, data, start + k * stride)
        for k in range(a["count"])
    ]


triangles = []
for mesh in d["meshes"]:
    for p in mesh["primitives"]:
        pos = access(p["attributes"]["POSITION"])
        ind = [x[0] for x in access(p["indices"])]
        triangles.extend(
            [[pos[ind[k + j]] for j in range(3)] for k in range(0, len(ind), 3)]
        )


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def ray(origin, direction):
    nearest = math.inf
    for a, b, c in triangles:
        e1, e2 = sub(b, a), sub(c, a)
        p = cross(direction, e2)
        det = dot(e1, p)
        if abs(det) < 1e-9:
            continue
        tvec = sub(origin, a)
        u = dot(tvec, p) / det
        if not 0 <= u <= 1:
            continue
        q = cross(tvec, e1)
        v = dot(direction, q) / det
        if v < 0 or u + v > 1:
            continue
        t = dot(e2, q) / det
        if t >= 0:
            nearest = min(nearest, t)
    return nearest


print("Offline GLB triangle-data checks (Python, NOT Godot runtime)")
print("Triangles:", len(triangles))
for name, origin, direction, expected in [
    ("top", (0, 3, 0), (0, -1, 0), 2.25),
    ("side", (3, 0.73, 0), (-1, 0, 0), 2.2),
    ("opposite side", (-3, 0.73, 0), (1, 0, 0), 2.2),
    ("front", (0, 0.73, 3), (0, 0, -1), 2.6),
    ("gap between legs", (0, 0.3, 2), (0, 0, -1), math.inf),
]:
    hit = ray(origin, direction)
    assert hit == expected or abs(hit - expected) < 1e-5, (name, hit)
    print(f"PASS: {name}: nearest ray distance {hit:.6f}")
print(
    "This confirms the GLB has selectable top/side triangles, not the execution of GDScript."
)
