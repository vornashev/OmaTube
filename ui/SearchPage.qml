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
  signal playlistPickerRequested(var media)
  signal collectionRequested()
  signal pageRequested(int page)

  property string source: "youtube"
  property string filter: "all"
  property string query: ""
  property bool showEntity: false
  property real savedContentY: 0
  function saveViewState() {
    return { source: source, filter: filter, query: query, draft: field.text,
      entity: showEntity ? entityContext : null, tab: channelPage.tab, entityStack: entityStack,
      returnToCollection: returnToCollection, returnPage: returnPage }
  }
  function restoreViewState(state) {
    if (!state) return
    source = state.source || "youtube"
    filter = state.filter || "all"
    field.text = state.query || ""
    if (state.entity) openEntity(state.entity, false, state.tab)
    else if (state.query) search()
    entityStack = state.entityStack || []
    returnToCollection = state.returnToCollection === true
    returnPage = state.returnPage === undefined ? -1 : state.returnPage
    field.text = state.draft || ""
    suggestionDebounce.stop()
    suggestionsSuppressed = true
  }
  property var copyEntity: null
  property var entityContext: null
  property bool returnToCollection: false
  property var entityStack: []
  property string restoreTab: ""
  property int returnPage: -1
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
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property bool isChannel: showEntity && Boolean(entityView.entity) && entityView.entity.kind === "channel"
  // A playlist or album plays on from the chosen track (Now playing); any other single video jumps to the head of My queue.
  function playRow(row) {
    if (!logic || !row) return
    if (showEntity && entityView.entity && entityView.entity.kind === "playlist")
      logic.request("play_view", { viewId: view.viewId, entryId: row.videoId })
    else if (row.canonicalUrl)
      logic.request("play_url", { url: row.canonicalUrl, media: row, placement: "first" })
  }
  readonly property bool wideLayout: width >= Style.space(560)
  readonly property bool gridMode: wideLayout && String(((logic && logic.stateData.preferences) || ({})).searchView || "grid") !== "list"
  readonly property int gridColumns: Math.max(2, Math.floor(width / Style.space(230)))
  readonly property real cardWidth: Math.floor((resultsViewport.width - (results.contentHeight > results.height ? Style.space(8) : 0)) / gridColumns)
  readonly property var filters: source === "youtube"
    ? [{ value: "all", label: L.tr("ВСЕ") }, { value: "video", label: L.tr("ВИДЕО") },
       { value: "playlist", label: L.tr("ПЛЕЙЛИСТЫ") }, { value: "channel", label: L.tr("КАНАЛЫ") }]
    : [{ value: "all", label: L.tr("ВСЕ") }, { value: "song", label: L.tr("ТРЕКИ") },
       { value: "video", label: L.tr("ВИДЕО") }, { value: "playlist", label: L.tr("ПЛЕЙЛИСТЫ") },
       { value: "artist", label: L.tr("АРТИСТЫ") }]
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
  // Nothing searched yet: the page doubles as Home (recent queries, continue watching, new, recommended).
  readonly property bool homeMode: !showEntity && query === ""
  readonly property var recentSearches: {
    var value = ((logic && logic.stateData.preferences) || ({})).recentSearches
    return Array.isArray(value) ? value : []
  }
  readonly property bool suggestionsOpen: !suggestionsSuppressed
    && field.activeFocus
    && (suggestionPending || visibleSuggestions.length > 0)

  onVisibleSuggestionsChanged: {
    if (selectedSuggestionIndex >= visibleSuggestions.length)
      selectedSuggestionIndex = -1
  }

  function swapLayout(text) {
    var en = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"
    var ru = "йцукенгшщзхъфывапролджэячсмитьбю.ёЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё"
    var toRu = /[a-z]/i.test(text) && !/[а-яё]/i.test(text)
    var out = ""
    for (var i = 0; i < text.length; ++i) {
      var ch = text.charAt(i)
      var index = toRu ? en.indexOf(ch) : ru.indexOf(ch)
      out += index >= 0 ? (toRu ? ru : en).charAt(index) : ch
    }
    return out
  }
  readonly property string layoutFix: query !== "" ? swapLayout(query) : ""

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
  Component.onDestruction: {
    if (logic) {
      var owned = [searchOperationId, suggestionOperationId, entityOperationId, moreOperationId]
      logic.retainedOperationIds = (logic.retainedOperationIds || []).filter(function(id) { return owned.indexOf(id) < 0 })
    }
  }

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

  function focusQuery() {
    field.forceActiveFocus()
    field.selectAll()
  }

  function showHome() {
    dismissSuggestions()
    field.text = ""
    query = ""
    searchPending = false
    morePending = false
    latestSearchRequestId = 0
    latestMoreRequestId = 0
    searchOperationId = ""
    moreOperationId = ""
    searchAcknowledgementError = ""
    moreAcknowledgementError = ""
  }

  function search() {
    var nextQuery = field.text.trim()
    if (!nextQuery || !logic) return
    dismissSuggestions()
    query = nextQuery
    entityStack = []
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
    grid.contentY = 0
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

  readonly property string baseLabel: returnToCollection ? L.tr("МЕДИАТЕКА") : (returnPage === 4 ? L.tr("ПОДПИСКИ") : (returnPage === 0 ? L.tr("СЕЙЧАС") : L.tr("ПОИСК")))
  readonly property var crumbs: {
    var rows = [{ label: baseLabel, depth: -1 }]
    for (var i = 0; i < entityStack.length; ++i)
      rows.push({ label: String(entityStack[i].entity.title || L.tr("Страница каталога")), depth: i })
    return rows
  }

  // Opens an entity from inside another entity page and remembers where we came from.
  function pushEntity(entity) {
    returnToCollection = returnToCollection && showEntity
    if (showEntity && entityContext) {
      var next = entityStack.slice()
      next.push({ entity: entityContext, tab: isChannel ? channelPage.activeTab : "" })
      entityStack = next
      openEntity(entity, true, "")
    } else {
      openEntity(entity)
    }
  }

  function popTo(depth) {
    if (depth < 0) {
      entityStack = []
      closeEntity()
      return
    }
    var target = entityStack[depth]
    entityStack = entityStack.slice(0, depth)
    openEntity(target.entity, true, target.tab)
  }

  function openEntity(entity, keepStack, tab) {
    if (!logic) return
    if (keepStack !== true) entityStack = []
    restoreTab = tab || ""
    if (!showEntity) savedContentY = results.contentY
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

  function requestSection(tab, sort) {
    if (!logic || !view.viewId || morePending || loadingMore) return
    moreOperationId = ""
    moreAcknowledgementError = ""
    morePending = true
    moreRequestViewId = String(view.viewId)
    latestMoreRequestId = logic.request("entity_section", { viewId: moreRequestViewId, tab: tab, sort: sort })
  }

  function retryFailure() {
    if (!failure || !logic) return
    var kind = String(failure.kind || "")
    if (kind === "search") search()
    else if (kind === "open_entity")
      openEntity(failure.request ? failure.request.entity : entityContext, true, restoreTab)
  }

  function retryMore() {
    var code = moreFailure && moreFailure.error
      ? String(moreFailure.error.code || "") : ""
    if (code === "cursor_expired") {
      if (showEntity) openEntity(entityContext, true, restoreTab)
      else search()
    } else {
      requestMore()
    }
  }

  function closeEntity() {
    if (entityStack.length > 0) { popTo(entityStack.length - 1); return }
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
    } else if (returnPage >= 0) {
      var target = returnPage
      returnPage = -1
      pageRequested(target)
    } else {
      Qt.callLater(function() { results.contentY = savedContentY; grid.contentY = savedContentY })
    }
  }
  function chooseSuggestion(value) {
    field.text = String(value)
    field.focus = false
    search()
  }

  function beginCopy(entity) {
    copyEntity = entity
    copyName.text = String(entity.title || L.tr("Плейлист")) + L.tr(" — копия")
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
          root.searchAcknowledgementError = root.logic.statusError || L.tr("Не удалось начать поиск")
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
          root.suggestionAcknowledgementError = root.logic.statusError || L.tr("Не удалось получить подсказки")
        }
      } else if (command === "open_entity"
                 && requestId === root.latestEntityRequestId && root.showEntity) {
        root.entityPending = false
        if (result.operationId) {
          root.entityOperationId = String(result.operationId)
          root.entityAcknowledgementError = ""
        } else {
          root.entityAcknowledgementError = root.logic.statusError || L.tr("Не удалось открыть страницу")
        }
      } else if ((command === "search_more" || command === "entity_more" || command === "entity_section")
                 && requestId === root.latestMoreRequestId
                 && String(payload.viewId || "") === root.moreRequestViewId
                 && root.moreRequestViewId === String(root.view.viewId || "")) {
        root.morePending = false
        if (result.operationId) {
          root.moreOperationId = String(result.operationId)
          root.moreAcknowledgementError = ""
        } else {
          root.moreAcknowledgementError = root.logic.statusError || L.tr("Не удалось загрузить страницу")
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
        root.searchAcknowledgementError = L.tr("Сервис перезапущен; обновите выдачу")
    }
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: root.wideLayout && !root.isChannel ? Style.space(24) : 0
    anchors.rightMargin: root.wideLayout && !root.isChannel ? Style.space(24) : 0
    anchors.topMargin: root.wideLayout && !root.isChannel ? Style.space(20) : 0
    anchors.bottomMargin: root.wideLayout && !root.isChannel ? Style.space(20) : 0
    spacing: Style.space(16)

    Row {
      visible: !root.showEntity
      width: parent.width
      height: visible ? Style.space(37) : 0
      spacing: Style.space(8)

      Item {
        id: sourceButton
        objectName: "sourceButton"
        width: Style.space(76)
        height: Style.space(35)
        anchors.verticalCenter: parent.verticalCenter
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: root.source === "youtube" ? L.tr("Источник: YouTube") : L.tr("Источник: YouTube Music")
        Keys.onReturnPressed: sourceMouse.clicked(null)
        Rectangle {
          anchors.fill: parent
          color: sourceMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06) : "transparent"
          border.width: Math.max(1, Style.space(1))
          border.color: parent.activeFocus ? Color.accent : root.lineColor
        }
        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)
          Icon { anchors.verticalCenter: parent.verticalCenter; name: root.source === "youtube" ? "square-play" : "music"; size: Style.space(14); color: Color.accent }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.source === "youtube" ? "YT" : "YTM"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
          }
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "chevron-down"; size: Style.space(12); color: root.dim }
        }
        MouseArea {
          id: sourceMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.latestSuggestionRequestId = 0
            root.source = root.source === "youtube" ? "music" : "youtube"
            root.filter = "all"
            if (field.text.trim() !== "") root.search()
          }
        }
      }

      Rectangle {
        width: parent.width - sourceButton.width - parent.spacing
        height: parent.height
        color: "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: field.activeFocus ? Color.accent : root.lineColor
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)
          Icon { anchors.verticalCenter: parent.verticalCenter; name: "search"; size: Style.space(14); color: root.dim }
          TextInput {
            objectName: "searchField"
            id: field
            width: parent.width - Style.space(24) - escHint.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(13)
            clip: true
            selectByMouse: true
            Text {
              visible: field.text === ""
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: L.tr("Видео, плейлист или автор")
              color: root.dim
              font: field.font
              elide: Text.ElideRight
            }
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
          } else if (event.key === Qt.Key_Escape && !root.showEntity && (field.text !== "" || root.query !== "")) {
            root.showHome()
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
          Text {
            id: escHint
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: field.text === "" ? "" : "esc"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
          }
        }
      }
    }

    Item {
      visible: !root.showEntity
      width: parent.width
      height: visible ? Style.space(32) : 0
      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Repeater {
          model: root.filters
          delegate: Pill {
            required property var modelData
            objectName: "filter-" + modelData.value
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(27)
            text: modelData.label.charAt(0) + modelData.label.slice(1).toLowerCase()
            selected: root.filter === modelData.value
            labelSize: 11
            letterSpacing: 0
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              root.latestSuggestionRequestId = 0
              root.filter = modelData.value
              if (field.text.trim() !== "") root.search()
            }
          }
        }
      }
      Row {
        id: viewRow
        visible: root.wideLayout
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Rectangle {
          width: Style.space(32); height: Style.space(32)
          color: root.gridMode ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1) : "transparent"
          Icon { anchors.centerIn: parent; name: "layout-grid"; size: Style.space(14); color: root.gridMode ? root.foreground : root.dim }
          MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: root.logic.request("setting", { key: "searchView", value: "grid" })
          }
        }
        Rectangle {
          width: Style.space(32); height: Style.space(32)
          color: !root.gridMode ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1) : "transparent"
          Icon { anchors.centerIn: parent; name: "list"; size: Style.space(14); color: !root.gridMode ? root.foreground : root.dim }
          MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: root.logic.request("setting", { key: "searchView", value: "list" })
          }
        }
      }
    }

    Text {
      visible: !root.showEntity && root.query !== "" && root.rows.length > 0
      textFormat: Text.PlainText
      text: L.tr("РЕЗУЛЬТАТЫ · ") + root.rows.length
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.space(10)
      font.bold: true
      font.letterSpacing: 1.5
    }

    Row {
      visible: root.showEntity && !root.isChannel
      width: parent.width
      height: visible ? Style.space(32) : 0
      spacing: Style.space(6)
      IconButton {
        icon: "arrow-left"
        iconSize: 14
        tooltipText: root.entityStack.length > 0 ? L.tr("Назад: ") + String(root.entityStack[root.entityStack.length - 1].entity.title || "")
          : (root.returnToCollection ? L.tr("Назад в медиатеку") : L.tr("Назад к результатам поиска"))
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.closeEntity()
      }
      Row {
        id: crumbRow
        visible: root.entityStack.length > 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Repeater {
          model: root.entityStack.length > 0 ? root.crumbs : []
          delegate: Row {
            required property var modelData
            spacing: Style.space(6)
            Text {
              id: crumbText
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, Style.space(150))
              textFormat: Text.PlainText
              text: modelData.label
              color: crumbMouse.containsMouse ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              font.underline: crumbMouse.containsMouse
              elide: Text.ElideRight
              MouseArea {
                id: crumbMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.popTo(modelData.depth)
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "›"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
            }
          }
        }
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
        width: Math.max(0, parent.width - Style.space(38)
          - (crumbRow.visible ? crumbRow.width + parent.spacing : 0)
          - (entityCover.visible ? entityCover.width + parent.spacing : 0)
          - (entityActions.visible ? entityActions.width + parent.spacing : 0))
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String(root.entityView.entity ? root.entityView.entity.title : L.tr("Страница каталога"))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      Row {
        id: entityActions
        visible: Boolean(root.entityView.entity) && root.entityView.entity.kind === "playlist"
        spacing: Style.space(6)
        IconButton {
          objectName: "playEntityButton"
          icon: "play"
          iconSize: 14
          active: true
          enabled: root.rows.some(function(row) { return Boolean(row.videoId) })
          tooltipText: L.tr("Играть всё")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: {
            var first = root.rows.filter(function(row) { return row.videoId })[0]
            if (first) root.logic.request("play_view", { viewId: root.view.viewId, entryId: first.videoId })
          }
        }
        IconButton {
          id: copyEntityButton
          objectName: "copyEntityButton"
          visible: Boolean(root.entityView.entity)
            && root.entityView.entity.kind === "playlist"
            && root.entityView.entity.source !== "local"
          width: visible ? Style.space(32) : 0
          icon: "copy"
          iconSize: 14
          active: true
          tooltipText: L.tr("Скопировать в медиатеку")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.beginCopy(root.entityView.entity)
        }
        IconButton {
          icon: "link"
          iconSize: 14
          active: true
          enabled: Boolean(root.entityView.entity && root.entityView.entity.canonicalUrl)
          tooltipText: L.tr("Копировать ссылку")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", String(root.entityView.entity.canonicalUrl)])
        }
        IconButton {
          icon: "external-link"
          iconSize: 14
          active: true
          enabled: Boolean(root.entityView.entity && root.entityView.entity.canonicalUrl)
          tooltipText: L.tr("Открыть в браузере")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: Quickshell.execDetached(["/usr/bin/xdg-open", String(root.entityView.entity.canonicalUrl)])
        }
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
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "triangle-alert"; size: Style.space(26); color: Color.urgent }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.failure && root.failure.error
            ? L.tb(root.failure.error.message || L.tr("Каталог недоступен")) : L.tr("Каталог недоступен")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
        Pill {
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(31)
          text: L.tr("ПОВТОРИТЬ")
          icon: "rotate-cw"
          selected: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.retryFailure()
        }
      }

      Column {
        visible: !root.loading && root.failure === null && root.rows.length === 0 && !root.homeMode
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(6)
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: root.query === "" ? "search" : "search-x"; size: Style.space(26); color: root.dim }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.query === "" ? L.tr("Найдите видео, музыку или канал")
            : L.tr("По запросу «") + root.query + L.tr("» ничего не найдено")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
        Pill {
          visible: root.query !== "" && root.layoutFix !== root.query
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(31)
          text: L.tr("Искать «") + root.layoutFix + L.tr("» (другая раскладка)")
          icon: "keyboard"
          selected: true
          letterSpacing: 0
          labelSize: 11
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { field.text = root.layoutFix; root.search() }
        }
      }

      Item {
        visible: root.homeMode && !root.loading && root.failure === null
        anchors.fill: parent

        Item {
          id: recentRow
          visible: root.recentSearches.length > 0
          width: parent.width
          height: visible ? Style.space(28) : 0
          clip: true
          Row {
            anchors.left: parent.left
            anchors.right: clearRecent.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              rightPadding: Style.space(4)
              textFormat: Text.PlainText
              text: L.tr("НЕДАВНИЕ")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.bold: true
              font.letterSpacing: 1.5
            }
            Repeater {
              model: root.recentSearches
              delegate: Pill {
                required property string modelData
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(26)
                text: modelData
                labelSize: 11
                letterSpacing: 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { field.text = modelData; root.search() }
              }
            }
          }
          Text {
            id: clearRecent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tr("очистить")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.logic.request("setting", { key: "recentSearches", value: [] })
            }
          }
        }

        HomePage {
          anchors.top: recentRow.bottom
          anchors.topMargin: recentRow.visible ? Style.space(14) : 0
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          embedded: true
          logic: root.logic
          foreground: root.foreground
          fontFamily: root.fontFamily
          onNavigate: index => root.pageRequested(index)
          onChannelRequested: entity => root.openEntity(entity)
          onOpenRequested: entity => root.openEntity(entity)
          onPlaylistPickerRequested: media => root.playlistPickerRequested(media)
        }
      }

      ListView {
        id: results
        visible: !root.loading && root.failure === null && root.rows.length > 0
          && suggestionsPanel.height === 0 && !root.gridMode && !root.isChannel
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height * 2
        spacing: Style.space(2)
        model: root.rows
        onContentYChanged: if (!root.showEntity) root.savedContentY = contentY
        delegate: MediaRow {
          logic: root.logic
          onFocusRequested: results.positionViewAtIndex(index, ListView.Contain)
          required property var modelData
          required property int index
          width: results.width - (results.contentHeight > results.height ? Style.space(8) : 0)
          item: modelData
          rowNumber: index + 1
          foreground: root.foreground
          fontFamily: root.fontFamily
          onPlayRequested: row => root.playRow(row)
          onNextRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "next" })
          onEndRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
          onOpenRequested: entity => root.pushEntity(entity)
          onSaveRequested: row => root.logic.request("save_media", { media: row, saved: true })
          onPlaylistRequested: media => root.playlistPickerRequested(media)
          onChannelRequested: entity => root.pushEntity(entity)
          commandsEnabled: true
          prefetchOnHover: true
          onCommandRequested: (command, payload) => root.logic.request(command, payload)
          onCopyRequested: entity => root.beginCopy(entity)
        }
        footer: moreFooter
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      GridView {
        id: grid
        visible: !root.loading && root.failure === null && root.rows.length > 0
          && suggestionsPanel.height === 0 && root.gridMode && !root.isChannel
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height * 2
        cellWidth: root.cardWidth
        cellHeight: Math.round((root.cardWidth - Style.space(16)) * 9 / 16) + Style.space(70)
        model: root.rows
        onContentYChanged: if (!root.showEntity && visible) root.savedContentY = contentY
        delegate: Item {
          required property var modelData
          width: grid.cellWidth
          height: grid.cellHeight
          MediaCard {
            logic: root.logic
            width: parent.width - Style.space(16)
            height: parent.height - Style.space(20)
            item: modelData
            foreground: root.foreground
            fontFamily: root.fontFamily
            onPlayRequested: row => root.playRow(row)
            onEndRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
            onOpenRequested: entity => root.pushEntity(entity)
            onPlaylistRequested: media => root.playlistPickerRequested(media)
            onPrefetchRequested: videoId => root.logic.request("prefetch", { videoId: videoId })
            onChannelRequested: entity => root.pushEntity(entity)
            onCopyRequested: entity => root.beginCopy(entity)
          }
        }
        footer: moreFooter
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      ChannelPage {
        id: channelPage
        visible: !root.loading && root.failure === null && root.isChannel
        anchors.fill: parent
        logic: root.logic
        view: root.view
        foreground: root.foreground
        fontFamily: root.fontFamily
        onBackRequested: root.closeEntity()
        onPlayVideo: row => root.playRow(row)
        onEnqueueVideo: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end" })
        onPlaylistPickerRequested: media => root.playlistPickerRequested(media)
        onOpenRequested: entity => root.pushEntity(entity)
        onLoadMoreRequested: root.requestMore()
        onSectionRequested: (tab, sort) => root.requestSection(tab, sort)
        onCopyRequested: entity => root.beginCopy(entity)
        initialTab: root.restoreTab
        backLabel: root.entityStack.length > 0
          ? String(root.entityStack[root.entityStack.length - 1].entity.title || root.baseLabel).toUpperCase() : root.baseLabel
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
                textFormat: Text.PlainText
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

  Component {
    id: moreFooter
    Button {
          focusable: true
          Accessible.name: text
          visible: root.hasMore(root.view) || root.loadingMore
            || root.moreFailure !== null
          width: resultsViewport.width
          height: visible ? Style.space(38) : 0
          text: root.loadingMore ? L.tr("Загружаем…")
            : (root.moreFailure && root.moreFailure.error
               && String(root.moreFailure.error.code || "") === "cursor_expired"
              ? L.tr("Обновить выдачу")
              : (root.moreFailure ? L.tr("Повторить загрузку") : L.tr("Загрузить ещё")))
          foreground: Color.accent
          enabled: !root.loadingMore && !root.morePending
          onClicked: root.moreFailure ? root.retryMore() : root.requestMore()
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
    title: L.tr("Создать локальную копию")
    modal: true
    width: Style.space(360)
    standardButtons: Dialog.Ok | Dialog.Cancel
    contentItem: TextField { id: copyName; placeholderText: L.tr("Название локального плейлиста") }
    onAccepted: if (root.copyEntity)
      root.logic.request("playlist_copy", { entity: root.copyEntity, name: copyName.text })
  }
}
