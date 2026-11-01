import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

// X2b · the thin panel expanded into a sheet over the current tab. The tab stays under a scrim
// and keeps its state; ˅ / Esc / a click on the scrim folds it, ↗ jumps to «Сейчас».
Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color surface: Color.background
  property bool open: false
  property string tab: "chapters"
  property real topGap: Style.space(145)
  signal closeRequested()
  signal nowRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var current: stateData.current || null
  readonly property var media: current ? current.media || ({}) : ({})
  readonly property string playState: String(stateData.state || "idle")
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real position: Number(stateData.position || 0)
  readonly property real volume: Number(stateData.volume === undefined ? 100 : stateData.volume)
  readonly property var chapters: stateData.info && stateData.info.chapters ? stateData.info.chapters : []
  readonly property var segments: stateData.sponsor && stateData.sponsor.segments ? stateData.sponsor.segments : []
  readonly property string description: stateData.info ? String(stateData.info.description || "") : ""
  readonly property var upcoming: {
    var rows = logic && logic.details.queue ? logic.details.queue : []
    var index = rows.findIndex(function(row) { return current && row.entryId === current.entryId })
    return rows.slice(index + 1)
  }
  readonly property int chapterIndex: {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (position >= Number(chapters[i].start)) found = i
    return found
  }
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  property real pendingVolume: -1

  function chapterEnd(index) {
    if (index + 1 < chapters.length) return Number(chapters[index + 1].start)
    return Number(chapters[index].end || duration)
  }
  function chapterTag(index) {
    var start = Number(chapters[index].start), end = chapterEnd(index)
    for (var i = 0; i < segments.length; ++i)
      if (segments[i].start < end && segments[i].end > start) return segments[i].category
    return ""
  }
  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0) || value === null || value === undefined || value === "") return ""
    if (count >= 1000000) return (count / 1000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }

  visible: open || sheet.y < height
  enabled: open

  Rectangle {
    id: scrim
    anchors.fill: parent
    color: "black"
    opacity: root.open ? .55 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
    MouseArea { anchors.fill: parent; onClicked: root.closeRequested() }
  }

  Rectangle {
    id: sheet
    x: 0
    y: root.open ? root.topGap : root.height
    width: parent.width
    height: parent.height - root.topGap
    color: root.surface
    Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    MouseArea { anchors.fill: parent }
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: Math.max(1, Style.space(1)); color: Color.accent }

    Item {
      id: header
      width: parent.width
      height: Style.space(44)
      Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.line }
      Rectangle {
        anchors.centerIn: parent
        width: Style.space(40)
        height: Style.space(3)
        radius: height / 2
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .35)
        MouseArea { anchors.fill: parent; anchors.margins: -Style.space(10); cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Style.space(16)
        spacing: Style.space(10)
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: L.tr("Esc · ˅ свернуть")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
        IconButton {
          anchors.verticalCenter: parent.verticalCenter
          icon: "external-link"; iconSize: 15
          tooltipText: L.tr("Открыть «Сейчас»")
          foreground: root.foreground; fontFamily: root.fontFamily
          onClicked: root.nowRequested()
        }
        Rectangle {
          width: Style.space(28)
          height: width
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, foldMouse.containsMouse ? .32 : .2)
          Icon { anchors.centerIn: parent; name: "chevron-down"; size: Style.space(16); color: Color.accent }
          MouseArea { id: foldMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
        }
      }
    }

    Item {
      id: left
      anchors.top: header.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: Math.round(parent.width * .42)
      clip: true
      Rectangle { anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: Math.max(1, Style.space(1)); color: root.line }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(24)
        anchors.topMargin: Style.space(18)
        spacing: Style.space(12)

        Rectangle {
          id: frame
          width: parent.width
          height: Math.min(Math.round(width * 9 / 16), left.height * .42)
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
            anchors.margins: Style.space(8)
            width: modeRow.implicitWidth + Style.space(14)
            height: Style.space(20)
            color: Qt.rgba(0, 0, 0, .72)
            Row {
              id: modeRow
              anchors.centerIn: parent
              spacing: Style.space(5)
              Icon { anchors.verticalCenter: parent.verticalCenter; name: root.logic && root.logic.videoMode !== "audio" ? "monitor-play" : "headphones"; size: Style.space(11); color: "#FFFFFF" }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.logic && root.logic.videoMode !== "audio" ? L.tr("ВИДЕО") : L.tr("АУДИО")
                color: "#FFFFFF"
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                font.letterSpacing: 1
              }
            }
          }
          Rectangle {
            visible: root.chapterIndex >= 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Style.space(8)
            width: Math.min(chapterBadge.implicitWidth + Style.space(14), parent.width * .6)
            height: Style.space(20)
            color: Qt.rgba(0, 0, 0, .72)
            Text {
              id: chapterBadge
              anchors.centerIn: parent
              width: parent.width - Style.space(14)
              textFormat: Text.PlainText
              text: root.chapterIndex >= 0 ? L.tr("гл. ") + (root.chapterIndex + 1) + "/" + root.chapters.length + " · "
                + String(root.chapters[root.chapterIndex].title || "") : ""
              color: "#FFFFFF"
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              elide: Text.ElideRight
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(root.media.title || L.tr("Ничего не играет"))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(15)
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: [L.tb(root.media.author || ""), root.formatCount(root.media.viewCount)].filter(function(part) { return part !== "" }).join(" · ")
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          Item { width: 1; height: Style.space(2) }
          Timeline {
            id: seek
            width: parent.width
            thin: false
            activeHeight: Style.space(5)
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            gapColor: root.surface
          }
          Item {
            width: parent.width
            height: Style.space(14)
            Text { anchors.left: parent.left; text: seek.formatTime(seek.position); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
            Text { anchors.right: parent.right; text: seek.formatTime(root.duration); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
          }
        }

        Item {
          width: parent.width
          height: Style.space(48)
          IconButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            icon: "shuffle"; iconSize: 16
            active: root.stateData.shuffle === true
            tooltipText: L.tr("Перемешать")
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.logic.request("shuffle", { value: root.stateData.shuffle !== true })
          }
          Row {
            anchors.centerIn: parent
            spacing: Style.space(14)
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              icon: "skip-back"; iconSize: 18
              tooltipText: L.tr("Предыдущий")
              foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.logic.request("previous")
            }
            Rectangle {
              width: Style.space(46)
              height: width
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, sheetPlay.containsMouse ? .3 : .18)
              border.width: Math.max(1, Style.space(1.5))
              border.color: Color.accent
              Icon {
                id: playbackGlyph
                anchors.centerIn: parent
                name: root.playState === "loading" ? "loader-circle" : (root.playState === "playing" ? "pause" : "play")
                size: Style.space(20)
                color: Color.accent
                NumberAnimation on rotation { running: root.playState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
              }
              MouseArea {
                id: sheetPlay
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.logic.request(root.playState === "loading" ? "cancel_load" : "toggle_pause")
              }
            }
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              icon: "skip-forward"; iconSize: 18
              tooltipText: L.tr("Следующий")
              foreground: root.foreground; fontFamily: root.fontFamily
              onClicked: root.logic.request("next")
            }
          }
          IconButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: root.stateData.repeat === "one" ? "repeat-1" : "repeat"; iconSize: 16
            active: root.stateData.repeat === "all" || root.stateData.repeat === "one"
            tooltipText: L.tr("Повтор")
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.logic.request("repeat", { value: root.stateData.repeat === "off" ? "all" : (root.stateData.repeat === "all" ? "one" : "off") })
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(10)
          readonly property real shown: root.pendingVolume >= 0 ? root.pendingVolume : root.volume
          IconButton {
            width: Style.space(22); height: Style.space(22)
            anchors.verticalCenter: parent.verticalCenter
            icon: root.stateData.muted === true ? "volume-x" : "volume-2"; iconSize: 14
            tooltipText: L.tr("Без звука")
            foreground: root.foreground; fontFamily: root.fontFamily
            onClicked: root.logic.request("mute", { value: root.stateData.muted !== true })
          }
          Item {
            id: volumeTrack
            width: parent.width - Style.space(22) - volumeLabel.width - parent.spacing * 2
            height: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: Style.space(4); color: root.line }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * parent.parent.shown / 100; height: Style.space(4); color: root.foreground }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              preventStealing: true
              function pick(mouse) { root.pendingVolume = Math.max(0, Math.min(100, 100 * mouse.x / Math.max(1, width))) }
              onPressed: mouse => pick(mouse)
              onPositionChanged: mouse => { if (pressed) pick(mouse) }
              onReleased: mouse => { pick(mouse); root.logic.request("volume", { value: Math.round(root.pendingVolume) }); root.pendingVolume = -1 }
            }
          }
          Text {
            id: volumeLabel
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(parent.shown) + "%"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
          }
        }
      }
    }

    Item {
      anchors.top: header.bottom
      anchors.bottom: parent.bottom
      anchors.left: left.right
      anchors.right: parent.right

      TabStrip {
        id: tabs
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Style.space(24)
        anchors.rightMargin: Style.space(24)
        anchors.topMargin: Style.space(14)
        labelSize: 11
        tabSpacing: 24
        leftInset: 2
        foreground: root.foreground
        fontFamily: root.fontFamily
        current: root.tab
        tabs: [{ label: L.tr("ГЛАВЫ"), value: "chapters" }, { label: L.tr("ОЧЕРЕДЬ · ") + root.upcoming.length, value: "queue" },
               { label: L.tr("ОПИСАНИЕ"), value: "description" }]
        onSelected: value => root.tab = value
      }

      Item {
        anchors.top: tabs.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.space(24)
        anchors.rightMargin: Style.space(24)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(12)

        Text {
          visible: root.tab === "chapters" && root.chapters.length === 0
          anchors.centerIn: parent
          text: L.tr("В этом видео нет глав")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
        ListView {
          id: chapterList
          visible: root.tab === "chapters"
          anchors.fill: parent
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.chapters
          delegate: Item {
            id: chapterRow
            required property var modelData
            required property int index
            readonly property bool active: index === root.chapterIndex
            readonly property string tag: root.chapterTag(index)
            width: chapterList.width
            height: Style.space(37)
            Rectangle {
              anchors.fill: parent
              color: chapterRow.active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
                : (chapterMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
            }
            Rectangle { visible: chapterRow.active; width: Math.max(2, Style.space(2)); height: parent.height; color: Color.accent }
            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(14)
              Text {
                width: Style.space(44)
                anchors.verticalCenter: parent.verticalCenter
                text: seek.formatTime(chapterRow.modelData.start)
                color: chapterRow.active ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(11)
              }
              Text {
                width: parent.width - Style.space(44) - tagBox.width - durationText.width - parent.spacing * 3
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: String(chapterRow.modelData.title || L.tr("Глава ") + (chapterRow.index + 1))
                color: chapterRow.active ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
                font.bold: chapterRow.active
                elide: Text.ElideRight
              }
              Rectangle {
                id: tagBox
                visible: chapterRow.tag !== ""
                width: visible ? tagText.implicitWidth + Style.space(10) : 0
                height: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: seek.categoryColors[chapterRow.tag] || Color.accent
                Text {
                  id: tagText
                  anchors.centerIn: parent
                  text: String(seek.categoryLabels[chapterRow.tag] || chapterRow.tag).toUpperCase()
                  color: seek.categoryColors[chapterRow.tag] || Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(9)
                  font.letterSpacing: 1
                }
              }
              Text {
                id: durationText
                anchors.verticalCenter: parent.verticalCenter
                text: chapterRow.active ? L.tr("осталось ") + seek.formatTime(root.chapterEnd(chapterRow.index) - root.position)
                  : seek.formatTime(root.chapterEnd(chapterRow.index) - Number(chapterRow.modelData.start))
                color: chapterRow.active ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(11)
              }
            }
            MouseArea {
              id: chapterMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: seek.seekTo(Number(chapterRow.modelData.start), "")
            }
          }
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }

        Text {
          visible: root.tab === "queue" && root.upcoming.length === 0
          anchors.centerIn: parent
          text: L.tr("Дальше в очереди ничего нет")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
        ListView {
          id: queueList
          visible: root.tab === "queue"
          anchors.fill: parent
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.upcoming
          delegate: MediaRow {
            showQueueMark: false
            required property var modelData
            required property int index
            width: queueList.width
            item: modelData
            rowNumber: index + 1
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            onPlayRequested: row => root.logic.request("queue_play", { entryId: row.entryId })
            onRemoveRequested: row => root.logic.request("queue_remove", { entryId: row.entryId })
            onPlaylistRequested: media => root.logic.playlistPickerRequested(media)
            onSaveRequested: row => root.logic.request("save_media", { media: row.media || row, saved: true })
          }
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }

        Flickable {
          visible: root.tab === "description"
          anchors.fill: parent
          clip: true
          contentHeight: descriptionText.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          Text {
            id: descriptionText
            width: parent.width
            textFormat: Text.PlainText
            text: root.description !== "" ? root.description : L.tr("Описания нет")
            color: root.description !== "" ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            lineHeight: 1.3
            wrapMode: Text.Wrap
          }
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }
      }
    }
  }
}
