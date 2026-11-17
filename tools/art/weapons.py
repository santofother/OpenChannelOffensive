"""Guns. Bore axis = +Y at x = 0, z = 0; y = 0 is the rear face of the receiver.
Each gun exports with its origin at the top of the pistol grip and these sockets:
Muzzle, Sight, Rail_Top, Rail_Side (left), Rail_Side_R, Hand_R, Hand_L. Animated parts: Mag, Bolt, Charge, Slide..."""
import math
from mathutils import Vector, Matrix
import gearlib as G

POLY, ALU, STEEL, BARE, RUB = "polymer_black", "steel_black", "steel_dark", "steel_bare", "rubber"
RAIL_H = 0.0094


# ------------------------------------------------------------------ shared modules
def holo_sight(A, P, y, zr, parent=None):
    """Open holographic sight clamped on a rail whose tooth tops are at zr. Returns the sight-axis height."""
    zc = zr + 0.036          # window centre
    y0, y1 = y, y + 0.074
    P.box(ALU, (0.030, 0.074, 0.010), (0, y + 0.037, zr + 0.005), bevel=0.002)                    # base
    P.box(ALU, (0.036, 0.034, 0.014), (0, y + 0.018, zr + 0.014), bevel=0.003)                    # battery/electronics block
    P.cyl(STEEL, 0.0075, (0.016, y + 0.05, zr + 0.004), (0.026, y + 0.05, zr + 0.004), segs=10)   # clamp knob
    P.cyl(STEEL, 0.004, (0.026, y + 0.05, zr + 0.004), (0.029, y + 0.05, zr + 0.004), segs=6)
    for i, bx in enumerate((-0.008, 0.008)):                                                       # rear buttons
        P.box(RUB, (0.009, 0.003, 0.006), (bx, y - 0.0005, zr + 0.014), bevel=0.001, segs=1)
    # hood: slanted side walls + roof, open window
    hw = 0.0215
    for s in (-1, 1):
        P.prof(ALU, [(y0 + 0.020, zr + 0.010), (y1, zr + 0.010), (y1 - 0.004, zc + 0.019), (y0 + 0.030, zc + 0.019)],
               s * hw - 0.002, s * hw + 0.002, 'X', bevel=0.0012)
        P.prof(ALU, [(y0 + 0.018, zr + 0.021), (y0 + 0.024, zr + 0.021), (y0 + 0.033, zc + 0.016), (y0 + 0.027, zc + 0.016)],
               s * hw - 0.0035, s * hw + 0.0035, 'X', bevel=0.001, segs=1)                             # wing rib
        P.screw(STEEL, (s * (hw + 0.002), y1 - 0.012, zr + 0.016), (s, 0, 0), r=0.0022)
    P.box(ALU, (hw * 2 + 0.004, 0.038, 0.004), (0, y1 - 0.021, zc + 0.019), bevel=0.0015)          # roof
    P.box(ALU, (hw * 2 + 0.004, 0.012, 0.006), (0, y0 + 0.032, zc + 0.0185), bevel=0.0015, rot=(-20, 0, 0))
    # inner window frame
    P.box(ALU, (hw * 2 - 0.004, 0.006, 0.003), (0, y1 - 0.012, zc - 0.0165), bevel=0.0008, segs=1)
    L = A.part("SightGlass", parent=parent) if "SightGlass" not in A.parts else A.parts["SightGlass"]
    L.box("glass_lens", (hw * 2 - 0.004, 0.0012, 0.034), (0, y1 - 0.012, zc), bevel=0)
    R = A.part("Reticle", parent=parent) if "Reticle" not in A.parts else A.parts["Reticle"]
    R.lathe("reticle", [(0, 0.0021), (0.0001, 0.00235)], 'Y', at=(0, y1 - 0.0135, zc), segs=28)
    R.lathe("reticle", [(0, 0.0), (0.0001, 0.00028)], 'Y', at=(0, y1 - 0.0135, zc), segs=10)
    for a in range(4):
        d = Vector((math.cos(a * math.pi / 2), 0, math.sin(a * math.pi / 2)))
        R.box("reticle", (0.0002 if a % 2 == 1 else 0.0007, 0.0001, 0.0007 if a % 2 == 1 else 0.0002), tuple(Vector((0, y1 - 0.0135, zc)) + d * 0.0027), bevel=0)
    A.socket("Sight", (0, y0 + 0.01, zc), parent=parent)
    return zc


def suppressor(P, y0, length=0.19, r=0.0205, mat=STEEL):
    y1 = y0 + length
    pts = [(y0, 0.011), (y0 + 0.004, 0.0165), (y0 + 0.016, 0.0165), (y0 + 0.018, r)]
    for k in range(3):
        ya = y0 + 0.026 + k * 0.012
        pts += [(ya, r), (ya + 0.0015, r - 0.0018), (ya + 0.0045, r - 0.0018), (ya + 0.006, r)]
    pts += [(y1 - 0.022, r), (y1 - 0.020, r - 0.0012), (y1 - 0.018, r), (y1 - 0.004, r), (y1, r - 0.004), (y1, 0.0062), (y1 - 0.02, 0.0062), (y1 - 0.02, 0.0)]
    P.lathe(mat, pts, 'Y', segs=28)
    for a in range(6):  # wrench flats at the rear collar
        ang = a * math.pi / 3
        P.box(mat, (0.008, 0.010, 0.002), (math.cos(ang) * 0.0162, y0 + 0.010, math.sin(ang) * 0.0162), bevel=0.0005, segs=1, rot=(0, -math.degrees(ang) + 90, 0))


def backup_sight(P, y, zr, front=True):
    P.box(ALU, (0.0215, 0.034, 0.006), (0, y + 0.017, zr + 0.003), bevel=0.0012)
    P.box(STEEL, (0.012, 0.026, 0.0045), (0, y + (0.016 if front else 0.018), zr + 0.008), bevel=0.001, segs=1)
    P.cyl(STEEL, 0.0032, (-0.0125, y + (0.005 if front else 0.029), zr + 0.0045), (0.0125, y + (0.005 if front else 0.029), zr + 0.0045), segs=8)


def ar_mag(P, y=0.143, top=-0.045, length=0.185, curve=0.03, w=0.0235, mat=POLY):
    """Curved box magazine; pivot is expected at (0, y, top)."""
    f, b = y + 0.031, y - 0.031
    z1 = top - length
    pts = [(b, top), (f, top), (f + 0.002, top - length * 0.35), (f + curve * 0.55, top - length * 0.75), (f + curve, z1 + 0.006),
           (f + curve - 0.004, z1), (b + curve + 0.006, z1 - 0.012), (b + curve * 0.5, top - length * 0.72), (b + 0.001, top - length * 0.35)]
    P.prof(mat, pts, -w / 2, w / 2, 'X', bevel=0.0022)
    # floor plate and raised side panels
    P.prof(mat, [(b + curve + 0.001, z1 - 0.017), (f + curve + 0.002, z1 - 0.002), (f + curve + 0.004, z1 + 0.006), (b + curve + 0.003, z1 - 0.009)],
           -w / 2 - 0.0015, w / 2 + 0.0015, 'X', bevel=0.0015)
    cy = sum(p[0] for p in pts) / len(pts)
    cz = sum(p[1] for p in pts) / len(pts)
    inner = [(cy + (p[0] - cy) * 0.62, cz + (p[1] - cz) * 0.80 - 0.012) for p in pts]
    P.prof(mat, inner, -w / 2 - 0.0012, w / 2 + 0.0012, 'X', bevel=0.001, segs=1)
    for k in range(4):
        t = 0.36 + k * 0.13
        P.box(mat, (w + 0.0042, 0.030, 0.0022), (0, y + curve * t * t * 1.1 + 0.001, top - length * t), bevel=0.0008, segs=1, rot=(-8 - 14 * t, 0, 0))


