extends "res://tests/lib/test_case.gd"
## Compass, markers, minimap image and the data of the minimap (docs/arquitetura.md sections 8.4 and 9.1, contract 1.4,
## HF5): Compass.label_for / heading_deg_of / get_heading_text, MapMarkers (kinds, colours, DRAW_ORDER), the source and
## destination rectangles of Minimap, MinimapBaker.world_to_pixel and the fallbacks of the baker, the Hud marks (order,
## crop dropped inside the plot, horde without crops, texture handed to the Minimap) and game.minimap validation.
## The bake of the real map (orientation, determinism, budget) is the sandbox "minimap_bake" of tests/net_unit.gd.

const MAP_RECT: Rect2 = Rect2(-128.0, -128.0, 256.0, 256.0)
const CROP: Rect2 = Rect2(20.0, -70.0, 40.0, 30.0)
const CROP_CENTER: Vector3 = Vector3(40.0, 0.0, -55.0)
const BAIT_POS: Vector3 = Vector3(-30.0, 0.0, -40.0)
const MARKED_POS: Vector3 = Vector3(0.0, 0.0, -30.0)
const BOAR_A: Vector3 = Vector3(10.0, 0.0, -20.0)
const BOAR_B: Vector3 = Vector3(-5.0, 0.0, -45.0)
const DOG_POS: Vector3 = Vector3(-4.0, 0.0, -6.0)
const DOG_TARGET: Vector3 = Vector3(3.0, 0.0, -15.0)
const ALL_KINDS: Array[StringName] = [&"crop", &"bait", &"revealed", &"boar", &"dog_target", &"dog"]


## A world with exactly what the HUD reads for the markers; the real Player and Hud run on top of it.
class FakeWorld extends HuntWorld:
	var player: PlayerBase = null
	var horde: bool = false
	var crops: Array[Rect2] = []
	var texture: Texture2D = null
	var alive: Dictionary = {}                      # boar id -> Vector3
	var marked: PackedVector3Array = PackedVector3Array()
	var dog_on: bool = false
	var dog_pos: Vector3 = Vector3.INF
	var dog_state: StringName = &"follow"
	var dog_target: Vector3 = Vector3.INF

	func get_map_rect() -> Rect2:
		return Rect2(-128.0, -128.0, 256.0, 256.0)

	func get_mode() -> StringName:
		return Ids.MODE_HORDE if horde else Ids.MODE_CONTRACT

	func get_crop_rects() -> Array[Rect2]:
		return crops

	func get_minimap_texture() -> Texture2D:
		return texture

	func get_alive_boar_ids() -> PackedInt32Array:
		return PackedInt32Array(alive.keys())

	func get_boar_position(boar_id: int) -> Vector3:
		return alive.get(boar_id, Vector3.INF)

	func get_marked_boar_positions() -> PackedVector3Array:
		return marked

	func get_nearest_boar_position(from: Vector3) -> Vector3:
		var best: Vector3 = Vector3.INF
		var best_d: float = INF
		for id: Variant in alive:
			var d: float = from.distance_squared_to(alive[id])
			if d < best_d:
				best_d = d
				best = alive[id]
		return best

	func has_dog() -> bool:
		return dog_on

	func get_dog_position() -> Vector3:
		return dog_pos

	func get_dog_state() -> StringName:
		return dog_state

	func get_dog_target_position() -> Vector3:
		return dog_target

	func get_player() -> PlayerBase:
		return player


# --------------------------------------------------------------------------------------------
# Compass: label_for / heading_deg_of / get_heading_text
# --------------------------------------------------------------------------------------------

func test_label_for_the_multiples_of_45_are_portuguese_names() -> void:
	var want: Dictionary = {0: "N", 45: "NE", 90: "L", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}
	for deg: int in want:
		eq(Compass.label_for(deg), want[deg], "label_for(%d)" % deg)


func test_label_for_other_multiples_of_15_are_the_number() -> void:
	for deg: int in [15, 30, 60, 75, 105, 120, 150, 165, 195, 210, 240, 255, 285, 300, 330, 345]:
		eq(Compass.label_for(deg), str(deg), "label_for(%d)" % deg)


func test_label_for_everything_else_is_empty() -> void:
	for deg: int in [1, 5, 7, 10, 14, 16, 44, 46, 89, 91, 359]:
		eq(Compass.label_for(deg), "", "label_for(%d)" % deg)


func test_label_for_wraps_negative_and_large_degrees() -> void:
	eq(Compass.label_for(360), "N", "360 = N")
	eq(Compass.label_for(720), "N", "720 = N")
	eq(Compass.label_for(-90), "O", "-90 = O")
	eq(Compass.label_for(-45), "NO", "-45 = NO")
	eq(Compass.label_for(-15), "345", "-15 = 345")
	eq(Compass.label_for(495), "SE", "495 = 135 = SE")


func test_label_for_never_says_english_cardinals() -> void:
	var seen: PackedStringArray = PackedStringArray()
	for deg: int in range(-360, 721):
		var text: String = Compass.label_for(deg)
		if text != "" and not text.is_valid_int() and not seen.has(text):
			seen.append(text)
	seen.sort()
	eq(seen, _sorted(["N", "NE", "L", "SE", "S", "SO", "O", "NO"]), "so os oito rotulos em portugues")
	for banned: String in ["E", "W", "SW", "NW"]:
		ok(not seen.has(banned), "'%s' nao aparece" % banned)


