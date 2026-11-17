"""Procedural gear modelling helpers for Blender 5.x (run through the Blender MCP).

Conventions: metres; Blender +Y = forward (Godot -Z after glTF export), +Z up, +X right.
An Asset is a collection with a root empty, named Part meshes (one object per animated piece),
socket empties and NLA-track animation clips. Materials are referenced by name from
art/materials.json; Godot rebuilds them from the same file, so exported .glb files carry no images.
"""
import bpy, bmesh, math, json, os, random
import numpy as np
from mathutils import Vector, Matrix, Euler
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEX_DIR = os.path.join(ROOT, "game", "assets", "textures", "gear")
MODEL_DIR = os.path.join(ROOT, "game", "assets", "models")
MAT_JSON = os.path.join(ROOT, "game", "assets", "models", "materials.json")
UV_SCALE = 0.25  # metres per UV unit (box projection)
FPS = 30


# ------------------------------------------------------------------ textures
def _fbm(n, beta, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    rad = np.sqrt(fx * fx + fy * fy)
    rad[0, 0] = 1.0
    spec = (rng.normal(size=(n, n)) + 1j * rng.normal(size=(n, n))) / rad ** beta
    spec[0, 0] = 0
    img = np.fft.ifft2(spec).real
    return (img - img.min()) / (img.max() - img.min())


def _normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([-dx / l * 0.5 + 0.5, -dy / l * 0.5 + 0.5, nz / l * 0.5 + 0.5], -1)


def _save(name, rgb, data=True):
    n = rgb.shape[0]
    if rgb.ndim == 2:
        rgb = np.stack([rgb] * 3, -1)
    rgba = np.concatenate([rgb, np.ones((n, n, 1))], -1).astype(np.float32)
    img = bpy.data.images.get(name) or bpy.data.images.new(name, n, n, alpha=False)
    img.pixels.foreach_set(rgba.ravel())
    os.makedirs(TEX_DIR, exist_ok=True)
    img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    img.file_format = 'PNG'
    img.save()
    if data:
        img.colorspace_settings.name = 'Non-Color'
    return img


def make_textures(n=512):
    """Shared tileable maps: grunge (albedo/roughness multiplier), grain and fabric normals, hazard stripes."""
    rng = np.random.default_rng(7)
    g = 0.80 + 0.2 * _fbm(n, 1.3, 1)
    blot = _fbm(n, 2.2, 2)
    g -= 0.10 * np.clip((blot - 0.62) * 6.0, 0, 1)
    for _ in range(90):  # fine scratches, wrapped
        x, y = rng.uniform(0, n, 2)
        a = rng.uniform(0, math.pi)
        ln = int(rng.uniform(8, 70))
        t = np.arange(ln)
        xs = (x + np.cos(a) * t).astype(int) % n
        ys = (y + np.sin(a) * t).astype(int) % n
        g[ys, xs] = np.minimum(g[ys, xs] + rng.uniform(0.05, 0.16), 1.0)
    _save("grunge", np.clip(g, 0, 1))
    _save("grain_n", _normal_from_height(_fbm(n, 0.2, 3), 1.3))
    yy, xx = np.mgrid[0:n, 0:n] / n
    fq = 110
    warp = np.abs(np.sin(xx * math.pi * fq)) * (np.floor(yy * fq) % 2) + np.abs(np.sin(yy * math.pi * fq)) * (1 - np.floor(yy * fq) % 2) * 0.0
    weft = np.abs(np.sin(yy * math.pi * fq)) * (np.floor(xx * fq) % 2)
    weave = np.maximum(warp * ((np.floor(xx * fq) + np.floor(yy * fq)) % 2), weft * ((np.floor(xx * fq) + np.floor(yy * fq) + 1) % 2))
    weave = np.abs(np.sin(xx * math.pi * fq)) * np.abs(np.sin(yy * math.pi * fq))
    chk = (np.floor(xx * fq) + np.floor(yy * fq)) % 2
    h = weave * (0.6 + 0.4 * chk) + 0.25 * _fbm(n, 1.0, 5)
    _save("fabric_n", _normal_from_height(h, 0.55))
    d = (xx + yy) * 4.0 % 1.0
    stripe = (d < 0.5)[..., None]
    hz = np.where(stripe, np.array([0.92, 0.66, 0.05]), np.array([0.035, 0.035, 0.04]))
    hz = hz * (0.75 + 0.25 * _fbm(n, 1.4, 6))[..., None]
    _save("hazard", hz, data=False)


# ------------------------------------------------------------------ materials
def load_matdefs():
    with open(MAT_JSON) as f:
        return json.load(f)


def get_mat(name):
    """Blender preview material built from materials.json (Godot builds the runtime twin)."""
    m = bpy.data.materials.get(name)
    if m:
        return m
    d = load_matdefs()[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    col = d["color"]
    bsdf.inputs["Metallic"].default_value = d.get("metallic", 0.0)
    bsdf.inputs["Roughness"].default_value = d.get("roughness", 0.6)
    alpha = d.get("alpha", 1.0)
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = 'BLENDED'
    em = d.get("emission")
    if em:
        bsdf.inputs["Emission Color"].default_value = (*em, 1)
        bsdf.inputs["Emission Strength"].default_value = d.get("emission_energy", 2.0)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    s = d.get("uv_scale", 4.0)
    mp.inputs["Scale"].default_value = (s, s, s)
    nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
    vc = nt.nodes.new("ShaderNodeVertexColor")
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = 'RGBA'
    mix.blend_type = 'MULTIPLY'
    mix.inputs[0].default_value = 1.0
    mix.inputs[6].default_value = (*col, 1)
    nt.links.new(vc.outputs["Color"], mix.inputs[7])
    out_col = mix.outputs[2]
    tex_name = d.get("albedo_tex")
    gr = d.get("grunge", 0.0 if em else 1.0)
    if tex_name or gr > 0:
        ti = nt.nodes.new("ShaderNodeTexImage")
        ti.image = bpy.data.images.get(tex_name or "grunge")
        nt.links.new(mp.outputs["Vector"], ti.inputs["Vector"])
        m2 = nt.nodes.new("ShaderNodeMix")
        m2.data_type = 'RGBA'
        m2.blend_type = 'MULTIPLY'
        m2.inputs[0].default_value = 1.0 if tex_name else gr
        nt.links.new(out_col, m2.inputs[6])
        nt.links.new(ti.outputs["Color"], m2.inputs[7])
        out_col = m2.outputs[2]
        if not tex_name:
            mr = nt.nodes.new("ShaderNodeMath")
            mr.operation = 'MULTIPLY'
            mr.inputs[1].default_value = d.get("roughness", 0.6) * 1.15
            nt.links.new(ti.outputs["Color"], mr.inputs[0])
            nt.links.new(mr.outputs[0], bsdf.inputs["Roughness"])
    nt.links.new(out_col, bsdf.inputs["Base Color"])
    nrm = d.get("normal")
    if nrm:
        ni = nt.nodes.new("ShaderNodeTexImage")
        ni.image = bpy.data.images.get(nrm + "_n")
        mp2 = nt.nodes.new("ShaderNodeMapping")
        s2 = d.get("normal_uv", s)
        mp2.inputs["Scale"].default_value = (s2, s2, s2)
        nt.links.new(tc.outputs["UV"], mp2.inputs["Vector"])
        nt.links.new(mp2.outputs["Vector"], ni.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = d.get("normal_scale", 0.5)
        nt.links.new(ni.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


# ------------------------------------------------------------------ geometry
def _rotm(rot):
    return Euler([math.radians(a) for a in rot], 'XYZ').to_matrix().to_4x4() if rot else Matrix.Identity(4)


def _bevel(bm, width, segs, angle=28.0):
    lay = bm.faces.layers.int.get("bev") or bm.faces.layers.int.new("bev")
    if width <= 0:
        return
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(angle)]
    if not edges:
        return
    r = bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type='OFFSET', segments=segs, profile=0.5,
                        affect='EDGES', clamp_overlap=True)
    for f in r["faces"]:
        f[lay] = 1


def _boolean(bm, cutter_bm):
    def tmp(b, nm):
        me = bpy.data.meshes.new(nm)
        b.to_mesh(me)
        ob = bpy.data.objects.new(nm, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob
    bmesh.ops.recalc_face_normals(cutter_bm, faces=cutter_bm.faces)
    a, c = tmp(bm, "_tmpA"), tmp(cutter_bm, "_tmpC")
    mod = a.modifiers.new("b", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = c
    mod.use_self = True
    dg = bpy.context.evaluated_depsgraph_get()
    ev = a.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    bm.clear()
    bm.from_mesh(me)
    for ob in (a, c):
        d = ob.data
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(d)
    bpy.data.meshes.remove(me)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1.0), verts=bm.verts, edges=bm.edges)


class Part:
    """Accumulates beveled primitives into one mesh with per-face material slots."""

    def __init__(self, name="part", pivot=(0, 0, 0), parent=None):
        self.name = name
        self.pivot = Vector(pivot)
        self.parent = parent
        self.bm = bmesh.new()
        self.bev = self.bm.faces.layers.int.new("bev")
        self.mats = []
        self.xf = Matrix.Identity(4)  # extra transform applied to every primitive added (for reuse)

    def _mi(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _merge(self, bm, mat, at=(0, 0, 0), rot=None, cuts=None, bevel=0.0, segs=2, angle=28.0):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        if cuts is not None:
            _boolean(bm, cuts.bm)
        _bevel(bm, bevel, segs, angle)
        lay = bm.faces.layers.int.get("bev")
        M = self.xf @ Matrix.Translation(Vector(at)) @ _rotm(rot)
        flip = M.determinant() < 0
        mi = self._mi(mat)
        vmap = {}
        for v in bm.verts:
            vmap[v.index] = self.bm.verts.new(M @ v.co)
        bm.verts.index_update()
        for f in bm.faces:
            vs = [vmap[v.index] for v in f.verts]
            if flip:
                vs.reverse()
            try:
                nf = self.bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index = mi
            nf[self.bev] = f[lay] if lay else 0
        bm.free()

    def box(self, mat, size, at=(0, 0, 0), bevel=0.0015, segs=2, rot=None, cuts=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
        self._merge(bm, mat, at, rot, cuts, bevel, segs)

    def prof(self, mat, pts, a0, a1, axis='X', bevel=0.0015, segs=2, at=(0, 0, 0), rot=None, cuts=None, angle=28.0):
        """Extrude a 2D outline along an axis. Outline plane: X->(y,z), Y->(x,z), Z->(x,y)."""
        bm = bmesh.new()
        def p3(p, a):
            if axis == 'X':
                return (a, p[0], p[1])
            if axis == 'Y':
                return (p[0], a, p[1])
            return (p[0], p[1], a)
        f = bm.faces.new([bm.verts.new(p3(p, a0)) for p in pts])
        r = bmesh.ops.extrude_face_region(bm, geom=[f])
        d = Vector(p3((0, 0), a1 - a0))
        bmesh.ops.translate(bm, vec=d, verts=[e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)])
        self._merge(bm, mat, at, rot, cuts, bevel, segs, angle)

    def lathe(self, mat, pts, axis='Y', at=(0, 0, 0), segs=24, rot=None, cuts=None, bevel=0.0, arc=360.0, cap=True):
        """Revolve (pos, radius) pairs around an axis through `at`."""
        bm = bmesh.new()
        rings = []
        full = arc >= 360.0
        n = segs if full else segs + 1
        for pos, r in pts:
            if r <= 1e-6:
                rings.append([bm.verts.new((0, 0, pos))])
            else:
                rings.append([bm.verts.new((r * math.cos(math.radians(arc) * i / segs), r * math.sin(math.radians(arc) * i / segs), pos)) for i in range(n)])
        for a, b in zip(rings[:-1], rings[1:]):
            for i in range(n if full else n - 1):
                j = (i + 1) % n
                if len(a) == 1 and len(b) == 1:
                    continue
                if len(a) == 1:
                    bm.faces.new([a[0], b[j], b[i]])
                elif len(b) == 1:
                    bm.faces.new([a[i], a[j], b[0]])
                else:
                    bm.faces.new([a[i], a[j], b[j], b[i]])
        if full and cap:
            if len(rings[0]) > 1:
                bm.faces.new(rings[0])
            if len(rings[-1]) > 1:
                bm.faces.new(rings[-1])
        R = {'Z': Matrix.Identity(4), 'Y': Matrix.Rotation(-math.pi / 2, 4, 'X'), 'X': Matrix.Rotation(math.pi / 2, 4, 'Y')}[axis]
        bmesh.ops.transform(bm, matrix=R, verts=bm.verts)
        self._merge(bm, mat, at, rot, cuts, bevel, 1, 50.0)

    def cyl(self, mat, r, p0, p1, segs=16, ch=0.0008, r1=None):
        """Chamfered cylinder (or cone when r1 is set) between two points."""
        p0, p1 = Vector(p0), Vector(p1)
        L = (p1 - p0).length
        r1 = r if r1 is None else r1
        ch = min(ch, L * 0.3, r * 0.5, r1 * 0.5)
        pts = [(0, r - ch), (ch, r), (L - ch, r1), (L, r1 - ch)] if ch > 0 else [(0, r), (L, r1)]
        bm_part = Part()
        bm_part.lathe(mat, pts, 'Z', segs=segs)
        q = Vector((0, 0, 1)).rotation_difference((p1 - p0).normalized())
        M = Matrix.Translation(p0) @ q.to_matrix().to_4x4()
        bmesh.ops.transform(bm_part.bm, matrix=M, verts=bm_part.bm.verts)
        self._merge(bm_part.bm, mat)

    def tube_path(self, mat, pts, radii, segs=10, squash=1.0, up=(0, 0, 1), cap=True):
        """Tube swept along a polyline with per-point radius (limbs, fingers, wires)."""
        bm = bmesh.new()
        pts = [Vector(p) for p in pts]
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * len(pts)
        rings = []
        upv = Vector(up)
        for i, p in enumerate(pts):
            t = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            side = t.cross(upv)
            if side.length < 1e-4:
                side = t.cross(Vector((1, 0, 0)))
            side.normalize()
            u = side.cross(t).normalized()
            upv = u
            rings.append([bm.verts.new(p + (side * math.cos(2 * math.pi * k / segs) + u * math.sin(2 * math.pi * k / segs) * squash) * radii[i]) for k in range(segs)])
        for a, b in zip(rings[:-1], rings[1:]):
            for i in range(segs):
                j = (i + 1) % segs
                bm.faces.new([a[i], a[j], b[j], b[i]])
        if cap:
            bm.faces.new(rings[0])
            bm.faces.new(rings[-1])
        self._merge(bm, mat)

    def rail(self, mat, y0, y1, z, x=0.0, w=0.0212, pitch=0.01, axis_up=(0, 0, 1)):
        """Picatinny-style rail along Y with its base at height z (teeth point along axis_up: +Z, -Z, +X or -X)."""
        sub = Part()
        hw = w / 2
        sub.prof(mat, [(-hw, 0), (hw, 0), (hw, 0.0028), (hw - 0.0022, 0.0052), (-hw + 0.0022, 0.0052), (-hw, 0.0028)], y0, y1, 'Y', bevel=0.0)
        n = int((y1 - y0) / pitch)
        off = (y1 - y0 - n * pitch) / 2 + pitch / 2
        for i in range(n):
            yc = y0 + off + i * pitch
            sub.prof(mat, [(-hw, 0.0052), (hw, 0.0052), (hw, 0.0066), (hw - 0.0026, 0.0094), (-hw + 0.0026, 0.0094), (-hw, 0.0066)],
                     yc - pitch * 0.26, yc + pitch * 0.26, 'Y', bevel=0.0005, segs=1)
        up = Vector(axis_up)
        if up.z > 0.5:
            R = Matrix.Identity(4)
        elif up.z < -0.5:
            R = Matrix.Rotation(math.pi, 4, 'Y')
        elif up.x > 0.5:
            R = Matrix.Rotation(math.pi / 2, 4, 'Y')
        else:
            R = Matrix.Rotation(-math.pi / 2, 4, 'Y')
        M = Matrix.Translation(Vector((x, 0, z))) @ R
        bmesh.ops.transform(sub.bm, matrix=M, verts=sub.bm.verts)
        self._merge(sub.bm, mat)

    def screw(self, mat, at, normal=(1, 0, 0), r=0.0028, h=0.0016, hexagon=True):
        at, n = Vector(at), Vector(normal).normalized()
        self.cyl(mat, r, at - n * 0.001, at + n * h, segs=6 if hexagon else 12, ch=0.0004)
        if not hexagon:
            self.cyl(mat, r * 0.45, at + n * h * 0.5, at + n * (h + 0.0003), segs=6, ch=0)

    def add_part(self, other, M=None):
        """Merge another Part's geometry (optionally transformed/mirrored)."""
        M = M or Matrix.Identity(4)
        flip = M.determinant() < 0
        vmap = {}
        other.bm.verts.index_update()
        for v in other.bm.verts:
            vmap[v.index] = self.bm.verts.new(M @ v.co)
        for f in other.bm.faces:
            vs = [vmap[v.index] for v in f.verts]
            if flip:
                vs.reverse()
            try:
                nf = self.bm.faces.new(vs)
            except ValueError:
                continue
            nf.material_index = self._mi(other.mats[f.material_index])
            nf[self.bev] = f[other.bev]

    def subdivide_smooth(self, levels=1):
        """Catmull-Clark the whole part (organic pieces: gloves, sleeves, pouches)."""
        me = bpy.data.meshes.new("_sub")
        self.bm.to_mesh(me)
        ob = bpy.data.objects.new("_sub", me)
        bpy.context.scene.collection.objects.link(ob)
        mod = ob.modifiers.new("s", 'SUBSURF')
        mod.levels = levels
        dg = bpy.context.evaluated_depsgraph_get()
        me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
        self.bm.clear()
        self.bm.from_mesh(me2)
        self.bev = self.bm.faces.layers.int.get("bev") or self.bm.faces.layers.int.new("bev")
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
        bpy.data.meshes.remove(me2)


def mirror_x():
    return Matrix.Scale(-1, 4, (1, 0, 0))


# ------------------------------------------------------------------ assets
class Asset:
    def __init__(self, name, family):
        self.name = name
        self.family = family
        self.parts = {}
        self.sockets = {}
        self.keys = []  # (clip, object, frame, loc_delta, rot_delta_deg, scale)
        self.objs = {}

    def part(self, name, pivot=(0, 0, 0), parent=None):
        p = Part(name, pivot, parent)
        self.parts[name] = p
        return p

    def socket(self, name, loc, rot=None, parent=None):
        self.sockets[name] = (Vector(loc), rot, parent)

    def key(self, clip, obj, frame, loc=None, rot=None, scale=None):
        self.keys.append((clip, obj, frame, loc, rot, scale))

    def _pivot(self, name):
        if name in self.parts:
            return self.parts[name].pivot
        if name in self.sockets:
            return self.sockets[name][0]
        return Vector()

    def build(self, origin=(0, 0, 0), ao=True, smooth_angle=38.0):
        origin = Vector(origin)
        old = bpy.data.collections.get(self.name)
        if old:
            for o in list(old.objects):
                d = o.data
                bpy.data.objects.remove(o)
                if d and d.users == 0 and isinstance(d, bpy.types.Mesh):
                    bpy.data.meshes.remove(d)
            bpy.data.collections.remove(old)
        for a in [a for a in bpy.data.actions if a.name.startswith(self.name + ".")]:
            bpy.data.actions.remove(a)
        coll = bpy.data.collections.new(self.name)
        bpy.context.scene.collection.children.link(coll)
        root = bpy.data.objects.new(self.name, None)
        root.empty_display_size = 0.02
        coll.objects.link(root)
        self.objs = {}
        tris = 0
        for name, p in self.parts.items():
            me = bpy.data.meshes.new(self.name + "." + name)
            bm = p.bm
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.00002)
            bmesh.ops.translate(bm, vec=-p.pivot, verts=bm.verts)
            for f in bm.faces:
                f.smooth = True
            bm.to_mesh(me)
            for mname in p.mats:
                me.materials.append(get_mat(mname))
            me.set_sharp_from_angle(angle=math.radians(getattr(p, 'smooth', None) or smooth_angle))
            ob = bpy.data.objects.new(name, me)
            ob["gear_name"] = name
            coll.objects.link(ob)
            wn = ob.modifiers.new("wn", 'WEIGHTED_NORMAL')
            wn.keep_sharp = True
            wn.weight = 60
            self.objs[name] = ob
            _box_uv(me, p.pivot)
            tris += sum(len(pl.vertices) - 2 for pl in me.polygons)
        for name, (loc, rot, parent) in self.sockets.items():
            e = bpy.data.objects.new(name, None)
            e["gear_name"] = name
            e.empty_display_type = 'ARROWS'
            e.empty_display_size = 0.015
            coll.objects.link(e)
            self.objs[name] = e
            if rot:
                e.rotation_euler = [math.radians(a) for a in rot]
        for name, ob in self.objs.items():
            parent = self.parts[name].parent if name in self.parts else self.sockets[name][2]
            ob.rotation_mode = 'XYZ'
            if parent:
                ob.parent = self.objs[parent]
                ob.location = self._pivot(name) - self._pivot(parent)
            else:
                ob.parent = root
                ob.location = self._pivot(name) - origin
        bpy.context.view_layer.update()
        if ao:
            _bake_vertex_ao([o for n, o in self.objs.items() if n in self.parts])
        self._animate()
        self.tris = tris
        return tris

    def _animate(self):
        clips = {}
        for clip, obj, frame, loc, rot, scale in self.keys:
            clips.setdefault((clip, obj), []).append((frame, loc, rot, scale))
        for (clip, obj), ks in clips.items():
            ob = self.objs[obj]
            rest_l, rest_r = ob.location.copy(), ob.rotation_euler.copy()
            ad = ob.animation_data or ob.animation_data_create()
            act = bpy.data.actions.new("%s.%s.%s" % (self.name, obj, clip))
            ad.action = act
            for frame, loc, rot, scale in sorted(ks, key=lambda k: k[0]):
                ob.location = rest_l + Vector(loc or (0, 0, 0))
                r = rot or (0, 0, 0)
                ob.rotation_euler = Euler([rest_r[i] + math.radians(r[i]) for i in range(3)], 'XYZ')
                ob.scale = scale or (1, 1, 1)
                ob.keyframe_insert("location", frame=frame)
                ob.keyframe_insert("rotation_euler", frame=frame)
                ob.keyframe_insert("scale", frame=frame)
            slot = ad.action_slot
            ad.action = None
            tr = ad.nla_tracks.new()
            tr.name = clip
            st = tr.strips.new(clip, 0, act)
            try:
                if slot is not None:
                    st.action_slot = slot
            except Exception:
                pass
            tr.mute = True
            ob.location, ob.rotation_euler, ob.scale = rest_l, rest_r, (1, 1, 1)


def _box_uv(me, pivot):
    uv = me.uv_layers.new(name="UVMap")
    for pl in me.polygons:
        n = pl.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in pl.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co + pivot
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            uv.data[li].uv = (u / UV_SCALE, v / UV_SCALE)


def _bake_vertex_ao(objs, rays=20, dist=0.05, strength=0.6):
    """Vertex colours = ambient occlusion (dark crevices) x edge wear (bevel rows stay bright)."""
    verts, polys = [], []
    for ob in objs:
        base = len(verts)
        mw = ob.matrix_world
        verts += [mw @ v.co for v in ob.data.vertices]
        polys += [[base + i for i in p.vertices] for p in ob.data.polygons]
    if not polys:
        return
    bvh = BVHTree.FromPolygons(verts, polys)
    rng = random.Random(3)
    dirs = []
    while len(dirs) < rays:
        v = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        if 0.1 < v.length <= 1.0:
            dirs.append(v.normalized())
    for ob in objs:
        me = ob.data
        mw = ob.matrix_world
        nm = mw.to_3x3()
        bevl = me.attributes.get("bev")
        allbev = [True] * len(me.vertices)
        if bevl:
            for p in me.polygons:
                if bevl.data[p.index].value == 0:
                    for vi in p.vertices:
                        allbev[vi] = False
        else:
            allbev = [False] * len(me.vertices)
        vcol = []
        for v in me.vertices:
            n = (nm @ v.normal).normalized()
            o = mw @ v.co + n * 0.0006
            hit = 0.0
            for d in dirs:
                dd = d if d.dot(n) > 0 else -d
                h = bvh.ray_cast(o, dd, dist)
                if h[0] is not None:
                    hit += 1.0 - h[3] / dist
            a = 1.0 - strength * min(hit / rays * 2.2, 1.0)
            c = a * (1.0 if allbev[v.index] else 0.8)
            vcol.append(c)
        ca = me.color_attributes.new("Col", 'BYTE_COLOR', 'CORNER')
        for l in me.loops:
            c = vcol[l.vertex_index]
            ca.data[l.index].color = (c, c, c, 1.0)
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = 0


# ------------------------------------------------------------------ scene / preview / export
def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for blk in (bpy.data.meshes, bpy.data.materials, bpy.data.actions, bpy.data.cameras, bpy.data.lights):
        for b in list(blk):
            if b.users == 0:
                blk.remove(b)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m)
    for n in ("grunge", "grain_n", "fabric_n", "hazard"):
        if not bpy.data.images.get(n):
            p = os.path.join(TEX_DIR, n + ".png")
            if os.path.exists(p):
                img = bpy.data.images.load(p)
                img.name = n
                if n != "hazard":
                    img.colorspace_settings.name = 'Non-Color'
    bpy.context.scene.render.fps = FPS


def show_only(names):
    names = set(names)
    for lc in bpy.context.view_layer.layer_collection.children:
        lc.exclude = lc.name not in names and lc.name not in ("Preview", "PreviewArms")


def render(path, cam, target, lens=35.0, res=(1100, 620), world=0.25, key=600.0):
    sc = bpy.context.scene
    pc = bpy.data.collections.get("Preview")
    if not pc:
        pc = bpy.data.collections.new("Preview")
        sc.collection.children.link(pc)
        camd = bpy.data.cameras.new("PreviewCam")
        co = bpy.data.objects.new("PreviewCam", camd)
        pc.objects.link(co)
        for nm, loc, e, col, size in (("Key", (0.9, -0.5, 1.2), key * 0.5, (1.0, 0.93, 0.85), 0.6), ("Rim", (-1.0, 1.2, 0.6), key * 0.7, (0.6, 0.75, 1.0), 0.8),
                                      ("Fill", (-0.8, -1.0, -0.2), key * 0.15, (1, 1, 1), 1.5)):
            ld = bpy.data.lights.new(nm, 'AREA')
            ld.energy = e / 12.0
            ld.color = col
            ld.size = size
            lo = bpy.data.objects.new(nm, ld)
            lo.location = loc
            lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
            pc.objects.link(lo)
    co = bpy.data.objects["PreviewCam"]
    co.location = cam
    co.rotation_euler = (Vector(target) - Vector(cam)).to_track_quat('-Z', 'Y').to_euler()
    co.data.lens = lens
    co.data.clip_start = 0.01
    sc.camera = co
    if not sc.world:
        sc.world = bpy.data.worlds.new("W")
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.5, 0.55, 0.62, 1)
        bg.inputs[1].default_value = world
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.filepath = path
    sc.render.image_settings.file_format = 'PNG'
    try:
        sc.view_settings.view_transform = 'AgX'
    except Exception:
        pass
    bpy.ops.render.render(write_still=True)


