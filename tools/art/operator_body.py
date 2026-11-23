"""Weighted uniform lofts in an exact T-pose. All dimensions are metres.

Arms follow adult proportions (wrist reach 0.55 m, arm span about body height). Each hand has a
palm, four fingers and a thumb on Fingers/FingerTips/Thumb bones so third-person holds can curl
them around grips. The outer shoulder line is shared with the clavicle (Shoulder) bones."""
import math
import os

import bpy
from mathutils import Vector
import gearlib as G


def build():
    asset = G.Asset("operator", "wearables")
    asset.socket("Weapon", (.09, .31, 1.42))
    asset.build()
    collection = bpy.data.collections["operator"]
    rig = bpy.data.objects.new("OperatorRig", bpy.data.armatures.new("Humanoid"))
    collection.objects.link(rig)
    rig.parent = collection.objects["operator"]
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")

    def bone(name, head, tail, parent=None):
        b = rig.data.edit_bones.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = rig.data.edit_bones[parent]

    spine = [("Hips", .87), ("Spine", 1.01), ("Chest", 1.19), ("Neck", 1.48), ("Head", 1.54)]
    for i, (name, z) in enumerate(spine):
        top = spine[i + 1][1] if i + 1 < len(spine) else 1.77
        bone(name, (0, 0, z), (0, 0, top), spine[i-1][0] if i else None)
    for sign, side in [(1, "Right"), (-1, "Left")]:
        for names, joints, parent in [
            (["Shoulder","Arm","ForeArm","Hand","Fingers","FingerTips"],
             [(0,0,1.44),(.185,0,1.435),(.48,0,1.435),(.735,0,1.435),(.835,0,1.435),(.877,0,1.435),(.925,0,1.433)], "Chest"),
            (["UpLeg","Leg","Foot"], [(.10,0,.91),(.108,.012,.505),(.113,0,.115),(.113,.15,.05)], "Hips")]:
            for j, name in enumerate(names):
                p, q = joints[j:j+2]
                bone(side+name, (sign*p[0],*p[1:]), (sign*q[0],*q[1:]), parent)
                parent = side+name
        bone(side+"Thumb", (sign*.752,.022,1.425), (sign*.812,.06,1.414), side+"Hand")
    bpy.ops.object.mode_set(mode="OBJECT")
    vertices, faces, materials, weights, slots = [], [], [], [], []

    def loft(rows, skin, paint, arm=0, sides=12):
        # Each cross-section has a center, two elliptical radii and one skin-weight map.
        start = len(vertices)
        def face(indices, mat):
            faces.append(indices)
            if mat not in slots:
                slots.append(mat)
            materials.append(slots.index(mat))
        for j, (x,y,z,a,b) in enumerate(rows):
            for k in range(sides):
                u = math.tau*k/sides
                c, s = math.cos(u), math.sin(u)
                vertices.append((x,y+a*c,z+arm*b*s) if arm else (x+a*c,y+b*s,z))
                weights.append(skin[j](math.cos(u)) if callable(skin[j]) else skin[j])
            if j:
                for k in range(sides):
                    lo = start+(j-1)*sides
                    h = (k+1)%sides
                    face([lo+k,lo+h,lo+sides+h,lo+sides+k],paint(j,k))
        face(list(reversed(range(start,start+sides))),paint(1,0))
        face(list(range(len(vertices)-sides,len(vertices))),paint(len(rows)-1,0))

    def column(rows, skins, paint):
        loft([(0,y,z,xr,yr) for z,y,xr,yr in rows], skins, paint)

    def yoke(share):
        # Vertices on the outer shoulder line move partly with that side's clavicle.
        return lambda c: ({"Chest":1-share,("Right" if c>0 else "Left")+"Shoulder":share}
                          if abs(c) > .8 else {"Chest":1})
    column([(.83,0,.15,.105),(.93,0,.178,.117),(1.01,0,.15,.108),(1.13,0,.161,.117),
            (1.235,0,.184,.123),(1.385,0,.198,.12),(1.44,0,.172,.098),(1.485,0,.085,.075)],
           [{"Hips":1}]*2+[{"Spine":1},{"Spine":.6,"Chest":.4},{"Chest":1},yoke(.3),yoke(.5),{"Chest":1}],
           lambda j,k: "team" if j>=5 and k not in (0,5,6,11) else "uniform")
    column([(.955,0,.172,.119),(.99,0,.168,.119)], [{"Hips":1}]*2,lambda j,k:"webbing")
    column([(1.46,0,.076,.074),(1.54,0,.069,.07),(1.575,0,.085,.08)],
           [{"Neck":1}]*3,lambda j,k:"uniform")
    column([(1.52,.015,.059,.077),(1.56,.015,.083,.091),(1.65,0,.106,.111),
            (1.705,-.003,.103,.104),(1.752,-.008,.081,.082),(1.772,-.008,.042,.052)],
           [{"Head":1}]*6,lambda j,k:"graphite" if j<=3 and k<6 else "uniform")
    # Sewn placket and utility belt buckle sit proud of the cloth.
    loft([(0,.115,1.233,.009,.009),(0,.121,1.385,.009,.009),(0,.102,1.45,.008,.008)],
         [{"Chest":1}]*3,lambda j,k:"webbing",sides=8)
    loft([(0,.119,.957,.031,.010),(0,.119,.987,.031,.010)],
         [{"Hips":1}]*2,lambda j,k:"polymer_black",sides=8)
    for sign,side in [(1,"Right"),(-1,"Left")]:
        def skin(a, b=None, w=.5):
            return {side+a:1} if b is None else {side+a:w,side+b:1-w}
        # Shoulder root (inside the torso), deltoid, biceps, elbow, forearm, cuff, palm to knuckles.
        rows=[(.14,.078,.072),(.20,.085,.08),(.265,.079,.076),(.33,.068,.066),(.40,.06,.057),
              (.455,.056,.053),(.48,.056,.052),(.51,.057,.051),(.575,.057,.049),(.66,.045,.041),
              (.715,.039,.034),(.735,.037,.029),(.76,.044,.024),(.80,.047,.021),(.83,.043,.017)]
        xs=[x for x,a,b in rows]
        top=lambda k: k<6 if sign==1 else k>=6
        loft([(x*sign,0,1.435,a,b) for x,a,b in rows],
             [skin("Shoulder"),skin("Shoulder","Arm",.45),skin("Arm","Shoulder",.9)]+[skin("Arm")]*2+
             [skin("Arm","ForeArm",.8),skin("Arm","ForeArm"),skin("Arm","ForeArm",.2)]+[skin("ForeArm")]*3+
             [skin("Hand","ForeArm")]+[skin("Hand")]*2+[skin("Hand","Fingers",.7)],
             lambda j,k:"glove" if xs[j-1]>=.714 else ("team" if 2<=j<=3 and top(k) else "uniform"),arm=sign)
        # Fingers lie flat in the rest pose; index nearest the front (+Y), pinky at the back.
        for y,length,z in [(.03,.085,1.434),(.01,.093,1.435),(-.01,.087,1.434),(-.029,.068,1.432)]:
            tip=.828+length
            loft([(sign*x,y,z,a,b) for x,a,b in [(.828,.0115,.0105),(.877,.0105,.0095),(tip-.008,.0095,.0085),(tip,.005,.005)]],
                 [skin("Fingers","Hand"),skin("Fingers","FingerTips"),skin("FingerTips"),skin("FingerTips")],
                 lambda j,k:"glove",arm=sign,sides=8)
        loft([(sign*x,y,z,a,b) for x,y,z,a,b in [(.748,.018,1.426,.014,.015),(.776,.037,1.42,.012,.012),
                                                 (.80,.053,1.416,.01,.01),(.818,.063,1.413,.006,.006)]],
             [skin("Hand","Thumb",.6)]+[skin("Thumb")]*3,lambda j,k:"glove",arm=sign,sides=8)
        # Leg rings run ankle to hip so winding remains outward.
        leg=[(.105,.048,.054),(.19,.056,.061),(.215,.061,.06),(.32,.076,.079),
             (.455,.071,.074),(.50,.078,.078),(.545,.077,.078),(.68,.088,.092),(.79,.098,.10),(.905,.094,.096)]
        loft([(sign*.108,.012*(1-abs(z-.5)*2),z,a,b) for z,a,b in leg],
             [skin("Leg")]*4+[skin("Leg","UpLeg",.8),skin("Leg","UpLeg"),skin("Leg","UpLeg",.2)]+[skin("UpLeg")]*3,
             lambda j,k:"uniform" if j!=5 or k>=6 else "sleeve")
        pocket=[(.655,.057,.030),(.674,.066,.035),(.776,.068,.034),(.798,.071,.038),(.814,.059,.030)]
        loft([(sign*.181,0,z,b,a) for z,a,b in pocket],[skin("UpLeg")]*5,
             lambda j,k:"webbing" if j==4 else "uniform")
        boot=[(.008,.052,.068,.131),(.035,.052,.069,.134),(.068,.05,.068,.131),
              (.105,.026,.064,.101),(.142,0,.058,.066),(.199,0,.059,.064)]
        loft([(sign*.11,y,z,a,b) for z,y,a,b in boot],[skin("Foot")]*4+[skin("Foot","Leg"),skin("Leg")],
             lambda j,k:"rubber" if j<=2 else "glove")

        for z in [.121,.159,.186]:
            loft([(sign*.11,.003,z,.060,.068),(sign*.11,.003,z+.011,.060,.068)],
                 [skin("Foot","Leg")]*2, lambda j,k:"glove_pad")

    mesh = bpy.data.meshes.new("Uniform")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    body = bpy.data.objects.new("Body",mesh)
    collection.objects.link(body)
    body.parent = rig
    for name in slots:
        mesh.materials.append(G.get_mat(name))
    for poly, index in zip(mesh.polygons,materials):
        poly.material_index = index
        poly.use_smooth = slots[index] != "graphite"
    G._box_uv(mesh,Vector())
    groups = {b.name:body.vertex_groups.new(name=b.name) for b in rig.data.bones}
    for i, mapping in enumerate(weights):
        for name, weight in mapping.items():
            groups[name].add([i],weight,"REPLACE")
    mod = body.modifiers.new("Skin","ARMATURE")
    mod.object = rig
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(G.ROOT,"art","blend","operator-tpose.fbx"),
                             use_selection=True, add_leaf_bones=False, bake_anim=False)
    return G.export("operator","wearables")
