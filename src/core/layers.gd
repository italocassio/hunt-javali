class_name Layers
extends RefCounted
## 3D collision bits. Names match project.godot [layer_names].

const TERRAIN: int = 1
const STATIC: int = 2
const PLAYER: int = 4
const BOAR_HITZONE: int = 8
const FENCE: int = 16   ## Horde level 2: invisible wall that confines the hunter to the farm; blocks the player body only

const MASK_PLAYER_BODY: int = TERRAIN | STATIC | FENCE
const MASK_WEAPON_RAY: int = TERRAIN | STATIC | BOAR_HITZONE
const MASK_LINE_OF_SIGHT: int = TERRAIN | STATIC
const MASK_GROUND: int = TERRAIN
