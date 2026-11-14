class_name NetCodec
extends RefCounted
## Wire constants and quantization shared by packages A, B and N. See docs/multiplayer.md section 4.

const PROTOCOL_VERSION: int = 1
const LANE_STATE: int = 0
const LANE_EVENT: int = 1
const FRAME_HEADER_BYTES: int = 5      # lane u8, seq u16, ack u16
const RECORD_HEADER_BYTES: int = 3     # type u8, len u16
const HUNTER_STATE_BYTES: int = 14
const NO_SLOT: int = 255

# Link / lobby (event lane)
const L_READY: int = 0x10
const L_LOBBY: int = 0x11
const L_START: int = 0x12
const L_LOADED: int = 0x13
const L_GO: int = 0x14
const L_NEED_RELAY: int = 0x15
# Host -> client
const H_SNAPSHOT: int = 0x20           # state lane
const EV_BOAR_SPAWN: int = 0x21
const EV_BOAR_HIT: int = 0x22
const EV_BOAR_ATTACK: int = 0x23
const EV_BOAR_DEATH: int = 0x24
const EV_CROP_EATEN: int = 0x25
const EV_BAIT: int = 0x26
const EV_DOG_MARK: int = 0x27
const EV_DOG_CMD: int = 0x28
const EV_MESSAGE: int = 0x29
const EV_HUNT_END: int = 0x2A
const EV_FULL_SYNC: int = 0x2B         # reserved (F8)
# Client -> host
const C_STATE: int = 0x40              # state lane
const C_SHOT: int = 0x41
const C_CHARGE_HIT: int = 0x42
const C_BAIT: int = 0x43
const C_DOG_CMD: int = 0x44

# Hunter state flags
const HF_CROUCH: int = 1
const HF_AIM: int = 2
const HF_SPRINT: int = 4
const HF_ALIVE: int = 8
const HF_RELOAD: int = 16
const HF_UNARMED: int = 32             # binoculars / item in hand

const BOAR_STATES: Array[StringName] = [&"wander", &"to_crop", &"eat", &"to_bait", &"alert", &"flee",
	&"scrape", &"charge", &"recover", &"bayed", &"held", &"dead"]
const DOG_STATES: Array[StringName] = [&"follow", &"seek", &"point", &"bay", &"hold", &"retreat", &"return"]
const ZONES: Array[StringName] = [&"head", &"vital", &"body", &"rear", &"dog"]


static func make_shot_id(slot: int, counter: int) -> int:
	return (slot << 24) | (counter & 0xFFFFFF)


static func shot_slot(shot_id: int) -> int:
	return (shot_id >> 24) & 0xFF


static func put_xz(out: StreamPeerBuffer, rect: Rect2, x: float, z: float) -> void:
	out.put_u16(clampi(roundi((x - rect.position.x) / rect.size.x * 65535.0), 0, 65535))
	out.put_u16(clampi(roundi((z - rect.position.y) / rect.size.y * 65535.0), 0, 65535))


static func get_xz(inp: StreamPeerBuffer, rect: Rect2) -> Vector2:
	var qx: int = inp.get_u16()
	var qz: int = inp.get_u16()
	return Vector2(rect.position.x + float(qx) / 65535.0 * rect.size.x,
		rect.position.y + float(qz) / 65535.0 * rect.size.y)


static func angle_to_u8(rad: float) -> int:
	return posmod(roundi(rad / TAU * 256.0), 256)


static func u8_to_angle(q: int) -> float:
	return float(q) / 256.0 * TAU


static func angle_to_u16(rad: float) -> int:
	return posmod(roundi(rad / TAU * 65536.0), 65536)


static func u16_to_angle(q: int) -> float:
	return float(q) / 65536.0 * TAU


## Wrap-aware "a is newer than b" for u16 sequence numbers.
static func seq_newer(a: int, b: int) -> bool:
	return ((a - b) & 0xFFFF) != 0 and ((a - b) & 0xFFFF) < 0x8000
