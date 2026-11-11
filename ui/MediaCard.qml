import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var item: ({})
  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool allowEnqueue: true
  property bool allowPlaylist: true

  signal playRequested(var item)
  signal nextRequested(var item)
  signal endRequested(var item)
  signal openRequested(var item)
  signal saveRequested(var item)
  signal playlistRequested(var item)
  signal channelRequested(var entity)
  signal copyRequested(var item)

  readonly property var media: item.media || item
  readonly property bool playable: Boolean(media.videoId)
  readonly property bool hovered: hover.hovered
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string thumbnailSource: String(media.thumbnailUrl
    || (media.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(media.videoId) + "/hqdefault.jpg" : ""))
  readonly property real progressRatio: item.watchProgress && Number(item.watchProgress.duration) > 0
    ? Math.min(1, Number(item.watchProgress.position) / Number(item.watchProgress.duration)) : 0
  readonly property bool watched: progressRatio >= 0.92 && cardState === ""
  readonly property var playerState: logic ? logic.stateData : ({})
  // loading / playing / paused / error / queued / "" — what the thumbnail overlay shows.
  readonly property string cardState: logic && playable ? logic.mediaState(media.videoId) : ""
  readonly property bool active: cardState === "playing" || cardState === "paused"
  readonly property real playRatio: active && Number(playerState.duration) > 0
    ? Math.min(1, Number(playerState.position || 0) / Number(playerState.duration)) : 0
  readonly property string chapterText: {
    var chapters = playerState.info && playerState.info.chapters ? playerState.info.chapters : []
    var position = Number(playerState.position || 0), found = -1
    for (var i = 0; i < chapters.length; ++i) if (position >= Number(chapters[i].start)) found = i
    return found >= 0 ? L.tr("глава ") + (found + 1) + "/" + chapters.length : ""
  }
  readonly property string stateLine: {
    var position = formatDuration(Number(playerState.position || 0)) || "0:00"
    if (cardState === "loading") return L.tr("загрузка потока…")
    if (cardState === "playing") return position + " / " + (formatDuration(playerState.duration || media.duration) || "—")
      + (chapterText !== "" ? " · " + chapterText : "")
    if (cardState === "paused") return L.tr("на паузе · ") + position
    if (cardState === "error") return L.tr("не удалось запустить · нажмите, чтобы повторить")
    if (cardState === "queued") return L.tb(media.author || item.author || "") + L.tr(" · добавлено")
    return ""
  }
  // Saving confirms with a toast that offers to put the video into a playlist.
  function save() {
    if (logic) logic.request("save_media", { media: media, saved: true })
    else playlistRequested(media)
  }
  readonly property bool saved: logic && playable ? logic.isSaved(media.videoId) : false
  function toggleSaved() {
    if (!saved) save()
    else if (logic) logic.request("save_media", { media: media, saved: false })
  }
  function removeFromQueue() {
    var entryId = logic ? logic.queueEntryId(media.videoId) : ""
    if (entryId !== "") logic.request("queue_remove", { entryId: entryId })
  }
  function activate() {
    if (cardState === "loading") return
    if (cardState === "error") logic.request("play")
    else if (active) logic.request("toggle_pause")
    else if (playable) playRequested(item)
    else openRequested(item)
  }
  readonly property bool isNew: item.isNew === true
  readonly property string kindLabel: item.kind === "playlist" ? L.tr("Плейлист") : String(item.kind || "")
  readonly property var menuModel: {
    var rows = []
    if (playable || String(item.kind || "") === "") return rows
    rows.push({ group: 1, action: "open", icon: item.kind === "playlist" ? "list-video" : "arrow-right", label: L.tr("Открыть") })
    if (item.kind === "playlist" && item.source !== "local")
      rows.push({ group: 1, action: "copy", icon: "copy", label: L.tr("Скопировать в медиатеку") })
    if (item.canonicalUrl) {
      rows.push({ group: 2, action: "copylink", icon: "link", label: L.tr("Копировать ссылку") })
      rows.push({ group: 2, action: "browser", icon: "external-link", label: L.tr("Открыть в браузере") })
    }
    return rows
  }
  function triggerMenuAction(action) {
    if (action === "open") openRequested(item)
    else if (action === "copy") copyRequested(item)
    else if (action === "copylink") Quickshell.execDetached(["/usr/bin/wl-copy", String(item.canonicalUrl)])
    else if (action === "browser") Quickshell.execDetached(["/usr/bin/xdg-open", String(item.canonicalUrl)])
  }
  readonly property string metaLine: {
    var parts = []
    parts.push(L.tb(media.author || item.author || (playable ? L.tr("Автор неизвестен") : kindLabel)))
    if (validCount(media.viewCount)) parts.push(formatCount(media.viewCount))
    return parts.join(" · ")
  }

  implicitHeight: thumb.height + info.implicitHeight + Style.space(8)
  readonly property bool authorLinked: Boolean(media.authorId) && playable

  function validCount(value) {
    return value !== null && value !== undefined && value !== "" && isFinite(Number(value)) && Number(value) >= 0
  }
  function formatCount(value) {
    var count = Number(value)
    if (count >= 1000000000) return (count / 1000000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млрд")
    if (count >= 1000000) return (count / 1000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }
  function formatDuration(value) {
    var seconds = Math.floor(Number(value || 0))
    if (!(seconds > 0)) return ""
    var hours = Math.floor(seconds / 3600)
    var minutes = Math.floor(seconds % 3600 / 60)
    var rest = seconds % 60
    return (hours > 0 ? hours + ":" + (minutes < 10 ? "0" : "") : "") + minutes + ":" + (rest < 10 ? "0" : "") + rest
  }

  signal prefetchRequested(string videoId)

  HoverHandler { id: hover }

  Timer {
    interval: 350
    running: root.hovered && String(root.media.videoId || "") !== ""
    onTriggered: root.prefetchRequested(String(root.media.videoId))
  }

  Button {
    id: activation
    objectName: "activationButton"
    z: 1
    anchors.fill: parent
    focusable: true
    Accessible.name: String(root.media.title || root.item.name || L.tr("Без названия")) + ", " + root.metaLine
    horizontalPadding: 0
    verticalPadding: 0
    onClicked: root.activate()
    onRightClicked: if (root.menuModel.length > 0) cardMenu.open()
  }

  Column {
    z: 2
    anchors.fill: parent
    anchors.margins: 0
    spacing: Style.space(8)

    Rectangle {
      id: thumb
      width: parent.width
      height: Math.round(width * 9 / 16)
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
      border.width: root.cardState === "loading" || root.cardState === "playing" ? Math.max(2, Style.space(2))
        : (root.hovered ? Math.max(1, Style.space(1)) : 0)
      border.color: root.cardState === "error" ? Color.urgent : Color.accent
      clip: true

      CatalogImage {
        anchors.fill: parent
        anchors.margins: parent.border.width
        opacity: root.watched ? .5 : 1
        requestedSource: root.thumbnailSource
        foreground: root.foreground
        fontFamily: root.fontFamily
        emptyIcon: root.playable ? "󰝚" : "󰒍"
        fillMode: Image.PreserveAspectCrop
      }

      Rectangle {
        visible: durationLabel.text !== ""
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(6)
        width: durationLabel.implicitWidth + Style.space(10)
        height: Style.space(18)
        radius: Style.space(3)
        color: Qt.rgba(0, 0, 0, .72)
        Text {
          id: durationLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: (root.watched ? "✓ " : "") + root.formatDuration(root.media.duration)
          color: "#FFFFFF"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        // Darkened frame + spinner between the click and the first frame.
        visible: root.cardState === "loading"
        anchors.fill: parent
        anchors.margins: parent.border.width
        color: Qt.rgba(0, 0, 0, .55)
        Column {
          anchors.centerIn: parent
          spacing: Style.space(8)
          Icon {
            id: loadingSpinner
            anchors.horizontalCenter: parent.horizontalCenter
            name: "loader-circle"
            size: Style.space(26)
            color: "#FFFFFF"
            RotationAnimator on rotation { running: loadingSpinner.animationVisible && root.cardState === "loading"; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running && loadingSpinner) loadingSpinner.rotation = 0 }
          }
          Text {
            textFormat: Text.PlainText
            text: L.tr("ЗАГРУЗКА")
            color: "#FFFFFF"
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: 2
          }
        }
      }

      Rectangle {
        id: stateBadge
        visible: root.active
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Style.space(7)
        width: badgeRow.implicitWidth + Style.space(12)
        height: Style.space(20)
        color: root.cardState === "paused" ? Qt.rgba(0, 0, 0, .72)
          : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, root.cardState === "queued" ? .85 : 1)
        Row {
          id: badgeRow
          anchors.centerIn: parent
          spacing: Style.space(5)
          readonly property color tone: root.cardState === "paused" ? "#FFFFFF" : Color.background
          Equalizer {
            visible: root.cardState === "playing"
            anchors.verticalCenter: parent.verticalCenter
            maxHeight: Style.space(9)
            barWidth: Math.max(1, Style.space(1.5))
            color: badgeRow.tone
          }
          Icon {
            visible: root.cardState !== "playing"
            anchors.verticalCenter: parent.verticalCenter
            name: root.cardState === "paused" ? "pause" : "list-checks"
            size: Style.space(11)
            color: badgeRow.tone
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.cardState === "playing" ? L.tr("ИГРАЕТ") : (root.cardState === "paused" ? L.tr("ПАУЗА")
              : L.tr("В ОЧЕРЕДИ · ") + (root.logic ? root.logic.queuePosition(root.media.videoId) : ""))
            color: badgeRow.tone
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: 1
          }
        }
      }

      Rectangle {
        visible: root.cardState === "paused" && !root.hovered
        anchors.centerIn: parent
        width: Style.space(40)
        height: width
        radius: width / 2
        color: Qt.rgba(0, 0, 0, .72)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(1, 1, 1, .6)
        Icon { anchors.centerIn: parent; name: "play"; size: Style.space(17); color: "#FFFFFF" }
      }

      Rectangle {
        visible: root.isNew && !stateBadge.visible
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: Style.space(6)
        width: newLabel.implicitWidth + Style.space(10)
        height: Style.space(18)
        radius: Style.space(3)
        color: Color.accent
        Text {
          id: newLabel
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: L.tr("НОВОЕ")
          color: Color.background
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Rectangle {
        readonly property real ratio: root.active ? root.playRatio : (root.watched ? 1 : root.progressRatio)
        visible: ratio > 0 && root.cardState !== "loading"
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Style.space(3)
        width: parent.width * ratio
        color: Color.accent
        opacity: root.watched ? .7 : 1
      }

      readonly property bool actionsShown: (root.hovered || playAction.activeFocus || playlistAction.activeFocus || endAction.activeFocus)
        && root.cardState !== "loading"

      Rectangle {
        id: playAction
        objectName: "playAction"
        z: 3
        visible: root.playable && parent.actionsShown
        anchors.centerIn: parent
        width: Style.space(48)
        height: width
        radius: width / 2
        color: Color.accent
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.cardState === "playing" ? L.tr("Пауза") : L.tr("Играть сейчас")
        Keys.onReturnPressed: root.activate()
        Icon { anchors.centerIn: parent; name: root.cardState === "playing" ? "pause" : "play"; size: Style.space(22); color: Color.background }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.activate() }
      }

      Column {
        z: 3
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(6)
        spacing: Style.space(4)
        visible: thumb.actionsShown || queueMark.visible || root.saved
        Rectangle {
          id: queueMark
          objectName: "queueMark"
          readonly property int position: root.cardState === "queued" && root.logic ? root.logic.queuePosition(root.media.videoId) : 0
          readonly property bool removing: queueMouse.containsMouse || activeFocus
          visible: position > 0
          x: parent.width - width
          width: markRow.implicitWidth + Style.space(16)
          height: Style.space(28)
          radius: Style.space(4)
          color: removing ? Qt.rgba(0, 0, 0, .85) : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .92)
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: position + L.tr("-е в очереди, убрать из очереди")
          Keys.onReturnPressed: root.removeFromQueue()
          Row {
            id: markRow
            anchors.centerIn: parent
            spacing: Style.space(5)
            readonly property color tone: queueMark.removing ? "#FFFFFF" : Color.background
            Icon {
              anchors.verticalCenter: parent.verticalCenter
              name: queueMark.removing ? "x" : (queueMark.position === 1 ? "list-start" : "list-checks")
              size: Style.space(13)
              color: markRow.tone
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: queueMark.removing ? L.tr("УБРАТЬ") : (queueMark.position === 1 ? L.tr("ДАЛЕЕ") : String(queueMark.position))
              color: markRow.tone
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              font.bold: true
              font.letterSpacing: 1
            }
          }
          MouseArea {
            id: queueMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.removeFromQueue()
          }
        }
        Rectangle {
          id: endAction
          objectName: "endAction"
          x: parent.width - width
          visible: thumb.actionsShown && root.playable && root.allowEnqueue && !queueMark.visible
          width: Style.space(28)
          height: visible ? Style.space(28) : 0
          radius: Style.space(4)
          color: Qt.rgba(0, 0, 0, .75)
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: L.tr("В мою очередь")
          Keys.onReturnPressed: root.endRequested(root.media)
          Icon { anchors.centerIn: parent; name: "list-plus"; size: Style.space(14); color: "#FFFFFF" }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.endRequested(root.media) }
        }
        Rectangle {
          id: playlistAction
          objectName: "playlistAction"
          x: parent.width - width
          visible: root.playable && root.allowPlaylist && (thumb.actionsShown || root.saved)
          width: Style.space(28)
          height: visible ? Style.space(28) : 0
          radius: Style.space(4)
          color: root.saved ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .92) : Qt.rgba(0, 0, 0, .75)
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: root.saved ? L.tr("Убрать из сохранённого") : L.tr("Сохранить")
          Keys.onReturnPressed: root.toggleSaved()
          Icon { anchors.centerIn: parent; name: root.saved ? "bookmark-check" : "bookmark"; size: Style.space(14); color: root.saved ? Color.background : "#FFFFFF" }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleSaved() }
        }
      }
    }

    Column {
      id: info
      width: parent.width
      spacing: Style.space(3)
      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(root.media.title || root.media.videoId || root.item.name || root.item.id || L.tr("Без названия"))
        color: root.cardState === "playing" ? Color.accent : (root.watched ? root.dim : root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Text {
        visible: root.stateLine !== ""
        width: parent.width
        textFormat: Text.PlainText
        text: root.stateLine
        color: root.cardState === "loading" || root.cardState === "playing" ? Color.accent
          : (root.cardState === "error" ? Color.urgent : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
        elide: Text.ElideRight
      }
      Row {
        visible: root.stateLine === ""
        width: parent.width
        opacity: root.watched ? .7 : 1
        spacing: 0
        Text {
          id: authorLabel
          width: Math.min(implicitWidth, parent.width)
          textFormat: Text.PlainText
          text: L.tb(root.media.author || root.item.author || (root.playable ? L.tr("Автор неизвестен") : root.kindLabel))
          color: authorMouse.containsMouse && root.authorLinked ? Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          font.underline: authorMouse.containsMouse && root.authorLinked
          elide: Text.ElideRight
          MouseArea {
            id: authorMouse
            z: 5
            anchors.fill: parent
            enabled: root.authorLinked
            hoverEnabled: true
            cursorShape: root.authorLinked ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.channelRequested({ source: "youtube", kind: "channel", id: L.tb(root.media.authorId), title: L.tb(root.media.author || "") })
          }
        }
        Text {
          width: Math.max(0, parent.width - authorLabel.width)
          textFormat: Text.PlainText
          text: root.validCount(root.media.viewCount) ? " · " + root.formatCount(root.media.viewCount) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          elide: Text.ElideRight
        }
      }
    }
  }

  RowMenu {
    id: cardMenu
    anchorItem: root
    title: String(root.media.title || root.item.name || "")
    subtitle: root.kindLabel
    actions: root.menuModel
    foreground: root.foreground
    fontFamily: root.fontFamily
    onTriggered: action => root.triggerMenuAction(action)
  }
}
