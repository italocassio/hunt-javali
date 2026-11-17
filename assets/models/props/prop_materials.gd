extends RefCounted
## Shared material library for the HD farm props (farmhouse, barn, water tank, fence, gate, bait, trough, barn corn stock).
## ONE ShaderMaterial (prop_hd.gdshader) serves every prop: the surface kind is the feature id painted into
## UV2.y with HDMesh.paint(color, 0.0, roughness, wear, feature). The noise texture is the 512 px RG texture the
## showcase weapons already build, so no extra texture exists.
##
## How a prop uses it:
##   var m := HDMesh.new()
##   m.paint(PropMaterials.PLASTER, 0.0, 0.9, 0.0, PropMaterials.F_PLASTER)
##   ... emit geometry ...
##   var built := m.build()                       # then HDMesh.bake_ao(...) and
##   HDMesh.commit(built, mesh, PropMaterials.surfaces())     # surface 0 -> the shared material
## Grain axis for wood features goes in the `wear` argument: GRAIN_Y / GRAIN_X / GRAIN_Z.

const HDMesh := preload("res://assets/models/weapons/showcase/hd_mesh.gd")
const RifleHD := preload("res://assets/models/weapons/showcase/rifle_308_hd.gd")
const SHADER: Shader = preload("res://assets/models/props/prop_hd.gdshader")

# feature ids (UV2.y), keep in sync with prop_hd.gdshader
const F_PLASTER: int = 0
const F_TILE: int = 1
const F_WOOD: int = 2
const F_PAINT: int = 3
const F_CEMENT: int = 4
const F_GLASS: int = 5
const F_LOUVER: int = 6
const F_ZINC: int = 7
const F_CERAMIC: int = 8
const F_PLANK: int = 9        # weathered vertical boards (barn walls)
const F_ROOF_ZINC: int = 10   # corrugated rusty zinc roof
const F_EARTH: int = 11       # packed earth floor
const F_FIBRO: int = 12       # fibre-cement (water tank)
const F_HAY: int = 13
const F_CORN: int = 14        # corn kernels: GRAIN_Y/X (code 0) = cob rows by UV, CORN_LOOSE = loose grain by object space

# wood grain axis, passed as the `wear` of paint()
const GRAIN_Y: float = 0.0
const GRAIN_X: float = 0.4
const GRAIN_Z: float = 0.8
const CORN_COB: float = 0.0
const CORN_LOOSE: float = 0.4

# palette (stored colours, rendered as is: same convention as the flora vertex colours)
const WHITEWASH: Color = Color(0.78, 0.80, 0.84)
const TILE_CLAY: Color = Color(0.50, 0.26, 0.19)
const TILE_CAP: Color = Color(0.46, 0.24, 0.17)
const WOOD_RAW: Color = Color(0.42, 0.29, 0.18)
const WOOD_LIGHT: Color = Color(0.52, 0.38, 0.25)
const PAINT_BLUE: Color = Color(0.25, 0.40, 0.48)
const CEMENT_RED: Color = Color(0.46, 0.24, 0.18)
const CEMENT_GREY: Color = Color(0.58, 0.55, 0.50)
const ZINC_GREY: Color = Color(0.62, 0.64, 0.64)
const BARN_RED: Color = Color(0.50, 0.19, 0.13)
const HAY: Color = Color(0.80, 0.66, 0.32)
const ROOF_ZINC: Color = Color(0.66, 0.68, 0.68)
const EARTH: Color = Color(0.46, 0.31, 0.20)
const FIBRO_GREY: Color = Color(0.64, 0.64, 0.60)
const TWINE: Color = Color(0.30, 0.22, 0.12)
const CORN_YELLOW: Color = Color(0.86, 0.66, 0.14)
const CORN_DEEP: Color = Color(0.74, 0.50, 0.08)
const HUSK: Color = Color(0.74, 0.66, 0.40)
const HUSK_DRY: Color = Color(0.62, 0.52, 0.30)
const SACK_CLOTH: Color = Color(0.70, 0.62, 0.46)
const WIRE_STEEL: Color = Color(0.50, 0.50, 0.50)

static var _material: ShaderMaterial = null


static func get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		var wood: ShaderMaterial = RifleHD.get_materials()[RifleHD.SURF_WOOD]
		_material.set_shader_parameter(&"noise_tex", wood.get_shader_parameter(&"noise_tex"))
	return _material


## Surface index -> material, for HDMesh.commit (everything on surface 0).
static func surfaces() -> Dictionary:
	return {0: get_material()}
