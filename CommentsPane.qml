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
  property var comments: []
  property var nextCursor: null
  property bool loading: false
  property string error: ""
  property string loadedVideoId: ""
  property int requestId: 0
  property bool appending: false

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var media: logic && logic.stateData.current ? logic.stateData.current.media : ({})
  readonly property string videoId: String(media.videoId || "")

  function load(more) {
    if (!logic || videoId === "") return
    if (!more) { if (videoId === loadedVideoId) return; loadedVideoId = videoId; comments = []; nextCursor = null }
    loading = true
    error = ""
    appending = more === true
    requestId = logic.request("comments", more ? { videoId: videoId, cursor: nextCursor } : { videoId: videoId })
  }

  onActiveChanged: if (active) load(false)
  onVideoIdChanged: if (active) load(false)

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      if (root.requestId === 0 || Number(root.logic.lastRequestId || 0) !== root.requestId) return
      root.loading = false
      var result = root.logic.lastResult
      if (result && result.items) {
        root.comments = root.appending ? root.comments.concat(result.items) : result.items
        root.nextCursor = result.nextCursor || null
      } else {
        root.error = root.logic.statusError || L.tr("Не удалось загрузить комментарии")
        if (!root.appending) root.loadedVideoId = ""
      }
    }
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: root.comments
    spacing: Style.space(10)
    delegate: Column {
      required property var modelData
      width: list.width - (list.contentHeight > list.height ? Style.space(8) : 0)
      spacing: Style.space(3)
      Row {
        spacing: Style.space(8)
        Text {
          textFormat: Text.PlainText
          text: (modelData.pinned ? "📌 " : "") + modelData.author
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Text {
          text: modelData.published
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: modelData.text
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.Wrap
        maximumLineCount: 8
        elide: Text.ElideRight
      }
      Text {
        visible: String(modelData.likes) !== "" || modelData.replies > 0
        text: "♥ " + modelData.likes + (modelData.replies > 0 ? L.tr("   ·   ответов: ") + modelData.replies : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    footer: Button {
      visible: root.nextCursor !== null && !root.loading
      width: list.width
      height: visible ? Style.space(38) : 0
      text: L.tr("Загрузить ещё")
      focusable: true
      Accessible.name: text
      foreground: Color.accent
      onClicked: root.load(true)
    }
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Text {
      visible: root.comments.length === 0
      anchors.centerIn: parent
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: root.videoId === "" ? L.tr("Включите видео, чтобы увидеть комментарии")
        : (root.loading ? L.tr("Загружаем комментарии…") : (root.error !== "" ? root.error : L.tr("Комментариев нет или они отключены")))
      color: root.error !== "" ? Color.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
