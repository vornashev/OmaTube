"""Small shell stand-ins for headless tests of the real panel and image loader."""
import http.server
import json
import re
from pathlib import Path
import shutil
import struct
import threading
import zlib


def panel_fixtures(root: Path, project: Path, ui_module: Path):
    shutil.copytree(project / "ui", root / "ui")
    shutil.copytree(project / "tests/qml", root / "tests/qml")
    qs = ui_module.parent.parent / "Quickshell"
    qs.mkdir()
    (qs / "qmldir").write_text(
        "module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\nLazyLoader 1.0 LazyLoader.qml\n"
    )
    (qs / "Quickshell.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { function env(name) { return "/tmp" } }\n'
    )
    # Quickshell's built-in LazyLoader is not a QtQuick.Loader. Keep the
    # colliding name exported so accidentally using it is caught by this test.
    (qs / "LazyLoader.qml").write_text("import QtQuick\nQtObject {}\n")
    io = qs / "Io"
    io.mkdir()
    (io / "qmldir").write_text("module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\nSocket 1.0 Socket.qml\nSplitParser 1.0 SplitParser.qml\n")
    (io / "Socket.qml").write_text('''import QtQuick
QtObject {
  property string path: ""
  property bool connected: false
  property QtObject parser: null
  property var messages: []
  signal error(var error)
  function write(data) { messages.push(data) }
  function flush() {}
}
''')
    (io / "SplitParser.qml").write_text('import QtQuick\nQtObject { signal read(string data) }\n')
    (io / "Process.qml").write_text('''import QtQuick
QtObject {
  id: process
  property var command: []
  property bool running: false
  property QtObject stdout: null
  property QtObject stderr: null
  signal exited(int code, int status)
  onRunningChanged: if (running) {
    Qt.callLater(function() {
      if (process.stdout) process.stdout.text = '{"ok":true,"result":{}}'
      process.running = false
      process.exited(0, 0)
    })
  }
}
''')
    (io / "StdioCollector.qml").write_text(
        'import QtQuick\nQtObject { property bool waitForEnd: false; property string text: "" }\n'
    )
    # Keep the real panel's navigation and RetainedLoaders; stand in for page bodies
    # that otherwise start shell services or call the user's backend.
    page = '''import QtQuick
Item {
  implicitWidth: 300; implicitHeight: 60
  property var logic: null
  property color foreground: "white"
  property string fontFamily: "Sans"
  property bool wide: false
  property int page: 0
  property string section: "saved"
  property var playlists: []
  property string openPlaylistId: ""
  property string playingPlaylistId: ""
  property string sourcePlace: ""
  property bool playlistPlaying: false
  property bool queueActive: false
  property int queueCount: 0
  property real queueDuration: 0
  property int newCount: 0
  property int downloadsActive: 0
  property int downloadsFailed: 0
  property real downloadsProgress: -1
  property bool settingsActive: false
  property string playlistId: ""
  property var pendingMedia: null
  property bool returnToCollection: false
  property int returnPage: -1
  property var entity: null
  property bool queryFocused: false
  property real scrollPosition: 0
  property bool open: false
  property string tab: "chapters"
  property string period: "month"
  property color surface: "black"
  property string format: "wide"
  property bool suppressed: false
  signal navigate(int index)
  signal searchRequested()
  signal sectionRequested(string section)
  signal playlistRequested(string playlistId)
  signal myQueueRequested()
  signal settingsRequested()
  signal shrinkRequested()
  signal expandRequested()
  signal channelRequested(var entity)
  signal playlistPickerRequested(var media, var anchorItem)
  signal sessionsRequested()
  signal collectionRequested()
  signal pageRequested(int index)
  signal mediaPickerRequested(var media)
  signal entityRequested(var entity)
  signal closeRequested()
  signal sheetRequested(string tab)
  signal nowRequested()
  signal accountRequested()
  function load() {}
  function focusQuery() { queryFocused = true }
  function openEntity(value) { entity = value }
}
'''
    for name in ["HistoryPage", "SubscriptionsPage", "ChannelPage"]:
        shutil.copy2(project / "ui" / f"{name}.qml", root / "ui" / f"Real{name}.qml")
    pages = ["NowPage", "SearchPage", "CollectionPage", "PlaylistPage", "SubscriptionsPage",
             "DownloadsPage", "HistoryPage", "StatsPage", "SettingsPage", "Rail", "PlayerHeader",
             "MiniPlayer", "PlayerSheet", "ThinPlayer", "PlayerBar", "ShelfPanel", "OnboardingPage",
             "Toast", "ErrorToast"]
    for name in pages:
        (root / "ui" / f"{name}.qml").write_text(page)
    popup = '''import QtQuick
import QtQuick.Controls
Popup {
  property var logic: null
  property color foreground: "white"
  property string fontFamily: "Sans"
  property int queueCount: 0
  property var media: null
  property Item anchorItem: null
  property Item boundsItem: null
}
'''
    for name in ["SessionsDialog", "PlaylistPicker"]:
        (root / "ui" / f"{name}.qml").write_text(popup)
    (ui_module / "qmldir").write_text(
        (ui_module / "qmldir").read_text()
        + "Panel 1.0 Panel.qml\nKeyboardPanel 1.0 KeyboardPanel.qml\n"
        + "Button 1.0 Button.qml\n"
    )
    (ui_module / "Button.qml").write_text('''import QtQuick
Item {
  property bool focusable: true
  property real horizontalPadding: 0
  property real verticalPadding: 0
  property bool hovered: false
  property bool pressed: false
  signal clicked()
  signal rightClicked()
}
''')
    (ui_module / "Panel.qml").write_text('''import QtQuick
Item {
  property string moduleName: ""
  property bool manageIpc: true
  property var bar: null
  property var settings: ({})
  readonly property bool opened: controller.open
  property QtObject controller: QtObject {
    property bool open: false
    function show() { open = true }
    function hide() { open = false }
  }
}
''')
    (ui_module / "KeyboardPanel.qml").write_text('''import QtQuick
Item {
  property var anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property var focusTarget: null
  property int padding: 0
  property real contentWidth: 1100
  property real contentHeight: 660
  width: contentWidth; height: contentHeight
  function fittedContentWidth(value) { return value }
  function fittedContentHeight(value, limit) { return value }
}
''')
    # Keep mock theme names unambiguous alongside Qt Quick Controls' styles.
    for source in (root / "ui").glob("*.qml"):
        value = source.read_text()
        if "import qs.Commons\n" in value:
            value = value.replace("import qs.Commons\n", "import qs.Commons\nimport qs.Commons as TestTheme\n")
            value = re.sub(r"(?<![\w.])Color\.", "TestTheme.Color.", value)
            source.write_text(value)


def image_fixture(ui_module: Path):
    # A real 1600x900 PNG so tests can inspect Qt's decoded dimensions.
    def chunk(kind, value):
        return struct.pack(">I", len(value)) + kind + value + struct.pack(">I", zlib.crc32(kind + value))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1600, 900, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress((b"\0" + b"\x60\x80\xa0" * 1600) * 900))
    png += chunk(b"IEND", b"")

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(png)))
            self.end_headers()
            self.wfile.write(png)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    port = server.server_address[1]
    with (ui_module / "qmldir").open("a") as f:
        f.write("singleton TestImage 1.0 TestImage.qml\n")
    (ui_module / "TestImage.qml").write_text(
        'pragma Singleton\nimport QtQuick\nQtObject { property string url: '
        + json.dumps(f"http://127.0.0.1:{port}/fixture.png")
        + f'; property int port: {port} }}\n'
    )
    return server
