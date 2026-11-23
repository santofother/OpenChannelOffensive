"""Check diagram consistency; this does not validate FPS balance or game collision."""
import json
import math
from build_maps import HERE, MAPS, solid_segments

def distance(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
    return math.dist(p,[a[0]+t*dx,a[1]+t*dy])

def check():
    result=[]
    for m in MAPS:
        assert len(m['sites'])==2
        assert sum(r['kind']=='siteA' for r in m['rooms'])==1
        assert sum(r['kind']=='siteB' for r in m['rooms'])==1
        assert all(w['destructible'] and w['reinforceable'] for w in m['walls'])
        w,h=m['size']
        # The room rectangles must tile the full floor, including the courtyard.
        for ix in range(w*2):
            for iy in range(h*2):
                x=(ix+.5)/2;y=(iy+.5)/2
                count=sum(r['x']<x<r['x']+r['w'] and r['y']<y<r['y']+r['h'] for r in m['rooms'])
                assert count==1,(m['id'],'floor overlap or gap',x,y,count)
        walls=[seg for wall in m['walls'] for seg in solid_segments(wall)]
        # 0.35 m player radius + 0.10 m wall half-thickness; props get body radius.
        length=0
        for a,b in zip(m['rotation'],m['rotation'][1:]):
            d=math.dist(a,b);length+=d
            for i in range(math.ceil(d/.04)+1):
                t=i/max(1,math.ceil(d/.04));p=[a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]
                assert all(distance(p,c,e)>=.45-1e-6 for c,e in walls),(m['id'],'rotation crosses wall',p)
                assert not any(c[0]-.35<p[0]<c[0]+c[2]+.35 and c[1]-.35<p[1]<c[1]+c[3]+.35 for c in m['props']),(m['id'],'rotation crosses prop',p)
        # Every illustrative cut/reinforcement must lie on a real, currently solid wall.
        for key in ['exampleCuts','exampleReinforcements']:
            for a,b in m[key]:
                assert any(distance(a,c,e)<1e-6 and distance(b,c,e)<1e-6 for c,e in walls),(m['id'],key,a,b)
        result.append(dict(layout=m['name'],sites=2,all_walls_destructible=True,all_walls_reinforceable=True,
                           floor_tiling='pass',rotation_clearance='pass',rotation_length_m=round(length,2),
                           primary_seconds_at_2_8mps=round(length/2.8,2),secondary_seconds_at_3_15mps=round(length/3.15,2),unarmed_seconds_at_3_4mps=round(length/3.4,2)))
    (HERE/'geometry-check.json').write_text(json.dumps(result,indent=2)+'\n')
    return result

if __name__=='__main__':
    for r in check():print(r)
