import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

// V2 · thin panel: the player that stays on screen outside «Сейчас».
// A 3 px timeline on the top edge and one row of title + transport; ˄ opens the sheet.
Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color surface: Color.background
  signal sheetRequested(string tab)

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var current: stateData.current || null
  readonly property var media: current ? current.media || ({}) : ({})
  readonly property string playState: String(stateData.state || "idle")
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var chapters: stateData.info && stateData.info.chapters ? stateData.info.chapters : []
  property bool scrubbing: false
  property real scrubSeconds: 0
  property string flashText: ""

  function chapterIndexAt(seconds) {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (seconds >= Number(chapters[i].start)) found = i
    return found
  }
  readonly property int chapterIndex: chapterIndexAt(Number(stateData.position || 0))

  implicitHeight: Style.space(48)

  HoverHandler { id: panelHover }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .035)
  }
  Rectangle { anchors.fill: parent; z: -1; color: root.surface }

  Timeline {
    id: timeline
    z: 5
    anchors.left: parent.left
    anchors.right: parent.right
    y: -height + Style.space(3)
    logic: root.logic
    foreground: root.foreground
    fontFamily: root.fontFamily
    gapColor: root.surface
    expanded: panelHover.hovered
    guideHeight: root.height - Style.space(3)
    onScrubbing: (active, seconds) => { root.scrubbing = active; root.scrubSeconds = seconds }
    onFlashed: text => { if (text === "") return; root.flashText = text; flashTimer.restart() }
  }
  Timer { id: flashTimer; interval: 1200; onTriggered: root.flashText = "" }

  Row {
    id: info
    anchors.left: parent.left
    anchors.right: controls.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.topMargin: Style.space(3)
    anchors.leftMargin: Style.space(24)
    anchors.rightMargin: Style.space(16)
    spacing: Style.space(12)

    Rectangle {
      width: Style.space(40)
      height: Style.space(23)
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

    Text {
      id: titleText
      width: Math.min(implicitWidth, parent.width - Style.space(52) - Math.min(metaText.implicitWidth, Style.space(160)))
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.scrubbing ? L.tr("Перемотка → ") + timeline.formatTime(root.scrubSeconds) : String(root.media.title || L.tr("Ничего не играет"))
      color: root.scrubbing ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.space(13)
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      id: metaText
      width: Math.max(0, parent.width - Style.space(52) - titleText.width - parent.spacing)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: {
        if (root.scrubbing) {
          var index = root.chapterIndexAt(root.scrubSeconds)
          return index >= 0 ? L.tr("·  Глава ") + (index + 1) + "/" + root.chapters.length + " «" + String(root.chapters[index].title || "") + "»" : ""
        }
        if (root.playState === "loading") return L.tr("·  загрузка потока…")
        var parts = []
        if (root.media.author) parts.push(L.tb(root.media.author))
        if (root.chapterIndex >= 0) parts.push(L.tr("гл. ") + (root.chapterIndex + 1) + "/" + root.chapters.length)
        return parts.length > 0 ? "·  " + parts.join("  ·  ") : ""
      }
      color: root.playState === "loading" && !root.scrubbing ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: info
    cursorShape: Qt.PointingHandCursor
    onClicked: root.sheetRequested("chapters")
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.rightMargin: Style.space(14)
    spacing: Style.space(4)

    Rectangle {
      visible: root.flashText !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: flashLabel.implicitWidth + Style.space(14)
      height: Style.space(20)
      color: Color.accent
      Text {
        id: flashLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.flashText
        color: Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        font.bold: true
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      rightPadding: Style.space(12)
      leftPadding: Style.space(6)
      textFormat: Text.PlainText
      text: timeline.formatTime(root.scrubbing ? root.scrubSeconds : Number(root.stateData.position || 0))
        + " / " + timeline.formatTime(root.duration)
      color: root.scrubbing || root.flashText !== "" ? Color.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(11)
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "skip-back"; iconSize: 15
      tooltipText: L.tr("Предыдущий")
      enabled: root.current !== null
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.logic.request("previous")
    }
    Rectangle {
      width: Style.space(32)
      height: Style.space(32)
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, playMouse.containsMouse ? .3 : .18)
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: root.playState === "playing" ? L.tr("Пауза") : L.tr("Играть")
      Keys.onReturnPressed: root.logic.request("toggle_pause")
      Icon {
        id: playbackGlyph
        anchors.centerIn: parent
        name: root.playState === "loading" ? "loader-circle" : (root.playState === "playing" ? "pause" : "play")
        size: Style.space(16)
        color: Color.accent
        NumberAnimation on rotation { running: playbackGlyph.animationVisible && root.playState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
      }
      MouseArea {
        id: playMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.request(root.playState === "loading" ? "cancel_load" : "toggle_pause")
      }
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "skip-forward"; iconSize: 15
      tooltipText: L.tr("Следующий")
      enabled: root.current !== null
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.logic.request("next")
    }
    Item { width: Style.space(12); height: 1 }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "list-music"; iconSize: 15
      tooltipText: L.tr("Очередь")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.sheetRequested("queue")
    }
    IconButton {
      anchors.verticalCenter: parent.verticalCenter
      icon: "chevron-up"; iconSize: 16
      active: true
      tooltipText: L.tr("Раскрыть плеер")
      foreground: root.foreground; fontFamily: root.fontFamily
      onClicked: root.sheetRequested("")
    }
  }
}