func _sorted(items: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(items)
	out.sort()
	return out


func test_heading_deg_of_the_yaw_examples() -> void:
	eq(Compass.heading_deg_of(0.0), 0, "yaw 0 olha o norte")
	eq(Compass.heading_deg_of(-PI * 0.5), 90, "yaw -PI/2 = leste (90)")
	eq(Compass.heading_deg_of(PI * 0.5), 270, "yaw PI/2 = oeste (270)")
	eq(Compass.heading_deg_of(PI), 180, "yaw PI = sul")
	eq(Compass.heading_deg_of(-PI), 180, "yaw -PI = sul")
	eq(Compass.heading_deg_of(-2.0 * PI), 0, "uma volta completa volta a 0")
	eq(Compass.heading_deg_of(-3.0 * PI * 0.5), 270, "yaw -3PI/2 = 270")
	eq(Compass.heading_deg_of(deg_to_rad(-135.0)), 135, "135")


func test_heading_deg_of_is_never_360_and_always_in_range() -> void:
	eq(Compass.heading_deg_of(deg_to_rad(-359.6)), 0, "359,6 arredonda para 360 e vira 0")
	eq(Compass.heading_deg_of(deg_to_rad(-359.4)), 359, "359,4 arredonda para 359")
	eq(Compass.heading_deg_of(deg_to_rad(0.3)), 0, "yaw ligeiramente positivo: -0,3 grau vira 0")
	eq(Compass.heading_deg_of(deg_to_rad(0.6)), 359, "yaw +0,6 grau = 359,4 = 359")
	var worst: int = -1
	var best: int = 1000
	var yaw: float = -20.0
	while yaw <= 20.0:
		var h: int = Compass.heading_deg_of(yaw)
		worst = maxi(worst, h)
		best = mini(best, h)
		yaw += 0.0173
	ok(best >= 0 and worst <= 359, "varredura de -20 a 20 rad fica em 0..359 (min %d, max %d)" % [best, worst])


func test_get_heading_text_shows_the_degree() -> void:
	var compass: Compass = Compass.new()
	track(compass)
	var cases: Dictionary = {135.0: "135°", 0.0: "0°", 90.0: "90°", 270.0: "270°", 45.0: "45°", 359.0: "359°"}
	for deg: float in cases:
		compass.update_state(Vector3.ZERO, deg_to_rad(-deg), [] as Array[Dictionary])
		eq(compass.get_heading_text(), cases[deg], "texto para %s graus" % deg)
	compass.update_state(Vector3.ZERO, deg_to_rad(-135.0), [] as Array[Dictionary])
	eq(compass.get_heading_deg(), 135, "get_heading_deg")
	eq(Compass.label_for(compass.get_heading_deg()), "SE", "o rotulo sob o entalhe e SE")
	compass.update_state(Vector3.ZERO, 0.0, [] as Array[Dictionary])
	eq(compass.get_heading_text(), "0°", "yaw 0")
	eq(Compass.label_for(compass.get_heading_deg()), "N", "sob o entalhe: N")


func test_compass_number_matches_the_label_under_the_notch() -> void:
	var compass: Compass = Compass.new()
	track(compass)
	for deg: int in range(0, 360, 15):
		compass.update_state(Vector3.ZERO, deg_to_rad(-float(deg)), [] as Array[Dictionary])
		eq(compass.get_heading_deg(), deg, "caixa mostra %d" % deg)
		var label: String = Compass.label_for(deg)
		ok(label != "", "sob o entalhe ha rotulo em %d" % deg)
		if deg % 45 != 0:
			eq(label, str(deg), "rotulo numerico %d" % deg)


func test_compass_has_the_taller_minimum_size() -> void:
	var compass: Compass = Compass.new()
	track(compass)
	eq(compass.custom_minimum_size, Vector2(480.0, Compass.BAND_H_PX + Compass.READOUT_H_PX + 2.0), "tamanho minimo")
	eq(compass.custom_minimum_size, Vector2(480.0, 54.0), "480 x 54")
	eq(compass.mouse_filter, Control.MOUSE_FILTER_IGNORE, "nao captura toque")


## The strip draws labels, ticks, every kind of marker and the readout at several widths and headings without error.
func test_compass_draws_every_kind_at_many_headings_and_widths() -> void:
	var compass: Compass = Compass.new()
	track(compass)
	compass.custom_minimum_size = Vector2.ZERO   # so the narrow widths below are real
	var marks: Array[Dictionary] = []
	for kind: StringName in ALL_KINDS:
		marks.append({"pos": Vector3(0.0, 0.0, -30.0), "kind": kind})
		marks.append({"pos": Vector3(0.0, 0.0, 30.0), "kind": kind})   # behind: pinned to the edge
	marks.append({"pos": Vector3(20.0, 0.0, 0.0), "kind": &"ally", "color": Color.RED, "down": false})
	marks.append({"pos": Vector3(-20.0, 0.0, 0.0), "kind": &"ally", "color": Color.BLUE, "down": true})
	for width: float in [480.0, 320.0, 120.0, 40.0, 0.0]:
		compass.size = Vector2(width, 54.0)
		for deg: float in [0.0, 7.0, 44.9, 135.0, 359.6, 720.0, -90.0]:
			compass.update_state(Vector3(3.0, 0.0, 4.0), deg_to_rad(-deg), marks)
			await frames(1)
	ok(true, "desenhou sem erro em larguras de 0 a 480 px")


# --------------------------------------------------------------------------------------------
# MapMarkers
# --------------------------------------------------------------------------------------------

func test_draw_order_is_exact() -> void:
	eq(MapMarkers.DRAW_ORDER, [&"crop", &"bait", &"revealed", &"boar", &"dog_target", &"dog", &"ally"] as Array[StringName],
		"DRAW_ORDER de tras para a frente")


func test_kind_constants_are_the_table_ids() -> void:
	eq(MapMarkers.KIND_CROP, &"crop", "KIND_CROP")
	eq(MapMarkers.KIND_BAIT, &"bait", "KIND_BAIT")
	eq(MapMarkers.KIND_REVEALED, &"revealed", "KIND_REVEALED")
	eq(MapMarkers.KIND_BOAR, &"boar", "KIND_BOAR")
	eq(MapMarkers.KIND_DOG_TARGET, &"dog_target", "KIND_DOG_TARGET")
	eq(MapMarkers.KIND_DOG, &"dog", "KIND_DOG")
	eq(MapMarkers.KIND_ALLY, &"ally", "KIND_ALLY")
	eq(MapMarkers.OUTLINE_PX, 1.5, "OUTLINE_PX")


func test_color_of_matches_the_table() -> void:
	ok(MapMarkers.color_of(&"crop").is_equal_approx(Color("#3FAF5A")), "crop #3FAF5A")
	ok(MapMarkers.color_of(&"bait").is_equal_approx(Color("#3CC7B4")), "ceva #3CC7B4")
	ok(MapMarkers.color_of(&"revealed").is_equal_approx(Color("#FF8A65")), "revelado #FF8A65")
	ok(MapMarkers.color_of(&"boar").is_equal_approx(Color("#D9452B")), "javali marcado #D9452B")
	ok(MapMarkers.color_of(&"dog").is_equal_approx(Color("#F2C12E")), "cao #F2C12E")
	ok(MapMarkers.color_of(&"dog_target").is_equal_approx(Color("#F2C12E")), "alvo do cao tem a cor do cao")


func test_the_marker_colours_stay_apart() -> void:
	# crop, bait, revealed and boar must be told apart at a glance; the dog and its target share one colour on purpose.
	var kinds: Array[StringName] = [&"crop", &"bait", &"revealed", &"boar", &"dog"]
	for i: int in kinds.size():
		for j: int in range(i + 1, kinds.size()):
			var a: Color = MapMarkers.color_of(kinds[i])
			var b: Color = MapMarkers.color_of(kinds[j])
			var dist: float = Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			ok(dist > 0.25, "%s e %s distintos (distancia %.2f)" % [kinds[i], kinds[j], dist])


func test_color_of_unknown_kind_does_not_crash() -> void:
	var c: Color = MapMarkers.color_of(&"nao_existe")
	ok(c.a > 0.0, "cor opaca devolvida para tipo desconhecido")


func test_draw_works_for_every_kind_and_for_a_faded_colour() -> void:
	var canvas: Control = Control.new()
	track(canvas)
	canvas.size = Vector2(100.0, 100.0)
	canvas.draw.connect(func() -> void:
		for kind: StringName in ALL_KINDS:
			MapMarkers.draw(canvas, kind, Vector2(50.0, 50.0), MapMarkers.color_of(kind), 6.0)
			var faded: Color = MapMarkers.color_of(kind)
			faded.a = 0.6
			MapMarkers.draw(canvas, kind, Vector2(20.0, 20.0), faded, 7.0)
		MapMarkers.draw(canvas, &"nao_existe", Vector2(70.0, 70.0), Color.WHITE, 4.5))
	canvas.queue_redraw()
	await frames(2)
	ok(true, "desenhou os seis tipos, esmaecidos e um desconhecido, sem erro")


# --------------------------------------------------------------------------------------------
# Minimap: source and destination rectangles (docs 8.4, exact examples)
# --------------------------------------------------------------------------------------------

func _texture(px: int) -> ImageTexture:
	var img: Image = Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color("#8C8C50"))
	return ImageTexture.create_from_image(img)


