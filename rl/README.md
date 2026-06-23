# RL training for Such Moon Launch

Goal: a learned policy that clears the hazard levels (which the heuristic pilot
can't) and flies race-competitive times, for **human-vs-robot race mode** and as a
**constructive proof every level is beatable**.

Read the company playbook first: `~/src/docs/reinforcement-learning-game-agent.md`.
This file is the project-specific setup + the agent code, kept here as code blocks
so it does NOT live in the game project (and break editor parsing) until the
`godot_rl_agents` plugin is installed to provide `AIController2D`.

Stack: `godot_rl_agents` (Godot plugin) + `godot-rl` + Stable Baselines3 PPO, ONNX
export for in-game inference. Reuses everything in `game/test/` (input-driving,
state-reading, headless, outcome detection).

## Status: SCAFFOLD (not yet trained)

Design + agent code ready. Not done yet: install plugin, build the train scene,
run PPO, export ONNX. Those are hands-on against the installed plugin.

## Setup

1. **Plugin:** Godot editor → AssetLib → "Godot RL Agents" → install, then enable
   in Project Settings → Plugins. (Or `git clone` the plugin repo into
   `addons/godot_rl_agents/` and enable it.) Keep `addons/godot_rl_agents/` and
   `rl/` in the export-exclude filter so they never ship.
2. **Python:** `python -m venv rl/.venv && source rl/.venv/bin/activate && pip install godot-rl stable-baselines3` (pulls torch; ~1-2GB).

## Agent (the RL env definition)

Drop this in once the plugin is installed (e.g. `rl/RocketAIController.gd`). It is
a **separate node added to a training scene** that references the rocket and drives
the same input actions the autopilot does — `rocket.gd` is NOT modified. Obs come
from the same state the heuristic used; the reward reuses the harness's win/death
detection.

```gdscript
extends AIController2D
## RL agent for the lander. Add as a child of a training-scene root that also has
## a Godot-RL-Agents `Sync` node. Reads the rocket (group "rocket"), drives
## thrust/ui_left/ui_right, and rewards landing / penalizes crash + hazard death.

var _rocket: RigidBody2D = null
var _target: Node2D = null
var _prev_dist := 0.0
var _step_reward := 0.0
var _hazard_death := false

const V_NORM := 300.0
const D_NORM := 1800.0
const W_NORM := 5.0

func _ready() -> void:
	init(self)  # godot_rl: register this controller
	if globalvar.has_signal("sendDeath"):
		globalvar.sendDeath.connect(func(): _hazard_death = true)

func _grab() -> void:
	var arr := get_tree().get_nodes_in_group("rocket")
	_rocket = arr[0] if arr.size() > 0 else null
	if _rocket:
		_rocket.can_sleep = false
		_target = _rocket.get("target")

func get_action_space() -> Dictionary:
	return {
		"thrust": {"size": 2, "action_type": "discrete"},   # 0 off, 1 on
		"rotate": {"size": 3, "action_type": "discrete"},   # 0 left, 1 none, 2 right
	}

func set_action(action) -> void:
	if int(action["thrust"][0]) == 1: Input.action_press("thrust")
	else: Input.action_release("thrust")
	var r := int(action["rotate"][0])
	Input.action_release("ui_left"); Input.action_release("ui_right")
	if r == 0: Input.action_press("ui_left")
	elif r == 2: Input.action_press("ui_right")

func get_obs() -> Dictionary:
	if _rocket == null or not is_instance_valid(_rocket): _grab()
	if _rocket == null or _target == null:
		return {"obs": [0,0, 0,1, 0, 1, 0,0, 1, 0,0]}
	var pos: Vector2 = _rocket.global_position
	var vel: Vector2 = _rocket.linear_velocity
	var to_t: Vector2 = _target.global_position - pos
	var fuel := float(_rocket.get("fuel")) / maxf(float(_rocket.get("max_fuel")), 1.0)
	return {"obs": [
		vel.x / V_NORM, vel.y / V_NORM,
		sin(_rocket.rotation), cos(_rocket.rotation),
		_rocket.angular_velocity / W_NORM,
		fuel,
		to_t.x / D_NORM, to_t.y / D_NORM,
		clampf(to_t.length() / D_NORM, 0.0, 2.0),
		# TODO: add relative dominant gravity body + nearest hazard + its velocity
	]}

func get_reward() -> float:
	var r := _step_reward
	_step_reward = 0.0
	return r

func reset() -> void:
	_hazard_death = false
	_prev_dist = 0.0
	_step_reward = 0.0

func _physics_process(_delta: float) -> void:
	if needs_reset:
		reset()
		return
	if _rocket == null or not is_instance_valid(_rocket): _grab()
	if _rocket == null or _target == null: return
	var dist := (_target.global_position - _rocket.global_position).length()
	if _prev_dist > 0.0:
		_step_reward += (_prev_dist - dist) * 0.01   # progress
	_prev_dist = dist
	_step_reward -= 0.005                            # time pressure
	# terminal: reuse the harness's win/death signals
	if _rocket.get("landattemptnow") == true or _rocket.get("flagplaced") == true:
		_step_reward += 10.0 + (float(_rocket.get("fuel")) / 100.0)
		done = true; needs_reset = true
	else:
		var skull = _rocket.get_node_or_null("SkullSprite")
		if (skull != null and skull.visible) or _hazard_death:
			_step_reward -= 10.0
			done = true; needs_reset = true
```

## Train scene + reset

- Build `rl/train.tscn`: a root node with a **Godot RL Agents `Sync`** node and a
  level instance whose root carries the `RocketAIController` above. The Sync node's
  **Speed Up** (up to ~8) accelerates training; it also supports parallel envs.
- **Reset strategy:** simplest is to reload the level scene on `needs_reset`. The
  first hands-on task is wiring reset cleanly with the plugin's multi-env model
  (reload vs reposition). Keep telemetry/scores gated off during training (reuse
  the `--sim`/`--capture` guards).

## Train, evaluate, export

```bash
source rl/.venv/bin/activate
gdrl --env_path=<exported_training_build> --experiment_name=moonlaunch_ppo --speedup=8
# evaluate the policy with the EXISTING harness (same parseable SIM_RESULT):
#   per level, load the ONNX policy instead of the heuristic and run --sim
# export ONNX for in-game inference (race mode + B-roll, no Python at runtime):
gdrl ... --onnx_export_path=rl/moonlaunch_policy.onnx
```

## Curriculum

Start on L1, add levels as it solves each (or sample by current failure rate).
Don't start on L11. Track win-rate per level with the harness sweep.
