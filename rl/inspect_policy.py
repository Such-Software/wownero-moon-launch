import argparse
from stable_baselines3 import PPO

ap = argparse.ArgumentParser()
ap.add_argument("--model", default="rl/moonlaunch_ppo_landing")
args = ap.parse_args()

m = PPO.load(args.model)
print("OBS SPACE :", m.observation_space)
print("ACT SPACE :", m.action_space)
print("\n=== policy module ===")
print(m.policy)
print("\n=== weight tensors (the exact layers to reimplement) ===")
for k, v in m.policy.state_dict().items():
    print(f"{k:45s} {tuple(v.shape)}")
