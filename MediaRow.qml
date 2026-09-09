import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  property var item: ({})
  property bool current: false
  property bool compact: false
  property bool showThumbnail: true
  property int rowNumber: 0
  property bool allowEnqueue: true
  property bool allowSave: true
  property bool allowPlaylist: true
  property string saveTooltip: "Сохранить"
  property string playlistTooltip: "Добавить в плейлист"
  property bool editable: Boolean(item.entryId)
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal playRequested(var item)
  signal nextRequested(var item)
  signal endRequested(var item)
  signal openRequested(var item)
  signal saveRequested(var item)
  signal playlistRequested(var item)
  signal copyRequested(var item)
  signal removeRequested(var item)
  signal moveUpRequested(var item)
  signal moveDownRequested(var item)
  signal focusRequested()

  readonly property var media: item.media || item
  readonly property bool playable: Boolean(media.videoId)
  readonly property string thumbnailSource: String(media.thumbnailUrl
    || (media.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(media.videoId) + "/hqdefault.jpg" : ""))
  readonly property bool hovered: hover.hovered
  readonly property bool actionFocused: playAction.activeFocus
    || saveAction.activeFocus || playlistAction.activeFocus
    || moreButton.activeFocus
  property bool keyboardActionsVisible: false
  onActionFocusedChanged: {
    if (actionFocused) keyboardActionsVisible = true
    else deferActionHide()
  }
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property bool hasViewCount: root.validCount(root.media.viewCount)
  readonly property bool hasLikeCount: root.validCount(root.media.likeCount)
  readonly property var menuModel: {
    var rows = []
    if (allowEnqueue && playable) {
      rows.push({ action: "next", icon: "󰒭", label: "Воспроизвести следующим" })
      rows.push({ action: "end", icon: "󰐕", label: "Добавить в конец очереди" })
    }
    if (item.kind === "playlist" && item.source !== "local")
      rows.push({ action: "copy", icon: "󰆏", label: "Скопировать в медиатеку" })
    if (editable) {
      rows.push({ action: "up", icon: "󰁝", label: "Переместить выше" })
      rows.push({ action: "down", icon: "󰁅", label: "Переместить ниже" })
      rows.push({ action: "remove", icon: "󰆴", label: "Удалить", danger: true })
    }
    return rows
  }
  readonly property bool hasMenuActions: menuModel.length > 0

  width: parent ? parent.width : Style.space(400)
  height: compact ? Style.space(58) : Style.space(64)
  radius: Style.cornerRadius
  color: current ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .16)
    : (hovered ? Style.hoverFillFor(foreground, Color.accent) : "transparent")
  border.width: current ? Math.max(1, Style.space(1)) : 0
  border.color: current ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .38) : "transparent"

  HoverHandler { id: hover }

  Button {
    id: activationButton
    objectName: "activationButton"
    z: 1
    anchors.fill: parent
    anchors.rightMargin: actions.visible ? actions.width + Style.space(8) : 0
    focusable: true
    Accessible.name: String(root.media.title || root.media.videoId
      || root.item.name || "Без названия") + ", "
      + String(root.media.author || root.item.author || "Автор неизвестен")
    horizontalPadding: 0
    verticalPadding: 0
    onActiveFocusChanged: {
      if (activeFocus) {
        root.keyboardActionsVisible = true
        root.focusRequested()
      } else {
        root.deferActionHide()
      }
    }
    onClicked: root.playable
      ? root.playRequested(root.item) : root.openRequested(root.item)
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    spacing: Style.space(9)

    Item {
      width: Style.space(24)
      height: parent.height
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.current ? (root.item && root.item.media && root.item.media.videoId ? "󰏤" : "•")
          : (root.rowNumber > 0 ? String(root.rowNumber) : (root.playable ? "󰐊" : "󰒍"))
        color: root.current ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: root.current ? Style.font.icon : Style.font.caption
      }
    }

    Rectangle {
      visible: root.showThumbnail
      width: visible ? Style.space(46) : 0
      height: Style.space(46)
      anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(3)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      clip: true
      CatalogImage {
        anchors.fill: parent
        requestedSource: root.thumbnailSource
        foreground: root.foreground
        fontFamily: root.fontFamily
        emptyIcon: root.playable ? "󰝚" : "󰒍"
        fillMode: Image.PreserveAspectCrop
      }
    }

    Column {
      width: Math.max(Style.space(100), parent.width - Style.space(24)
        - (root.showThumbnail ? Style.space(55) : 0)
        - (actions.visible ? actions.width + Style.space(9) : durationLabel.width + Style.space(9))
        - parent.spacing)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || root.media.videoId || root.item.name || root.item.id || "Без названия")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: root.current
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.author || root.item.author || root.item.kind || "Автор неизвестен")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Row {
        visible: root.playable && (root.hasViewCount || root.hasLikeCount)
        height: visible ? metricsLabel.implicitHeight : 0
        spacing: Style.space(10)
        Text {
          id: metricsLabel
          textFormat: Text.PlainText
          text: root.hasViewCount ? "󰈈  " + root.formatCount(root.media.viewCount) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          textFormat: Text.PlainText
          text: "󰋑  " + (root.hasLikeCount ? root.formatCount(root.media.likeCount) : "—")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      id: durationLabel
      visible: !actions.visible
      width: Math.max(Style.space(32), implicitWidth)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: root.formatDuration(root.media.duration)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Row {
      id: actions
      z: 3
      visible: root.hovered || root.keyboardActionsVisible
        || root.actionFocused || rowMenu.opened
      width: visible ? implicitWidth : 0
      height: parent.height
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Button {
        id: playAction
        objectName: "playAction"
        focusable: true
        Accessible.name: tooltipText
        visible: root.playable
        width: visible ? Style.space(30) : 0
        height: Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐊"
        iconSize: Style.font.icon
        tooltipText: "Воспроизвести"
        foreground: root.foreground
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.playRequested(root.item)
      }
      Button {
        id: saveAction
        objectName: "saveAction"
        focusable: true
        Accessible.name: tooltipText
        visible: root.playable && root.allowSave
        width: visible ? Style.space(30) : 0
        height: Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰋑"
        iconSize: Style.font.icon
        tooltipText: root.saveTooltip
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.saveRequested(root.item)
      }
      Button {
        id: playlistAction
        objectName: "playlistAction"
        focusable: true
        Accessible.name: tooltipText
        visible: root.playable && root.allowPlaylist
        width: visible ? Style.space(30) : 0
        height: Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐕"
        iconSize: Style.font.icon
        tooltipText: root.playlistTooltip
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.playlistRequested(root.media)
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: moreButton
        objectName: "moreButton"
        visible: root.hasMenuActions
        width: visible ? Style.space(30) : 0
        height: Style.space(30)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰇙"
        iconSize: Style.font.icon
        tooltipText: "Другие действия"
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: rowMenu.open()
      }
    }
  }

  Popup {
    id: rowMenu
    parent: Overlay.overlay
    objectName: "rowMenu"
    readonly property point anchorPosition: parent ? root.mapToItem(parent, 0, 0) : Qt.point(0, 0)
    x: parent ? Math.max(Style.space(8), Math.min(parent.width - width - Style.space(8),
      anchorPosition.x + root.width - width - Style.space(4))) : 0
    y: parent ? Math.max(Style.space(8), Math.min(parent.height - height - Style.space(8),
      anchorPosition.y + root.height - Style.space(2))) : 0
    width: Style.space(218)
    height: menuColumn.implicitHeight + Style.space(8)
    padding: Style.space(4)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    popupType: Popup.Item
    onOpened: Qt.callLater(function() {
      var first = menuRepeater.itemAt(0)
      if (first) first.forceActiveFocus()
    })
    onClosed: if (moreButton.visible) moreButton.forceActiveFocus()

    background: Rectangle {
      radius: Style.cornerRadius
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g,
        Color.popups.background.b, 1)
      border.width: Math.max(1, Style.space(1))
      border.color: Color.popups.border
    }

    contentItem: Column {
      id: menuColumn
      spacing: Style.space(2)
      Repeater {
        id: menuRepeater
        model: root.menuModel
        delegate: Button {
          id: actionRow
          objectName: "menuAction-" + modelData.action
          required property var modelData
          width: menuColumn.width
          height: Style.space(34)
          text: modelData.label
          iconText: modelData.icon
          leftAlign: true
          focusable: true
          Accessible.name: text
          foreground: modelData.danger === true
            ? Color.urgent : root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          iconSize: Style.font.icon
          horizontalPadding: Style.space(8)
          verticalPadding: 0
          onClicked: root.triggerMenuAction(modelData.action)
        }
      }
    }
  }
  function deferActionHide() {
    Qt.callLater(function() {
      if (!activationButton.activeFocus && !root.actionFocused
          && !rowMenu.opened)
        root.keyboardActionsVisible = false
    })
  }


  function triggerMenuAction(action) {
    rowMenu.close()
    if (action === "next") nextRequested(media)
    else if (action === "end") endRequested(media)
    else if (action === "copy") copyRequested(item)
    else if (action === "up") moveUpRequested(item)
    else if (action === "down") moveDownRequested(item)
    else if (action === "remove") removeRequested(item)
  }

  function validCount(value) {
    return value !== null && value !== undefined && value !== "" && isFinite(Number(value)) && Number(value) >= 0
  }

  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0)) return ""
    if (count >= 1000000000) return (count / 1000000000).toFixed(count >= 10000000000 ? 0 : 1).replace(".", ",") + " млрд"
    if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1).replace(".", ",") + " млн"
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", ",") + " тыс."
    return String(Math.floor(count))
  }
  function formatDuration(value) {
    var seconds = Number(value || 0)
    if (!(seconds > 0)) return ""
    seconds = Math.floor(seconds)
    var minutes = Math.floor(seconds / 60)
    var rest = seconds % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }
}
