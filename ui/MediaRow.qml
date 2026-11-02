import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
  id: root

  property var item: ({})
  property var logic: null
  property bool current: false
  property bool compact: false
  property bool showThumbnail: true
  property int rowNumber: 0
  property bool allowEnqueue: true
  property bool allowSave: true
  property bool allowPlaylist: true
  property bool showQueueMark: true
  property bool commandsEnabled: false
  property string saveTooltip: L.tr("Сохранить")
  property string playlistTooltip: L.tr("Добавить в плейлист")
  property bool editable: Boolean(item.entryId)
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal playRequested(var item)
  signal nextRequested(var item)
  signal endRequested(var item)
  signal openRequested(var item)
  signal saveRequested(var item)
  signal playlistRequested(var item)
  signal channelRequested(var entity)
  property bool prefetchOnHover: false
  signal commandRequested(string command, var payload)
  signal timecodeRequested(var media)
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
  // Playback state of this row: loading / playing / paused / error, or watched / unavailable / "".
  readonly property var playerState: logic ? logic.stateData : ({})
  readonly property bool sameEntry: !item.entryId || !playerState.current || item.entryId === playerState.current.entryId
  readonly property string rowState: {
    if (unavailable) return "unavailable"
    var state = logic && sameEntry ? logic.mediaState(media.videoId) : ""
    if (state === "queued") state = ""
    if (state === "" && current) state = "paused"
    if (state === "" && watchedRatio >= .92) return "watched"
    return state
  }
  readonly property bool active: rowState === "playing" || rowState === "paused"
  readonly property bool unavailable: item.unavailable === true || media.unavailable === true
    || /^\[(Deleted|Private) video\]$/.test(String(media.title || ""))
  readonly property string positionText: formatDuration(Number(playerState.position || 0)) || "0:00"
  readonly property string errorText: {
    var error = playerState.error || ({})
    return L.tb(error.message || L.tr("Не удалось открыть поток"))
  }
  readonly property bool actionFocused: playAction.activeFocus
    || saveAction.activeFocus || playlistAction.activeFocus
    || moreButton.activeFocus
  property bool keyboardActionsVisible: false
  onActionFocusedChanged: {
    if (actionFocused) keyboardActionsVisible = true
    else deferActionHide()
  }
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property real watchedRatio: item.watchProgress && Number(item.watchProgress.duration) > 0
    ? Math.min(1, Number(item.watchProgress.position) / Number(item.watchProgress.duration)) : 0
  readonly property string metaText: {
    if (rowState === "loading") return L.tr("загрузка потока…")
    if (rowState === "error") return errorText + L.tr(" · нажмите, чтобы повторить")
    if (rowState === "unavailable") return L.tr("видео недоступно")
    var total = formatDuration(media.duration)
    if (rowState === "playing") return L.tb(media.author || L.tr("Автор неизвестен")) + " · " + positionText + (total ? " / " + total : "")
    if (rowState === "paused") return L.tr("на паузе · ") + positionText + (total ? " / " + total : "")
    if (rowState === "watched") return L.tr("просмотрено")
    var parts = [L.tb(media.author || item.author || item.kind || L.tr("Автор неизвестен"))]
    if (playable && hasViewCount) parts.push(formatCount(media.viewCount))
    if (playable && hasLikeCount) parts.push("♥ " + formatCount(media.likeCount))
    return parts.join(" · ")
  }
  readonly property bool hasViewCount: root.validCount(root.media.viewCount)
  readonly property bool hasLikeCount: root.validCount(root.media.likeCount)
  readonly property var menuModel: {
    var rows = []
    if (allowEnqueue && playable) {
      rows.push({ group: 1, action: "next", icon: "list-start", label: L.tr("Играть следующим") })
      rows.push({ group: 1, action: "end", icon: "list-plus", label: L.tr("В мою очередь") })
    }
    if (commandsEnabled && playable) rows.push({ group: 1, action: "radio", icon: "radio", label: L.tr("Радио по видео") })
    if (item.kind === "playlist" && item.source !== "local")
      rows.push({ group: 1, action: "copy", icon: "copy", label: L.tr("Скопировать в медиатеку") })
    if (allowPlaylist && playable) rows.push({ group: 2, action: "playlist", icon: "list-plus", label: L.tr("В плейлист…") })
    if (commandsEnabled && playable) {
      rows.push({ group: 2, action: "later", icon: "clock-3", label: L.tr("Смотреть позже") })
      rows.push({ group: 2, action: "download", icon: "download", label: L.tr("Скачать") })
    }
    if (playable && media.canonicalUrl) {
      rows.push({ group: 3, action: "copylink", icon: "link", label: L.tr("Копировать ссылку") })
      if (commandsEnabled && active) rows.push({ group: 3, action: "timecode", icon: "clock-4", label: L.tr("Ссылка с таймкодом") })
      rows.push({ group: 3, action: "browser", icon: "external-link", label: L.tr("Открыть в браузере") })
    }
    if (playable && media.authorId) rows.push({ group: 3, action: "channel", icon: "user", label: L.tr("Перейти на канал") })
    if (commandsEnabled && playable && media.authorId)
      rows.push({ group: 4, action: "hide", icon: "eye-off", label: L.tr("Не рекомендовать канал") })
    if (editable) {
      rows.push({ group: 4, action: "up", icon: "arrow-up", label: L.tr("Переместить выше") })
      rows.push({ group: 4, action: "down", icon: "arrow-down", label: L.tr("Переместить ниже") })
      rows.push({ group: 4, action: "remove", icon: "trash-2", label: L.tr("Убрать из очереди"), danger: true })
    }
    return rows
  }
  readonly property bool hasMenuActions: menuModel.length > 0

  width: parent ? parent.width : Style.space(400)
  height: Style.space(56)
  radius: 0
  color: rowState === "playing" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
    : (rowState === "paused" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .08)
    : (rowState === "error" ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .06)
    : (rowState === "loading" || (hovered && rowState !== "unavailable") ? Qt.rgba(foreground.r, foreground.g, foreground.b, .05) : "transparent")))

  Rectangle {
    visible: root.active || root.rowState === "error"
    z: 3
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(2, Style.space(2))
    color: root.rowState === "error" ? Color.urgent : (root.rowState === "playing" ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .5))
  }

  HoverHandler { id: hover }

  Timer {
    interval: 350
    running: root.prefetchOnHover && root.hovered && String(root.media.videoId || "") !== ""
    onTriggered: root.commandRequested("prefetch", { videoId: String(root.media.videoId) })
  }

  Button {
    id: activationButton
    objectName: "activationButton"
    z: 1
    anchors.fill: parent
    focusable: true
    Accessible.name: String(root.media.title || root.media.videoId
      || root.item.name || L.tr("Без названия")) + ", "
      + L.tb(root.media.author || root.item.author || L.tr("Автор неизвестен"))
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
    enabled: root.rowState !== "unavailable"
    onClicked: root.activate()
    onRightClicked: if (root.hasMenuActions) rowMenu.open()
  }

  Row {
    z: 2
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
        : root.rowState === "watched" && !root.hovered ? "check"
        : root.rowState === "unavailable" ? "ban"
        : root.rowState === "" && root.hovered && root.playable ? "play"
        : (root.rowState === "" && root.rowNumber === 0 ? (root.playable ? "play" : "list-video") : "")
      Equalizer {
        visible: root.rowState === "playing"
        anchors.centerIn: parent
        maxHeight: Style.space(12)
      }
      Icon {
        id: playbackGlyph
        visible: parent.glyph !== ""
        anchors.centerIn: parent
        name: parent.glyph
        size: Style.space(13)
        color: root.rowState === "error" ? Color.urgent
          : (root.rowState === "loading" || root.rowState === "paused" ? Color.accent
          : (root.hovered && root.rowState === "" ? root.foreground : root.dim))
        NumberAnimation on rotation { running: root.rowState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onStopped: playbackGlyph.rotation = 0 }
      }
      Text {
        visible: parent.glyph === "" && root.rowState !== "playing"
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.rowNumber > 0 ? String(root.rowNumber) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }

    Rectangle {
      visible: root.showThumbnail
      width: visible ? Style.space(72) : 0
      height: Style.space(40)
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      clip: true
      CatalogImage {
        anchors.fill: parent
        visible: root.rowState !== "unavailable"
        opacity: root.rowState === "watched" ? .55 : 1
        requestedSource: root.rowState === "unavailable" ? "" : root.thumbnailSource
        foreground: root.foreground
        fontFamily: root.fontFamily
        emptyIcon: root.playable ? "󰝚" : "󰒍"
        fillMode: Image.PreserveAspectCrop
      }
      Rectangle {
        visible: root.watchedRatio > 0 && root.watchedRatio < .92 && !root.active
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Math.max(2, Style.space(2))
        width: parent.width * root.watchedRatio
        color: Color.accent
      }
    }

    Column {
      width: Math.max(Style.space(100), parent.width - Style.space(18)
        - (root.showThumbnail ? Style.space(84) : 0)
        - (actions.visible ? actions.width + Style.space(12) : trailing.width + Style.space(12))
        - Style.space(12))
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.rowState === "unavailable" && /^\[/.test(String(root.media.title || ""))
          ? L.tr("Удалённое видео") : String(root.media.title || root.media.videoId || root.item.name || root.item.id || L.tr("Без названия"))
        color: root.rowState === "playing" ? Color.accent : (root.rowState === "error" ? Color.urgent
          : (root.rowState === "watched" || root.rowState === "unavailable" ? root.dim : root.foreground))
        font.family: root.fontFamily
        font.pixelSize: Style.space(13)
        font.bold: root.active
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.metaText
        color: root.rowState === "loading" ? Color.accent : (root.rowState === "error" ? Color.urgent : root.dim)
        opacity: root.rowState === "watched" || root.rowState === "unavailable" ? .75 : 1
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
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

    Item {
      id: trailing
      z: 3
      visible: !actions.visible
      width: Math.max(Style.space(32), durationLabel.implicitWidth, queueMark.visible ? queueMark.width : 0)
      height: parent.height
      QueueMark {
        id: queueMark
        z: 1
        visible: root.showQueueMark && position > 0 && root.rowState !== "loading" && root.rowState !== "error"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        logic: root.logic
        videoId: String(root.media.videoId || "")
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
      Text {
        id: durationLabel
        visible: !queueMark.visible && root.rowState !== "loading" && root.rowState !== "error"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.active ? root.positionText : (root.rowState === "unavailable" ? "—" : root.formatDuration(root.media.duration))
        color: root.rowState === "playing" ? Color.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      IconButton {
        visible: root.rowState === "loading" || root.rowState === "error"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: Style.space(28)
        icon: root.rowState === "error" ? "rotate-cw" : "x"
        iconSize: root.rowState === "error" ? 14 : 12
        danger: root.rowState === "error"
        tooltipText: root.rowState === "error" ? L.tr("Повторить") : L.tr("Отменить загрузку (Esc)")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.logic.request(root.rowState === "error" ? "play" : "cancel_load")
      }
    }

    Row {
      id: actions
      z: 3
      visible: (root.hovered || root.keyboardActionsVisible
        || root.actionFocused || rowMenu.opened) && ["loading", "error", "unavailable"].indexOf(root.rowState) < 0
      width: visible ? implicitWidth : 0
      height: parent.height
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      IconButton {
        id: playAction
        objectName: "playAction"
        visible: root.playable && root.keyboardActionsVisible && !root.hovered
        width: visible ? Style.space(28) : 0
        anchors.verticalCenter: parent.verticalCenter
        icon: "play"
        iconSize: 14
        tooltipText: L.tr("Воспроизвести")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.playRequested(root.item)
      }
      IconButton {
        id: saveAction
        objectName: "saveAction"
        visible: root.playable && root.allowSave
        width: visible ? Style.space(28) : 0
        anchors.verticalCenter: parent.verticalCenter
        icon: "heart"
        iconSize: 14
        tooltipText: root.saveTooltip
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.saveRequested(root.item)
      }
      IconButton {
        id: playlistAction
        objectName: "playlistAction"
        visible: root.playable && root.allowPlaylist
        width: visible ? Style.space(28) : 0
        anchors.verticalCenter: parent.verticalCenter
        icon: "list-plus"
        iconSize: 14
        tooltipText: root.playlistTooltip
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.playlistRequested(root.media)
      }
      IconButton {
        id: moreButton
        objectName: "moreButton"
        visible: root.hasMenuActions
        width: visible ? Style.space(28) : 0
        anchors.verticalCenter: parent.verticalCenter
        icon: "ellipsis"
        iconSize: 14
        tooltipText: L.tr("Другие действия")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: rowMenu.open()
      }
    }
  }

  RowMenu {
    id: rowMenu
    anchorItem: root
    returnFocusItem: moreButton
    title: String(root.media.title || root.item.name || "")
    subtitle: L.tb(root.media.author || "") + (root.formatDuration(root.media.duration) !== "" ? " · " + root.formatDuration(root.media.duration) : "")
    actions: root.menuModel
    foreground: root.foreground
    fontFamily: root.fontFamily
    onTriggered: action => root.triggerMenuAction(action)
  }
  function activate() {
    if (rowState === "unavailable") return
    if (rowState === "error") logic.request("play")
    else if (active && logic) logic.request("toggle_pause")
    else if (rowState === "loading") return
    else if (playable) playRequested(item)
    else openRequested(item)
  }

  function deferActionHide() {
    Qt.callLater(function() {
      if (!activationButton.activeFocus && !root.actionFocused
          && !rowMenu.opened)
        root.keyboardActionsVisible = false
    })
  }


  function triggerMenuAction(action) {
    if (action === "next") nextRequested(media)
    else if (action === "end") endRequested(media)
    else if (action === "copy") copyRequested(item)
    else if (action === "playlist") playlistRequested(media)
    else if (action === "download") commandRequested("download_add", { media: media })
    else if (action === "later") commandRequested("watch_later", { media: media })
    else if (action === "radio") commandRequested("radio", { videoId: String(media.videoId) })
    else if (action === "hide") commandRequested("hide_channel", { channelId: L.tb(media.authorId), title: L.tb(media.author || "") })
    else if (action === "timecode") timecodeRequested(media)
    else if (action === "channel") channelRequested({ source: "youtube", kind: "channel", id: L.tb(media.authorId), title: L.tb(media.author || "") })
    else if (action === "copylink") {
      if (logic) logic.copyLink(media.canonicalUrl, 0)
      else Quickshell.execDetached(["wl-copy", String(media.canonicalUrl)])
    }
    else if (action === "browser") Quickshell.execDetached(["xdg-open", String(media.canonicalUrl)])
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
    if (count >= 1000000000) return (count / 1000000000).toFixed(count >= 10000000000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" млрд")
    if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
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
