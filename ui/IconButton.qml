import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string icon: ""
  property real iconSize: 16
  property string tooltipText: ""
  property bool active: false
  property bool danger: false
  property bool spinning: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property alias hovered: mouse.containsMouse
  signal clicked()

  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitWidth: Style.space(32)
  implicitHeight: Style.space(32)
  opacity: enabled ? 1 : .35
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: tooltipText
  Keys.onReturnPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08) : "transparent"
    border.width: root.activeFocus ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
  }

  Icon {
    id: playbackGlyph
    anchors.centerIn: parent
    name: root.icon
    size: Style.space(root.iconSize)
    color: root.danger ? Color.urgent : (root.active ? Color.accent : (mouse.containsMouse ? root.foreground : root.dim))
    // Keep rotation on the GUI thread so stopping cannot overwrite the reset.
    NumberAnimation on rotation { running: root.spinning; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
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
