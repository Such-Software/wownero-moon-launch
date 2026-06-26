extends SceneTree
func _init():
	var pol = load("res://game/ai/RLPolicy.gd").new()
	if not pol.load_json("res://rl/landing_policy.json"):
		print("[VALIDATE] FAILED to load policy"); quit(1); return
	var f := FileAccess.open("res://rl/policy_test_cases.json", FileAccess.READ)
	var cases = JSON.parse_string(f.get_as_text()); f.close()
	var fail := 0
	for c in cases:
		var got = pol.predict(c["obs"], true)
		var exp = c["act"]
		if int(got[0]) != int(exp[0]) or int(got[1]) != int(exp[1]):
			fail += 1
			if fail <= 5: print("  MISMATCH got=", got, " exp=", exp)
	print("[VALIDATE] %d/%d mismatches  (0 = GDScript inference == SB3, EXACT)" % [fail, cases.size()])
	quit(0 if fail == 0 else 1)
