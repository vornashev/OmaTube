import QtQuick
import qs.Commons

Rectangle {
  id: root

  property var options: []
  property var current: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal chosen(var value)

  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitWidth: row.implicitWidth + Style.space(6)
  implicitHeight: Style.space(31)
  color: "transparent"
  border.width: Math.max(1, Style.space(1))
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(3)
    Repeater {
      model: root.options
      delegate: Rectangle {
        required property var modelData
        readonly property bool on: root.current === modelData.value
        width: label.implicitWidth + Style.space(20)
        height: Style.space(25)
        color: on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : (mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: modelData.label
        Keys.onReturnPressed: root.chosen(modelData.value)
        Text {
          id: label
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: modelData.label
          color: on ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          font.letterSpacing: 1
          font.bold: on
        }
        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.chosen(modelData.value)
        }
      }
    }
  }
}
