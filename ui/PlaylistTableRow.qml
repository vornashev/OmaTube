import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var item: ({})
  property int rowNumber: 0
  property bool current: false
  // "" | "loading" | "playing" | "paused" | "error" | "played" (earlier in the playing list)
  property string rowState: current ? "playing" : ""
  property string positionText: ""
  property bool editable: true
  property bool compact: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal playRequested(var item)
  signal toggleRequested()
  signal cancelRequested()
  signal enqueueRequested(var media)
  signal saveRequested(var media)
  signal removeRequested(var item)
  signal moveUpRequested(var item)
  signal moveDownRequested(var item)
  signal channelRequested(var entity)

  readonly property var media: item.media || item
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property bool hovered: hover.hovered
  readonly property bool active: rowState === "playing" || rowState === "paused"
  readonly property bool marked: active || rowState === "loading" || rowState === "error"

  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0) || value === null || value === undefined) return "—"
    if (count >= 1000000000) return (count / 1000000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млрд")
    if (count >= 1000000) return (count / 1000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }
  function formatDuration(value) {
    var seconds = Math.floor(Number(value || 0))
    if (!(seconds > 0)) return ""
    return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
  }

  height: Style.space(44)

  HoverHandler { id: hover }

  Rectangle {
    anchors.fill: parent
    color: root.rowState === "playing" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
      : (root.rowState === "paused" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .08)
      : (root.rowState === "error" ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .06)
      : (root.rowState === "loading" || root.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")))
  }
  Rectangle {
    visible: root.marked
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(2))
    color: root.rowState === "error" ? Color.urgent : (root.rowState === "paused" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .5) : Color.accent)
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: {
      if (root.active) root.toggleRequested()
      else if (root.rowState !== "loading") root.playRequested(root.item)
    }
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    spacing: Style.space(12)

    Item {
      width: Style.space(18)
      height: parent.height
      readonly property string glyph: root.rowState === "loading" ? "loader-circle"
        : root.rowState === "paused" ? "pause"
        : root.rowState === "error" ? "triangle-alert"
        : root.rowState === "played" ? "check"
        : (root.hovered && root.rowState === "" ? "play" : "")
      Equalizer { visible: root.rowState === "playing"; anchors.centerIn: parent; maxHeight: Style.space(12) }
      Icon {
        id: playbackGlyph
        visible: parent.glyph !== ""
        anchors.centerIn: parent
        name: parent.glyph
        size: Style.space(13)
        color: root.rowState === "error" ? Color.urgent : (root.rowState === "loading" || root.rowState === "paused" ? Color.accent
          : (root.rowState === "played" ? root.dim : root.foreground))
        NumberAnimation on rotation { running: root.rowState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
      }
      Text {
        visible: parent.glyph === "" && root.rowState !== "playing"
        anchors.centerIn: parent
        text: String(root.rowNumber)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }

    Row {
      width: parent.width - Style.space(18) - (root.compact ? 0 : Style.space(140)) - Style.space(56) - parent.spacing * (root.compact ? 2 : 4)
      height: parent.height
      spacing: Style.space(12)
      Rectangle {
        width: Style.space(57)
        height: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
        clip: true
        CatalogImage {
          anchors.fill: parent
          opacity: root.rowState === "played" ? .5 : 1
          requestedSource: String(root.media.thumbnailUrl || (root.media.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(root.media.videoId) + "/hqdefault.jpg" : ""))
          foreground: root.foreground
          fontFamily: root.fontFamily
          fillMode: Image.PreserveAspectCrop
        }
      }
      Column {
        width: parent.width - Style.space(69) - (rowActions.visible ? rowActions.width + Style.space(12) : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Row {
          width: parent.width
          spacing: Style.space(10)
          Text {
            id: titleLabel
            width: Math.min(implicitWidth, parent.width - (stateLabel.visible ? stateLabel.implicitWidth + parent.spacing : 0))
            textFormat: Text.PlainText
            text: String(root.media.title || root.media.videoId || L.tr("Без названия"))
            color: root.rowState === "playing" ? Color.accent : (root.rowState === "error" ? Color.urgent
              : (root.rowState === "played" ? root.dim : root.foreground))
            font.family: root.fontFamily
            font.pixelSize: Style.space(13)
            font.bold: root.marked
            elide: Text.ElideRight
          }
          Text {
            id: stateLabel
            visible: root.rowState === "loading" || root.rowState === "error"
            text: root.rowState === "loading" ? L.tr("·  загрузка…") : L.tr("·  не удалось открыть")
            color: root.rowState === "error" ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            font.bold: root.rowState === "loading"
          }
        }
        Text {
          visible: !root.compact || root.rowState !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: L.tb(root.media.author || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          elide: Text.ElideRight
        }
      }
      Row {
        id: rowActions
        visible: root.hovered && root.rowState !== "loading"
        anchors.verticalCenter: parent.verticalCenter
        IconButton { icon: "list-plus"; iconSize: 14; width: Style.space(26); height: Style.space(26); tooltipText: L.tr("В мою очередь"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.enqueueRequested(root.media) }
        IconButton { icon: "bookmark"; iconSize: 14; active: true; width: Style.space(26); height: Style.space(26); tooltipText: L.tr("Сохранить"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.saveRequested(root.media) }
        Item { width: Style.space(8); height: 1; visible: root.editable }
        IconButton { icon: "arrow-up"; iconSize: 13; width: Style.space(26); height: Style.space(26); tooltipText: L.tr("Выше"); foreground: root.foreground; fontFamily: root.fontFamily; visible: root.editable; onClicked: root.moveUpRequested(root.item) }
        IconButton { icon: "arrow-down"; iconSize: 13; width: Style.space(26); height: Style.space(26); tooltipText: L.tr("Ниже"); foreground: root.foreground; fontFamily: root.fontFamily; visible: root.editable; onClicked: root.moveDownRequested(root.item) }
        IconButton { icon: "trash-2"; iconSize: 13; width: Style.space(26); height: Style.space(26); tooltipText: L.tr("Убрать из плейлиста"); foreground: root.foreground; fontFamily: root.fontFamily; visible: root.editable; onClicked: root.removeRequested(root.item) }
      }
    }

    Text {
      visible: !root.compact
      width: visible ? Style.space(80) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.formatCount(root.media.viewCount)
      color: root.dim
      opacity: root.rowState === "played" ? .7 : 1
      font.family: root.fontFamily
      font.pixelSize: Style.space(11)
    }
    Text {
      visible: !root.compact
      width: visible ? Style.space(60) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.formatCount(root.media.likeCount)
      color: root.dim
      opacity: root.rowState === "played" ? .7 : 1
      font.family: root.fontFamily
      font.pixelSize: Style.space(11)
    }
    Item {
      width: Style.space(56)
      height: parent.height
      Text {
        visible: root.rowState !== "loading"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.active && root.positionText !== "" ? root.positionText : root.formatDuration(root.media.duration)
        color: root.rowState === "playing" ? Color.accent : root.dim
        opacity: root.rowState === "played" ? .7 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      IconButton {
        visible: root.rowState === "loading"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(26)
        height: Style.space(26)
        icon: "x"
        iconSize: 12
        tooltipText: L.tr("Отменить загрузку")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.cancelRequested()
      }
    }
  }
}
