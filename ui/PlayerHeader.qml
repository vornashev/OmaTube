import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
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
  readonly property string videoMode: logic ? logic.videoMode : "audio"
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real position: seeking && pendingSeek >= 0 ? pendingSeek : Number(stateData.position || 0)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property bool hasTrack: Boolean(currentEntry)
  readonly property var chapters: stateData.info && stateData.info.chapters ? stateData.info.chapters : []
  readonly property int chapterIndex: {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (position >= chapters[i].start) found = i
    return found
  }

  implicitHeight: Style.space(181)
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, .05)

  function request(command, payload) { if (logic) logic.request(command, payload || ({})) }
  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
  }
  function previewSeek(mouse) {
    pendingSeek = Math.max(0, Math.min(duration, duration * mouse.x / Math.max(1, progressMouse.width)))
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: Style.space(18)
    anchors.rightMargin: Style.space(18)
    anchors.topMargin: Style.space(18)
    anchors.bottomMargin: Style.space(14)
    spacing: Style.space(14)

    Row {
      width: parent.width
      height: Style.space(68)
      spacing: Style.space(12)
      Rectangle {
        width: Style.space(112)
        height: Style.space(63)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
        clip: true
        CatalogImage {
          anchors.fill: parent
          requestedSource: String(root.media.thumbnailUrl || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          fillMode: Image.PreserveAspectCrop
        }
        Rectangle {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(4)
          width: Style.space(20)
          height: Style.space(14)
          color: "#000000B3"
          Icon {
            anchors.centerIn: parent
            name: root.videoMode === "audio" ? "headphones" : (root.videoMode === "tile" ? "panels-top-left" : "picture-in-picture-2")
            size: Style.space(10)
            color: "#FFFFFF"
          }
        }
      }
      Column {
        width: parent.width - Style.space(124)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: String(root.media.title || L.tr("Очередь пуста"))
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(13)
          font.bold: true
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: L.tb(root.media.author || (root.hasTrack ? L.tr("Автор неизвестен") : ""))
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: root.chapterIndex >= 0 || root.stateData.state === "error"
          textFormat: Text.PlainText
          text: root.stateData.state === "error" ? L.tr("Ошибка воспроизведения")
            : L.tr("Глава ") + (root.chapterIndex + 1) + "/" + root.chapters.length + " · " + (root.chapterIndex >= 0 ? root.chapters[root.chapterIndex].title : "")
          color: root.stateData.state === "error" ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          elide: Text.ElideRight
        }
      }
    }

    Row {
      width: parent.width
      height: Style.space(13)
      spacing: Style.space(10)
      Text { id: posLabel; width: Style.space(28); textFormat: Text.PlainText; text: root.formatTime(root.position); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
      Item {
        width: parent.width - posLabel.width - durLabel.width - parent.spacing * 2
        height: parent.height
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(3)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.position / Math.max(1, root.duration)))
            height: parent.height
            color: Color.accent
          }
        }
        MouseArea {
          id: progressMouse
          anchors.fill: parent
          enabled: root.stateData.canSeek === true && root.duration > 0
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
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
      Text { id: durLabel; width: Style.space(28); horizontalAlignment: Text.AlignRight; textFormat: Text.PlainText; text: root.formatTime(root.duration); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
    }

    Item {
      width: parent.width
      height: Style.space(40)

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        IconButton {
          icon: "shuffle"; active: root.stateData.shuffle === true; tooltipText: L.tr("Перемешать")
          foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.hasTrack
          onClicked: root.request("shuffle", { value: !root.stateData.shuffle })
        }
        IconButton {
          objectName: "video-mode-toggle"
          icon: root.videoMode === "audio" ? "headphones" : (root.videoMode === "tile" ? "panels-top-left" : "picture-in-picture-2")
          active: root.videoMode !== "audio"
          tooltipText: root.videoMode === "audio" ? L.tr("Только аудио") : (root.videoMode === "tile" ? L.tr("Видео в плитке") : L.tr("Видео поверх окон"))
          foreground: root.foreground; fontFamily: root.fontFamily
          enabled: !(root.logic && root.logic.videoLoading)
          onClicked: root.request("video_mode", { value: root.videoMode === "audio" ? "tile" : (root.videoMode === "tile" ? "floating" : "audio") })
        }
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(10)
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip-back"; iconSize: 18; tooltipText: L.tr("Предыдущий"); enabled: root.hasTrack; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.request("previous") }
        Item {
          width: Style.space(40); height: Style.space(40)
          opacity: root.hasTrack ? 1 : .4
          Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18); border.width: Math.max(1.5, Style.space(1.5)); border.color: Color.accent }
          Icon { anchors.centerIn: parent; name: root.stateData.state === "playing" ? "pause" : "play"; size: Style.space(18); color: Color.accent }
          MouseArea { anchors.fill: parent; enabled: root.hasTrack; cursorShape: Qt.PointingHandCursor; onClicked: root.request("toggle_pause") }
          Accessible.role: Accessible.Button
          Accessible.name: root.stateData.state === "playing" ? L.tr("Пауза") : L.tr("Продолжить")
        }
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip-forward"; iconSize: 18; tooltipText: L.tr("Следующий"); enabled: root.hasTrack; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.request("next") }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        IconButton {
          icon: root.stateData.repeat === "one" ? "repeat-1" : "repeat"
          active: root.stateData.repeat === "one" || root.stateData.repeat === "all"
          tooltipText: L.tr("Повтор")
          foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.hasTrack
          onClicked: root.request("repeat", { value: root.stateData.repeat === "off" ? "all" : (root.stateData.repeat === "all" ? "one" : "off") })
        }
        IconButton { icon: "settings"; tooltipText: L.tr("Настройки"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.settingsRequested() }
      }
    }
  }
}
