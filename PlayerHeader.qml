import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real pendingSeek: -1
  property bool seeking: false
  signal settingsRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  readonly property var media: currentEntry ? currentEntry.media : ({})
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real position: seeking && pendingSeek >= 0 ? pendingSeek : Number(stateData.position || 0)
  readonly property color dim: Qt.darker(foreground, 1.5)

  implicitHeight: Style.space(172)

  function request(command, payload) {
    if (logic) logic.request(command, payload || ({}))
  }

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    var minutes = Math.floor(seconds / 60)
    var rest = seconds % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }

  function previewSeek(mouse) {
    pendingSeek = Math.max(0, Math.min(duration, duration * mouse.x / Math.max(1, progressMouse.width)))
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      width: parent.width
      height: Style.space(68)
      spacing: Style.space(12)

      Rectangle {
        width: parent.height
        height: parent.height
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .16)
        clip: true
        CatalogImage {
          anchors.fill: parent
          anchors.margins: Math.max(1, Style.space(1))
          requestedSource: String(root.media.thumbnailUrl || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          fillMode: Image.PreserveAspectCrop
        }
      }

      Column {
        width: parent.width - Style.space(68) - utilityButtons.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(root.media.title || "Очередь пуста")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(root.media.author || (root.currentEntry ? "Автор неизвестен" : "Добавьте видео или найдите его в каталоге"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.stateData.state === "error" ? "ОШИБКА ВОСПРОИЗВЕДЕНИЯ"
            : (root.stateData.state === "loading" ? "ПОДКЛЮЧАЕМ АУДИОПОТОК"
            : (root.stateData.state === "playing" ? "СЕЙЧАС ИГРАЕТ"
            : (root.currentEntry ? "ПАУЗА" : "OMATUBE")))
          color: root.stateData.state === "loading"
            || root.stateData.state === "error" ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: .8
          elide: Text.ElideRight
        }
      }

      Row {
        id: utilityButtons
        height: parent.height
        spacing: 0
        Button {
          focusable: true
          Accessible.name: tooltipText
          width: Style.space(28)
          height: Style.space(28)
          iconText: "󰒓"
          iconSize: Style.font.icon
          tooltipText: "Настройки"
          foreground: root.dim
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: root.settingsRequested()
        }
      }
    }

    Item {
      width: parent.width
      height: Style.space(28)
      Rectangle {
        id: progressTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Style.space(5)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, root.position / Math.max(1, root.duration)))
          height: parent.height
          radius: parent.radius
          color: Color.accent
        }
        MouseArea {
          id: progressMouse
          anchors.fill: parent
          anchors.topMargin: -Style.space(8)
          anchors.bottomMargin: -Style.space(8)
          enabled: root.stateData.canSeek === true && root.duration > 0
          cursorShape: enabled ? (pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor) : Qt.ArrowCursor
          preventStealing: true
          onPressed: function(mouse) { root.seeking = true; root.previewSeek(mouse) }
          onPositionChanged: function(mouse) { if (pressed) root.previewSeek(mouse) }
          onReleased: function(mouse) {
            root.previewSeek(mouse)
            root.request("seek", { seconds: root.pendingSeek })
            root.seeking = false
          }
          onCanceled: root.seeking = false
        }
      }
      Text {
        anchors.left: parent.left
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: root.formatTime(root.position)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        anchors.top: progressTrack.bottom
        anchors.topMargin: Style.space(2)
        text: root.formatTime(root.duration)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Item {
      width: parent.width
      height: Style.space(48)

      Button {
        focusable: true
        Accessible.name: tooltipText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        height: Style.space(38)
        iconText: root.stateData.shuffle ? "󰒟" : "󰒞"
        iconSize: Style.space(19)
        tooltipText: root.stateData.shuffle ? "Выключить перемешивание" : "Перемешивать очередь"
        foreground: root.stateData.shuffle ? Color.accent : root.dim
        enabled: Boolean(root.currentEntry)
        opacity: enabled ? 1 : .35
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.request("shuffle", { value: !root.stateData.shuffle })
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(12)
        Button {
          focusable: true
          Accessible.name: tooltipText
          width: Style.space(40)
          height: Style.space(40)
          iconText: "󰒮"
          iconSize: Style.space(21)
          tooltipText: "Предыдущий"
          foreground: root.foreground
          enabled: Boolean(root.currentEntry)
          opacity: enabled ? 1 : .35
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: root.request("previous")
        }
        Button {
          focusable: true
          Accessible.name: tooltipText
          width: Style.space(46)
          height: Style.space(46)
          radius: height / 2
          bordered: true
          iconText: root.stateData.state === "playing" ? "󰏤" : "󰐊"
          iconSize: Style.space(25)
          tooltipText: root.stateData.state === "playing" ? "Пауза" : "Продолжить"
          foreground: Color.accent
          enabled: Boolean(root.currentEntry)
          opacity: enabled ? 1 : .35
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: root.request("toggle_pause")
        }
        Button {
          focusable: true
          Accessible.name: tooltipText
          width: Style.space(40)
          height: Style.space(40)
          iconText: "󰒭"
          iconSize: Style.space(21)
          tooltipText: "Следующий"
          foreground: root.foreground
          enabled: Boolean(root.currentEntry)
          opacity: enabled ? 1 : .35
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: root.request("next")
        }
      }

      Button {
        focusable: true
        Accessible.name: tooltipText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(38)
        height: Style.space(38)
        iconText: root.stateData.repeat === "one" ? "󰑘"
          : (root.stateData.repeat === "all" ? "󰑖" : "󰑗")
        iconSize: Style.space(19)
        tooltipText: root.stateData.repeat === "one" ? "Повторять текущий трек"
          : (root.stateData.repeat === "all" ? "Повторять очередь" : "Повтор выключен")
        foreground: root.stateData.repeat === "off" ? root.dim : Color.accent
        enabled: Boolean(root.currentEntry)
        opacity: enabled ? 1 : .35
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.request("repeat", { value: root.stateData.repeat === "off" ? "all"
          : (root.stateData.repeat === "all" ? "one" : "off") })
      }
    }
  }
}
