import QtQuick
import qs.Commons

Item {
  id: row

  property string label: ""
  property string description: ""
  property bool checked: false
  property bool separator: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal toggled()

  readonly property color dim: Qt.darker(foreground, 1.5)

  width: parent ? parent.width : 0
  height: Style.space(description !== "" ? 47 : 32)
  activeFocusOnTab: true
  Accessible.role: Accessible.CheckBox
  Accessible.name: label
  Accessible.checked: checked
  Keys.onReturnPressed: row.toggled()
  Keys.onSpacePressed: row.toggled()

  Rectangle {
    visible: row.activeFocus
    anchors.fill: parent
    color: "transparent"
    border.width: Math.max(1, Style.space(1))
    border.color: Color.accent
  }
  Rectangle {
    visible: row.separator
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.space(1))
    color: Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, .1)
  }
  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(10)
    Column {
      width: parent.width - track.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Text {
        width: parent.width
        text: row.label
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.space(12)
        elide: Text.ElideRight
      }
      Text {
        visible: row.description !== ""
        width: parent.width
        text: row.description
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.space(10)
        elide: Text.ElideRight
      }
    }
    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: Style.space(16)
      radius: height / 2
      color: row.checked ? Color.accent : Qt.rgba(row.foreground.r, row.foreground.g, row.foreground.b, .12)
      Rectangle {
        width: Style.space(12)
        height: width
        radius: width / 2
        anchors.verticalCenter: parent.verticalCenter
        x: row.checked ? parent.width - width - Style.space(2) : Style.space(2)
        color: row.checked ? Color.background : row.dim
        Behavior on x { NumberAnimation { duration: 100 } }
      }
    }
  }
  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.toggled() }
}
