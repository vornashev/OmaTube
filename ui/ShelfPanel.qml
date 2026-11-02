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
  signal expandRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  readonly property var media: currentEntry ? currentEntry.media : ({})
  readonly property var queue: logic && logic.details.queue ? logic.details.queue : []
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real position: Number(stateData.position || 0)
  readonly property color dim: Qt.darker(foreground, 1.5)

  function request(command, payload) { if (logic) logic.request(command, payload || ({})) }
  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    var m = Math.floor(seconds / 60), s = seconds % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  Row {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(16)

    Rectangle {
      width: Math.round(height * 16 / 9)
      height: parent.height
      radius: Style.cornerRadius
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
    }

    Column {
      width: Style.space(340)
      height: parent.height
      spacing: Style.space(6)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || L.tr("Очередь пуста"))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: L.tb(root.media.author || "")
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Item { width: 1; height: Style.space(4) }
      Item {
        width: parent.width
        height: Style.space(18)
        Text {
          id: posLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.formatTime(root.position)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          id: durLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.formatTime(root.duration)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Rectangle {
          anchors.left: posLabel.right
          anchors.right: durLabel.left
          anchors.margins: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.position / Math.max(1, root.duration)))
            height: parent.height
            radius: parent.radius
            color: Color.accent
          }
          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -Style.space(8)
            anchors.bottomMargin: -Style.space(8)
            enabled: root.stateData.canSeek === true && root.duration > 0
            onClicked: mouse => root.request("seek", { seconds: root.duration * mouse.x / width })
          }
        }
      }
      Row {
        spacing: Style.space(8)
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip-back"; iconSize: 18; tooltipText: L.tr("Предыдущий"); enabled: Boolean(root.currentEntry); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.request("previous") }
        Item {
          width: Style.space(40); height: Style.space(40)
          opacity: root.currentEntry ? 1 : .4
          Rectangle { anchors.fill: parent; radius: width / 2; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18); border.width: Math.max(1.5, Style.space(1.5)); border.color: Color.accent }
          Icon { anchors.centerIn: parent; name: root.stateData.state === "playing" ? "pause" : "play"; size: Style.space(18); color: Color.accent }
          MouseArea { anchors.fill: parent; enabled: Boolean(root.currentEntry); cursorShape: Qt.PointingHandCursor; onClicked: root.request("toggle_pause") }
          Accessible.role: Accessible.Button
          Accessible.name: L.tr("Пауза / продолжить")
        }
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip-forward"; iconSize: 18; tooltipText: L.tr("Следующий"); enabled: Boolean(root.currentEntry); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.request("next") }
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "shuffle"; active: root.stateData.shuffle === true; tooltipText: L.tr("Перемешать"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.request("shuffle", { value: !root.stateData.shuffle }) }
        IconButton { anchors.verticalCenter: parent.verticalCenter; icon: "maximize-2"; iconSize: 14; tooltipText: L.tr("Развернуть панель"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.expandRequested() }
      }
    }

    Column {
      width: parent.width - Math.round(parent.height * 16 / 9) - Style.space(340) - parent.spacing * 2
      height: parent.height
      spacing: Style.space(6)
      Text {
        text: L.tr("ДАЛЕЕ") + (root.queue.length > 0 ? "  ·  " + root.queue.length : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1
      }
      ListView {
        id: strip
        width: parent.width
        height: parent.height - Style.space(24)
        orientation: ListView.Horizontal
        spacing: Style.space(10)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.queue
        delegate: Button {
          required property var modelData
          readonly property var m: modelData.media || modelData
          readonly property bool isCurrent: root.currentEntry && modelData.entryId === root.currentEntry.entryId
          width: Style.space(160)
          height: strip.height
          bordered: isCurrent
          selected: isCurrent
          focusable: true
          Accessible.name: String(m.title || "")
          foreground: root.foreground
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: root.request("queue_play", { entryId: modelData.entryId })
          Column {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            spacing: Style.space(4)
            Rectangle {
              width: parent.width
              height: Math.round(width * 9 / 16)
              radius: Style.space(3)
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
              clip: true
              CatalogImage {
                anchors.fill: parent
                requestedSource: String(m.thumbnailUrl || (m.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(m.videoId) + "/hqdefault.jpg" : ""))
                foreground: root.foreground
                fontFamily: root.fontFamily
                fillMode: Image.PreserveAspectCrop
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: String(m.title || "")
              color: isCurrent ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
          }
        }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
      }
    }
  }
}
