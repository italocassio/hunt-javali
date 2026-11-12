class_name Layers
extends RefCounted
## 3D collision bits. Names match project.godot [layer_names].

const TERRAIN: int = 1
const STATIC: int = 2
const PLAYER: int = 4
const BOAR_HITZONE: int = 8

const MASK_PLAYER_BODY: int = TERRAIN | STATIC
const MASK_WEAPON_RAY: int = TERRAIN | STATIC | BOAR_HITZONE
const MASK_LINE_OF_SIGHT: int = TERRAIN | STATIC
const MASK_GROUND: int = TERRAIN
