class_name Contact
extends RefCounted
## One ship in an encounter, and everything the fight keeps about it: what
## our sensors know of it and its of us, whether it is hostile, its air
## wing, its automation (ShipPolicy: role, salvos, discipline), its salvo
## in flight, and where it stands (arriving, beaten, taken as a prize).
## Its id is its ship's id in the WorldSimulation and stays stable while it
## lives; once beaten it is retired (re-keyed as a wreck) and leaves the
## encounter.

var id: StringName
## Place in the encounter (0 = the lead ship); sets its role.
var index: int = 0
## Our sensors' track of it, and its track of us.
var track := SensorTrack.new()
var their_track := SensorTrack.new()
var hostile: bool = false
var wing: AirWing
var policy: ShipPolicy
## Inbound to its standoff; it must be detected before it engages.
var arriving: bool = false
## Disabled or captured once (counted for missions); taken as a prize.
var beaten: bool = false
var prize_taken: bool = false
## Its missile salvo in flight (null when none), and when the next may go.
var salvo: MissileSalvo
var salvo_at: float = 0.0
## After we cut its gangway it waits until then before boarding again.
var reboard_at: float = -INF


static func create(p_id: StringName, p_index: int, p_policy: ShipPolicy) -> Contact:
	var c := Contact.new()
	c.id = p_id
	c.index = p_index
	c.policy = p_policy
	return c
