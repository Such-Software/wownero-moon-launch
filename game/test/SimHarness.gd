extends Node
## Headless balance / autopilot-tuning harness. NO window, NO Movie Maker.
##
## Run one level to completion and print a single parseable result line, then
## quit the instant the outcome is known:
##
##   godot --headless --autopilot --sim res://game/levels/1/Level1.tscn
##   -> SIM_RESULT outcome=WIN level=1 t=12.34 fuel=44.0 frames=740
##
## Env knobs:
##   SIM_LEVEL       set globalvar.nowlevel (upgrades/scaling/report); default keeps the scene's
##   SIM_MAX_TIME    seconds of game-time before TIMEOUT (default 90)
##   SIM_TIME_SCALE  Engine.time_scale for faster-than-real sims (default 1.0; keep low for fidelity)
##   AP_*            autopilot tuning knobs (see AutoPilot.gd)
##
## Telemetry + score submission are disabled under --sim (see Telemetry.gd / ScoreClient.gd),
## so sweeps never touch the live backend.

var _start_frame := 0
var _max_frames := 0
var _done := false
var _hazard_death := false  # set if a hazard (Martian/black hole/etc.) killed us


func _ready() -> void:
	if not ("--sim" in OS.get_cmdline_args()):
		set_physics_process(false)
		return
	# Hazards kill via globalvar.sendDeath; collisions kill via the rocket's own
	# crash path. Listening here lets us report which one happened.
	if globalvar.has_signal("sendDeath"):
		globalvar.sendDeath.connect(func(): _hazard_death = true)
	Engine.max_fps = 0
	var ts := OS.get_environment("SIM_TIME_SCALE")
	if ts != "":
		Engine.time_scale = maxf(0.1, float(ts))
	var lvl := OS.get_environment("SIM_LEVEL")
	if lvl != "":
		globalvar.nowlevel = int(lvl)
	var maxt := 90.0
	var mt := OS.get_environment("SIM_MAX_TIME")
	if mt != "":
		maxt = float(mt)
	_max_frames = int(maxt * Engine.physics_ticks_per_second)
	_start_frame = Engine.get_physics_frames()


func _physics_process(_dt: float) -> void:
	if _done:
		return
	var elapsed := Engine.get_physics_frames() - _start_frame
	var arr := get_tree().get_nodes_in_group("rocket")
	var rocket = arr[0] if arr.size() > 0 else null
	if rocket != null and is_instance_valid(rocket):
		# WIN: touchdown within landing speed (set well before the Victory scene loads)
		if rocket.get("landattemptnow") == true or rocket.get("flagplaced") == true:
			_report("WIN", rocket, elapsed)
			return
		# DEATH: death() shows the skull (normal mode; easy-bounce is off by default)
		var skull = rocket.get_node_or_null("SkullSprite")
		if skull != null and skull.visible:
			_report("DEATH", rocket, elapsed)
			return
	if elapsed > _max_frames:
		_report("TIMEOUT", rocket, elapsed)


func _report(outcome: String, rocket, frames: int) -> void:
	_done = true
	set_physics_process(false)
	var t := float(frames) / float(Engine.physics_ticks_per_second)
	var fuel := 0.0
	if rocket != null and is_instance_valid(rocket):
		fuel = float(rocket.get("fuel"))
	var cause := ""
	if outcome == "DEATH":
		# Prefer the authoritative cause_type computed by rocket.gd's death forensics
		# (exposed via globalvar.last_death once WP-B3 lands); it correctly resolves
		# crash-vs-out_of_fuel by crash_body, which the harness cannot observe. Until
		# then, fall back to the sendDeath signal (hazard) vs a plain collision crash.
		# Note: we deliberately do NOT infer out_of_fuel from `fuel<=0` — a crash with
		# an empty tank is a crash, and that guess would over-report out_of_fuel.
		var cause_type := "hazard" if _hazard_death else "crash"
		var ld = globalvar.get("last_death")
		if typeof(ld) == TYPE_DICTIONARY and ld.has("cause_type"):
			cause_type = String(ld["cause_type"])
		cause = " cause=" + cause_type
	print("SIM_RESULT outcome=%s level=%d t=%.2f fuel=%.1f frames=%d%s" % [outcome, globalvar.nowlevel, t, fuel, frames, cause])
	get_tree().quit()
