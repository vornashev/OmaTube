import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

// Refresh failed but older data is still on screen: a small tag next to the page actions, details on click.
Item {
  id: root

  property string title: ""
  property string message: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal retryRequested()
  signal dismissRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitWidth: tagRow.implicitWidth + Style.space(18)
  implicitHeight: Style.space(28)
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: title + ". " + message
  Keys.onReturnPressed: details.open()
  Keys.onSpacePressed: details.open()

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, mouse.containsMouse || details.opened ? .18 : .1)
    border.width: root.activeFocus ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
  }

  Row {
    id: tagRow
    anchors.centerIn: parent
    spacing: Style.space(6)
    Icon { anchors.verticalCenter: parent.verticalCenter; name: "circle-alert"; size: Style.space(12); color: Color.urgent }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: L.tr("НЕ ОБНОВЛЕНО")
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.letterSpacing: 1.2
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: details.opened ? details.close() : details.open()
  }

  Popup {
    id: details
    y: root.height + Style.space(6)
    x: root.width - width
    width: Style.space(300)
    padding: Style.space(12)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    background: Rectangle {
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .98)
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14)
    }
    contentItem: Column {
      spacing: Style.space(6)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        wrapMode: Text.WordWrap
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.message + L.tr(". Показан прошлый список.")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        lineHeight: 1.3
        wrapMode: Text.WordWrap
      }
      Row {
        topPadding: Style.space(4)
        spacing: Style.space(4)
        Pill {
          height: Style.space(26)
          text: L.tr("ПОВТОРИТЬ")
          danger: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { details.close(); root.retryRequested() }
        }
        Pill {
          height: Style.space(26)
          text: L.tr("КОПИРОВАТЬ")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", root.title + ": " + root.message])
        }
        Pill {
          height: Style.space(26)
          text: L.tr("СКРЫТЬ")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { details.close(); root.dismissRequested() }
        }
      }
    }
  }
}