def pistol_grip(P, y=0.02, top=-0.047, w=0.029, mat=POLY, length=0.1, rake=0.036):
    pts = [(y + 0.022, top - 0.001), (y + 0.014, top - 0.024), (y + 0.012 - rake * 0.35, top - 0.05), (y - rake + 0.012, top - length),
           (y - rake - 0.030, top - length + 0.002), (y - rake * 0.5 - 0.026, top - 0.055), (y - 0.030, top - 0.022), (y - 0.034, top - 0.006), (y - 0.022, top + 0.002)]
    P.prof(mat, pts, -w / 2, w / 2, 'X', bevel=0.0048, segs=3)
    for k in range(7):  # grip texture grooves across both flanks
        t = 0.30 + k * 0.09
        P.box(mat, (w + 0.0022, 0.030, 0.0026), (0, y - rake * t - 0.010, top - length * t), bevel=0.0009, segs=1, rot=(20, 0, 0))
    P.box(mat, (w + 0.002, 0.036, 0.005), (0, y - rake - 0.009, top - length - 0.0005), bevel=0.0018)  # base cap


def mlok_cutters(y0, y1, hw=0.021, zb=-0.026, pitch=0.05, slot=0.032):
    C = G.Part()
    C.lathe(None, [(y0 - 0.01, 0.0168), (y1 + 0.01, 0.0168)], 'Y', segs=20)   # hollow bore
    n = int((y1 - y0 - 0.03) / pitch)
    for i in range(n):
        yc = y0 + 0.035 + i * pitch
        C.box(None, (0.08, slot, 0.0068), (0, yc, 0.0005), bevel=0.0)                       # 3 and 9 o'clock
        C.box(None, (0.0068, slot, 0.03), (0, yc, zb), bevel=0.0)                           # 6 o'clock
        for s in (-1, 1):
            C.box(None, (0.02, slot, 0.0062), (s * (hw - 0.0045), yc + pitch * 0.5 if i < n - 1 else yc, (zb - 0.015) / 2 - 0.0), bevel=0.0, rot=(0, s * 50.7, 0))
            C.cyl(None, 0.0035, (s * 0.012, yc + pitch * 0.5, 0.02), (s * 0.03, yc + pitch * 0.5, 0.032), segs=10, ch=0)   # upper lightening holes
    return C


# ------------------------------------------------------------------ AR-pattern platform (service rifle, carbine, marksman)
UPPER_CS = [(-0.019, -0.018), (0.019, -0.018), (0.021, -0.004), (0.021, 0.014), (0.0135, 0.0275), (-0.0135, 0.0275), (-0.021, 0.014), (-0.021, -0.004)]
HG_CS = [(-0.012, -0.026), (0.012, -0.026), (0.021, -0.015), (0.021, 0.016), (0.0135, 0.0275), (-0.0135, 0.0275), (-0.021, 0.016), (-0.021, -0.015)]


def ar_receiver(A, P):
    """Upper + lower receiver, controls, grip, bolt and charging handle (shared by all AR variants)."""
    C = G.Part()
    C.box(None, (0.02, 0.066, 0.0165), (0.021, 0.118, 0.0035), bevel=0)
    P.prof(ALU, UPPER_CS, 0.0, 0.205, 'Y', bevel=0.0016, cuts=C)
    P.rail(ALU, 0.004, 0.204, 0.0275)
    P.prof(ALU, [(0.060, -0.004), (0.084, -0.004), (0.084, 0.012), (0.074, 0.012)], 0.0205, 0.0265, 'X', bevel=0.0012)              # brass deflector
    P.cyl(ALU, 0.0068, (0.0185, 0.052, 0.006), (0.0285, 0.030, 0.006), segs=12)                                                    # forward assist
    P.cyl(STEEL, 0.0058, (0.0285, 0.030, 0.006), (0.0325, 0.021, 0.006), segs=12)
    P.box(STEEL, (0.0018, 0.068, 0.018), (0.0222, 0.118, -0.0125), bevel=0.0007, segs=1, rot=(0, -8, 0))                            # open dust cover
    P.cyl(STEEL, 0.0018, (0.0215, 0.082, -0.0045), (0.0215, 0.154, -0.0045), segs=6, ch=0)
    P.prof(ALU, [(-0.016, -0.016), (0.200, -0.016), (0.200, -0.050), (0.181, -0.084), (0.108, -0.078), (0.104, -0.047), (0.036, -0.047), (0.0, -0.054), (-0.016, -0.046)],
           -0.018, 0.018, 'X', bevel=0.0022)
    P.prof(ALU, [(0.103, -0.040), (0.186, -0.046), (0.184, -0.082), (0.106, -0.076)], -0.0195, 0.0195, 'X', bevel=0.0015)            # magwell flare
    P.lathe(ALU, [(-0.026, 0.0185), (-0.024, 0.0205), (-0.004, 0.0205), (0.0, 0.0185)], 'Y', at=(0, 0, -0.001), segs=18)             # buffer tower ring
    P.box(ALU, (0.013, 0.078, 0.0032), (0, 0.068, -0.0795), bevel=0.0012)                                                           # trigger guard
    P.box(ALU, (0.013, 0.0032, 0.03), (0, 0.031, -0.066), bevel=0.0012, rot=(-18, 0, 0))
    P.prof(STEEL, [(0.072, -0.046), (0.079, -0.046), (0.0765, -0.058), (0.081, -0.069), (0.0775, -0.071), (0.070, -0.058)], -0.003, 0.003, 'X', bevel=0.001, segs=1)
    for py, pz in ((0.010, -0.024), (0.192, -0.026)):
        P.cyl(STEEL, 0.0038, (-0.0195, py, pz), (0.0195, py, pz), segs=10)
    P.cyl(STEEL, 0.006, (-0.0215, 0.034, -0.030), (-0.018, 0.034, -0.030), segs=12)                                                 # selector
    P.box(STEEL, (0.003, 0.022, 0.0055), (-0.022, 0.026, -0.027), bevel=0.001, segs=1, rot=(25, 0, 0))
    P.box(STEEL, (0.003, 0.012, 0.03), (-0.0205, 0.132, -0.012), bevel=0.001, segs=1)                                               # bolt catch
    P.box(STEEL, (0.004, 0.016, 0.014), (-0.0215, 0.132, 0.0), bevel=0.0012, segs=1)
    P.cyl(STEEL, 0.0048, (0.018, 0.098, -0.031), (0.0225, 0.098, -0.031), segs=10)                                                  # magazine release
    P.box(ALU, (0.002, 0.026, 0.003), (0.019, 0.098, -0.038), bevel=0.0008, segs=1)
    pistol_grip(P)
    B = A.part("Bolt", pivot=(0.011, 0.118, 0.0035))
    B.cyl(BARE, 0.0088, (0.0105, 0.078, 0.0035), (0.0105, 0.158, 0.0035), segs=12)
    B.box(STEEL, (0.004, 0.02, 0.006), (0.019, 0.132, 0.0035), bevel=0.001, segs=1)
    for k in range(3):
        B.cyl(STEEL, 0.0092, (0.0105, 0.09 + k * 0.012, 0.0035), (0.0105, 0.094 + k * 0.012, 0.0035), segs=12, ch=0.0003)
    Cg = A.part("Charge", pivot=(0, 0.0, 0.019))
    Cg.box(STEEL, (0.054, 0.013, 0.0075), (0, -0.0045, 0.0185), bevel=0.002)
    Cg.box(STEEL, (0.012, 0.03, 0.006), (0, 0.012, 0.0185), bevel=0.001, segs=1)
    for s in (-1, 1):
        Cg.box(STEEL, (0.010, 0.006, 0.0085), (s * 0.023, -0.0085, 0.0185), bevel=0.0015, segs=1)


