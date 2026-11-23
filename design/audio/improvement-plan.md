# Audio improvement plan

November 17, 2026. The first playable implementation through stage 5 ships in protocol 14. [Project memory](../../PROJECT.md#current-milestone-known-issues-and-next-task) records shipped behavior and verification. Keep Session 09.5 active for real-device headphone and cross-platform checks.

The original slice used generic procedural shots, reloads and beeps, simple door sounds, and no footsteps. The implementation uses original procedural samples with a pooled effects mixer, separate voice buses and shared live direct-path obstruction. Lightwell's Electrical and Workshop spaces use metal footsteps, carpet covers other interiors, and the sites, courtyard and staging use concrete/asphalt. The current room treatment uses short shot reflections under cover. Revisit indirect routing through openings if blind tests show direct paths are hard to interpret.

## 1. Make the mix readable

Add Master, Weapons, Movement, Breaching, Objectives, Proximity Voice, Team Radio and Intercepted Radio buses. Expose master/effects/voice volume plus a separate enemy-radio level and mute control. Keep the enemy-radio mute independent from microphone mute and nearby speech; reset enemy listening to on each round. Preserve receiver authorization on the host.

Normalize source levels, reserve headroom for six talkers plus combat, cap simultaneous debris/weapon tails and add a gentle master limiter. Start with intelligible speech and distinct bomb cues, then balance shots and destruction around them. Keep ducking modest and configurable so speech cannot conceal approaching footsteps. Do not boost distant sounds into misleading proximity.

**Exit:** headphones hear one copy of every voice source, no clipping during six-talker/explosion stress, clear independent volume controls, and muting an intercepted radio removes queued spam immediately while proximity stays audible.

## 2. Add movement information

Generate footsteps from distance travelled while grounded, including remote authoritative movement. Cover carpet, concrete/asphalt and metal with 4–6 deterministic variants per surface; include stop/start scuffs and a quiet equipment layer. Standing movement is audible; crouching is quieter and slower. There is no sprint. Switching to a sidearm or empty hands changes cadence through actual movement speed, without making the faster loadout silent.

Prefer events derived from confirmed movement/state, with owner prediction and deduplication. Never play footsteps during reconciliation replay, while stationary, in the air, after death or behind an unauthorized spectator view. Share audible events with the bot hearing model so bots and humans receive comparable information.

**Exit:** a blind listener can distinguish movement from gun handling and identify left/right approach and approximate near/far range; no duplicate owner steps at 100 ms RTT / 2% simulated loss.

## 3. Give guns, doors and destruction distinct signatures

Create original recorded/procedural or license-audited $0 assets. Keep a source/license manifest before importing downloaded audio. Build per-weapon close shot, mechanical action and short indoor tail, plus suppressed variants and distance layers. Split reloads into magazine-out, magazine-in and action cues timed to the animation; cancel remaining cues on interrupted reload/switch/death.

For doors, distinguish hinge movement, latch, tie tightening, locked rattle, each kick, fourth-hit break and handle-shot release. For destruction, distinguish ordinary/reinforced charges, wall rupture, cover break and short bounded debris. Use surface contact points and modest seeded pitch/variant changes. Warm assets and pool players so first use causes no load hitch.

**Exit:** a listener can tell a pistol from a rifle, a locked-door kick from a wall breach, and local action from a distant event. A broken wall/cover emits once per authoritative revision and resets cleanly.

## 4. Unify obstruction and room response

First implement inexpensive direct-path occlusion for gameplay sounds using the same current world collision as voice. Opening a door or destroying a wall must update both immediately. Tune low-pass and attenuation separately; one wall should dull speech/shots rather than produce an arbitrary silence boundary. Avoid multiple expensive rays per sound per frame: update a bounded set at a fixed cadence and prioritize nearby/high-value sounds.

Then evaluate a small authored room/door graph from the canonical Lightwell definition. If direct rays remain confusing, route indirect sound through open doors and breached wall cells; pan from the nearest audible opening, with bounded path length and gain. Recompute only affected adjacency on door/wall revisions. Prototype before committing to a full acoustics engine. Use restrained room-specific early reflections; avoid long reverb that masks location. Full acoustic simulation remains outside scope.

**Exit:** blind tests of adjoining rooms, closed/open doors, intact/breached exterior and courtyard walls produce explainable changes; actual voices and gameplay cues agree on direction. No stale occlusion after reset or late join.

## 5. Finish objective and radio feedback

Give bomb pickup/drop, plant start/interruption/completion, defuse, countdown and round outcome distinct cues. Keep routine UI/buy feedback local. Plant/defuse and bomb beeps are spatial; round outcomes have a clear local cue without covering speech. Escalate countdown rhythm consistently and keep the visual timer authoritative.

Add short radio transmit/receive clicks and a clear theft-success cue. Present stolen-channel status and the O/button mute state visibly. All enemy team-radio speech is received after theft; stealing does not change the thief's transmit team. Keep proximity speech during radio use and mutual-theft cases. The former encrypted-radio purchase is removed under the user's clear-interception requirement.

**Exit:** players can identify a dropped/planted bomb and radio listening status without reading the full HUD. Intercepted speech stays receive-only; distant enemies cannot hear the thief unless they also stole that team's radio.

## Validation and order

Implement 1 → 2 → 3 → 4 → 5 in small complete increments. After each, run the relevant deterministic recipient/lifecycle checks and a focused exported-build headphone test. Record build, OS/audio device, volume settings, speaker/listener room, wall/door state and three largest confusions. Test Mac and Windows with each hosting; use both A/B sites, courtyard, closed/tied/broken doors, multiple wall openings, dead/live listeners and round resets.

Measure real mouth-to-ear latency (existing ≤250 ms target remains unverified), six-talker upload, peak audio-player count, audio processing/frame time and first-use stalls. Compare intact and heavily destroyed maps. Finish with six humans speaking during combat, then tune levels from those findings. Codec replacement, complex propagation and more assets are follow-on decisions only if these measurements justify them.

## Source shortlist and production decisions

Research, November 17, 2026. These are **candidates**, not selected or auditioned assets. CC0 is a public-domain dedication, not a software open-source license. Favor CC0 for the $0 project and preserve provenance even when credit is optional. No files have been imported as part of this research.

| Need | Candidate | Next action |
| --- | --- | --- |
| Concrete footsteps | [Footsteps, GboxMikeFozzy](https://opengameart.org/content/footsteps-0), six OGG files, listed CC0 | Audition for natural boot weight and separate usable steps; source carpet and metal separately. |
| Guns and handling | [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), listed CC0 | Audition prepared and raw recordings for rifle/pistol identity and mechanical layers; check the actual downloaded archive's provenance. |
| Door and gear mechanisms | [Mechanical Sounds, BMacZero](https://opengameart.org/content/mechanical-sounds), listed CC0 | Audition rattles, clicks and clanks for latches, locked doors and handling. |
| Impact and break layers | [Impact Sounds, Kenney](https://kenney.nl/assets/impact-sounds), 130 files, listed CC0; [100 CC0 SFX #2, rubberduck](https://opengameart.org/content/100-cc0-sfx-2) | Audition material impacts, doors and break layers; choose a small consistent palette. |
| Additional specific sounds | [Freesound](https://freesound.org/help/faq/) | Search individual recordings when gaps remain; check each file's license and provenance. Prefer CC0; CC BY requires attribution. Exclude noncommercial-only sounds for a potentially commercial game. |

LastMage is read-only reference material. Under `/Users/santofothergill/PersonalProjects/LastMage/the-last-fire-mage/assets/audio/`, audition `movement/step_mage_01.ogg` through `step_mage_08.ogg` and `step_villager_01.ogg` through `step_villager_05.ogg` for footsteps; `interact/carry_pickup_*.ogg` and `carry_drop_*.ogg` for equipment; `ui/ui_click_*.ogg` and `ui_confirm.ogg` for local UI; and `mage/hit_flesh_*.ogg` for impacts. Names alone do not establish that they fit a grounded FPS. The local search found no audio-specific source/license manifest in LastMage's Markdown, text or JSON files; ownership and reuse rights remain **unverified per file**. Locate original source records or confirm original authorship before copying any into this project. Do not assume all LastMage assets share a license.

For each selected source, record original title, creator, source URL or proof of authorship, exact license/version and terms, access date, original filename, edits, intended game filename and required attribution in a project asset manifest; retain a copy of applicable license text. Check that the uploader had rights to share the sound. Audition and level-match candidates in headphones before choosing them; retain only the needed files and variations. Recordings and sounds made for this project are also an option. Free commercial libraries with restrictive licenses are separate from the CC0 shortlist and must be evaluated against distribution needs before use.

The implemented build uses no downloaded or LastMage samples. The shortlist remains available for future auditioning after the headphone playtest identifies specific cues that need better source material.
