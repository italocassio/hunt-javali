extends Node
## Autoload "GameEvents": global signal bus. Declares signals only. See docs/arquitetura.md §5.

@warning_ignore_start("unused_signal")

# Hunt lifecycle
signal hunt_started(request: HuntRequest)
signal hunt_ended(result: HuntResult)
signal hunt_paused_changed(paused: bool)
signal hunt_abandon_requested()

# Player / weapons / items
signal shot_fired(weapon_id: StringName, origin: Vector3, direction: Vector3, noise_radius_m: float)
signal player_damaged(amount: float, source_position: Vector3, health_after: float)
signal player_healed(amount: float, health_after: float)
signal player_died()
signal item_used(item_id: StringName, position: Vector3)
signal thermal_vision_changed(active: bool)
signal dog_command_requested()

# Boars / world
signal boar_spawned(boar_id: int, type_id: StringName, weight_kg: float)
signal boar_hit(boar_id: int, zone: StringName, damage: float, hit_position: Vector3, shot_id: int)
signal boar_state_changed(boar_id: int, state: StringName)
signal boar_killed(kill: KillInfo)
signal boar_counts_changed(killed: int, total: int)
signal crop_health_changed(pct: float)
signal crop_under_attack(active: bool)
signal bait_placed(position: Vector3, duration_s: float)

# Dog
signal dog_state_changed(state: StringName)
signal dog_health_changed(pct: float)
signal dog_marked_boar(position: Vector3, duration_s: float)
signal dog_command_executed(command: StringName)

# HUD
signal hud_message_requested(text: String, duration_s: float)

# Meta-game
signal wallet_changed(money: int, gold: int)
signal inventory_changed()
signal loadout_changed()
signal progression_changed()
signal settings_changed(key: String, value: Variant)
signal touch_mode_changed(is_touch: bool)

@warning_ignore_restore("unused_signal")
