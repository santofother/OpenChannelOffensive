"""Design proposals, not engine levels. Python 3; no third-party dependencies.

All coordinates are proposed metres. Every wall segment, including every exterior
segment, is destructible and reinforceable. Module subdivision is a diagram aid,
not a restriction on where players can destroy or reinforce walls.
"""
import json
import math
from pathlib import Path
from html import escape

HERE=Path(__file__).resolve().parent

def room(name,x,y,w,h,kind="room",label=None):
    return dict(name=name,x=x,y=y,w=w,h=h,kind=kind,label=label or [x+w/2,y+h/2])

def wall(x1,y1,x2,y2,gaps=()):
    return dict(a=[x1,y1],b=[x2,y2],gaps=list(gaps),destructible=True,reinforceable=True)

MAPS=[
dict(id="a",name="Switchboard",subtitle="Diagonal sites / central connector",size=[30,24],bounds=[-4,-4,38,38],
     rooms=[room("Reception",0,0,9,8),room("Meeting",9,0,10,8),room("A · Server",19,0,11,8,"siteA",[24.5,2]),
            room("Office",0,8,9,8),room("Connector",9,8,12,8,"hall",[15,9.8]),room("Electrical",21,8,9,8),
            room("B · Workshop",0,16,12,8,"siteB",[6,18]),room("Archive",12,16,9,8),room("Loading",21,16,9,8)],
     walls=[wall(0,0,30,0,[(13.3,14.7)]),wall(30,0,30,24,[(11.3,12.7)]),wall(0,24,30,24,[(25.3,26.7)]),wall(0,0,0,24,[(11.3,12.7)]),
            wall(0,8,30,8,[(3.3,4.7),(13.3,14.7),(24.3,25.7)]),wall(0,16,30,16,[(4.3,5.7),(15.3,16.7),(25.3,26.7)]),
            wall(9,0,9,16,[(3.3,4.7),(11.3,12.7)]),wall(19,0,19,8,[(3.3,4.7)]),wall(21,8,21,24,[(11.3,12.7),(19.3,20.7)]),wall(12,16,12,24,[(19.3,20.7)])],
     props=[[13,11,3,2],[23,3,2,2],[4,20,2,2],[14,18,2,1.3],[28,27,3,1.5]],
     spawn=[32,31],sites=[[26,5.5],[7.5,20]],
     rotation=[[26,5.5],[25,5.5],[25,9.5],[25,12],[18,12],[18,14],[16,14],[16,17],[18,17],[18,20],[11,20],[7.5,20]],
     exampleCuts=[[[23,0],[25,0]],[[0,18],[0,20]],[[13,16],[15,16]]],
     exampleReinforcements=[[[26,0],[28,0]],[[2,24],[4,24]],[[9,5],[9,7]]]),
next(layout for layout in json.loads((HERE/"layouts.json").read_text()) if layout["id"] == "b"),
dict(id="c",name="Twin Wing",subtitle="Parallel sites / shared server room",size=[28,24],bounds=[-4,-4,36,38],
     rooms=[room("A · Records",0,0,10,10,"siteA",[5,1.8]),room("Server",10,0,8,10,label=[14,1]),room("B · Electrical",18,0,10,10,"siteB",[23,1.8]),
            room("Office wing",0,10,10,8,label=[5,11.5]),room("Cross hall",10,10,8,4,"hall"),room("Utility",10,14,8,4),
            room("Service wing",18,10,10,8,label=[23,11.5]),room("Loading lobby",0,18,28,6,label=[14,19.5])],
     walls=[wall(0,0,28,0,[(13.3,14.7)]),wall(28,0,28,24,[(13.3,14.7)]),wall(0,24,28,24,[(3.3,4.7),(23.3,24.7)]),wall(0,0,0,24,[(13.3,14.7)]),
            wall(10,0,10,10,[(3.3,4.7)]),wall(18,0,18,10,[(6.3,7.7)]),wall(0,10,28,10,[(3.3,4.7),(13.3,14.7),(23.3,24.7)]),
            wall(10,10,10,18,[(11.3,12.7),(15.3,16.7)]),wall(18,10,18,18,[(11.3,12.7),(15.3,16.7)]),wall(10,14,18,14,[(13.3,14.7)]),
            wall(0,18,28,18,[(3.3,4.7),(13.3,14.7),(23.3,24.7)])],
     props=[[4,4,2,2],[22,4,2,2],[13,2,2,5],[4,13,2,2],[22,13,2,2],[11,21,6,1],[12,26,4,2]],
     spawn=[14,31],sites=[[7,7.5],[25,7.5]],
     rotation=[[7,7.5],[8.5,7.5],[8.5,4],[11.5,4],[11.5,8.5],[16,8.5],[16,7],[20,7],[25,7.5]],
     exampleCuts=[[[0,6],[0,8]],[[28,6],[28,8]],[[10,7],[10,9]]],
     exampleReinforcements=[[[2,0],[4,0]],[[24,0],[26,0]],[[18,2],[18,4]]]),
]

def solid_segments(w):
    horizontal=w["a"][1]==w["b"][1]
    start=w["a"][0] if horizontal else w["a"][1]
    end=w["b"][0] if horizontal else w["b"][1]
    for lo,hi in sorted(w["gaps"])+[(end,end)]:
        if lo>start:
            yield ([start,w["a"][1]],[lo,w["a"][1]]) if horizontal else ([w["a"][0],start],[w["a"][0],lo])
        start=hi

