#!/usr/bin/env python3
"""Unit checks for idempotent TestFlight internal-group distribution."""

from __future__ import annotations

import unittest
from typing import Any

from app_store_connect import AppStoreConnectError, distribute_to_group


GROUP_ID = "group-id"
APP_ID = "app-id"
BUILD_ID = "build-id"


class FakeClient:
    def __init__(
        self,
        *,
        all_builds: bool = False,
        related_builds: list[dict[str, str]] | None = None,
    ) -> None:
        self.all_builds = all_builds
        self.related_builds = related_builds if related_builds is not None else []
        self.requests: list[tuple[str, str, dict[str, Any]]] = []

    def request(
        self,
        method: str,
        path: str,
        *,
        query: dict[str, str] | None = None,
        body: dict[str, Any] | None = None,
        expected_status: int = 200,
    ) -> dict[str, Any] | None:
        self.requests.append(
            (
                method,
                path,
                {
                    "query": query,
                    "body": body,
                    "expected_status": expected_status,
                },
            )
        )
        if method == "GET" and path == f"/v1/betaGroups/{GROUP_ID}":
            return {
                "data": {
                    "type": "betaGroups",
                    "id": GROUP_ID,
                    "attributes": {
                        "name": "Internal testers",
                        "isInternalGroup": True,
                        "hasAccessToAllBuilds": self.all_builds,
                    },
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": APP_ID}}
                    },
                }
            }
        if method == "GET" and path.endswith("/relationships/builds"):
            return {"data": self.related_builds}
        if method == "POST" and path.endswith("/relationships/builds"):
            if expected_status != 204:
                raise AssertionError("distribution POST must require HTTP 204")
            return None
        raise AssertionError(f"unexpected request: {method} {path}")


class DistributionTests(unittest.TestCase):
    def test_all_builds_group_skips_manual_assignment(self) -> None:
        client = FakeClient(all_builds=True)

        group = distribute_to_group(client, GROUP_ID, APP_ID, BUILD_ID)

        self.assertEqual(group["id"], GROUP_ID)
        self.assertEqual([request[0] for request in client.requests], ["GET"])

    def test_existing_assignment_is_idempotent(self) -> None:
        client = FakeClient(
            related_builds=[{"type": "builds", "id": BUILD_ID}]
        )

        distribute_to_group(client, GROUP_ID, APP_ID, BUILD_ID)

        self.assertEqual(
            [request[0] for request in client.requests],
            ["GET", "GET"],
        )

    def test_unassigned_build_is_added_once(self) -> None:
        client = FakeClient()

        distribute_to_group(client, GROUP_ID, APP_ID, BUILD_ID)

        self.assertEqual(
            [request[0] for request in client.requests],
            ["GET", "GET", "POST"],
        )
        post = client.requests[-1][2]
        self.assertEqual(
            post["body"],
            {"data": [{"type": "builds", "id": BUILD_ID}]},
        )

    def test_malformed_relationship_fails_closed(self) -> None:
        client = FakeClient(related_builds=[{"type": "not-builds", "id": BUILD_ID}])

        with self.assertRaises(AppStoreConnectError):
            distribute_to_group(client, GROUP_ID, APP_ID, BUILD_ID)


if __name__ == "__main__":
    unittest.main()
