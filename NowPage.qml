import QtQuick
import qs.Commons

Item {
  id: root

  property var logic: null
  property bool wide: true
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal playlistPickerRequested(var media, var anchorItem)
  signal channelRequested(var entity)
  signal sessionsRequested()

  Row {
    anchors.fill: parent

    PlayerCard {
      visible: root.wide
      width: visible ? Style.space(400) : 0
      height: parent.height
      logic: root.logic
      foreground: root.foreground
      fontFamily: root.fontFamily
      onPlaylistPickerRequested: (media, anchorItem) => root.playlistPickerRequested(media, anchorItem)
      onChannelRequested: entity => root.channelRequested(entity)
    }

    Rectangle {
      visible: root.wide
      width: visible ? Math.max(1, Style.space(1)) : 0
      height: parent.height
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
    }

    QueuePane {
      id: queuePane
      width: parent.width - (root.wide ? Style.space(400) + Math.max(1, Style.space(1)) : 0)
      height: parent.height
      logic: root.logic
      foreground: root.foreground
      fontFamily: root.fontFamily
      leftInset: root.wide ? Style.space(16) : 0
      onPlaylistPickerRequested: media => root.playlistPickerRequested(media)
      onChannelRequested: entity => root.channelRequested(entity)
      onSessionsRequested: root.sessionsRequested()
    }
  }
}
