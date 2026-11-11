import QtQuick
import qs.Commons

// Four bouncing bars: the "now playing" marker used in rows, cards, badges and the rail.
Row {
  id: root

  property bool running: true
  property color color: Color.accent
  property real barWidth: Math.max(2, Style.space(2))
  property real maxHeight: Style.space(12)

  spacing: Math.max(1, Style.space(1.5))
  height: maxHeight

  Repeater {
    model: [.55, 1, .7, .4]
    delegate: Rectangle {
      id: bar
      required property real modelData
      required property int index
      property real level: modelData
      anchors.bottom: parent.bottom
      width: root.barWidth
      height: Math.max(root.barWidth, root.maxHeight * level)
      color: root.color
      SequentialAnimation on level {
        running: root.running && bar.visible && bar.Window.window !== null && bar.Window.window.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 260 + bar.index * 70; easing.type: Easing.InOutSine }
        NumberAnimation { to: .25; duration: 300 + bar.index * 50; easing.type: Easing.InOutSine }
        NumberAnimation { to: bar.modelData; duration: 240; easing.type: Easing.InOutSine }
      }
    }
  }
}
