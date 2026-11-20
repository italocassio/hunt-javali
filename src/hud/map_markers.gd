class_name MapMarkers
extends RefCounted
## Single source of shape and colour of the markers on the compass and on the minimap (docs §8.4, table
## "Marcadores"). Both scripts draw through MapMarkers.draw, so a kind looks the same on both.
## &"ally" is not drawn here: the compass uses a diamond and the minimap an arrow, each in its own script.

const KIND_CROP: StringName = &"crop"
const KIND_BAIT: StringName = &"bait"
const KIND_REVEALED: StringName = &"revealed"
const KIND_BOAR: StringName = &"boar"
const KIND_DOG_TARGET: StringName = &"dog_target"
const KIND_DOG: StringName = &"dog"
const KIND_ALLY: StringName = &"ally"

const COLOR_CROP: Color = Color("#3FAF5A")
const COLOR_BAIT: Color = Color("#3CC7B4")
const COLOR_REVEALED: Color = Color("#FF8A65")
const COLOR_BOAR: Color = Color("#D9452B")
const COLOR_DOG: Color = Color("#F2C12E")

## Black outline around every filled shape.
const OUTLINE_PX: float = 1.5
## Ring (dog target): line width is a fraction of the radius and the outline is a little thinner than the line,
## which gives 2.5 + 2 x 2.0 px at radius 10 (compass) and 2.0 + 2 x 1.5 px at radius 8 (minimap).
const RING_WIDTH_FRAC: float = 0.25
const RING_OUTLINE_LESS_PX: float = 0.5
const RING_POINTS: int = 24
const HEXAGON_SIDES: int = 6
## Triangle (marked boar): apex above the centre, base below, both measured in half widths.
const TRIANGLE_TIP: float = 1.0
const TRIANGLE_BASE: float = 0.8

## Back to front, the same on the compass and on the minimap.
const DRAW_ORDER: Array[StringName] = [KIND_CROP, KIND_BAIT, KIND_REVEALED, KIND_BOAR, KIND_DOG_TARGET, KIND_DOG, KIND_ALLY]


## The colour of a kind (&"ally" has none of its own: its colour is the hunter slot colour).
static func color_of(kind: StringName) -> Color:
	match kind:
		KIND_CROP:
			return COLOR_CROP
		KIND_BAIT:
			return COLOR_BAIT
		KIND_REVEALED:
			return COLOR_REVEALED
		KIND_BOAR:
			return COLOR_BOAR
		_:
			return COLOR_DOG


## Draws the shape of `kind` centred on `at`, with a black outline. `half_px` is the half width (the radius for
## round shapes). `color.a` also scales the outline, so a faded marker fades as a whole.
static func draw(ci: CanvasItem, kind: StringName, at: Vector2, color: Color, half_px: float) -> void:
	var outline: Color = Color(0.0, 0.0, 0.0, color.a)
	match kind:
		KIND_CROP:
			var out_half: float = half_px + OUTLINE_PX
			ci.draw_rect(Rect2(at - Vector2.ONE * out_half, Vector2.ONE * out_half * 2.0), outline)
			ci.draw_rect(Rect2(at - Vector2.ONE * half_px, Vector2.ONE * half_px * 2.0), color)
		KIND_BAIT:
			var inner: PackedVector2Array = _hexagon(at, half_px)
			ci.draw_colored_polygon(_hexagon(at, half_px + OUTLINE_PX), outline)
			ci.draw_colored_polygon(inner, color)
		KIND_BOAR:
			var tri: PackedVector2Array = _triangle(at, half_px)
			ci.draw_colored_polygon(_triangle(at, half_px + OUTLINE_PX), outline)
			ci.draw_colored_polygon(tri, color)
		KIND_DOG_TARGET:
			var width: float = half_px * RING_WIDTH_FRAC
			ci.draw_arc(at, half_px, 0.0, TAU, RING_POINTS, outline, width + (width - RING_OUTLINE_LESS_PX) * 2.0)
			ci.draw_arc(at, half_px, 0.0, TAU, RING_POINTS, color, width)
		_:   # KIND_REVEALED and KIND_DOG: a dot
			ci.draw_circle(at, half_px + OUTLINE_PX, outline)
			ci.draw_circle(at, half_px, color)


## Regular hexagon with a vertex pointing up.
static func _hexagon(at: Vector2, radius: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in HEXAGON_SIDES:
		var a: float = -PI * 0.5 + TAU * float(i) / float(HEXAGON_SIDES)
		pts.append(at + Vector2(cos(a), sin(a)) * radius)
	return pts


## Triangle with the apex up; `half_px` is the half width of the base.
static func _triangle(at: Vector2, half_px: float) -> PackedVector2Array:
	return PackedVector2Array([at + Vector2(0.0, -half_px * TRIANGLE_TIP),
		at + Vector2(half_px, half_px * TRIANGLE_BASE), at + Vector2(-half_px, half_px * TRIANGLE_BASE)])
