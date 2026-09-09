import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var bar: null
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omatube"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/vornashev.omatube"

  property var stateData: ({ state: "idle", current: null, position: 0, duration: null, videoMode: "audio", buffering: false, youtubeAuth: ({ configured: false, authenticated: false, cookieCount: 0, browser: "chromium" }), preferences: ({ videoQuality: 1080 }) })
  property var details: ({ queue: [], views: ({}), operations: [] })
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
  property var retainedOperationIds: []
  property bool refreshPending: false
  property string statusRequestCommand: ""
  property int busySeconds: 0

  readonly property bool hasTrack: Boolean(stateData.current && stateData.current.media)
  readonly property bool playing: stateData.state === "playing"
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
    || (failedOperation && failedOperation.error ? String(failedOperation.error.message || "") : "")
    || (stateData.error ? String(stateData.error.message || "") : "")
  readonly property string errorKey: bootstrapError !== "" ? "bootstrap:" + bootstrapError
    : (statusError !== "" ? "status:" + statusError
    : (failedOperation ? "operation:" + String(failedOperation.operationId || "")
    : (stateData.error ? "player:" + String(stateData.error.code || stateData.error.message || "") : "")))
  readonly property string error: errorKey !== "" && errorKey !== dismissedErrorKey ? rawError : ""
  readonly property string loadingMessage: {
    var kind = activeOperation && activeOperation.state === "running"
      ? String(activeOperation.kind || "") : String(runningCommand || "")
    if (bootstrapProcess.running) return "Запускаем фоновый сервис…"
    if (stateData.buffering) return videoMode === "audio"
      ? "Буферизуем аудио после перемотки…" : "Буферизуем видео после перемотки…"
    if (stateData.state === "loading") return videoMode === "audio"
      ? "Получаем аудиопоток и подключаем mpv…" : "Получаем видео и подключаем mpv…"
    if (kind === "suggestions") return "Подбираем варианты запроса…"
    if (kind === "search") return "Ищем в каталоге YouTube…"
    if (kind === "search_more" || kind === "entity_more") return "Загружаем следующую страницу…"
    if (kind === "open_entity") return "Открываем страницу каталога…"
    if (kind === "playlist_copy") return "Копируем плейлист в коллекцию…"
    if (kind === "play_url" || kind === "play_view" || kind === "play_playlist") return "Подготавливаем воспроизведение…"
    if (kind === "collection" || kind === "open_playlist") return "Загружаем медиатеку…"
    if (kind === "video_mode") return "Переключаем режим воспроизведения…"
    if (kind === "youtube_auth_import") return "Импортируем cookies YouTube из Chromium…"
    if (kind === "youtube_auth_clear") return "Удаляем cookies YouTube…"
    if (actionProcess.running) return "Выполняем действие…"
    return "Обновляем состояние…"
  }
  readonly property string loaderTooltip: "Сейчас: " + loadingMessage
    + (busySeconds > 0 ? "\nОжидание: " + busySeconds + " с" : "")
    + (activeOperation && activeOperation.processed > 0 ? "\nОбработано: " + activeOperation.processed : "")

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

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
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

  function refresh(immediate) {
    var urgent = immediate !== false
    if (statusProcess.running) {
      if (urgent) refreshPending = true
      return
    }
    var useDetails = requiresDetails()
    statusRequestCommand = useDetails ? "details" : "status"
    if (useDetails) {
      var request = {
        command: "details",
        knownRevisions: {
          backendSessionId: backendSessionId,
          queueRevision: knownQueueRevision,
          catalogRevision: knownCatalogRevision
        },
        retainedOperationIds: trackedOperationIds()
      }
      statusProcess.command = [cli, "request", JSON.stringify(request)]
    } else {
      statusProcess.command = [cli, "status"]
    }
    statusProcess.running = true
  }

  function request(command, payload) {
    var source = payload || ({})
    var body = ({})
    for (var key in source) body[key] = source[key]
    body.command = command
    requestSerial += 1
    var requestId = requestSerial
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
      root.bootstrapError = code === 0 ? "" : String(bootstrapErr.text || "Не удалось запустить OmaTube").trim()
      root.refresh(true)
    }
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(code) {
      var repeatRefresh = root.refreshPending
      var successful = false
      root.refreshPending = false
      if (code !== 0) {
        root.statusError = "Фоновый сервис OmaTube недоступен"
      } else {
        try {
          var envelope = JSON.parse(statusOut.text || "{}")
          if (!envelope.ok)
            throw new Error(envelope.error ? envelope.error.message : "Ошибка backend")
          var result = envelope.result || ({})
          var nextSessionId = String(result.backendSessionId || "")
          if (nextSessionId !== "" && root.backendSessionId !== ""
              && nextSessionId !== root.backendSessionId) {
            root.knownQueueRevision = -1
            root.knownCatalogRevision = -1
            root.activeOperationId = ""
            root.retainedOperationIds = []
            root.backendSessionSerial += 1
          }
          if (nextSessionId !== "") root.backendSessionId = nextSessionId
          root.stateData = result
          if (root.statusRequestCommand === "details") {
            var previous = root.details || ({ queue: [], views: ({}), operations: [] })
            var hasQueue = Object.prototype.hasOwnProperty.call(result, "queue")
            var hasViews = Object.prototype.hasOwnProperty.call(result, "views")
            var hasOperations = Object.prototype.hasOwnProperty.call(result, "operations")
            if (hasQueue || hasViews || hasOperations) {
              root.details = {
                queue: hasQueue ? result.queue : previous.queue,
                views: hasViews ? result.views : previous.views,
                operations: hasOperations ? result.operations : previous.operations
              }
            }
            if (hasQueue)
              root.knownQueueRevision = Number(result.queueRevision)
            if (hasViews && hasOperations)
              root.knownCatalogRevision = Number(result.catalogRevision)
          }
          root.statusError = ""
          successful = true
        } catch (error) {
          root.statusError = String(error.message || "Некорректный ответ OmaTube")
        }
      }
      if (successful && repeatRefresh)
        Qt.callLater(function() { root.refresh(true) })
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
          root.statusError = envelope.error ? String(envelope.error.message || "Действие не выполнено") : "Действие не выполнено"
        } else {
          root.lastResult = envelope.result
          if (envelope.result && envelope.result.operationId) root.activeOperationId = String(envelope.result.operationId)
          root.statusError = ""
        }
      } catch (error) {
        root.statusError = "Действие вернуло некорректный ответ"
      }
      root.lastRequestId = root.runningRequestId
      root.actionSerial += 1
      root.refresh(true)
      root.runNextAction()
    }
  }

  Timer {
    interval: root.opened || root.playing || root.busy ? 500 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh(false)
  }
  Timer {
    interval: 1000
    running: root.busy
    repeat: true
    onTriggered: root.busySeconds += 1
  }

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }
}
