class_name RLPolicy
extends RefCounted
## Pure-GDScript inference for a small SB3 PPO MLP policy.
##
## Why not ONNX: godot_rl_agents' ONNX inference is C#/.NET (it loads ONNXInference.cs),
## and this is a standard-GDScript project shipping to Web/Android/iOS/Windows. A native
## onnxruntime GDExtension would have to be cross-compiled for every one of those. This
## policy is a tiny MLP (13 -> 64 -> 64 -> 5), so an exact GDScript forward pass runs
## identically on every platform with zero native deps. It is validated bit-for-bit
## against SB3's model.predict (see rl/export_policy.py + rl/validate_policy.gd).
##
## Architecture (from rl/export_policy.py): Linear(13,64) -> tanh -> Linear(64,64)
## -> tanh -> action_net Linear(64,5); the 5 logits split per MultiDiscrete([3,2])
## into dim0=rotate(3) and dim1=thrust(2).

var _nvec: Array = []
var _l0_w: Array = []
var _l0_b: Array = []
var _l1_w: Array = []
var _l1_b: Array = []
var _act_w: Array = []
var _act_b: Array = []
var loaded := false


## Load exported weights (res:// path, ships with the game).
func load_json(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("RLPolicy: cannot open " + path)
		return false
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("RLPolicy: bad JSON " + path)
		return false
	_nvec = data["nvec"]
	_l0_w = data["l0"]["w"]; _l0_b = data["l0"]["b"]
	_l1_w = data["l1"]["w"]; _l1_b = data["l1"]["b"]
	_act_w = data["act"]["w"]; _act_b = data["act"]["b"]
	loaded = true
	return true


func _layer(x: Array, w: Array, b: Array, activate: bool) -> Array:
	var out := []
	out.resize(w.size())
	for i in w.size():
		var row: Array = w[i]
		var s: float = b[i]
		for j in row.size():
			s += float(row[j]) * float(x[j])
		out[i] = tanh(s) if activate else s
	return out


func forward_logits(obs: Array) -> Array:
	var h := _layer(obs, _l0_w, _l0_b, true)
	h = _layer(h, _l1_w, _l1_b, true)
	return _layer(h, _act_w, _act_b, false)


## Returns one int per MultiDiscrete dim: [rotate(0..2), thrust(0..1)].
## deterministic -> argmax (matches SB3 deterministic=True); else softmax-sample
## (the stochastic mode = a varied opponent, never the same run twice).
func predict(obs: Array, deterministic: bool = false) -> Array:
	var logits := forward_logits(obs)
	var out := []
	var i := 0
	for n in _nvec:
		var seg: Array = logits.slice(i, i + int(n))
		out.append(_argmax(seg) if deterministic else _sample(seg))
		i += int(n)
	return out


func _argmax(a: Array) -> int:
	var best := 0
	for k in range(1, a.size()):
		if a[k] > a[best]:
			best = k
	return best


func _sample(logits: Array) -> int:
	# numerically stable softmax sample
	var mx: float = logits[0]
	for v in logits:
		mx = maxf(mx, v)
	var probs := []
	var tot := 0.0
	for v in logits:
		var e := exp(float(v) - mx)
		probs.append(e); tot += e
	var r := randf() * tot
	var acc := 0.0
	for k in probs.size():
		acc += probs[k]
		if r <= acc:
			return k
	return probs.size() - 1
