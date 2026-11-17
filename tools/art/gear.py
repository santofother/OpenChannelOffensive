"""Breach charges, reinforcement kit, medkit, grenades, weapon attachments and night-vision goggles.

Wall devices (charges, kit) are built with their back on the plane y = 0 and their face towards -Y
(Godot +Z = out of the wall), up = +Z. Hand-held sockets: Hand_R / Hand_L."""
import math
from mathutils import Vector, Matrix
import gearlib as G

POLY, ALU, STEEL, BARE, RUB = "polymer_black", "steel_black", "steel_dark", "steel_bare", "rubber"


def _clamp(P, x, z, sx, sz, size=1.0):
    """Corner clamp: hinged steel jaw with a bolt, reaching past the device edge to the wall."""
    s = size
    P.box(STEEL, (0.034 * s, 0.022 * s, 0.030 * s), (x + sx * 0.008 * s, -0.011 * s, z + sz * 0.006 * s), bevel=0.003)
    P.box(STEEL, (0.020 * s, 0.012 * s, 0.040 * s), (x + sx * 0.020 * s, -0.006 * s, z + sz * 0.016 * s), bevel=0.002, rot=(0, sx * sz * -28, 0))
    P.cyl(BARE, 0.0045 * s, (x - 0.019 * s + sx * 0.008 * s, -0.024 * s, z), (x + 0.019 * s + sx * 0.008 * s, -0.024 * s, z), segs=10)
    P.screw(BARE, (x + sx * 0.008 * s, -0.022 * s, z + sz * 0.008 * s), (0, -1, 0), r=0.005 * s, h=0.004 * s)


def _wire(P, start, length=0.26, mat="paint_red", r=0.0028, sway=0.03, seed=0.0):
    pts = []
    s = Vector(start)
    n = 12
    for i in range(n + 1):
        t = i / n
        pts.append(s + Vector((math.sin(t * 5.0 + seed) * sway * t, -0.012 * math.sin(t * math.pi) - 0.004, -length * t)))
    P.tube_path(mat, pts, r, segs=6, cap=True)


