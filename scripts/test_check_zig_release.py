import unittest
from unittest.mock import Mock, patch

import check_zig_release


class CheckZigReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.platforms = {
            "x86_64-linux": {"tarball": "https://example.com/zig.tar.xz"},
            "aarch64-macos": {"tarball": "https://example.com/zig-macos.tar.xz"},
            "x86_64-windows": {"tarball": "https://example.com/zig.zip"},
        }

    def check_index(self, index: dict, existing_tag: bool = False) -> tuple[Mock, Mock]:
        with (
            patch.object(check_zig_release, "fetch_index", return_value=index),
            patch.object(check_zig_release, "tag_exists", return_value=existing_tag) as tag_exists,
            patch.object(check_zig_release, "set_github_output") as output,
            patch.dict(check_zig_release.os.environ, {"GITHUB_REPOSITORY": "cataggar/zig"}),
        ):
            check_zig_release.main()
        return tag_exists, output

    def test_selects_latest_stable_version_numerically(self) -> None:
        tag_exists, output = self.check_index({
            "master": self.platforms | {"version": "0.18.0-dev.1+abc"},
            "0.9.0": self.platforms,
            "0.17.0": self.platforms | {"version": "0.17.0"},
            "0.16.0": self.platforms,
            "0.18.0-dev.1+abc": self.platforms,
        })

        tag_exists.assert_called_once_with("cataggar/zig", "v0.17.0")
        output.assert_called_once_with("new_versions", '["v0.17.0"]')

    def test_stable_entry_without_version_metadata(self) -> None:
        tag_exists, output = self.check_index({
            "master": self.platforms | {"version": "0.18.0-dev.1+abc"},
            "0.15.1": self.platforms,
        })

        tag_exists.assert_called_once_with("cataggar/zig", "v0.15.1")
        output.assert_called_once_with("new_versions", '["v0.15.1"]')

    def test_does_not_backfill_when_latest_stable_tag_exists(self) -> None:
        tag_exists, output = self.check_index({
            "master": self.platforms | {"version": "0.18.0-dev.1+abc"},
            "0.17.0": self.platforms,
            "0.16.0": self.platforms,
        }, existing_tag=True)

        tag_exists.assert_called_once_with("cataggar/zig", "v0.17.0")
        output.assert_called_once_with("new_versions", "")

    def test_development_only_index_does_not_publish(self) -> None:
        with self.assertLogs(check_zig_release.log, level="WARNING") as logs:
            tag_exists, output = self.check_index({
                "master": self.platforms | {"version": "0.18.0-dev.1+abc"},
                "0.18.0-dev.1+abc": self.platforms,
                "0.18.0-rc.1": self.platforms,
            })

        tag_exists.assert_not_called()
        output.assert_called_once_with("new_versions", "")
        self.assertIn("No stable releases found", logs.output[0])


if __name__ == "__main__":
    unittest.main()