def _claim_names(coll):
    """Blender object names are unique per file; give this asset's objects their clean names for export."""
    want = {o: o["gear_name"] for o in coll.objects if "gear_name" in o}
    names = set(want.values())
    for o in bpy.data.objects:
        if o not in want and o.name in names:
            o.name = o.name + ".x"
    for o, n in want.items():
        o.name = n


def export(asset_name, family, anim=True):
    """Export one asset collection as game/assets/models/<family>/<asset>.glb. Returns triangle count."""
    coll = bpy.data.collections[asset_name]
    lc = bpy.context.view_layer.layer_collection.children[asset_name]
    lc.exclude = False
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    _claim_names(coll)
    for o in coll.objects:
        o.hide_set(False)
        o.select_set(True)
    out = os.path.join(MODEL_DIR, family)
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, asset_name + ".glb")
    import logging
    logging.disable(logging.INFO)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='NONE', export_materials='EXPORT',
                              export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_animations=anim, export_animation_mode='NLA_TRACKS',
                              export_force_sampling=True, export_frame_range=False, export_anim_slide_to_zero=False,
                              export_optimize_animation_size=True, export_extras=False, export_cameras=False, export_lights=False)
    dg = bpy.context.evaluated_depsgraph_get()
    tris = 0
    for o in coll.objects:
        if o.type == 'MESH':
            tris += sum(len(p.vertices) - 2 for p in o.data.polygons)
    return tris


