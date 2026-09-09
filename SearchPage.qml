import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal playlistPickerRequested(var media)
  signal collectionRequested()

  property string source: "youtube"
  property string filter: "all"
  property string query: ""
  property bool showEntity: false
  property real savedContentY: 0
  property var copyEntity: null
  property var entityContext: null
  property bool returnToCollection: false
  property string searchOperationId: ""
  property string suggestionOperationId: ""
  property string entityOperationId: ""
  property string moreOperationId: ""
  property bool searchPending: false
  property bool suggestionPending: false
  property bool entityPending: false
  property int selectedSuggestionIndex: -1
  property bool morePending: false
  property int latestSearchRequestId: 0
  property int latestSuggestionRequestId: 0
  property int latestEntityRequestId: 0
  property int latestMoreRequestId: 0
  property string searchRequestSource: ""
  property string searchRequestFilter: ""
  property string searchRequestQuery: ""
  property string suggestionRequestSource: ""
  property string suggestionRequestQuery: ""
  property string moreRequestViewId: ""
  property string searchAcknowledgementError: ""
  property string suggestionAcknowledgementError: ""
  property string entityAcknowledgementError: ""
  property string moreAcknowledgementError: ""
  property bool suggestionsSuppressed: false

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property var filters: source === "youtube"
    ? [{ value: "all", label: "ВСЕ" }, { value: "video", label: "ВИДЕО" },
       { value: "playlist", label: "СПИСКИ" }, { value: "channel", label: "КАНАЛЫ" }]
    : [{ value: "all", label: "ВСЕ" }, { value: "song", label: "ТРЕКИ" },
       { value: "video", label: "ВИДЕО" }, { value: "playlist", label: "СПИСКИ" },
       { value: "artist", label: "АРТИСТЫ" }]
  readonly property var searchOperation: logic ? logic.operation(searchOperationId) : null
  readonly property var suggestionOperation: logic ? logic.operation(suggestionOperationId) : null
  readonly property var entityOperation: logic ? logic.operation(entityOperationId) : null
  readonly property var moreOperation: logic ? logic.operation(moreOperationId) : null
  readonly property var searchView: completedResult(searchOperation, "search")
  readonly property var entityView: completedResult(entityOperation, "entity")
  readonly property var moreView: completedResult(moreOperation, showEntity ? "entity" : "search")
  readonly property var view: moreView.viewId ? moreView : (showEntity ? entityView : searchView)
  readonly property var rows: flattenRows(view)
  readonly property bool loading: searchPending || entityPending
    || (showEntity ? operationRunning(entityOperation) : operationRunning(searchOperation))
  readonly property bool loadingMore: morePending || operationRunning(moreOperation)
  readonly property var moreFailure: operationFailed(moreOperation) ? moreOperation
    : (moreAcknowledgementError === "" ? null : ({
      state: "failed",
      kind: showEntity ? "entity_more" : "search_more",
      error: ({ code: "network_error", message: moreAcknowledgementError })
    }))
  readonly property var acknowledgementFailure: {
    var message = showEntity ? entityAcknowledgementError : searchAcknowledgementError
    return message === "" ? null : ({
      state: "failed",
      kind: showEntity ? "open_entity" : "search",
      error: ({ message: message })
    })
  }
  readonly property var failure: showEntity && operationFailed(entityOperation)
    ? entityOperation
    : (!showEntity && operationFailed(searchOperation)
      ? searchOperation : acknowledgementFailure)
  readonly property var suggestions: {
    if (!suggestionOperation || suggestionOperation.state !== "done") return []
    if (String(suggestionOperation.request ? suggestionOperation.request.query || "" : "") !== field.text.trim()) return []
    var result = suggestionOperation.result || ({})
    return result.items || []
  }
  readonly property var visibleSuggestions: suggestions.slice(0, 5)
  readonly property bool suggestionsOpen: !suggestionsSuppressed
    && field.activeFocus
    && (suggestionPending || visibleSuggestions.length > 0)

  onVisibleSuggestionsChanged: {
    if (selectedSuggestionIndex >= visibleSuggestions.length)
      selectedSuggestionIndex = -1
  }

  function operationRunning(operation) { return operation && operation.state === "running" }
  function operationFailed(operation) { return operation && operation.state === "failed" }

  function completedResult(operation, type) {
    if (!operation || operation.state !== "done" || !operation.result
        || !operation.result.viewId || !logic || !logic.details) {
      return ({ items: [], sections: ({}) })
    }
    var views = logic.details.views || ({})
    var completed = views[String(operation.result.viewId)] || null
    return completed && completed.type === type
      ? completed : ({ items: [], sections: ({}) })
  }

  function flattenRows(value) {
    if (value.items && value.items.length) return value.items
    var output = []
    var sections = value.sections || ({})
    Object.keys(sections).forEach(function(key) { output = output.concat(sections[key].items || []) })
    return output
  }

  function hasMore(value) {
    if (value.nextCursor) return true
    var sections = value.sections || ({})
    return Object.keys(sections).some(function(key) { return Boolean(sections[key].nextCursor) })
  }
  function moveSuggestion(direction) {
    var count = visibleSuggestions.length
    if (count === 0) return
    if (selectedSuggestionIndex < 0)
      selectedSuggestionIndex = direction > 0 ? 0 : count - 1
    else
      selectedSuggestionIndex = (selectedSuggestionIndex + direction + count) % count
  }
  function publishRetainedOperations() {
    if (!logic) return
    var values = [
      searchOperationId,
      suggestionOperationId,
      entityOperationId,
      moreOperationId
    ].filter(function(value) { return String(value || "") !== "" })
    logic.retainedOperationIds = values
  }

  onSearchOperationIdChanged: publishRetainedOperations()
  onSuggestionOperationIdChanged: publishRetainedOperations()
  onEntityOperationIdChanged: publishRetainedOperations()
  onMoreOperationIdChanged: publishRetainedOperations()
  onLogicChanged: publishRetainedOperations()

  function dismissSuggestions() {
    suggestionDebounce.stop()
    latestSuggestionRequestId = 0
    suggestionOperationId = ""
    suggestionPending = false
    suggestionAcknowledgementError = ""
    selectedSuggestionIndex = -1
    suggestionsSuppressed = true
    field.focus = false
  }

  function search() {
    var nextQuery = field.text.trim()
    if (!nextQuery || !logic) return
    dismissSuggestions()
    query = nextQuery
    returnToCollection = false
    showEntity = false
    latestEntityRequestId = 0
    latestMoreRequestId = 0
    entityPending = false
    morePending = false
    entityOperationId = ""
    searchOperationId = ""
    moreOperationId = ""
    entityAcknowledgementError = ""
    moreAcknowledgementError = ""
    searchAcknowledgementError = ""
    searchPending = true
    searchRequestSource = source
    searchRequestFilter = filter
    searchRequestQuery = query
    results.contentY = 0
    latestSearchRequestId = logic.request("search", {
      source: searchRequestSource,
      kind: searchRequestFilter,
      query: searchRequestQuery
    })
  }

  function requestSuggestions() {
    var text = field.text.trim()
    if (suggestionsSuppressed || text.length < 2 || !logic) return
    suggestionOperationId = ""
    suggestionAcknowledgementError = ""
    suggestionPending = true
    suggestionRequestSource = source
    suggestionRequestQuery = text
    latestSuggestionRequestId = logic.request("suggestions", {
      source: suggestionRequestSource,
      query: suggestionRequestQuery
    })
  }

  function openEntity(entity) {
    if (!logic) return
    savedContentY = results.contentY
    entityContext = entity
    showEntity = true
    latestSearchRequestId = 0
    searchPending = false
    latestEntityRequestId = 0
    latestMoreRequestId = 0
    entityOperationId = ""
    moreOperationId = ""
    entityAcknowledgementError = ""
    moreAcknowledgementError = ""
    entityPending = true
    morePending = false
    latestEntityRequestId = logic.request("open_entity", { entity: entity })
  }

  function requestMore() {
    if (!logic || !view.viewId || morePending || loadingMore) return
    moreOperationId = ""
    moreAcknowledgementError = ""
    morePending = true
    moreRequestViewId = String(view.viewId)
    latestMoreRequestId = logic.request(
      showEntity ? "entity_more" : "search_more",
      { viewId: moreRequestViewId }
    )
  }

  function retryFailure() {
    if (!failure || !logic) return
    var kind = String(failure.kind || "")
    if (kind === "search") search()
    else if (kind === "open_entity")
      openEntity(failure.request ? failure.request.entity : entityContext)
  }

  function retryMore() {
    var code = moreFailure && moreFailure.error
      ? String(moreFailure.error.code || "") : ""
    if (code === "cursor_expired") {
      if (showEntity) openEntity(entityContext)
      else search()
    } else {
      requestMore()
    }
  }

  function closeEntity() {
    latestEntityRequestId = 0
    latestMoreRequestId = 0
    entityPending = false
    morePending = false
    entityAcknowledgementError = ""
    moreAcknowledgementError = ""
    showEntity = false
    moreOperationId = ""
    if (returnToCollection) {
      returnToCollection = false
      collectionRequested()
    } else {
      Qt.callLater(function() { results.contentY = savedContentY })
    }
  }
  function chooseSuggestion(value) {
    field.text = String(value)
    field.focus = false
    search()
  }

  function beginCopy(entity) {
    copyEntity = entity
    copyName.text = String(entity.title || "Плейлист") + " — копия"
    copyDialog.open()
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var requestId = Number(root.logic.lastRequestId || 0)
      var command = String(root.logic.lastCommand || "")
      var result = root.logic.lastResult || ({})
      var payload = root.logic.lastPayload || ({})
      if (command === "search" && requestId === root.latestSearchRequestId
          && !root.showEntity
          && String(payload.source || "") === root.searchRequestSource
          && String(payload.kind || "") === root.searchRequestFilter
          && String(payload.query || "").trim() === root.searchRequestQuery) {
        root.searchPending = false
        if (result.operationId) {
          root.searchOperationId = String(result.operationId)
          root.searchAcknowledgementError = ""
        } else {
          root.searchAcknowledgementError = root.logic.statusError || "Не удалось начать поиск"
        }
      } else if (command === "suggestions"
                 && requestId === root.latestSuggestionRequestId
                 && !root.suggestionsSuppressed
                 && String(payload.source || "") === root.suggestionRequestSource
                 && root.suggestionRequestSource === root.source
                 && String(payload.query || "").trim() === root.suggestionRequestQuery
                 && root.suggestionRequestQuery === field.text.trim()) {
        root.suggestionPending = false
        if (result.operationId) {
          root.suggestionOperationId = String(result.operationId)
          root.suggestionAcknowledgementError = ""
        } else {
          root.suggestionAcknowledgementError = root.logic.statusError || "Не удалось получить подсказки"
        }
      } else if (command === "open_entity"
                 && requestId === root.latestEntityRequestId && root.showEntity) {
        root.entityPending = false
        if (result.operationId) {
          root.entityOperationId = String(result.operationId)
          root.entityAcknowledgementError = ""
        } else {
          root.entityAcknowledgementError = root.logic.statusError || "Не удалось открыть страницу"
        }
      } else if ((command === "search_more" || command === "entity_more")
                 && requestId === root.latestMoreRequestId
                 && String(payload.viewId || "") === root.moreRequestViewId
                 && root.moreRequestViewId === String(root.view.viewId || "")) {
        root.morePending = false
        if (result.operationId) {
          root.moreOperationId = String(result.operationId)
          root.moreAcknowledgementError = ""
        } else {
          root.moreAcknowledgementError = root.logic.statusError || "Не удалось загрузить страницу"
        }
      }
    }
    function onBackendSessionSerialChanged() {
      root.latestSearchRequestId = 0
      root.latestSuggestionRequestId = 0
      root.latestEntityRequestId = 0
      root.latestMoreRequestId = 0
      root.searchOperationId = ""
      root.suggestionOperationId = ""
      root.entityOperationId = ""
      root.moreOperationId = ""
      root.searchPending = false
      root.suggestionPending = false
      root.entityPending = false
      root.morePending = false
      root.showEntity = false
      root.entityAcknowledgementError = ""
      root.moreAcknowledgementError = ""
      if (field.text.trim() !== "")
        root.searchAcknowledgementError = "Сервис перезапущен; обновите выдачу"
    }
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    Row {
      width: parent.width
      height: Style.space(36)
      spacing: Style.space(4)
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: sourceButton
        objectName: "sourceButton"
        width: Style.space(48)
        height: parent.height
        text: root.source === "youtube" ? "YT" : "YTM"
        tooltipText: root.source === "youtube" ? "Искать в YouTube" : "Искать в YouTube Music"
        foreground: Color.accent
        bordered: true
        horizontalPadding: Style.space(4)
        verticalPadding: 0
        onClicked: {
          root.latestSuggestionRequestId = 0
          root.source = root.source === "youtube" ? "music" : "youtube"
          root.filter = "all"
          if (field.text.trim() !== "") root.search()
        }
      }
      TextField {
        objectName: "searchField"
        id: field
        width: parent.width - sourceButton.width - searchButton.width - parent.spacing * 2
        height: parent.height
        placeholderText: "Видео, плейлист или автор"
        font.family: root.fontFamily
        onAccepted: {
          if (suggestionsPanel.visible && root.selectedSuggestionIndex >= 0)
            root.chooseSuggestion(root.visibleSuggestions[root.selectedSuggestionIndex])
          else
            root.search()
        }
        Keys.onPressed: event => {
          if (event.key === Qt.Key_Escape && root.suggestionsOpen) {
            suggestionDebounce.stop()
            root.latestSuggestionRequestId = 0
            root.suggestionOperationId = ""
            root.suggestionPending = false
            root.suggestionAcknowledgementError = ""
            root.selectedSuggestionIndex = -1
            root.suggestionsSuppressed = true
            event.accepted = true
          } else if (event.key === Qt.Key_Down
                     && root.visibleSuggestions.length > 0) {
            root.moveSuggestion(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Up
                     && root.visibleSuggestions.length > 0) {
            root.moveSuggestion(-1)
            event.accepted = true
          }
        }
        onTextChanged: {
          root.suggestionsSuppressed = false
          root.selectedSuggestionIndex = -1
          suggestionDebounce.stop()
          root.latestSuggestionRequestId = 0
          root.suggestionOperationId = ""
          root.suggestionPending = false
          root.suggestionAcknowledgementError = ""
          if (text.trim().length >= 2) suggestionDebounce.restart()
        }
      }
      Button {
        focusable: true
        Accessible.name: tooltipText
        id: searchButton
        objectName: "searchButton"
        width: Style.space(36)
        height: parent.height
        iconText: "󰍉"
        iconSize: Style.font.icon
        tooltipText: "Найти"
        foreground: root.foreground
        bordered: true
        enabled: field.text.trim() !== "" && !root.searchPending
        opacity: enabled ? 1 : .4
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.search()
      }
    }

    Row {
      visible: !root.showEntity
      width: parent.width
      height: visible ? Style.space(30) : 0
      spacing: Style.space(3)
      Repeater {
        model: root.filters
        delegate: Button {
          id: filterButton
          required property var modelData
          objectName: "filter-" + modelData.value
          readonly property bool currentFilter: root.filter === modelData.value
          width: (parent.width - parent.spacing * (root.filters.length - 1))
            / root.filters.length
          height: parent.height
          text: modelData.label
          selected: currentFilter
          active: currentFilter
          focusable: true
          Accessible.name: text
          foreground: currentFilter ? root.foreground : root.dim
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(3)
          verticalPadding: 0
          onClicked: {
            root.latestSuggestionRequestId = 0
            root.filter = modelData.value
            if (field.text.trim() !== "") root.search()
          }
        }
      }
    }

    Row {
      visible: root.showEntity
      width: parent.width
      height: visible ? Style.space(32) : 0
      spacing: Style.space(6)
      Button {
        focusable: true
        Accessible.name: tooltipText
        width: Style.space(32)
        height: parent.height
        iconText: "󰁍"
        tooltipText: root.returnToCollection
          ? "Назад в медиатеку" : "Назад к результатам поиска"
        foreground: root.foreground
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.closeEntity()
      }
      Rectangle {
        id: entityCover
        visible: Boolean(root.entityView.entity && root.entityView.entity.thumbnailUrl)
        width: visible ? Style.space(32) : 0
        height: Style.space(32)
        radius: Style.space(3)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
        clip: true
        CatalogImage {
          anchors.fill: parent
          requestedSource: entityCover.visible
            ? String(root.entityView.entity.thumbnailUrl || "") : ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          emptyIcon: "󰒍"
          fillMode: Image.PreserveAspectCrop
        }
      }
      Text {
        width: parent.width - Style.space(38)
          - (entityCover.visible ? entityCover.width + parent.spacing : 0)
          - (copyEntityButton.visible ? copyEntityButton.width + parent.spacing : 0)
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.entityView.entity ? root.entityView.entity.title : "Страница каталога")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      Button {
        id: copyEntityButton
        objectName: "copyEntityButton"
        focusable: true
        Accessible.name: tooltipText
        visible: Boolean(root.entityView.entity)
          && root.entityView.entity.kind === "playlist"
          && root.entityView.entity.source !== "local"
        width: visible ? Style.space(32) : 0
        height: parent.height
        iconText: "󰆏"
        iconSize: Style.font.icon
        tooltipText: "Скопировать в медиатеку"
        foreground: Color.accent
        horizontalPadding: 0
        verticalPadding: 0
        onClicked: root.beginCopy(root.entityView.entity)
      }
    }

    Item {
      id: resultsViewport
      width: parent.width
      height: Math.max(0, parent.height - y)
      clip: true

      SkeletonList {
        visible: root.loading
        anchors.fill: parent
        rowCount: 7
        foreground: root.foreground
      }

      Column {
        visible: !root.loading && root.failure !== null
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(8)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "󰅚"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.space(25)
        }
        Text {
          width: parent.width
          text: root.failure && root.failure.error
            ? String(root.failure.error.message || "Каталог недоступен") : "Каталог недоступен"
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
          onClicked: root.retryFailure()
        }
      }

      Column {
        visible: !root.loading && root.failure === null && root.rows.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(6)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.query === "" ? "󰍉" : "󰅐"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(25)
        }
        Text {
          width: parent.width
          text: root.query === "" ? "Найдите видео, музыку или канал"
            : "По запросу «" + root.query + "» ничего не найдено"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      ListView {
        id: results
        visible: !root.loading && root.failure === null && root.rows.length > 0
          && suggestionsPanel.height === 0
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height * 2
        spacing: Style.space(2)
        model: root.rows
        onContentYChanged: if (!root.showEntity) root.savedContentY = contentY
        delegate: MediaRow {
          onFocusRequested: results.positionViewAtIndex(index, ListView.Contain)
          required property var modelData
          required property int index
          width: results.width - (results.contentHeight > results.height ? Style.space(8) : 0)
          item: modelData
          rowNumber: index + 1
          foreground: root.foreground
          fontFamily: root.fontFamily
          onPlayRequested: row => root.logic.request("play_view", { viewId: root.view.viewId, entryId: row.videoId })
          onNextRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "next" })
          onEndRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
          onOpenRequested: entity => {
            root.returnToCollection = false
            root.openEntity(entity)
          }
          onSaveRequested: row => row.videoId
            ? root.logic.request("save_media", { media: row, saved: true })
            : root.logic.request("save_entity", { entity: row, saved: true })
          onPlaylistRequested: media => root.playlistPickerRequested(media)
          onCopyRequested: entity => root.beginCopy(entity)
        }
        footer: Button {
          focusable: true
          Accessible.name: text
          visible: root.hasMore(root.view) || root.loadingMore
            || root.moreFailure !== null
          width: results.width
          height: visible ? Style.space(38) : 0
          text: root.loadingMore ? "Загружаем…"
            : (root.moreFailure && root.moreFailure.error
               && String(root.moreFailure.error.code || "") === "cursor_expired"
              ? "Обновить выдачу"
              : (root.moreFailure ? "Повторить загрузку" : "Загрузить ещё"))
          foreground: Color.accent
          enabled: !root.loadingMore && !root.morePending
          onClicked: root.moreFailure ? root.retryMore() : root.requestMore()
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      Rectangle {
        id: suggestionsPanel
        z: 20
        visible: root.suggestionsOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: visible ? Math.min(Style.space(150), suggestionColumn.implicitHeight + Style.space(6)) : 0
        radius: Style.cornerRadius
        color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        Column {
          id: suggestionColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(3)
          SkeletonList {
            visible: root.suggestionPending
            width: parent.width
            height: visible ? Style.space(96) : 0
            rowCount: 2
            foreground: root.foreground
          }
          Repeater {
            model: root.visibleSuggestions
            delegate: Rectangle {
              id: suggestionRow
              required property var modelData
              required property int index
              readonly property bool keyboardSelected: root.selectedSuggestionIndex === index
              width: suggestionColumn.width
              height: Style.space(28)
              radius: Style.cornerRadius
              color: keyboardSelected
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
                : (suggestionMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
              border.width: keyboardSelected ? Math.max(1, Style.space(1)) : 0
              border.color: keyboardSelected
                ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .45) : "transparent"
              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: String(suggestionRow.modelData)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              MouseArea {
                id: suggestionMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedSuggestionIndex = suggestionRow.index
                onClicked: root.chooseSuggestion(suggestionRow.modelData)
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: suggestionDebounce
    interval: 300
    repeat: false
    onTriggered: root.requestSuggestions()
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
}
