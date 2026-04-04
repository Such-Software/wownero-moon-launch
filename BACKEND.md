# Backend Integration

How Wownero Moon Launch talks to the server.

> **API Base**: `https://api.such.software/v1/moonlaunch`
> **Backend Repo**: [such.software-apps-backend](https://github.com/Such-Software/such.software-apps-backend)
> **Server**: `163.245.212.18` (`api.such.software`), Debian 13, PostgreSQL 17, Python 3.13 / Flask 3.1

---

## Game-Side Files

| File | Autoload | Purpose |
|------|----------|---------|
| `game/net/ScoreClient.gd` | `ScoreClient` | Leaderboard submit, fetch, rank |
| `game/net/CloudSave.gd` | `CloudSave` | Cloud save upload/download |
| `game/net/AdManager.gd` | `AdManager` | Ad abstraction (not backend-related) |

All three are registered in `project.godot` under `[autoload]`.

---

## Endpoints Used

### Leaderboard (ScoreClient.gd)

| Action | Method | Path | Auth |
|--------|--------|------|------|
| Submit score | `POST` | `/scores` | HMAC |
| Get leaderboard | `GET` | `/scores?level=&limit=&device_uuid=` | None |
| Get player rank | `GET` | `/rank?level=&device_uuid=` | None |

**Submit payload:**
```json
{
  "device_uuid": "uuid-v4",
  "nickname": "MoonWhale",
  "level": 1,
  "completion_time": 25.5,
  "fuel_remaining": 42.0,
  "crypto_collected": 15,
  "stars": 2,
  "platform": "ANDROID"
}
```

### Cloud Save (CloudSave.gd)

| Action | Method | Path | Auth |
|--------|--------|------|------|
| Upload save | `PUT` | `/save` | HMAC |
| Download save | `GET` | `/save?device_uuid=` | None |

**Upload payload:**
```json
{
  "device_uuid": "uuid-v4",
  "nickname": "MoonWhale",
  "save_data": { "wallet": 500, "upgrades": { "thrust": 2 }, "..." : "..." },
  "platform": "ANDROID"
}
```

**Download response:**
```json
{
  "status": "ok",
  "save_data": { "wallet": 500, "upgrades": { "thrust": 2 }, "..." : "..." }
}
```

Returns HTTP 404 `{"error": "No save found"}` if no cloud save exists for that UUID.

---

## HMAC Signing

All `POST` and `PUT` requests are signed with HMAC-SHA256.

### How it works

1. Get the hex-encoded secret from `ScoreClient._get_hmac_secret()`
2. Get current unix timestamp as string
3. Compute `HMAC-SHA256(hex_decode(secret), timestamp_bytes + body_bytes)`
4. Send as headers: `X-Timestamp` (epoch string) and `X-Signature` (hex digest)

### Server verification

- Recomputes the HMAC and uses constant-time comparison
- Rejects timestamps older than **5 minutes** (replay protection)
- If `HMAC_SECRET` env var is empty (dev mode), verification is skipped

### Game code (ScoreClient.gd)

```gdscript
var ctx := HMACContext.new()
ctx.start(HashingContext.HASH_SHA256, secret_hex.hex_decode())
ctx.update(timestamp.to_utf8_buffer())
ctx.update(body_bytes)
var signature := ctx.finish().hex_encode()
```

CloudSave.gd reuses `ScoreClient._sign()` and `ScoreClient._get_hmac_secret()` — the secret is in one place.

---

## Cloud Save Flow

### Upload (automatic)

Every call to `globalvar.save_game()` triggers a fire-and-forget cloud upload:

```
save_game() → write savegame.json locally → CloudSave.upload_save()
												 ↓
										  PUT /save (HMAC-signed)
												 ↓
										  Server upserts JSONB
```

Triggered on: level completion, upgrade purchase, skin unlock, difficulty change.

### Download (on demand)

```
globalvar.restore_from_cloud()
		 ↓
  CloudSave.download_save()
		 ↓
  GET /save?device_uuid=...
		 ↓
  _on_cloud_save_downloaded() → _apply_save_data() → save_game()
```

Only overwrites local state if the cloud copy has more progress (higher `highest_completed` or `wallet`).

### What's saved

| Field | Type | Description |
|-------|------|-------------|
| `level` | int | Next level to play |
| `highest_completed` | int | Furthest level beaten |
| `completed` | bool | Beat all 11 story levels? |
| `wallet` | int | Moonrocks balance |
| `upgrades` | dict | All 10 upgrade levels (thrust, fuel, armor, etc.) |
| `best_times` | dict | Best time per level (`{"1": 25.3, "2": 42.1}`) |
| `best_stars` | dict | Best star rating per level (`{"1": 3, "2": 2}`) |
| `device_uuid` | string | UUID v4, generated once on first launch |
| `nickname` | string | Random crypto-themed name (e.g. "SatoshiPilot") |
| `tutorial_shown` | bool | Level 1 tutorial seen? |
| `difficulty` | int | 0=Easy, 1=Normal, 2=Hard |
| `selected_skin` | string | Current ship skin ID |
| `owned_skins` | array | List of purchased skin IDs |
| `total_deaths` | int | Lifetime death count |
| `total_crypto_earned` | int | Lifetime Moonrocks earned (never decreases) |
| `best_wave` | int | Best endless mode wave reached |
| `levels_unlocked` | bool | All levels unlocked flag |

---

## Local Dev Setup

To test against a local backend:

1. Clone the backend repo and follow its README for local setup
2. Change `API_BASE` in both `ScoreClient.gd` and `CloudSave.gd`:
   ```gdscript
   const API_BASE := "http://127.0.0.1:8080/v1/moonlaunch"
   ```
3. Run the game — HMAC verification is skipped when `HMAC_SECRET` is empty on the server

To test against production, leave `API_BASE` as `https://api.such.software/v1/moonlaunch`.

---

## Server-Side Validation

The backend rejects invalid submissions:

| Check | Rule |
|-------|------|
| Min time per level | L1: 3s, L2: 5s, L3: 8s, L4: 10s |
| Max time | 600s |
| Fuel range | 0–100% |
| Crypto range | 0–10,000 per run |
| Stars range | 1–3 |
| Level range | 1–20 |
| UUID format | Valid UUID v4 |
| Nickname | Alphanumeric + space/underscore/hyphen, max 20 chars |
| Dedup | Same player + level + exact score = upsert |
| Save size | Max 64 KB |

---

## Deployment

See the backend repo's README for full deployment instructions. Quick summary:

```bash
ssh root@163.245.212.18
cd /opt/such-software-api
git pull origin master
sudo systemctl restart such-software-api
```

For new migrations, also run the SQL and grant permissions (see backend README).
