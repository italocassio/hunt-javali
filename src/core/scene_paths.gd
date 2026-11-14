class_name ScenePaths
extends RefCounted
## Scene paths and asset path conventions. Single source for every load().

const BOOT: String = "res://src/ui/boot/boot.tscn"
const MAIN_MENU: String = "res://src/ui/main_menu/main_menu.tscn"
const MAP_SELECT: String = "res://src/ui/map_select/map_select.tscn"
const PREPARATION: String = "res://src/ui/preparation/preparation.tscn"
const SHOP: String = "res://src/ui/shop/shop.tscn"
const RESULT: String = "res://src/ui/result/result.tscn"
const DONATE: String = "res://src/ui/donate/donate.tscn"
const SETTINGS: String = "res://src/ui/settings/settings.tscn"
const SETTINGS_PANEL: String = "res://src/ui/settings/settings_panel.tscn"
const HUNT: String = "res://src/hunt/hunt.tscn"
const PLAYER: String = "res://src/player/player.tscn"
const HUD: String = "res://src/hud/hud.tscn"
const BOAR: String = "res://src/boars/boar.tscn"
const DOG: String = "res://src/dogs/dog.tscn"
const LOBBY: String = "res://src/ui/lobby/lobby.tscn"
const REMOTE_HUNTER: String = "res://src/player/remote_hunter.tscn"

const BOAR_VISUAL: String = "res://assets/models/boar/boar_visual.tscn"
const DOG_VISUAL: String = "res://assets/models/dog/dog_visual.tscn"
const HUNTER_VISUAL: String = "res://assets/models/hunter/hunter_visual.tscn"
const FLORA_LIBRARY: String = "res://assets/models/flora/flora_library.gd"
const TERRAIN_MATERIAL: String = "res://assets/materials/terrain.tres"
const WATER_MATERIAL: String = "res://assets/materials/water.tres"
const UI_THEME: String = "res://assets/ui/theme.tres"
const SCOPE_SHADER: String = "res://assets/ui/scope_overlay.gdshader"


static func map_scene(map_id: StringName) -> String:
	return "res://src/world/maps/%s/%s_map.tscn" % [map_id, map_id]


static func weapon_view(weapon_id: StringName) -> String:
	return "res://assets/models/weapons/%s_view.tscn" % weapon_id


static func prop(prop_id: StringName) -> String:
	return "res://assets/models/props/%s.tscn" % prop_id


static func environment(map_id: StringName) -> String:
	return "res://assets/env/%s_env.tscn" % map_id


static func vfx(vfx_id: StringName) -> String:
	return "res://assets/vfx/%s.tscn" % vfx_id


static func icon(icon_id: StringName) -> String:
	return "res://assets/ui/icons/%s.svg" % icon_id