def charge(heavy=False):
    A = G.Asset("heavy" if heavy else "ordinary", "gear")
    P = A.part("Body")
    P.smooth = 50.0
    if not heavy:
        W, H, D = 0.25, 0.18, 0.055
        P.box(STEEL, (W + 0.012, 0.006, H + 0.012), (0, -0.003, 0), bevel=0.002)                               # back plate
        P.box("polymer_olive", (W - 0.02, D - 0.008, H - 0.02), (0, -D / 2 - 0.002, 0), bevel=0.007, segs=3)   # explosive pack
        for k in range(5):                                                                                     # ribbed face
            P.box("polymer_olive", (W * 0.50, 0.004, 0.012), (-W * 0.16, -D + 0.001, -0.056 + k * 0.028), bevel=0.0015, segs=1)
        P.box("hazard", (0.040, 0.004, H - 0.045), (W * 0.33, -D + 0.0005, 0), bevel=0.001, segs=1)            # hazard panel
        P.box(POLY, (0.050, 0.006, H - 0.035), (W * 0.33, -D + 0.002, 0), bevel=0.0015, segs=1)
        P.box(POLY, (0.086, 0.016, 0.040), (-W * 0.12, -D - 0.004, 0.012), bevel=0.003)                        # detonator housing
        P.box(STEEL, (0.070, 0.004, 0.018), (-W * 0.12, -D - 0.0125, 0.012), bevel=0.001, segs=1)
        for s in (-1, 1):
            P.screw(BARE, (-W * 0.12 + s * 0.037, -D - 0.011, 0.012 + s * 0.013), (0, -1, 0), r=0.0026)
        for sx in (-1, 1):
            for sz in (-1, 1):
                _clamp(P, sx * (W / 2 - 0.004), sz * (H / 2 - 0.006), sx, sz)
        hx = [(-0.05 + 0.1 * i / 8, -D * 0.5, H / 2 + 0.004 + 0.022 * math.sin(math.pi * i / 8)) for i in range(9)]
        P.tube_path("cordura_black", hx, 0.005, segs=6, squash=0.5)                                            # carry strap
        P.cyl(POLY, 0.006, (-W * 0.12 - 0.03, -D - 0.004, -0.008), (-W * 0.12 - 0.03, -D - 0.004, -0.02), segs=8)   # cable gland
        _wire(P, (-W * 0.12 - 0.03, -D - 0.004, -0.02), 0.30)
        led = (-W * 0.12, -D - 0.0148, 0.012)
        led_size = (0.052, 0.002, 0.010)
    else:
        W, H, D = 0.40, 0.30, 0.095
        P.box(STEEL, (W + 0.016, 0.008, H + 0.016), (0, -0.004, 0), bevel=0.003)
        for sz in (-1, 1):                                                                                     # two charge blocks
            P.box(POLY, (W - 0.05, D - 0.02, H / 2 - 0.03), (0, -D / 2 - 0.002, sz * (H / 4 - 0.004)), bevel=0.009, segs=3)
            for k in range(6):
                P.box(POLY, (0.016, 0.005, H / 2 - 0.06), (-0.135 + k * 0.034, -D + 0.008, sz * (H / 4 - 0.004)), bevel=0.0015, segs=1)
            P.box("hazard", (0.050, 0.005, H / 2 - 0.055), (W * 0.36, -D + 0.008, sz * (H / 4 - 0.004)), bevel=0.001, segs=1)
        P.box(STEEL, (W + 0.004, 0.014, 0.030), (0, -D + 0.004, 0), bevel=0.003)                               # centre strongback
        for sx in (-1, 1):
            P.box(STEEL, (0.026, 0.014, H + 0.004), (sx * (W / 2 - 0.02), -D + 0.006, 0), bevel=0.003)         # frame rails
            hx = [(sx * (W / 2 + 0.006 + 0.03 * math.sin(math.pi * i / 8)), -D * 0.55, -0.06 + 0.12 * i / 8) for i in range(9)]
            P.tube_path(BARE, hx, 0.006, segs=8)                                                               # side handles
            for sz in (-1, 1):
                _clamp(P, sx * (W / 2 - 0.006), sz * (H / 2 - 0.008), sx, sz, 1.5)
                P.screw(BARE, (sx * (W / 2 - 0.02), -D - 0.001, sz * 0.09), (0, -1, 0), r=0.005, h=0.003)
        P.box(POLY, (0.13, 0.024, 0.056), (-0.03, -D - 0.008, 0), bevel=0.004)                                 # firing unit
        P.box(STEEL, (0.105, 0.004, 0.030), (-0.03, -D - 0.0205, 0.002), bevel=0.001, segs=1)
        P.cyl(RUB, 0.009, (0.022, -D - 0.02, -0.012), (0.022, -D - 0.03, -0.012), segs=12)                     # arming knob
        P.cyl("paint_red", 0.0075, (0.022, -D - 0.03, -0.012), (0.022, -D - 0.034, -0.012), segs=12)
        for i, m in enumerate(("paint_red", RUB)):
            P.cyl(POLY, 0.007, (-0.075 + i * 0.022, -D - 0.008, -0.028), (-0.075 + i * 0.022, -D - 0.008, -0.045), segs=8)
            _wire(P, (-0.075 + i * 0.022, -D - 0.008, -0.045), 0.36, m, 0.0034, 0.04, i * 1.7)
        led = (-0.04, -D - 0.0228, 0.004)
        led_size = (0.070, 0.002, 0.014)
    L = A.part("LED")
    L.box("led_orange", led_size, led, bevel=0)
    A.socket("Hand_R", (W / 2 - 0.01, -D / 2, -0.02))
    A.socket("Hand_L", (-W / 2 + 0.01, -D / 2, -0.02))
    A.meta = {"origin": (0, 0, 0), "cam": 0.55 if heavy else 0.4}
    return A


