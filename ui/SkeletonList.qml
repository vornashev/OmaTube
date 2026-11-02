import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property color foreground: Color.foreground
  property int rowCount: 6
  spacing: 0

  Repeater {
    model: root.rowCount
    delegate: Item {
      id: skeletonRow
      required property int index
      width: root.width
      height: Style.space(52)
      clip: true

      Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(18)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .09)
        }
        Column {
          width: parent.width - Style.space(70)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Rectangle {
            width: parent.width * (.56 + (skeletonRow.index % 3) * .1)
            height: Style.space(8)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .11)
          }
          Rectangle {
            width: parent.width * (.3 + (skeletonRow.index % 2) * .14)
            height: Style.space(6)
            radius: height / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .07)
          }
        }
        Rectangle {
          width: Style.space(32)
          height: Style.space(6)
          radius: height / 2
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .07)
        }
      }

      Rectangle {
        id: shimmer
        width: parent.width * .18
        height: parent.height
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .045)
        rotation: 8
        SequentialAnimation on x {
          loops: Animation.Infinite
          PauseAnimation { duration: skeletonRow.index * 55 }
          NumberAnimation {
            from: -shimmer.width
            to: skeletonRow.width + shimmer.width
            duration: 1050
            easing.type: Easing.InOutQuad
          }
          PauseAnimation { duration: 300 }
        }
      }
    }
  }
}
