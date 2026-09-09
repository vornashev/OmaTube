import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string section: "saved"
  property var items: []
  property var nextOffset: null
  property var copyEntity: null
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
  property string loadRequestSection: ""
  property int loadRequestOffset: 0
  property int moreRequestOffset: 0
  property int moreGeneration: 0
  property int seenCollectionRevision: -1
  signal playlistRequested(string playlistId)
  signal mediaPickerRequested(var media)
  signal entityRequested(var entity)

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var sections: [
    { id: "saved", label: "СОХРАНЕНО" },
    { id: "playlists", label: "СПИСКИ" },
    { id: "bookmarks", label: "YOUTUBE" },
    { id: "authors", label: "АВТОРЫ" },
    { id: "history", label: "ИСТОРИЯ" }
  ]

  function load(preserveExisting) {
    if (!logic) return
    loadGeneration += 1
    latestMoreRequestId = 0
    morePending = false
    loadingMore = false
    moreError = ""
    loadPreservesItems = preserveExisting === true && items.length > 0
    if (!loadPreservesItems) {
      items = []
      nextOffset = null
    }
    loading = !loadPreservesItems
    loadError = ""
    loadRequestSection = section
    loadRequestOffset = 0
    latestLoadRequestId = logic.request("collection", {
      section: loadRequestSection,
      offset: loadRequestOffset
    })
  }

  function loadMore() {
    if (!logic || nextOffset === null || morePending || loadingMore) return
    morePending = true
    loadingMore = true
    moreError = ""
    moreGeneration = loadGeneration
    moreRequestOffset = Number(nextOffset)
    latestMoreRequestId = logic.request("collection", {
      section: section,
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

  function beginCopy(entity) {
    copyEntity = entity
    copyName.text = String(entity.title || "Плейлист") + " — копия"
    copyDialog.open()
  }

  onLogicChanged: if (logic) {
    seenCollectionRevision = Number(logic.stateData.collectionRevision || 0)
    load(false)
  }
  onSectionChanged: if (logic) load(false)
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
      if (command === "collection"
          && requestId === root.latestLoadRequestId
          && String(payload.section || "") === root.loadRequestSection
          && root.loadRequestSection === root.section
          && Number(payload.offset || 0) === root.loadRequestOffset) {
        root.loading = false
        if (result && result.items) {
          root.items = result.items
          root.nextOffset = result.nextOffset === undefined ? null : result.nextOffset
          root.loadError = ""
        } else {
          root.loadError = root.logic.statusError || "Не удалось загрузить медиатеку"
        }
        root.finishRequest()
      } else if (command === "collection"
                 && requestId === root.latestMoreRequestId
                 && String(payload.section || "") === root.section
                 && Number(payload.offset) === root.moreRequestOffset
                 && root.moreGeneration === root.loadGeneration) {
        root.morePending = false
        root.loadingMore = false
        if (result && result.items) {
          root.items = root.items.concat(result.items)
          root.nextOffset = result.nextOffset === undefined ? null : result.nextOffset
          root.moreError = ""
        } else {
          root.moreError = root.logic.statusError || "Не удалось загрузить следующую страницу"
        }
        root.finishRequest()
      } else if (result && (
          command === "playlist_create"
          || command === "history_clear"
          || command === "save_media"
          || command === "save_entity"
          || command === "playlist_delete"
          || command === "playlist_rename"
          || command === "playlist_add"
          || command === "playlist_remove"
          || command === "playlist_move")) {
        root.requestRefresh()
      }
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
      if (root.visible) root.load(false)
      else root.dirty = true
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    Flickable {
      width: parent.width
      height: Style.space(32)
      contentWidth: sectionTabs.width
      contentHeight: height
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Row {
        id: sectionTabs
        height: parent.height
        spacing: Style.space(3)
        Repeater {
          model: root.sections
          delegate: Button {
            focusable: true
            Accessible.name: text
            required property var modelData
            height: sectionTabs.height
            text: modelData.label
            foreground: root.section === modelData.id ? Color.accent : root.dim
            bordered: root.section === modelData.id
            horizontalPadding: Style.space(8)
            verticalPadding: 0
            onClicked: root.section = modelData.id
          }
        }
      }
    }

    Row {
      visible: root.section === "playlists"
      width: parent.width
      height: visible ? Style.space(34) : 0
      spacing: Style.space(4)
      TextField {
        id: playlistName
        width: parent.width - createPlaylist.width - parent.spacing
        height: parent.height
        placeholderText: "Новый локальный плейлист"
        font.family: root.fontFamily
        onAccepted: createPlaylist.clicked()
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: createPlaylist
        width: Style.space(34)
        height: parent.height
        iconText: "󰐕"
        tooltipText: "Создать плейлист"
        foreground: Color.accent
        bordered: true
        enabled: playlistName.text.trim() !== ""
        opacity: enabled ? 1 : .4
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: {
          root.logic.request("playlist_create", { name: playlistName.text })
          playlistName.clear()
        }
      }
    }

    Row {
      width: parent.width
      height: Style.space(28)
      Text {
        width: parent.width - clearHistory.width
        anchors.verticalCenter: parent.verticalCenter
        text: root.sections.filter(function(value) { return value.id === root.section })[0].label
          + (root.items.length > 0 ? "  ·  " + root.items.length : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: .8
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: clearHistory
        visible: root.section === "history" && root.items.length > 0
        width: visible ? Style.space(28) : 0
        height: Style.space(28)
        iconText: "󰆴"
        tooltipText: "Очистить историю"
        foreground: root.dim
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: clearHistoryDialog.open()
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
        visible: !root.loading && root.loadError !== "" && root.items.length === 0
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

      Column {
        visible: !root.loading && root.loadError === "" && root.items.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(6)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "󰋼"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(25)
        }
        Text {
          width: parent.width
          text: root.section === "playlists" ? "Создайте первый локальный плейлист"
            : "В этом разделе пока ничего нет"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
        }
      }

      ListView {
        id: collectionList
        visible: !root.loading && root.items.length > 0
        anchors.fill: parent
        model: root.items
        clip: true
        cacheBuffer: height
        boundsBehavior: Flickable.StopAtBounds
        spacing: Style.space(2)
        delegate: MediaRow {
          onFocusRequested: collectionList.positionViewAtIndex(index, ListView.Contain)
          required property var modelData
          required property int index
          width: collectionList.width - (collectionList.contentHeight > collectionList.height ? Style.space(8) : 0)
          item: modelData
          rowNumber: index + 1
          foreground: root.foreground
          fontFamily: root.fontFamily
          allowSave: root.section !== "playlists"
          saveTooltip: "Убрать из медиатеки"
          onPlayRequested: row => root.logic.request("play_url", { url: (row.media || row).canonicalUrl })
          onNextRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "next" })
          onEndRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
          onOpenRequested: row => {
            if (root.section === "playlists") root.playlistRequested(row.id)
            else root.entityRequested(row)
          }
          onSaveRequested: row => row.videoId
            ? root.logic.request("save_media", { media: row, saved: false })
            : root.logic.request("save_entity", { entity: row, saved: false })
          onPlaylistRequested: media => root.mediaPickerRequested(media)
          onCopyRequested: entity => root.beginCopy(entity)
        }
        footer: Button {
          focusable: true
          Accessible.name: text
          visible: root.nextOffset !== null || root.loadingMore
            || root.moreError !== "" || (root.loadError !== "" && root.items.length > 0)
          width: collectionList.width
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

  Dialog {
    id: copyDialog
    title: "Создать локальную копию"
    modal: true
    width: Style.space(360)
    standardButtons: Dialog.Ok | Dialog.Cancel
    contentItem: TextField { id: copyName; placeholderText: "Название локального плейлиста" }
    onAccepted: if (root.copyEntity)
      root.logic.request("playlist_copy", { entity: root.copyEntity, name: copyName.text })
  }

  Dialog {
    id: clearHistoryDialog
    title: "Очистить всю историю прослушивания?"
    modal: true
    width: Style.space(360)
    standardButtons: Dialog.Yes | Dialog.No
    onAccepted: root.logic.request("history_clear", ({}))
  }
}