def kit():
    """Reinforcement kit as carried: folded steel plates in a red frame with a ratchet clamp."""
    A = G.Asset("kit", "gear")
    P = A.part("Body")
    W, H, D = 0.24, 0.32, 0.04
    for i in range(3):
        P.box("steel_plate", (W - 0.02 - i * 0.006, 0.009, H - 0.02 - i * 0.008), (0, -0.006 - i * 0.011, 0), bevel=0.0015)
    for sx in (-1, 1):
        P.box("paint_red", (0.022, D + 0.004, H + 0.006), (sx * (W / 2 - 0.006), -D / 2, 0), bevel=0.003)
        for k in range(5):
            P.screw(BARE, (sx * (W / 2 - 0.006), -D - 0.001, -0.12 + k * 0.06), (0, -1, 0), r=0.0045, h=0.003)
    for sz in (-1, 1):
        P.box("paint_red", (W + 0.006, D + 0.004, 0.022), (0, -D / 2, sz * (H / 2 - 0.006)), bevel=0.003)
    for ix in range(4):
        for iz in range(5):
            P.cyl(BARE, 0.0042, (-0.072 + ix * 0.048, -0.034, -0.11 + iz * 0.055), (-0.072 + ix * 0.048, -0.0375, -0.11 + iz * 0.055), segs=8, ch=0.0008)
    P.box(STEEL, (0.15, 0.016, 0.03), (0, -D - 0.006, 0.02), bevel=0.003)                                      # ratchet bar
    P.cyl(RUB, 0.011, (-0.05, -D - 0.022, 0.02), (0.05, -D - 0.022, 0.02), segs=12)                            # handle
    for s in (-1, 1):
        P.box(STEEL, (0.012, 0.022, 0.02), (s * 0.058, -D - 0.014, 0.02), bevel=0.002)
    P.box("hazard", (0.12, 0.003, 0.03), (0, -D + 0.0085, -0.09), bevel=0.0008, segs=1)
    L = A.part("LED")
    L.box("led_green", (0.02, 0.002, 0.008), (0.06, -D - 0.0145, 0.02), bevel=0)
    A.socket("Hand_R", (W / 2 - 0.004, -D / 2, -0.03))
    A.socket("Hand_L", (-W / 2 + 0.004, -D / 2, -0.03))
    for f, r in ((0, 0), (20, -8), (40, 4), (60, -6), (80, 0)):
        A.key("use", "Body", f, rot=(r, 0, 0))
    A.meta = {"origin": (0, 0, 0), "cam": 0.5}
    return A


def medkit():
    A = G.Asset("medkit", "gear")
    P = A.part("Body")
    P.smooth = 60.0
    W, H, D = 0.15, 0.20, 0.07
    P.box("cordura_olive", (W, D, H), (0, -D / 2, 0), bevel=0.014, segs=3)
    P.box("cordura_olive", (W - 0.016, 0.012, H - 0.02), (0, -D - 0.002, 0), bevel=0.005, segs=2)              # front pocket
    P.box(RUB, (W + 0.002, D * 0.14, H * 0.88), (0, -D * 0.62, 0.004), bevel=0.002, segs=1)                    # zip track
    P.box("paint_white", (0.062, 0.003, 0.062), (0, -D - 0.0085, 0.02), bevel=0.003, segs=1)                   # cross patch
    P.box("medic_red", (0.046, 0.003, 0.014), (0, -D - 0.0095, 0.02), bevel=0.0006, segs=1)
    P.box("medic_red", (0.014, 0.003, 0.046), (0, -D - 0.0095, 0.02), bevel=0.0006, segs=1)
    for k in range(3):                                                                                         # MOLLE rows
        P.box("webbing", (W - 0.02, 0.003, 0.018), (0, -D - 0.0085, -0.045 - k * 0.0), bevel=0.0008, segs=1) if k == 0 else None
    for s in (-1, 1):
        P.box("webbing", (0.022, D + 0.006, 0.006), (s * 0.045, -D / 2, H / 2 - 0.004), bevel=0.001, segs=1)   # top straps
        P.box(POLY, (0.026, 0.012, 0.018), (s * 0.045, -D - 0.004, H / 2 - 0.02), bevel=0.003)                 # buckles
    hx = [(-0.03 + 0.06 * i / 8, -D * 0.5, H / 2 + 0.018 * math.sin(math.pi * i / 8)) for i in range(9)]
    P.tube_path("webbing", hx, 0.006, segs=6, squash=0.4)
    P.box("medic_red", (0.014, 0.004, 0.05), (W / 2 - 0.016, -D * 0.62 - 0.006, -0.04), bevel=0.001, segs=1)   # red pull tab
    A.socket("Hand_R", (W / 2 - 0.006, -D / 2, -0.03))
    A.socket("Hand_L", (-W / 2 + 0.006, -D / 2, -0.03))
    for f, r, l in ((0, 0, 0), (15, -14, 0.02), (45, -10, 0.03), (75, -16, 0.02), (90, 0, 0)):
        A.key("use", "Body", f, rot=(r, 0, 0), loc=(0, 0, l))
    A.meta = {"origin": (0, 0, 0), "cam": 0.36}
    return A


