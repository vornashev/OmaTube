import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var sponsor: logic && logic.stateData.sponsor ? logic.stateData.sponsor : null
  readonly property var lastSkip: sponsor ? sponsor.lastSkip : null
  readonly property var pending: sponsor ? sponsor.pending : null
  readonly property var shown: pending || (skipVisible ? lastSkip : null)
  readonly property var labels: ({
    sponsor: L.tr("спонсор"), intro: L.tr("интро"), outro: L.tr("концовка"), selfpromo: L.tr("самореклама"),
    interaction: L.tr("напоминание"), preview: L.tr("превью"), music_offtopic: L.tr("не музыка")
  })
  readonly property var categoryColors: ({
    sponsor: "#00d400", intro: "#00ffff", outro: "#4a4aff", selfpromo: "#ffff00",
    interaction: "#cc00ff", preview: "#008fd6", music_offtopic: "#ff9900"
  })
  readonly property color barColor: shown ? (categoryColors[shown.category] || Color.accent) : Color.accent
  property string shownSkipId: ""
  property bool skipVisible: false

  function formatSeconds(value) {
    var seconds = Math.round(Number(value || 0))
    return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
  }

  onLastSkipChanged: {
    if (lastSkip && lastSkip.id !== shownSkipId) { shownSkipId = lastSkip.id; skipVisible = true; hideTimer.restart() }
    else if (!lastSkip) skipVisible = false
  }

  visible: shown !== null
  implicitHeight: Style.space(34)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, .06)

  Timer { id: hideTimer; interval: 7000; onTriggered: root.skipVisible = false }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(3)
    color: root.barColor
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(14)
    anchors.rightMargin: Style.space(12)
    spacing: Style.space(10)
    Icon {
      anchors.verticalCenter: parent.verticalCenter
      name: "skip-forward"
      size: Style.space(14)
      color: root.barColor
    }
    Text {
      width: parent.width - Style.space(24) - actionLabel.width - parent.spacing * 2 - (root.pending ? dismissLabel.width + parent.spacing : 0)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.pending
        ? L.tr("Пропустить ") + (root.labels[root.pending.category] || root.pending.category) + "?"
        : (root.lastSkip ? L.tr("Пропущен ") + (root.labels[root.lastSkip.category] || root.lastSkip.category) + " · " + root.formatSeconds(root.lastSkip.seconds) : "")
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
      elide: Text.ElideRight
    }
    Text {
      id: actionLabel
      anchors.verticalCenter: parent.verticalCenter
      text: root.pending ? L.tr("ПРОПУСТИТЬ") : L.tr("ВЕРНУТЬ")
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: 1
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.request(root.pending ? "sponsor_skip" : "sponsor_undo")
      }
    }
    Text {
      id: dismissLabel
      visible: root.pending !== null
      anchors.verticalCenter: parent.verticalCenter
      text: "✕"
      color: root.foreground
      opacity: .6
      font.family: root.fontFamily
      font.pixelSize: Style.space(11)
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.request("sponsor_dismiss")
      }
    }
  }
}
