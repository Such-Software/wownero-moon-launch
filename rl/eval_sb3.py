"""Evaluate a trained policy (deterministic) in the godot_rl env. Pair with a Godot
client launched with RL_EVAL=1 so the rocket spawns at the level's NATURAL start
(no reverse-curriculum reposition). The Godot side logs landings ([RL] lines)."""
import argparse

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="rl/moonlaunch_ppo")
    ap.add_argument("--steps", type=int, default=30000)
    ap.add_argument("--speedup", type=int, default=8)
    ap.add_argument("--deterministic", type=int, default=1, help="1=greedy, 0=stochastic (matches the in-game opponent)")
    args = ap.parse_args()

    print(f"[eval] opening env; waiting for Godot (RL_EVAL=1, natural L1 start)...", flush=True)
    env = StableBaselinesGodotEnv(env_path=None, show_window=False, speedup=args.speedup)
    model = PPO.load(args.model)
    print(f"[eval] loaded {args.model}; running {args.steps} deterministic steps", flush=True)

    obs = env.reset()
    for _ in range(args.steps):
        action, _ = model.predict(obs, deterministic=bool(args.deterministic))
        obs, _, _, _ = env.step(action)
    env.close()
    print("[eval] done", flush=True)


if __name__ == "__main__":
    main()