def export_world(asset_name, family, max_tris=2800, skip=("Reticle", "SightGlass")):
    """Decimated single-mesh form for third-person / world use: <asset>_w.glb, no animation."""
    coll = bpy.data.collections[asset_name]
    dg = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    mats = []
    root = bpy.data.objects[asset_name] if asset_name in coll.objects else None
    inv = coll.objects[asset_name].matrix_world.inverted()
    for o in coll.objects:
        if o.type != 'MESH' or o.name.split(".")[0] in skip:
            continue
        me = o.data
        off = len(bm.verts)
        M = inv @ o.matrix_world
        tmp = bmesh.new()
        tmp.from_mesh(me)
        col = tmp.loops.layers.color.get("Col")
        colm = bm.loops.layers.color.get("Col") or bm.loops.layers.color.new("Col")
        vm = [bm.verts.new(M @ v.co) for v in tmp.verts]
        for f in tmp.faces:
            mname = me.materials[f.material_index].name
            if mname not in mats:
                mats.append(mname)
            try:
                nf = bm.faces.new([vm[v.index] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = mats.index(mname)
            nf.smooth = True
            if col:
                for l1, l2 in zip(nf.loops, f.loops):
                    l1[colm] = l2[col]
        tmp.free()
    me = bpy.data.meshes.new(asset_name + "_w")
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(get_mat(m))
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    ob = bpy.data.objects.new(asset_name + "_w", me)
    bpy.context.scene.collection.objects.link(ob)
    if tris > max_tris:
        d = ob.modifiers.new("d", 'DECIMATE')
        d.ratio = max_tris / tris
    _box_uv(me, Vector())
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    ob.select_set(True)
    out = os.path.join(MODEL_DIR, family)
    import logging
    logging.disable(logging.INFO)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, asset_name + "_w.glb"), export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_image_format='NONE', export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_animations=False, export_extras=False)
    dg = bpy.context.evaluated_depsgraph_get()
    n = sum(len(p.vertices) - 2 for p in ob.evaluated_get(dg).to_mesh().polygons)
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    return n


def save_blend(family):
    os.makedirs(os.path.join(ROOT, "art", "blend"), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "art", "blend", family + ".blend"))
