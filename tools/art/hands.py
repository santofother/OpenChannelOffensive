"""First-person gloved arms. Each arm is authored in the frame of the socket it attaches to
(Hand_R / Hand_L on a gun or held item), so Godot only has to parent it to that socket."""
import math, random
from mathutils import Vector, Matrix, Euler
import gearlib as G

GLOVE, PAD, SLEEVE = "glove", "glove_pad", "sleeve"

# knuckle x offset, segment lengths, base radius (right hand: thumb on -X, fingers +Y, back of hand +Z)
FINGERS = [(-0.030, (0.043, 0.027, 0.023), 0.0112), (-0.010, (0.047, 0.031, 0.024), 0.0116),
           (0.0105, (0.043, 0.029, 0.023), 0.0110), (0.0295, (0.034, 0.022, 0.020), 0.0100)]


def _finger(P, M, x, lens, r, curls, spread=0.0, y0=0.048):
    """Finger as a swept tube: curls = (mcp, pip, dip) flexion in degrees toward the palm (-Z)."""
    pts, radii = [], []
    p = Vector((x, y0 - 0.012, 0.002))
    d = Vector((-math.sin(math.radians(spread)), math.cos(math.radians(spread)), 0))
    pts.append(p.copy()); radii.append(r * 1.05)
    p = Vector((x, y0, 0.0))
    ang = 0.0
    side = Vector((1, 0, 0))
    joints = []
    for i, L in enumerate(lens):
        ang += curls[i]
        # blend into the bend with two sub-steps so knuckles look round
        dn = Matrix.Rotation(-math.radians(ang), 3, side) @ d
        pts.append(p + dn * L * 0.12); radii.append(r * (1.06 - 0.07 * i))
        pts.append(p + dn * L * 0.55); radii.append(r * (0.97 - 0.07 * i))
        joints.append((p + dn * L * 0.5, dn, L))
        p = p + dn * L
        pts.append(p.copy()); radii.append(r * (1.0 - 0.07 * (i + 1)) * (0.92 if i == 2 else 1.0))
    pts.append(p + dn * r * 0.45); radii.append(r * 0.62)
    pts.append(p + dn * r * 0.72); radii.append(r * 0.3)
    P.xf = M
    P.tube_path(GLOVE, pts, radii, segs=8, up=(0, 0, 1))
    # rubberised pad on the back of the first segment
    c, dn, L = joints[0]
    up = side.cross(dn).normalized() * -1.0
    if up.z < 0 and abs(curls[0]) < 20:
        up = -up
    back = dn.cross(side).normalized()
    q = Matrix((side, dn, back)).transposed().to_4x4()
    P.xf = M @ Matrix.Translation(c + back * (r * 0.72)) @ q
    P.box(PAD, (r * 1.5, L * 0.62, r * 0.7), bevel=0.0018, segs=2)
    P.xf = Matrix.Identity(4)
    return p


def _thumb(P, M, yaw, pitch, curl, base=(-0.036, 0.004, -0.010)):
    pts, radii = [], []
    p = Vector(base)
    d = Matrix.Rotation(math.radians(yaw), 3, 'Z') @ (Matrix.Rotation(math.radians(pitch), 3, 'X') @ Vector((0, 1, 0)))
    ax = d.cross(Vector((0, 0, 1))).normalized()
    pts.append(p - d * 0.018 + Vector((0.012, 0, 0))); radii.append(0.017)
    pts.append(p.copy()); radii.append(0.0155)
    ang = 0.0
    for i, L in enumerate((0.034, 0.029, 0.025)):
        ang += curl[i]
        dn = Matrix.Rotation(-math.radians(ang), 3, ax) @ d
        pts.append(p + dn * L * 0.5); radii.append(0.0142 - 0.001 * i)
        p = p + dn * L
        pts.append(p.copy()); radii.append((0.0136 - 0.0012 * i) * (0.92 if i == 2 else 1.0))
    pts.append(p + dn * 0.006); radii.append(0.0075)
    pts.append(p + dn * 0.009); radii.append(0.0035)
    P.xf = M
    P.tube_path(GLOVE, pts, radii, segs=8, up=(0, 0, 1))
    P.xf = Matrix.Identity(4)


