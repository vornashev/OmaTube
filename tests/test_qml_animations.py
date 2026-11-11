"""Exercise QML lifecycle, navigation and image sizing without changing the user's shell."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from qml_fixtures import image_fixture, panel_fixtures

ROOT = Path(__file__).resolve().parents[1]
RUNNER = shutil.which("qmltestrunner6") or shutil.which("qmltestrunner")
if RUNNER is None and Path("/usr/lib/qt6/bin/qmltestrunner").exists():
    RUNNER = "/usr/lib/qt6/bin/qmltestrunner"


@unittest.skipUnless(RUNNER, "Qt Quick Test is not installed")
class IdleAnimationTests(unittest.TestCase):
    def test_headless_ui_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix="omatube-qml-test-") as tmp:
            # Theme values, page bodies and external services are stand-ins.
            # The panel, widget logic, loaders, images and animations are real.
            commons = Path(tmp) / "qs" / "Commons"
            commons.mkdir(parents=True)
            (commons / "qmldir").write_text(
                "module qs.Commons\nsingleton Color 1.0 Color.qml\n"
                "singleton Style 1.0 Style.qml\n"
            )
            (commons / "Color.qml").write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { '
                'property color accent: "white"; property color foreground: "white"; '
                'property color urgent: "red"; property color background: "black"; '
                'property QtObject popups: QtObject { property color background: "black" } }\n'
            )
            (commons / "Style.qml").write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { function space(n) { return n }\n'
                'property int cornerRadius: 4; property var font: ({ family: "Sans", bodySmall: 12, caption: 10, body: 14 }) }\n'
            )
            ui = Path(tmp) / "qs" / "Ui"
            ui.mkdir()
            (ui / "qmldir").write_text("module qs.Ui\nPanelToolTip 1.0 PanelToolTip.qml\n")
            (ui / "PanelToolTip.qml").write_text(
                'import QtQuick\nItem { property string text: ""; property string fontFamily: "" }\n'
            )
            panel_fixtures(Path(tmp), ROOT, ui)
            server = image_fixture(ui)
            try:
                for scale in ("1", "2"):
                    with self.subTest(display_scale=scale):
                        result = subprocess.run(
                            [RUNNER, "-platform", "offscreen", "-import", tmp,
                             "-input", str(Path(tmp) / "tests/qml")],
                            capture_output=True, text=True, timeout=30,
                            env={**os.environ, "QML_DISABLE_DISK_CACHE": "1",
                                 "QT_SCALE_FACTOR": scale, "QT_QUICK_BACKEND": "software"},
                        )
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            finally:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    unittest.main()
