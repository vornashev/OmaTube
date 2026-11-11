import QtQuick
import QtQuick.Controls
import qs.Commons

// Context menu of a media row: title header plus grouped actions. Shared by MediaRow and QueueRow.
Popup {
  id: root

  property Item anchorItem: null
  property Item returnFocusItem: null
  property var media: ({})
  property string title: ""
  property string subtitle: ""
  property var actions: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal triggered(string action)

  readonly property color muted: Qt.darker(foreground, 1.5)

  parent: Overlay.overlay
  objectName: "rowMenu"
  readonly property point anchorPosition: parent && anchorItem ? anchorItem.mapToItem(parent, 0, 0) : Qt.point(0, 0)
  x: parent && anchorItem ? Math.max(Style.space(8), Math.min(parent.width - width - Style.space(8),
    anchorPosition.x + anchorItem.width - width - Style.space(4))) : 0
  y: parent && anchorItem ? Math.max(Style.space(8), Math.min(parent.height - height - Style.space(8),
    anchorPosition.y + anchorItem.height - Style.space(2))) : 0
  width: Style.space(250)
  height: menuColumn.implicitHeight + Style.space(12)
  padding: Style.space(6)
  modal: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  popupType: Popup.Item
  onOpened: Qt.callLater(function() {
    var first = menuRepeater.itemAt(0)
    if (first && first.children.length > 1) first.children[1].forceActiveFocus()
  })
  onClosed: if (returnFocusItem && returnFocusItem.visible) returnFocusItem.forceActiveFocus()

  function trigger(action) {
    close()
    triggered(action)
  }

  background: Rectangle {
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    border.width: Math.max(1, Style.space(1))
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14)
  }

  contentItem: Column {
    id: menuColumn
    spacing: 0
    Item {
      width: parent.width
      height: headColumn.implicitHeight + Style.space(18)
      Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1) }
      Column {
        id: headColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        anchors.topMargin: Style.space(8)
        spacing: Style.space(2)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.subtitle
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          elide: Text.ElideRight
        }
      }
    }
    Repeater {
      id: menuRepeater
      model: root.actions
      delegate: Column {
        id: menuEntry
        required property var modelData
        required property int index
        readonly property bool startsGroup: index === 0 || root.actions[index - 1].group !== modelData.group
        width: menuColumn.width
        Rectangle {
          visible: menuEntry.startsGroup && menuEntry.index > 0
          width: parent.width
          height: visible ? Math.max(1, Style.space(1)) : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
        }
        Item {
          objectName: "menuAction-" + modelData.action
          width: parent.width
          height: Style.space(30)
          activeFocusOnTab: true
          Accessible.role: Accessible.MenuItem
          Accessible.name: modelData.label
          Keys.onReturnPressed: root.trigger(modelData.action)
          Rectangle {
            anchors.fill: parent
            color: itemMouse.containsMouse || parent.activeFocus ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
          }
          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(10)
            Icon {
              anchors.verticalCenter: parent.verticalCenter
              name: modelData.icon
              size: Style.space(14)
              color: modelData.danger === true ? Color.urgent : (itemMouse.containsMouse ? Color.accent : root.muted)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: modelData.danger === true ? Color.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(12)
            }
            Text {
              visible: String(modelData.shortcut || "") !== ""
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(modelData.shortcut || "")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
            }
          }
          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.trigger(modelData.action)
          }
        }
      }
    }
  }
}
