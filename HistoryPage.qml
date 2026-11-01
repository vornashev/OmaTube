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
  property var items: []
  property int total: 0
  property var nextOffset: null
  property string filter: "all"
  property bool loading: false
  property bool confirmClear: false
  property int requestId: 0
  property int moreRequestId: 0
  property int seenRevision: -1

  readonly property bool compact: width < Style.space(600)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property bool recording: !logic || !logic.stateData.preferences || logic.stateData.preferences.historyEnabled !== false
  readonly property var groups: {
    var now = new Date()
    var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000
    var result = [{ label: L.tr("СЕГОДНЯ"), min: startToday, items: [] }, { label: L.tr("ВЧЕРА"), min: startToday - 86400, items: [] },
      { label: L.tr("НА ЭТОЙ НЕДЕЛЕ"), min: startToday - 6 * 86400, items: [] }, { label: L.tr("РАНЬШЕ"), min: -1, items: [] }]
    items.forEach(function(item) {
      var p = item.watchProgress
      var fraction = p && p.duration > 0 ? p.position / p.duration : 1
      var resumable = p && p.position >= 15 && fraction < 0.95
      if (filter === "continue" && !resumable) return
      if (filter === "done" && resumable) return
      for (var i = 0; i < result.length; ++i) {
        if (Number(item.startedAt) >= result[i].min) { result[i].items.push(item); break }
      }
    })
    return result.filter(function(group) { return group.items.length > 0 })
  }

  function load() {
    if (!logic) return
    loading = true
    requestId = logic.request("collection", { section: "history", offset: 0 })
  }

  function loadMore() {
    if (!logic || nextOffset === null || loading) return
    loading = true
    moreRequestId = logic.request("collection", { section: "history", offset: nextOffset })
  }

  function clockTime(timestamp) {
    var date = new Date(Number(timestamp) * 1000)
    return (date.getHours() < 10 ? "0" : "") + date.getHours() + ":" + (date.getMinutes() < 10 ? "0" : "") + date.getMinutes()
  }

  function remaining(item) {
    var p = item.watchProgress
    if (!p || !(p.duration > 0)) return ""
    if (p.position < 15 || p.position >= p.duration * 0.95) return L.tr("просмотрено")
    var minutes = Math.max(1, Math.round((p.duration - p.position) / 60))
    return L.tr("ещё ") + (minutes >= 60 ? Math.floor(minutes / 60) + L.tr(" ч ") + (minutes % 60) + L.tr(" мин") : minutes + L.tr(" мин")) + L.tr(" · продолжить")
  }

  function resumes(item) {
    var p = item.watchProgress
    return p && p.position >= 15 && p.position < p.duration * 0.95
  }

  function play(item) {
    if (!logic || !item.canonicalUrl) return
    logic.request("play_url", { url: item.canonicalUrl, start: resumes(item) ? Math.floor(item.watchProgress.position) : 0, media: item })
  }

  function requestClear() {
    if (!confirmClear) { confirmClear = true; clearTimer.restart(); return }
    confirmClear = false
    logic.request("history_clear")
  }

  onLogicChanged: if (logic) load()
  onVisibleChanged: if (visible) load()

  Timer { id: clearTimer; interval: 3000; onTriggered: root.confirmClear = false }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      var result = root.logic.lastResult
      if (id === root.requestId && result && result.items) {
        root.items = result.items
        root.total = Number(result.total || result.items.length)
        root.nextOffset = result.nextOffset === undefined ? null : result.nextOffset
        root.loading = false
      } else if (id === root.moreRequestId && result && result.items) {
        root.items = root.items.concat(result.items)
        root.nextOffset = result.nextOffset === undefined ? null : result.nextOffset
        root.loading = false
      } else if (root.logic.lastCommand === "history_clear" || root.logic.lastCommand === "history_remove") {
        root.load()
      }
    }
    function onStateDataChanged() {
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenRevision < 0) root.seenRevision = revision
      else if (revision !== root.seenRevision) { root.seenRevision = revision; if (root.visible) root.load() }
    }
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: Style.space(root.compact ? 0 : 24)
    anchors.rightMargin: Style.space(root.compact ? 0 : 24)
    anchors.topMargin: Style.space(root.compact ? 10 : 20)
    spacing: Style.space(root.compact ? 10 : 14)

    Flow {
      id: header
      width: parent.width
      spacing: Style.space(10)

      Column {
        width: root.compact ? parent.width : parent.width - filters.width - parent.spacing
        spacing: Style.space(3)
        Text {
          text: L.tr("История")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(20)
          font.bold: true
        }
        Text {
          width: parent.width
          text: root.total + L.tr(" просмотров · хранится только на этом компьютере") + (root.recording ? "" : L.tr(" · запись выключена"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          elide: Text.ElideRight
        }
      }

      Row {
        id: filters
        spacing: Style.space(6)
        Pill { text: L.tr("ВСЁ"); height: Style.space(25); selected: root.filter === "all"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.filter = "all" }
        Pill { text: L.tr("ПРОДОЛЖИТЬ"); height: Style.space(25); selected: root.filter === "continue"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.filter = "continue" }
        Pill { text: L.tr("ПРОСМОТРЕНО"); height: Style.space(25); selected: root.filter === "done"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.filter = "done" }
        Pill {
          text: root.confirmClear ? L.tr("ТОЧНО?") : L.tr("ОЧИСТИТЬ")
          icon: "trash-2"
          iconSize: 12
          height: Style.space(25)
          danger: true
          enabled: root.total > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.requestClear()
        }
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.max(0, parent.height - y)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.groups
      spacing: Style.space(14)
      delegate: Column {
        required property var modelData
        width: list.width - (list.contentHeight > list.height ? Style.space(8) : 0)
        spacing: Style.space(2)

        Row {
          width: parent.width
          height: Style.space(17)
          spacing: Style.space(10)
          Text {
            id: groupLabel
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label + " · " + modelData.items.length
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: 1.5
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - groupLabel.width - parent.spacing)
            height: Math.max(1, Style.space(1))
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
          }
        }

        Repeater {
          model: modelData.items
          delegate: Item {
            id: row
            required property var modelData
            readonly property var progress: modelData.watchProgress
            readonly property bool partial: root.resumes(modelData)
            width: parent.width
            height: Style.space(58)
            HoverHandler { id: rowHover }
            Rectangle {
              anchors.fill: parent
              color: rowHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent"
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.play(row.modelData)
            }
            Row {
              anchors.fill: parent
              anchors.topMargin: Style.space(4)
              anchors.bottomMargin: Style.space(4)
              anchors.leftMargin: Style.space(2)
              anchors.rightMargin: Style.space(2)
              spacing: Style.space(root.compact ? 10 : 14)

              Rectangle {
                width: Style.space(root.compact ? 80 : 88)
                height: parent.height
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
                clip: true
                CatalogImage {
                  anchors.fill: parent
                  requestedSource: String(row.modelData.thumbnailUrl || (row.modelData.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(row.modelData.videoId) + "/hqdefault.jpg" : ""))
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fillMode: Image.PreserveAspectCrop
                }
                Rectangle {
                  visible: row.partial
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  width: parent.width * Math.min(1, row.progress.position / row.progress.duration)
                  height: Math.max(2, Style.space(3))
                  color: Color.accent
                }
              }

              Column {
                width: parent.width - Style.space(root.compact ? 80 : 88) - (timeLabel.visible ? timeLabel.width + parent.spacing : 0) - actions.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(5)
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: String(row.modelData.title || row.modelData.videoId)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(12)
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: [L.tb(row.modelData.author || ""), root.remaining(row.modelData)].filter(function(part) { return part !== "" }).join(" · ")
                  color: row.partial ? Color.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  elide: Text.ElideRight
                }
              }

              Text {
                id: timeLabel
                visible: !root.compact
                width: visible ? implicitWidth : 0
                anchors.verticalCenter: parent.verticalCenter
                text: root.clockTime(row.modelData.startedAt)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(11)
              }

              QueueMark {
                id: historyMark
                anchors.verticalCenter: parent.verticalCenter
                logic: root.logic
                videoId: String(row.modelData.videoId || "")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                id: actions
                visible: rowHover.hovered
                width: visible ? implicitWidth : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                IconButton { icon: "play"; iconSize: 14; tooltipText: row.partial ? L.tr("Продолжить") : L.tr("Играть"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.play(row.modelData) }
                IconButton { visible: !historyMark.visible; width: visible ? implicitWidth : 0; icon: "list-plus"; iconSize: 14; tooltipText: L.tr("В мою очередь"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.logic.request("enqueue_url", { url: row.modelData.canonicalUrl, placement: "end", media: row.modelData }) }
                IconButton { icon: "x"; iconSize: 14; tooltipText: L.tr("Убрать из истории"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.logic.request("history_remove", { playId: row.modelData.playId }) }
              }
            }
          }
        }
      }

      footer: Item {
        width: list.width
        height: root.nextOffset !== null ? Style.space(48) : Style.space(8)
        Pill {
          visible: root.nextOffset !== null
          anchors.centerIn: parent
          text: root.loading ? L.tr("ЗАГРУЖАЕМ…") : L.tr("ПОКАЗАТЬ ЕЩЁ")
          enabled: !root.loading
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.loadMore()
        }
      }

      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Text {
        visible: !root.loading && root.groups.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.items.length === 0 ? (root.recording ? L.tr("История пока пуста. Просмотры появятся здесь после 10 секунд воспроизведения.") : L.tr("Запись истории выключена в настройках"))
          : L.tr("В этом фильтре ничего нет")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }
  }
}
