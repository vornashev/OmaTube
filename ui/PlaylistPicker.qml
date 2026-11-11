import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

Popup {
  id: root

  property var logic: null
  property var media: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property Item anchorItem: null
  property Item boundsItem: null
  property var playlists: []
  property var member: ({})
  property string filter: ""
  property int listRequestId: 0
  property int membershipRequestId: 0
  property int createRequestId: 0
  property var toggleRequests: ({})
  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  // media is one video, or an array of them when adding a selection (add-only, no membership).
  readonly property bool batch: Array.isArray(media)
  readonly property string videoId: media && !batch ? String(media.videoId || "") : ""

  function addAll(playlistId) {
    media.forEach(function(item) { logic.request("playlist_toggle", { playlistId: playlistId, media: item, present: false }) })
    var copy = Object.assign({}, member)
    copy[playlistId] = true
    member = copy
  }
  readonly property var shown: playlists.filter(function(row) {
    return filter === "" || String(row.name || "").toLowerCase().indexOf(filter.toLowerCase()) >= 0
  })

  function reload() {
    if (!logic) return
    member = ({})
    listRequestId = logic.request("collection", { section: "playlists", offset: 0 })
    if (videoId !== "") membershipRequestId = logic.request("playlist_membership", { videoId: videoId })
  }

  parent: Overlay.overlay
  readonly property point anchorPosition: anchorItem && parent
    ? anchorItem.mapToItem(parent, 0, 0) : Qt.point(0, 0)
  readonly property point boundsPosition: boundsItem && parent
    ? boundsItem.mapToItem(parent, 0, 0) : Qt.point(0, 0)
  readonly property real boundsInsetX: boundsItem
    ? Math.min(Style.space(8), Math.max(0, (boundsItem.width - width) / 2)) : Style.space(8)
  readonly property real boundsInsetY: boundsItem
    ? Math.min(Style.space(8), Math.max(0, (boundsItem.height - height) / 2)) : Style.space(8)
  readonly property real boundsMinX: (boundsItem ? boundsPosition.x : 0) + boundsInsetX
  readonly property real boundsMaxX: (boundsItem ? boundsPosition.x + boundsItem.width : parent.width) - width - boundsInsetX
  readonly property real boundsMinY: (boundsItem ? boundsPosition.y : 0) + boundsInsetY
  readonly property real boundsMaxY: (boundsItem ? boundsPosition.y + boundsItem.height : parent.height) - height - boundsInsetY
  x: anchorItem && parent
    ? Math.max(boundsMinX, Math.min(boundsMaxX, anchorPosition.x + anchorItem.width - width))
    : Math.round((parent.width - width) / 2)
  y: anchorItem && parent
    ? Math.max(boundsMinY, Math.min(boundsMaxY, anchorPosition.y - height - Style.space(6)))
    : Math.round((parent.height - height) / 2)
  width: Style.space(260)
  padding: Style.space(6)
  modal: true
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
  popupType: Popup.Item
  onAboutToShow: { filter = ""; searchField.text = ""; newField.text = ""; reload() }
  onOpened: searchField.forceActiveFocus()

  background: Rectangle {
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    border.width: Math.max(1, Style.space(1))
    border.color: Color.accent
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      var result = root.logic.lastResult
      if (id === root.listRequestId && result && result.items) {
        root.playlists = result.items
      } else if (id === root.membershipRequestId && result && result.playlistIds) {
        var map = ({})
        result.playlistIds.forEach(function(value) { map[value] = true })
        root.member = map
      } else if (id === root.createRequestId && result && result.id) {
        root.createRequestId = 0
        if (root.batch) root.addAll(result.id)
        else root.logic.request("playlist_toggle", { playlistId: result.id, media: root.media, present: false })
        root.reload()
      } else if (root.toggleRequests[id] !== undefined && result) {
        var copy = Object.assign({}, root.member)
        if (result.present) copy[root.toggleRequests[id]] = true
        else delete copy[root.toggleRequests[id]]
        root.member = copy
        var pending = Object.assign({}, root.toggleRequests)
        delete pending[id]
        root.toggleRequests = pending
      }
    }
  }

  contentItem: Column {
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: Style.space(31)
      Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(8)
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "search"; size: Style.space(12); color: root.muted }
        TextInput {
          id: searchField
          width: parent.width - Style.space(20)
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          selectionColor: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          clip: true
          onTextChanged: root.filter = text
          Text {
            visible: searchField.text === ""
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: L.tr("Найти плейлист")
            color: root.muted
            font: searchField.font
          }
        }
      }
    }

    ListView {
      id: list
      width: parent.width
      height: Math.min(Style.space(240), Math.max(Style.space(30), contentHeight))
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.shown
      delegate: Item {
        required property var modelData
        readonly property bool present: root.member[modelData.id] === true
        width: list.width
        height: Style.space(30)
        activeFocusOnTab: true
        Accessible.role: Accessible.CheckBox
        Accessible.name: String(modelData.name)
        Accessible.checked: present
        function toggle() {
          if (root.batch) { if (!present) root.addAll(modelData.id); return }
          var id = root.logic.request("playlist_toggle", { playlistId: modelData.id, media: root.media, present: present })
          var pending = Object.assign({}, root.toggleRequests)
          pending[id] = modelData.id
          root.toggleRequests = pending
        }
        Keys.onReturnPressed: toggle()
        Rectangle {
          anchors.fill: parent
          color: pickMouse.containsMouse || parent.activeFocus ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06) : "transparent"
        }
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(10)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14)
            height: width
            color: present ? Color.accent : "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: present ? Color.accent : root.muted
            Icon { anchors.centerIn: parent; visible: present; name: "check"; size: Style.space(10); color: Color.background }
          }
          Text {
            width: parent.width - Style.space(34) - countLabel.width
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tb(modelData.name)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            elide: Text.ElideRight
          }
          Text {
            id: countLabel
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String(modelData.itemCount !== undefined ? modelData.itemCount : "")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
          }
        }
        MouseArea { id: pickMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: toggle() }
      }
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    Rectangle { width: parent.width; height: Math.max(1, Style.space(1)); color: root.lineColor }

    Item {
      width: parent.width
      height: Style.space(32)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(10)
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "plus"; size: Style.space(14); color: Color.accent }
        TextInput {
          id: newField
          width: parent.width - Style.space(24)
          anchors.verticalCenter: parent.verticalCenter
          color: Color.accent
          selectionColor: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          clip: true
          onAccepted: {
            if (text.trim() === "") return
            root.createRequestId = root.logic.request("playlist_create", { name: text })
            text = ""
          }
          Text {
            visible: newField.text === ""
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: L.tr("Новый плейлист…")
            color: Color.accent
            font: newField.font
          }
        }
      }
    }
  }
}