def _fuze(A, P, top, lever_len=0.075, body_r=0.03, lever_mat=STEEL):
    """Grenade fuze head, safety lever (part Lever) and pull ring (part Pin). `top` = z of the body top."""
    P.cyl(STEEL, 0.0125, (0, 0, top - 0.002), (0, 0, top + 0.016), segs=14)
    P.box(STEEL, (0.022, 0.016, 0.012), (0, 0.004, top + 0.021), bevel=0.002)
    P.cyl(BARE, 0.0025, (-0.014, 0.002, top + 0.021), (0.014, 0.002, top + 0.021), segs=6)
    Lv = A.part("Lever", pivot=(0, 0.012, top + 0.024))
    Lv.prof(lever_mat, [(-0.004, top + 0.026), (0.016, top + 0.029), (body_r + 0.006, top + 0.012), (body_r + 0.004, top - lever_len + 0.02),
                        (body_r + 0.001, top - lever_len + 0.02), (body_r + 0.003, top + 0.010), (0.014, top + 0.0265), (-0.004, top + 0.0235)],
            -0.008, 0.008, 'X', bevel=0.0008, segs=1)
    Pn = A.part("Pin", pivot=(-0.016, 0.002, top + 0.021))
    Pn.tube_path(BARE, [(-0.03 + 0.013 * math.cos(a * math.pi / 8), 0.002, top + 0.021 + 0.013 * math.sin(a * math.pi / 8)) for a in range(17)], 0.0014, segs=6, cap=False)
    Pn.cyl(BARE, 0.0013, (-0.017, 0.002, top + 0.021), (0.016, 0.002, top + 0.021), segs=6, ch=0)
    A.socket("Hand_R", (0.0, -0.004, top - 0.055))
    for f, l in ((0, (0, 0, 0)), (8, (0, 0, 0)), (12, (-0.03, 0, 0.0)), (16, (-0.12, -0.03, -0.05)), (20, (-0.3, -0.08, -0.3))):
        A.key("pin", "Pin", f, loc=l)
    for f, l, r in ((0, (0, 0, 0), 0), (20, (0, 0, 0), 0), (23, (0, 0.03, 0.03), -50), (28, (0.02, 0.14, 0.05), -200), (32, (0.05, 0.3, -0.1), -400)):
        A.key("pin", "Lever", f, loc=l, rot=(r, 0, 0))


