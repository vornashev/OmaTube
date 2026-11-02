import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string text: ""
  property string icon: ""
  property bool selected: false
  property bool danger: false
  property bool bold: false
  property bool filled: false
  property bool spinning: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real labelSize: 10
  property real iconSize: 14
  property real letterSpacing: 1
  property string tooltipText: ""
  property alias hovered: mouse.containsMouse
  signal clicked()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color tone: filled ? Color.background : (!enabled ? dim : (danger ? Color.urgent : (selected ? Color.accent : (mouse.containsMouse ? foreground : dim))))
  readonly property color labelColor: filled ? Color.background : (selected ? foreground : tone)

  implicitHeight: Style.space(28)
  implicitWidth: row.implicitWidth + Style.space(20)
  opacity: enabled ? 1 : .4
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: text !== "" ? text : tooltipText
  Keys.onReturnPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.filled ? Color.accent : root.selected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
      : (mouse.pressed ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .16)
      : (mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .09) : "transparent"))
    border.width: Math.max(1, Style.space(1))
    border.color: root.activeFocus || root.selected || root.filled ? Color.accent
      : (mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .3) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1))
    Behavior on color { ColorAnimation { duration: 90 } }
    Behavior on border.color { ColorAnimation { duration: 90 } }
  }

  scale: mouse.pressed && enabled ? .94 : 1
  Behavior on scale { NumberAnimation { duration: 80 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)
    Icon {
      id: playbackGlyph
      visible: root.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: root.icon
      size: Style.space(root.iconSize)
      color: root.tone
      NumberAnimation on rotation { running: root.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
    }
    Text {
      visible: root.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.text
      color: root.labelColor
      font.family: root.fontFamily
      font.pixelSize: Style.space(root.labelSize)
      font.letterSpacing: root.letterSpacing
      font.bold: root.bold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