def ar_stock(A, fixed=False):
    """Shoulder stock as its own part (hidden in first person: it sits behind the camera)."""
    K = A.part("Stock")
    K.cyl(STEEL, 0.0148, (0, -0.165, -0.001), (0, -0.004, -0.001), segs=18)
    K.lathe(STEEL, [(-0.034, 0.019), (-0.032, 0.021), (-0.027, 0.021), (-0.025, 0.019)], 'Y', at=(0, 0, -0.001), segs=18)
    sy = 0.0 if fixed else 0.06
    C = G.Part()
    C.prof(None, [(-0.200 + sy, -0.040), (-0.200 + sy, -0.080), (-0.150 + sy, -0.040)], -0.05, 0.05, 'X', bevel=0)
    K.prof(POLY, [(-0.050, 0.020), (-0.212 + sy, 0.020), (-0.230 + sy, 0.011), (-0.230 + sy, -0.094), (-0.214 + sy, -0.104), (-0.192 + sy, -0.094), (-0.105 + sy * 0.5, -0.034), (-0.050, -0.024)],
           -0.0205, 0.0205, 'X', bevel=0.0035, segs=2, cuts=C)
    K.prof(RUB, [(-0.229 + sy, 0.013), (-0.239 + sy, 0.007), (-0.239 + sy, -0.092), (-0.229 + sy, -0.098)], -0.021, 0.021, 'X', bevel=0.003, segs=2)
    K.box(POLY, (0.045, 0.05 if not fixed else 0.10, 0.007 if not fixed else 0.014), (0, -0.105 if not fixed else -0.13, 0.0215 if not fixed else 0.026), bevel=0.0025)
    K.box(STEEL, (0.012, 0.03, 0.006), (0, -0.075, -0.031), bevel=0.0015, rot=(36, 0, 0))
    for s in (-1, 1):
        K.cyl(STEEL, 0.0055, (s * 0.0205, -0.062, -0.006), (s * 0.0225, -0.062, -0.006), segs=10)


def flash_hider(P, y0, r=0.0105, length=0.045):
    P.lathe(STEEL, [(y0, 0.0092), (y0 + 0.004, r), (y0 + length - 0.003, r), (y0 + length, r - 0.002), (y0 + length, 0.004), (y0 + length - 0.02, 0.004), (y0 + length - 0.02, 0)], 'Y', segs=18)
    for a in range(6):
        ang = a * math.pi / 3 + 0.3
        P.box(RUB, (0.0022, length * 0.5, 0.0016), (math.cos(ang) * r, y0 + length * 0.6, math.sin(ang) * r), bevel=0, rot=(0, -math.degrees(ang) + 90, 0))


def muzzle_brake(P, y0, length=0.06):
    P.lathe(STEEL, [(y0, 0.0105), (y0 + 0.006, 0.0105), (y0 + 0.008, 0.013), (y0 + 0.01, 0.0105)], 'Y', segs=16)
    C = G.Part()
    for k in range(3):
        C.box(None, (0.05, 0.008, 0.012), (0, y0 + 0.02 + k * 0.014, 0.0), bevel=0)
    P.box(STEEL, (0.03, length - 0.01, 0.022), (0, y0 + 0.005 + length / 2, 0), bevel=0.003, cuts=C)
    P.cyl(RUB, 0.0045, (0, y0 + 0.01, 0), (0, y0 + length + 0.0003, 0), segs=10, ch=0)


def tube_dot(A, P, y, zr):
    """Tube red-dot on a riser; hollow so the dot is seen through it."""
    zc = zr + 0.038
    P.box(ALU, (0.026, 0.05, 0.022), (0, y + 0.035, zr + 0.011), bevel=0.003)
    P.cyl(STEEL, 0.007, (0.013, y + 0.035, zr + 0.006), (0.024, y + 0.035, zr + 0.006), segs=10)
    ro, ri = 0.0185, 0.0145
    P.lathe(ALU, [(y, ri), (y, ro - 0.002), (y + 0.003, ro), (y + 0.014, ro), (y + 0.016, ro - 0.0025), (y + 0.054, ro - 0.0025), (y + 0.056, ro), (y + 0.067, ro), (y + 0.07, ro - 0.002),
                  (y + 0.07, ri), (y, ri)], 'Y', at=(0, 0, zc), segs=28, cap=False)
    P.cyl(ALU, 0.008, (0.012, y + 0.035, zc), (0.031, y + 0.035, zc), segs=14)                       # brightness turret
    P.cyl(RUB, 0.0088, (0.031, y + 0.035, zc), (0.036, y + 0.035, zc), segs=14)
    P.cyl(ALU, 0.007, (0, y + 0.035, zc + 0.012), (0, y + 0.035, zc + 0.026), segs=12)               # elevation cap
    L = A.part("SightGlass")
    L.lathe("glass_lens", [(0, 0.0), (0.0003, ri)], 'Y', at=(0, y + 0.06, zc), segs=20)
    R = A.part("Reticle")
    R.lathe("reticle", [(0, 0.0), (0.0001, 0.00045)], 'Y', at=(0, y + 0.058, zc), segs=10)
    A.socket("Sight", (0, y, zc))
    return zc


