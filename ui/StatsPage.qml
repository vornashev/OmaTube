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
  property string period: "month"
  property var stats: ({})
  property int requestId: 0
  property int seenRevision: -1

  readonly property bool compact: width < Style.space(600)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var bars: stats.bars || []
  readonly property real maxBar: bars.reduce(function(top, bar) { return Math.max(top, bar.seconds) }, 1)
  readonly property int peak: {
    var index = -1, best = 0
    bars.forEach(function(bar, i) { if (bar.seconds > best) { best = bar.seconds; index = i } })
    return index
  }
  readonly property real maxChannel: (stats.topChannels || []).reduce(function(top, row) { return Math.max(top, row.seconds) }, 1)
  readonly property real maxPlays: (stats.topTracks || []).reduce(function(top, row) { return Math.max(top, row.plays) }, 1)
  readonly property string periodNote: period === "week" ? L.tr("за 7 дней") : (period === "month" ? L.tr("за 30 дней") : L.tr("за всё время"))

  function duration(seconds) {
    var minutes = Math.round(Number(seconds || 0) / 60)
    if (minutes < 60) return minutes + L.tr(" мин")
    var hours = Math.floor(minutes / 60)
    return hours + L.tr(" ч ") + (minutes % 60 < 10 ? "0" : "") + (minutes % 60) + L.tr(" мин")
  }

  function hours(seconds) {
    return (Number(seconds || 0) / 3600).toFixed(1).replace(".", L.decimal())
  }

  function size(bytes) {
    var value = Number(bytes || 0)
    if (value >= 1073741824) return (value / 1073741824).toFixed(1).replace(".", L.decimal()) + L.tr(" ГБ")
    if (value >= 1048576) return Math.round(value / 1048576) + L.tr(" МБ")
    return Math.round(value / 1024) + L.tr(" КБ")
  }

  function delta() {
    if (stats.previousSeconds === null || stats.previousSeconds === undefined) return L.tr("за всё время")
    var diff = Number(stats.totalSeconds) - Number(stats.previousSeconds)
    return (diff >= 0 ? "+" : "−") + duration(Math.abs(diff)) + L.tr(" к прошлому периоду")
  }

  function plural(count, one, few, many) { return L.plural(count, one, few, many) }

  function load() { if (logic) requestId = logic.request("stats", { period: period }) }

  onLogicChanged: if (logic) load()
  onVisibleChanged: if (visible) load()
  onPeriodChanged: load()

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      if (id === root.requestId && root.logic.lastResult && root.logic.lastResult.totalSeconds !== undefined)
        root.stats = root.logic.lastResult
    }
    function onStateDataChanged() {
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenRevision < 0) root.seenRevision = revision
      else if (revision !== root.seenRevision) { root.seenRevision = revision; if (root.visible) root.load() }
    }
  }

  component SectionHead: Row {
    property string label: ""
    property string note: ""
    width: parent ? parent.width : 0
    height: Style.space(17)
    spacing: Style.space(10)
    Text {
      id: headLabel
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: 1.5
    }
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - headLabel.width - headNote.width - parent.spacing * 2)
      height: Math.max(1, Style.space(1))
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
    }
    Text {
      id: headNote
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.note
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
    }
  }

  component TopList: Column {
    id: board
    property string title: ""
    property var rows: []
    property bool byTime: true
    width: parent ? parent.width : 0
    spacing: Style.space(9)
    SectionHead { label: board.title }
    Repeater {
      model: board.rows
      delegate: Row {
        required property var modelData
        required property int index
        width: board.width
        height: Style.space(20)
        spacing: Style.space(12)
        Text {
          width: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(index + 1)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
        Text {
          width: parent.width - Style.space(12) - Style.space(90) - Style.space(88) - parent.spacing * 3
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(modelData.title)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          elide: Text.ElideRight
        }
        Rectangle {
          width: Style.space(90)
          height: Math.max(2, Style.space(3))
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
          Rectangle {
            width: parent.width * (board.byTime ? modelData.seconds / root.maxChannel : modelData.plays / root.maxPlays)
            height: parent.height
            color: index === 0 ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .4)
          }
        }
        Text {
          width: Style.space(88)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: board.byTime ? root.duration(modelData.seconds) : modelData.plays + " " + root.plural(modelData.plays, L.tr("раз"), L.tr("раза"), L.tr("раз"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
      }
    }
    Text {
      visible: board.rows.length === 0
      textFormat: Text.PlainText
      text: L.tr("Пока нет данных")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(11)
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: Style.space(root.compact ? 0 : 24)
    anchors.rightMargin: Style.space(root.compact ? 0 : 24)
    anchors.topMargin: Style.space(root.compact ? 10 : 20)
    contentWidth: width
    contentHeight: page.implicitHeight + Style.space(20)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: page
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(8) : 0)
      spacing: Style.space(root.compact ? 14 : 18)

      Flow {
        width: parent.width
        spacing: Style.space(10)
        Column {
          width: root.compact ? parent.width : parent.width - periodControl.width - parent.spacing
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: L.tr("Статистика")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(20)
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: L.tr("данные хранятся только на этом компьютере")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
        }
        Segmented {
          id: periodControl
          foreground: root.foreground
          fontFamily: root.fontFamily
          current: root.period
          options: [{ value: "week", label: L.tr("НЕДЕЛЯ") }, { value: "month", label: L.tr("МЕСЯЦ") }, { value: "all", label: L.tr("ВСЁ ВРЕМЯ") }]
          onChosen: value => root.period = value
        }
      }

      Grid {
        id: metrics
        width: parent.width
        columns: root.compact ? 2 : 4
        columnSpacing: Style.space(20)
        rowSpacing: Style.space(14)
        Repeater {
          model: [
            { label: L.tr("ВРЕМЯ ПРОСЛУШИВАНИЯ"), value: root.duration(root.stats.totalSeconds), note: root.delta(), accent: true },
            { label: L.tr("ТРЕКОВ И ВИДЕО"), value: String(root.stats.plays || 0), note: (root.stats.channels || 0) + " " + root.plural(root.stats.channels || 0, L.tr("канал"), L.tr("канала"), L.tr("каналов")) },
            { label: L.tr("ЭКОНОМИЯ SPONSORBLOCK"), value: root.duration(root.stats.sponsorSeconds), note: (root.stats.sponsorSegments || 0) + " " + root.plural(root.stats.sponsorSegments || 0, L.tr("сегмент"), L.tr("сегмента"), L.tr("сегментов")) + L.tr(" пропущено") },
            { label: L.tr("СКАЧАНО"), value: root.size(root.stats.downloadsBytes), note: (root.stats.downloadsCount || 0) + " " + root.plural(root.stats.downloadsCount || 0, L.tr("файл"), L.tr("файла"), L.tr("файлов")) }
          ]
          delegate: Column {
            required property var modelData
            width: (metrics.width - metrics.columnSpacing * (metrics.columns - 1)) / metrics.columns
            spacing: Style.space(5)
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: modelData.label
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: modelData.value
              color: modelData.accent === true ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(root.compact ? 20 : 24)
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: modelData.note
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              elide: Text.ElideRight
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(10)
        SectionHead {
          label: root.period === "week" ? L.tr("ПО ДНЯМ · ЧАСОВ") : (root.period === "month" ? L.tr("ПО 5 ДНЕЙ · ЧАСОВ") : L.tr("ПО МЕСЯЦАМ · ЧАСОВ"))
          note: root.stats.avgPerDay > 0 ? L.tr("в среднем ") + root.duration(root.stats.avgPerDay) + L.tr(" в день") : ""
        }
        Row {
          width: parent.width
          height: Style.space(root.compact ? 120 : 150)
          spacing: Style.space(root.compact ? 8 : 14)
          Repeater {
            model: root.bars
            delegate: Column {
              required property var modelData
              required property int index
              width: (parent.width - parent.spacing * Math.max(0, root.bars.length - 1)) / Math.max(1, root.bars.length)
              height: parent.height
              spacing: Style.space(6)
              Item {
                width: parent.width
                height: parent.height - Style.space(18)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: bar.top
                  anchors.bottomMargin: Style.space(4)
                  visible: modelData.seconds > 0
                  textFormat: Text.PlainText
                  text: root.hours(modelData.seconds)
                  color: index === root.peak ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                }
                Rectangle {
                  id: bar
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(modelData.seconds > 0 ? Style.space(3) : Math.max(1, Style.space(1)), (parent.height - Style.space(16)) * modelData.seconds / root.maxBar)
                  color: index === root.peak ? Color.accent : (modelData.seconds > 0 ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .3) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1))
                }
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: L.tb(modelData.label).toUpperCase()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                font.letterSpacing: 1
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(32)
        TopList {
          width: root.compact ? parent.width : (parent.width - parent.spacing) / 2
          title: L.tr("ТОП КАНАЛОВ")
          rows: root.stats.topChannels || []
          byTime: true
        }
        TopList {
          width: root.compact ? parent.width : (parent.width - parent.spacing) / 2
          title: L.tr("ТОП ТРЕКОВ И ВИДЕО")
          rows: root.stats.topTracks || []
          byTime: false
        }
      }
    }
  }
}
