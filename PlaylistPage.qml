import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

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
          nameField.text = root.playlist.name || ""
          root.loadError = ""
        } else {
          root.loadError = root.logic.statusError || "Не удалось открыть плейлист"
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
          root.moreError = root.logic.statusError || "Не удалось загрузить следующую страницу"
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

  Column {
    anchors.fill: parent
    spacing: Style.space(7)

    Row {
      width: parent.width
      height: Style.space(48)
      spacing: Style.space(4)
      Button {
        focusable: true
        Accessible.name: tooltipText
        width: Style.space(34)
        height: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰁍"
        tooltipText: "Назад в медиатеку"
        foreground: root.foreground
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.closeRequested()
      }
      Rectangle {
        id: playlistCover
        width: Style.space(48)
        height: Style.space(48)
        radius: Style.space(4)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
        clip: true
        CatalogImage {
          anchors.fill: parent
          requestedSource: String(root.playlist.thumbnailUrl || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          emptyIcon: "󰒍"
          fillMode: Image.PreserveAspectCrop
        }
      }
      TextField {
        id: nameField
        width: parent.width - playlistCover.width - Style.space(34) * 3 - parent.spacing * 4
        height: Style.space(36)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "Название плейлиста"
        font.family: root.fontFamily
        onAccepted: saveName.clicked()
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: saveName
        width: Style.space(34)
        height: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰆓"
        tooltipText: "Сохранить название"
        foreground: Color.accent
        enabled: root.playlistId !== "" && nameField.text.trim() !== ""
        opacity: enabled ? 1 : .4
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.logic.request("playlist_rename", {
          playlistId: root.playlistId,
          name: nameField.text
        })
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        width: Style.space(34)
        height: Style.space(34)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰆴"
        tooltipText: "Удалить плейлист"
        foreground: Color.urgent
        enabled: root.playlistId !== ""
        opacity: enabled ? 1 : .4
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: confirmDelete.open()
      }
    }

    Rectangle {
      visible: root.pendingMedia !== null
      width: parent.width
      height: visible ? Style.space(48) : 0
      radius: Style.cornerRadius
      color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .1)
      border.width: Math.max(1, Style.space(1))
      border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .35)
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(9)
        anchors.rightMargin: Style.space(6)
        spacing: Style.space(6)
        Column {
          width: parent.width - addPending.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: "ДОБАВИТЬ В ПЛЕЙЛИСТ"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: .6
          }
          Text {
            width: parent.width
            text: String(root.pendingMedia ? root.pendingMedia.title || "Выбранное видео" : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        Button {
          focusable: true
          Accessible.name: tooltipText
          id: addPending
          width: Style.space(34)
          height: Style.space(34)
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰐕"
          tooltipText: "Добавить выбранное"
          foreground: Color.accent
          bordered: true
          horizontalPadding: 0
          verticalPadding: 0
          onClicked: {
            root.logic.request("playlist_add", {
              playlistId: root.playlistId,
              media: root.pendingMedia
            })
            root.pendingMedia = null
          }
        }
      }
    }

    Row {
      width: parent.width
      height: Style.space(32)
      Text {
        width: parent.width - playPlaylist.width
        anchors.verticalCenter: parent.verticalCenter
        text: "ТРЕКИ" + ((root.playlist.items || []).length > 0
          ? "  ·  " + (root.playlist.items || []).length : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: .8
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: playPlaylist
        visible: (root.playlist.items || []).length > 0
        width: visible ? Style.space(32) : 0
        height: Style.space(32)
        iconText: "󰐊"
        tooltipText: "Воспроизвести плейлист"
        foreground: Color.accent
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.logic.request("play_playlist", {
          playlistId: root.playlistId,
          entryId: null
        })
      }
    }

    Item {
      width: parent.width
      height: Math.max(0, parent.height - y)

      SkeletonList {
        visible: root.loading
        anchors.fill: parent
        rowCount: 6
        foreground: root.foreground
      }

      Column {
        visible: !root.loading && root.loadError !== ""
          && (root.playlist.items || []).length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(8)
        Text {
          width: parent.width
          text: root.loadError
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
        Button {
          focusable: true
          Accessible.name: text
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Повторить"
          iconText: "󰑐"
          foreground: Color.accent
          bordered: true
          onClicked: root.load(false)
        }
      }

      Text {
        visible: !root.loading && root.loadError === "" && (root.playlist.items || []).length === 0
        anchors.centerIn: parent
        text: "В плейлисте пока нет видео"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      ListView {
        id: playlistList
        visible: !root.loading && (root.playlist.items || []).length > 0
        anchors.fill: parent
        clip: true
        cacheBuffer: height
        boundsBehavior: Flickable.StopAtBounds
        model: root.playlist.items || []
        spacing: Style.space(2)
        delegate: MediaRow {
          onFocusRequested: playlistList.positionViewAtIndex(index, ListView.Contain)
          required property var modelData
          required property int index
          width: playlistList.width - (playlistList.contentHeight > playlistList.height ? Style.space(8) : 0)
          item: modelData
          rowNumber: index + 1
          showThumbnail: true
          allowEnqueue: false
          allowSave: false
          allowPlaylist: false
          editable: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onPlayRequested: row => root.logic.request("play_playlist", {
            playlistId: root.playlistId,
            entryId: row.entryId
          })
          onRemoveRequested: row => root.logic.request("playlist_remove", {
            playlistId: root.playlistId,
            entryId: row.entryId
          })
          onMoveUpRequested: row => root.move(row, -1)
          onMoveDownRequested: row => root.move(row, 1)
        }
        footer: Button {
          focusable: true
          Accessible.name: text
          visible: root.playlist.nextOffset !== null
            && root.playlist.nextOffset !== undefined
            || root.loadingMore || root.moreError !== ""
            || (root.loadError !== "" && (root.playlist.items || []).length > 0)
          width: playlistList.width
          height: visible ? Style.space(38) : 0
          text: root.loadingMore ? "Загружаем…"
            : (root.moreError !== "" || root.loadError !== ""
              ? "Повторить загрузку" : "Загрузить ещё")
          foreground: Color.accent
          enabled: !root.loadingMore && !root.morePending
          onClicked: {
            if (root.loadError !== "") root.load(true)
            else root.loadMore()
          }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }
    }
  }

  Dialog {
    id: confirmDelete
    title: "Удалить «" + String(root.playlist.name || "плейлист") + "»?"
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
