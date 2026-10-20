class_name MissileSalvo
extends RefCounted
## One press of M: every missile aboard that the chosen mode allows, fired
## as fast as the launchers cycle. Modes: everything at once, conventional
## (anti-ship and saturation) only, EMP only, nuclear only, or a sequence —
## all of one warhead, then all of the next, in the player's order (e.g. EMP
## first to blind the point defence, then the anti-ship swarm).

enum Mode { ALL, CONVENTIONAL, EMP, NUCLEAR, SEQUENCE }
const MODE_NAMES := ["all", "conventional", "EMP", "nuclear", "sequence"]
## Warhead names, by MissileConfig.Warhead.
const WARHEAD_NAMES := ["conventional", "EMP", "nuclear"]
const DEFAULT_ORDER: Array[int] = [MissileConfig.Warhead.EMP, MissileConfig.Warhead.ANTI_SHIP, MissileConfig.Warhead.NUCLEAR]

var shooter_id: StringName
var target_id: StringName
## Warheads still to fire, in order (-1 = any kind).
var groups: Array[int] = []
var launched: int = 0
## At most this many missiles (0 = every one the mode allows); a swarm
## launch may overshoot by the rest of its swarm.
var limit: int = 0


## The warhead groups a mode fires, in order.
static func groups_for(mode: int, order: Array) -> Array[int]:
	var out: Array[int] = []
	match mode:
		Mode.CONVENTIONAL:
			out.append(MissileConfig.Warhead.ANTI_SHIP)
		Mode.EMP:
			out.append(MissileConfig.Warhead.EMP)
		Mode.NUCLEAR:
			out.append(MissileConfig.Warhead.NUCLEAR)
		Mode.SEQUENCE:
			for w in sanitize_order(order):
				out.append(w)
		_:
			out.append(-1)
	return out


## A full order of the three warheads (bad or missing entries fixed up).
static func sanitize_order(order: Array) -> Array[int]:
	var out: Array[int] = []
	for w in order:
		var k := int(w)
		if k >= 0 and k < WARHEAD_NAMES.size() and not out.has(k):
			out.append(k)
	for w in DEFAULT_ORDER:
		if not out.has(w):
			out.append(w)
	return out


## "EMP → conventional → nuclear".
static func order_text(order: Array) -> String:
	return " → ".join(sanitize_order(order).map(func(w: int) -> String: return WARHEAD_NAMES[w]))


static func mode_text(mode: int, order: Array) -> String:
	return "sequence %s" % order_text(order) if mode == Mode.SEQUENCE else MODE_NAMES[clampi(mode, 0, MODE_NAMES.size() - 1)]


static func start(p_shooter: StringName, p_target: StringName, mode: int, order: Array, p_limit: int = 0) -> MissileSalvo:
	var s := MissileSalvo.new()
	s.shooter_id = p_shooter
	s.target_id = p_target
	s.groups = groups_for(mode, order)
	s.limit = maxi(p_limit, 0)
	return s


## Missiles aboard `sys` that this salvo would fire.
func available(sys: ShipSystems) -> int:
	var n := 0
	for g in groups:
		n += sys.missiles_of(g)
	return n


## Fire every launcher of the current group that is ready; when the group
## has nothing left, move on to the next. Returns the launches this call.
func step(world: WorldSimulation) -> int:
	var shooter := world.get_ship(shooter_id)
	var target := world.get_ship(target_id)
	if shooter == null or shooter.systems == null or not shooter.is_active() or target == null or not target.is_active():
		groups.clear()
		return 0
	var n := 0
	while not groups.is_empty():
		if limit > 0 and launched + n >= limit:
			groups.clear()
			break
		if shooter.systems.missiles_of(groups[0]) == 0:
			groups.pop_front()
			continue
		var before := world.missiles.size()
		while (limit == 0 or launched + n < limit) and world.launch_missile(shooter_id, target_id, groups[0]) == "":
			n += world.missiles.size() - before
			before = world.missiles.size()
		break
	launched += n
	if limit > 0 and launched >= limit:
		groups.clear()
	return n


func done() -> bool:
	return groups.is_empty()
