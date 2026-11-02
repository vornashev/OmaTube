import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

// V1 · bottom panel: a full transport row that stays under every tab except «Сейчас».
Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color surface: Color.background
  signal expandRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var current: stateData.current || null
  readonly property var media: current ? current.media || ({}) : ({})
  readonly property string playState: String(stateData.state || "idle")
  readonly property bool loading: playState === "loading"
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real volume: Number(stateData.volume === undefined ? 100 : stateData.volume)
  readonly property color dim: Qt.darker(foreground, 1.5)
  property string savedVideoId: ""

  implicitHeight: Style.space(72)

  Rectangle { anchors.fill: parent; color: root.surface }
  Rectangle { anchors.fill: parent; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .035) }
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(1, Style.space(1))
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
  }

  Row {
    id: info
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(20)
    width: Style.space(250)
    spacing: Style.space(12)
    Rectangle {
      width: Style.space(72)
      height: Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      clip: true
      CatalogImage {
        anchors.fill: parent
        requestedSource: String(root.media.thumbnailUrl || "")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fillMode: Image.PreserveAspectCrop
      }
    }
    Column {
      width: parent.width - Style.space(84)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || L.tr("Ничего не играет"))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(13)
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.loading ? L.tr("загрузка потока…") : L.tb(root.media.author || "")
        color: root.loading ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        elide: Text.ElideRight
      }
    }
  }
  MouseArea {
    anchors.fill: info
    cursorShape: Qt.PointingHandCursor
    onClicked: root.expandRequested()
  }

  Row {
    id: transport
    anchors.left: info.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(14)
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      readonly property bool saved: root.savedVideoId !== "" && root.savedVideoId === String(root.media.videoId || "")
      icon: saved ? "heart-filled" : "heart"; iconSize: 17
      active: true
      enabled: root.current !== null
      tooltipText: saved ? L.tr("Убрать из медиатеки") : L.tr("Сохранить в медиатеку")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: {
        root.savedVideoId = saved ? "" : String(root.media.videoId || "")
        root.logic.request("save_media", { media: root.media, saved: !saved })
      }
    }
    Item { width: Style.space(4); height: 1 }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "skip-back"; iconSize: 17
      tooltipText: L.tr("Предыдущий")
      enabled: root.current !== null
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.logic.request("previous")
    }
    Rectangle {
      width: Style.space(40)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, playMouse.containsMouse ? .3 : .18)
      border.width: Math.max(1, Style.space(1.5))
      border.color: Color.accent
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: root.playState === "playing" ? L.tr("Пауза") : L.tr("Играть")
      Keys.onReturnPressed: root.logic.request("toggle_pause")
      Icon {
        id: playbackGlyph
        anchors.centerIn: parent
        name: root.loading ? "loader-circle" : (root.playState === "playing" ? "pause" : "play")
        size: Style.space(18)
        color: Color.accent
        NumberAnimation on rotation { running: root.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
      }
      MouseArea {
        id: playMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.request(root.loading ? "cancel_load" : "toggle_pause")
      }
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "skip-forward"; iconSize: 17
      tooltipText: L.tr("Следующий")
      enabled: root.current !== null
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.logic.request("next")
    }
  }

  Row {
    id: tools
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: Style.space(16)
    spacing: Style.space(6)
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: root.stateData.muted === true || root.volume === 0 ? "volume-x" : (root.volume < 50 ? "volume-1" : "volume-2")
      iconSize: 16
      tooltipText: L.tr("Громкость ") + Math.round(root.volume) + L.tr("% · колесо — изменить")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.logic.request("mute", { value: root.stateData.muted !== true })
      WheelHandler {
        onWheel: event => root.logic.request("volume", {
          value: Math.max(0, Math.min(100, Math.round(root.volume + (event.angleDelta.y > 0 ? 5 : -5))))
        })
      }
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "list-music"; iconSize: 16
      tooltipText: L.tr("Очередь")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.expandRequested()
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "maximize-2"; iconSize: 16
      active: true
      tooltipText: L.tr("Открыть «Сейчас»")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.expandRequested()
    }
  }

  Text {
    id: elapsed
    anchors.left: transport.right
    anchors.leftMargin: Style.space(28)
    anchors.verticalCenter: parent.verticalCenter
    text: seek.formatTime(root.loading ? 0 : seek.position)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.space(11)
  }
  Timeline {
    id: seek
    anchors.left: elapsed.right
    anchors.right: total.left
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    thin: false
    activeHeight: Style.space(4)
    showUpcoming: false
    logic: root.logic
    foreground: root.foreground
    fontFamily: root.fontFamily
    gapColor: root.surface
  }
  Text {
    id: total
    anchors.right: tools.left
    anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    text: seek.formatTime(root.duration)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.space(11)
  }
}
