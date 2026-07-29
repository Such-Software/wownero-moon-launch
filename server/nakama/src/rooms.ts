var MOON_ROOM_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
var MOON_ROOM_PROTOCOL_VERSION = 1;
var MOON_ROOM_TTL_SECONDS = 10 * 60;
var MOON_ROOM_MAX_PLAYERS = 2;

interface MoonRoomRegistration {
  match_id: string;
  protocol_version: number;
  max_players: number;
}

function moonRequireUser(ctx: nkruntime.Context): string {
  if (!ctx.userId || !/^[0-9a-f-]{36}$/.test(ctx.userId)) {
    throw moonError("Authentication required.", nkruntime.Codes.UNAUTHENTICATED);
  }
  return ctx.userId;
}

function moonRandomRoomCode(bytes: ArrayBuffer): string {
  var input = new Uint8Array(bytes);
  var code = "";
  var index;
  for (index = 0; index < input.length && code.length < 6; index += 1) {
    // The alphabet has 32 symbols, so modulo mapping introduces no bias.
    code += MOON_ROOM_CODE_ALPHABET.charAt(
      input[index] % MOON_ROOM_CODE_ALPHABET.length
    );
  }
  if (!/^[A-HJ-NP-Z2-9]{6}$/.test(code)) {
    throw moonError("Room code generation failed.", nkruntime.Codes.INTERNAL);
  }
  return code;
}

