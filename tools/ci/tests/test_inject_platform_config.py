"""Contract for the App Platform config injection.

The failure this guards against is a build that looks fine and ships a client
which cannot reach its own runtime, because the settings it reads were never
written. That failure is invisible until someone installs the app.
"""

from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


def _load():
    spec = importlib.util.spec_from_file_location(
        "inject_platform_config", ROOT / "tools/ci/inject_platform_config.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


inject = _load()

GOOD = {
    "SUCH_APP_IDP_TICKET_URL": "https://id.wowne.ro/nakama/ticket",
    "SUCH_APP_NAKAMA_ENDPOINT": "https://api.moonlaunch.space",
    "SUCH_APP_NAKAMA_SERVER_KEY": "a" * 32,
}

PROJECT = """; Engine configuration file.
config_version=5

[application]

config/name="Such Moon Launch"
"""


class InjectionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.saved = {k: os.environ.get(k) for k in inject.REQUIRED}
        for key, value in GOOD.items():
            os.environ[key] = value

    def tearDown(self) -> None:
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def _project(self, body: str = PROJECT) -> Path:
        handle = tempfile.NamedTemporaryFile(
            "w", suffix=".godot", delete=False, encoding="utf-8"
        )
        handle.write(body)
        handle.close()
        return Path(handle.name)

    def test_settings_match_the_names_the_client_reads(self) -> None:
        source = (ROOT / "game/platform/PlatformSession.gd").read_text(encoding="utf-8")
        # The client builds the setting name by lowercasing the env name, so the
        # two must agree exactly or the value is written where nothing looks.
        self.assertIn('"such/app_platform/%s" % env_name.to_lower()', source)
        for name in inject.REQUIRED:
            with self.subTest(name=name):
                self.assertIn(f'"{name}"', source)

    def test_a_good_configuration_is_written(self) -> None:
        project = self._project()
        inject.inject(project, inject.read_values(release=True))
        text = project.read_text(encoding="utf-8")
        self.assertIn("[such]", text)
        self.assertIn(
            'app_platform/such_app_nakama_endpoint="https://api.moonlaunch.space"', text
        )
        self.assertIn(
            'app_platform/such_app_idp_ticket_url="https://id.wowne.ro/nakama/ticket"',
            text,
        )
        project.unlink()

    def test_a_missing_value_stops_the_build(self) -> None:
        for name in inject.REQUIRED:
            with self.subTest(name=name):
                os.environ[name] = ""
                with self.assertRaises(SystemExit):
                    inject.read_values(release=True)
                os.environ[name] = GOOD[name]

    def test_a_release_refuses_plaintext(self) -> None:
        os.environ["SUCH_APP_NAKAMA_ENDPOINT"] = "http://api.moonlaunch.space"
        with self.assertRaises(SystemExit):
            inject.read_values(release=True)
        # The same value is fine for a local build that never leaves the machine.
        self.assertTrue(inject.read_values(release=False))

    def test_a_malformed_endpoint_is_refused(self) -> None:
        for bad in (
            "https://api.moonlaunch.space/",
            "https://api.moonlaunch.space/path",
            "api.moonlaunch.space",
            "https://api.moonlaunch.space?x=1",
        ):
            with self.subTest(bad=bad):
                os.environ["SUCH_APP_NAKAMA_ENDPOINT"] = bad
                with self.assertRaises(SystemExit):
                    inject.read_values(release=True)

    def test_errors_never_echo_the_server_key(self) -> None:
        # Must fail the shape check, or nothing is raised and the test proves
        # nothing. The "!" is what makes it invalid.
        secret = "this-should-never-appear-in-output!!"
        os.environ["SUCH_APP_NAKAMA_SERVER_KEY"] = secret
        with self.assertRaises(SystemExit) as caught:
            inject.read_values(release=True)
        self.assertNotIn(secret, str(caught.exception))

    def test_an_existing_section_is_not_merged_into(self) -> None:
        project = self._project(PROJECT + "\n[such]\n\napp_platform/other=\"x\"\n")
        with self.assertRaises(SystemExit):
            inject.inject(project, inject.read_values(release=True))
        project.unlink()


if __name__ == "__main__":
    unittest.main()
