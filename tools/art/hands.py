"""First-person gloved arms. Each arm is authored in the frame of the socket it attaches to
(Hand_R / Hand_L on a gun or held item), so Godot only has to parent it to that socket."""
import math, random, bpy
from mathutils import Vector, Matrix, Euler
import gearlib as G

GLOVE, PAD, SLEEVE = "glove", "glove_pad", "sleeve"

# knuckle x offset, segment lengths, base radius (right hand: thumb on -X, fingers +Y, back of hand +Z)
FINGERS = [(-0.030, (0.038, 0.024, 0.019), 0.0112), (-0.010, (0.042, 0.027, 0.021), 0.0116),
           (0.0105, (0.039, 0.025, 0.020), 0.0110), (0.0295, (0.030, 0.021, 0.017), 0.0100)]


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
    for i, L in enumerate((0.026, 0.023, 0.018)):
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


def arm(P, M, elbow, curls, thumb, right=True, spread=(4, 0, -3, -7), sleeve_r=0.041, seed=1, thumb_path=None):
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
    P.tube_path(GLOVE, [(0.002, y, -0.001) for y in (-0.105, -0.100, -0.060, -0.050, -0.045)], [0.031, 0.033, 0.0325, 0.031, 0.030], segs=14, squash=0.72, up=(0, 0, 1))
    P.box(PAD, (0.040, 0.022, 0.006), (0.004, -0.078, 0.024), bevel=0.0015, segs=1)
    P.xf = Matrix.Identity(4)
    for (x, lens, r), c, sp in zip(FINGERS, curls, spread):
        _finger(P, Mx, x, lens, r, c, sp)
    if thumb_path:
        # Authored socket-space opposition: around the backstrap, then along the frame.
        # A single Euler curl sent the thumbs sideways across the rear sight.
        P.tube_path(GLOVE, thumb_path, [0.016, 0.015, 0.014, 0.012, 0.007], segs=10)
    else:
        _thumb(P, Mx, *thumb)
    # sleeve from the cuff to the elbow, with cloth folds
    wrist = Mx @ Vector((0.002, -0.098, -0.001))
    wdir = (Mx.to_3x3() @ Vector((0, -1, 0))).normalized()
    elbow = Vector(elbow)
    P.wrist = wrist.copy()
    P.elbow = elbow.copy()
    rng = random.Random(seed)
    n = 13
    pts, radii = [], []
    for i in range(n):
        t = i / (n - 1)
        # Forearm bones are straight. Only soften the wrist transition; the old
        # S-curve made the sleeve look like a flexible hose.
        pts.append(wrist.lerp(elbow, t))
        fold = math.sin(t * math.pi * 7) * 0.0018 * (1.0 - t)
        radii.append(0.030 + 0.020 * math.sin(t * math.pi * 0.65) + fold)
    P.tube_path(SLEEVE, pts, radii, segs=14, squash=0.92, cap=False)
    # cuff hem and a forearm pocket flap
    P.tube_path(SLEEVE, [pts[0] + wdir * 0.003, pts[0] + wdir * 0.012], [0.033, 0.034], segs=14, cap=False)


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
    M = hand_matrix((0.026, -0.034, -0.042), (0.0, 0.38, -0.92), (-0.10, 0.92, 0.38))
    arm(P, M, (0.20, -0.42, -0.26), [(32, 45, 15), (55, 75, 30), (58, 75, 30), (60, 75, 30)], (-20, -8, (0, 8, 5)), seed=1, thumb_path=[(.026, -.030, -.006), (.010, -.044, .002), (-.010, -.043, .004), (-.022, -.018, .003), (-.022, .004, .002)])
    # Left hand cupping a handguard from below, thumb up the left side.
    P = A.part("ArmL_Fore")
    M = hand_matrix((-0.032, -0.008, -0.008), (0.0, -0.44, 0.90), (0.30, 0.85, 0.42)) @ G.mirror_x()
    arm(P, M, (-0.17, -0.36, -0.30), [(45, 65, 25), (48, 68, 25), (50, 68, 25), (52, 68, 25)], (-20, -8, (0, 8, 5)), seed=2, thumb_path=[(-.043, -.020, .002), (-.043, .001, .017), (-.036, .024, .025), (-.029, .045, .024), (-.029, .056, .022)])
    # Right hand on a handgun grip (elbow tucked in under the camera).
    P = A.part("ArmR_Pistol")
    M = hand_matrix((0.026, -0.034, -0.042), (0.0, 0.38, -0.92), (-0.10, 0.92, 0.38))
    arm(P, M, (0.13, -0.30, -0.36), [(32, 45, 15), (55, 75, 30), (58, 75, 30), (60, 75, 30)], (-20, -8, (0, 8, 5)), seed=6, thumb_path=[(.026, -.030, -.006), (.010, -.044, .002), (-.010, -.043, .004), (-.022, -.018, .003), (-.022, .004, .002)])
    # Left hand supporting a pistol grip (wraps the right hand's fingers).
    P = A.part("ArmL_Support")
    M = hand_matrix((-0.047, -0.014, -0.048), (0.0, -0.38, 0.92), (0.10, 0.92, 0.38)) @ G.mirror_x()
    arm(P, M, (-0.15, -0.30, -0.36), [(45, 70, 25)] * 4, (-20, -8, (0, 8, 5)), seed=3, thumb_path=[(-.050, -.028, -.008), (-.045, -.010, .002), (-.037, .012, .006), (-.033, .037, .005), (-.033, .052, .004)])
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
    A.build(ao=False)
    _organic_gloves(A)
    _rig(A)
    return A