func _minimap(tex_px: int = 256, side: float = 180.0) -> Minimap:
	var mm: Minimap = Minimap.new()
	track(mm)
	mm.custom_minimum_size = Vector2.ZERO   # a Control cannot be resized below its minimum size
	mm.size = Vector2(side, side)
	mm.map_rect = MAP_RECT
	if tex_px > 0:
		mm.map_texture = _texture(tex_px)
	return mm


func test_minimap_rects_example_at_the_center() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_src_rect(), Rect2(38.0, 38.0, 180.0, 180.0), "src no centro")
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 180.0, 180.0), "dst no centro")


func test_minimap_rects_example_near_the_west_edge() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3(-118.0, 0.0, 0.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(0.0, 38.0, 100.0, 180.0), "src junto a borda oeste")
	eq(mm.get_map_dst_rect(), Rect2(80.0, 0.0, 100.0, 180.0), "dst junto a borda oeste")


func test_minimap_rects_at_the_other_edges_and_the_corner() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3(118.0, 0.0, 0.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(156.0, 38.0, 100.0, 180.0), "src leste")
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 100.0, 180.0), "dst leste")
	mm.update_player(Vector3(0.0, 0.0, -118.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(38.0, 0.0, 180.0, 100.0), "src norte")
	eq(mm.get_map_dst_rect(), Rect2(0.0, 80.0, 180.0, 100.0), "dst norte")
	mm.update_player(Vector3(118.0, 0.0, 118.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(156.0, 156.0, 100.0, 100.0), "src canto sudeste")
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 100.0, 100.0), "dst canto sudeste")


func test_minimap_rects_do_not_depend_on_the_yaw() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3(-118.0, 0.0, 0.0), 1.234)
	eq(mm.get_map_src_rect(), Rect2(0.0, 38.0, 100.0, 180.0), "src com yaw")
	eq(mm.get_map_dst_rect(), Rect2(80.0, 0.0, 100.0, 180.0), "dst com yaw (norte sempre para cima)")


func test_minimap_rects_scale_with_the_texture_resolution() -> void:
	var mm: Minimap = _minimap(512)
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_src_rect(), Rect2(76.0, 76.0, 360.0, 360.0), "textura 512 px: texels dobrados")
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 180.0, 180.0), "o destino nao muda")
	var small: Minimap = _minimap(128)
	small.update_player(Vector3.ZERO, 0.0)
	eq(small.get_map_src_rect(), Rect2(19.0, 19.0, 90.0, 90.0), "textura 128 px: metade dos texels")


func test_minimap_rects_with_a_non_square_control() -> void:
	var mm: Minimap = _minimap()
	mm.size = Vector2(200.0, 120.0)
	mm.update_player(Vector3.ZERO, 0.0)
	# scale = min(200, 120) / 2 / 90 = 2/3 px per m; the view is 300 x 180 m, the map 256 m wide
	var dst: Rect2 = mm.get_map_dst_rect()
	var src: Rect2 = mm.get_map_src_rect()
	near(dst.position.x, 100.0 - 128.0 * 2.0 / 3.0, 0.001, "dst x")
	near(dst.position.y, 0.0, 0.001, "dst y")
	near(dst.size.x, 256.0 * 2.0 / 3.0, 0.001, "dst largura")
	near(dst.size.y, 120.0, 0.001, "dst altura")
	eq(src, Rect2(0.0, 38.0, 256.0, 180.0), "src: o mapa todo na largura, 180 m na altura")


func test_minimap_origin_outside_the_map_gives_empty_rects() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3(1000.0, 0.0, 0.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(), "src fora do mapa")
	eq(mm.get_map_dst_rect(), Rect2(), "dst fora do mapa")
	mm.update_player(Vector3(0.0, 0.0, -1000.0), 0.0)
	eq(mm.get_map_src_rect(), Rect2(), "src fora do mapa (norte)")
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 180.0, 180.0), "voltou ao mapa: recalcula")


