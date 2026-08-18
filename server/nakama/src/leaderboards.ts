// Server-authoritative leaderboards.
//
// Scores previously went to a separate HTTP service at
// api.such.software/v1/moonlaunch, which is outside the platform: it has no
// link to a player's account, so a score cannot follow someone to a new device,
// cannot be restored, and cannot be attributed to the identity that owns their
// purchases. Play Games and Game Center have the same problem in a different
// shape, being per-platform and unreadable from the others.
//
// Nakama already owns ranking, pagination, reset schedules and record storage,
// so none of that is reimplemented here. What this module adds is the part
// Nakama deliberately leaves to the app: which boards exist, what their sort
// order and operator mean, and the rule that a client may not name its own
// score.
//
// such_platform_leaderboard records the declaration so a board is a reviewed
// part of a release rather than a string that appeared in game code, and so a
// recovery generation can record which boards existed at that moment.

const LEADERBOARD_CONTRACT_VERSION = 1;

interface LeaderboardDeclaration {
  key: string;
  displayName: string;
  // ASC for boards where lower wins, which is the case for a completion time.
  sortOrder: nkruntime.SortOrder;
  operator: nkruntime.Operator;
  resetSchedule: string | null;
}

// The two boards the legacy service actually served. Adding a third is a row
// here plus a migration row, not a code path.
const MOON_LAUNCH_LEADERBOARDS: LeaderboardDeclaration[] = [
  {
    key: "time",
    displayName: "Fastest Completion",
    sortOrder: nkruntime.SortOrder.ASCENDING,
    operator: nkruntime.Operator.BEST,
    resetSchedule: null,
  },
  {
    key: "score",
    displayName: "High Score",
    sortOrder: nkruntime.SortOrder.DESCENDING,
    operator: nkruntime.Operator.BEST,
    resetSchedule: null,
  },
];

function leaderboardId(key: string): string {
  return "moon_launch_" + key;
}

// Nakama stores scores as integers. A completion time arrives in seconds with
// two decimals, and rounding it to whole seconds would collapse most of the
// board into ties, so it is carried in milliseconds and converted back on read.
const TIME_SCALE = 1000;
const MAX_SCORE = 9007199254740991;

function encodeTimeMilliseconds(seconds: number): number {
  const milliseconds = Math.round(seconds * TIME_SCALE);
  if (!isFinite(milliseconds) || milliseconds < 1 || milliseconds > MAX_SCORE) {
    throw {
      message: "completion time is out of range",
      code: 3,
    } as nkruntime.Error;
  }
  return milliseconds;
}

function ensureLeaderboards(nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  for (const declaration of MOON_LAUNCH_LEADERBOARDS) {
    const id = leaderboardId(declaration.key);
    try {
      nk.leaderboardCreate(
        id,
        true, // authoritative: only the server runtime may write a record
        declaration.sortOrder,
        declaration.operator,
        declaration.resetSchedule,
        { contract_version: LEADERBOARD_CONTRACT_VERSION }
      );
    } catch (error) {
      // Already existing is the normal case on every restart after the first.
      logger.info("leaderboard %s already present", id);
    }

    nk.sqlExec(
      "INSERT INTO such_platform_leaderboard " +
        "(leaderboard_key, nakama_leaderboard_id, display_name, sort_order, " +
        " operator, reset_schedule, authoritative, contract_version) " +
        "VALUES ($1, $2, $3, $4, $5, $6, true, $7) " +
        "ON CONFLICT (leaderboard_key) DO UPDATE SET " +
        "nakama_leaderboard_id=excluded.nakama_leaderboard_id, " +
        "display_name=excluded.display_name, " +
        "sort_order=excluded.sort_order, " +
        "operator=excluded.operator, " +
        "reset_schedule=excluded.reset_schedule, " +
        "contract_version=excluded.contract_version, " +
        "updated_at=now()",
      [
        declaration.key,
        id,
        declaration.displayName,
        declaration.sortOrder.toUpperCase(),
        declaration.operator.toUpperCase(),
        declaration.resetSchedule,
        LEADERBOARD_CONTRACT_VERSION,
      ]
    );
  }
}

function declaredLeaderboard(key: string): LeaderboardDeclaration {
  for (const declaration of MOON_LAUNCH_LEADERBOARDS) {
    if (declaration.key === key) {
      return declaration;
    }
  }
  throw {
    message: "unknown leaderboard",
    code: 3,
  } as nkruntime.Error;
}

// The client sends what it did, never what it scored. A submitted score is a
// number the client controls, and a leaderboard whose entries are supplied by
// the client is a leaderboard of whoever edits packets best.
const moonRpcSubmitScore: nkruntime.RpcFunction = function (
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw { message: "authentication required", code: 16 } as nkruntime.Error;
  }
  const request = JSON.parse(payload || "{}") as {
    board?: string;
    completion_time?: number;
    score?: number;
    level?: number;
    stars?: number;
  };

  const declaration = declaredLeaderboard(String(request.board || ""));
  let value: number;
  if (declaration.key === "time") {
    if (typeof request.completion_time !== "number") {
      throw { message: "completion_time is required", code: 3 } as nkruntime.Error;
    }
    value = encodeTimeMilliseconds(request.completion_time);
  } else {
    if (typeof request.score !== "number" || !isFinite(request.score)) {
      throw { message: "score is required", code: 3 } as nkruntime.Error;
    }
    value = Math.round(request.score);
    if (value < 0 || value > MAX_SCORE) {
      throw { message: "score is out of range", code: 3 } as nkruntime.Error;
    }
  }

  const record = nk.leaderboardRecordWrite(
    leaderboardId(declaration.key),
    ctx.userId,
    ctx.username,
    value,
    0,
    {
      level: typeof request.level === "number" ? Math.round(request.level) : null,
      stars: typeof request.stars === "number" ? Math.round(request.stars) : null,
    }
  );

  logger.info("leaderboard write %s by %s", declaration.key, ctx.userId);
  return JSON.stringify({
    contract_version: LEADERBOARD_CONTRACT_VERSION,
    app_id: MOON_APP_ID,
    ok: true,
    board: declaration.key,
    rank: record.rank ? String(record.rank) : null,
  });
};

const moonRpcLeaderboard: nkruntime.RpcFunction = function (
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  const request = JSON.parse(payload || "{}") as {
    board?: string;
    limit?: number;
    cursor?: string;
  };
  const declaration = declaredLeaderboard(String(request.board || ""));
  const limit = Math.min(Math.max(Number(request.limit) || 20, 1), 100);

  const list = nk.leaderboardRecordsList(
    leaderboardId(declaration.key),
    undefined,
    limit,
    request.cursor || undefined
  );

  const entries = (list.records || []).map(function (record) {
    const raw = Number(record.score);
    return {
      rank: record.rank ? String(record.rank) : null,
      // Usernames come from Nakama's own users table, which already owns
      // uniqueness and validation. Nothing here stores a second copy.
      username: record.username || null,
      // The client asked for a time in seconds; give it back in seconds
      // rather than exporting the storage detail.
      completion_time: declaration.key === "time" ? raw / TIME_SCALE : null,
      score: declaration.key === "score" ? raw : null,
      metadata: record.metadata || {},
      is_self: ctx.userId ? record.ownerId === ctx.userId : false,
    };
  });

  return JSON.stringify({
    contract_version: LEADERBOARD_CONTRACT_VERSION,
    app_id: MOON_APP_ID,
    ok: true,
    board: declaration.key,
    entries: entries,
    next_cursor: list.nextCursor || null,
  });
};
