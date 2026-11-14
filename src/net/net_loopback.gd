class_name NetLoopback
extends RefCounted
## In-memory pair of transports between two NetLink, for tests (no socket, no server).
## It carries both paths: the relay (reliable, ordered) and a direct transport (event channel
## reliable and ordered, state channel with configurable loss and reordering).
##
##   var lp := NetLoopback.new(seed)
##   lp.state_loss = 0.2
##   lp.attach(link_a, link_b, true)     # true = also plug the direct transport (still closed)
##   lp.open_direct()                    # both links promote to PATH_RTC on their next poll
##   ... link_a.send_events(...) ; link_a.poll(now) ; lp.step() ; link_b.poll(now) ; link_b.take_events()
##
## Nothing is delivered until step(): one step = one network hop.


class Port extends NetLink.Direct:
	var open: bool = false
	var failed: bool = false
	var out_state: Array[PackedByteArray] = []
	var out_event: Array[PackedByteArray] = []
	var inbox: Array[PackedByteArray] = []

	func is_open() -> bool:
		return open and not failed

	func is_failed() -> bool:
		return failed

	func send_state(frame: PackedByteArray) -> bool:
		if not is_open():
			return false
		out_state.append(frame)
		return true

	func send_event(frame: PackedByteArray) -> bool:
		if not is_open():
			return false
		out_event.append(frame)
		return true

	func take_frames() -> Array[PackedByteArray]:
		var out: Array[PackedByteArray] = inbox
		inbox = []
		return out

	func close() -> void:
		open = false
		failed = true


var state_loss: float = 0.0       # probability that a state-channel message of the direct path is lost
var state_reorder: float = 0.0    # probability that it is held back and delivered after newer ones
var relay_enabled: bool = true    # false = the relay sink fails (room server gone)
var stall_direct: bool = false    # true = the direct transport stays "open" but delivers nothing
var direct_dropped: int = 0       # frames swallowed by stall_direct

var port_a: Port = Port.new()
var port_b: Port = Port.new()

# Counters.
var relay_messages_ab: int = 0
var relay_messages_ba: int = 0
var relay_bytes_ab: int = 0
var relay_bytes_ba: int = 0
var state_sent: int = 0
var state_lost: int = 0
var state_reordered: int = 0

var _link_a: NetLink = null
var _link_b: NetLink = null
var _relay_ab: Array[PackedByteArray] = []
var _relay_ba: Array[PackedByteArray] = []
var _held_ab: Array[PackedByteArray] = []
var _held_ba: Array[PackedByteArray] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_seed: int = 1) -> void:
	_rng.seed = p_seed


## Wires the relay of both links (cfg = Data.get_net()) and, optionally, the direct transport.
func attach(link_a: NetLink, link_b: NetLink, cfg: Dictionary, with_direct: bool = false) -> void:
	_link_a = link_a
	_link_b = link_b
	link_a.setup(cfg, 2, _sink_a)
	link_b.setup(cfg, 1, _sink_b)
	link_a.set_relay_alive_check(_is_relay_up)
	link_b.set_relay_alive_check(_is_relay_up)
	if with_direct:
		link_a.set_direct(port_a)
		link_b.set_direct(port_b)


func open_direct() -> void:
	port_a.open = true
	port_b.open = true


## The direct transport dies: both ports report failed and everything in flight is lost.
func fail_direct() -> void:
	kill_port(port_a)
	kill_port(port_b)


## One side's port dies (the other side still thinks its own is fine).
func kill_port(port: Port) -> void:
	port.failed = true
	port.out_state = []
	port.out_event = []
	port.inbox = []
	_held_ab = []
	_held_ba = []


## Delivers everything sent since the previous step.
func step() -> void:
	var ab: Array[PackedByteArray] = _relay_ab
	_relay_ab = []
	for payload: PackedByteArray in ab:
		_link_b.receive_relay(payload)
	var ba: Array[PackedByteArray] = _relay_ba
	_relay_ba = []
	for payload: PackedByteArray in ba:
		_link_a.receive_relay(payload)
	_held_ab = _carry(port_a, port_b, _held_ab)
	_held_ba = _carry(port_b, port_a, _held_ba)


func _carry(from: Port, to: Port, held: Array[PackedByteArray]) -> Array[PackedByteArray]:
	if stall_direct:   # the path looks open on both ends but nothing gets through
		direct_dropped += from.out_event.size() + from.out_state.size() + held.size()
		from.out_event = []
		from.out_state = []
		return []
	for frame: PackedByteArray in from.out_event:
		to.inbox.append(frame)
	from.out_event = []
	var keep: Array[PackedByteArray] = []
	for frame: PackedByteArray in from.out_state:
		state_sent += 1
		if _rng.randf() < state_loss:
			state_lost += 1
		elif _rng.randf() < state_reorder:
			state_reordered += 1
			keep.append(frame)
		else:
			to.inbox.append(frame)
	from.out_state = []
	for frame: PackedByteArray in held:   # late arrivals: after the newer frames of this step
		to.inbox.append(frame)
	return keep


func _is_relay_up() -> bool:
	return relay_enabled


func _sink_a(payload: PackedByteArray) -> bool:
	if not relay_enabled:
		return false
	relay_messages_ab += 1
	relay_bytes_ab += payload.size()
	_relay_ab.append(payload)
	return true


func _sink_b(payload: PackedByteArray) -> bool:
	if not relay_enabled:
		return false
	relay_messages_ba += 1
	relay_bytes_ba += payload.size()
	_relay_ba.append(payload)
	return true