function moonParseRoomRegistration(payload: string): MoonRoomRegistration {
  if (!moonIsBoundedString(payload, 2, 1024)) {
    throw moonError(
      "Room registration is invalid.",
      nkruntime.Codes.INVALID_ARGUMENT
    );
  }
  var value = moonParseObject(payload, "Room registration");
  if (!moonHasExactKeys(
    value,
    ["match_id", "protocol_version", "max_players"],
    []
  ) ||
      !moonIsOpaqueString(value.match_id, 8, 256) ||
      !/^[A-Za-z0-9._:-]+$/.test(value.match_id) ||
      value.protocol_version !== MOON_ROOM_PROTOCOL_VERSION ||
      value.max_players !== MOON_ROOM_MAX_PLAYERS) {
    throw moonError("Room registration is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  return value as MoonRoomRegistration;
}

function moonParseRoomCode(payload: string, label: string): string {
  if (!moonIsBoundedString(payload, 2, 128)) {
    throw moonError(label + " is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  var value = moonParseObject(payload, label);
  if (!moonHasExactKeys(value, ["room_code"], []) ||
      typeof value.room_code !== "string" ||
      !/^[A-HJ-NP-Z2-9]{6}$/.test(value.room_code)) {
    throw moonError(label + " is invalid.", nkruntime.Codes.INVALID_ARGUMENT);
  }
  return value.room_code;
}

function moonHasPremium(
  nk: nkruntime.Nakama,
  userId: string
): boolean {
  var rows = nk.sqlQuery(
    "SELECT 1 AS found FROM such_platform_entitlement e " +
      "JOIN such_platform_identity i ON i.subject_id = e.subject_id " +
      "WHERE i.nakama_user_id = $1::uuid " +
      "AND e.entitlement_key = 'premium' " +
      "AND e.operation IN ('GRANT', 'REINSTATE') " +
      "AND e.effective_at <= now() " +
      "AND (e.expires_at IS NULL OR e.expires_at > now())",
    [userId]
  );
  return rows.length === 1;
}

function moonRoomDescriptor(row: MoonJsonObject): MoonJsonObject {
  var expiry = new Date(row.expires_at);
  if (isNaN(expiry.getTime())) {
    throw moonError("Room state is invalid.", nkruntime.Codes.INTERNAL);
  }
  return {
    room_code: row.room_code,
    match_id: row.match_id,
    protocol_version: Number(row.protocol_version),
    max_players: Number(row.max_players),
    expires_at: expiry.toISOString()
  };
}

function moonRpcRoomRegister(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  var userId = moonRequireUser(ctx);
  if (!moonHasPremium(nk, userId)) {
    throw moonError(
      "Premium capability is required to host a room.",
      nkruntime.Codes.PERMISSION_DENIED
    );
  }
  var registration = moonParseRoomRegistration(payload);
  var match = nk.matchGet(registration.match_id);
  if (!match ||
      match.authoritative ||
      match.size !== 1 ||
      match.matchId !== registration.match_id) {
    throw moonError("Relayed room is unavailable.", nkruntime.Codes.NOT_FOUND);
  }

  nk.sqlExec(
    "UPDATE such_moon_launch_friendly_room " +
      "SET state = 'EXPIRED', closed_at = COALESCE(closed_at, now()), " +
      "updated_at = now() " +
      "WHERE state = 'OPEN' AND expires_at <= now()",
    []
  );
  var existing = nk.sqlQuery(
    "SELECT * FROM such_moon_launch_friendly_room " +
      "WHERE match_id = $1 AND host_user_id = $2::uuid " +
      "AND state = 'OPEN' AND expires_at > now()",
    [registration.match_id, userId]
  );
  if (existing.length === 1) {
    return JSON.stringify(moonRoomDescriptor(existing[0]));
  }

  var expiresAt =
    new Date(Date.now() + MOON_ROOM_TTL_SECONDS * 1000).toISOString();
  var attempt;
  for (attempt = 0; attempt < 8; attempt += 1) {
    var roomCode = moonRandomRoomCode(nk.secureRandomBytes(6));
    var rows = nk.sqlQuery(
      "INSERT INTO such_moon_launch_friendly_room " +
        "(room_code, match_id, host_user_id, protocol_version, " +
        "max_players, expires_at) " +
        "VALUES ($1, $2, $3::uuid, $4, $5, $6::timestamptz) " +
        "ON CONFLICT DO NOTHING RETURNING *",
      [
        roomCode,
        registration.match_id,
        userId,
        registration.protocol_version,
        registration.max_players,
        expiresAt
      ]
    );
    if (rows.length === 1) {
      return JSON.stringify(moonRoomDescriptor(rows[0]));
    }
    existing = nk.sqlQuery(
      "SELECT * FROM such_moon_launch_friendly_room " +
        "WHERE match_id = $1 AND host_user_id = $2::uuid " +
        "AND state = 'OPEN' AND expires_at > now()",
      [registration.match_id, userId]
    );
    if (existing.length === 1) {
      return JSON.stringify(moonRoomDescriptor(existing[0]));
    }
  }
  throw moonError(
    "Room code capacity is temporarily exhausted.",
    nkruntime.Codes.RESOURCE_EXHAUSTED
  );
}

function moonRpcRoomResolve(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  var userId = moonRequireUser(ctx);
  var roomCode = moonParseRoomCode(payload, "Room code");
  var existing = nk.sqlQuery(
    "SELECT * FROM such_moon_launch_friendly_room " +
      "WHERE room_code = $1 AND state = 'OPEN' AND expires_at > now()",
    [roomCode]
  );
  if (existing.length !== 1) {
    throw moonError(
      "Room code is expired or unavailable.",
      nkruntime.Codes.NOT_FOUND
    );
  }
  var match = nk.matchGet(existing[0].match_id);
  if (!match ||
      match.authoritative ||
      match.size >= MOON_ROOM_MAX_PLAYERS ||
      match.matchId !== existing[0].match_id) {
    throw moonError(
      "Room is unavailable or full.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  var rows = nk.sqlQuery(
    "UPDATE such_moon_launch_friendly_room " +
      "SET guest_user_id = COALESCE(guest_user_id, $2::uuid), " +
      "updated_at = now() " +
      "WHERE room_code = $1 AND state = 'OPEN' AND expires_at > now() " +
      "AND host_user_id <> $2::uuid " +
      "AND (guest_user_id IS NULL OR guest_user_id = $2::uuid) " +
      "RETURNING *",
    [roomCode, userId]
  );
  if (rows.length !== 1) {
    throw moonError(
      "Room is unavailable or full.",
      nkruntime.Codes.FAILED_PRECONDITION
    );
  }
  return JSON.stringify(moonRoomDescriptor(rows[0]));
}

function moonRpcRoomClose(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  var userId = moonRequireUser(ctx);
  var roomCode = moonParseRoomCode(payload, "Room close request");
  var result = nk.sqlExec(
    "UPDATE such_moon_launch_friendly_room " +
      "SET state = 'CLOSED', closed_at = now(), updated_at = now() " +
      "WHERE room_code = $1 AND host_user_id = $2::uuid AND state = 'OPEN'",
    [roomCode, userId]
  );
  if (result.rowsAffected !== 1) {
    throw moonError("Room was not found for this host.", nkruntime.Codes.NOT_FOUND);
  }
  return JSON.stringify({closed: true});
}
