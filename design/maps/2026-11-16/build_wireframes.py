"""Regenerate editable SVG map proposals and the data used by the comparison view.

Coordinates are proposed metres, not surveyed dimensions or an engine implementation.
Run with Python 3, no dependencies.
"""
import json
from pathlib import Path
from html import escape

HERE = Path(__file__).resolve().parent

def room(name, x, y, w, h, kind="room"):
    return dict(name=name, x=x, y=y, w=w, h=h, kind=kind)

def wall(x1, y1, x2, y2, gaps=()):
    return dict(a=[x1,y1], b=[x2,y2], gaps=list(gaps))

MAPS = [
    dict(id="a", name="Switchboard", subtitle="Offset office loop", size=[30,24],
         rooms=[room("Reception",0,0,8,9), room("Lobby",0,9,8,6), room("Loading",0,15,8,9),
                room("Meeting",8,0,12,9), room("Spine",8,9,12,6,"hall"), room("Workshop",8,15,12,9),
                room("Archive",20,0,10,7), room("Server site",20,7,10,10,"site"), room("Electrical",20,17,10,7)],
         walls=[wall(8,0,8,24,[(4.3,5.7),(11.3,12.7),(20.3,21.7)]),
                wall(20,0,20,24,[(4.3,5.7),(11.3,12.7),(13,15),(20.3,21.7)]),
                wall(0,9,20,9,[(2.3,3.7),(12.3,13.7)]), wall(0,15,20,15,[(2.3,3.7),(12.3,13.7)]),
                wall(20,7,30,7,[(24,26)]), wall(20,17,30,17,[(21.3,22.7)])],
         breaches=[dict(id="B1",a=[24,7],b=[26,7],kind="soft"),dict(id="B2",a=[20,13],b=[20,15],kind="reinforced")],
         cover=[[14,11,2,3],[24,10,2,4],[5,1,1.5,2.5],[15,18,2,2],[26,2,1.5,2]],
         spawnA=[2,12],spawnD=[28,15],plant=[23,13],
         routes=[dict(name="Main",points=[[2,12],[11,12],[11,10],[18,10],[18,12],[22,12]]),
                 dict(name="South",points=[[2,12],[3,12],[3,21],[11,21],[21.8,21],[22,18.5],[22,16],[23,16]]),
                 dict(name="B1",breach=True,points=[[2,12],[3,12],[3,5],[11,5],[21,5],[25,5],[25,8.5]])],
         takeaway="Best first graybox: two normal site entrances plus one new attack front through Archive."),
    dict(id="b",name="Lightwell",subtitle="Courtyard ring",size=[32,28],
         rooms=[room("Reception",0,0,12,8),room("Conference",12,0,10,8),room("Server site",22,0,10,10,"site"),
                room("Lobby",0,8,8,12),room("Ring",8,8,14,3,"hall"),room("West",8,11,3,6,"hall"),
                room("Lightwell",11,11,10,6,"void"),room("East",21,10,3,10,"hall"),room("South",8,17,13,3,"hall"),
                room("Electrical",24,10,8,10),room("Loading",0,20,12,8),room("Workshop",12,20,12,8),room("Stores",24,20,8,8)],
         walls=[wall(0,8,22,8,[(4.3,5.7),(15.3,16.7)]),wall(12,0,12,8,[(3.3,4.7)]),
                wall(8,8,8,20,[(13.3,14.7)]),wall(22,0,22,10,[(3,5),(8.2,9.6)]),
                wall(22,10,32,10,[(26.3,27.7)]),wall(24,10,24,20,[(14.3,15.7)]),
                wall(0,20,32,20,[(4.3,5.7),(16.3,17.7),(27,29)]),
                wall(12,20,12,28,[(23.3,24.7)]),wall(24,20,24,28,[(23.3,24.7)]),
                wall(11,11,21,11),wall(21,11,21,17),wall(11,17,21,17),wall(11,11,11,17)],
         breaches=[dict(id="B1",a=[22,3],b=[22,5],kind="reinforced"),dict(id="B2",a=[27,20],b=[29,20],kind="soft")],
         cover=[[4,10,2,2],[15,4,2,2],[26,3,2,3],[29,12,2,2],[16,23,2,2]],
         spawnA=[2,15],spawnD=[30,7],plant=[25,6],
         routes=[dict(name="North",points=[[2,15],[5,15],[5,14],[9.5,14],[9.5,9.5],[19,9.5],[21,9],[23,9],[24,8]]),
                 dict(name="South",points=[[2,15],[5,15],[5,24],[10,24],[15,24],[15,22],[17,22],[17,18.5],[22.5,18.5],[22.5,15],[25,15],[27,16],[27,9],[28,8]]),
                 dict(name="B1",breach=True,points=[[2,15],[2,8.7],[5,8.7],[5,4],[13,4],[13,2],[20,2],[20,4],[23,4]])],
         takeaway="Strongest visual landmark and longest rotation; risks empty travel with only six players."),
    dict(id="c",name="Twin Wing",subtitle="Two-wing pincer",size=[28,28],
         rooms=[room("Archive",0,0,8,10),room("Server site",8,0,12,10,"site"),room("Electrical",20,0,8,10),
                room("Office wing",0,10,10,12),room("Cross hall",10,10,8,4,"hall"),room("Service core",10,14,8,8,"void"),
                room("Service wing",18,10,10,12),room("Loading lobby",0,22,28,6)],
         walls=[wall(8,0,8,10,[(2,4),(4.8,6.2)]),wall(20,0,20,10,[(4.8,6.2)]),
                wall(0,10,28,10,[(3.3,4.7),(13,15),(23.3,24.7)]),
                wall(10,10,10,22,[(11.3,12.7)]),wall(18,10,18,22,[(11.3,12.7)]),
                wall(10,14,18,14),wall(0,22,28,22,[(3.3,4.7),(23.3,24.7)])],
         breaches=[dict(id="B1",a=[13,10],b=[15,10],kind="soft"),dict(id="B2",a=[8,2],b=[8,4],kind="reinforced")],
         cover=[[4,15,3,2],[21,15,3,2],[12,3,3,3],[11,24,6,1],[2,2,2,2]],
         spawnA=[14,26.5],spawnD=[17,2],plant=[17,7],
         routes=[dict(name="West",points=[[14,26.5],[4,26.5],[4,20],[2,20],[2,12],[4,12],[4,8],[6,8],[6,5.5],[10,5.5]]),
                 dict(name="East",points=[[14,26.5],[24,26.5],[24,20],[26,20],[26,12],[24,12],[24,8],[22,8],[22,5.5],[18,5.5]]),
                 dict(name="B1",breach=True,points=[[14,26.5],[4,26.5],[4,20],[2,20],[2,12],[9,12],[14,12],[14,9],[15.5,8]])],
         takeaway="Clearest coordinated pincer, but splitting a three-player team can punish an early casualty."),
]