func test_minimap_view_that_only_touches_the_map_edge_has_no_rect() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3(-218.0, 0.0, 0.0), 0.0)   # the view ends exactly at x = -128, no area in common
	eq(mm.get_map_src_rect(), Rect2(), "src sem area")
	eq(mm.get_map_dst_rect(), Rect2(), "dst sem area")
	mm.update_player(Vector3(-217.0, 0.0, 0.0), 0.0)   # one metre of overlap
	eq(mm.get_map_src_rect(), Rect2(0.0, 38.0, 1.0, 180.0), "um metro de sobreposicao: src")
	eq(mm.get_map_dst_rect(), Rect2(179.0, 0.0, 1.0, 180.0), "um metro de sobreposicao: dst")


func test_minimap_without_texture_has_empty_rects() -> void:
	var mm: Minimap = _minimap(0)
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_src_rect(), Rect2(), "src sem textura")
	eq(mm.get_map_dst_rect(), Rect2(), "dst sem textura")
	var with_tex: Minimap = _minimap()
	with_tex.update_player(Vector3.ZERO, 0.0)
	with_tex.map_texture = null
	eq(with_tex.get_map_src_rect(), Rect2(), "textura retirada: src vazio na hora")
	eq(with_tex.get_map_dst_rect(), Rect2(), "textura retirada: dst vazio na hora")


func test_minimap_setters_recompute_without_a_new_update() -> void:
	var mm: Minimap = _minimap(0)
	mm.update_player(Vector3.ZERO, 0.0)
	mm.map_texture = _texture(256)
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 180.0, 180.0), "colocar a textura recalcula")
	mm.map_rect = Rect2(-64.0, -64.0, 128.0, 128.0)   # a smaller map: the 256 px texture now covers 128 m (k = 2)
	eq(mm.get_map_src_rect(), Rect2(0.0, 0.0, 256.0, 256.0), "map_rect menor: src e a textura toda")
	eq(mm.get_map_dst_rect(), Rect2(26.0, 26.0, 128.0, 128.0), "map_rect menor: dst centralizado (2 px por m)")
	mm.map_rect = MAP_RECT
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 180.0, 180.0), "map_rect de volta")


func test_minimap_resize_recomputes() -> void:
	var mm: Minimap = _minimap()
	mm.update_player(Vector3.ZERO, 0.0)
	mm.size = Vector2(90.0, 90.0)
	eq(mm.get_map_dst_rect(), Rect2(0.0, 0.0, 90.0, 90.0), "controle de 90 px: o mesmo recorte em escala menor")
	eq(mm.get_map_src_rect(), Rect2(38.0, 38.0, 180.0, 180.0), "controle de 90 px: o mesmo src")


func test_minimap_before_layout_has_no_rects_and_does_not_divide_by_zero() -> void:
	var mm: Minimap = Minimap.new()
	track(mm)
	mm.custom_minimum_size = Vector2.ZERO
	mm.size = Vector2.ZERO
	mm.map_texture = _texture(256)
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_src_rect(), Rect2(), "tamanho 0: src vazio")
	eq(mm.get_map_dst_rect(), Rect2(), "tamanho 0: dst vazio")
	mm.size = Vector2(180.0, 0.0)
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_dst_rect(), Rect2(), "altura 0: dst vazio")
	await frames(2)
	ok(true, "desenhou com o controle sem tamanho")


func test_minimap_degenerate_map_rect_does_not_crash() -> void:
	var mm: Minimap = _minimap()
	mm.map_rect = Rect2(0.0, 0.0, 0.0, 0.0)
	mm.update_player(Vector3.ZERO, 0.0)
	eq(mm.get_map_dst_rect(), Rect2(), "mapa sem area: dst vazio")
	await frames(2)
	ok(true, "desenhou com map_rect sem area")


func test_minimap_uses_linear_filtering_and_ignores_the_mouse() -> void:
	var mm: Minimap = _minimap()
	eq(mm.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR, "filtro linear")
	eq(mm.mouse_filter, Control.MOUSE_FILTER_IGNORE, "nao captura toque")
	ok(mm.clip_contents, "recorta o que passa da moldura")


func test_minimap_draws_with_texture_and_every_marker() -> void:
	var mm: Minimap = _minimap()
	mm.crop_rects = [CROP, Rect2(-100.0, 60.0, 30.0, 30.0)] as Array[Rect2]
	mm.dog_position = DOG_POS
	mm.dog_target = DOG_TARGET
	mm.marked = PackedVector3Array([MARKED_POS, Vector3(900.0, 0.0, 900.0)])
	mm.revealed = PackedVector3Array([BOAR_A, BOAR_B])
	mm.baits = PackedVector3Array([BAIT_POS])
	mm.update_player(Vector3.ZERO, 0.7)
	await frames(2)
	mm.update_player(Vector3(-118.0, 0.0, 118.0), 0.0)   # a corner: part of the view is outside the map
	await frames(2)
	mm.update_player(Vector3(5000.0, 0.0, 0.0), 0.0)   # far away: nothing of the image, markers on the frame
	await frames(2)
	ok(true, "desenhou com textura em tres posicoes sem erro")


# --------------------------------------------------------------------------------------------
# MinimapBaker: world_to_pixel and fallbacks
# --------------------------------------------------------------------------------------------

func test_world_to_pixel_corners_and_center() -> void:
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -128.0, -128.0), Vector2i(0, 0), "canto noroeste (x min, z min)")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 128.0, -128.0), Vector2i(255, 0), "canto nordeste")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -128.0, 128.0), Vector2i(0, 255), "canto sudoeste")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 128.0, 128.0), Vector2i(255, 255), "canto sudeste (preso: 256 -> 255)")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 0.0, 0.0), Vector2i(128, 128), "centro")


func test_world_to_pixel_orientation_east_right_south_down() -> void:
	var a: Vector2i = MinimapBaker.world_to_pixel(MAP_RECT, 256, -70.0, -55.0)   # the pond, north-west
	var b: Vector2i = MinimapBaker.world_to_pixel(MAP_RECT, 256, 70.0, 55.0)
	ok(a.x < b.x, "leste fica a direita (coluna maior)")
	ok(a.y < b.y, "sul fica embaixo (linha maior)")
	eq(a, Vector2i(58, 73), "acude em (58, 73)")
	eq(b, Vector2i(198, 183), "ponto espelhado em (198, 183)")


