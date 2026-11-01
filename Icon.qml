import QtQuick
import QtQuick.Effects

Item {
  id: root

  property string name: ""
  property real size: 16
  property color color: "white"

  implicitWidth: size
  implicitHeight: size

  Image {
    id: image
    anchors.fill: parent
    visible: false
    source: root.name !== "" ? Qt.resolvedUrl("icons/" + root.name + ".svg") : ""
    sourceSize.width: Math.ceil(root.size * 2)
    sourceSize.height: Math.ceil(root.size * 2)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: false
  }

  MultiEffect {
    anchors.fill: parent
    source: image
    colorization: 1.0
    colorizationColor: root.color
    visible: image.status === Image.Ready
  }
}
