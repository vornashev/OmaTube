import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal expandRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  readonly property var media: currentEntry ? currentEntry.media : ({})
  readonly property real progress: Math.max(0, Math.min(1, Number(stateData.position || 0) / Math.max(1, Number(stateData.duration || media.duration || 0))))
  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitHeight: Style.space(52)
  radius: Style.cornerRadius
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, .05)
  border.width: Math.max(1, Style.space(1))
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)

  Button {
    anchors.fill: parent
    focusable: true
    Accessible.name: L.tr("Открыть плеер")
    horizontalPadding: 0
    verticalPadding: 0
    onClicked: root.expandRequested()
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(10)

    Rectangle {
      width: Math.round(height * 16 / 9)
      height: parent.height
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      clip: true
      CatalogImage {
        anchors.fill: parent
        requestedSource: String(root.media.thumbnailUrl || "")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fillMode: Image.PreserveAspectCrop
      }
    }

    Column {
      width: parent.width - Math.round(height * 16 / 9) - Style.space(36) * 2 - parent.spacing * 3
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || L.tr("Ничего не играет"))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: L.tb(root.media.author || (root.currentEntry ? "" : L.tr("Очередь пуста")))
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    IconButton {
      z: 2
      anchors.verticalCenter: parent.verticalCenter
      icon: root.stateData.state === "playing" ? "pause" : "play"
      iconSize: 16
      active: true
      tooltipText: root.stateData.state === "playing" ? L.tr("Пауза") : L.tr("Продолжить")
      enabled: Boolean(root.currentEntry)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.logic.request("toggle_pause")
    }
    IconButton {
      z: 2
      anchors.verticalCenter: parent.verticalCenter
      icon: "skip-forward"
      iconSize: 16
      tooltipText: L.tr("Следующий")
      enabled: Boolean(root.currentEntry)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.logic.request("next")
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.radius
    height: Math.max(2, Style.space(2))
    width: (parent.width - root.radius * 2) * root.progress
    color: Color.accent
    visible: root.currentEntry !== null
  }
}