func test_world_to_pixel_pixel_boundaries() -> void:
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -127.001, 0.0).x, 0, "dentro do primeiro pixel")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -127.0, 0.0).x, 1, "no limite do segundo pixel")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -0.001, 0.0).x, 127, "logo antes do centro")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 0.0, -0.001).y, 127, "logo antes do centro (z)")


func test_world_to_pixel_clamps_outside_the_map() -> void:
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -500.0, -500.0), Vector2i(0, 0), "alem do noroeste")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 500.0, 500.0), Vector2i(255, 255), "alem do sudeste")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, -500.0, 500.0), Vector2i(0, 255), "alem do sudoeste")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 256, 0.0, -500.0), Vector2i(128, 0), "so o z fora")


func test_world_to_pixel_other_rects_and_resolutions() -> void:
	var rect: Rect2 = Rect2(100.0, 200.0, 64.0, 64.0)
	eq(MinimapBaker.world_to_pixel(rect, 64, 100.0, 200.0), Vector2i(0, 0), "retangulo deslocado: origem")
	eq(MinimapBaker.world_to_pixel(rect, 64, 132.0, 232.0), Vector2i(32, 32), "retangulo deslocado: centro")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 128, 0.0, 0.0), Vector2i(64, 64), "128 px: centro")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 512, 0.0, 0.0), Vector2i(256, 256), "512 px: centro")
	eq(MinimapBaker.world_to_pixel(Rect2(-100.0, -50.0, 200.0, 100.0), 100, 0.0, 0.0), Vector2i(50, 50), "mapa retangular")
	eq(MinimapBaker.world_to_pixel(MAP_RECT, 1, 50.0, 50.0), Vector2i(0, 0), "imagem de 1 px")


func test_baker_returns_null_without_a_map_or_a_heightmap() -> void:
	eq(MinimapBaker.bake(null, {}), null, "mapa nulo")
	var map: MapRoot = MapRoot.new()
	track(map)
	eq(MinimapBaker.bake(map, {}), null, "mapa sem heightmap")
	map.build_minimap({})
	eq(map.get_minimap_image(), null, "build_minimap sem heightmap: sem imagem")
	eq(map.get_minimap_texture(), null, "build_minimap sem heightmap: sem textura")


func test_baker_defaults_equal_the_data() -> void:
	var cfg: Dictionary = Data.get_game()["minimap"]
	eq(MinimapBaker.DEFAULT_IMAGE_PX, int(cfg["image_px"]), "image_px")
	eq(MinimapBaker.DEFAULT_GRID_STRIDE, int(cfg["grid_stride"]), "grid_stride")
	eq(MinimapBaker.DEFAULT_CROP_ROW_PX, int(cfg["crop_row_px"]), "crop_row_px")
	var hs: Dictionary = cfg["hillshade"]
	near(MinimapBaker.DEFAULT_AZIMUTH_DEG, float(hs["azimuth_deg"]), 0.0001, "azimuth")
	near(MinimapBaker.DEFAULT_ALTITUDE_DEG, float(hs["altitude_deg"]), 0.0001, "altitude")
	near(MinimapBaker.DEFAULT_HILL_STRENGTH, float(hs["strength"]), 0.0001, "strength")
	near(MinimapBaker.DEFAULT_HILL_MIN, float(hs["min"]), 0.0001, "min")
	near(MinimapBaker.DEFAULT_HILL_MAX, float(hs["max"]), 0.0001, "max")
	near(MinimapBaker.DEFAULT_TINT_LOW, float(cfg["height_tint"]["low"]), 0.0001, "tint low")
	near(MinimapBaker.DEFAULT_TINT_HIGH, float(cfg["height_tint"]["high"]), 0.0001, "tint high")
	eq(MinimapBaker.DEFAULT_COLORS, cfg["colors"], "cores")
	eq(MinimapBaker.DEFAULT_PROP_COLORS, cfg["prop_colors"], "cores das construcoes")
	eq(MinimapBaker.DEFAULT_CANOPY, cfg["canopy"], "copas")


# --------------------------------------------------------------------------------------------
# Hud: marks (docs 8.4), the minimap texture and the crops, with a real Player and a fake world
# --------------------------------------------------------------------------------------------

func _spawn(world: FakeWorld, dog_id: StringName = &"foxhound", mode: StringName = Ids.MODE_CONTRACT) -> Hud:
	InputSetup.set_touch_override("off")
	fresh_profile()
	track(world)
	var player: Player = (load(ScenePaths.PLAYER) as PackedScene).instantiate() as Player
	world.player = player
	world.add_child(player)
	player.global_position = Vector3.ZERO
	var req: HuntRequest = HuntRequest.make_debug(&"mato_grosso", 0, mode)
	req.weapon_ids = [Ids.W_CARBINE_22] as Array[StringName]
	req.item_ids = [Ids.I_MEDKIT] as Array[StringName]
	req.item_counts = {Ids.I_MEDKIT: 1}
	if dog_id != &"":
		req.dog_id = dog_id
	player.setup(req, world)
	for child: Node in player.get_children():
		if child is Hud:
			return child as Hud
	fail("o Player nao criou o Hud")
	return null


func _world_with_everything() -> FakeWorld:
	var world: FakeWorld = FakeWorld.new()
	world.crops = [CROP] as Array[Rect2]
	world.texture = _texture(256)
	world.alive = {1: BOAR_A, 2: BOAR_B}
	world.marked = PackedVector3Array([MARKED_POS])
	world.dog_on = true
	world.dog_pos = DOG_POS
	world.dog_state = &"seek"
	world.dog_target = DOG_TARGET
	return world


func _kinds(hud: Hud) -> Array[StringName]:
	var out: Array[StringName] = []
	for m: Dictionary in hud._marks:
		out.append(m["kind"])
	return out


