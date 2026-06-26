"""Export an SB3 PPO policy to JSON (exact MLP weights) for pure-GDScript in-game
inference, and VALIDATE a numpy reimplementation matches model.predict bit-for-bit.
Pure-GDScript is the only zero-native-dep path that runs on Web/Android/iOS (the
plugin's ONNX inference is C#/.NET, incompatible with this GDScript project)."""
import argparse, json
import numpy as np
from stable_baselines3 import PPO

ap = argparse.ArgumentParser()
ap.add_argument("--model", default="rl/moonlaunch_ppo_landing")
ap.add_argument("--out", default="rl/landing_policy.json")
args = ap.parse_args()

m = PPO.load(args.model)
sd = m.policy.state_dict()
def W(k): return sd[k].cpu().numpy().astype(np.float64)
w0,b0 = W("mlp_extractor.policy_net.0.weight"), W("mlp_extractor.policy_net.0.bias")
w2,b2 = W("mlp_extractor.policy_net.2.weight"), W("mlp_extractor.policy_net.2.bias")
wa,ba = W("action_net.weight"), W("action_net.bias")
nvec = m.action_space.nvec.tolist()

def logits(obs):
    h = np.tanh(w0 @ obs + b0); h = np.tanh(w2 @ h + b2)
    return wa @ h + ba
def np_predict(obs):
    L = logits(obs); out=[]; i=0
    for n in nvec: out.append(int(np.argmax(L[i:i+n]))); i+=n
    return out

rng = np.random.default_rng(0); mism=0; N=3000
for _ in range(N):
    obs = rng.uniform(-1,1,size=13).astype(np.float32)
    a_sb,_ = m.predict({"obs": obs[None]}, deterministic=True)
    if np_predict(obs.astype(np.float64)) != a_sb[0].tolist():
        mism+=1
print(f"VALIDATION (numpy reimpl vs SB3 predict): {mism}/{N} mismatches  [0 = EXACT]")
print(f"action mapping: MultiDiscrete{nvec} -> dim0=rotate(3), dim1=thrust(2)")

json.dump({"nvec":nvec,
           "l0":{"w":w0.tolist(),"b":b0.tolist()},
           "l1":{"w":w2.tolist(),"b":b2.tolist()},
           "act":{"w":wa.tolist(),"b":ba.tolist()}}, open(args.out,"w"))
print("wrote", args.out, f"({len(json.dumps(json.load(open(args.out))))//1024} KB)")