def arm(P, M, elbow, curls, thumb, right=True, spread=(4, 0, -3, -7), sleeve_r=0.041, seed=1):
    """Build a gloved hand at matrix M (hand space, right-handed layout) and a sleeve to `elbow` (target space).
    For a left hand pass a mirrored M (det < 0)."""
    Mx = M
    # palm: two stacked rounded slabs give a slightly cupped hand
    P.xf = Mx
    P.box(GLOVE, (0.088, 0.100, 0.030), (0.0, 0.0, 0.0), bevel=0.011, segs=3)
    P.box(GLOVE, (0.070, 0.050, 0.034), (0.004, -0.030, -0.003), bevel=0.012, segs=3)   # heel of the hand
    # hard knuckle guard and back-of-hand panel
    P.prof(PAD, [(-0.043, 0.030), (0.043, 0.030), (0.045, 0.047), (0.040, 0.058), (-0.040, 0.058), (-0.045, 0.047)], 0.012, 0.0215, 'Z', bevel=0.003, segs=2)
    for kx in (-0.030, -0.010, 0.0105, 0.0295):
        P.box(PAD, (0.015, 0.016, 0.006), (kx, 0.047, 0.0225), bevel=0.0028, segs=2)
    P.box(PAD, (0.060, 0.034, 0.004), (0.002, 0.004, 0.0165), bevel=0.0015, segs=1)
    for i in range(3):
        P.box(GLOVE, (0.050, 0.0035, 0.003), (0.002, -0.006 + i * 0.010, 0.0195), bevel=0.001, segs=1)
    # wrist cuff with a closure strap
    P.lathe(GLOVE, [(-0.105, 0.0345), (-0.100, 0.037), (-0.060, 0.0365), (-0.050, 0.0345), (-0.045, 0.03)], 'Y', at=(0.002, 0, -0.001), segs=14)
    P.box(PAD, (0.040, 0.022, 0.006), (0.004, -0.078, 0.0345), bevel=0.0015, segs=1)
    P.box(GLOVE, (0.016, 0.026, 0.007), (0.028, -0.078, 0.033), bevel=0.002, segs=1, rot=(0, 25, 0))
    P.xf = Matrix.Identity(4)
    for (x, lens, r), c, sp in zip(FINGERS, curls, spread):
        _finger(P, Mx, x, lens, r, c, sp)
    _thumb(P, Mx, *thumb)
    # sleeve from the cuff to the elbow, with cloth folds
    wrist = Mx @ Vector((0.002, -0.085, -0.001))
    wdir = (Mx.to_3x3() @ Vector((0, -1, 0))).normalized()
    elbow = Vector(elbow)
    rng = random.Random(seed)
    n = 13
    pts, radii = [], []
    for i in range(n):
        t = i / (n - 1)
        # ease from the wrist direction into the straight forearm
        a = wrist + wdir * 0.33 * t
        b = wrist.lerp(elbow, t)
        k = t * t * (3 - 2 * t)
        pts.append(a.lerp(b, min(1.0, k * 1.6)))
        fold = (0.0035 if i % 2 else -0.002) + rng.uniform(-0.0015, 0.0015)
        radii.append(0.039 + (sleeve_r - 0.039) * min(1.0, t * 2.5) + sleeve_r * 0.16 * t + (fold if 0 < i < n - 1 else 0))
    P.tube_path(SLEEVE, pts, radii, segs=14, squash=0.92, cap=False)
    # cuff hem and a forearm pocket flap
    P.tube_path(SLEEVE, [pts[0] - wdir * -0.004, pts[0] + wdir * 0.012], [0.0435, 0.0435], segs=14, cap=False)


def hand_matrix(pos, x_axis, y_axis, left=False):
    """Hand space -> target space. y_axis = finger direction, x_axis = towards the little finger (right hand)."""
    y = Vector(y_axis).normalized()
    x = Vector(x_axis).normalized()
    z = x.cross(y).normalized()
    x = y.cross(z).normalized()
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = Vector(pos)
    if left:
        M = M @ G.mirror_x()
    return M


def build():
    A = G.Asset("hands", "weapons")
    wrap = [(62, 78, 40)] * 4
    # Right hand on a rifle pistol grip: palm against the right side, fingers round the front, index along the frame.
    P = A.part("ArmR_Grip")
    M = hand_matrix((0.021, -0.030, -0.040), (0.0, -0.33, -0.94), (-0.08, 0.93, -0.34))
    arm(P, M, (0.20, -0.42, -0.26), [(28, 36, 18), (80, 84, 36), (82, 86, 36), (84, 86, 38)], (26, -58, (14, 34, 24)), seed=1)
    # Left hand cupping a handguard from below, thumb up the left side.
    P = A.part("ArmL_Fore")
    M = hand_matrix((-0.026, -0.016, -0.017), (-0.5, 0.86, 0.0), (0.86, 0.5, 0.12)) @ G.mirror_x()
    arm(P, M, (-0.17, -0.36, -0.30), [(66, 50, 30), (68, 52, 30), (68, 52, 32), (70, 52, 34)], (48, -22, (6, 16, 12)), seed=2)
    # Right hand on a handgun grip (elbow tucked in under the camera).
    P = A.part("ArmR_Pistol")
    M = hand_matrix((0.021, -0.030, -0.040), (0.0, -0.33, -0.94), (-0.08, 0.93, -0.34))
    arm(P, M, (0.13, -0.30, -0.36), [(28, 36, 18), (80, 84, 36), (82, 86, 36), (84, 86, 38)], (26, -58, (14, 34, 24)), seed=6)
    # Left hand supporting a pistol grip (wraps the right hand's fingers).
    P = A.part("ArmL_Support")
    M = hand_matrix((-0.030, -0.004, -0.060), (0.0, -0.45, -0.89), (0.42, 0.82, -0.40)) @ G.mirror_x()
    arm(P, M, (-0.15, -0.30, -0.36), [(58, 76, 40)] * 4, (30, -10, (20, 28, 18)), seed=3)
    # Right hand holding a flat device or grenade from below/behind (palm up-left, fingers curled round it).
    P = A.part("ArmR_Hold")
    M = hand_matrix((0.035, -0.02, -0.03), (0.35, -0.2, -0.92), (-0.25, 0.9, -0.3))
    arm(P, M, (0.22, -0.42, -0.24), [(48, 66, 36)] * 4, (30, -24, (18, 26, 16)), seed=4)
    # Left hand steadying a device from the left.
    P = A.part("ArmL_Hold")
    M = hand_matrix((-0.035, -0.02, -0.03), (-0.35, -0.2, -0.92), (0.25, 0.9, -0.3)) @ G.mirror_x()
    arm(P, M, (-0.24, -0.42, -0.24), [(48, 66, 36)] * 4, (30, -24, (18, 26, 16)), seed=5)
    for p in A.parts.values():
        p.smooth = 75.0
    A.build(ao=True)
    return A
