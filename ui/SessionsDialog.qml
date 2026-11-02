import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

Popup {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var sessions: []
  property int listRequestId: 0
  property int queueCount: 0
  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property bool restoreQueue: !logic || !logic.stateData.preferences || logic.stateData.preferences.restoreQueue !== false

  function reload() { if (logic) listRequestId = logic.request("sessions", ({})) }

  function describe(row) {
    var parts = [row.count + " " + plural(row.count, L.tr("трек"), L.tr("трека"), L.tr("треков"))]
    if (row.duration > 0) {
      var minutes = Math.round(row.duration / 60)
      parts.push(minutes >= 60 ? Math.floor(minutes / 60) + L.tr(" ч ") + (minutes % 60) + L.tr(" мин") : minutes + L.tr(" мин"))
    }
    var date = new Date(row.updatedAt * 1000), now = new Date()
    var days = Math.floor((new Date(now.getFullYear(), now.getMonth(), now.getDate()) - new Date(date.getFullYear(), date.getMonth(), date.getDate())) / 86400000)
    var time = (date.getHours() < 10 ? "0" : "") + date.getHours() + ":" + (date.getMinutes() < 10 ? "0" : "") + date.getMinutes()
    parts.push(days === 0 ? L.tr("сегодня ") + time : (days === 1 ? L.tr("вчера") : days + L.tr(" дн. назад")))
    return parts.join(" · ")
  }

  function plural(count, one, few, many) {
    var n = Math.abs(count) % 100, m = n % 10
    if (n > 10 && n < 20) return many
    if (m > 1 && m < 5) return few
    return m === 1 ? one : many
  }

  function save() {
    if (!logic || queueCount === 0) return
    logic.request("session_save", { name: nameField.text })
    nameField.text = ""
  }

  parent: Overlay.overlay
  anchors.centerIn: Overlay.overlay
  width: Style.space(440)
  padding: Style.space(16)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  popupType: Popup.Item
  onAboutToShow: { nameField.text = ""; reload() }
  onOpened: nameField.forceActiveFocus()

  background: Rectangle {
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    border.width: Math.max(1, Style.space(1))
    border.color: Color.accent
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      var result = root.logic.lastResult
      if (id === root.listRequestId && result && result.items) root.sessions = result.items
      else if (result && (root.logic.lastCommand === "session_save" || root.logic.lastCommand === "session_delete")) root.reload()
      else if (root.logic.lastCommand === "session_restore" && result && root.opened) root.close()
    }
  }

  contentItem: Column {
    spacing: Style.space(14)

    Row {
      width: parent.width
      spacing: Style.space(10)
      Column {
        width: parent.width - closeButton.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          text: L.tr("Сессии очереди")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(15)
          font.bold: true
        }
        Text {
          width: parent.width
          text: L.tr("сохранённые очереди · восстановление одним кликом")
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          elide: Text.ElideRight
        }
      }
      IconButton {
        id: closeButton
        icon: "x"
        iconSize: 14
        tooltipText: L.tr("Закрыть")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.close()
      }
    }

    Row {
      width: parent.width
      height: Style.space(17)
      spacing: Style.space(10)
      Text {
        id: listLabel
        anchors.verticalCenter: parent.verticalCenter
        text: L.tr("СОХРАНЁННЫЕ · ") + root.sessions.length
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - listLabel.width - parent.spacing)
        height: Math.max(1, Style.space(1))
        color: root.lineColor
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.min(Style.space(260), Math.max(Style.space(48), contentHeight))
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      spacing: Style.space(2)
      model: root.sessions
      delegate: Item {
        id: row
        required property var modelData
        required property int index
        width: list.width - (list.contentHeight > list.height ? Style.space(8) : 0)
        height: Style.space(46)
        HoverHandler { id: rowHover }
        Rectangle {
          anchors.fill: parent
          color: index === 0 ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
            : (rowHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
        }
        Rectangle {
          visible: index === 0
          width: Math.max(2, Style.space(2))
          height: parent.height
          color: Color.accent
        }
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(4)
          spacing: Style.space(6)
          Column {
            width: parent.width - actions.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(3)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: L.tb(row.modelData.name)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(13)
              font.weight: row.index === 0 ? Font.DemiBold : Font.Normal
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: root.describe(row.modelData)
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              elide: Text.ElideRight
            }
          }
          Row {
            id: actions
            anchors.verticalCenter: parent.verticalCenter
            IconButton { icon: "play"; iconSize: 15; tooltipText: L.tr("Заменить очередь"); foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.logic.request("session_restore", { id: row.modelData.id, mode: "replace" }) }
            IconButton { icon: "list-plus"; iconSize: 15; tooltipText: L.tr("Добавить в конец очереди"); foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.logic.request("session_restore", { id: row.modelData.id, mode: "append" }) }
            IconButton { icon: "trash-2"; iconSize: 15; tooltipText: L.tr("Удалить сессию"); foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.logic.request("session_delete", { id: row.modelData.id }) }
          }
        }
      }
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Text {
        visible: root.sessions.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(20)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: L.tr("Сессий пока нет. Сохраните текущую очередь, чтобы вернуться к ней позже.")
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }

    Rectangle { width: parent.width; height: Math.max(1, Style.space(1)); color: root.lineColor }

    Row {
      width: parent.width
      spacing: Style.space(8)
      Rectangle {
        width: parent.width - saveButton.width - parent.spacing
        height: Style.space(34)
        color: "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: nameField.activeFocus ? Color.accent : root.lineColor
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(8)
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "save"; size: Style.space(14); color: root.muted }
          TextInput {
            id: nameField
            width: parent.width - Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            clip: true
            maximumLength: 80
            onAccepted: root.save()
            Text {
              visible: nameField.text === ""
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              text: L.tr("Название сессии…")
              color: root.muted
              font: nameField.font
            }
          }
        }
      }
      Pill {
        id: saveButton
        height: Style.space(34)
        text: L.tr("СОХРАНИТЬ · ") + root.queueCount
        filled: true
        bold: true
        enabled: root.queueCount > 0
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.save()
      }
    }

    ToggleRow {
      width: parent.width
      label: L.tr("Восстанавливать при запуске")
      description: L.tr("последняя очередь и позиция, пауза без автозапуска")
      checked: root.restoreQueue
      separator: false
      foreground: root.foreground
      fontFamily: root.fontFamily
      onToggled: root.logic.request("setting", { key: "restoreQueue", value: !root.restoreQueue })
    }
  }
}