def scope(A, P, y, zr):
    """Fixed-power scope in two rings. ADS uses the 2D scope overlay, so the lenses are opaque."""
    zc = zr + 0.034
    for ry in (y + 0.085, y + 0.185):
        P.box(ALU, (0.024, 0.018, 0.02), (0, ry, zr + 0.010), bevel=0.002)
        P.lathe(ALU, [(-0.009, 0.0175), (-0.007, 0.0195), (0.007, 0.0195), (0.009, 0.0175)], 'Y', at=(0, ry, zc), segs=20)
        for s in (-1, 1):
            P.screw(STEEL, (s * 0.0195, ry, zc + 0.006), (s, 0, 0), r=0.002)
            P.screw(STEEL, (s * 0.0125, ry, zr + 0.006), (s, 0, 0), r=0.0026)
    pts = [(y - 0.012, 0.0), (y - 0.012, 0.0165), (y - 0.010, 0.0205), (y + 0.004, 0.022), (y + 0.022, 0.022), (y + 0.026, 0.0205), (y + 0.05, 0.0195), (y + 0.062, 0.0152),
           (y + 0.215, 0.0152), (y + 0.245, 0.0235), (y + 0.30, 0.0245), (y + 0.305, 0.0235), (y + 0.305, 0.021), (y + 0.290, 0.021), (y + 0.290, 0.0)]
    P.lathe(ALU, pts, 'Y', at=(0, 0, zc), segs=26)
    P.lathe(RUB, [(y + 0.0, 0.0225), (y + 0.002, 0.0235), (y + 0.018, 0.0235), (y + 0.02, 0.0225)], 'Y', at=(0, 0, zc), segs=26)   # zoom ring
    P.box(ALU, (0.034, 0.034, 0.034), (0, y + 0.135, zc), bevel=0.006)                                                            # turret saddle
    P.cyl(ALU, 0.0115, (0, y + 0.135, zc + 0.015), (0, y + 0.135, zc + 0.034), segs=18)
    P.cyl(RUB, 0.0125, (0, y + 0.135, zc + 0.026), (0, y + 0.135, zc + 0.033), segs=18)
    P.cyl(ALU, 0.0115, (0.015, y + 0.135, zc), (0.034, y + 0.135, zc), segs=18)
    P.cyl(RUB, 0.0125, (0.026, y + 0.135, zc), (0.033, y + 0.135, zc), segs=18)
    P.cyl(ALU, 0.010, (-0.015, y + 0.135, zc), (-0.028, y + 0.135, zc), segs=18)
    P.lathe("glass_dark", [(0, 0.0), (0.0005, 0.0165)], 'Y', at=(0, y - 0.0125, zc), segs=20)
    P.lathe("glass_dark", [(0, 0.021), (0.002, 0.0)], 'Y', at=(0, y + 0.292, zc), segs=20)
    A.socket("Sight", (0, y - 0.012, zc))
    return zc


def front_sight_tower(P, y, zr_bore=0.0):
    P.prof(STEEL, [(y - 0.012, 0.009), (y + 0.012, 0.009), (y + 0.006, 0.056), (y - 0.002, 0.056)], -0.005, 0.005, 'X', bevel=0.0015)
    P.cyl(STEEL, 0.0125, (0, y - 0.012, 0), (0, y + 0.012, 0), segs=16)
    for s in (-1, 1):
        P.prof(STEEL, [(y - 0.003, 0.054), (y + 0.006, 0.054), (y + 0.005, 0.069), (y - 0.002, 0.069)], s * 0.006 - 0.001, s * 0.006 + 0.001, 'X', bevel=0.0006, segs=1)
    P.cyl(STEEL, 0.0011, (0, y + 0.002, 0.054), (0, y + 0.002, 0.066), segs=6, ch=0)


def ribbed_handguard(P, y0, y1, mat=POLY):
    pts = [(y0, 0.019), (y0 + 0.004, 0.0235)]
    n = int((y1 - y0 - 0.02) / 0.016)
    for k in range(n):
        ya = y0 + 0.012 + k * 0.016
        t = k / max(n - 1, 1)
        r = 0.0245 - 0.004 * t
        pts += [(ya, r), (ya + 0.009, r), (ya + 0.011, r - 0.0022), (ya + 0.014, r - 0.0022)]
    pts += [(y1 - 0.006, 0.0205), (y1, 0.018)]
    P.lathe(mat, pts, 'Y', segs=20)
    P.lathe(STEEL, [(y0 - 0.008, 0.022), (y0 - 0.006, 0.026), (y0 + 0.002, 0.026), (y0 + 0.004, 0.022)], 'Y', segs=20)          # delta ring
    P.lathe(STEEL, [(y1 - 0.002, 0.018), (y1, 0.0205), (y1 + 0.004, 0.0205), (y1 + 0.006, 0.018)], 'Y', segs=20)               # end cap


def bipod(P, y, zb):
    P.box(ALU, (0.03, 0.03, 0.012), (0, y, zb - 0.006), bevel=0.002)
    for s in (-1, 1):
        P.cyl(STEEL, 0.0055, (s * 0.016, y, zb - 0.012), (s * 0.019, y + 0.17, zb - 0.016), segs=10)
        P.cyl(ALU, 0.0068, (s * 0.018, y + 0.10, zb - 0.014), (s * 0.019, y + 0.165, zb - 0.016), segs=10)
        P.box(RUB, (0.016, 0.022, 0.014), (s * 0.019, y + 0.178, zb - 0.016), bevel=0.003)


def ar_platform(name, hg1=0.505, barrel=0.545, muzzle="suppressor", optic="holo", handguard="mlok", fixed_stock=False, mag_len=0.185, mag_curve=0.03, bip=False, barrel_r=0.0092):
    A = G.Asset(name, "weapons")
    P = A.part("Body")
    HG0 = 0.208
    ar_receiver(A, P)
    ar_stock(A, fixed_stock)
    zr = 0.0275 + RAIL_H
    if handguard == "mlok":
        P.prof(ALU, HG_CS, HG0, hg1, 'Y', bevel=0.0012, segs=1, cuts=mlok_cutters(HG0, hg1))
        P.rail(ALU, HG0 + 0.002, hg1 - 0.002, 0.0275)
        P.lathe(STEEL, [(0.198, 0.022), (0.2, 0.0245), (0.206, 0.0245), (0.208, 0.022)], 'Y', segs=18)
        for s in (-1, 1):
            for sy in (0.218, 0.232):
                P.screw(STEEL, (s * 0.021, sy, -0.008), (s, 0, 0), r=0.0026, hexagon=False)
        P.cyl(STEEL, 0.0128, (0, 0.395, 0), (0, 0.428, 0), segs=16)
        P.cyl(STEEL, 0.003, (0, 0.21, 0.0145), (0, 0.41, 0.0145), segs=8, ch=0)
        backup_sight(P, hg1 - 0.043, zr, True)
        backup_sight(P, 0.008, zr, False)
    else:
        ribbed_handguard(P, HG0 + 0.006, hg1)
        front_sight_tower(P, hg1 + 0.03)
        backup_sight(P, 0.008, zr, False)
    P.cyl(STEEL, barrel_r, (0, 0.20, 0), (0, barrel, 0), segs=16)
    if muzzle == "suppressor":
        suppressor(P, barrel - 0.033, 0.195)
        mz = barrel - 0.033 + 0.195
    elif muzzle == "brake":
        muzzle_brake(P, barrel - 0.012)
        mz = barrel + 0.05
    else:
        flash_hider(P, barrel - 0.01)
        mz = barrel + 0.036
    S = A.part("Optic")
    if optic == "holo":
        holo_sight(A, S, 0.062, zr)
    elif optic == "dot":
        tube_dot(A, S, 0.075, zr)
    else:
        scope(A, S, 0.035, zr)
    if bip:
        bipod(P, HG0 + 0.07, -0.026)
    M = A.part("Mag", pivot=(0, 0.143, -0.06))
    ar_mag(M, length=mag_len, curve=mag_curve)
    hand_y = 0.335 if hg1 > 0.45 else 0.30
    A.socket("Muzzle", (0, mz + 0.004, 0))
    A.socket("Rail_Top", (0, 0.30, zr))
    A.socket("Rail_Side", (-0.0215 if handguard == "mlok" else -0.0245, hg1 - 0.05, 0.0005))
    A.socket("Rail_Side_R", (0.0215 if handguard == "mlok" else 0.0245, hg1 - 0.05, 0.0005))
    A.socket("Hand_R", (0, 0.02, -0.047))
    A.socket("Hand_L", (0, hand_y, -0.026))
    A.socket("Eject", (0.024, 0.12, 0.004))
    rifle_anims(A, mag_drop=(0.0, -0.035, -0.20), hand_to_mag=(0.012, 0.143 - hand_y - 0.008, -0.105), hand_to_catch=(-0.01, 0.145 - hand_y, 0.0))
    A.meta = {"origin": (0, 0.02, -0.047)}
    return A