func test_hud_marks_come_in_the_draw_order() -> void:
	var world: FakeWorld = _world_with_everything()
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	GameEvents.bait_placed.emit(BAIT_POS, 600.0)
	GameEvents.item_used.emit(Ids.I_SCOUT_DRONE, Vector3.ZERO)
	hud._poll_world()
	var kinds: Array[StringName] = _kinds(hud)
	# crop, bait, two revealed, the marked boar, the dog target and the dog
	eq(kinds, [&"crop", &"bait", &"revealed", &"revealed", &"boar", &"dog_target", &"dog"] as Array[StringName], "ordem dos marcadores")
	var order: Array[StringName] = MapMarkers.DRAW_ORDER
	var last: int = -1
	for kind: StringName in kinds:
		var at: int = order.find(kind)
		ok(at >= last, "%s nao volta atras na DRAW_ORDER" % kind)
		last = at
	eq(hud._marks[0]["pos"], CROP_CENTER, "o talhao marca o centro")
	eq(hud._marks[1]["pos"], BAIT_POS, "a ceva marca a posicao dela")
	eq(hud._marks[4]["pos"], MARKED_POS, "o javali marcado")
	eq(hud._marks[5]["pos"], DOG_TARGET, "o alvo do cao")
	eq(hud._marks[6]["pos"], DOG_POS, "o cao")


func test_hud_minimap_gets_the_world_texture_and_the_crops() -> void:
	var world: FakeWorld = _world_with_everything()
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	ok(hud._minimap.map_texture == world.texture, "Minimap.map_texture e a textura do mundo")
	eq(hud._minimap.map_rect, MAP_RECT, "map_rect do mundo")
	eq(hud._minimap.crop_rects, [CROP] as Array[Rect2], "crop_rects do mundo")
	eq(hud._crop_centers.size(), 1, "um centro por talhao")
	eq(hud._crop_centers[0], CROP_CENTER, "centro do talhao com y = 0")


func test_hud_without_a_world_texture_keeps_the_plain_background() -> void:
	var world: FakeWorld = _world_with_everything()
	world.texture = null
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	ok(hud._minimap.map_texture == null, "sem textura no mundo, o minimapa fica sem textura")
	hud._minimap.update_player(Vector3.ZERO, 0.0)
	eq(hud._minimap.get_map_dst_rect(), Rect2(), "retangulos vazios")
	await frames(2)
	ok(true, "o minimapa desenha o fundo liso sem erro")


func test_hud_crop_mark_disappears_inside_the_plot() -> void:
	var world: FakeWorld = _world_with_everything()
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	hud._poll_world()
	ok(_kinds(hud).has(&"crop"), "fora do talhao: marca de talhao")
	world.player.global_position = CROP_CENTER
	hud._poll_world()
	ok(not _kinds(hud).has(&"crop"), "dentro do talhao: a marca some")
	world.player.global_position = Vector3(CROP.position.x + 0.1, 0.0, CROP.position.y + 0.1)
	hud._poll_world()
	ok(not _kinds(hud).has(&"crop"), "logo dentro da borda: sem marca")
	world.player.global_position = Vector3(CROP.end.x + 0.5, 0.0, CROP_CENTER.z)
	hud._poll_world()
	ok(_kinds(hud).has(&"crop"), "um passo fora: a marca volta")


func test_hud_two_crops_only_the_one_the_hunter_stands_in_is_dropped() -> void:
	var world: FakeWorld = _world_with_everything()
	var second: Rect2 = Rect2(-60.0, 40.0, 30.0, 30.0)
	world.crops = [CROP, second] as Array[Rect2]
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	hud._poll_world()
	var crops: Array[Dictionary] = []
	for m: Dictionary in hud._marks:
		if m["kind"] == &"crop":
			crops.append(m)
	eq(crops.size(), 2, "dois talhoes, duas marcas")
	world.player.global_position = Vector3(-45.0, 0.0, 55.0)   # inside the second
	hud._poll_world()
	crops.clear()
	for m: Dictionary in hud._marks:
		if m["kind"] == &"crop":
			crops.append(m)
	eq(crops.size(), 1, "dentro do segundo: sobra uma marca")
	if crops.size() == 1:
		eq(crops[0]["pos"], CROP_CENTER, "a que sobra e a do primeiro talhao")


func test_hud_in_the_horde_has_no_crop_marks_and_no_contour() -> void:
	var world: FakeWorld = _world_with_everything()
	world.horde = true
	var hud: Hud = _spawn(world, &"foxhound", Ids.MODE_HORDE)
	if hud == null:
		return
	GameEvents.bait_placed.emit(BAIT_POS, 600.0)
	hud._poll_world()
	ok(not _kinds(hud).has(&"crop"), "horda: nenhuma marca de talhao")
	ok(_kinds(hud).has(&"bait"), "horda: a ceva aparece")
	eq(hud._minimap.crop_rects.size(), 0, "horda: o minimapa nao tem contorno de talhao")
	ok(hud._minimap.map_texture == world.texture, "horda: a imagem do mapa e a mesma")


func test_hud_follow_state_has_no_dog_target_ring() -> void:
	var world: FakeWorld = _world_with_everything()
	world.dog_state = &"follow"
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	hud._poll_world()
	var kinds: Array[StringName] = _kinds(hud)
	ok(not kinds.has(&"dog_target"), "o cao seguindo nao tem alvo")
	ok(kinds.has(&"dog"), "o cao aparece")
	eq(hud._minimap.dog_target, Vector3.INF, "minimapa sem anel")


func test_hud_reveal_marks_only_while_the_drone_lasts() -> void:
	var world: FakeWorld = _world_with_everything()
	world.marked = PackedVector3Array()
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	hud._poll_world()
	ok(not _kinds(hud).has(&"revealed"), "sem drone: nenhum revelado")
	GameEvents.item_used.emit(Ids.I_SCOUT_DRONE, Vector3.ZERO)
	hud._poll_world()
	var revealed: int = _kinds(hud).count(&"revealed")
	eq(revealed, 2, "drone usado: os dois javalis vivos")
	eq(hud._minimap.revealed.size(), 2, "minimapa recebe os dois")
	world.alive.erase(1)
	hud._poll_world()
	eq(_kinds(hud).count(&"revealed"), 1, "javali abatido sai da lista")
	hud._reveal_left = 0.0
	hud._poll_world()
	eq(_kinds(hud).count(&"revealed"), 0, "acabou o efeito do drone")
	eq(hud._minimap.revealed.size(), 0, "minimapa sem revelados")
	world.alive[3] = Vector3.INF   # a boar whose position is unknown must not be drawn
	hud._reveal_left = 5.0
	hud._poll_world()
	eq(_kinds(hud).count(&"revealed"), 1, "posicao infinita e ignorada")


