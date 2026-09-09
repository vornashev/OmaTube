import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal playlistPickerRequested(var media)

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  readonly property var queue: logic && logic.details.queue ? logic.details.queue : []
  readonly property color dim: Qt.darker(foreground, 1.5)

  function request(command, payload) {
    if (logic) logic.request(command, payload || ({}))
  }

  function submitUrl(placement) {
    var url = urlField.text.trim()
    if (!url) return
    request(placement === "play" ? "play_url" : "enqueue_url", placement === "play"
      ? { url: url } : { url: url, placement: "end" })
    urlField.selectAll()
  }

  function move(row, delta) {
    var index = queue.findIndex(function(entry) { return entry.entryId === row.entryId })
    var target = index + delta
    if (index < 0 || target < 0 || target >= queue.length) return
    request("queue_move", {
      entryId: row.entryId,
      beforeEntryId: delta < 0 ? queue[target].entryId
        : (target + 1 < queue.length ? queue[target + 1].entryId : null)
    })
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      width: parent.width
      height: Style.space(36)
      spacing: Style.space(4)
      TextField {
        id: urlField
        width: parent.width - playUrl.width - addUrl.width - parent.spacing * 2
        height: parent.height
        placeholderText: "Ссылка на видео или плейлист"
        font.family: root.fontFamily
        onAccepted: root.submitUrl("play")
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: playUrl
        width: Style.space(36)
        height: parent.height
        iconText: "󰐊"
        iconSize: Style.font.icon
        tooltipText: "Воспроизвести ссылку"
        foreground: root.foreground
        bordered: true
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.submitUrl("play")
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: addUrl
        width: Style.space(36)
        height: parent.height
        iconText: "󰐕"
        iconSize: Style.font.icon
        tooltipText: "Добавить ссылку в конец очереди"
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.submitUrl("queue")
      }
    }

    Row {
      width: parent.width
      height: Style.space(30)
      Text {
        width: parent.width - clearQueue.width
        anchors.verticalCenter: parent.verticalCenter
        text: "ОЧЕРЕДЬ" + (root.queue.length > 0 ? "  ·  " + root.queue.length : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: .8
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: clearQueue
        visible: root.queue.length > 0
        width: visible ? Style.space(30) : 0
        height: Style.space(30)
        iconText: "󰆴"
        iconSize: Style.font.icon
        tooltipText: "Очистить очередь"
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.request("queue_clear")
      }
    }

    Item {
      width: parent.width
      height: Math.max(0, parent.height - y)

      Column {
        visible: root.queue.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(7)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "󰝚"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(28)
        }
        Text {
          width: parent.width
          text: "Очередь пока пуста"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          width: parent.width
          text: "Вставьте ссылку выше или найдите видео в каталоге"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      ListView {
        id: queueView
        visible: root.queue.length > 0
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height
        spacing: Style.space(2)
        model: root.queue
        delegate: MediaRow {
          onFocusRequested: queueView.positionViewAtIndex(index, ListView.Contain)
          required property var modelData
          required property int index
          width: queueView.width - (queueView.contentHeight > queueView.height ? Style.space(8) : 0)
          item: modelData
          rowNumber: index + 1
          current: root.currentEntry && modelData.entryId === root.currentEntry.entryId
          compact: true
          showThumbnail: true
          allowEnqueue: false
          foreground: root.foreground
          fontFamily: root.fontFamily
          onPlayRequested: row => root.request("queue_play", { entryId: row.entryId })
          onRemoveRequested: row => root.request("queue_remove", { entryId: row.entryId })
          onMoveUpRequested: row => root.move(row, -1)
          onMoveDownRequested: row => root.move(row, 1)
          onSaveRequested: row => root.request("save_media", { media: row.media, saved: true })
          onPlaylistRequested: media => root.playlistPickerRequested(media)
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }
    }
  }
}
