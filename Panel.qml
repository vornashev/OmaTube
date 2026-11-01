import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "i18n.js" as L

Panel {
  id: root

  moduleName: "vornashev.omatube"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var logic: null
  property int page: 0
  property string playlistId: ""
  property var pickerMedia: null
  property var pickerAnchor: null
  property bool settingsOpen: false
  property var railPlaylists: []
  property int railRequestId: 0
  property int seenRailRevision: -1
  readonly property var preferences: logic && logic.stateData && logic.stateData.preferences
    ? logic.stateData.preferences : ({})
  readonly property string format: String(preferences.panelFormat || "wide")
  readonly property bool shelf: format === "shelf" && panel.contentWidth >= Style.space(820)
  readonly property bool wide: format !== "compact" && !shelf
    && panel.contentWidth >= Style.space(820)
  readonly property string collectionSection: collectionLoader.item ? collectionLoader.item.section : "saved"
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var youtubeAuth: logic && logic.stateData && logic.stateData.youtubeAuth
    ? logic.stateData.youtubeAuth : ({ configured: false, authenticated: false, cookieCount: 0, browser: "chromium" })
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Player outside «Сейчас»: V2 thin panel (default) or V1 bottom panel.
  readonly property string playerDock: String(preferences.playerDock || "thin")
  readonly property bool showDock: wide && page !== 0 && logic !== null && logic.hasTrack
  readonly property real dockHeight: showDock ? (playerDock === "bar" ? playerBar.implicitHeight : thinPlayer.implicitHeight) : 0
  property bool sheetOpen: false
  property string sheetTab: "chapters"
  property string lastPlayState: ""
  readonly property color surface: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
  onPageChanged: sheetOpen = false
  onShowDockChanged: if (!showDock) sheetOpen = false
  function openSheet(tab) {
    if (playerDock !== "thin") { showPage(0); return }
    if (tab !== "") sheetTab = tab
    sheetOpen = true
  }

  function open() { root.controller.show(); if (logic) logic.refresh(); refreshRail() }
  function close() { root.controller.hide() }
  function showPage(index) { settingsOpen = false; page = index }
  function openSection(section) {
    settingsOpen = false
    page = 2
    if (collectionLoader.item) collectionLoader.item.section = section
  }
  function refreshRail() {
    if (!logic) return
    railRequestId = logic.request("collection", { section: "playlists", offset: 0 })
  }
  function toggle() { if (root.opened) close(); else open() }
  function closeForPopoutSwitch() { close() }
  function openPlaylist(id, media) { playlistId = id || ""; pickerMedia = media || null; page = 3 }
  function openChannel(entity, returnPage) {
    settingsOpen = false
    page = 1
    searchPage.returnToCollection = false
    searchPage.returnPage = returnPage === undefined ? -1 : returnPage
    searchPage.openEntity(entity)
  }
  function openPicker(media, anchorItem) {
    pickerAnchor = anchorItem || null
    playlistPicker.media = media
    playlistPicker.anchorItem = pickerAnchor
    playlistPicker.open()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyScope
    padding: 0
    contentWidth: panel.fittedContentWidth(root.format === "compact" ? Style.space(420)
      : (root.format === "shelf" ? Style.space(1440) : Style.space(1100)))
    contentHeight: panel.fittedContentHeight(root.format === "compact" ? Style.space(700)
      : (root.format === "shelf" ? Style.space(236) : Style.space(660)), Style.space(900))

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: event => {
        if (event.key === Qt.Key_Tab
            && (event.modifiers & Qt.ControlModifier)) {
          if (root.bar && typeof root.bar.switchPanelFrom === "function")
            root.bar.switchPanelFrom(
              root.barIdentity,
              event.modifiers & Qt.ShiftModifier ? -1 : 1
            )
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (root.sheetOpen) root.sheetOpen = false
          else if (root.logic && root.logic.stateData.state === "loading" && root.showDock) root.logic.request("cancel_load")
          else if (root.settingsOpen) root.settingsOpen = false
          else root.close()
          event.accepted = true
        } else if (event.modifiers === Qt.NoModifier
                   && event.key >= Qt.Key_0 && event.key <= Qt.Key_6) {
          root.showPage([6, 0, 1, 2, 4, 5, 8][event.key - Qt.Key_0])
          event.accepted = true
        }
      }
      Row {
        id: shell
        anchors.fill: parent

        Rail {
          id: rail
          visible: root.wide
          width: visible ? implicitWidth : 0
          height: parent.height
          foreground: root.foreground
          fontFamily: root.fontFamily
          page: root.page
          section: root.collectionSection
          playlists: root.railPlaylists
          openPlaylistId: root.page === 3 ? root.playlistId : ""
          playingPlaylistId: root.logic && root.logic.sourceContext && root.logic.sourceContext.kind === "playlist"
            ? String(root.logic.sourceContext.id) : ""
          sourcePlace: root.logic && root.logic.sourceContext && root.logic.sourceContext.total
            ? root.logic.sourceContext.index + "/" + root.logic.sourceContext.total : ""
          playlistPlaying: root.logic !== null && root.logic.playing
          queueActive: root.logic !== null && root.logic.lane === "main"
          queueCount: root.logic ? Number(root.logic.myQueue.count || 0) : 0
          queueDuration: root.logic ? Number(root.logic.myQueue.duration || 0) : 0
          newCount: root.logic && root.logic.stateData.newCount ? Number(root.logic.stateData.newCount) : 0
          downloadsActive: root.logic && root.logic.stateData.downloadsActive ? Number(root.logic.stateData.downloadsActive) : 0
          settingsActive: root.settingsOpen
          onNavigate: index => root.showPage(index)
          onSectionRequested: section => root.openSection(section)
          onPlaylistRequested: playlistId => { root.settingsOpen = false; root.openPlaylist(playlistId, null) }
          onMyQueueRequested: {
            root.settingsOpen = false
            if (root.logic && root.logic.lane !== "main") {
              if (root.logic.myQueue.count > 0) root.logic.request("lane_switch", { lane: "main" })
              else root.logic.notify({ text: L.tr("Моя очередь пуста — добавляйте видео через «В мою очередь»"), icon: "list-video" })
            }
            root.showPage(0)
          }
          onSettingsRequested: root.settingsOpen = !root.settingsOpen
          onShrinkRequested: if (root.logic) root.logic.request("setting", { key: "panelFormat", value: "compact" })
        }

        Item {
          id: main
          width: parent.width - rail.width
          height: parent.height

          Column {
            id: content
            anchors.fill: parent
            spacing: root.wide ? Style.space(8) : Style.space(0)

            PlayerHeader {
              id: playerHeader
              visible: !root.wide && root.page === 0
              width: parent.width
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              onSettingsRequested: root.settingsOpen = true
            }

            TabStrip {
              id: tabs
              visible: !root.wide
              width: parent.width
              height: visible ? Style.space(35) : 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              labelSize: 10
              tabSpacing: 12
              leftInset: 14
              current: root.page === 3 ? 2 : root.page
              tabs: [{ label: L.tr("СЕЙЧАС"), value: 0, icon: "play" }, { label: L.tr("ПОИСК"), value: 1, icon: "search" }, { label: L.tr("МЕДИА"), value: 2, icon: "library" },
                { label: L.tr("ПОДПИСКИ"), value: 4, icon: "rss" }, { label: L.tr("ЗАГРУЗКИ"), value: 5, icon: "download" }]
              onSelected: value => root.page = value
            }

        Rectangle {
            id: errorCard
            visible: root.logic && root.logic.error !== ""
              && !(root.page === 1 && root.logic.failedOperation)
            x: root.wide ? Style.space(20) : 0
            width: parent.width - x * 2
            height: visible ? errorContent.implicitHeight + Style.space(16) : 0
            color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .08)
            border.width: Math.max(1, Style.space(1))
            border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .5)
            Row {
              id: errorContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              Text {
                width: parent.width - authError.width - retryError.width - dismissError.width - parent.spacing * 3
                textFormat: Text.PlainText
                text: root.logic ? root.logic.error : ""
                color: Color.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              Pill {
                id: authError
                visible: root.logic && (root.logic.errorCode === "auth_required" || root.logic.errorCode === "po_token_required")
                width: visible ? implicitWidth : 0
                height: Style.space(28)
                anchors.verticalCenter: parent.verticalCenter
                text: L.tr("АККАУНТ")
                icon: "settings"
                selected: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.settingsOpen = true
              }
              IconButton {
                id: retryError
                anchors.verticalCenter: parent.verticalCenter
                icon: "rotate-cw"
                iconSize: 14
                danger: true
                tooltipText: L.tr("Повторить последнее действие")
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.logic.retryLastOperation()
              }
              IconButton {
                id: dismissError
                anchors.verticalCenter: parent.verticalCenter
                icon: "x"
                iconSize: 14
                tooltipText: L.tr("Скрыть ошибку")
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.logic.dismissError()
              }
            }
          }


            StackLayout {
              x: root.wide ? 0 : Style.space(12)
              width: parent.width - x * 2
              height: Math.max(0, parent.height - y - (miniPlayer.visible ? miniPlayer.height + parent.spacing : 0) - (root.wide ? 0 : Style.space(8))
                - root.dockHeight)
              currentIndex: root.page

              NowPage {
                wide: root.wide
                logic: root.logic
                foreground: root.foreground
                fontFamily: root.fontFamily
                onPlaylistPickerRequested: (media, anchorItem) => root.openPicker(media, anchorItem)
                onChannelRequested: entity => root.openChannel(entity, 0)
                onSessionsRequested: sessionsDialog.open()
              }
              Item {
                SearchPage {
                  id: searchPage
                  anchors.fill: parent
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onPlaylistPickerRequested: media => root.openPicker(media)
                  onCollectionRequested: root.page = 2
                  onPageRequested: index => root.page = index
                }
              }
              Item {
                Loader {
                  id: collectionLoader
                  anchors.fill: parent
                  anchors.leftMargin: root.wide ? Style.space(24) : 0
                  anchors.rightMargin: root.wide ? Style.space(24) : 0
                  anchors.topMargin: root.wide ? Style.space(20) : 0
                  anchors.bottomMargin: root.wide ? Style.space(20) : 0
                  active: true
                  sourceComponent: CollectionPage {
                    logic: root.logic
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onPlaylistRequested: playlistId => root.openPlaylist(playlistId, root.pickerMedia)
                    onMediaPickerRequested: media => root.openPicker(media)
                    onDownloadsRequested: root.showPage(5)
                    onEntityRequested: entity => {
                      root.page = 1
                      searchPage.returnToCollection = true
                      searchPage.openEntity(entity)
                    }
                  }
                }
              }
              Item {
                PlaylistPage {
                  anchors.fill: parent
                  anchors.leftMargin: root.wide ? Style.space(24) : 0
                  anchors.rightMargin: root.wide ? Style.space(24) : 0
                  anchors.topMargin: root.wide ? Style.space(20) : 0
                  anchors.bottomMargin: root.wide ? Style.space(20) : 0
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  playlistId: root.playlistId
                  onSectionRequested: section => { root.playlistId = ""; root.pickerMedia = null; root.openSection(section) }
                  pendingMedia: root.pickerMedia
                  onPendingMediaChanged: root.pickerMedia = pendingMedia
                  onCloseRequested: {
                    root.page = 2
                    root.playlistId = ""
                    root.pickerMedia = null
                    if (collectionLoader.item) collectionLoader.item.load()
                  }
                }
              }
              Item {
                SubscriptionsPage {
                  anchors.fill: parent
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChannelRequested: entity => root.openChannel(entity, 4)
                }
              }
              Item {
                DownloadsPage {
                  anchors.fill: parent
                  anchors.leftMargin: root.wide ? Style.space(24) : 0
                  anchors.rightMargin: root.wide ? Style.space(24) : 0
                  anchors.topMargin: root.wide ? Style.space(20) : 0
                  anchors.bottomMargin: root.wide ? Style.space(20) : 0
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
              Item {
                HomePage {
                  anchors.fill: parent
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onNavigate: index => root.showPage(index)
                  onChannelRequested: entity => root.openChannel(entity, 6)
                  onOpenRequested: entity => root.openChannel(entity, 6)
                  onPlaylistPickerRequested: media => root.openPicker(media)
                }
              }
              Item {
                HistoryPage {
                  anchors.fill: parent
                  anchors.leftMargin: root.wide ? 0 : Style.space(0)
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
              Item {
                StatsPage {
                  anchors.fill: parent
                  logic: root.logic
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
              }
            }

            MiniPlayer {
              id: miniPlayer
              visible: !root.wide && root.page !== 0
              width: parent.width
              height: visible ? implicitHeight : 0
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              onExpandRequested: root.showPage(0)
            }
          }

          PlayerSheet {
            id: playerSheet
            z: 45
            anchors.fill: parent
            open: root.sheetOpen && root.showDock
            tab: root.sheetTab
            onTabChanged: root.sheetTab = tab
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            surface: root.surface
            onCloseRequested: root.sheetOpen = false
            onNowRequested: root.showPage(0)
          }

          ThinPlayer {
            id: thinPlayer
            z: 40
            visible: root.showDock && root.playerDock !== "bar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: implicitHeight
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            surface: root.surface
            onSheetRequested: tab => {
              if (root.sheetOpen && tab === "") root.sheetOpen = false
              else root.openSheet(tab)
            }
          }

          PlayerBar {
            id: playerBar
            z: 40
            visible: root.showDock && root.playerDock === "bar"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: implicitHeight
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            surface: root.surface
            onExpandRequested: root.showPage(0)
          }

          Toast {
            id: toast
            z: 60
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: (root.sheetOpen ? 0 : root.dockHeight)
              + (miniPlayer.visible ? miniPlayer.height : 0) + Style.space(12)
            width: Math.min(implicitWidth, parent.width - Style.space(40))
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Rectangle {
            id: shelfLayer
            visible: root.shelf
            z: 50
            anchors.fill: parent
            color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
            ShelfPanel {
              anchors.fill: parent
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              onExpandRequested: root.logic.request("setting", { key: "panelFormat", value: "wide" })
            }
          }

          Rectangle {
            id: onboardingLayer
            visible: root.logic !== null && root.preferences.onboarded === false
            z: 200
            anchors.fill: parent
            color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
            OnboardingPage {
              anchors.fill: parent
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              format: root.wide ? "wide" : "compact"
            }
          }

          Rectangle {
            id: settingsLayer
            visible: root.settingsOpen
            z: 100
            anchors.fill: parent
            color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
            MouseArea { anchors.fill: parent }
            SettingsPage {
              anchors.fill: parent
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              onCloseRequested: root.settingsOpen = false
            }
          }
        }
      }

      SessionsDialog {
        id: sessionsDialog
        logic: root.logic
        foreground: root.foreground
        fontFamily: root.fontFamily
        queueCount: root.logic && root.logic.details.queue ? root.logic.details.queue.length : 0
      }

      PlaylistPicker {
        id: playlistPicker
        logic: root.logic
        foreground: root.foreground
        fontFamily: root.fontFamily
        boundsItem: keyScope
      }

      Rectangle {
        id: slowNetwork
        visible: root.logic !== null && root.logic.stateData.netSlow === true
        z: 80
        anchors.right: busyIndicator.visible ? busyIndicator.left : parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(10)
        width: slowRow.implicitWidth + Style.space(16)
        height: Style.space(24)
        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .92)
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .2)
        Accessible.role: Accessible.StaticText
        Accessible.name: L.tr("Медленное соединение с YouTube")
        Row {
          id: slowRow
          anchors.centerIn: parent
          spacing: Style.space(6)
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "wifi-off"; size: Style.space(12); color: Color.urgent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: L.tr("медленная сеть")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
          }
        }
      }

      Item {
        id: busyIndicator
        visible: root.logic && root.logic.busy
        z: 80
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(10)
        width: Style.space(28)
        height: width
        Icon {
          anchors.centerIn: parent
          name: "loader-circle"
          size: Style.space(16)
          color: Color.accent
          RotationAnimator on rotation { running: busyIndicator.visible; from: 0; to: 360; duration: 800; loops: Animation.Infinite; onRunningChanged: if (!running) target.rotation = 0 }
        }
        MouseArea {
          id: busyMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
        PanelToolTip {
          visible: busyMouse.containsMouse
          text: root.logic ? root.logic.loaderTooltip : L.tr("Загрузка…")
          fontFamily: root.fontFamily
        }
      }
    }
  }

  Connections {
    target: root.logic
    function onStateDataChanged() {
      var playState = String(root.logic.stateData.state || "")
      if (playState === "error" && root.lastPlayState !== "error" && root.lastPlayState !== "") {
        var error = root.logic.stateData.error || ({})
        root.logic.notify({ text: L.tr("Не удалось запустить · ") + L.tb(error.message || L.tr("ошибка потока")), danger: true,
          action: L.tr("ПОВТОРИТЬ"), run: function() { root.logic.request("play") } })
      }
      root.lastPlayState = playState
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenRailRevision < 0) root.seenRailRevision = revision
      else if (revision !== root.seenRailRevision) {
        root.seenRailRevision = revision
        root.refreshRail()
      }
    }
    function onPlaylistPickerRequested(media) { root.openPicker(media) }
    function onActionSerialChanged() {
      var payload = root.logic.lastPayload || ({})
      var result = root.logic.lastResult
      if ((root.logic.lastCommand === "playlist_add" || (root.logic.lastCommand === "playlist_toggle" && result && result.present === true))
          && result && payload.media) {
        var target = root.railPlaylists.find(function(row) { return String(row.id) === String(payload.playlistId) })
        var media = payload.media
        root.logic.notify({ text: L.tr("Сохранено в «") + String(target ? target.name || target.title : L.tr("плейлист")) + "»", icon: "bookmark",
          action: L.tr("ИЗМЕНИТЬ"), run: function() { root.openPicker(media) } })
      }
      if (root.logic.lastCommand === "collection" && Number(root.logic.lastRequestId || 0) === root.railRequestId
          && root.logic.lastResult && root.logic.lastResult.items)
        root.railPlaylists = root.logic.lastResult.items
      if (root.page === 2 && root.pickerMedia && root.logic.lastCommand === "playlist_create"
          && root.logic.lastResult && root.logic.lastResult.id) {
        var createdId = root.logic.lastResult.id
        root.logic.request("playlist_add", { playlistId: createdId, media: root.pickerMedia })
        root.openPlaylist(createdId, null)
      }
    }
  }
}