def svg(m):
    width=1180;height=1430
    s=min(24,(width-180)/m["bounds"][2],(height-370)/m["bounds"][3])
    ox=90-m["bounds"][0]*s;oy=190-m["bounds"][1]*s
    fills={"room":"#1b2d3c","hall":"#25404b","siteA":"#204854","siteB":"#493e32","yard":"#253c36"}
    p=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       '<rect width="100%" height="100%" fill="#0c141e"/>',
       '<style>text{font-family:Arial,sans-serif;fill:#e8f0f3}.muted{fill:#b2c4ce}.label{font-size:18px;text-anchor:middle;paint-order:stroke;stroke:#182735;stroke-width:3;stroke-linejoin:round}</style>',
       '<text x="70" y="49" font-size="15">OPEN CHANNEL OFFENSIVE / MAP STUDY 02 / PROPOSED</text>',
       f'<text x="70" y="94" font-size="38">{m["name"]}</text>',
       f'<text x="70" y="128" font-size="20" class="muted">{m["subtitle"]} · {m["size"][0]} × {m["size"][1]} m building</text>',
       '<text x="70" y="160" font-size="19" fill="#82d6cf">TWO PLANT SITES · EVERY WALL DESTRUCTIBLE + REINFORCEABLE</text>']
    def line(a,b,color,stroke=6,dash=""):
        p.append(f'<line x1="{ox+a[0]*s}" y1="{oy+a[1]*s}" x2="{ox+b[0]*s}" y2="{oy+b[1]*s}" stroke="{color}" stroke-width="{stroke}" {dash}/>')
    def rect(x,y,w,h,fill,attrs=""):
        p.append(f'<rect x="{ox+x*s}" y="{oy+y*s}" width="{w*s}" height="{h*s}" fill="{fill}" {attrs}/>')
    rect(*m["bounds"],"#142330",'stroke="#4c6573" stroke-width="1" stroke-dasharray="5 6"')
    for r in m["rooms"]:rect(r["x"],r["y"],r["w"],r["h"],fills[r["kind"]])
    w,h=m["size"]
    for x in range(w+1):line([x,0],[x,h],"#3b5160",.4)
    for y in range(h+1):line([0,y],[w,y],"#3b5160",.4)
    for c in m["props"]:rect(*c,"#607887",'stroke="#adbfca" stroke-width="1.5"')
    for wall_info in m["walls"]:
        for a,b in solid_segments(wall_info):line(a,b,"#cedce2")
    path=" ".join(f'{ox+x*s},{oy+y*s}' for x,y in m["rotation"])
    p.append(f'<polyline points="{path}" fill="none" stroke="#c8a9e8" stroke-width="4" stroke-dasharray="8 7"/>')
    for r in m["rooms"]:
        if not r["name"]:continue
        x,y=r["label"];p.append(f'<text class="label" x="{ox+x*s}" y="{oy+y*s}">{escape(r["name"])}</text>')
    markers=[(m["sites"][0],"A","#71dcf0"),(m["sites"][1],"B","#ffc37e")]
    for index,zone in enumerate(m.get("attack_zones",[]),1):
        x,y,_=zone["spawns"][2]
        markers.append(((x,y),f"ATK {index}","#a6e7bc"))
    if "spawn" in m:
        markers.append((m["spawn"],"ATK","#a6e7bc"))
    for (x,y),letter,color in markers:
        px=ox+x*s;py=oy+y*s
        p.append(f'<circle cx="{px}" cy="{py}" r="{23 if letter.startswith("ATK") else 20}" fill="#0c141e" stroke="{color}" stroke-width="3"/><text x="{px}" y="{py+6}" text-anchor="middle" font-size="{14 if letter.startswith("ATK") else 20}" style="fill:{color}">{letter}</text>')
    y=190+m["bounds"][3]*s+42
    staging="ATK 1–7 = attacker zones" if "attack_zones" in m else "ATK = staging proposal"
    p.extend([f'<text x="90" y="{y}" font-size="18">A / B = alternative plant pockets · {staging}</text>',
              f'<text x="90" y="{y+31}" font-size="18" class="muted">All pale walls, including exterior + courtyard walls, can be destroyed or reinforced.</text>',
              f'<text x="90" y="{y+62}" font-size="18" class="muted">Gaps = existing doors · dashed purple = one intact A↔B rotation · grid = 1 m</text>',
              f'<text x="90" y="{y+93}" font-size="18" class="muted">Gray blocks = cover (breakable in Lightwell). No permanent wall chokepoints.</text>',
              f'<text x="90" y="{y+132}" font-size="18">Draft geometry only — balance, sightlines and sound require in-engine playtests.</text>'])
    p.append('</svg>');return "\n".join(p)

if __name__=="__main__":
    (HERE/"wireframes").mkdir(exist_ok=True)
    for m in MAPS:(HERE/"wireframes"/f'{m["id"]}-{m["name"].lower().replace(" ","-")}.svg').write_text(svg(m))
    (HERE/"layouts.json").write_text(json.dumps(MAPS,indent=2)+"\n")
    print("Wrote 3 v2 floorplans: 2 sites each; every wall destructible + reinforceable")
