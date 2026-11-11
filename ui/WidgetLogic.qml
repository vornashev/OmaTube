import QtQuick
import Quickshell
import Quickshell.Io
import "i18n.js" as L

Item {
  id: root

  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omatube"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/vornashev.omatube"

  readonly property QtObject stateData: PlayerState {}
  property var details: ({ queue: [], mainQueue: [], views: ({}), operations: [], savedIds: [] })
  property var lastResult: null
  property string lastCommand: ""
  property var lastPayload: ({})
  property string runningCommand: ""
  property var runningPayload: ({})
  property string activeOperationId: ""
  property string statusError: ""
  property string bootstrapError: ""
  property string dismissedErrorKey: ""
  property var actionQueue: []
  property int actionSerial: 0
  property int requestSerial: 0
  property int runningRequestId: 0
  property int lastRequestId: 0
  property string backendSessionId: ""
  property int backendSessionSerial: 0
  property int knownQueueRevision: -1
  property int knownCatalogRevision: -1
  property int knownCollectionRevision: -1
  property var retainedOperationIds: []
  property int busySeconds: 0

  readonly property bool hasTrack: Boolean(stateData.current && stateData.current.media)
  readonly property bool playing: stateData.state === "playing"
  readonly property string currentVideoId: hasTrack ? String(stateData.current.media.videoId || "") : ""
  readonly property var playContext: stateData.context || null
  // "source" (Now playing: a playlist, page or link) or "main" (My queue, saved for later).
  readonly property string lane: String(stateData.lane || "source")
  readonly property var myQueue: stateData.lanes && stateData.lanes.main ? stateData.lanes.main : ({ count: 0, duration: null, next: null })
  // The playlist behind Now playing, also while My queue plays and it waits paused.
  readonly property var sourceContext: stateData.lanes && stateData.lanes.source ? stateData.lanes.source.context || null : null
  // Upcoming entries in play order: the rest of the active lane, then My queue while it waits.
  readonly property var upcomingRows: {
    var rows = details && details.queue ? details.queue : []
    var currentId = stateData.current ? stateData.current.entryId : ""
    var start = rows.findIndex(function(row) { return row.entryId === currentId })
    var result = rows.slice(start + 1)
    if (lane !== "main" && details && details.mainQueue) result = result.concat(details.mainQueue)
    return result
  }
  // Video id → 1-based place among the upcoming entries, for "В ОЧЕРЕДИ · 4" badges.
  readonly property var queuedPositions: {
    var result = ({})
    for (var i = 0; i < upcomingRows.length; ++i) {
      var id = String((upcomingRows[i].media || ({})).videoId || "")
      if (id !== "" && result[id] === undefined) result[id] = i + 1
    }
    return result
  }
  readonly property var queuedEntryIds: {
    var result = ({})
    for (var i = 0; i < upcomingRows.length; ++i) {
      var id = String((upcomingRows[i].media || ({})).videoId || "")
      if (id !== "" && result[id] === undefined) result[id] = String(upcomingRows[i].entryId || "")
    }
    return result
  }
  // Backend notices (a watched item left My queue, Now playing ran out) become toasts once each.
  property int seenNoticeId: -1
  onStateDataChanged: {
    var notice = stateData.notice
    if (!notice || Number(notice.id) === seenNoticeId) return
    var first = seenNoticeId < 0
    seenNoticeId = Number(notice.id)
    if (first) return
    if (notice.kind === "finished") {
      var entries = notice.entries
      notify({ text: L.tr("Досмотрено — убрано из очереди: ") + "«" + String(notice.title || L.tr("Видео")) + "»",
        icon: "check", action: L.tr("ВЕРНУТЬ"), run: function() { root.request("queue_restore", { entries: entries, lane: "main" }) } })
    } else if (notice.kind === "laneSwitched" && notice.reason === "sourceEnded") {
      notify({ text: L.tr("Плейлист закончился — продолжаем мою очередь"), icon: "list-video", action: L.tr("ОТМЕНИТЬ"),
        run: function() { root.request("lane_switch", { lane: "source", play: false }) } })
    } else if (notice.kind === "laneSwitched" && notice.reason === "queueEnded") {
      var finished = notice.entries || []
      notify({ text: L.fill(L.tr("Моя очередь закончилась — продолжаем «%1»"), [String(notice.name || L.tr("Плейлист"))]), icon: "list-video",
        action: finished.length ? L.tr("ВЕРНУТЬ") : "",
        run: function() {
          root.request("queue_restore", { entries: finished, lane: "main" })
          root.request("lane_switch", { lane: "main", play: false })
        } })
    }
  }
  signal toastRequested(var toast)
  signal playlistPickerRequested(var media)

  // "loading" | "playing" | "paused" | "error" | "queued" | "" for any media shown in a list.
  function mediaState(videoId) {
    var id = String(videoId || "")
    if (id === "") return ""
    if (id === currentVideoId) {
      var state = String(stateData.state || "")
      if (state === "loading" || state === "playing" || state === "paused" || state === "error") return state
      return ""
    }
    return queuedPositions[id] !== undefined ? "queued" : ""
  }
  readonly property var savedLookup: {
    var ids = details && details.savedIds ? details.savedIds : []
    var result = ({})
    for (var i = 0; i < ids.length; ++i) result[ids[i]] = true
    return result
  }
  function isSaved(videoId) { return savedLookup[String(videoId || "")] === true }
  function queueEntryId(videoId) { return queuedEntryIds[String(videoId || "")] || "" }
  function queuePosition(videoId) {
    var position = queuedPositions[String(videoId || "")]
    return position === undefined ? 0 : position
  }
  // toast: { text, icon, action, run: function, danger }
  function notify(toast) { toastRequested(toast) }
  readonly property string videoMode: String(stateData.videoMode || "audio")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: false
  readonly property var activeOperation: operation(activeOperationId)
  readonly property var runningOperation: latestOperation("running")
  readonly property var failedOperation: activeOperation && activeOperation.state === "failed" ? activeOperation : null
  readonly property bool busy: bootstrapProcess.running || actionProcess.running
    || stateData.state === "loading" || Boolean(stateData.buffering)
    || Boolean(activeOperation && activeOperation.state === "running")
  readonly property bool videoLoading: {
    if (Boolean(stateData.buffering) && videoMode !== "audio") return true
    if (stateData.state === "loading" && videoMode !== "audio") return true
    if (!busy) return false
    var operation = runningOperation
    if (!operation) return runningCommand === "video_quality"
      || (runningCommand === "video_mode" && String((runningPayload || ({})).value || "") !== "audio")
    if (operation.kind === "video_quality") return true
    return operation.kind === "video_mode"
      && String((operation.request || ({})).value || "") !== "audio"
  }
  readonly property string busyActivityKey: {
    if (bootstrapProcess.running) return "bootstrap"
    if (stateData.state === "loading") {
      var current = stateData.current || ({})
      var media = current.media || ({})
      return "player:" + String(current.entryId || media.videoId || "")
    }
    if (stateData.buffering) {
      var bufferingCurrent = stateData.current || ({})
      var bufferingMedia = bufferingCurrent.media || ({})
      return "buffering:" + String(bufferingCurrent.entryId || bufferingMedia.videoId || "")
    }
    if (activeOperation && activeOperation.state === "running")
      return "operation:" + String(activeOperation.operationId || activeOperation.kind || "")
    if (actionProcess.running)
      return "action:" + String(runningCommand || "") + ":" + JSON.stringify(runningPayload || ({}))
    return busy ? "refresh" : ""
  }
  readonly property string rawError: bootstrapError || statusError
    || (failedOperation && failedOperation.error ? L.tb(failedOperation.error.message) : "")
    || (stateData.error ? L.tb(stateData.error.message) : "")
  readonly property string errorCode: failedOperation && failedOperation.error ? String(failedOperation.error.code || "")
    : (stateData.error ? String(stateData.error.code || "") : "")
  readonly property string errorKey: bootstrapError !== "" ? "bootstrap:" + bootstrapError
    : (statusError !== "" ? "status:" + statusError
    : (failedOperation ? "operation:" + String(failedOperation.operationId || "")
    : (stateData.error ? "player:" + String(stateData.error.code || stateData.error.message || "") : "")))
  readonly property string error: errorKey !== "" && errorKey !== dismissedErrorKey ? rawError : ""
  // What failed, for the error toast heading; `error` above says why.
  readonly property string errorTitle: {
    if (bootstrapError !== "") return L.tr("Не удалось запустить OmaTube")
    if (statusError !== "") return L.tr("Действие не выполнено")
    var kind = failedOperation ? String(failedOperation.kind || "") : ""
    if (kind === "search" || kind === "suggestions") return L.tr("Поиск не выполнен")
    if (kind === "search_more" || kind === "entity_more") return L.tr("Не удалось загрузить страницу")
    if (kind === "open_entity") return L.tr("Не удалось открыть страницу")
    if (kind === "playlist_copy") return L.tr("Не удалось скопировать плейлист")
    if (kind === "play_url" || kind === "play_view" || kind === "play_playlist") return L.tr("Не удалось запустить воспроизведение")
    if (kind === "collection" || kind === "open_playlist") return L.tr("Не удалось загрузить медиатеку")
    if (kind === "video_mode" || kind === "video_quality") return L.tr("Не удалось переключить режим")
    if (kind === "youtube_auth_import" || kind === "youtube_auth_clear") return L.tr("Не удалось обновить вход в YouTube")
    if (failedOperation) return L.tr("Действие не выполнено")
    return stateData.error ? L.tr("Ошибка воспроизведения") : ""
  }
  readonly property string loadingMessage: {
    var kind = activeOperation && activeOperation.state === "running"
      ? String(activeOperation.kind || "") : String(runningCommand || "")
    if (bootstrapProcess.running) return L.tr("Запускаем фоновый сервис…")
    if (stateData.buffering) return videoMode === "audio"
      ? L.tr("Буферизуем аудио после перемотки…") : L.tr("Буферизуем видео после перемотки…")
    if (stateData.state === "loading") return videoMode === "audio"
      ? L.tr("Получаем аудиопоток и подключаем mpv…") : L.tr("Получаем видео и подключаем mpv…")
    if (kind === "suggestions") return L.tr("Подбираем варианты запроса…")
    if (kind === "search") return L.tr("Ищем в каталоге YouTube…")
    if (kind === "search_more" || kind === "entity_more") return L.tr("Загружаем следующую страницу…")
    if (kind === "open_entity") return L.tr("Открываем страницу каталога…")
    if (kind === "playlist_copy") return L.tr("Копируем плейлист в коллекцию…")
    if (kind === "play_url" || kind === "play_view" || kind === "play_playlist") return L.tr("Подготавливаем воспроизведение…")
    if (kind === "collection" || kind === "open_playlist") return L.tr("Загружаем медиатеку…")
    if (kind === "video_mode") return L.tr("Переключаем режим воспроизведения…")
    if (kind === "youtube_auth_import") return L.tr("Импортируем cookies YouTube из Chromium…")
    if (kind === "youtube_auth_clear") return L.tr("Удаляем cookies YouTube…")
    if (actionProcess.running) return L.tr("Выполняем действие…")
    return L.tr("Обновляем состояние…")
  }
  readonly property string loaderTooltip: L.tr("Сейчас: ") + loadingMessage
    + (busySeconds > 0 ? L.tr("\nОжидание: ") + busySeconds + L.tr(" с") : "")
    + (activeOperation && activeOperation.processed > 0 ? L.tr("\nОбработано: ") + activeOperation.processed : "")

  function operation(operationId) {
    if (!operationId) return null
    var operations = details && details.operations ? details.operations : []
    for (var i = operations.length - 1; i >= 0; --i) {
      if (String(operations[i].operationId || "") === String(operationId)) return operations[i]
    }
    return null
  }

  function latestOperation(state, kind) {
    var operations = details && details.operations ? details.operations : []
    for (var i = operations.length - 1; i >= 0; --i) {
      if ((!state || operations[i].state === state) && (!kind || operations[i].kind === kind)) return operations[i]
    }
    return null
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = root.anchorItem
    target.hostWidget = root.hostWidget
    target.logic = root
  }

  function open() {
    panelOpenPending = true
    var panel = panelLoader.ensureLoaded()
    if (panel && panelOpenPending) { panelOpenPending = false; panel.open() }
  }
  property bool panelOpenPending: false
  function close() { panelOpenPending = false; if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (opened || panelOpenPending) close(); else open() }
  function closeForPopoutSwitch() { close() }
  function trackedOperationIds() {
    var values = (retainedOperationIds || []).slice(0)
    if (activeOperationId) values.push(activeOperationId)
    var seen = ({})
    return values.filter(function(value) {
      var id = String(value || "")
      if (id === "" || seen[id]) return false
      seen[id] = true
      return true
    }).slice(0, 8)
  }

  function requiresDetails() {
    if (opened) return true
    var ids = trackedOperationIds()
    for (var i = 0; i < ids.length; ++i) {
      var record = operation(ids[i])
      if (!record || record.state === "running") return true
    }
    return false
  }

  readonly property bool wantsDetails: requiresDetails()
  property int connectionFailures: 0
  property bool subscriptionFullNeeded: false
  onWantsDetailsChanged: Qt.callLater(function() { root.refresh() })
  onRetainedOperationIdsChanged: Qt.callLater(function() { root.refresh() })

  function refresh(immediate) {
    if (!stateSocket.connected) {
      if (!bootstrapProcess.running) stateSocket.connected = true
      return
    }
    stateSocket.write(JSON.stringify({ command: "subscribe", details: wantsDetails,
      retainedOperationIds: trackedOperationIds(), full: subscriptionFullNeeded }) + "\n")
    stateSocket.flush()
    subscriptionFullNeeded = false
  }

  readonly property var parallelCommands: ["comments", "lyrics", "downloads", "feed", "subscriptions", "feed_refresh",
    "progress", "hidden_channels", "playlist_membership", "is_subscribed", "subscriptions_import", "prefetch", "home", "stats", "sessions"]

  function runParallel(entry) {
    parallelComponent.createObject(root, { entry: entry, command: [cli, "request", entry.json], running: true })
  }

  function finishParallel(entry, code, text) {
    var failedMessage = ""
    var result = null
    try {
      var envelope = JSON.parse(text || "{}")
      if (code !== 0 || !envelope.ok) failedMessage = envelope.error ? L.tb(envelope.error.message || L.tr("Действие не выполнено")) : L.tr("Действие не выполнено")
      else result = envelope.result
    } catch (error) {
      failedMessage = L.tr("Действие вернуло некорректный ответ")
    }
    lastCommand = entry.command
    lastPayload = entry.payload
    lastResult = result
    lastRequestId = entry.requestId
    if (failedMessage !== "") statusError = failedMessage
    actionSerial += 1
  }

  property var prefetched: ({})

  function request(command, payload) {
    var source = payload || ({})
    if (command === "prefetch") {
      // Hovering the same video repeatedly must not spawn a CLI process each time.
      var id = String(source.videoId || ""), now = Date.now()
      if (id === "" || (prefetched[id] && now - prefetched[id] < 600000)) return 0
      prefetched[id] = now
    }
    var body = ({})
    for (var key in source) body[key] = source[key]
    body.command = command
    requestSerial += 1
    var requestId = requestSerial
    if (parallelCommands.indexOf(command) >= 0) {
      runParallel({ requestId: requestId, command: command, payload: source, json: JSON.stringify(body) })
      return requestId
    }
    dismissedErrorKey = ""
    if (command === "suggestions") {
      actionQueue = actionQueue.filter(function(action) {
        return action.command !== "suggestions"
      })
    }
    actionQueue = actionQueue.concat([{
      requestId: requestId,
      command: command,
      payload: source,
      json: JSON.stringify(body)
    }])
    runNextAction()
    return requestId
  }

  function retryOperation(record) {
    if (record && record.kind) request(String(record.kind), record.request || ({}))
  }

  function retryLastOperation() {
    if (failedOperation) retryOperation(failedOperation)
    else if (lastCommand !== "") request(lastCommand, lastPayload || ({}))
    else refresh()
  }

  function dismissError() { dismissedErrorKey = errorKey }

  // Every action that changes something off-screen is confirmed with a toast that can undo it.
  function confirmAction(command, payload, result) {
    if (command === "enqueue_url" && result && result.entryId) {
      var entryId = String(result.entryId)
      var undo = function() { root.request("queue_remove", { entryId: entryId }) }
      if (payload.placement === "next")
        notify({ text: L.tr("Будет следующим"), icon: "list-start", action: L.tr("ОТМЕНИТЬ"), run: undo })
      else
        notify({ text: "«" + String((result.media || ({})).title || L.tr("Видео")) + L.tr("» — в мою очередь, ")
          + Number(result.position || 0) + L.tr("-м"), icon: "list-plus", action: L.tr("ОТМЕНИТЬ"), run: undo })
    } else if (command === "save_media" && payload.saved === true && payload.media) {
      var media = payload.media
      notify({ text: L.tr("Сохранено в медиатеку"), icon: "bookmark", action: L.tr("В ПЛЕЙЛИСТ"),
        run: function() { root.playlistPickerRequested(media) } })
    }
  }
  function copyLink(url, position) {
    var link = String(url || "")
    if (link === "") return
    var seconds = Math.floor(Number(position || 0))
    if (seconds > 0) link += (link.indexOf("?") >= 0 ? "&" : "?") + "t=" + seconds
    Quickshell.execDetached(["/usr/bin/wl-copy", link])
    notify({ text: seconds > 0 ? L.tr("Ссылка скопирована (с таймкодом ") + formatTime(seconds) + ")" : L.tr("Ссылка скопирована"), icon: "link" })
  }
  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    var hours = Math.floor(seconds / 3600), minutes = Math.floor(seconds % 3600 / 60), rest = seconds % 60
    return (hours > 0 ? hours + ":" + (minutes < 10 ? "0" : "") : "") + minutes + ":" + (rest < 10 ? "0" : "") + rest
  }

  function runNextAction() {
    if (actionProcess.running || actionQueue.length === 0) return
    var next = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    runningCommand = next.command
    runningPayload = next.payload || ({})
    runningRequestId = Number(next.requestId || 0)
    actionProcess.command = [cli, "request", next.json]
    actionProcess.running = true
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onAnchorItemChanged: injectPanel()
  onBusyChanged: {
    if (!busy) busySeconds = 0
  }
  onBusyActivityKeyChanged: busySeconds = 0
  Component.onCompleted: {
    bootstrapProcess.command = [pluginDir + "/bootstrap.sh"]
    bootstrapProcess.running = true
  }

  Process {
    id: bootstrapProcess
    command: []
    stderr: StdioCollector { id: bootstrapErr; waitForEnd: true }
    onExited: function(code) {
      root.bootstrapError = code === 0 ? "" : String(bootstrapErr.text || L.tr("Не удалось запустить OmaTube")).trim()
      Qt.callLater(function() { root.refresh(true) })
    }
  }

  function receiveState(text) {
    try {
      var envelope = JSON.parse(text || "{}")
      if (!envelope.ok || envelope.event !== "state")
        throw new Error(envelope.error ? L.tb(envelope.error.message) : L.tr("Ошибка backend"))
      var result = envelope.result || ({})
      var nextSessionId = String(result.backendSessionId || "")
      if (nextSessionId !== "" && backendSessionId !== "" && nextSessionId !== backendSessionId) {
        knownQueueRevision = -1
        knownCatalogRevision = -1
        knownCollectionRevision = -1
        activeOperationId = ""
        retainedOperationIds = []
        seenNoticeId = -1
        details = ({ queue: [], mainQueue: [], views: ({}), operations: [], savedIds: [] })
        backendSessionSerial += 1
      }
      if (nextSessionId !== "") backendSessionId = nextSessionId
      var meaningful = stateData.apply(result)
      var previous = details
      var hasQueue = Object.prototype.hasOwnProperty.call(result, "queue")
      var hasMainQueue = Object.prototype.hasOwnProperty.call(result, "mainQueue")
      var hasViews = Object.prototype.hasOwnProperty.call(result, "views")
      var hasOperations = Object.prototype.hasOwnProperty.call(result, "operations")
      var hasSaved = Object.prototype.hasOwnProperty.call(result, "savedIds")
      if (hasQueue || hasMainQueue || hasViews || hasOperations || hasSaved) {
        details = {
          queue: hasQueue ? result.queue : previous.queue,
          mainQueue: hasMainQueue ? result.mainQueue : previous.mainQueue,
          views: hasViews ? result.views : previous.views,
          operations: hasOperations ? result.operations : previous.operations,
          savedIds: hasSaved ? result.savedIds : previous.savedIds
        }
      }
      if (hasSaved) knownCollectionRevision = Number(stateData.collectionRevision)
      if (hasQueue) knownQueueRevision = Number(stateData.queueRevision)
      if (hasViews) knownCatalogRevision = Number(stateData.catalogRevision)
      // Compatibility for pages tracking revisions; position has its own notify signal.
      if (meaningful) root.stateDataChanged()
      statusError = ""
    } catch (error) {
      statusError = String(error.message || L.tr("Некорректный ответ OmaTube"))
    }
  }

  Socket {
    id: stateSocket
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/omatube/backend.sock"
    parser: SplitParser { onRead: data => root.receiveState(data) }
    onConnectedChanged: {
      if (connected) {
        reconnectTimer.stop()
        root.connectionFailures = 0
        root.refresh()
      } else {
        reconnectTimer.restart()
      }
    }
    onError: {
      root.statusError = L.tr("Фоновый сервис OmaTube недоступен")
      if (!reconnectTimer.running) reconnectTimer.start()
    }
  }
  Timer {
    id: reconnectTimer
    interval: Math.min(30000, 1000 * Math.pow(2, Math.min(5, root.connectionFailures)))
    onTriggered: { root.connectionFailures += 1; stateSocket.connected = true }
  }

  Component {
    id: parallelComponent
    Process {
      property var entry: ({})
      stdout: StdioCollector { id: parallelOut; waitForEnd: true }
      onExited: function(code) {
        root.finishParallel(entry, code, parallelOut.text)
        destroy()
      }
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    onExited: function(code) {
      root.lastCommand = root.runningCommand
      root.lastPayload = root.runningPayload
      root.lastResult = null
      try {
        var envelope = JSON.parse(actionOut.text || "{}")
        if (code !== 0 || !envelope.ok) {
          root.statusError = envelope.error ? L.tb(envelope.error.message || L.tr("Действие не выполнено")) : L.tr("Действие не выполнено")
        } else {
          root.lastResult = envelope.result
          if (envelope.result && envelope.result.operationId) root.activeOperationId = String(envelope.result.operationId)
          root.statusError = ""
          root.confirmAction(root.runningCommand, root.runningPayload, envelope.result)
        }
      } catch (error) {
        root.statusError = L.tr("Действие вернуло некорректный ответ")
      }
      root.lastRequestId = root.runningRequestId
      root.actionSerial += 1
      root.refresh(true)
      root.runNextAction()
    }
  }

  Timer {
    interval: 1000
    running: root.busy
    repeat: true
    onTriggered: root.busySeconds += 1
  }

  RetainedLoader {
    id: panelLoader
    objectName: "panelLoader"
    needed: root.opened || (requested && root.busy)
    unloadAfter: 10 * 60 * 1000
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      if (root.panelOpenPending) { root.panelOpenPending = false; item.open() }
      Qt.callLater(root.injectPanel)
    }
    onReleased: {
      root.details = ({ queue: [], mainQueue: [], views: ({}), operations: [], savedIds: [] })
      root.retainedOperationIds = []
      root.activeOperationId = ""
      root.subscriptionFullNeeded = true
      root.refresh()
    }
  }
}
