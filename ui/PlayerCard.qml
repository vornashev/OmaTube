import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real pendingVolume: -1
  signal playlistPickerRequested(var media, var anchorItem)
  signal channelRequested(var entity)

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  readonly property var media: currentEntry ? currentEntry.media : ({})
  readonly property string videoMode: logic ? logic.videoMode : "audio"
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real position: Number(stateData.position || 0)
  readonly property real volume: pendingVolume >= 0 ? pendingVolume : Number(stateData.volume === undefined ? 100 : stateData.volume)
  readonly property bool hasTrack: Boolean(currentEntry)
  property string savedVideoId: ""
  property string copiedUrl: ""
  Timer { id: copiedReset; interval: 1500; onTriggered: root.copiedUrl = "" }
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property var chapters: stateData.info && stateData.info.chapters ? stateData.info.chapters : []
  readonly property int chapterIndex: {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (position >= chapters[i].start) found = i
    return found
  }
  readonly property bool authorLinked: Boolean(media.authorId)

  function request(command, payload) {
    if (logic) logic.request(command, payload || ({}))
  }

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    var rest = seconds % 60
    return Math.floor(seconds / 60) + ":" + (rest < 10 ? "0" : "") + rest
  }

  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0) || value === null || value === undefined || value === "") return ""
    if (count >= 1000000000) return (count / 1000000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млрд")
    if (count >= 1000000) return (count / 1000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }

  readonly property string metaLine: {
    var parts = []
    var views = formatCount(media.viewCount)
    var likes = formatCount(media.likeCount)
    if (views !== "") parts.push(views + L.tr(" просмотров"))
    if (likes !== "") parts.push("♥ " + likes)
    return parts.join(" · ")
  }

  function previewVolume(mouse) {
    pendingVolume = Math.max(0, Math.min(100, 100 * mouse.x / Math.max(1, volumeMouse.width)))
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(24)
    spacing: Style.space(16)

    Rectangle {
      id: cover
      width: parent.width
      height: Math.round(width * 9 / 16)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      clip: true

      CatalogImage {
        anchors.fill: parent
        requestedSource: String(root.media.thumbnailUrl || "")
        foreground: root.foreground
        fontFamily: root.fontFamily
        emptyIcon: "󰗃"
        fillMode: Image.PreserveAspectCrop
      }

      Rectangle {
        anchors.fill: parent
        visible: root.stateData.state === "loading"
        color: Qt.rgba(0, 0, 0, .45)
        Icon {
          id: spinner
          anchors.centerIn: parent
          name: "loader-circle"
          size: Style.space(28)
          color: Color.accent
          RotationAnimator on rotation { running: spinner.animationVisible; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running && spinner) spinner.rotation = 0 }
        }
      }

      Item {
        visible: root.hasTrack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(10)
        height: Style.space(21)

        Rectangle {
          anchors.left: parent.left
          height: parent.height
          width: modeRow.implicitWidth + Style.space(16)
          color: "#000000B3"
          Row {
            id: modeRow
            anchors.centerIn: parent
            spacing: Style.space(6)
            Icon {
              anchors.verticalCenter: parent.verticalCenter
              name: root.videoMode === "audio" ? "headphones" : (root.videoMode === "tile" ? "panels-top-left" : "picture-in-picture-2")
              size: Style.space(12)
              color: "#FFFFFF"
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.videoMode === "audio" ? L.tr("АУДИО") : (root.videoMode === "tile" ? L.tr("ТАЙЛ") : L.tr("ОКНО"))
              color: "#FFFFFF"
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.letterSpacing: 1
            }
          }
        }
        Rectangle {
          visible: root.duration > 0
          anchors.right: parent.right
          height: parent.height
          width: durationText.implicitWidth + Style.space(16)
          color: "#000000B3"
          Text {
            id: durationText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.formatTime(root.duration)
            color: "#FFFFFF"
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
          }
        }
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(5)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || L.tr("Очередь пуста"))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.space(17)
        font.bold: true
        lineHeight: 1.3
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Item {
        width: parent.width
        height: authorText.implicitHeight
        Text {
          id: authorText
          width: Math.min(parent.width, implicitWidth)
          textFormat: Text.PlainText
          text: L.tb(root.media.author || (root.hasTrack ? L.tr("Автор неизвестен") : L.tr("Добавьте видео или найдите его в каталоге")))
          color: root.hasTrack ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(13)
          font.underline: authorMouse.containsMouse && root.authorLinked
          elide: Text.ElideRight
        }
        MouseArea {
          id: authorMouse
          anchors.fill: authorText
          enabled: root.authorLinked
          hoverEnabled: true
          cursorShape: root.authorLinked ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.channelRequested({ source: "youtube", kind: "channel", id: L.tb(root.media.authorId), title: L.tb(root.media.author || "") })
        }
      }
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: root.stateData.state === "error" ? L.tr("ОШИБКА ВОСПРОИЗВЕДЕНИЯ") : (root.hasTrack ? root.metaLine : "")
        color: root.stateData.state === "error" ? Color.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        elide: Text.ElideRight
      }
    }

    Rectangle {
      id: errorBox
      visible: root.stateData.state === "error"
      width: parent.width
      height: visible ? errorColumn.implicitHeight + Style.space(20) : 0
      color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .08)
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .5)
      Column {
        id: errorColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(10)
        spacing: Style.space(6)
        Row {
          spacing: Style.space(8)
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "triangle-alert"; size: Style.space(14); color: Color.urgent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tr("mpv не смог открыть поток")
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            font.bold: true
          }
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: L.tb(root.stateData.error ? root.stateData.error.message || "" : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          wrapMode: Text.WordWrap
        }
        Row {
          spacing: Style.space(6)
          Pill {
            text: L.tr("ПОВТОРИТЬ"); selected: true; foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: if (root.currentEntry) root.request("queue_play", { entryId: root.currentEntry.entryId })
          }
          Pill {
            text: L.tr("ПРОПУСТИТЬ"); foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.request("next")
          }
          Pill {
            text: L.tr("ЛОГ"); foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", L.tb(root.stateData.error ? root.stateData.error.message || "" : "")])
          }
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(10)
      Text {
        id: timeLeft
        width: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.formatTime(seekArea.position)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      Timeline {
        id: seekArea
        width: parent.width - timeLeft.width - timeRight.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        thin: false
        activeHeight: Style.space(4)
        logic: root.logic
        foreground: root.foreground
        fontFamily: root.fontFamily
        gapColor: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
      }
      Text {
        id: timeRight
        width: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: root.formatTime(root.duration)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }

    Row {
      visible: root.chapterIndex >= 0
      width: parent.width
      spacing: Style.space(8)
      Icon { anchors.verticalCenter: parent.verticalCenter; name: "list-tree"; size: Style.space(13); color: Color.accent }
      Text {
        width: parent.width - Style.space(21)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: L.tr("Глава ") + (root.chapterIndex + 1) + "/" + root.chapters.length + " · "
          + (root.chapterIndex >= 0 ? root.chapters[root.chapterIndex].title : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        elide: Text.ElideRight
      }
    }

    Item {
      width: parent.width
      height: Style.space(48)

      IconButton {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        icon: "shuffle"
        active: root.stateData.shuffle === true
        enabled: root.hasTrack
        tooltipText: root.stateData.shuffle ? L.tr("Выключить перемешивание") : L.tr("Перемешивать очередь")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.request("shuffle", { value: !root.stateData.shuffle })
      }

      Row {
        anchors.centerIn: parent
        spacing: Style.space(14)
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          icon: "skip-back"
          iconSize: 18
          enabled: root.hasTrack
          tooltipText: L.tr("Предыдущий")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.request("previous")
        }
        Item {
          width: Style.space(48)
          height: Style.space(48)
          opacity: root.hasTrack ? 1 : .4
          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: playMouse.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .28) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
            border.width: Math.max(1.5, Style.space(1.5))
            border.color: Color.accent
          }
          Icon {
            anchors.centerIn: parent
            name: root.stateData.state === "playing" ? "pause" : "play"
            size: Style.space(20)
            color: Color.accent
          }
          MouseArea {
            id: playMouse
            anchors.fill: parent
            enabled: root.hasTrack
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.request("toggle_pause")
          }
          Accessible.role: Accessible.Button
          Accessible.name: root.stateData.state === "playing" ? L.tr("Пауза") : L.tr("Продолжить")
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          icon: "skip-forward"
          iconSize: 18
          enabled: root.hasTrack
          tooltipText: L.tr("Следующий")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.request("next")
        }
      }

      IconButton {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        icon: root.stateData.repeat === "one" ? "repeat-1" : "repeat"
        active: root.stateData.repeat === "one" || root.stateData.repeat === "all"
        enabled: root.hasTrack
        tooltipText: root.stateData.repeat === "one" ? L.tr("Повторять текущий трек")
          : (root.stateData.repeat === "all" ? L.tr("Повторять очередь") : L.tr("Повтор выключен"))
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.request("repeat", { value: root.stateData.repeat === "off" ? "all"
          : (root.stateData.repeat === "all" ? "one" : "off") })
      }
    }

    Row {
      width: parent.width
      height: Style.space(16)
      spacing: Style.space(12)
      MouseArea {
        width: Style.space(16)
        height: parent.height
        cursorShape: Qt.PointingHandCursor
        onClicked: root.request("mute", { value: !root.stateData.muted })
        Icon {
          anchors.fill: parent
          name: root.stateData.muted || root.volume <= 0 ? "volume-x" : (root.volume < 50 ? "volume-1" : "volume-2")
          size: Style.space(16)
          color: root.dim
        }
      }
      Item {
        width: parent.width - Style.space(16) - volumeText.width - parent.spacing * 2
        height: parent.height
        Rectangle {
          id: volumeTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          color: root.line
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.volume / 100))
            height: parent.height
            color: root.stateData.muted ? root.dim : root.foreground
          }
        }
        MouseArea {
          id: volumeMouse
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          preventStealing: true
          onPressed: function(mouse) { root.previewVolume(mouse) }
          onPositionChanged: function(mouse) {
            if (!pressed) return
            root.previewVolume(mouse)
            volumeThrottle.pending = true
          }
          onReleased: function(mouse) {
            root.previewVolume(mouse)
            root.request("volume", { value: Math.round(root.pendingVolume) })
            volumeReset.restart()
          }
        }
      }
      Text {
        id: volumeText
        width: Style.space(28)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: Math.round(root.volume) + "%"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      Timer {
        id: volumeThrottle
        property bool pending: false
        interval: 150
        repeat: true
        running: pending
        onTriggered: {
          pending = false
          root.request("volume", { value: Math.round(root.pendingVolume) })
        }
      }
      Timer {
        id: volumeReset
        interval: 1200
        onTriggered: root.pendingVolume = -1
      }
    }

    Item { width: 1; height: Math.max(0, parent.height - y - (toast.visible ? toast.height + parent.spacing : 0) - actions.height - parent.spacing) }

    SkipToast {
      id: toast
      width: parent.width
      logic: root.logic
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Row {
      id: actions
      width: parent.width
      spacing: Style.space(8)
      readonly property real modeWidth: Math.floor((width - Style.space(34) * 4 - spacing * 5) / 2)
      Pill {
        objectName: "mode-audio"
        width: actions.modeWidth
        text: L.tr("АУДИО")
        icon: "headphones"
        selected: root.videoMode === "audio"
        enabled: !(root.logic && root.logic.videoLoading)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: if (root.videoMode !== "audio") root.request("video_mode", { value: "audio" })
      }
      Pill {
        objectName: "mode-video"
        width: actions.modeWidth
        text: root.videoMode === "floating" ? L.tr("ОКНО") : L.tr("ВИДЕО")
        icon: root.videoMode === "floating" ? "picture-in-picture-2" : "monitor-play"
        selected: root.videoMode !== "audio"
        enabled: !(root.logic && root.logic.videoLoading)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.request("video_mode", { value: root.videoMode === "tile" ? "floating" : "tile" })
      }
      Pill {
        width: Style.space(34)
        selected: root.savedVideoId !== "" && root.savedVideoId === String(root.media.videoId || "")
        icon: selected ? "heart-filled" : "heart"
        enabled: root.hasTrack
        tooltipText: selected ? L.tr("Убрать из медиатеки") : L.tr("Сохранить в медиатеку")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          var id = String(root.media.videoId || "")
          var save = !selected
          root.savedVideoId = save ? id : ""
          root.request("save_media", { media: root.media, saved: save })
        }
      }
      Pill {
        id: playlistButton
        width: Style.space(34)
        icon: "bookmark"
        enabled: root.hasTrack
        tooltipText: L.tr("Добавить в плейлист")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.playlistPickerRequested(root.media, playlistButton)
      }
      Pill {
        width: Style.space(34)
        icon: root.copiedUrl !== "" && root.copiedUrl === String(root.media.canonicalUrl || "") ? "check" : "share-2"
        enabled: root.hasTrack && Boolean(root.media.canonicalUrl)
        tooltipText: L.tr("Копировать ссылку")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          Quickshell.execDetached(["/usr/bin/wl-copy", String(root.media.canonicalUrl)])
          root.copiedUrl = String(root.media.canonicalUrl)
          copiedReset.restart()
        }
      }
      Pill {
        id: optionsButton
        objectName: "playback-options"
        width: Style.space(34)
        icon: "gauge"
        selected: playbackPopover.opened
        tooltipText: L.tr("Режим, скорость, таймер сна")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: {
          if (playbackPopover.opened) playbackPopover.close()
          else {
            // Attach to the live button so outside dismissal excludes the toggle.
            playbackPopover.parent = optionsButton
            playbackPopover.open()
          }
        }
      }
    }
  }

  PlaybackPopover {
    id: playbackPopover
    logic: root.logic
    foreground: root.foreground
    fontFamily: root.fontFamily
    anchorItem: optionsButton
    boundsItem: root
  }
}