def service_rifle():
    return ar_platform("service_rifle")


def carbine():
    return ar_platform("carbine", hg1=0.40, barrel=0.47, muzzle="hider", optic="dot", handguard="ribbed")


def marksman():
    return ar_platform("marksman", hg1=0.56, barrel=0.68, muzzle="brake", optic="scope", fixed_stock=True, mag_len=0.115, mag_curve=0.008, bip=True, barrel_r=0.0105)


# ------------------------------------------------------------------ compact SMG
def smg():
    A = G.Asset("smg", "weapons")
    P = A.part("Body")
    cs = [(-0.017, -0.024), (0.017, -0.024), (0.021, -0.018), (0.021, 0.018), (0.016, 0.026), (-0.016, 0.026), (-0.021, 0.018), (-0.021, -0.018)]
    C = G.Part()
    C.box(None, (0.02, 0.05, 0.016), (0.021, 0.125, 0.006), bevel=0)                           # ejection port
    C.box(None, (0.02, 0.10, 0.006), (-0.021, 0.19, 0.012), bevel=0)                           # charging slot (left)
    for k in range(4):
        C.box(None, (0.06, 0.016, 0.005), (0, 0.215 + k * 0.024, -0.008), bevel=0, rot=(0, 0, 0))
    P.prof(ALU, cs, -0.02, 0.30, 'Y', bevel=0.002, cuts=C)
    P.rail(ALU, 0.0, 0.29, 0.026)
    zr = 0.026 + RAIL_H
    # lower: grip frame + magwell ahead of the trigger
    P.prof(POLY, [(-0.02, -0.022), (0.20, -0.022), (0.20, -0.046), (0.176, -0.080), (0.128, -0.080), (0.122, -0.050), (0.05, -0.050), (0.0, -0.056), (-0.02, -0.046)],
           -0.0175, 0.0175, 'X', bevel=0.003)
    P.box(POLY, (0.013, 0.07, 0.0032), (0, 0.086, -0.0815), bevel=0.0012)
    P.box(POLY, (0.013, 0.0032, 0.03), (0, 0.05, -0.068), bevel=0.0012, rot=(-16, 0, 0))
    P.prof(STEEL, [(0.090, -0.050), (0.097, -0.050), (0.0945, -0.062), (0.099, -0.072), (0.0955, -0.074), (0.088, -0.062)], -0.003, 0.003, 'X', bevel=0.001, segs=1)
    pistol_grip(P, y=0.036, top=-0.050)
    P.cyl(STEEL, 0.0055, (-0.0205, 0.05, -0.032), (-0.0175, 0.05, -0.032), segs=12)
    P.box(STEEL, (0.003, 0.02, 0.005), (-0.021, 0.042, -0.03), bevel=0.001, segs=1, rot=(20, 0, 0))
    P.box(STEEL, (0.003, 0.014, 0.02), (0.019, 0.118, -0.06), bevel=0.001, segs=1)             # mag catch paddle
    for py, pz in ((0.0, -0.03), (0.19, -0.03)):
        P.cyl(STEEL, 0.0035, (-0.019, py, pz), (0.019, py, pz), segs=10)
    # barrel shroud + stubby suppressor
    P.lathe(STEEL, [(0.30, 0.016), (0.304, 0.019), (0.312, 0.019), (0.314, 0.0165)], 'Y', segs=20)
    suppressor(P, 0.306, 0.15, r=0.0195)
    # rear end cap + folded wire stock on the right side
    P.box(ALU, (0.04, 0.012, 0.05), (0, -0.026, 0.0), bevel=0.004)
    P.cyl(STEEL, 0.006, (0.0, -0.03, -0.028), (0.0, -0.03, 0.028), segs=10)
    K = A.part("StockFold")
    for z in (0.016, -0.016):
        K.cyl(STEEL, 0.004, (0.0265, -0.03, z), (0.0265, 0.20, z), segs=8)
    K.prof(RUB, [(0.198, -0.03), (0.212, -0.03), (0.212, 0.03), (0.198, 0.03)], 0.022, 0.032, 'X', bevel=0.003)
    K.cyl(STEEL, 0.005, (0.0, -0.03, 0.0), (0.0265, -0.03, 0.0), segs=8)
    # mini reflex sight
    S = A.part("Optic")
    y = 0.07
    zc = zr + 0.022
    S.box(ALU, (0.028, 0.046, 0.009), (0, y + 0.023, zr + 0.0045), bevel=0.002)
    S.box(ALU, (0.026, 0.02, 0.012), (0, y + 0.01, zr + 0.011), bevel=0.003)
    for s in (-1, 1):
        S.prof(ALU, [(y + 0.030, zr + 0.008), (y + 0.046, zr + 0.008), (y + 0.044, zc + 0.014), (y + 0.036, zc + 0.014)], s * 0.0135 - 0.0015, s * 0.0135 + 0.0015, 'X', bevel=0.001)
    S.box(ALU, (0.03, 0.009, 0.003), (0, y + 0.040, zc + 0.014), bevel=0.001)
    L = A.part("SightGlass")
    L.box("glass_lens", (0.024, 0.001, 0.024), (0, y + 0.041, zc), bevel=0)
    R = A.part("Reticle")
    R.lathe("reticle", [(0, 0.0), (0.0001, 0.0005)], 'Y', at=(0, y + 0.0395, zc), segs=10)
    A.socket("Sight", (0, y + 0.01, zc))
    B = A.part("Bolt", pivot=(0.011, 0.125, 0.006))
    B.box(BARE, (0.012, 0.075, 0.015), (0.0125, 0.135, 0.006), bevel=0.001, segs=1)
    Cg = A.part("Charge", pivot=(-0.022, 0.225, 0.012))
    Cg.cyl(STEEL, 0.0045, (-0.016, 0.225, 0.012), (-0.034, 0.225, 0.012), segs=10)
    Cg.cyl(RUB, 0.0065, (-0.034, 0.225, 0.012), (-0.046, 0.225, 0.012), segs=12)
    M = A.part("Mag", pivot=(0, 0.151, -0.07))
    M.prof(STEEL, [(0.132, -0.045), (0.170, -0.045), (0.180, -0.215), (0.142, -0.215)], -0.011, 0.011, 'X', bevel=0.002)
    M.prof(POLY, [(0.139, -0.213), (0.183, -0.213), (0.184, -0.224), (0.140, -0.224)], -0.0125, 0.0125, 'X', bevel=0.002)
    for k in range(4):
        M.box(STEEL, (0.0235, 0.004, 0.12), (0, 0.142 + k * 0.009 + 0.003, -0.14), bevel=0.0008, segs=1, rot=(3.4, 0, 0))
    A.socket("Muzzle", (0, 0.46, 0))
    A.socket("Rail_Top", (0, 0.2, zr))
    A.socket("Rail_Side", (-0.0215, 0.27, 0.0))
    A.socket("Rail_Side_R", (0.0215, 0.27, -0.012))
    A.socket("Hand_R", (0, 0.036, -0.050))
    A.socket("Hand_L", (0, 0.255, -0.024))
    A.socket("Eject", (0.024, 0.125, 0.008))
    rifle_anims(A, mag_drop=(0.0, 0.012, -0.21), hand_to_mag=(0.012, 0.151 - 0.255 - 0.006, -0.12), hand_to_catch=(-0.03, -0.03, 0.03), bolt_travel=0.045)
    A.meta = {"origin": (0, 0.036, -0.050)}
    return A


