import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

// Global error (backend, catalog operation, playback) as a toast that stays until it is retried or dismissed.
Rectangle {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool suppressed: false
  signal accountRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string message: logic ? String(logic.error || "") : ""
  readonly property string title: logic ? String(logic.errorTitle || "") : ""
  readonly property bool needsAccount: logic !== null
    && (logic.errorCode === "auth_required" || logic.errorCode === "po_token_required")
  readonly property bool shown: message !== "" && !suppressed

  visible: opacity > 0
  opacity: shown ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 140 } }
  implicitWidth: Style.space(420)
  implicitHeight: Math.max(Style.space(54), content.implicitHeight + Style.space(20))
  color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .98)
  border.width: Math.max(1, Style.space(1))
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, .14)
  Accessible.role: Accessible.AlertMessage
  Accessible.name: title + ". " + message

  MouseArea { anchors.fill: parent }

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(3))
    color: Color.urgent
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(16)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(10)

    Icon {
      anchors.verticalCenter: parent.verticalCenter
      name: "circle-alert"
      size: Style.space(14)
      color: Color.urgent
    }

    Column {
      width: parent.width - Style.space(14) - actions.width - parent.spacing * 2
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      Text {
        width: parent.width
        visible: root.title !== ""
        textFormat: Text.PlainText
        text: root.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.message
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
    }

    Row {
      id: actions
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      Pill {
        visible: root.needsAccount
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(28)
        text: L.tr("АККАУНТ")
        icon: "settings"
        selected: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.accountRequested()
      }
      Pill {
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(28)
        text: L.tr("ПОВТОРИТЬ")
        danger: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        tooltipText: L.tr("Повторить последнее действие")
        onClicked: root.logic.retryLastOperation()
      }
      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: Style.space(28)
        icon: "copy"
        iconSize: 13
        tooltipText: L.tr("Скопировать ошибку")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: Quickshell.execDetached(["wl-copy", root.title + ": " + root.message])
      }
      IconButton {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: Style.space(28)
        icon: "x"
        iconSize: 13
        tooltipText: L.tr("Скрыть ошибку")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.logic.dismissError()
      }
    }
  }
}
