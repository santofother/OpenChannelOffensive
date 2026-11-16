# Free asset candidates — weapons, charges, sound

Optional reference, researched November 16, 2026 (web research by a subagent; nothing downloaded or imported). Licenses marked "verified" were read on the listing page. Before importing anything, record source URL, author, license text, attribution and modifications (see [architecture: Assets/settings](architecture.md#assetssettings)) and re-check the license inside the download.

**Main gap:** no free, commercial-safe modern-military rifle + first-person arms + full animation set was found. Plan on static CC0 gun meshes, animated in code (the current `Viewmodel` approach) or with a self-made arm rig.

## Weapons / arms

| Asset | License | Contents | Fit / notes |
| --- | --- | --- | --- |
| [chilly_durango — Low Poly Firearms](https://chilly-durango.itch.io/low-poly-firearms) | CC0 (verified) | 16 guns (AK, M4, AUG, UMP, pistols, shotguns), one .blend, moving parts separate, ≤270 tris, untextured | **Best pick.** Grounded silhouettes; needs our materials; export GLB from Blender, fix pivots |
| [Quaternius — 50 Lowpoly Guns](https://quaternius.itch.io/50-lowpoly-guns) | CC0 (verified) | 50+ guns, scopes, suppressors; FBX/OBJ/Blend | Stylised; use for suppressors/optics; rebuild materials |
| [Styloo — Guns Asset Pack](https://styloo.itch.io/guns-asset-pack) | CC0 (verified), $5+ | Guns, flashbang, grenades, ammo box, GLB | PSX style — off-vibe; grenades useful. Not free |
| [Kuptchi — Retro Weapon Pack](https://kuptchi.itch.io/f) | Custom, unclear ("suited for commercial", no resale) | 4 rigged weapons, FP arms, 80+ animations | Only free arms+animation set found. Retro style. Confirm license with creator before shipping |

Excluded: GDQuest godot-4-fps-arms (art is CC-BY-NC-SA — non-commercial; code MIT, useful as structure reference only); Unity Asset Store / Fab / Unreal Marketplace packs (engine-locked or paid); Mixamo (unverified, no FPS arm sets); Sketchfab (unchecked; per-model licenses).

## Breach charge

- [goldenranger915 — C4 charge](https://www.summerengine.com/asset-store/library-explosive-c4): CC0 (verified), GLB brick with detonator and wire. New listing — inspect poly count/textures. Scale/reskin for the heavy charge.
- Avoid OpenGameArt "C4 Charge" (CC-BY-SA 3.0, share-alike).

## Sound

- [Sonniss GDC 2026 bundle](https://gdc.sonniss.com/) and [GDC 2024](https://sonniss.com/gameaudiogdc): royalty-free, commercial use, no attribution ([terms](https://sonniss.com/gdc-bundle-license/)). Restrictions: no AI/ML training, no redistributing the raw sounds as a pack. Check the track list for gun/foley/explosion content. Best bulk source.
- [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds): CC0, 130 impacts/foley (debris, doors, bodies).
- OpenGameArt CC0 gunshot uploads and Freesound CC0-only: variable quality, check each file. Never CC-BY-NC.

## Suggested starter kit

chilly_durango rifle (+ Quaternius suppressor/optic) → C4 by goldenranger915 → Sonniss weapons/explosions + Kenney impacts. No attribution strictly required for these; credit creators anyway.
