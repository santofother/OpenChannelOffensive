class_name ShopCatalog
extends RefCounted
## CS-style buy menu contents. `ready` items work now; the rest are listed greyed out until their phase lands.
## Breach-tool prices/limits come from MatchTuning; weapon/equipment prices from Weapons/this table.
## Reinforcements one player can carry (the wire format stores a byte). Unreachable with the credit cap.
const MAX_REINFORCE := 250
const UTILITY_LIMIT := 3
const DROP_UTILITY := ["ordinary", "heavy", "medkit", "zip_tie", "frag", "flash", "smoke", "incendiary"]
const CATEGORIES := ["Equipment", "Pistols", "Mid-Tier", "Rifles", "Breach Tools", "Grenades", "Attachments"]
const ITEMS := [
	{"id": "vest", "cat": 0, "name": "Body Armor", "price": 650, "limit": 1},
	{"id": "armor_helmet", "cat": 0, "name": "Armor + Helmet", "price": 1000, "limit": 1},
	{"id": "defuse_kit", "cat": 0, "name": "Defuse Kit", "price": 400, "limit": 1, "role": "defend"},
	{"id": "medkit", "cat": 0, "name": "Medkit", "price": 400},
	{"id": "p9_match", "cat": 1, "name": "P-9 Match", "limit": 1, "weapon": true},
	{"id": "revolver", "cat": 1, "name": "Magnum Revolver", "limit": 1, "weapon": true},
	{"id": "smg", "cat": 2, "name": "Compact SMG", "limit": 1, "weapon": true},
	{"id": "carbine", "cat": 2, "name": "Light Carbine", "limit": 1, "weapon": true},
	{"id": "service_rifle", "cat": 3, "name": "Service Rifle", "limit": 1, "weapon": true},
	{"id": "marksman", "cat": 3, "name": "Marksman Rifle", "limit": 1, "weapon": true},
	{"id": "ordinary", "cat": 4, "name": "Ordinary Charge", "role": "attack"},
	{"id": "heavy", "cat": 4, "name": "Heavy Charge", "role": "attack"},
	{"id": "kit", "cat": 4, "name": "Reinforcement Kit (x5)", "role": "defend"},
	{"id": "flash", "cat": 5, "name": "Flashbang", "price": 200},
	{"id": "smoke", "cat": 5, "name": "Smoke Grenade", "price": 300},
	{"id": "incendiary", "cat": 5, "name": "Incendiary", "price": 500},
	{"id": "frag", "cat": 5, "name": "Frag Grenade", "price": 300},
	{"id": "flashlight", "cat": 6, "name": "Weapon Flashlight", "price": 150},
	{"id": "laser", "cat": 6, "name": "Laser Sight", "price": 200},
	{"id": "nvg", "cat": 6, "name": "Night Vision", "price": 800},
	{"id": "silencer", "cat": 6, "name": "Silencer (all guns)", "price": 300},
	{"id": "zip_tie", "cat": 4, "name": "Zip Tie (one per purchase)", "price": 100},
]
## Attachment bits in Loadout.gadgets_owned. The silencer has no toggle: owned = fitted to every gun.
const GADGET_BITS := {"flashlight": 1, "laser": 2, "nvg": 4, "silencer": 8}

static func find(id: String) -> Dictionary:
	for it: Dictionary in ITEMS:
		if it.id == id:
			return it
	return {}

static func price(t: MatchTuning, id: String) -> int:
	match id:
		"ordinary": return t.price_ordinary
		"heavy": return t.price_heavy
		"kit": return t.price_reinforce
	var it := find(id)
	if it.get("weapon", false):
		return int(Weapons.DEFS[id].price)
	return int(it.get("price", 0))

static func limit(t: MatchTuning, id: String) -> int:
	if id in DROP_UTILITY:
		return UTILITY_LIMIT
	if id == "kit":
		return t.limit_reinforce * t.reinforce_per_kit if t.limit_reinforce > 0 else MAX_REINFORCE
	return int(find(id).get("limit", 1))

## Buyable ids for a role (excludes not-yet-implemented items).
static func buyable(attacker: bool) -> Array:
	var out := []
	for it: Dictionary in ITEMS:
		if it.get("soon", false):
			continue
		var role: String = it.get("role", "")
		if role == "" or (role == "attack") == attacker:
			out.append(it.id)
	return out

## How many of `id` the loadout holds (weapons/armor/helmet count as 0 or 1).
static func owned(lo: Loadout, id: String) -> int:
	if id in ["frag", "flash", "smoke", "incendiary"]:
		return int(lo.charges.get(Loadout.key_tool(id), 0))
	if GADGET_BITS.has(id):
		return int(bool(lo.gadgets_owned & int(GADGET_BITS[id])))
	match id:
		"ordinary": return int(lo.charges[Loadout.Tool.ORDINARY_CHARGE])
		"heavy": return int(lo.charges[Loadout.Tool.HEAVY_CHARGE])
		"kit": return int(lo.charges[Loadout.Tool.REINFORCE])
		"medkit": return int(lo.charges[Loadout.Tool.MEDKIT])
		"zip_tie": return lo.zip_ties
		"encrypt": return 0 # team item: MatchLoop checks the team's stock
		"vest": return 1 if lo.armor >= 100 else 0
		"armor_helmet": return int(lo.helmet and lo.armor >= 100)
		"defuse_kit": return int(lo.defuse_kit)
	return 1 if lo.primary == id or lo.secondary == id else 0

## Reinforcements per purchased kit (MatchTuning default; the shop uses the default tuning value).
static func kit_size() -> int:
	return MatchTuning.new().reinforce_per_kit


## Applies a purchase to the (host) loadout.
static func grant(lo: Loadout, id: String) -> void:
	if id in ["frag", "flash", "smoke", "incendiary"]:
		lo.charges[Loadout.key_tool(id)] += 1
		return
	if GADGET_BITS.has(id):
		lo.gadgets_owned |= int(GADGET_BITS[id])
		return
	match id:
		"ordinary": lo.charges[Loadout.Tool.ORDINARY_CHARGE] += 1
		"heavy": lo.charges[Loadout.Tool.HEAVY_CHARGE] += 1
		"kit": lo.charges[Loadout.Tool.REINFORCE] = mini(lo.charges[Loadout.Tool.REINFORCE] + kit_size(), MAX_REINFORCE)
		"medkit": lo.charges[Loadout.Tool.MEDKIT] += 1
		"zip_tie": lo.zip_ties += 1
		"encrypt": pass # MatchLoop sets the team flag
		"vest": lo.armor = 100
		"armor_helmet":
			lo.armor = 100
			lo.helmet = true
		"defuse_kit": lo.defuse_kit = true
		_:
			if Weapons.DEFS.has(id):
				if int(Weapons.DEFS[id].slot) == 0:
					lo.set_gear(id, lo.secondary)
				else:
					lo.set_gear(lo.primary, id)
