import QtQuick
import qs.Commons

Item {
  id: root

  property var tabs: []
  property var current: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real labelSize: 11
  property real tabSpacing: 24
  property real leftInset: 12
  signal selected(var value)

  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitHeight: Style.space(35)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.space(1))
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(root.leftInset)
    spacing: Style.space(root.tabSpacing)
    Repeater {
      model: root.tabs
      delegate: Item {
        required property var modelData
        readonly property bool chosen: root.current === modelData.value
        width: tabRow.implicitWidth
        height: parent.height
        Accessible.role: Accessible.PageTab
        Accessible.name: modelData.label
        activeFocusOnTab: true
        Keys.onReturnPressed: root.selected(modelData.value)
        Keys.onSpacePressed: root.selected(modelData.value)
        Row {
          id: tabRow
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: -Style.space(1)
          spacing: Style.space(6)
          Icon {
            visible: modelData.icon !== undefined
            anchors.verticalCenter: parent.verticalCenter
            name: modelData.icon || ""
            size: Style.space(12)
            color: chosen ? Color.accent : root.dim
          }
          Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: chosen ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(root.labelSize)
            font.letterSpacing: 1.2
            font.bold: chosen
          }
        }
        Rectangle {
          visible: chosen
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(2, Style.space(2))
          color: Color.accent
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selected(modelData.value)
        }
      }
    }
  }
}