func test_hud_bait_expires_and_a_marked_boar_hides_the_revealed_one_below() -> void:
	var world: FakeWorld = _world_with_everything()
	world.alive = {1: MARKED_POS}   # the same boar is revealed and marked
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	GameEvents.bait_placed.emit(BAIT_POS, -1.0)   # already expired
	GameEvents.item_used.emit(Ids.I_SCOUT_DRONE, Vector3.ZERO)
	hud._poll_world()
	var kinds: Array[StringName] = _kinds(hud)
	ok(not kinds.has(&"bait"), "ceva vencida nao aparece")
	var at_revealed: int = kinds.find(&"revealed")
	var at_boar: int = kinds.find(&"boar")
	ok(at_revealed >= 0 and at_boar > at_revealed, "o triangulo (boar) vem depois do circulo (revealed): cobre")


func test_hud_caramelo_nearest_boar_is_in_the_boar_block_before_the_dog() -> void:
	var world: FakeWorld = _world_with_everything()
	world.marked = PackedVector3Array()
	world.dog_state = &"follow"
	var hud: Hud = _spawn(world, Ids.D_CARAMELO)
	if hud == null:
		return
	hud._poll_world()
	var kinds: Array[StringName] = _kinds(hud)
	eq(kinds, [&"crop", &"boar", &"dog"] as Array[StringName], "caramelo: o javali mais proximo antes do cao")
	eq(hud._marks[1]["pos"], BOAR_A, "o mais proximo do cacador")


func test_hud_dog_target_and_dog_come_after_every_boar_mark() -> void:
	var world: FakeWorld = _world_with_everything()
	var hud: Hud = _spawn(world, Ids.D_CARAMELO)
	if hud == null:
		return
	GameEvents.dog_marked_boar.emit(Vector3(15.0, 0.0, 15.0), 6.0)
	hud._poll_world()
	var kinds: Array[StringName] = _kinds(hud)
	var last_boar: int = -1
	for i: int in kinds.size():
		if kinds[i] == &"boar":
			last_boar = i
	ok(last_boar >= 0, "ha javalis marcados")
	ok(kinds.find(&"dog_target") > last_boar, "o anel do alvo vem depois de todo triangulo")
	ok(kinds.find(&"dog") > kinds.find(&"dog_target"), "o cao vem por ultimo")
	eq(kinds[kinds.size() - 1], &"dog", "o cao e o ultimo sem aliados")


func test_hud_polling_twice_does_not_stack_marks() -> void:
	var world: FakeWorld = _world_with_everything()
	var hud: Hud = _spawn(world)
	if hud == null:
		return
	hud._poll_world()
	var first: int = hud._marks.size()
	hud._poll_world()
	hud._poll_world()
	eq(hud._marks.size(), first, "o polling reconstroi as marcas")


# --------------------------------------------------------------------------------------------
# Data: game.minimap (docs 9.1), poked in the live registry and restored
# --------------------------------------------------------------------------------------------

## Errors that _validate_minimap reports after `mutate` changed a deep copy of the block (the registry ends untouched).
func _minimap_errors(mutate: Callable) -> PackedStringArray:
	var game: Dictionary = Data._raw["game"]
	var original: Variant = game.get("minimap")
	var base: int = Data.get_load_errors().size()
	var copy: Variant = (original as Dictionary).duplicate(true) if original is Dictionary else null
	game["minimap"] = copy
	mutate.call(copy)
	Data._validate_minimap()
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(base, Data.get_load_errors().size()):
		out.append(Data.get_load_errors()[i])
	game["minimap"] = original
	Data._errors.resize(base)
	return out


func _first_has(errs: PackedStringArray, needle: String) -> bool:
	return errs.size() >= 1 and errs[0].contains(needle)


func test_data_loads_clean_with_the_minimap_block() -> void:
	eq(Data.get_load_errors().size(), 0, "Data.get_load_errors: %s" % str(Data.get_load_errors()))
	var cfg: Dictionary = Data.get_game().get("minimap", {})
	ok(not cfg.is_empty(), "game.minimap existe")
	eq(int(cfg["image_px"]), 256, "image_px 256")
	eq(int(cfg["grid_stride"]), 1, "grid_stride 1")
	for key: String in ["hillshade", "height_tint", "colors", "prop_colors", "canopy", "crop_row_px"]:
		ok(cfg.has(key), "minimap.%s existe" % key)
	eq(_minimap_errors(func(_c: Dictionary) -> void: pass).size(), 0, "validar o bloco intacto nao da erro")
	eq(Data.get_load_errors().size(), 0, "registro restaurado")


func test_data_step_weights_put_minimap_between_flora_and_crop() -> void:
	var keys: Array = (Data.get_game()["loading"]["step_weights"] as Dictionary).keys()
	var flora: int = keys.find("flora")
	ok(flora >= 0, "step_weights tem flora")
	eq(keys.find("minimap"), flora + 1, "minimap logo depois de flora")
	eq(keys.find("crop"), flora + 2, "crop logo depois de minimap")
	ok(float(Data.get_game()["loading"]["step_weights"]["minimap"]) > 0.0, "peso do minimap positivo")


func test_data_rejects_image_px_out_of_range() -> void:
	var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void: c["image_px"] = 1000)
	eq(errs.size(), 1, "image_px 1000: um erro (%s)" % str(errs))
	ok(_first_has(errs, "image_px"), "o erro cita image_px")
	ok(_first_has(errs, "64-512"), "o erro cita a faixa")
	for bad: Variant in [63, 513, 0, -256, 256.5, "256", null, [256], true]:
		eq(_minimap_errors(func(c: Dictionary) -> void: c["image_px"] = bad).size(), 1, "image_px %s: um erro" % str(bad))
	eq(Data.get_load_errors().size(), 0, "registro restaurado")


func test_data_accepts_the_image_px_edges() -> void:
	for good: Variant in [64, 512, 128, 256, 256.0]:
		eq(_minimap_errors(func(c: Dictionary) -> void: c["image_px"] = good).size(), 0, "image_px %s" % str(good))