def grenade(kind):
    A = G.Asset(kind, "grenades")
    P = A.part("Body")
    P.smooth = 50.0
    if kind == "frag":
        r = 0.031
        pts = [(-0.031, 0.0), (-0.030, 0.008), (-0.026, 0.017), (-0.018, 0.0255), (-0.008, 0.0302), (0.0, 0.031), (0.008, 0.0302), (0.018, 0.0255), (0.026, 0.017), (0.030, 0.012)]
        P.lathe("paint_olive", pts, 'Z', segs=20)
        P.lathe("paint_olive", [(-0.002, 0.0318), (0.0, 0.0326), (0.002, 0.0318)], 'Z', segs=20)             # seam
        P.lathe("paint_yellow", [(0.0245, 0.0196), (0.0275, 0.0166)], 'Z', segs=20)                           # marking band
        top = 0.030
        _fuze(A, P, top, 0.07, 0.027, "paint_olive")
        h0 = -0.031
    else:
        r = {"flash": 0.025, "smoke": 0.030, "incendiary": 0.029}[kind]
        h = {"flash": 0.098, "smoke": 0.118, "incendiary": 0.122}[kind]
        mat = {"flash": "paint_grey", "smoke": "paint_grey", "incendiary": "paint_red"}[kind]
        band = {"flash": "paint_blue", "smoke": "paint_white", "incendiary": "paint_yellow"}[kind]
        z0, z1 = -h / 2, h / 2
        if kind == "flash":
            # hexagonal end caps with a perforated tube between them
            P.lathe(STEEL, [(z0, 0.0), (z0, r + 0.004), (z0 + 0.012, r + 0.004), (z0 + 0.012, r - 0.002)], 'Z', segs=6)
            P.lathe(STEEL, [(z1 - 0.012, r - 0.002), (z1 - 0.012, r + 0.004), (z1, r + 0.004), (z1, 0.0)], 'Z', segs=6)
            P.lathe(mat, [(z0 + 0.012, r), (z1 - 0.012, r)], 'Z', segs=18)
            for row in range(3):
                for a in range(6):
                    ang = a * math.pi / 3 + (row % 2) * math.pi / 6
                    c = Vector((math.cos(ang) * r, math.sin(ang) * r, z0 + 0.027 + row * 0.022))
                    n = Vector((math.cos(ang), math.sin(ang), 0))
                    P.cyl(RUB, 0.0052, c - n * 0.002, c + n * 0.0006, segs=10, ch=0)
            P.lathe(band, [(z0 + 0.0135, r + 0.0006), (z0 + 0.0185, r + 0.0006)], 'Z', segs=18)
        else:
            P.lathe(mat, [(z0, 0.0), (z0, r - 0.003), (z0 + 0.003, r), (z0 + 0.008, r), (z0 + 0.009, r - 0.0012), (z0 + 0.011, r), (z1 - 0.011, r), (z1 - 0.009, r - 0.0012), (z1 - 0.008, r),
                          (z1 - 0.003, r), (z1, r - 0.003), (z1, 0.0)], 'Z', segs=22)
            P.lathe(band, [(z1 - 0.036, r + 0.0005), (z1 - 0.022, r + 0.0005)], 'Z', segs=22)
            if kind == "smoke":
                for a in range(4):
                    ang = a * math.pi / 2 + 0.6
                    P.cyl(RUB, 0.004, (math.cos(ang) * 0.019, math.sin(ang) * 0.019, z1 - 0.001), (math.cos(ang) * 0.019, math.sin(ang) * 0.019, z1 + 0.0005), segs=8, ch=0)
            else:
                P.lathe("paint_yellow", [(z0 + 0.03, r + 0.0005), (z0 + 0.036, r + 0.0005)], 'Z', segs=22)
        top = z1
        _fuze(A, P, top, 0.085, r, STEEL)
    A.meta = {"origin": (0, 0, 0), "cam": 0.26}
    return A


def flashlight():
    """Weapon light. Origin = rail contact; body sits towards -X; Beam socket at the lens."""
    A = G.Asset("flashlight", "attachments")
    P = A.part("Body")
    cx = -0.021
    P.box(ALU, (0.012, 0.034, 0.022), (-0.006, 0.0, 0), bevel=0.002)                                           # rail clamp
    P.cyl(STEEL, 0.005, (-0.006, 0.0, -0.011), (-0.006, 0.0, -0.019), segs=8)
    pts = [(-0.042, 0.0), (-0.042, 0.0105), (-0.040, 0.012), (-0.030, 0.012), (-0.029, 0.011), (-0.02, 0.011)]
    for k in range(4):
        pts += [(-0.018 + k * 0.007, 0.0118), (-0.014 + k * 0.007, 0.0118), (-0.0135 + k * 0.007, 0.011), (-0.0115 + k * 0.007, 0.011)]
    pts += [(0.014, 0.011), (0.020, 0.0165), (0.040, 0.0165), (0.042, 0.0152), (0.042, 0.013), (0.038, 0.013), (0.038, 0.0)]
    P.lathe(ALU, pts, 'Y', at=(cx, 0, 0), segs=20)
    P.cyl(RUB, 0.008, (cx, -0.047, 0), (cx, -0.042, 0), segs=14)                                               # tail switch
    Lz = A.part("Lens")
    Lz.lathe("led_white", [(0.0, 0.0), (0.0004, 0.013)], 'Y', at=(cx, 0.0375, 0), segs=16)
    A.socket("Beam", (cx, 0.04, 0))
    A.meta = {"origin": (0, 0, 0), "cam": 0.2}
    return A


