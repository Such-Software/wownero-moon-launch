extends Node
## Autoload: fires a ONE-TIME HintService banner the first time the player meets each
## hazard TYPE, so players don't have to pre-read Help page 7. Connects
## get_tree().node_added and, when a node whose name identifies a hazard enters the tree,
## maps it to a canonical key and fires show_hint("hazard_<key>", "<one-liner>").
##
## HintService owns the one-time keying (persisted seen_hints), the queue/stagger, and the
## capture suppression, so there is no extra gating here — we just call show_hint().

# Canonical node-name (trailing instance digits stripped) -> hint key. Aliases are folded
# exactly the way rocket.gd:_canonical_hazard does it (GammeRay->GammaRay,
# OrbitingAsteroid->Asteroid, Hull->Mothership).
const NAME_TO_KEY := {
	"Martian": "martian",
	"GammaRay": "gammaray",
	"GammeRay": "gammaray",
	"Asteroid": "asteroid",
	"OrbitingAsteroid": "asteroid",
	"Asteriod": "asteroid",           # misspelled scene root (game/asteriod/Asteriod.tscn) — the L4 spawned asteroids
	"AsteroidCluster": "asteroid",    # L9 asteroid-belt cluster hazard
	"Mothership": "mothership",
	"Hull": "mothership",
	"BlackHole": "blackhole",
	"Wormhole": "wormhole",
	"WormholeA": "wormhole",          # levels name their two wormhole ends WormholeA / WormholeB
	"WormholeB": "wormhole",
	"SolarWind": "solarwind",
	"Nebula": "nebula",
}

# One-line copy per hazard, shortened from DeathScreen.HAZARD_ADVICE / Help.gd page 7.
const HINT_TEXT := {
	"martian": "MARTIANS — they chase! Outrun them or fire back",
	"gammaray": "GAMMA RAYS — bursts flash then fire. Move between the beams",
	"asteroid": "ASTEROIDS — drifting rocks. Watch ahead and thread the gaps",
	"mothership": "MOTHERSHIP — it hits hard. Weave and return fire",
	"blackhole": "BLACK HOLES — they pull hard. Keep your distance and your speed",
	"wormhole": "WORMHOLES — they fling you far. Line up your exit first",
	"solarwind": "SOLAR WIND — shoves you off course. Thrust across it, not into it",
	"nebula": "NEBULA — drains fuel inside. Pass through quickly",
}


func _ready() -> void:
	# One connection for the whole session; hazards only ever appear in level scenes.
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	var key := _key_for(node)
	if key == "":
		return
	var hint_id := "hazard_" + key
	# Cheap early-out for the common case (every node in the tree passes through here).
	if HintService.was_shown(hint_id):
		return
	HintService.show_hint(hint_id, HINT_TEXT[key])


func _key_for(node: Node) -> String:
	## Map a freshly-added node to its canonical hazard key, or "" if it isn't a hazard.
	## Name mapping is the reliable path — the "hazard" group tells us a node IS a hazard
	## but not WHICH one, and the banner copy is type-specific.
	var base := _strip_trailing_digits(String(node.name))
	return NAME_TO_KEY.get(base, "")


func _strip_trailing_digits(n: String) -> String:
	## Same normalization as rocket.gd:_canonical_hazard (Martian2 -> Martian).
	var s := n
	while s.length() > 0 and s.substr(s.length() - 1, 1).is_valid_int():
		s = s.substr(0, s.length() - 1)
	return s
