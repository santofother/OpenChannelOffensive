class_name Weapons
extends RefCounted
## Placeholder gun table (S8 shop). Stats are proposals for playtesting; models come in a later wave.
## slot 0 = primary (key 1), slot 1 = sidearm (key 2). `look` scales the placeholder viewmodel length.
const DEFAULT_SIDEARM := "p9"
const DEFAULT_PRIMARY := "service_rifle" ## offline/test loadout only; matches start without a primary
const ORDER := ["p9", "p9_match", "revolver", "smg", "carbine", "service_rifle", "marksman"]
const DEFS := {
	"p9": {"name": "P-9 Pistol", "slot": 1, "price": 0, "damage": 14.0, "interval": 0.25, "mag": 12, "reserve": 36,
		"reload": 1.5, "hip": 1.0, "aim": 0.4, "kick": 0.4, "auto": false, "look": 0.5},
	"p9_match": {"name": "P-9 Match", "slot": 1, "price": 300, "damage": 18.0, "interval": 0.2, "mag": 15, "reserve": 45,
		"reload": 1.6, "hip": 0.8, "aim": 0.2, "kick": 0.4, "auto": false, "look": 0.55},
	"revolver": {"name": "Magnum Revolver", "slot": 1, "price": 700, "damage": 45.0, "interval": 0.55, "mag": 6, "reserve": 24,
		"reload": 2.4, "hip": 0.6, "aim": 0.05, "kick": 1.2, "auto": false, "look": 0.6},
	"smg": {"name": "Compact SMG", "slot": 0, "price": 1100, "damage": 13.0, "interval": 0.06, "mag": 30, "reserve": 90,
		"reload": 1.8, "hip": 1.5, "aim": 0.8, "kick": 0.25, "auto": true, "look": 0.7},
	"carbine": {"name": "Light Carbine", "slot": 0, "price": 1700, "damage": 17.0, "interval": 0.085, "mag": 30, "reserve": 90,
		"reload": 1.9, "hip": 1.0, "aim": 0.2, "kick": 0.3, "auto": true, "look": 0.85},
	"service_rifle": {"name": "Service Rifle", "slot": 0, "price": 2700, "damage": 20.0, "interval": 0.1, "mag": 30, "reserve": 90,
		"reload": 1.8, "hip": 0.7, "aim": 0.1, "kick": 0.3, "auto": true, "look": 1.0},
	"marksman": {"name": "Marksman Rifle", "slot": 0, "price": 3300, "damage": 42.0, "interval": 0.4, "mag": 10, "reserve": 30,
		"reload": 2.6, "hip": 1.6, "aim": 0.02, "kick": 1.0, "auto": false, "look": 1.05, "scope": true, "zoom": 0.42},
}

static func index_of(id: String) -> int:
	return ORDER.find(id) if id != "" else 255

static func id_at(i: int) -> String:
	return ORDER[i] if i >= 0 and i < ORDER.size() else ""

static func apply(t: WeaponTuning, id: String) -> void:
	var d: Dictionary = DEFS[id]
	t.damage = d.damage
	t.fire_interval = d.interval
	t.mag_size = d.mag
	t.reserve_start = d.reserve
	t.reload_time = d.reload
	t.spread_hip_deg = d.hip
	t.spread_aim_deg = d.aim
	t.kick_deg = d.kick
	t.auto = d.auto
	t.ads_fov_mult = float(d.get("zoom", 0.8))
