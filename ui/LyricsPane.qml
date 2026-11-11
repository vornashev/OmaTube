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
  property bool active: false
  property var lyrics: null
  property bool loading: false
  property int requestId: 0
  property string loadedKey: ""
  property real offset: 0

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var media: stateData.current ? stateData.current.media : ({})
  readonly property real position: Number(stateData.position || 0)
  readonly property string trackKey: String(media.videoId || "") + ":" + String(Math.round(Number(stateData.duration || media.duration || 0)))
  readonly property var lines: lyrics && lyrics.found ? lyrics.lines : []
  readonly property bool synced: Boolean(lyrics && lyrics.synced)
  readonly property int activeIndex: {
    if (!synced) return -1
    var found = -1
    var now = position + offset
    for (var i = 0; i < lines.length; ++i) if (lines[i].t <= now) found = i
    return found
  }

  function load() {
    if (!logic || !media.videoId || trackKey === loadedKey) return
    loadedKey = trackKey
    lyrics = null
    offset = 0
    loading = true
    requestId = logic.request("lyrics", {
      title: String(media.title || ""), author: String(media.author || ""),
      duration: Number(stateData.duration || media.duration || 0) || null
    })
  }

  onActiveChanged: if (active) load()
  onTrackKeyChanged: if (active) load()
  onActiveIndexChanged: if (activeIndex >= 0 && !list.moving) list.positionViewAtIndex(activeIndex, ListView.Center)

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      if (Number(root.logic.lastRequestId || 0) !== root.requestId || root.requestId === 0) return
      root.loading = false
      root.lyrics = root.logic.lastResult || ({ found: false })
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(8)

    ListView {
      id: list
      width: parent.width
      height: Math.max(0, parent.height - footer.height - parent.spacing)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.lines
      spacing: Style.space(6)
      topMargin: Style.space(10)
      bottomMargin: Style.space(40)
      delegate: Button {
        required property var modelData
        required property int index
        readonly property bool current: index === root.activeIndex
        width: list.width
        height: label.implicitHeight + Style.space(10)
        focusable: root.synced
        enabled: root.synced
        Accessible.name: String(modelData.text)
        foreground: root.foreground
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.logic.request("seek", { seconds: Math.max(0, modelData.t - root.offset) })
        Text {
          id: label
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          textFormat: Text.PlainText
          text: String(modelData.text) === "" ? "♪" : String(modelData.text)
          color: current ? Color.accent : (root.synced ? root.dim : root.foreground)
          font.family: root.fontFamily
          font.pixelSize: current ? Style.font.body + 3 : Style.font.body
          font.bold: current
          wrapMode: Text.WordWrap
          opacity: current || !root.synced ? 1 : .7
        }
      }
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Text {
        visible: root.loading || (root.lyrics !== null && !root.lyrics.found) || !root.media.videoId
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: !root.media.videoId ? L.tr("Включите трек, чтобы увидеть текст")
          : (root.loading ? L.tr("Ищем текст…")
          : (root.lyrics && root.lyrics.error === "network" ? L.tr("Нет связи с LRCLIB") : L.tr("Текст для этого трека не найден")))
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: footer
      width: parent.width
      height: Style.space(30)
      visible: root.lyrics !== null && root.lyrics.found === true
      Text {
        width: parent.width - offsetControls.width
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.synced ? L.tr("Источник: LRCLIB · клик по строке — перемотка") : L.tr("Источник: LRCLIB · без синхронизации")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Row {
        id: offsetControls
        visible: root.synced
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Button {
          width: Style.space(26); height: Style.space(26)
          focusable: true; Accessible.name: L.tr("Текст раньше на 0.5 с")
          text: "−"; foreground: root.dim; horizontalPadding: 0; verticalPadding: 0
          onClicked: root.offset -= 0.5
        }
        Text {
          width: Style.space(54)
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: (root.offset > 0 ? "+" : "") + root.offset.toFixed(1) + L.tr(" с")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Button {
          width: Style.space(26); height: Style.space(26)
          focusable: true; Accessible.name: L.tr("Текст позже на 0.5 с")
          text: "+"; foreground: root.dim; horizontalPadding: 0; verticalPadding: 0
          onClicked: root.offset += 0.5
        }
      }
    }
  }
}
