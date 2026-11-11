import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

// A page with nothing to show because loading failed: replaces the list until a retry succeeds.
Column {
  id: root

  property string title: ""
  property string message: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal retryRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)

  spacing: Style.space(8)

  Icon {
    anchors.horizontalCenter: parent.horizontalCenter
    name: "circle-alert"
    size: Style.space(24)
    color: Color.urgent
  }
  Text {
    width: parent.width
    topPadding: Style.space(2)
    textFormat: Text.PlainText
    text: root.title
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.space(14)
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
  Text {
    width: parent.width
    visible: root.message !== "" && root.message !== root.title
    textFormat: Text.PlainText
    text: root.message
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.space(11)
    lineHeight: 1.3
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
  Item { width: 1; height: Style.space(4) }
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(8)
    Pill {
      height: Style.space(30)
      text: L.tr("ПОВТОРИТЬ")
      icon: "rotate-cw"
      iconSize: 12
      danger: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.retryRequested()
    }
    Pill {
      height: Style.space(30)
      text: L.tr("СКОПИРОВАТЬ ОШИБКУ")
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", root.title + ": " + root.message])
    }
  }
}
