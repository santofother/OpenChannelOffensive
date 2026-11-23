class_name MatchTuning
extends Resource
## Provisional S7 rules, all durations in seconds. No economy until S8.
@export var prep := 30.0
@export var live := 150.0
@export var plant := 5.0
@export var defuse := 7.0 ## baseline for the kit/no-kit multipliers
@export var defuse_without_kit := 2.0
@export var defuse_with_kit := 0.8
@export var fuse := 40.0
@export var outside_reveal := 5.0 ## seconds a defender may spend outside before attackers see them
@export var resolution := 6.0
@export var rounds := 12 ## first to floor(rounds / 2) + 1; even settings can need a deciding round
@export var swap_after := 6
@export var bomb_blast_radius := 10.0
@export var bomb_beep_range := 16.0
@export var interact_range := 1.8
@export var site_radius := 1.1
@export var sites: Array[Vector3] = [Vector3(6.8, 0.05, -4.5), Vector3(4.3, 0.05, -6.4)]
## Maps with room-sized sites provide a footprint and vertical bounds for each site.
@export_storage var site_areas: Array[Dictionary] = []

func site_at(pos: Vector3) -> int:
	for i in sites.size():
		if i >= site_areas.size():
			if pos.distance_to(sites[i]) <= site_radius:
				return i
			continue
		var room: Dictionary = site_areas[i]
		if pos.y >= room.bottom and pos.y < room.top and Geometry2D.is_point_in_polygon(
				Vector2(pos.x, pos.z), room.polygon):
			return i
	return -1

@export_group("Match points")
@export var points_per_damage := 1.0
@export var points_kill := 100
@export var points_assist := 50
@export var assist_min_damage := 20.0
@export var points_survived := 50
@export var points_reinforced := 25
@export var points_tactical := 35
@export var points_planted := 100
@export var points_defused := 150
@export_group("Economy (S8 placeholders, not playtest-tuned)")
@export var start_credits := 800
@export var credit_cap := 9000
@export var win_reward := 3000
@export var loss_base := 1400
@export var loss_bonus := 500 ## per prior consecutive loss
@export var loss_streak_max := 4
@export var plant_bonus := 300 ## attackers who planted, win or lose
@export var kill_reward := 300 ## per enemy eliminated
@export var damage_reward_per_hp := 2 ## per point of health removed from enemies
@export var reinforce_reward := 75 ## per panel reinforced
@export var survive_bonus := 200 ## alive when the round resolves
@export var price_ordinary := 200
@export var price_heavy := 500
@export var price_reinforce := 300 ## one kit
@export var limit_reinforce := 0 ## kits carried at once; 0 = no limit
@export var base_ordinary := 1 ## free attacker loadout besides the rifle
@export var base_reinforce := 1 ## free defender kits besides the rifle
@export var reinforce_per_kit := 5 ## reinforcements (panels) one kit holds
@export var reinforce_allowance := 0 ## panels one team may reinforce per round; 0 = no limit
