class_name AppPlatformFeatures
extends RefCounted
## Compile-time App Platform rollout gates.
##
## These stay closed until linked evidence and provisioned identifiers land in
## a reviewed promotion commit. Do not replace them with remotely mutable
## values in official mobile builds.

const SHARED_IDENTITY_ENABLED := false
const NAKAMA_ENABLED := false
const ENTITLEMENTS_ENABLED := false
const FRIENDLY_LAUNCH_ROOM_ENABLED := false
const MEDUSA_SHOP_LINK_ENABLED := false
const NEARBY_P2P_ENABLED := false


static func all_closed() -> bool:
	return not (
		SHARED_IDENTITY_ENABLED
		or NAKAMA_ENABLED
		or ENTITLEMENTS_ENABLED
		or FRIENDLY_LAUNCH_ROOM_ENABLED
		or MEDUSA_SHOP_LINK_ENABLED
		or NEARBY_P2P_ENABLED
	)
