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
  property var summary: ({ items: [], directory: "", used: 0, free: null, active: 0 })
  property int requestId: 0

  readonly property bool compact: width < Style.space(600)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var preferences: logic && logic.stateData.preferences ? logic.stateData.preferences : ({})
  readonly property var items: summary.items || []
  readonly property var activeItems: items.filter(function(row) { return row.state === "queued" || row.state === "running" || row.state === "paused" })
  readonly property var failedItems: items.filter(function(row) { return row.state === "failed" })
  readonly property var doneItems: items.filter(function(row) { return row.state === "done" })
  readonly property var sections: {
    var rows = []
    if (activeItems.length) rows.push({ kind: "header", label: L.tr("В ПРОЦЕССЕ · ") + activeItems.length, action: anyRunning ? L.tr("пауза для всех") : L.tr("продолжить все"), command: anyRunning ? "download_pause_all" : "download_resume_all" })
    activeItems.forEach(function(row) { rows.push({ kind: "item", row: row }) })
    if (failedItems.length) rows.push({ kind: "header", label: L.tr("ОШИБКИ · ") + failedItems.length })
    failedItems.forEach(function(row) { rows.push({ kind: "item", row: row }) })
    if (doneItems.length) rows.push({ kind: "header", label: L.tr("ГОТОВО · ") + doneItems.length, action: L.tr("открыть папку"), command: "open_folder" })
    doneItems.forEach(function(row) { rows.push({ kind: "item", row: row }) })
    return rows
  }
  readonly property bool anyRunning: activeItems.some(function(row) { return row.state === "running" })

  function formatSize(bytes) {
    var value = Number(bytes)
    if (!(value >= 0)) return "—"
    if (value >= 1073741824) return (value / 1073741824).toFixed(1).replace(".", L.decimal()) + L.tr(" ГБ")
    if (value >= 1048576) return Math.round(value / 1048576) + L.tr(" МБ")
    return Math.max(1, Math.round(value / 1024)) + L.tr(" КБ")
  }

  function describe(row) {
    if (row.state === "failed") return L.tb(row.error || L.tr("Не удалось скачать")) + L.tr(" · повторить")
    if (row.state === "done") return (row.kind === "audio" ? "opus" : "mp4") + " · " + formatSize(row.size)
    if (row.state === "queued") return L.tr("в очереди")
    var percent = row.total > 0 ? Math.round(100 * row.downloaded / row.total) : 0
    var text = row.state === "paused" ? L.tr("на паузе · ") + percent + "%" : percent + "% · " + formatSize(row.downloaded) + " / " + formatSize(row.total)
    if (row.state === "running" && row.speed) text += " · " + formatSize(row.speed) + L.tr("/с")
    if (row.state === "running" && row.eta) text += " · ~" + Math.round(row.eta) + L.tr(" с")
    return text
  }

  function refresh() { if (logic && visible) requestId = logic.request("downloads", ({})) }

  onVisibleChanged: if (visible) refresh()
  onLogicChanged: refresh()

  Timer {
    interval: 1000
    repeat: true
    running: root.visible && (root.summary.active > 0 || root.items.length === 0)
    onTriggered: root.refresh()
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var result = root.logic.lastResult
      if (result && result.items !== undefined && result.directory !== undefined) root.summary = result
      else if (String(root.logic.lastCommand).indexOf("download") === 0) root.refresh()
    }
  }

  Column {
    anchors.fill: parent
    anchors.topMargin: root.compact ? Style.space(10) : 0
    spacing: Style.space(root.compact ? 10 : 16)

    Row {
      width: parent.width
      height: Style.space(46)
      Column {
        width: parent.width - formatRow.width
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: L.tr("Загрузки")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(20)
          font.bold: true
        }
        Text {
          width: parent.width
          text: String(root.summary.directory || "").replace(/^\/home\/[^/]+/, "~") + " · " + root.formatSize(root.summary.used)
            + (root.summary.free ? L.tr(" · свободно ") + root.formatSize(root.summary.free) : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      Segmented {
        id: formatRow
        anchors.verticalCenter: parent.verticalCenter
        foreground: root.foreground
        fontFamily: root.fontFamily
        current: String(root.preferences.downloadKind || "audio")
        options: root.compact ? [{ value: "audio", label: L.tr("АУДИО") }, { value: "video", label: L.tr("ВИДЕО") }]
          : [{ value: "audio", label: L.tr("АУДИО · OPUS") }, { value: "video", label: L.tr("ВИДЕО · ") + Number(root.preferences.videoQuality || 1080) + "P" }]
        onChosen: value => root.logic.request("setting", { key: "downloadKind", value: value })
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.max(0, parent.height - y)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.sections
      spacing: Style.space(2)
      delegate: Loader {
        required property var modelData
        width: list.width - (list.contentHeight > list.height ? Style.space(8) : 0)
        sourceComponent: modelData.kind === "header" ? headerComponent : itemComponent
        property var entry: modelData
      }
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Text {
        visible: root.items.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: L.tr("Пока ничего не скачано. Выберите «Скачать» в меню трека (ПКМ) или в параметрах плеера.")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Component {
    id: headerComponent
    Row {
      height: Style.space(26)
      spacing: Style.space(10)
      Text {
        id: headerLabel
        anchors.verticalCenter: parent.verticalCenter
        text: entry.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - headerLabel.width - actionLabel.width - parent.spacing * 2)
        height: Math.max(1, Style.space(1))
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
      }
      Text {
        id: actionLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: entry.action !== undefined
        text: entry.action || ""
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (entry.command === "open_folder") Quickshell.execDetached(["xdg-open", String(root.summary.directory)])
            else root.logic.request(entry.command, ({}))
          }
        }
      }
    }
  }

  Component {
    id: itemComponent
    Item {
      readonly property var row: entry.row
      readonly property var media: row.media || ({})
      height: Style.space(58)
      Row {
        anchors.fill: parent
        anchors.topMargin: Style.space(4)
        anchors.bottomMargin: Style.space(4)
        spacing: Style.space(root.compact ? 10 : 14)
        Rectangle {
          width: Style.space(root.compact ? 72 : 88)
          height: parent.height
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
          clip: true
          CatalogImage {
            anchors.fill: parent
            requestedSource: String(media.thumbnailUrl || (media.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(media.videoId) + "/hqdefault.jpg" : ""))
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
        }
        Column {
          width: parent.width - Style.space(root.compact ? 72 : 88) - actions.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: String(media.title || row.videoId)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            elide: Text.ElideRight
          }
          Row {
            width: parent.width
            spacing: Style.space(10)
            Rectangle {
              visible: row.state === "running" || row.state === "paused" || row.state === "queued"
              width: parent.width * .62
              height: Math.max(3, Style.space(3))
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
              Rectangle {
                width: parent.width * (row.total > 0 ? Math.min(1, row.downloaded / row.total) : 0)
                height: parent.height
                color: row.state === "paused" ? root.dim : Color.accent
              }
            }
            Text {
              width: (row.state === "running" || row.state === "paused" || row.state === "queued") ? parent.width * .38 - parent.spacing : parent.width
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.describe(row)
              color: row.state === "failed" ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              elide: Text.ElideRight
            }
          }
        }
        Row {
          id: actions
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          IconButton {
            visible: row.state === "running" || row.state === "paused" || row.state === "failed" || row.state === "done"
            width: visible ? Style.space(32) : 0
            icon: row.state === "running" ? "pause" : (row.state === "failed" ? "rotate-cw" : "play")
            iconSize: 14
            tooltipText: row.state === "running" ? L.tr("Пауза") : (row.state === "failed" ? L.tr("Повторить") : (row.state === "done" ? L.tr("Открыть файл") : L.tr("Продолжить")))
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (row.state === "running") root.logic.request("download_pause", { id: row.id })
              else if (row.state === "paused") root.logic.request("download_resume", { id: row.id })
              else if (row.state === "failed") root.logic.request("download_retry", { id: row.id })
              else if (row.filepath) Quickshell.execDetached(["xdg-open", String(row.filepath)])
            }
          }
          IconButton {
            visible: row.state === "done" && !root.compact
            width: visible ? Style.space(32) : 0
            icon: "folder-open"
            iconSize: 14
            tooltipText: L.tr("Показать в папке")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: Quickshell.execDetached(["xdg-open", String(root.summary.directory)])
          }
          IconButton {
            icon: row.state === "done" ? "trash-2" : "x"
            iconSize: 14
            danger: row.state === "done"
            tooltipText: row.state === "done" ? L.tr("Удалить файл") : L.tr("Отменить")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.logic.request(row.state === "done" ? "download_remove" : "download_cancel", { id: row.id, deleteFile: row.state === "done" })
          }
        }
      }
    }
  }
}