func test_data_rejects_a_grid_stride_that_is_not_1_or_2() -> void:
	var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void: c["grid_stride"] = 3)
	eq(errs.size(), 1, "grid_stride 3: um erro (%s)" % str(errs))
	ok(_first_has(errs, "grid_stride"), "o erro cita grid_stride")
	for bad: Variant in [0, 4, -1, 1.5, "2"]:
		eq(_minimap_errors(func(c: Dictionary) -> void: c["grid_stride"] = bad).size(), 1, "grid_stride %s: um erro" % str(bad))
	eq(_minimap_errors(func(c: Dictionary) -> void: c["grid_stride"] = 2).size(), 0, "grid_stride 2 vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["grid_stride"] = 1).size(), 0, "grid_stride 1 vale")


func test_data_rejects_a_hillshade_with_min_above_max() -> void:
	var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void:
		c["hillshade"]["min"] = 1.3
		c["hillshade"]["max"] = 1.25)
	eq(errs.size(), 1, "hillshade min > max: um erro (%s)" % str(errs))
	ok(_first_has(errs, "hillshade"), "o erro cita hillshade")
	eq(_minimap_errors(func(c: Dictionary) -> void:
		c["hillshade"]["min"] = 1.0
		c["hillshade"]["max"] = 1.0).size(), 0, "min = max vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["min"] = 0.0).size(), 1, "min = 0: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["min"] = -0.5).size(), 1, "min negativo: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"].erase("max")).size(), 1, "max ausente: um erro")


func test_data_rejects_bad_hillshade_angles_and_strength() -> void:
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["altitude_deg"] = 0.0).size(), 1, "altitude 0: erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["altitude_deg"] = 91.0).size(), 1, "altitude 91: erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["altitude_deg"] = 90.0).size(), 0, "altitude 90 vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["azimuth_deg"] = 361.0).size(), 1, "azimute 361: erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["azimuth_deg"] = -1.0).size(), 1, "azimute negativo: erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["azimuth_deg"] = 0.0).size(), 0, "azimute 0 vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["strength"] = 3.0).size(), 1, "forca 3: erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["hillshade"]["strength"] = 0.0).size(), 0, "forca 0 vale (sem relevo)")
	eq(_minimap_errors(func(c: Dictionary) -> void: c.erase("hillshade")).size(), 1, "hillshade ausente: um erro")


func test_data_rejects_a_color_that_is_not_a_color() -> void:
	var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void: c["colors"]["grass"] = "verde")
	eq(errs.size(), 1, "cor \"verde\": um erro (%s)" % str(errs))
	ok(_first_has(errs, "colors.grass"), "o erro cita colors.grass")
	for bad: Variant in ["", "#12345", "#GGGGGG", 12, null, [1, 2, 3]]:
		eq(_minimap_errors(func(c: Dictionary) -> void: c["colors"]["water"] = bad).size(), 1, "colors.water %s: um erro" % str(bad))
	eq(_minimap_errors(func(c: Dictionary) -> void: c["prop_colors"]["barn"] = "verde").size(), 1, "prop_colors invalida: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["canopy"]["ipe"]["color"] = "verde").size(), 1, "copa com cor invalida: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["colors"]["grass"] = "BDA85C").size(), 0, "hexadecimal sem # vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["colors"]["grass"] = "#BDA85CFF").size(), 0, "hexadecimal com alfa vale")


func test_data_rejects_a_missing_color_key() -> void:
	for key: String in ["grass", "crop_soil", "road", "wet", "water", "water_edge", "soy", "corn", "crop_row", "prop_default"]:
		var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void: c["colors"].erase(key))
		eq(errs.size(), 1, "sem colors.%s: um erro (%s)" % [key, str(errs)])
		ok(_first_has(errs, key), "o erro cita %s" % key)
	eq(_minimap_errors(func(c: Dictionary) -> void: c.erase("colors")).size(), 1, "colors ausente: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c.erase("prop_colors")).size(), 1, "prop_colors ausente: um erro")


func test_data_rejects_a_canopy_radius_that_is_not_positive() -> void:
	var errs: PackedStringArray = _minimap_errors(func(c: Dictionary) -> void: c["canopy"]["ipe"]["radius_m"] = 0)
	eq(errs.size(), 1, "canopy.ipe.radius_m 0: um erro (%s)" % str(errs))
	ok(_first_has(errs, "ipe.radius_m"), "o erro cita ipe.radius_m")
	for bad: Variant in [-1.0, "2", null]:
		eq(_minimap_errors(func(c: Dictionary) -> void: c["canopy"]["buriti"]["radius_m"] = bad).size(), 1, "radius_m %s: um erro" % str(bad))
	eq(_minimap_errors(func(c: Dictionary) -> void: c["canopy"]["buriti"]["radius_m"] = 0.5).size(), 0, "0,5 m vale")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["canopy"]["buriti"] = "x").size(), 1, "entrada de copa que nao e objeto: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c.erase("canopy")).size(), 1, "canopy ausente: um erro")


func test_data_rejects_a_missing_or_wrong_minimap_block() -> void:
	var errs: PackedStringArray = _minimap_errors(func(_c: Dictionary) -> void:
		Data._raw["game"].erase("minimap"))
	eq(errs.size(), 1, "bloco ausente: um erro (%s)" % str(errs))
	ok(_first_has(errs, "minimap"), "o erro cita minimap")
	eq(Data.get_game().get("minimap", {}).is_empty(), false, "o bloco foi restaurado")
	var as_text: PackedStringArray = _minimap_errors(func(_c: Dictionary) -> void:
		Data._raw["game"]["minimap"] = "nada")
	eq(as_text.size(), 1, "bloco que nao e objeto: um erro")
	eq(Data.get_load_errors().size(), 0, "registro restaurado")


func test_data_rejects_bad_crop_rows_and_height_tint() -> void:
	eq(_minimap_errors(func(c: Dictionary) -> void: c["crop_row_px"] = -1).size(), 1, "crop_row_px -1: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["crop_row_px"] = 1.5).size(), 1, "crop_row_px 1,5: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["crop_row_px"] = 0).size(), 0, "crop_row_px 0 vale (sem linhas)")
	eq(_minimap_errors(func(c: Dictionary) -> void: c["height_tint"]["low"] = 0.0).size(), 1, "tint low 0: um erro")
	eq(_minimap_errors(func(c: Dictionary) -> void: c.erase("height_tint")).size(), 2, "height_tint ausente: um erro por chave")
