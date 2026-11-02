import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

// A video in the "Now" queue: handle · number/▶ · thumbnail · title/meta · duration or row actions.
// Order belongs to the user here, so the row can be dragged, played next and removed.
// At rest it shows only number, thumbnail, title and duration; controls appear on hover and keyboard focus.
FocusScope {
  id: root

  property var item: ({})
  property var logic: null
  property int rowNumber: 0
  property bool current: false
  property bool played: false
  property bool isNext: false
  property string nextIn: ""
  property bool fresh: false
  property bool flash: false
  property bool selected: false
  property bool selectionMode: false
  // "" | "ghost" (empty slot left behind while dragging) | "lifted" (the row under the cursor)
  property string dragRole: ""
  property string dragHint: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal playRequested()
  signal nextRequested()
  signal removeRequested()
  signal moveRequested(int delta)
  signal navigateRequested(int delta)
  signal selectRequested(bool toggle, bool range)
  signal selectionCleared()
  signal playlistRequested(var media)
  signal channelRequested(var entity)
  signal commandRequested(string command, var payload)
  signal timecodeRequested(var media)
  signal dragStarted(real y)
  signal dragMoved(real y)
  signal dragFinished()

  readonly property var media: item.media || item
  readonly property string videoId: String(media.videoId || "")
  readonly property bool playable: videoId !== ""
  readonly property string thumbnailSource: String(media.thumbnailUrl
    || (playable ? "https://i.ytimg.com/vi/" + encodeURIComponent(videoId) + "/hqdefault.jpg" : ""))
  readonly property var playerState: logic ? logic.stateData : ({})
  readonly property bool unavailable: item.unavailable === true || media.unavailable === true
    || /^\[(Deleted|Private) video\]$/.test(String(media.title || ""))
  // loading | playing | paused | error | unavailable | ""
  readonly property string rowState: {
    if (unavailable) return "unavailable"
    if (!current) return ""
    var state = logic ? logic.mediaState(videoId) : ""
    return state === "" || state === "queued" ? "paused" : state
  }
  readonly property bool active: rowState === "playing" || rowState === "paused"
  readonly property bool busy: rowState === "loading" || rowState === "error" || rowState === "unavailable"
  readonly property bool saved: logic ? logic.isSaved(videoId) : false
  readonly property bool hovered: hover.hovered && dragRole === ""
  readonly property bool engaged: hovered || activeFocus || rowMenu.opened || dragRole === "lifted"
  readonly property bool showActions: engaged && !busy && !selectionMode && dragRole === ""
  readonly property bool canDrag: !current && !selectionMode
  readonly property bool canPlayNext: playable && !current && !isNext && !unavailable
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property real position: Number(playerState.position || 0)
  readonly property real duration: Number(current && playerState.duration || media.duration || 0)
  readonly property string errorText: L.tb((playerState.error || ({})).message || L.tr("Не удалось открыть поток"))

  readonly property string metaText: {
    if (dragRole === "lifted" && dragHint !== "") return dragHint
    if (rowState === "loading") return L.tr("загрузка потока…")
    if (rowState === "error") return errorText + L.tr(" · повторить")
    if (rowState === "unavailable") return L.tr("недоступно · будет пропущено")
    var total = formatDuration(duration)
    var progress = formatDuration(position) || "0:00"
    if (rowState === "paused") return L.tr("на паузе · ") + progress + (total ? " / " + total : "")
    var author = L.tb(media.author || L.tr("Автор неизвестен"))
    if (rowState === "playing") return author + " · " + progress + (total ? " / " + total : "")
    if (isNext && nextIn !== "") return author + L.tr(" · через ") + nextIn
    if (fresh) return author + L.tr(" · только что добавлено")
    return validCount(media.viewCount) ? author + " · " + formatCount(media.viewCount) : author
  }
  readonly property string trailingText: {
    if (rowState === "unavailable") return "—"
    if (active && duration > 0) return "−" + formatDuration(Math.max(0, duration - position))
    return formatDuration(media.duration)
  }

  readonly property var menuModel: {
    var rows = []
    if (canPlayNext) rows.push({ group: 1, action: "next", icon: "list-start", label: L.tr("Играть следующим"), shortcut: "N" })
    if (playable) rows.push({ group: 1, action: "radio", icon: "radio", label: L.tr("Радио по видео") })
    if (playable) {
      rows.push({ group: 2, action: "playlist", icon: "list-plus", label: L.tr("В плейлист…") })
      rows.push({ group: 2, action: "later", icon: "clock-3", label: L.tr("Смотреть позже") })
      rows.push({ group: 2, action: "download", icon: "download", label: L.tr("Скачать") })
    }
    if (playable && media.canonicalUrl) {
      rows.push({ group: 3, action: "copylink", icon: "link", label: L.tr("Копировать ссылку") })
      if (active) rows.push({ group: 3, action: "timecode", icon: "clock-4", label: L.tr("Ссылка с таймкодом") })
      rows.push({ group: 3, action: "browser", icon: "external-link", label: L.tr("Открыть в браузере") })
    }
    if (playable && media.authorId) rows.push({ group: 3, action: "channel", icon: "user", label: L.tr("Перейти на канал") })
    if (!current) {
      rows.push({ group: 4, action: "up", icon: "arrow-up", label: L.tr("Переместить выше"), shortcut: "Alt+↑" })
      rows.push({ group: 4, action: "down", icon: "arrow-down", label: L.tr("Переместить ниже"), shortcut: "Alt+↓" })
    }
    rows.push({ group: 4, action: "remove", icon: "x", label: L.tr("Убрать из очереди"), shortcut: "Del", danger: true })
    return rows
  }

  width: parent ? parent.width : Style.space(400)
  height: Style.space(48)
  activeFocusOnTab: true
  Accessible.role: Accessible.ListItem
  Accessible.name: String(media.title || videoId || L.tr("Без названия")) + ", " + L.tb(media.author || L.tr("Автор неизвестен"))
  Accessible.selected: selected

  Keys.onPressed: event => {
    var alt = event.modifiers & Qt.AltModifier
    var plain = event.modifiers === Qt.NoModifier || event.modifiers === Qt.KeypadModifier
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && plain) root.activate()
    else if (event.key === Qt.Key_Up && alt) { if (!root.current) root.moveRequested(-1) }
    else if (event.key === Qt.Key_Down && alt) { if (!root.current) root.moveRequested(1) }
    else if (event.key === Qt.Key_Up && plain) root.navigateRequested(-1)
    else if (event.key === Qt.Key_Down && plain) root.navigateRequested(1)
    else if (event.key === Qt.Key_N && plain) { if (root.canPlayNext) root.nextRequested() }
    else if (event.key === Qt.Key_S && plain) root.toggleSaved()
    else if (event.key === Qt.Key_Delete && plain) root.removeRequested()
    else if (event.key === Qt.Key_Menu) rowMenu.open()
    else if (event.key === Qt.Key_Space && (event.modifiers & Qt.ControlModifier)) root.selectRequested(true, false)
    else return
    event.accepted = true
  }

  // Lifted copy under the cursor while dragging.
  RectangularShadow {
    visible: root.dragRole === "lifted"
    anchors.fill: background
    offset: Qt.vector2d(0, Style.space(8))
    blur: Style.space(20)
    color: Qt.rgba(0, 0, 0, .6)
  }

  Rectangle {
    id: background
    anchors.fill: parent
    readonly property color accentSoft: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
    color: root.dragRole === "ghost" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .06)
      : root.dragRole === "lifted" ? Qt.tint(Color.background, Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1))
      : root.selected || root.flash || root.rowState === "playing" ? accentSoft
      : root.hovered && root.rowState !== "unavailable" ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
      : root.rowState === "paused" || root.rowState === "loading" ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .04)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0)
    border.width: root.dragRole !== "" || root.activeFocus && !root.hovered ? Math.max(1, Style.space(1)) : 0
    border.color: root.dragRole === "ghost" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .45)
      : root.dragRole === "lifted" ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .5)
    Behavior on color { ColorAnimation { duration: root.flash ? 0 : 600 } }
  }

  Rectangle {
    visible: root.dragRole === "" && (root.current || root.rowState === "error")
    z: 3
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(2))
    color: root.rowState === "error" ? Color.urgent : (root.rowState === "paused" ? root.dim : Color.accent)
  }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    enabled: root.dragRole === ""
    onPressed: root.forceActiveFocus()
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) { rowMenu.open(); return }
      var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0
      var range = (mouse.modifiers & Qt.ShiftModifier) !== 0
      if (toggle || range) root.selectRequested(toggle, range)
      else if (root.selectionMode) root.selectionCleared()
    }
    onDoubleClicked: mouse => {
      if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier) root.activate()
    }
  }

  Row {
    id: content
    z: 2
    // Stays visible (only transparent) as a ghost so the handle keeps its mouse grab during the drag.
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(10)
    opacity: root.dragRole === "ghost" ? 0 : root.dragRole === "lifted" ? 1 : root.rowState === "unavailable" ? .6 : root.played && !root.engaged && !root.selected ? .55 : 1

    // Drag handle: hidden at rest and on the current row, which is not draggable.
    Item {
      id: handle
      width: Style.space(12)
      height: Style.space(20)
      anchors.verticalCenter: parent.verticalCenter
      Icon {
        visible: root.canDrag && (root.engaged || handleMouse.drag)
        anchors.centerIn: parent
        name: "grip-vertical"
        size: Style.space(13)
        color: handleMouse.pressed || root.dragRole === "lifted" ? Color.accent
          : (handleMouse.containsMouse ? root.foreground : root.dim)
      }
      MouseArea {
        id: handleMouse
        property bool drag: false
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        enabled: root.canDrag
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: mouse => { drag = true; root.forceActiveFocus(); root.dragStarted(mapToItem(root, mouse.x, mouse.y).y) }
        onPositionChanged: mouse => { if (drag) root.dragMoved(mapToItem(root, mouse.x, mouse.y).y) }
        onReleased: { if (drag) { drag = false; root.dragFinished() } }
        onCanceled: { if (drag) { drag = false; root.dragFinished() } }
      }
    }

    // Number → ▶ on hover; state glyphs replace it for the current, played, unavailable and selected rows.
    Item {
      id: lead
      width: Style.space(20)
      height: parent.height
      readonly property string glyph: root.rowState === "loading" ? "loader-circle"
        : root.rowState === "paused" ? (leadMouse.containsMouse ? "play" : "pause")
        : root.rowState === "error" ? "triangle-alert"
        : root.rowState === "unavailable" ? "ban"
        : root.rowState === "playing" ? (leadMouse.containsMouse ? "pause" : "")
        : root.engaged && root.dragRole === "" && root.playable ? "play"
        : root.played ? "check" : ""
      Equalizer {
        visible: root.rowState === "playing" && !leadMouse.containsMouse
        anchors.centerIn: parent
        maxHeight: Style.space(12)
      }
      Icon {
        id: playbackGlyph
        visible: !root.selectionMode && lead.glyph !== ""
        anchors.centerIn: parent
        name: lead.glyph
        size: Style.space(15)
        color: root.rowState === "error" ? Color.urgent
          : root.rowState === "unavailable" ? root.dim
          : root.current || leadMouse.containsMouse ? Color.accent
          : root.engaged ? root.foreground : root.dim
        NumberAnimation on rotation { running: root.rowState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
      }
      Text {
        visible: !root.selectionMode && lead.glyph === "" && root.rowState !== "playing"
        anchors.centerIn: parent
        text: String(root.rowNumber)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      Rectangle {
        visible: root.selectionMode && !root.current
        anchors.centerIn: parent
        width: Style.space(14)
        height: width
        color: root.selected ? Color.accent : "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: root.selected ? Color.accent : root.dim
        Icon { visible: root.selected; anchors.centerIn: parent; name: "check"; size: Style.space(10); color: Color.background }
      }
      MouseArea {
        id: leadMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.rowState !== "unavailable" && root.dragRole === ""
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
          if (root.selectionMode && !root.current) root.selectRequested(true, (mouse.modifiers & Qt.ShiftModifier) !== 0)
          else root.activate()
        }
      }
    }

    Rectangle {
      width: Style.space(64)
      height: Style.space(36)
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
      clip: true
      CatalogImage {
        anchors.fill: parent
        visible: root.rowState !== "unavailable"
        requestedSource: root.rowState === "unavailable" ? "" : root.thumbnailSource
        foreground: root.foreground
        fontFamily: root.fontFamily
        emptyIcon: "󰝚"
        fillMode: Image.PreserveAspectCrop
      }
    }

    Column {
      width: parent.width - handle.width - lead.width - Style.space(64) - trailing.width - parent.spacing * 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      Row {
        width: parent.width
        spacing: Style.space(6)
        Rectangle {
          id: tag
          readonly property string label: root.isNext && !root.current ? L.tr("ДАЛЕЕ") : (root.fresh ? L.tr("НОВОЕ") : "")
          visible: label !== "" && root.dragRole === ""
          anchors.verticalCenter: parent.verticalCenter
          width: visible ? tagLabel.implicitWidth + Style.space(10) : 0
          height: tagLabel.implicitHeight + Style.space(2)
          color: label === L.tr("ДАЛЕЕ") ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
          Text {
            id: tagLabel
            anchors.centerIn: parent
            text: tag.label
            color: tag.label === L.tr("ДАЛЕЕ") ? Color.background : Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(8)
            font.bold: true
            font.letterSpacing: 1
          }
        }
        Text {
          width: parent.width - (tag.visible ? tag.width + parent.spacing : 0)
          textFormat: Text.PlainText
          text: root.rowState === "unavailable" && /^\[/.test(String(root.media.title || ""))
            ? L.tr("Удалённое видео") : String(root.media.title || root.videoId || L.tr("Без названия"))
          color: root.rowState === "playing" ? Color.accent : root.rowState === "error" ? Color.urgent
            : root.rowState === "unavailable" ? root.dim : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          font.bold: root.current
          elide: Text.ElideRight
        }
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.metaText
        color: root.rowState === "loading" ? Color.accent : (root.rowState === "error" ? Color.urgent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        elide: Text.ElideRight
      }
      Item {
        // Indeterminate stripe under the text while the stream is being resolved.
        id: loadingTrack
        visible: root.rowState === "loading"
        width: parent.width * .45
        height: visible ? Math.max(2, Style.space(2)) : 0
        clip: true
        Rectangle { anchors.fill: parent; color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) }
        Rectangle {
          id: loadingBar
          width: parent.width * .4
          height: parent.height
          color: Color.accent
          NumberAnimation on x { running: loadingTrack.visible; loops: Animation.Infinite; from: -loadingBar.width; to: loadingTrack.width; duration: 1000; easing.type: Easing.InOutQuad }
        }
      }
    }

    Row {
      id: trailing
      height: parent.height
      spacing: Style.space(2)

      Text {
        visible: !root.showActions && !root.busy
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: root.saved ? Style.space(4) : 0
        text: root.trailingText
        color: root.rowState === "playing" ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
      }
      RowAction {
        visible: root.rowState === "loading" || root.rowState === "error"
        icon: root.rowState === "error" ? "rotate-cw" : "x"
        danger: root.rowState === "error"
        tooltipText: root.rowState === "error" ? L.tr("Повторить") : L.tr("Отменить загрузку (Esc)")
        onClicked: if (root.logic) root.logic.request(root.rowState === "error" ? "play" : "cancel_load")
      }
      RowAction {
        visible: root.showActions
        enabled: root.canPlayNext
        icon: "list-start"
        active: root.isNext
        tooltipText: root.isNext ? L.tr("Уже следующее") : (root.current ? L.tr("Сейчас играет") : L.tr("Следующим · N"))
        onClicked: root.nextRequested()
      }
      RowAction {
        // A saved row keeps its mark visible at rest.
        visible: root.playable && (root.showActions || root.saved && !root.busy)
        icon: root.saved ? "bookmark-check" : "bookmark"
        active: root.saved
        tooltipText: root.saved ? L.tr("Убрать из «Сохранено» · S") : L.tr("Сохранить · S · ПКМ — в плейлист")
        onClicked: root.toggleSaved()
        onRightClicked: root.playlistRequested(root.media)
      }
      RowAction {
        visible: root.showActions
        icon: "x"
        removal: true
        tooltipText: L.tr("Убрать из очереди · Delete")
        onClicked: root.removeRequested()
      }
      RowAction {
        id: moreButton
        visible: root.showActions || rowMenu.opened
        icon: "ellipsis"
        active: rowMenu.opened
        tooltipText: L.tr("Ещё")
        onClicked: rowMenu.open()
      }
    }
  }

  RowMenu {
    id: rowMenu
    anchorItem: root
    returnFocusItem: root
    title: String(root.media.title || "")
    subtitle: L.tb(root.media.author || "") + (root.formatDuration(root.media.duration) !== "" ? " · " + root.formatDuration(root.media.duration) : "")
    actions: root.menuModel
    foreground: root.foreground
    fontFamily: root.fontFamily
    onTriggered: action => root.triggerMenuAction(action)
  }

  // 26×26 borderless row button: dim at rest, surface on hover, accent when pressed or active.
  // The removal button turns red on hover — it is the only destructive action in the row.
  component RowAction: Item {
    id: action
    property string icon: ""
    property bool active: false
    property bool danger: false
    property bool removal: false
    property string tooltipText: ""
    signal clicked()
    signal rightClicked()
    readonly property bool red: danger || removal && actionMouse.containsMouse

    width: visible ? Style.space(26) : 0
    height: Style.space(26)
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    activeFocusOnTab: visible && enabled
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText
    Keys.onReturnPressed: action.clicked()
    Keys.onSpacePressed: action.clicked()

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: !action.enabled ? "transparent"
        : actionMouse.pressed ? (action.removal ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .3) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18))
        : actionMouse.containsMouse ? (action.removal ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .15) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08))
        : action.active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
      border.width: action.activeFocus ? Math.max(1, Style.space(1)) : 0
      border.color: Color.accent
    }
    Icon {
      anchors.centerIn: parent
      name: action.icon
      size: Style.space(14)
      opacity: action.enabled ? 1 : .45
      color: action.red ? Color.urgent
        : !action.enabled ? root.dim
        : actionMouse.pressed || action.active ? Color.accent
        : actionMouse.containsMouse ? root.foreground : root.dim
    }
    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: action.enabled
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: mouse => mouse.button === Qt.RightButton ? action.rightClicked() : action.clicked()
    }
    PanelToolTip {
      visible: action.tooltipText !== "" && actionMouse.containsMouse
      text: action.tooltipText
      fontFamily: root.fontFamily
    }
  }

  function activate() {
    if (rowState === "unavailable" || rowState === "loading") return
    if (rowState === "error") { if (logic) logic.request("play") }
    else if (active) { if (logic) logic.request("toggle_pause") }
    else playRequested()
  }

  function toggleSaved() {
    if (playable && logic) logic.request("save_media", { media: media, saved: !saved })
  }

  function triggerMenuAction(action) {
    if (action === "next") nextRequested()
    else if (action === "playlist") playlistRequested(media)
    else if (action === "download") commandRequested("download_add", { media: media })
    else if (action === "later") commandRequested("watch_later", { media: media })
    else if (action === "radio") commandRequested("radio", { videoId: videoId })
    else if (action === "timecode") timecodeRequested(media)
    else if (action === "channel") channelRequested({ source: "youtube", kind: "channel", id: L.tb(media.authorId), title: L.tb(media.author || "") })
    else if (action === "copylink") {
      if (logic) logic.copyLink(media.canonicalUrl, 0)
      else Quickshell.execDetached(["wl-copy", String(media.canonicalUrl)])
    }
    else if (action === "browser") Quickshell.execDetached(["xdg-open", String(media.canonicalUrl)])
    else if (action === "up") moveRequested(-1)
    else if (action === "down") moveRequested(1)
    else if (action === "remove") removeRequested()
  }

  function validCount(value) {
    return value !== null && value !== undefined && value !== "" && isFinite(Number(value)) && Number(value) >= 0
  }

  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0)) return ""
    if (count >= 1000000000) return (count / 1000000000).toFixed(count >= 10000000000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" млрд")
    if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }

  function formatDuration(value) {
    var seconds = Number(value || 0)
    if (!(seconds > 0)) return ""
    seconds = Math.floor(seconds)
    var minutes = Math.floor(seconds / 60), rest = seconds % 60
    return minutes + ":" + (rest < 10 ? "0" : "") + rest
  }
}
