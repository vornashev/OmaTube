"""Check the real Quickshell socket/parser, not just the headless stand-ins."""
import asyncio
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest

from backend.events import StateEvents


@unittest.skipUnless(shutil.which("quickshell"), "Quickshell is not installed")
class NativeEventsTests(unittest.IsolatedAsyncioTestCase):
    async def test_native_widget_receives_state_without_cli_polling(self):
        project = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="omatube-native-events-") as tmp:
            root = Path(tmp)
            (root / "omatube").mkdir()
            for name in ["WidgetLogic.qml", "PlayerState.qml", "RetainedLoader.qml", "i18n.js"]:
                shutil.copy2(project / "ui" / name, root / name)
            widget = root / "WidgetLogic.qml"
            widget.write_text(widget.read_text().replace(
                'bootstrapProcess.command = [pluginDir + "/bootstrap.sh"]',
                'bootstrapProcess.command = ["/usr/bin/true"]').replace(
                    'objectName: "panelLoader"', 'objectName: "panelLoader"\n    asynchronous: true'))
            (root / "Panel.qml").write_text('''import QtQuick
Item {
  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  property var logic: null
  property bool opened: false
  property int opens: 0
  function open() { opens += 1; opened = true }
  function close() { opened = false }
}
''')
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  WidgetLogic { id: logic }
  Connections {
    target: logic.stateData
    function onPositionChanged() {
      if (logic.stateData.position === 42) logic.open()
    }
  }
  Connections {
    target: logic
    function onOpenedChanged() {
      if (logic.opened) Qt.callLater(function() {
        if (logic.children[0].item.opens === 1) console.warn("NATIVE_STREAM_OK")
      })
    }
  }
}
''')
            connected = asyncio.Event()
            state = {"backendSessionId": "test", "position": 0, "state": "paused"}
            events = StateEvents(lambda options, known: state, interval=0.01)
            async def handle(reader, writer):
                try:
                    request = json.loads(await reader.readline())
                    connected.set()
                    await events.serve(reader, writer, request)
                finally:
                    writer.close()
                    await writer.wait_closed()
            server = await asyncio.start_unix_server(handle, root / "omatube/backend.sock")
            process = await asyncio.create_subprocess_exec(
                shutil.which("quickshell"), "-p", str(root), "--no-color",
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
                env={**os.environ, "XDG_RUNTIME_DIR": str(root), "QT_QPA_PLATFORM": "offscreen",
                     "QS_DISABLE_FILE_WATCHER": "1", "QML_DISABLE_DISK_CACHE": "1"},
            )
            output = []
            async def success():
                while line := await process.stdout.readline():
                    output.append(line.decode(errors="replace"))
                    if "NATIVE_STREAM_OK" in output[-1]:
                        return
                raise AssertionError("Quickshell exited: " + "".join(output))
            monitor = asyncio.create_task(success())
            try:
                await asyncio.wait_for(connected.wait(), 8)
                state["position"] = 42
                events.notify()
                await asyncio.wait_for(asyncio.shield(monitor), 8)
            except TimeoutError:
                self.fail("No native socket update: " + "".join(output))
            finally:
                monitor.cancel()
                await asyncio.gather(monitor, return_exceptions=True)
                if process.returncode is None:
                    process.terminate()
                await asyncio.wait_for(process.wait(), 5)
                await events.stop()
                server.close()
                await server.wait_closed()