LABELS = {
    "a": {"Spine":[11.5,13.7],"Workshop":[12,18],"Archive":[23.5,2.3],"Server site":[25,8.7]},
    "b": {"Conference":[17,6.8],"Server site":[27,1.5],"Workshop":[19,26.5]},
    "c": {"Server site":[14,1.5],"Loading lobby":[14,23.2]},
}
for m in MAPS:
    for r in m["rooms"]:
        r["label"]=LABELS[m["id"]].get(r["name"],[r["x"]+r["w"]/2,r["y"]+r["h"]/2])

def segments(w):
    a,b=w["a"],w["b"]
    horizontal=a[1]==b[1]
    start=a[0] if horizontal else a[1]
    end=b[0] if horizontal else b[1]
    for lo,hi in sorted(w["gaps"]):
        if lo>start:
            yield ([start,a[1]],[lo,a[1]]) if horizontal else ([a[0],start],[a[0],lo])
        start=hi
    if end>start:
        yield ([start,a[1]],[end,a[1]]) if horizontal else ([a[0],start],[a[0],end])

def svg(m):
    s=27; ox=90; oy=170; width=1044; height=1150
    colors=dict(room="#172a3a",hall="#213c4b",site="#334d43",void="#0b131c")
    p=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
       '<rect width="100%" height="100%" fill="#0b131c"/>',
       '<style>text{font-family:Arial,sans-serif;fill:#e5edf0} .minor{fill:#a9bac4} .label{font-size:17px;text-anchor:middle} .wall{stroke:#ced8df;stroke-width:7;stroke-linecap:butt}</style>',
       f'<text x="70" y="52" font-size="14" fill="#76c9d2">OPEN CHANNEL OFFENSIVE / MAP STUDY 01 / PROPOSED</text>',
       f'<text x="70" y="96" font-size="36">{m["id"].upper()} / {m["name"]}</text>',
       f'<text x="70" y="130" class="minor" font-size="18">{m["subtitle"]} · {m["size"][0]} × {m["size"][1]} m footprint · 3v3 / one floor / one site</text>']
    def rect(x,y,w,h,fill,other=""):
        p.append(f'<rect x="{ox+x*s}" y="{oy+y*s}" width="{w*s}" height="{h*s}" fill="{fill}" {other}/>')
    def line(a,b,col,sw=7,dash=""):
        p.append(f'<line x1="{ox+a[0]*s}" y1="{oy+a[1]*s}" x2="{ox+b[0]*s}" y2="{oy+b[1]*s}" stroke="{col}" stroke-width="{sw}" {dash}/>')
    for r in m["rooms"]: rect(r["x"],r["y"],r["w"],r["h"],colors[r["kind"]])
    # One-metre grid; no mechanic is implied by the grid.
    for x in range(m["size"][0]+1): line([x,0],[x,m["size"][1]],"#405563",.4)
    for y in range(m["size"][1]+1): line([0,y],[m["size"][0],y],"#405563",.4)
    for w in m["walls"]:
        for a,b in segments(w): line(a,b,"#ced8df")
    w,h=m["size"]
    for a,b in [([0,0],[w,0]),([w,0],[w,h]),([w,h],[0,h]),([0,h],[0,0])]: line(a,b,"#ced8df")
    for c in m["cover"]: rect(*c,"#647888",'stroke="#a8bbc7" stroke-width="2"')
    for b in m["breaches"]:
        color="#f3bd60" if b["kind"]=="soft" else "#de92c9"
        line(b["a"],b["b"],color,10,'stroke-dasharray="12 5"' if b["kind"]=="soft" else '')
        cx=(b["a"][0]+b["b"][0])/2; cy=(b["a"][1]+b["b"][1])/2
        p.append(f'<text x="{ox+cx*s+15}" y="{oy+cy*s-14}" font-size="16" style="fill:{color}">{b["id"]}</text>')
    for i,route in enumerate(m["routes"]):
        coords=" ".join(f'{ox+x*s},{oy+y*s}' for x,y in route["points"])
        color=["#66d8ec","#83aef6","#f3bd60"][i]
        dash='stroke-dasharray="9 7"' if route.get("breach") else ''
        p.append(f'<polyline points="{coords}" fill="none" stroke="{color}" stroke-width="4" opacity=".8" {dash}/>')
        x,y=route["points"][-1]
        p.append(f'<circle cx="{ox+x*s}" cy="{oy+y*s}" r="5" fill="{color}"/>')
    for r in m["rooms"]:
        x=ox+r["label"][0]*s; y=oy+r["label"][1]*s
        p.append(f'<text class="label" x="{x}" y="{y}">{escape(r["name"])}</text>')
        if r["kind"]=="void": p.append(f'<text class="minor" x="{x}" y="{y+22}" text-anchor="middle" font-size="13">INACCESSIBLE</text>')
    for key,letter,color in [("spawnA","A","#66d8ec"),("spawnD","D","#fa9a91"),("plant","P","#b5e6ab")]:
        x,y=m[key]; px=ox+x*s;py=oy+y*s
        p.append(f'<circle cx="{px}" cy="{py}" r="16" fill="#0b131c" stroke="{color}" stroke-width="3"/><text x="{px}" y="{py+6}" font-size="17" text-anchor="middle" style="fill:{color}">{letter}</text>')
    y=oy+m["size"][1]*s+50
    p.extend([f'<text x="90" y="{y}" font-size="16">A attacker staging · D defender start area · P proposed plant pocket</text>',
              f'<text x="90" y="{y+28}" font-size="16" class="minor">Wall gaps = open doors · gray blocks = full-height hard cover</text>',
              f'<text x="90" y="{y+56}" font-size="16"><tspan fill="#f3bd60">Dashed amber = ordinary panel</tspan> · <tspan fill="#de92c9">purple = reinforced panel</tspan></text>',
              f'<text x="90" y="{y+84}" font-size="16" class="minor">Cyan / blue = normal routes · dashed amber route needs B1 open</text>',
              f'<text x="90" y="{y+112}" font-size="16" class="minor">Diagram grid = 1 m · panel length = 2 m; actual breach opening ≈ 1.2 m</text>',
              f'<text x="90" y="{y+149}" font-size="16">Layout hypothesis only — no balance, acoustics or sightlines validated in-engine.</text>'])
    # Scale bar and north reference above the map; north is diagram orientation only.
    line([0,-.8],[5,-.8],"#a9bac4",3)
    p.append(f'<text x="{ox+2.5*s}" y="{oy-30}" class="minor" font-size="13" text-anchor="middle">5 m</text>')
    p.append('</svg>')
    return "\n".join(p)

if __name__ == "__main__":
    (HERE/"wireframes").mkdir(exist_ok=True)
    for m in MAPS:
        (HERE/"wireframes"/f'{m["id"]}-{m["name"].lower().replace(" ","-")}.svg').write_text(svg(m))
    (HERE/"layouts.json").write_text(json.dumps(MAPS,indent=2)+"\n")
    print("Wrote 3 editable wireframes and layouts.json")
