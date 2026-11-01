import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string playlistId: ""
  property var playlist: ({ items: [], nextOffset: null })
  property var pendingMedia: null
  property bool loading: false
  property bool loadingMore: false
  property bool morePending: false
  property bool dirty: false
  property bool loadPreservesItems: false
  property string loadError: ""
  property string moreError: ""
  property int loadGeneration: 0
  property int latestLoadRequestId: 0
  property int latestMoreRequestId: 0
  property string loadRequestPlaylistId: ""
  property int loadRequestOffset: 0
  property int moreRequestOffset: 0
  property int moreGeneration: 0
  property int seenCollectionRevision: -1
  signal closeRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)

  function load(preserveExisting) {
    if (!playlistId || !logic) return
    loadGeneration += 1
    latestMoreRequestId = 0
    morePending = false
    loadingMore = false
    moreError = ""
    loadPreservesItems = preserveExisting === true
      && (playlist.items || []).length > 0
    if (!loadPreservesItems)
      playlist = ({ items: [], nextOffset: null })
    loading = !loadPreservesItems
    loadError = ""
    loadRequestPlaylistId = playlistId
    loadRequestOffset = 0
    latestLoadRequestId = logic.request("open_playlist", {
      playlistId: loadRequestPlaylistId,
      offset: loadRequestOffset
    })
  }

  function loadMore() {
    var offset = playlist.nextOffset
    if (!logic || offset === null || offset === undefined
        || morePending || loadingMore) return
    morePending = true
    loadingMore = true
    moreError = ""
    moreGeneration = loadGeneration
    moreRequestOffset = Number(offset)
    latestMoreRequestId = logic.request("playlist_more", {
      playlistId: playlistId,
      offset: moreRequestOffset
    })
  }

  function requestRefresh() {
    if (!visible) {
      dirty = true
      return
    }
    revisionRefresh.restart()
  }

  function finishRequest() {
    if (dirty && visible && !loading && !loadingMore) {
      dirty = false
      revisionRefresh.restart()
    }
  }

  function move(row, delta) {
    var rows = playlist.items || []
    var index = rows.findIndex(function(item) { return item.entryId === row.entryId })
    var target = index + delta
    if (index < 0 || target < 0) return
    if (target >= rows.length) {
      if (delta > 0 && playlist.nextOffset !== null
          && playlist.nextOffset !== undefined) loadMore()
      return
    }
    logic.request("playlist_move", {
      playlistId: playlistId,
      entryId: row.entryId,
      beforeEntryId: delta < 0 ? rows[target].entryId
        : (target + 1 < rows.length ? rows[target + 1].entryId : null)
    })
  }

  onLogicChanged: if (logic) {
    seenCollectionRevision = Number(logic.stateData.collectionRevision || 0)
    load(false)
  }
  onPlaylistIdChanged: {
    latestLoadRequestId = 0
    latestMoreRequestId = 0
    if (playlistId) load(false)
    else playlist = ({ items: [], nextOffset: null })
  }
  onVisibleChanged: if (visible && dirty) {
    dirty = false
    revisionRefresh.restart()
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var command = String(root.logic.lastCommand || "")
      var result = root.logic.lastResult
      var payload = root.logic.lastPayload || ({})
      var requestId = Number(root.logic.lastRequestId || 0)
      if (command === "open_playlist"
          && requestId === root.latestLoadRequestId
          && String(payload.playlistId || "") === root.loadRequestPlaylistId
          && root.loadRequestPlaylistId === root.playlistId
          && Number(payload.offset || 0) === root.loadRequestOffset) {
        root.loading = false
        if (result && result.id && result.items) {
          root.playlist = result
          root.loadError = ""
        } else {
          root.loadError = root.logic.statusError || L.tr("Не удалось открыть плейлист")
        }
        root.finishRequest()
      } else if (command === "playlist_more"
                 && requestId === root.latestMoreRequestId
                 && String(payload.playlistId || "") === root.playlistId
                 && Number(payload.offset) === root.moreRequestOffset
                 && root.moreGeneration === root.loadGeneration) {
        root.morePending = false
        root.loadingMore = false
        if (result && result.items) {
          var merged = ({})
          for (var key in root.playlist) merged[key] = root.playlist[key]
          merged.items = (root.playlist.items || []).concat(result.items)
          merged.nextOffset = result.nextOffset === undefined ? null : result.nextOffset
          root.playlist = merged
          root.moreError = ""
        } else {
          root.moreError = root.logic.statusError || L.tr("Не удалось загрузить следующую страницу")
        }
        root.finishRequest()
      } else if (["playlist_rename", "playlist_add", "playlist_remove", "playlist_move"].indexOf(command) >= 0
                 && String(payload.playlistId || "") === root.playlistId && result) {
        root.requestRefresh()
      }
      if (command === "playlist_delete" && result
          && String(payload.playlistId || "") === root.playlistId)
        root.closeRequested()
    }
    function onStateDataChanged() {
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenCollectionRevision < 0) {
        root.seenCollectionRevision = revision
      } else if (revision !== root.seenCollectionRevision) {
        root.seenCollectionRevision = revision
        root.requestRefresh()
      }
    }
    function onBackendSessionSerialChanged() {
      if (root.visible && root.playlistId) root.load(false)
      else root.dirty = true
    }
  }

  signal sectionRequested(string section)

  readonly property var rowsData: playlist.items || []
  readonly property string totalDuration: {
    var seconds = 0
    rowsData.forEach(function(row) { seconds += Number((row.media || row).duration || 0) })
    if (seconds <= 0) return ""
    var hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60)
    return hours > 0 ? hours + L.tr(" ч ") + minutes + L.tr(" мин") : minutes + L.tr(" мин")
  }
  readonly property var covers: rowsData.slice(0, 4).map(function(row) {
    var media = row.media || row
    return String(media.thumbnailUrl || (media.videoId ? "https://i.ytimg.com/vi/" + encodeURIComponent(media.videoId) + "/hqdefault.jpg" : ""))
  }).filter(function(url) { return url !== "" })
  property bool renaming: false

  // What the player is doing relative to this list.
  readonly property var playerState: logic ? logic.stateData : ({})
  readonly property var context: logic ? logic.playContext : null
  readonly property bool isPlayingList: context !== null && context.kind === "playlist" && String(context.id) === playlistId
  readonly property string playState: String(playerState.state || "idle")
  readonly property int itemCount: Number(playlist.itemCount || rowsData.length)
  readonly property int currentRow: {
    if (!isPlayingList || !logic) return -1
    var videoId = logic.currentVideoId
    var guess = Number(context.index || 0) - 1
    if (guess >= 0 && guess < rowsData.length && String((rowsData[guess].media || rowsData[guess]).videoId) === videoId) return guess
    return rowsData.findIndex(function(row) { return String((row.media || row).videoId) === videoId })
  }
  // Set by the header buttons: until the first frame the list is "starting", a row click is "switching".
  property bool launching: false
  readonly property bool starting: launching && logic !== null && ((logic.runningCommand === "play_playlist"
      && String((logic.runningPayload || ({})).playlistId || "") === playlistId)
    || logic.actionQueue.some(function(action) { return action.command === "play_playlist" && String(action.payload.playlistId || "") === playlistId })
    || (isPlayingList && playState === "loading"))
  onPlayStateChanged: if (playState !== "loading") launching = false
  readonly property string listState: {
    if (starting) return "starting"
    if (isPlayingList && playState === "loading") return "switching"
    if (isPlayingList && playState === "playing") return "playing"
    if (isPlayingList && (playState === "paused" || playState === "error")) return "paused"
    if (logic && logic.hasTrack && playState !== "idle") return "other"
    if (playlist.resume && Number(playlist.resume.index) > 0) return "resume"
    return "idle"
  }
  readonly property var origin: playlist.origin ? (playlist.origin.entity || playlist.origin) : null
  readonly property string positionText: logic ? logic.formatTime(playerState.position || 0) : "0:00"

  function relativeDay(seconds) {
    var value = Number(seconds || 0)
    if (!(value > 0)) return ""
    var then = new Date(value * 1000), now = new Date()
    var days = Math.round((new Date(now.getFullYear(), now.getMonth(), now.getDate())
      - new Date(then.getFullYear(), then.getMonth(), then.getDate())) / 86400000)
    if (days <= 0) return L.tr("сегодня")
    if (days === 1) return L.tr("вчера")
    if (days < 7) return days + L.tr(" дн. назад")
    return then.toLocaleDateString(Qt.locale("ru_RU"), "d MMMM")
  }
  function playFromStart() {
    launching = true
    logic.request("play_playlist", { playlistId: playlistId, entryId: null })
  }
  function enqueueAll() {
    rowsData.forEach(function(row) {
      var media = row.media || row
      if (media.canonicalUrl) logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
    })
  }

  readonly property bool compact: width < Style.space(600)

  Column {
    anchors.fill: parent
    spacing: Style.space(root.compact ? 10 : 18)

    TabStrip {
      width: parent.width
      labelSize: root.compact ? 10 : 11
      tabSpacing: root.compact ? 14 : 24
      leftInset: root.compact ? 2 : 12
      foreground: root.foreground
      fontFamily: root.fontFamily
      current: "playlists"
      tabs: [{ label: L.tr("СОХРАНЕНО"), value: "saved" }, { label: L.tr("ПЛЕЙЛИСТЫ"), value: "playlists" },
             { label: "YOUTUBE", value: "bookmarks" }, { label: L.tr("АВТОРЫ"), value: "authors" }, { label: L.tr("ИСТОРИЯ"), value: "history" }]
      onSelected: value => root.sectionRequested(value)
    }

    Row {
      width: parent.width
      spacing: Style.space(root.compact ? 12 : 20)

      Item {
        id: mosaic
        width: Style.space(root.compact ? 112 : 224)
        height: Style.space(root.compact ? 63 : 126)
        Rectangle { anchors.fill: parent; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06) }
        Grid {
          anchors.fill: parent
          columns: 2
          spacing: Style.space(2)
          visible: root.covers.length >= 4
          Repeater {
            model: root.covers.length >= 4 ? root.covers : []
            delegate: Item {
              required property string modelData
              width: (mosaic.width - Style.space(2)) / 2
              height: (mosaic.height - Style.space(2)) / 2
              clip: true
              CatalogImage {
                anchors.fill: parent
                requestedSource: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                fillMode: Image.PreserveAspectCrop
              }
            }
          }
        }
        CatalogImage {
          anchors.fill: parent
          visible: root.covers.length < 4
          requestedSource: root.covers.length > 0 ? root.covers[0] : String(root.playlist.thumbnailUrl || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          emptyIcon: "󰒍"
          fillMode: Image.PreserveAspectCrop
        }
      }

      Column {
        width: parent.width - mosaic.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Text {
          text: (root.playlist.origin ? L.tr("ПЛЕЙЛИСТ YOUTUBE") : L.tr("ЛОКАЛЬНЫЙ ПЛЕЙЛИСТ"))
            + (root.listState === "playing" || root.listState === "switching" ? L.tr("  ·  ИГРАЕТ")
              : (root.listState === "paused" ? L.tr("  ·  НА ПАУЗЕ") : ""))
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          font.bold: true
          font.letterSpacing: 1.5
        }

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            visible: !root.renaming
            width: Math.min(implicitWidth, parent.width - renameButton.width - parent.spacing)
            textFormat: Text.PlainText
            text: L.tb(root.playlist.name || L.tr("Плейлист"))
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(22)
            font.bold: true
            elide: Text.ElideRight
          }
          Rectangle {
            visible: root.renaming
            width: parent.width - renameButton.width - parent.spacing
            height: Style.space(32)
            color: "transparent"
            border.width: Math.max(1, Style.space(1))
            border.color: Color.accent
            TextInput {
              id: nameField
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              verticalAlignment: TextInput.AlignVCenter
              color: root.foreground
              selectionColor: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.space(16)
              clip: true
              selectByMouse: true
              onAccepted: {
                if (text.trim() !== "") root.logic.request("playlist_rename", { playlistId: root.playlistId, name: text })
                root.renaming = false
              }
              Keys.onEscapePressed: root.renaming = false
            }
          }
          IconButton {
            id: renameButton
            anchors.verticalCenter: parent.verticalCenter
            icon: root.renaming ? "check" : "pencil"
            iconSize: 14
            tooltipText: root.renaming ? L.tr("Сохранить название") : L.tr("Переименовать")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (root.renaming) nameField.accepted()
              else { nameField.text = String(root.playlist.name || ""); root.renaming = true; nameField.forceActiveFocus() }
            }
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: [root.origin && root.origin.author ? L.tb(root.origin.author) : "",
            root.itemCount + L.tr(" видео"), root.totalDuration,
            root.relativeDay(root.playlist.updated_at) !== "" ? L.tr("обновлён ") + root.relativeDay(root.playlist.updated_at) : ""]
            .filter(function(part) { return part !== "" }).join("  ·  ")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }

        Flow {
          width: parent.width
          topPadding: Style.space(root.compact ? 4 : 10)
          spacing: Style.space(8)
          readonly property bool hasItems: root.rowsData.length > 0
          Pill {
            objectName: "playPlaylist"
            height: Style.space(31)
            readonly property var look: ({
              idle: { text: L.tr("ИГРАТЬ"), icon: "play" }, other: { text: L.tr("ИГРАТЬ"), icon: "play" },
              resume: { text: L.tr("С ") + (Number(root.playlist.resume ? root.playlist.resume.index : 0) + 1) + L.tr("-ГО ТРЕКА"), icon: "history" },
              starting: { text: L.tr("ЗАПУСК…"), icon: "loader-circle" },
              playing: { text: L.tr("ПАУЗА"), icon: "pause" }, switching: { text: L.tr("ПАУЗА"), icon: "pause" },
              paused: { text: L.tr("ПРОДОЛЖИТЬ"), icon: "play" }
            })[root.listState]
            text: look.text
            icon: look.icon
            spinning: root.listState === "starting"
            filled: root.listState !== "paused"
            selected: root.listState === "paused"
            bold: true
            labelSize: 11
            enabled: parent.hasItems
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              var state = root.listState
              if (state === "starting") return
              if (state === "playing" || state === "switching" || state === "paused") root.logic.request("toggle_pause")
              else if (state === "resume") {
                root.launching = true
                root.logic.request("play_playlist", { playlistId: root.playlistId, entryId: null, resume: true })
              }
              else root.playFromStart()
            }
          }
          Pill {
            objectName: "secondaryPlaylistAction"
            height: Style.space(31)
            readonly property var look: ({
              idle: { text: "", icon: "shuffle", tip: L.tr("Перемешать") },
              resume: { text: "", icon: "play", tip: L.tr("Играть с начала") },
              starting: { text: "", icon: "x", tip: L.tr("Отменить запуск") },
              playing: { text: L.tr("ДАЛЕЕ"), icon: "skip-forward", tip: "" },
              switching: { text: L.tr("ДАЛЕЕ"), icon: "skip-forward", tip: "" },
              paused: { text: L.tr("С НАЧАЛА"), icon: "rotate-ccw", tip: "" },
              other: { text: L.tr("В ОЧЕРЕДЬ"), icon: "list-plus", tip: "" }
            })[root.listState]
            width: look.text === "" ? height + Style.space(10) : implicitWidth
            text: look.text
            icon: look.icon
            tooltipText: look.tip
            bold: true
            labelSize: 11
            enabled: parent.hasItems
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              var state = root.listState
              if (state === "idle") {
                root.logic.request("shuffle", { value: true })
                root.playFromStart()
              } else if (state === "resume" || state === "paused") root.playFromStart()
              else if (state === "starting") root.logic.request("cancel_load")
              else if (state === "playing" || state === "switching") root.logic.request("next")
              else root.enqueueAll()
            }
          }
          Pill {
            objectName: "enqueuePlaylist"
            visible: ["playing", "switching", "paused"].indexOf(root.listState) >= 0
            height: Style.space(31)
            text: L.tr("В ОЧЕРЕДЬ")
            icon: "list-plus"
            bold: true
            labelSize: 11
            enabled: parent.hasItems
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.enqueueAll()
          }
          IconButton {
            visible: root.origin !== null && Boolean(root.origin.canonicalUrl)
            icon: "copy"
            iconSize: 15
            tooltipText: L.tr("Скопировать ссылку на плейлист")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.logic.copyLink(root.origin.canonicalUrl, 0)
          }
          IconButton {
            visible: root.origin !== null && Boolean(root.origin.canonicalUrl)
            icon: "external-link"
            iconSize: 15
            tooltipText: L.tr("Открыть на YouTube")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: Quickshell.execDetached(["xdg-open", String(root.origin.canonicalUrl)])
          }
          IconButton {
            icon: "trash-2"
            iconSize: 14
            danger: true
            tooltipText: L.tr("Удалить плейлист")
            enabled: root.playlistId !== ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: confirmDelete.open()
          }
        }

        Row {
          // One line that says what the main button will do / what the list is doing right now.
          visible: root.listState !== "idle"
          width: parent.width
          spacing: Style.space(7)
          readonly property bool accent: ["starting", "playing", "switching"].indexOf(root.listState) >= 0
          readonly property var currentMedia: root.currentRow >= 0 ? (root.rowsData[root.currentRow].media || root.rowsData[root.currentRow])
            : (root.playerState.current ? root.playerState.current.media : ({}))
          readonly property string place: root.context ? Number(root.context.index || 0) + L.tr(" из ") + Number(root.context.total || root.itemCount) : ""
          Equalizer {
            visible: root.listState === "playing"
            anchors.verticalCenter: parent.verticalCenter
            maxHeight: Style.space(11)
          }
          Icon {
            visible: root.listState === "starting" || root.listState === "switching"
            anchors.verticalCenter: parent.verticalCenter
            name: "loader-circle"
            size: Style.space(12)
            color: Color.accent
            RotationAnimator on rotation { running: parent.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite; onRunningChanged: if (!running) target.rotation = 0 }
          }
          Text {
            width: Math.min(implicitWidth, parent.width - Style.space(20))
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: {
              var title = String(parent.currentMedia.title || "")
              var total = root.logic ? root.logic.formatTime(root.playerState.duration || parent.currentMedia.duration || 0) : ""
              var resume = root.playlist.resume || ({})
              switch (root.listState) {
              case "starting": return L.tr("готовим очередь  ·  ") + root.itemCount + L.tr(" видео")
              case "playing": return [L.tr("играет"), parent.place, title, root.positionText + " / " + total].join("  ·  ")
              case "switching": return [L.tr("переключаемся"), parent.place, title].join("  ·  ")
              case "paused": return [L.tr("на паузе"), parent.place, root.positionText].join("  ·  ")
              case "other": return L.tr("заменит текущую очередь (") + String(root.context && root.context.name ? root.context.name
                : (root.playerState.current ? root.playerState.current.media.title || L.tr("очередь") : L.tr("очередь"))) + ")"
              case "resume": return L.tr("вы остановились ") + root.relativeDay(resume.updatedAt) + "  ·  "
                + (Number(resume.index) + 1) + L.tr(" из ") + root.itemCount
              }
              return ""
            }
            color: parent.accent ? Color.accent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
        }
      }
    }

    Rectangle {
      visible: root.pendingMedia !== null
      width: parent.width
      height: visible ? Style.space(48) : 0
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .1)
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .35)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(8)
        spacing: Style.space(8)
        Column {
          width: parent.width - addPending.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          Text { width: parent.width; text: L.tr("ДОБАВИТЬ В ПЛЕЙЛИСТ"); color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.space(10); font.bold: true; font.letterSpacing: 1 }
          Text { width: parent.width; text: String(root.pendingMedia ? root.pendingMedia.title || L.tr("Выбранное видео") : ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(11); elide: Text.ElideRight }
        }
        Pill {
          id: addPending
          anchors.verticalCenter: parent.verticalCenter
          text: L.tr("ДОБАВИТЬ")
          icon: "plus"
          selected: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: {
            root.logic.request("playlist_add", { playlistId: root.playlistId, media: root.pendingMedia })
            root.pendingMedia = null
          }
        }
      }
    }

    Column {
      width: parent.width
      height: Math.max(0, parent.height - y)
      spacing: 0

      Item {
        width: parent.width
        height: Style.space(30)
        Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1) }
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(12)
          Text { width: Style.space(18); anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; text: "#"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); font.letterSpacing: 1 }
          Text { width: parent.width - Style.space(18) - Style.space(root.compact ? 56 : 196) - parent.spacing * (root.compact ? 2 : 4); anchors.verticalCenter: parent.verticalCenter; text: L.tr("НАЗВАНИЕ"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); font.letterSpacing: 1 }
          Text { visible: !root.compact; width: visible ? Style.space(80) : 0; anchors.verticalCenter: parent.verticalCenter; text: L.tr("ПРОСМ."); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); font.letterSpacing: 1 }
          Text { visible: !root.compact; width: visible ? Style.space(60) : 0; anchors.verticalCenter: parent.verticalCenter; text: "♥"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
          Text { width: Style.space(56); anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: L.tr("ВРЕМЯ"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); font.letterSpacing: 1 }
        }
      }

      Item {
        width: parent.width
        height: Math.max(0, parent.height - Style.space(30))

        SkeletonList {
          visible: root.loading
          anchors.fill: parent
          rowCount: 6
          foreground: root.foreground
        }

        Column {
          visible: !root.loading && root.loadError !== "" && root.rowsData.length === 0
          anchors.centerIn: parent
          width: parent.width - Style.space(32)
          spacing: Style.space(8)
          Text { width: parent.width; text: root.loadError; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
          Pill {
            anchors.horizontalCenter: parent.horizontalCenter
            text: L.tr("ПОВТОРИТЬ")
            icon: "rotate-cw"
            selected: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.load(false)
          }
        }

        Text {
          visible: !root.loading && root.loadError === "" && root.rowsData.length === 0
          anchors.centerIn: parent
          text: L.tr("В плейлисте пока нет видео")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }

        ListView {
          id: playlistList
          visible: !root.loading && root.rowsData.length > 0
          anchors.fill: parent
          clip: true
          cacheBuffer: height
          boundsBehavior: Flickable.StopAtBounds
          model: root.rowsData
          delegate: PlaylistTableRow {
            compact: root.compact
            required property var modelData
            required property int index
            width: playlistList.width - (playlistList.contentHeight > playlistList.height ? Style.space(8) : 0)
            item: modelData
            rowNumber: index + 1
            rowState: index === root.currentRow
              ? (["loading", "playing", "paused", "error"].indexOf(root.playState) >= 0 ? root.playState : "paused")
              : (root.isPlayingList && root.currentRow >= 0 && index < root.currentRow ? "played" : "")
            positionText: root.positionText
            foreground: root.foreground
            fontFamily: root.fontFamily
            onPlayRequested: row => root.logic.request("play_playlist", { playlistId: root.playlistId, entryId: row.entryId })
            onToggleRequested: root.logic.request("toggle_pause")
            onCancelRequested: root.logic.request("cancel_load")
            onEnqueueRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
            onSaveRequested: media => root.logic.request("save_media", { media: media, saved: true })
            onRemoveRequested: row => root.logic.request("playlist_remove", { playlistId: root.playlistId, entryId: row.entryId })
            onMoveUpRequested: row => root.move(row, -1)
            onMoveDownRequested: row => root.move(row, 1)
          }
          footer: Item {
            width: playlistList.width
            height: visible ? Style.space(44) : 0
            visible: root.playlist.nextOffset !== null && root.playlist.nextOffset !== undefined
              || root.loadingMore || root.moreError !== ""
              || (root.loadError !== "" && root.rowsData.length > 0)
            Pill {
              anchors.centerIn: parent
              text: root.loadingMore ? L.tr("ЗАГРУЖАЕМ…") : (root.moreError !== "" || root.loadError !== "" ? L.tr("ПОВТОРИТЬ ЗАГРУЗКУ") : L.tr("ЗАГРУЗИТЬ ЕЩЁ"))
              enabled: !root.loadingMore && !root.morePending
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: { if (root.loadError !== "") root.load(true); else root.loadMore() }
            }
          }
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        }
      }
    }
  }

  Dialog {
    id: confirmDelete
    title: L.tr("Удалить «") + L.tb(root.playlist.name || L.tr("плейлист")) + "»?"
    modal: true
    width: Style.space(360)
    standardButtons: Dialog.Yes | Dialog.No
    onAccepted: root.logic.request("playlist_delete", { playlistId: root.playlistId })
  }

  Timer {
    id: revisionRefresh
    interval: 0
    repeat: false
    onTriggered: {
      if (!root.visible) {
        root.dirty = true
      } else if (root.loading || root.loadingMore) {
        root.dirty = true
      } else {
        root.dirty = false
        root.load(true)
      }
    }
  }
}