# ------------------------------------------------------------------ pistols
def pistol(name, match=False):
    A = G.Asset(name, "weapons")
    L = 0.176 if match else 0.156
    slide_mat = ALU
    S = A.part("Slide", pivot=(0, 0.05, 0.0))
    cs = [(-0.0132, -0.009), (0.0132, -0.009), (0.0132, 0.008), (0.0105, 0.0138), (-0.0105, 0.0138), (-0.0132, 0.008)]
    C = G.Part()
    C.box(None, (0.016, 0.036, 0.014), (0.010, 0.060, 0.011), bevel=0)                         # ejection port
    for k in range(7):
        for s in (-1, 1):
            C.box(None, (0.0016, 0.0024, 0.017), (s * 0.0134, -0.024 + k * 0.0052, 0.0), bevel=0, rot=(-14, 0, 0))
    if match:
        for k in range(3):
            C.box(None, (0.05, 0.016, 0.0065), (0, 0.098 + k * 0.022, 0.004), bevel=0)        # lightening windows
        C.box(None, (0.011, 0.062, 0.01), (0, 0.12, 0.014), bevel=0)
        for k in range(4):
            for s in (-1, 1):
                C.box(None, (0.0016, 0.0024, 0.017), (s * 0.0134, 0.150 + k * 0.0052, 0.0), bevel=0, rot=(-14, 0, 0))
    S.prof(slide_mat, cs, -0.032, L, 'Y', bevel=0.0013, cuts=C)
    zt = 0.0138
    if match:
        # micro red dot on the slide + low front post
        S.box(ALU, (0.026, 0.040, 0.006), (0, -0.006, zt + 0.003), bevel=0.0015)
        for s in (-1, 1):
            S.prof(ALU, [(0.002, zt + 0.004), (0.014, zt + 0.004), (0.013, zt + 0.027), (0.006, zt + 0.027)], s * 0.012 - 0.0014, s * 0.012 + 0.0014, 'X', bevel=0.001)
        S.box(ALU, (0.0268, 0.008, 0.003), (0, 0.0095, zt + 0.0268), bevel=0.001)
        Lp = A.part("SightGlass", parent="Slide")
        Lp.box("glass_lens", (0.0215, 0.001, 0.02), (0, 0.010, zt + 0.0155), bevel=0)
        R = A.part("Reticle", parent="Slide")
        R.lathe("reticle", [(0, 0.0), (0.0001, 0.00055)], 'Y', at=(0, 0.0088, zt + 0.0155), segs=10)
        A.socket("Sight", (0, -0.02, zt + 0.0155), parent="Slide")
        S.box(STEEL, (0.0035, 0.007, 0.004), (0, L - 0.008, zt + 0.0018), bevel=0.0008, segs=1)
    else:
        S.box(STEEL, (0.0036, 0.007, 0.0052), (0, L - 0.008, zt + 0.0024), bevel=0.0008, segs=1)                         # front post
        S.cyl("paint_white", 0.0011, (0, L - 0.0117, zt + 0.0032), (0, L - 0.0114, zt + 0.0032), segs=8, ch=0)
        S.box(STEEL, (0.022, 0.009, 0.0022), (0, -0.024, zt + 0.001), bevel=0.0006, segs=1)                              # rear sight base
        for s in (-1, 1):
            S.box(STEEL, (0.0075, 0.009, 0.0052), (s * 0.0064, -0.024, zt + 0.0026), bevel=0.0008, segs=1)
            S.cyl("paint_white", 0.0011, (s * 0.0064, -0.0286, zt + 0.0032), (s * 0.0064, -0.0283, zt + 0.0032), segs=8, ch=0)
        A.socket("Sight", (0, -0.03, zt + 0.0046), parent="Slide")
    P = A.part("Body")
    # barrel + chamber hood (visible through the port and at the muzzle)
    bm = "brass" if match else BARE
    P.cyl(bm, 0.0068, (0, 0.03, 0.001), (0, L + (0.0 if match else 0.003), 0.001), segs=14)
    P.box(bm, (0.017, 0.034, 0.014), (0.0, 0.060, 0.004), bevel=0.001, segs=1)
    P.cyl(RUB, 0.0046, (0, L - 0.01, 0.001), (0, L + (0.0003 if match else 0.0033), 0.001), segs=10, ch=0)
    P.cyl(STEEL, 0.004, (0, 0.05, -0.0045), (0, L - 0.003, -0.0045), segs=8)                                             # guide rod
    if match:
        C = G.Part()
        for k in range(2):
            C.box(None, (0.008, 0.007, 0.03), (0, L + 0.012 + k * 0.012, 0.012), bevel=0)
        P.prof(ALU, [(-0.0135, -0.021), (0.0135, -0.021), (0.0135, 0.008), (0.0105, 0.0138), (-0.0105, 0.0138), (-0.0135, 0.008)], L + 0.001, L + 0.034, 'Y', bevel=0.0014, cuts=C)
        P.cyl(RUB, 0.0046, (0, L + 0.02, 0.001), (0, L + 0.0345, 0.001), segs=10, ch=0)
    # polymer frame with grip
    C = G.Part()
    C.prof(None, [(0.030, -0.030), (0.076, -0.030), (0.073, -0.052), (0.036, -0.054)], -0.05, 0.05, 'X', bevel=0)
    P.prof(POLY, [(-0.050, -0.0085), (0.150, -0.0085), (0.150, -0.022), (0.090, -0.0255), (0.086, -0.038), (0.078, -0.059), (0.030, -0.061), (0.012, -0.045),
                  (-0.022, -0.122), (-0.076, -0.122), (-0.046, -0.034), (-0.056, -0.020)], -0.0134, 0.0134, 'X', bevel=0.0024, segs=2, cuts=C)
    P.box(POLY, (0.0272, 0.19, 0.004), (0, 0.052, -0.0075), bevel=0.0008, segs=1)                                        # slide rails (closes the slide/frame seam)
    for k in range(3):                                                                                                    # accessory rail slots
        P.box(POLY, (0.0215, 0.005, 0.003), (0, 0.105 + k * 0.014, -0.0245), bevel=0.0008, segs=1)
    for s in (-1, 1):                                                                                                     # grip texture panels
        P.prof(RUB, [(-0.012, -0.050), (-0.034, -0.112), (-0.066, -0.112), (-0.046, -0.050)], s * 0.0139 - 0.0006, s * 0.0139 + 0.0006, 'X', bevel=0.0005, segs=1)
    P.prof(STEEL, [(0.052, -0.027), (0.058, -0.027), (0.056, -0.040), (0.060, -0.050), (0.057, -0.052), (0.050, -0.040)], -0.003, 0.003, 'X', bevel=0.001, segs=1)   # trigger
    P.box(STEEL, (0.0022, 0.03, 0.005), (-0.0145, 0.040, -0.012), bevel=0.0008, segs=1)                                 # slide stop
    P.cyl(STEEL, 0.004, (-0.0155, 0.012, -0.034), (-0.0125, 0.012, -0.034), segs=10)                                    # mag release
    for s in (-1, 1):
        P.box(STEEL, (0.0018, 0.012, 0.004), (s * 0.0142, 0.072, -0.016), bevel=0.0006, segs=1)                         # takedown tabs
    if match:
        P.prof("paint_grey", [(-0.020, -0.119), (-0.079, -0.119), (-0.084, -0.132), (-0.016, -0.132)], -0.017, 0.017, 'X', bevel=0.003)       # flared magwell
    M = A.part("Mag", pivot=(-0.03, 0.0, -0.08))
    M.prof(STEEL, [(-0.040, -0.030), (-0.004, -0.030), (-0.030, -0.120), (-0.068, -0.120)], -0.0098, 0.0098, 'X', bevel=0.0015)
    zb = -0.134 if match else -0.123
    M.prof(POLY, [(-0.024, zb + 0.004), (-0.074, zb + 0.004), (-0.078, zb - 0.008), (-0.022, zb - 0.008)], -0.0142, 0.0142, 'X', bevel=0.003)
    A.socket("Muzzle", (0, L + (0.036 if match else 0.004), 0.001))
    A.socket("Rail_Side", (0, 0.118, -0.026))
    A.socket("Rail_Side_R", (0, 0.118, -0.026))
    A.socket("Hand_R", (0, -0.016, -0.014))
    A.socket("Hand_L", (0, -0.016, -0.014))
    A.socket("Eject", (0.016, 0.06, 0.012))
    # clips
    A.key("fire", "Slide", 0)
    A.key("fire", "Slide", 1, loc=(0, -0.038, 0))
    A.key("fire", "Slide", 3)
    drop = Vector((0, -0.062, -0.215))
    for f, k in ((0, 0), (8, 0), (12, 0.12), (18, 1.0), (30, 1.0), (38, 0.2), (42, 0.03), (44, -0.01), (46, 0), (60, 0)):
        A.key("reload", "Mag", f, loc=tuple(drop * k))
    for f, l, r in ((0, (0, 0, 0), (0, 0, 0)), (8, (-0.02, -0.02, -0.07), (0, 0, -15)), (18, (-0.03, -0.10, -0.30), (-10, 0, -20)), (30, (-0.03, -0.10, -0.30), (-10, 0, -20)),
                    (38, (-0.012, -0.045, -0.14), (0, 0, -10)), (44, (-0.004, -0.03, -0.085), (0, 0, -6)), (48, (-0.004, -0.03, -0.085), (0, 0, -6)), (60, (0, 0, 0), (0, 0, 0))):
        A.key("reload", "Hand_L", f, loc=l, rot=r)
    for f, d in ((0, 0), (5, -0.038), (7, -0.038), (10, 0)):
        A.key("rack", "Slide", f, loc=(0, d, 0))
    A.meta = {"origin": (0, -0.016, -0.014)}
    return A