def laser():
    A = G.Asset("laser", "attachments")
    P = A.part("Body")
    P.box(ALU, (0.010, 0.036, 0.020), (-0.005, 0.0, 0), bevel=0.002)
    P.box(ALU, (0.026, 0.058, 0.030), (-0.022, 0.0, 0.002), bevel=0.004)
    P.box(ALU, (0.020, 0.012, 0.022), (-0.022, 0.030, 0.002), bevel=0.003)
    P.cyl(STEEL, 0.0058, (-0.022, 0.028, 0.006), (-0.022, 0.0375, 0.006), segs=12)
    P.cyl(RUB, 0.006, (-0.036, -0.012, 0.004), (-0.0385, -0.012, 0.004), segs=10)                              # activation pad
    for z in (0.012, -0.008):
        P.screw(STEEL, (-0.0352, 0.012, z), (-1, 0, 0), r=0.0022)
    P.cyl(STEEL, 0.004, (-0.022, -0.01, 0.017), (-0.022, -0.01, 0.022), segs=10)                               # windage turret
    Lz = A.part("Lens")
    Lz.lathe("led_red", [(0.0, 0.0), (0.0003, 0.004)], 'Y', at=(-0.022, 0.0378, 0.006), segs=10)
    A.socket("Beam", (-0.022, 0.039, 0.006))
    A.meta = {"origin": (0, 0, 0), "cam": 0.18}
    return A


def nvg():
    """Twin-tube goggles on a flip mount. Origin = helmet shroud contact (forehead), tubes forward (+Y)."""
    A = G.Asset("nvg", "attachments")
    M = A.part("Mount")
    M.box(ALU, (0.040, 0.012, 0.036), (0, 0.006, 0.0), bevel=0.003)                                            # shroud plate
    M.box(STEEL, (0.022, 0.03, 0.014), (0, 0.024, -0.006), bevel=0.003)
    T = A.part("Tubes", pivot=(0, 0.036, -0.008))
    T.box(ALU, (0.020, 0.018, 0.046), (0, 0.044, -0.028), bevel=0.003)                                         # arm
    T.box(ALU, (0.090, 0.026, 0.020), (0, 0.062, -0.052), bevel=0.004)                                         # bridge
    for s in (-1, 1):
        x = s * 0.033
        pts = [(0.022, 0.0), (0.022, 0.0125), (0.026, 0.0165), (0.046, 0.0165), (0.048, 0.0185), (0.075, 0.0185), (0.077, 0.0165), (0.092, 0.0165), (0.094, 0.0195),
               (0.112, 0.0195), (0.114, 0.0175), (0.114, 0.0155), (0.108, 0.0155), (0.108, 0.0)]
        T.lathe(ALU, pts, 'Y', at=(x, 0, -0.07), segs=18)
        T.lathe(RUB, [(0.010, 0.0115), (0.012, 0.0145), (0.022, 0.0145), (0.024, 0.0125)], 'Y', at=(x, 0, -0.07), segs=18)   # eyecup
        T.cyl(ALU, 0.005, (x + s * 0.016, 0.062, -0.062), (x + s * 0.022, 0.062, -0.062), segs=10)
    T.cyl(RUB, 0.007, (0, 0.062, -0.040), (0, 0.062, -0.034), segs=12)                                         # power knob
    Lz = A.part("Lens", parent="Tubes")
    for s in (-1, 1):
        Lz.lathe("nvg_lens", [(0.0, 0.0), (0.0005, 0.0155)], 'Y', at=(s * 0.033, 0.1075, -0.07), segs=16)
    # flipped up when off: clip "up" holds the stowed pose (frame 0 = down, last = up)
    A.key("up", "Tubes", 0)
    A.key("up", "Tubes", 8, rot=(95, 0, 0))
    A.meta = {"origin": (0, 0, 0), "cam": 0.3}
    return A


BUILDERS = {"ordinary": lambda: charge(False), "heavy": lambda: charge(True), "kit": kit, "medkit": medkit,
            "frag": lambda: grenade("frag"), "flash": lambda: grenade("flash"), "smoke": lambda: grenade("smoke"), "incendiary": lambda: grenade("incendiary"),
            "flashlight": flashlight, "laser": laser, "nvg": nvg}


def build_all(only=None):
    out = {}
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        A = fn()
        A.build(origin=A.meta["origin"])
        out[name] = G.export(name, A.family)
    return out
