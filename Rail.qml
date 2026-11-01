import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int page: 0
  property string section: ""
  property var playlists: []
  property string openPlaylistId: ""
  property string playingPlaylistId: ""
  property bool playlistPlaying: false
  // My queue: pinned above the playlists; while it plays, the playlist behind Now playing waits paused.
  property bool queueActive: false
  property int queueCount: 0
  property real queueDuration: 0
  property string sourcePlace: ""
  property bool settingsActive: false
  property int newCount: 0
  property int downloadsActive: 0
  signal navigate(int page)
  signal sectionRequested(string section)
  signal playlistRequested(string playlistId)
  signal myQueueRequested()
  signal settingsRequested()
  signal shrinkRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var tiles: [
    { label: L.tr("Сейчас"), icon: "audio-lines", page: 0 },
    { label: L.tr("Медиатека"), icon: "library", page: 2 }
  ]

  implicitWidth: Style.space(226)
  color: "transparent"

  function trackCount(count) {
    return count + " " + L.plural(count, L.tr("трек"), L.tr("трека"), L.tr("треков"))
  }
  function queueMeta() {
    if (queueActive) return (queueCount > 0 ? L.tr("играет") : L.tr("пусто"))
    if (queueCount === 0) return L.tr("пусто")
    var text = queueCount + " " + L.plural(queueCount, L.tr("видео"), "видео", "видео")
    var minutes = Math.round(queueDuration / 60)
    if (minutes > 0) text += " · " + (minutes >= 60 ? Math.floor(minutes / 60) + L.tr(" ч ") + (minutes % 60) + L.tr(" мин") : minutes + L.tr(" мин"))
    return text
  }
  function fade(alpha) { return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha) }
  function soft(alpha) { return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, alpha) }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(1, Style.space(1))
    color: root.fade(.08)
  }

  component FooterButton: Rectangle {
    id: button
    property string icon: ""
    property string label: ""
    property bool selected: false
    property bool badge: false
    signal clicked()

    width: Style.space(34)
    height: Style.space(32)
    radius: Style.space(6)
    color: selected ? root.soft(.18) : (buttonMouse.containsMouse ? root.fade(.05) : "transparent")
    border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onReturnPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()

    Icon {
      anchors.centerIn: parent
      name: button.icon
      size: Style.space(16)
      color: button.selected ? Color.accent : root.dim
    }
    Rectangle {
      visible: button.badge
      x: Style.space(22)
      y: Style.space(6)
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Color.accent
    }
    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(2)

    Rectangle {
      id: searchField
      width: parent.width
      height: Style.space(36)
      radius: Style.space(6)
      color: root.fade(.04)
      border.width: Math.max(1, Style.space(1))
      border.color: searchField.activeFocus || searchMouse.containsMouse ? Color.accent : root.fade(.08)
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: L.tr("Поиск")
      Keys.onReturnPressed: root.navigate(1)
      Keys.onSpacePressed: root.navigate(1)

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)
        Icon {
          anchors.verticalCenter: parent.verticalCenter
          name: "search"
          size: Style.space(15)
          color: root.dim
        }
        Text {
          width: parent.width - Style.space(15) - kbd.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          text: L.tr("Поиск")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          elide: Text.ElideRight
        }
        Text {
          id: kbd
          anchors.verticalCenter: parent.verticalCenter
          text: "/"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
        }
      }
      MouseArea {
        id: searchMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigate(1)
      }
    }

    Item { width: 1; height: Style.space(6) }

    Row {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: root.tiles
        delegate: Rectangle {
          id: tile
          required property var modelData
          readonly property bool selected: !root.settingsActive
            && (root.page === modelData.page || (modelData.page === 2 && root.page === 3))
          width: (parent.width - parent.spacing) / 2
          height: Style.space(60)
          radius: Style.space(6)
          color: selected ? root.soft(.18) : (tileMouse.containsMouse ? root.fade(.1) : root.fade(.04))
          border.width: selected || activeFocus ? Math.max(1, Style.space(1)) : 0
          border.color: Color.accent
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: modelData.label
          Keys.onReturnPressed: root.navigate(modelData.page)
          Keys.onSpacePressed: root.navigate(modelData.page)

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(6)
            Icon {
              name: tile.modelData.icon
              size: Style.space(16)
              color: Color.accent
            }
            Text {
              width: parent.width
              text: tile.modelData.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(12)
              font.bold: true
              elide: Text.ElideRight
            }
          }
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.navigate(tile.modelData.page)
          }
        }
      }
    }

    Row {
      width: parent.width
      height: Style.space(34)
      leftPadding: Style.space(12)
      rightPadding: Style.space(6)
      topPadding: Style.space(14)
      Text {
        width: parent.width - parent.leftPadding - parent.rightPadding - countLabel.width
        text: L.tr("ПЛЕЙЛИСТЫ")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
      Text {
        id: countLabel
        text: String(root.playlists.length)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
    }

    Flickable {
      id: playlistFlick
      width: parent.width
      height: Math.max(0, parent.height - y - Style.space(50))
      contentWidth: width
      contentHeight: playlistColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: playlistColumn
        width: playlistFlick.width
        spacing: Style.space(2)
        Rectangle {
          id: queueRow
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: queueMouse.containsMouse ? root.fade(.05) : "transparent"
          border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
          border.color: Color.accent
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: L.tr("Моя очередь")
          Keys.onReturnPressed: root.myQueueRequested()
          Keys.onSpacePressed: root.myQueueRequested()

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(10)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              radius: Style.space(4)
              color: root.soft(.16)
              Icon {
                anchors.centerIn: parent
                name: "list-video"
                size: Style.space(15)
                color: Color.accent
              }
            }
            Column {
              width: parent.width - Style.space(30) - parent.spacing - (queueEq.visible ? queueEq.width + parent.spacing : 0)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: L.tr("Моя очередь")
                color: root.queueActive ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
                font.bold: root.queueActive
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.queueMeta()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                elide: Text.ElideRight
              }
            }
            Equalizer {
              id: queueEq
              visible: root.queueActive && root.queueCount > 0
              anchors.verticalCenter: parent.verticalCenter
              running: root.playlistPlaying
              maxHeight: Style.space(12)
            }
          }
          MouseArea {
            id: queueMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.myQueueRequested()
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.fade(.08)
        }

        Repeater {
          model: root.playlists.slice(0, 40)
          delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string playlistId: String(modelData.id || modelData.playlistId || "")
            readonly property bool selected: !root.settingsActive && playlistId !== "" && playlistId === root.openPlaylistId
            readonly property bool current: playlistId !== "" && playlistId === root.playingPlaylistId
            readonly property bool playing: current && !root.queueActive
            readonly property bool paused: current && root.queueActive
            readonly property int count: Number(modelData.itemCount || 0)
            width: parent.width
            height: Style.space(38)
            radius: Style.space(6)
            color: selected ? root.fade(.04) : (rowMouse.containsMouse ? root.fade(.05) : "transparent")
            border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
            border.color: Color.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: nameLabel.text
            Keys.onReturnPressed: root.playlistRequested(playlistId)
            Keys.onSpacePressed: root.playlistRequested(playlistId)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(10)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: width
                radius: Style.space(4)
                color: root.fade(.08)
                clip: true
                CatalogImage {
                  anchors.fill: parent
                  requestedSource: String(row.modelData.thumbnailUrl || "")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fillMode: Image.PreserveAspectCrop
                }
              }
              Column {
                width: parent.width - Style.space(30) - parent.spacing - (rowEq.visible ? rowEq.width + parent.spacing : 0)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  id: nameLabel
                  width: parent.width
                  textFormat: Text.PlainText
                  text: L.tb(row.modelData.name || row.modelData.title || L.tr("Плейлист"))
                  color: row.playing || row.selected ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(12)
                  font.bold: row.playing || row.selected
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.trackCount(row.count) + (row.playing ? " · " + L.tr("играет")
                    : row.paused ? " · " + L.tr("на паузе") + (root.sourcePlace !== "" ? " " + root.sourcePlace : "") : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  elide: Text.ElideRight
                }
              }
              Equalizer {
                id: rowEq
                visible: row.playing
                anchors.verticalCenter: parent.verticalCenter
                running: root.playlistPlaying
                maxHeight: Style.space(12)
              }
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.playlistRequested(row.playlistId)
            }
          }
        }
      }
    }
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(10)
    height: Style.space(41)

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: Math.max(1, Style.space(1))
      color: root.fade(.08)
    }
    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: Style.space(2)
      FooterButton {
        icon: "house"
        label: L.tr("Главная")
        selected: !root.settingsActive && root.page === 6
        onClicked: root.navigate(6)
      }
      FooterButton {
        icon: "rss"
        label: L.tr("Подписки")
        selected: !root.settingsActive && root.page === 4
        badge: root.newCount > 0
        onClicked: root.navigate(4)
      }
    }
    FooterButton {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      icon: "settings"
      label: L.tr("Настройки")
      selected: root.settingsActive
      onClicked: root.settingsRequested()
    }
  }
}
