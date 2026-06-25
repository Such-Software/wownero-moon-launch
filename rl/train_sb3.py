"""PPO trainer for Such Moon Launch via godot_rl_agents.

Interactive mode (env_path=None): this process opens the RL server and waits for a
Godot instance running rl/train.tscn to connect (the Sync node connects to us).
Launch the Godot client separately (see rl/run_train.sh).
"""
import argparse

from godot_rl.wrappers.stable_baselines_wrapper import StableBaselinesGodotEnv
from stable_baselines3 import PPO
from stable_baselines3.common.callbacks import CheckpointCallback


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--timesteps", type=int, default=30000)
    ap.add_argument("--speedup", type=int, default=8)
    ap.add_argument("--env_path", default=None, help="exported binary; None = interactive editor/client mode")
    ap.add_argument("--n_parallel", type=int, default=1, help="number of exported game env processes")
    ap.add_argument("--port", type=int, default=11008, help="base port; each env uses port+index")
    ap.add_argument("--seed", type=int, default=1, help="base seed; each env uses seed+index")
    ap.add_argument("--save", default="rl/moonlaunch_ppo")
    ap.add_argument("--restore", default=None, help="path to a saved model .zip to continue")
    args = ap.parse_args()

    if args.n_parallel > 1 and not args.env_path:
        raise ValueError("--n_parallel > 1 requires --env_path to an exported training binary")

    print(
        f"[train] opening RL env (env_path={args.env_path}, n_parallel={args.n_parallel}, "
        f"speedup={args.speedup}, port={args.port})...",
        flush=True,
    )
    env = StableBaselinesGodotEnv(
        env_path=args.env_path,
        n_parallel=args.n_parallel,
        show_window=False,
        speedup=args.speedup,
        port=args.port,
        seed=args.seed,
    )
    print("[train] CONNECTED. obs:", env.observation_space, "| act:", env.action_space, flush=True)

    if args.restore:
        model = PPO.load(args.restore, env=env, tensorboard_log="rl/logs")
        print("[train] restored from", args.restore, flush=True)
    else:
        model = PPO(
            "MultiInputPolicy", env, verbose=1,
            n_steps=256, batch_size=64, ent_coef=0.01, gamma=0.999,
            tensorboard_log="rl/logs",
        )

    ckpt = CheckpointCallback(save_freq=50000, save_path="rl/checkpoints", name_prefix="moonlaunch")
    model.learn(args.timesteps, callback=ckpt, progress_bar=False)
    model.save(args.save)
    env.close()
    print("[train] DONE. saved", args.save, flush=True)


if __name__ == "__main__":
    main()
