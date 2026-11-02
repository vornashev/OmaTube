import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string account: "chromium"
  property string format: "wide"
  property int step: 2
  signal finished()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property var accountOptions: [
    { value: "chromium", icon: "globe", label: L.tr("Импорт из Chromium"), badge: L.tr("РЕКОМЕНДУЕМ"),
      description: L.tr("Cookies YouTube берутся из профиля браузера: рекомендации, лайки и плейлисты аккаунта.") },
    { value: "none", icon: "user-x", label: L.tr("Без аккаунта"),
      description: L.tr("Поиск и воспроизведение работают, личные подписки и лайки недоступны. Подключить можно позже в настройках.") }
  ]
  readonly property var formatOptions: [
    { value: "compact", label: L.tr("Компакт"), size: "400 × 660" },
    { value: "wide", label: L.tr("Широкий"), size: "1100 × 660" },
    { value: "shelf", label: L.tr("Полка"), size: L.tr("на всю ширину") }
  ]
  readonly property var steps: [{ n: 1, label: L.tr("Проверка") }, { n: 2, label: L.tr("Аккаунт") }, { n: 3, label: L.tr("Формат") }]

  function finish() {
    if (!logic) return
    if (account === "chromium") logic.request("youtube_auth_import", { browser: "chromium" })
    logic.request("setting", { key: "panelFormat", value: format })
    logic.request("setting", { key: "onboarded", value: true })
    finished()
  }

  MouseArea { anchors.fill: parent }

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(48), Style.space(560))
    spacing: Style.space(20)

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(10)
      Icon { anchors.verticalCenter: parent.verticalCenter; name: "tv-minimal-play"; size: Style.space(22); color: Color.accent }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "OMATUBE"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(16)
        font.bold: true
        font.letterSpacing: 3
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      Repeater {
        model: root.steps
        delegate: Row {
          required property var modelData
          required property int index
          readonly property bool done: modelData.n < root.step
          readonly property bool current: modelData.n === root.step
          spacing: Style.space(8)
          Rectangle {
            visible: index > 0
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            height: Math.max(1, Style.space(1))
            color: modelData.n <= root.step ? Color.accent : root.lineColor
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            height: width
            radius: width / 2
            color: done ? Color.accent : (current ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent")
            border.width: Math.max(1, Style.space(1))
            border.color: done || current ? Color.accent : root.lineColor
            Icon { visible: done; anchors.centerIn: parent; name: "check"; size: Style.space(12); color: Color.background }
            Text {
              visible: !done
              anchors.centerIn: parent
              text: String(modelData.n)
              color: current ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.bold: true
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: done || current ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            font.bold: current
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: cardColumn.implicitHeight + Style.space(48)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05)
      border.width: Math.max(1, Style.space(1))
      border.color: root.lineColor

      Column {
        id: cardColumn
        anchors.fill: parent
        anchors.margins: Style.space(24)
        spacing: Style.space(16)

        Column {
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: root.step === 2 ? L.tr("Подключить аккаунт YouTube?") : L.tr("Выберите формат панели")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(18)
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.step === 2 ? L.tr("Нужно для подписок, лайков и «Смотреть позже». Без аккаунта работают поиск и воспроизведение.")
              : L.tr("Формат можно сменить в любой момент в настройках.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            wrapMode: Text.WordWrap
          }
        }

        Repeater {
          model: root.step === 2 ? root.accountOptions : []
          delegate: Rectangle {
            required property var modelData
            readonly property bool chosen: root.account === modelData.value
            width: cardColumn.width
            height: optionRow.implicitHeight + Style.space(28)
            color: chosen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: chosen ? Color.accent : root.lineColor
            activeFocusOnTab: true
            Accessible.role: Accessible.RadioButton
            Accessible.name: modelData.label
            Accessible.checked: chosen
            Keys.onReturnPressed: root.account = modelData.value
            Row {
              id: optionRow
              anchors.fill: parent
              anchors.margins: Style.space(14)
              spacing: Style.space(14)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(36); height: width
                color: chosen ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
                Icon { anchors.centerIn: parent; name: modelData.icon; size: Style.space(16); color: chosen ? Color.background : root.dim }
              }
              Column {
                width: parent.width - Style.space(36) - Style.space(16) - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Row {
                  spacing: Style.space(8)
                  Text { text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(13); font.bold: true }
                  Rectangle {
                    visible: modelData.badge !== undefined
                    anchors.verticalCenter: parent.verticalCenter
                    width: badgeText.implicitWidth + Style.space(12)
                    height: Style.space(14)
                    color: "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: Color.accent
                    Text { id: badgeText; anchors.centerIn: parent; text: modelData.badge || ""; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.space(8); font.bold: true; font.letterSpacing: .8 }
                  }
                }
                Text {
                  width: parent.width
                  text: modelData.description
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  wrapMode: Text.WordWrap
                }
              }
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(16); height: width; radius: width / 2
                color: "transparent"
                border.width: Math.max(1.5, Style.space(1.5))
                border.color: chosen ? Color.accent : root.dim
                Rectangle { anchors.centerIn: parent; visible: chosen; width: Style.space(8); height: width; radius: width / 2; color: Color.accent }
              }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.account = modelData.value }
          }
        }

        Row {
          visible: root.step === 3
          width: parent.width
          spacing: Style.space(12)
          Repeater {
            model: root.step === 3 ? root.formatOptions : []
            delegate: Rectangle {
              required property var modelData
              readonly property bool chosen: root.format === modelData.value
              width: (parent.width - parent.spacing * 2) / 3
              height: Style.space(72)
              color: chosen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: chosen ? Color.accent : root.lineColor
              activeFocusOnTab: true
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData.label
              Keys.onReturnPressed: root.format = modelData.value
              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); font.bold: chosen }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.size; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.format = modelData.value }
            }
          }
        }

        Row {
          width: parent.width
          topPadding: Style.space(6)
          spacing: Style.space(10)
          Pill {
            visible: root.step > 2
            height: Style.space(33)
            icon: "arrow-left"
            iconSize: 13
            text: L.tr("НАЗАД")
            labelSize: 11
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.step = 2
          }
          Item { width: parent.width - nextButton.width - (root.step > 2 ? Style.space(100) : 0) - parent.spacing * (root.step > 2 ? 2 : 1); height: 1 }
          Pill {
            id: nextButton
            height: Style.space(33)
            text: root.step === 2 ? (root.account === "chromium" ? L.tr("ДАЛЕЕ") : L.tr("ДАЛЕЕ")) : (root.account === "chromium" ? L.tr("ИМПОРТИРОВАТЬ И НАЧАТЬ") : L.tr("НАЧАТЬ"))
            icon: root.step === 2 ? "arrow-right" : "check"
            filled: true
            bold: true
            labelSize: 11
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: { if (root.step === 2) root.step = 3; else root.finish() }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: L.tr("Пропустить настройку")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.underline: skipMouse.containsMouse
      MouseArea { id: skipMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.account = "none"; root.finish() } }
    }
  }
}