def _organic_gloves(A):
    """Join intersecting palm/heel/finger volumes into one continuous glove surface.
    Keep rubber pads and cloth separate so their material edges stay crisp.
    """
    for ob in A.objs.values():
        src = ob.data
        glove = [p for p in src.polygons if src.materials[p.material_index].name == GLOVE]
        keep = [p for p in src.polygons if src.materials[p.material_index].name != GLOVE]
        tmp = bpy.data.meshes.new('glove_union')
        tmp.from_pydata([v.co for v in src.vertices], [], [list(p.vertices) for p in glove])
        work = bpy.data.objects.new('glove_union', tmp)
        bpy.context.scene.collection.objects.link(work)
        mod = work.modifiers.new('Connected glove', 'REMESH')
        mod.mode = 'VOXEL'
        mod.voxel_size = .0025
        mod.use_smooth_shade = True
        smooth = work.modifiers.new('Soft tissue', 'SMOOTH')
        smooth.factor = .6
        smooth.iterations = 3
        dec = work.modifiers.new('Game mesh', 'DECIMATE')
        dec.ratio = .20
        bpy.context.view_layer.update()
        evaluated = work.evaluated_get(bpy.context.evaluated_depsgraph_get())
        union = evaluated.to_mesh()
        verts = [v.co.copy() for v in src.vertices]
        faces = [list(p.vertices) for p in keep]
        material_indices = [p.material_index for p in keep]
        offset = len(verts)
        verts += [v.co.copy() for v in union.vertices]
        faces += [[offset + i for i in p.vertices] for p in union.polygons]
        material_indices += [list(m.name for m in src.materials).index(GLOVE)] * len(union.polygons)
        me = bpy.data.meshes.new(src.name + '_connected')
        me.from_pydata(verts, [], faces)
        for mat in src.materials:
            me.materials.append(mat)
        for poly, mi in zip(me.polygons, material_indices):
            poly.material_index = mi
            poly.use_smooth = True
        ob.data = me
        G._box_uv(me, Vector())
        evaluated.to_mesh_clear()
        bpy.data.objects.remove(work, do_unlink=True)
        bpy.data.meshes.remove(tmp)
    G._bake_vertex_ao(list(A.objs.values()))


def _rig(A):
    """Separate wrist and forearm deformation; Godot anchors elbows during socket animation.
    Each named pose is a self-contained subtree so it can be instanced independently.
    """
    coll = bpy.data.collections[A.name]
    root = next(o for o in coll.objects if o.type == 'EMPTY' and o.parent is None)
    for name, part in A.parts.items():
        mesh = A.objs[name]
        mesh.name = name + '_Mesh'
        mesh['gear_name'] = mesh.name
        wrapper = bpy.data.objects.new(name, None)
        wrapper['gear_name'] = name
        coll.objects.link(wrapper)
        wrapper.parent = root
        armature = bpy.data.armatures.new(name + '_Rig')
        rig = bpy.data.objects.new(name + '_Skeleton', armature)
        coll.objects.link(rig)
        rig.parent = wrapper
        for ob in bpy.context.view_layer.objects:
            if ob.select_get():
                ob.select_set(False)
        rig.select_set(True)
        bpy.context.view_layer.objects.active = rig
        bpy.ops.object.mode_set(mode='EDIT')
        hand = armature.edit_bones.new('Hand')
        hand.head = part.wrist
        hand.tail = part.wrist + Vector((0, .06, 0))
        forearm = armature.edit_bones.new('Forearm')
        forearm.head = part.wrist
        forearm.tail = part.elbow
        end = armature.edit_bones.new('ElbowEnd')
        end.head = part.elbow
        end.tail = part.elbow + (part.elbow - part.wrist).normalized() * .03
        end.parent = forearm
        bpy.ops.object.mode_set(mode='OBJECT')
        mesh.parent = rig
        vg_hand = mesh.vertex_groups.new(name='Hand')
        vg_arm = mesh.vertex_groups.new(name='Forearm')
        sleeve_indices = set()
        for poly in mesh.data.polygons:
            if mesh.data.materials[poly.material_index].name == SLEEVE:
                sleeve_indices.update(poly.vertices)
        direction = (part.elbow - part.wrist).normalized()
        for v in mesh.data.vertices:
            weight = min(1.0, max(0.0, (v.co - part.wrist).dot(direction) / .055)) if v.index in sleeve_indices else 0.0
            if weight < 1.0:
                vg_hand.add([v.index], 1.0 - weight, 'REPLACE')
            if weight > 0.0:
                vg_arm.add([v.index], weight, 'REPLACE')
        mod = mesh.modifiers.new('Armature', 'ARMATURE')
        mod.object = rig
