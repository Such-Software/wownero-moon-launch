import json, numpy as np
from stable_baselines3 import PPO
m = PPO.load("rl/moonlaunch_ppo")
obs_dim = m.observation_space["obs"].shape[0]
rng = np.random.default_rng(42); cases=[]
for _ in range(500):
    obs = rng.uniform(-1,1,size=obs_dim).astype(np.float32)
    a,_ = m.predict({"obs": obs[None]}, deterministic=True)
    cases.append({"obs": obs.tolist(), "act": a[0].tolist()})
json.dump(cases, open("rl/policy_test_cases.json","w"))
print("wrote", len(cases), "test cases (obs_dim=%d)" % obs_dim)
