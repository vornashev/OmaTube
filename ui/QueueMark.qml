import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

// "В очереди · N" plaque; hover turns it into a remove button.
Rectangle {
  id: root

  property var logic: null
  property string videoId: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real markHeight: Style.space(22)

  readonly property int position: logic && videoId !== "" ? logic.queuePosition(videoId) : 0
  readonly property bool removing: mouse.containsMouse || activeFocus

  function remove() {
    var entryId = logic ? logic.queueEntryId(videoId) : ""
    if (entryId !== "") logic.request("queue_remove", { entryId: entryId })
  }

  visible: position > 0
  width: markRow.implicitWidth + Style.space(14)
  height: markHeight
  radius: Style.space(4)
  color: removing ? Qt.rgba(0, 0, 0, .85) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .92)
  activeFocusOnTab: true
  Accessible.role: Accessible.Button
  Accessible.name: position + L.tr("-е в очереди, убрать из очереди")
  Keys.onReturnPressed: root.remove()

  Row {
    id: markRow
    anchors.centerIn: parent
    spacing: Style.space(5)
    readonly property color tone: root.removing ? "#FFFFFF" : Color.background
    Icon {
      anchors.verticalCenter: parent.verticalCenter
      name: root.removing ? "x" : (root.position === 1 ? "list-start" : "list-checks")
      size: Style.space(12)
      color: markRow.tone
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.removing ? L.tr("УБРАТЬ") : (root.position === 1 ? L.tr("ДАЛЕЕ") : String(root.position))
      color: markRow.tone
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: 1
    }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.remove()
  }
}
