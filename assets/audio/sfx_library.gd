extends Node
## Autoload "Sfx". Synthesizes every sound at startup (loops lazily on first use), owns the audio
## buses SFX / Ambience / UI and a small player pool. See docs/arquitetura.md section 7.8.
## No bus effects (the Web "sample" playback mode ignores them).

const POOL_3D: int = 12
const POOL_2D: int = 6
const BUS_SFX: StringName = &"SFX"
const BUS_AMBIENCE: StringName = &"Ambience"
const BUS_UI: StringName = &"UI"
const UI_PREFIX: String = "ui_"

var _streams: Dictionary = {}
var _warned: Dictionary = {}
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer] = []
var _next_3d: int = 0
var _next_2d: int = 0
var _loops: Dictionary = {}
var synth_ms: float = 0.0
var _animals_built: bool = false


func _ready() -> void:
	_ensure_buses()
	var t0: int = Time.get_ticks_usec()
	SynthWeapons.build(_streams)
	SynthWorld.build(_streams)
	synth_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	for i in POOL_3D:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 250.0
		p.bus = BUS_SFX
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_2D:
		var q: AudioStreamPlayer = AudioStreamPlayer.new()
		q.bus = BUS_SFX
		add_child(q)
		_pool_2d.append(q)
	_connect_settings.call_deferred()
	_build_animals.call_deferred()


## Animal voices are built one frame after startup to keep _ready short.
func _build_animals() -> void:
	if _animals_built:
		return
	_animals_built = true
	var t0: int = Time.get_ticks_usec()
	SynthAnimals.build(_streams)
	synth_ms += float(Time.get_ticks_usec() - t0) / 1000.0


func _ensure_buses() -> void:
	for bus_name: StringName in [BUS_SFX, BUS_AMBIENCE, BUS_UI]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


func _connect_settings() -> void:
	var profile: Node = get_node_or_null("/root/Profile")
	if profile != null and profile.has_method(&"get_setting"):
		for key: String in ["volume_master", "volume_sfx", "volume_ambience"]:
			var v: Variant = profile.call(&"get_setting", key)
			if v != null:
				_apply_setting(key, v)
	var events: Node = get_node_or_null("/root/GameEvents")
	if events != null and events.has_signal(&"settings_changed"):
		events.connect(&"settings_changed", _apply_setting)


func _apply_setting(key: String, value: Variant) -> void:
	match key:
		"volume_master": set_bus_volume(&"Master", float(value))
		"volume_sfx":
			set_bus_volume(BUS_SFX, float(value))
			set_bus_volume(BUS_UI, float(value))
		"volume_ambience": set_bus_volume(BUS_AMBIENCE, float(value))


func _get_stream(id: StringName) -> AudioStreamWAV:
	if _streams.has(id):
		return _streams[id]
	if SynthWeapons.SHOT_IDS.has(id):
		_streams[id] = SynthWeapons.build_shot(id)
		return _streams[id]
	if not _animals_built and (String(id).begins_with("boar_") or String(id).begins_with("dog_")):
		_build_animals()
		if _streams.has(id):
			return _streams[id]
	if SynthWorld.LAZY_IDS.has(id):
		var s: AudioStreamWAV = SynthWorld.build_lazy(id)
		_streams[id] = s
		return s
	if not _warned.has(id):
		_warned[id] = true
		push_warning("Sfx: unknown sound id '%s'" % id)
	return null


func has_sound(id: StringName) -> bool:
	return _streams.has(id) or SynthWorld.LAZY_IDS.has(id) or SynthWeapons.SHOT_IDS.has(id) or String(id).begins_with("boar_") or String(id).begins_with("dog_")


func play(id: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStreamWAV = _get_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stop()
	p.stream = s
	p.bus = BUS_UI if String(id).begins_with(UI_PREFIX) else BUS_SFX
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch, 0.01)
	p.play()


func play_3d(id: StringName, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var s: AudioStreamWAV = _get_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer3D = _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stop()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch, 0.01)
	p.position = position
	p.play()


func play_loop(id: StringName, volume_db: float = 0.0) -> void:
	var s: AudioStreamWAV = _get_stream(id)
	if s == null:
		return
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = BUS_AMBIENCE
		p.stream = s
		add_child(p)
		_loops[id] = p
	p.volume_db = volume_db
	if not p.playing:
		p.play()


func stop_loop(id: StringName) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p != null:
		p.stop()


func stop_all_loops() -> void:
	for id: StringName in _loops:
		(_loops[id] as AudioStreamPlayer).stop()


func unlock_audio() -> void:
	var p: AudioStreamPlayer = _pool_2d[0] if not _pool_2d.is_empty() else null
	if p == null:
		return
	var s: AudioStreamWAV = AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SynthDsp.RATE
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(2 * 441)
	s.data = bytes
	p.stream = s
	p.volume_db = -80.0
	p.play()


func set_bus_volume(bus: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