def revolver():
    A = G.Asset("revolver", "weapons")
    P = A.part("Body")
    C = G.Part()
    C.box(None, (0.05, 0.046, 0.046), (0, 0.036, -0.012), bevel=0)                               # cylinder window
    C.prof(None, [(0.004, -0.042), (0.040, -0.042), (0.036, -0.062), (0.008, -0.064)], -0.05, 0.05, 'X', bevel=0)   # trigger guard opening
    P.prof(STEEL, [(-0.030, 0.0215), (0.066, 0.0215), (0.066, -0.030), (0.046, -0.040), (0.044, -0.060), (0.036, -0.070), (0.004, -0.071), (-0.012, -0.045),
                   (-0.020, -0.110), (-0.060, -0.110), (-0.052, -0.050), (-0.040, -0.012), (-0.036, 0.010)], -0.0085, 0.0085, 'X', bevel=0.003, segs=2, cuts=C)
    P.box(STEEL, (0.030, 0.006, 0.040), (0, 0.009, -0.012), bevel=0.003)                          # recoil shield
    # barrel with full underlug and vented rib
    P.cyl(STEEL, 0.0088, (0, 0.066, 0), (0, 0.176, 0), segs=16)
    P.prof(STEEL, [(-0.0088, -0.002), (0.0088, -0.002), (0.0078, -0.016), (0.0045, -0.021), (-0.0045, -0.021), (-0.0078, -0.016)], 0.066, 0.150, 'Y', bevel=0.0018)
    P.prof(STEEL, [(0.150, -0.002), (0.150, -0.021), (0.170, -0.004)], -0.0078, 0.0078, 'X', bevel=0.0015)
    C = G.Part()
    for k in range(4):
        C.box(None, (0.03, 0.016, 0.0036), (0, 0.084 + k * 0.024, 0.0115), bevel=0)
    P.prof(STEEL, [(-0.0042, 0.006), (0.0042, 0.006), (0.0042, 0.0152), (-0.0042, 0.0152)], 0.060, 0.176, 'Y', bevel=0.001, cuts=C)
    P.cyl(RUB, 0.0056, (0, 0.166, 0), (0, 0.1763, 0), segs=12, ch=0)
    P.prof(STEEL, [(0.150, 0.0152), (0.174, 0.0152), (0.172, 0.0235), (0.164, 0.0235)], -0.0017, 0.0017, 'X', bevel=0.0006, segs=1)   # front ramp
    P.box("medic_red", (0.0036, 0.006, 0.004), (0, 0.166, 0.0222), bevel=0.0005, segs=1)
    for s in (-1, 1):
        P.box(STEEL, (0.0055, 0.008, 0.0052), (s * 0.0052, -0.022, 0.0238), bevel=0.0008, segs=1)                       # rear notch
    P.box(STEEL, (0.016, 0.012, 0.003), (0, -0.022, 0.0222), bevel=0.0008, segs=1)
    P.prof(STEEL, [(0.022, -0.041), (0.027, -0.041), (0.025, -0.052), (0.028, -0.060), (0.025, -0.062), (0.019, -0.052)], -0.003, 0.003, 'X', bevel=0.001, segs=1)   # trigger
    P.box(STEEL, (0.003, 0.016, 0.009), (-0.0095, -0.004, -0.004), bevel=0.001, segs=1)                                 # cylinder latch
    P.cyl(STEEL, 0.003, (0, 0.066, -0.0135), (0, 0.150, -0.0135), segs=8)                                               # ejector rod
    # wooden grips
    P.prof("wood", [(-0.011, -0.042), (-0.019, -0.070), (-0.014, -0.092), (-0.020, -0.116), (-0.060, -0.120), (-0.066, -0.095), (-0.056, -0.050), (-0.047, -0.022), (-0.037, -0.026)],
           -0.0145, 0.0145, 'X', bevel=0.0065, segs=3)
    for s in (-1, 1):
        P.cyl("brass", 0.0055, (s * 0.0148, -0.040, -0.062), (s * 0.0158, -0.040, -0.062), segs=14, ch=0.0003)
        P.screw(STEEL, (s * 0.0148, -0.044, -0.098), (s, 0, 0), r=0.003, hexagon=False)
    Cy = A.part("Cylinder", pivot=(0, 0.036, -0.0135))
    C = G.Part()
    for a in range(6):
        ang = a * math.pi / 3
        C.cyl(None, 0.0062, (math.sin(ang + math.pi / 6) * 0.0252, 0.030, -0.0135 + math.cos(ang + math.pi / 6) * 0.0252),
              (math.sin(ang + math.pi / 6) * 0.0252, 0.070, -0.0135 + math.cos(ang + math.pi / 6) * 0.0252), segs=10, ch=0)
        C.cyl(None, 0.0052, (math.sin(ang) * 0.0135, 0.052, -0.0135 + math.cos(ang) * 0.0135), (math.sin(ang) * 0.0135, 0.07, -0.0135 + math.cos(ang) * 0.0135), segs=10, ch=0)
    Cy.lathe(STEEL, [(0.0145, 0.0), (0.0145, 0.0205), (0.016, 0.0218), (0.056, 0.0218), (0.0575, 0.0205), (0.0575, 0.0)], 'Y', at=(0, 0, -0.0135), segs=24, cuts=C)
    for a in range(6):
        ang = a * math.pi / 3
        Cy.cyl("brass", 0.0056, (math.sin(ang) * 0.0135, 0.0128, -0.0135 + math.cos(ang) * 0.0135), (math.sin(ang) * 0.0135, 0.0146, -0.0135 + math.cos(ang) * 0.0135), segs=10, ch=0.0003)
    H = A.part("Hammer", pivot=(0, -0.022, 0.0))
    H.prof(STEEL, [(-0.016, -0.004), (-0.008, 0.004), (-0.010, 0.020), (-0.018, 0.031), (-0.028, 0.033), (-0.029, 0.029), (-0.021, 0.024), (-0.020, 0.010), (-0.026, 0.0)],
           -0.0032, 0.0032, 'X', bevel=0.001, segs=1)
    A.socket("Sight", (0, -0.026, 0.0252))
    A.socket("Muzzle", (0, 0.18, 0))
    A.socket("Rail_Side", (0, 0.12, -0.026))
    A.socket("Rail_Side_R", (0, 0.12, -0.026))
    A.socket("Hand_R", (0, -0.028, -0.034))
    A.socket("Hand_L", (0, -0.028, -0.034))
    for f, r in ((0, 0), (1, -42), (2, 0), (4, 0)):
        A.key("fire", "Hammer", f, rot=(r, 0, 0))
    for f, r in ((0, 0), (3, 60), (4, 60)):
        A.key("fire", "Cylinder", f, rot=(0, r, 0))
    out = (-0.034, 0.0, -0.014)
    for f, l, r in ((0, (0, 0, 0), 0), (8, (0, 0, 0), 0), (14, out, 0), (20, out, 0), (34, out, 360), (46, out, 360), (52, (0, 0, 0), 360), (60, (0, 0, 0), 360)):
        A.key("reload", "Cylinder", f, loc=l, rot=(0, r, 0))
    for f, l, r in ((0, (0, 0, 0), (0, 0, 0)), (10, (-0.03, 0.04, 0.02), (0, 0, -10)), (16, (-0.05, 0.05, 0.0), (0, 0, -14)), (24, (-0.06, -0.06, -0.22), (0, 0, -20)),
                    (32, (-0.05, 0.05, 0.0), (0, 0, -14)), (46, (-0.05, 0.05, 0.0), (0, 0, -14)), (52, (-0.02, 0.04, 0.02), (0, 0, -8)), (60, (0, 0, 0), (0, 0, 0))):
        A.key("reload", "Hand_L", f, loc=l, rot=r)
    A.meta = {"origin": (0, -0.028, -0.034)}
    return A


