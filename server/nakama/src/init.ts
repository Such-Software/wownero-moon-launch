function InitModule(
  _ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerBeforeAuthenticateCustom(moonBeforeAuthenticateCustom);
  initializer.registerAfterAuthenticateCustom(moonAfterAuthenticateCustom);
  initializer.registerRpc("app_platform_health", moonRpcHealth);
  initializer.registerRpc("app_platform_readiness", moonRpcReadiness);
  initializer.registerRpc("app_platform_build_info", moonRpcBuildInfo);
  initializer.registerRpc("app_platform_entitlements", moonRpcEntitlements);
  initializer.registerRpc(
    "app_platform_prepare_guest_claim",
    moonRpcPrepareGuestClaim
  );
  initializer.registerRpc("app_platform_claim_guest", moonRpcClaimGuest);
  initializer.registerRpc("app_platform_validate_iap", moonRpcValidateIap);
  initializer.registerRpc(
    "app_entitlement_projection",
    moonRpcEntitlementProjection
  );
  initializer.registerRpc(
    "app_platform_currency_balance",
    moonRpcCurrencyBalance
  );
  initializer.registerRpc(
    "app_currency_projection",
    moonRpcCurrencyProjection
  );
  initializer.registerRpc(
    "moon_launch_room_register",
    moonRpcRoomRegister
  );
  initializer.registerRpc(
    "moon_launch_room_resolve",
    moonRpcRoomResolve
  );
  initializer.registerRpc(
    "moon_launch_room_close",
    moonRpcRoomClose
  );
}
