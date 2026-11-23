"""Original low-poly operator and removable equipment, metres, Blender +Y forward."""
import gearlib as G
import operator_body

def build():
    out = {'operator': operator_body.build()}
    a = G.Asset('vest','wearables');p=a.part('Vest')
    p.box('team',(.402,.29,.32),(0,0,1.275),bevel=.04,segs=3)
    for s in [-1,1]:
        p.box('webbing',(.055,.245,.075),(s*.125,0,1.425),bevel=.012)
    for z in [1.28, 1.34, 1.40]:
        for y in [-.146,.146]:
            p.box('webbing',(.278,.014,.024),(0,y,z),bevel=.003)
    for x in [-.12,0,.12]:
        p.box('team',(.105,.06,.15),(x,.16,1.16),bevel=.012)
        p.box('webbing',(.07,.009,.025),(x,.196,1.205),bevel=.003)
    p.box('polymer_black',(.055,.045,.09),(-.12,.165,1.34),bevel=.008)
    p.cyl('rubber',.004,(-.12,.165,1.38),(-.12,.165,1.49),segs=8)
    a.build();out['vest']=G.export('vest','wearables')
    a=G.Asset('helmet','wearables');p=a.part('Helmet')
    p.lathe('team', [(1.62,.125),(1.67,.13),(1.736,.122),(1.764,.098),(1.786,.061),(1.797,0)],'Z',segs=20)
    for s in [-1,1]:
        p.box('polymer_black',(.035,.09,.10),(s*.123,0,1.60),bevel=.018,segs=3)
    p.box('steel_black',(.04,.02,.04),(0,.12,1.69),bevel=.005)
    a.socket('NVG',(0,.13,1.69))
    a.build();out['helmet']=G.export('helmet','wearables')
    G.save_blend('wearables')
    return out