BUILDERS = {"p9": lambda: pistol("p9"), "p9_match": lambda: pistol("p9_match", True), "revolver": revolver, "smg": smg,
            "carbine": carbine, "service_rifle": service_rifle, "marksman": marksman}


def build_all(only=None):
    out = {}
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        A = fn()
        A.build(origin=A.meta["origin"])
        out[name] = G.export(name, "weapons")
        out[name + "_w"] = G.export_world(name, "weapons")
    return out


def rifle_anims(A, mag_drop=(0.0, -0.035, -0.20), hand_to_mag=(0.012, -0.200, -0.105), hand_to_catch=(-0.01, -0.19, 0.0), bolt_travel=0.06):
    """Clips at 30 fps: fire (0.1 s), reload (2.0 s, played scaled to the gun's reload time), dry."""
    # fire: bolt cycles
    A.key("fire", "Bolt", 0)
    A.key("fire", "Bolt", 1, loc=(0, -bolt_travel, 0))
    A.key("fire", "Bolt", 3)
    # reload
    out = Vector(mag_drop)
    far = out + Vector((-0.06, -0.08, -0.22))
    h = Vector(hand_to_mag)
    for f, ml, mr in ((0, (0, 0, 0), (0, 0, 0)), (12, (0, 0, 0), (0, 0, 0)), (15, (0, 0, -0.012), (0, 0, 0)), (20, tuple(out), (-14, 0, 6)), (25, tuple(far), (-30, 0, 18)),
                      (31, tuple(far), (-30, 0, 18)), (37, tuple(out * 0.8), (-10, 0, 4)), (42, (0, 0, -0.03), (0, 0, 0)), (44, (0, 0, 0.004), (0, 0, 0)), (46, (0, 0, 0), (0, 0, 0)), (60, (0, 0, 0), (0, 0, 0))):
        A.key("reload", "Mag", f, loc=ml, rot=mr)
    hk = [(0, (0, 0, 0), (0, 0, 0)), (4, (-0.01, -0.02, -0.03), (0, 0, -6)), (11, tuple(h), (10, 0, -8)), (15, tuple(h + Vector((0, 0, -0.012))), (10, 0, -8)),
          (20, tuple(h + out), (-4, 0, -2)), (25, tuple(h + far), (-20, 0, 10)), (31, tuple(h + far), (-20, 0, 10)), (37, tuple(h + out * 0.8), (0, 0, -4)),
          (42, tuple(h + Vector((0, 0, -0.03))), (10, 0, -8)), (44, tuple(h + Vector((0, 0, 0.004))), (10, 0, -8)), (47, tuple(h), (10, 0, -8)),
          (51, tuple(Vector(hand_to_catch) + Vector((-0.03, 0, 0))), (0, 0, -20)), (53, tuple(hand_to_catch), (0, 0, -20)), (55, tuple(Vector(hand_to_catch) + Vector((-0.02, 0, 0))), (0, 0, -18)), (60, (0, 0, 0), (0, 0, 0))]
    for f, l, r in hk:
        A.key("reload", "Hand_L", f, loc=l, rot=r)
    for f, d in ((0, 0), (52, 0), (53, -bolt_travel), (54, -bolt_travel), (56, 0), (60, 0)):
        A.key("reload", "Bolt", f, loc=(0, d, 0))
    # dry / inspect-free clip: charging handle rack (used when a fresh gun is drawn)
    for f, d in ((0, 0), (5, -0.055), (7, -0.055), (10, 0)):
        A.key("rack", "Charge", f, loc=(0, d, 0))
        A.key("rack", "Bolt", f, loc=(0, d, 0))


def attach_preview_arms(asset, right="ArmR_Grip", left="ArmL_Fore"):
    """Linked duplicates of the arms on this gun's sockets for Blender preview renders (never exported)."""
    import bpy
    pc = bpy.data.collections.get("PreviewArms") or bpy.data.collections.new("PreviewArms")
    if pc.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(pc)
    for o in list(pc.objects):
        bpy.data.objects.remove(o)
    for sock, arm in (("Hand_R", right), ("Hand_L", left)):
        src = bpy.data.collections["hands"].objects[arm]
        o = bpy.data.objects.new("pv_" + arm, src.data)
        pc.objects.link(o)
        o.parent = asset.objs[sock]
    return pc
