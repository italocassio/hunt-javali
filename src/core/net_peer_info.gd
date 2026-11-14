class_name NetPeerInfo
extends RefCounted

var slot: int = 0
var display_name: String = ""
var is_host: bool = false
var ready: bool = false
var loaded: bool = false
var weapon_id: StringName = &""     # weapon in slot 0 of the loadout (lobby display, first visual)
var dog_id: StringName = &""
var path: int = 0                   # Net.Path of the link (host: link to that peer; client: link to host)
