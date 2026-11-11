import QtQuick
import qs.Commons
import qs.Ui

// Bottom toast confirming an action that did not navigate anywhere; lives 3 s and can undo it.
Rectangle {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var toast: null
  property bool shown: false

  readonly property bool danger: toast !== null && toast.danger === true
  readonly property color tone: danger ? Color.urgent : Color.accent

  function show(next) {
    toast = next
    shown = true
    hideTimer.interval = next && next.danger ? 6000 : 3000
    hideTimer.restart()
  }

  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 140 } }
  implicitWidth: row.implicitWidth + Style.space(30)
  implicitHeight: Style.space(36)
  color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .98)
  border.width: Math.max(1, Style.space(1))
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, .14)
  Accessible.role: Accessible.AlertMessage
  Accessible.name: toast ? String(toast.text || "") : ""

  Timer { id: hideTimer; interval: 3000; onTriggered: root.shown = false }
  HoverHandler { onHoveredChanged: if (hovered) hideTimer.stop(); else if (root.shown) hideTimer.restart() }

  Connections {
    target: root.logic
    function onToastRequested(next) { root.show(next) }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(3))
    color: root.tone
  }

  Row {
    id: row
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(16)
    spacing: Style.space(10)
    Icon {
      anchors.verticalCenter: parent.verticalCenter
      name: root.toast && root.toast.icon ? root.toast.icon : (root.danger ? "triangle-alert" : "check")
      size: Style.space(14)
      color: root.tone
    }
    Text {
      // Fixed cap instead of the toast width: the toast is sized from this row.
      width: Math.min(implicitWidth, Style.space(420))
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.toast ? String(root.toast.text || "") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.space(12)
      elide: Text.ElideRight
    }
    Item { width: Style.space(14); height: 1; visible: actionLabel.visible }
    Text {
      id: actionLabel
      visible: root.toast !== null && String(root.toast.action || "") !== ""
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.toast ? String(root.toast.action || "") : ""
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: 1.5
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(8)
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var run = root.toast ? root.toast.run : null
          root.shown = false
          if (typeof run === "function") run()
        }
      }
    }
  }
}
