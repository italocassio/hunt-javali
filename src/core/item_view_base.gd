class_name ItemViewBase
extends Node3D
## First-person item in the hunter's hands: bandage, energy drink, scout drone, corn bait
## (docs/arquitetura.md §7.13, docs/plano_itens_animados.md).
##
## Child of the camera, under the WeaponHolder (so it inherits bob, sway and the aim offset).
## Camera space: eye at the origin, looking -Z. At rest the item sits off screen (below the bottom
## edge): the view is only seen while ItemHands plays a use, and the weapon view is hidden meanwhile.
##
## No Muzzle, no AdsAnchor: an item is never aimed and never fires.


func setup(_item_id: StringName) -> void:
	pass


## One whole use over `duration_s` seconds. The gesture must read in three beats: the item comes up
## into view, the effect beat lands at `effect_at` (0..1 of `duration_s`) — the bandage pulled tight,
## the last gulp, the drone leaving the hands, the corn leaving the hand — and the hands are back at
## rest (off screen) when the duration ends.
func play_use(_duration_s: float, _effect_at: float) -> void:
	pass


## The use was cut short (the hunter went down, died, or ItemBelt.cancel_use): back to the rest pose
## at once, no animation. Called right before the view is hidden.
func cancel_use() -> void:
	pass
