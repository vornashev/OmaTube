import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real leftInset: 0
  property int tab: 0
  signal playlistPickerRequested(var media)
  signal channelRequested(var entity)
  signal sessionsRequested()

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var currentEntry: stateData.current || null
  // The list shows the lane that plays: My queue, or what "Play" started.
  readonly property bool myQueue: logic !== null && logic.lane === "main"
  readonly property var queue: logic && logic.details.queue ? logic.details.queue : []
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color line: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)

  readonly property var info: stateData.info || ({ description: "", chapters: [] })
  readonly property var chapters: info.chapters || []
  readonly property var sponsor: stateData.sponsor || null
  readonly property var sponsorSegments: sponsor && sponsor.segments ? sponsor.segments : []
  readonly property real position: Number(stateData.position || 0)
  readonly property real duration: Number(stateData.duration || 0)
  readonly property int currentChapter: {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (position >= chapters[i].start) found = i
    return found
  }
  readonly property string descriptionHtml: {
    var text = String(info.description || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    text = text.replace(/\b((?:\d{1,2}:)?\d{1,2}:\d{2})\b/g, function(match) {
      var parts = match.split(":").map(Number), seconds = 0
      for (var i = 0; i < parts.length; ++i) seconds = seconds * 60 + parts[i]
      return '<a href="seek:' + seconds + '">' + match + '</a>'
    })
    return text.replace(/\n/g, "<br>")
  }

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    return Math.floor(seconds / 60) + ":" + (seconds % 60 < 10 ? "0" : "") + (seconds % 60)
  }

  function chapterEnd(index) {
    if (index + 1 < chapters.length) return chapters[index + 1].start
    return duration
  }

  readonly property var categoryLabels: ({
    sponsor: L.tr("СПОНСОР"), intro: L.tr("ИНТРО"), outro: L.tr("КОНЦОВКА"), selfpromo: L.tr("РЕКЛАМА"),
    interaction: L.tr("ПОДПИСКА"), preview: L.tr("ПРЕВЬЮ"), music_offtopic: L.tr("НЕ МУЗЫКА")
  })
  readonly property var categoryColors: ({
    sponsor: "#00d400", intro: "#00ffff", outro: "#4a4aff", selfpromo: "#ffff00",
    interaction: "#cc00ff", preview: "#008fd6", music_offtopic: "#ff9900"
  })

  function chapterBadge(index) {
    var start = chapters[index].start
    var end = chapterEnd(index)
    for (var i = 0; i < sponsorSegments.length; ++i) {
      var segment = sponsorSegments[i]
      if (segment.start >= start && segment.start < (end || 1e9)) {
        return { category: segment.category, label: categoryLabels[segment.category] || segment.category.toUpperCase(),
                 extra: segment.category === "sponsor" ? " " + formatTime(segment.end - segment.start) : "" }
      }
    }
    return null
  }

  readonly property string totalDuration: {
    var seconds = 0
    for (var i = 0; i < queue.length; ++i) seconds += Number((queue[i].media || queue[i]).duration || 0)
    if (seconds <= 0) return ""
    var h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), sec = Math.floor(seconds % 60)
    return h + ":" + (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }
  readonly property int currentIndex: {
    for (var i = 0; i < queue.length; ++i) if (currentEntry && queue[i].entryId === currentEntry.entryId) return i
    return -1
  }

  property string clipboardUrl: ""
  readonly property bool wantsClipboard: queue.length === 0 && tab === 0 && visible

  function refreshClipboard() {
    if (!clipboardProcess.running) clipboardProcess.running = true
  }
  onWantsClipboardChanged: if (wantsClipboard) refreshClipboard()

  Process {
    id: clipboardProcess
    command: ["/usr/bin/wl-paste", "--no-newline"]
    stdout: StdioCollector { id: clipboardOut; waitForEnd: true }
    onExited: function(code) {
      var text = code === 0 ? String(clipboardOut.text || "").trim() : ""
      root.clipboardUrl = /^https?:\/\/(www\.|m\.|music\.)?(youtube\.com|youtu\.be)\/\S+$/.test(text) ? text : ""
    }
  }
  Timer {
    interval: 2500
    repeat: true
    running: root.wantsClipboard
    onTriggered: root.refreshClipboard()
  }

  function request(command, payload) {
    if (logic) logic.request(command, payload || ({}))
  }

  function submitUrl(placement) {
    var url = urlField.text.trim()
    if (!url) return
    request(placement === "play" ? "play_url" : "enqueue_url", placement === "play"
      ? { url: url } : { url: url, placement: "end" })
    urlField.selectAll()
  }

  // ---- Queue list: selection, drag-and-drop, undoable removal and "just added" flash.

  property var selectedIds: ({})
  property string selectionAnchor: ""
  readonly property int selectedCount: Object.keys(selectedIds).length
  // Removed rows collapse into an undo plaque for 5 s: { key, rows: [{ entry, beforeEntryId }], title, beforeId, expiresAt }
  property var removals: []
  property int removalSerial: 0
  property var restoringIds: ({})
  property var knownIds: null
  property var freshUntil: ({})
  property var flashUntil: ({})
  property real now: Date.now()
  property string pendingFocusId: ""
  property string dragEntryId: ""
  property real dragY: 0
  property real dragGrab: 0
  property int dropSlot: -1
  // After a drop the rows hold their new places until the backend sends the reordered queue.
  property string settleId: ""
  property int settleSlot: -1

  readonly property bool shuffled: stateData.shuffle === true
  readonly property var removedIds: {
    var ids = ({})
    removals.forEach(function(group) { group.rows.forEach(function(row) { ids[row.entry.entryId] = true }) })
    return ids
  }
  readonly property var entries: queue.filter(function(entry) { return !removedIds[entry.entryId] })
  readonly property int entriesCurrentIndex: {
    for (var i = 0; i < entries.length; ++i) if (currentEntry && entries[i].entryId === currentEntry.entryId) return i
    return -1
  }
  readonly property var displayRows: {
    var rows = entries.map(function(entry, index) { return { kind: "entry", entry: entry, index: index } })
    removals.forEach(function(group) {
      var at = group.beforeId ? rows.findIndex(function(row) { return row.kind === "entry" && row.entry.entryId === group.beforeId }) : -1
      var plaque = { kind: "removal", group: group }
      if (at < 0) rows.push(plaque)
      else rows.splice(at, 0, plaque)
    })
    return rows
  }
  readonly property string currentRemaining: {
    var left = Number(stateData.duration || 0) - position
    return left > 0 ? formatTime(left) : ""
  }

  onQueueChanged: {
    settleId = ""
    settleSlot = -1
    var ids = queue.map(function(entry) { return entry.entryId })
    var present = ({})
    ids.forEach(function(id) { present[id] = true })
    if (knownIds !== null) {
      var added = ids.filter(function(id) { return !knownIds[id] && !restoringIds[id] })
      // A replaced queue is not "added to"; only flash a few new rows next to existing ones.
      if (added.length > 0 && added.length < ids.length) {
        var fresh = Object.assign({}, freshUntil), flash = Object.assign({}, flashUntil), at = Date.now()
        added.forEach(function(id) { fresh[id] = at + 6000; flash[id] = at + 1500 })
        freshUntil = fresh
        flashUntil = flash
        now = at
        var first = added[0]
        Qt.callLater(function() { root.revealEntry(first, false) })
      }
    }
    knownIds = present
    var restoring = Object.assign({}, restoringIds)
    for (var id in restoring) if (present[id]) delete restoring[id]
    restoringIds = restoring
    var selected = Object.assign({}, selectedIds), changed = false
    for (var key in selected) if (!present[key]) { delete selected[key]; changed = true }
    if (changed) selectedIds = selected
    if (pendingFocusId !== "") {
      var target = pendingFocusId
      pendingFocusId = ""
      Qt.callLater(function() { root.revealEntry(target, true) })
    }
  }

  Timer {
    interval: 200
    repeat: true
    running: root.removals.length > 0 || Object.keys(root.freshUntil).length > 0
    onTriggered: {
      var at = Date.now()
      root.now = at
      var expired = root.removals.filter(function(group) { return group.expiresAt <= at })
      if (expired.length > 0) root.removals = root.removals.filter(function(group) { return group.expiresAt > at })
      root.freshUntil = root.prune(root.freshUntil, at)
      root.flashUntil = root.prune(root.flashUntil, at)
    }
  }

  Timer {
    id: settleTimer
    interval: 1500
    onTriggered: { root.settleId = ""; root.settleSlot = -1 }
  }

  function prune(map, at) {
    var copy = ({}), changed = false
    for (var id in map) { if (map[id] > at) copy[id] = map[id]; else changed = true }
    return changed ? copy : map
  }

  function displayIndexOf(entryId) {
    return displayRows.findIndex(function(row) { return row.kind === "entry" && row.entry.entryId === entryId })
  }

  function revealEntry(entryId, focus) {
    var index = displayIndexOf(entryId)
    if (index < 0) return
    queueView.positionViewAtIndex(index, ListView.Contain)
    var holder = queueView.itemAtIndex(index)
    if (focus && holder && holder.row) holder.row.forceActiveFocus()
  }

  function navigate(entryId, delta) {
    var index = displayIndexOf(entryId)
    for (var i = index + delta; i >= 0 && i < displayRows.length; i += delta) {
      if (displayRows[i].kind !== "entry") continue
      revealEntry(displayRows[i].entry.entryId, true)
      return
    }
  }

  function moveBefore(entryId, beforeEntryId, keepFocus) {
    if (keepFocus) pendingFocusId = entryId
    request("queue_move", { entryId: entryId, beforeEntryId: beforeEntryId })
  }

  function move(entryId, delta, keepFocus) {
    var index = entries.findIndex(function(entry) { return entry.entryId === entryId })
    var target = index + delta
    if (index < 0 || target < 0 || target >= entries.length) return
    moveBefore(entryId, delta < 0 ? entries[target].entryId
      : (target + 1 < entries.length ? entries[target + 1].entryId : null), keepFocus)
  }

  // Places the given entries, in queue order, right after the current one.
  function playNext(ids, keepFocus) {
    var picked = ({})
    ids.forEach(function(id) { if (!currentEntry || id !== currentEntry.entryId) picked[id] = true })
    var before = null
    for (var i = entriesCurrentIndex + 1; i < entries.length; ++i)
      if (!picked[entries[i].entryId]) { before = entries[i].entryId; break }
    entries.forEach(function(entry) {
      if (picked[entry.entryId]) moveBefore(entry.entryId, before, keepFocus && ids.length === 1)
    })
  }

  function removeEntries(ids, keepFocus) {
    var order = entries.map(function(entry) { return entry.entryId })
    var picked = ids.filter(function(id) { return order.indexOf(id) >= 0 })
      .sort(function(a, b) { return order.indexOf(a) - order.indexOf(b) })
    if (picked.length === 0) return
    var set = ({})
    picked.forEach(function(id) { set[id] = true })
    var rows = picked.map(function(id) {
      var index = order.indexOf(id)
      return { entry: entries[index], beforeEntryId: index + 1 < order.length ? order[index + 1] : null }
    })
    var beforeId = null
    for (var i = order.indexOf(picked[0]) + 1; i < order.length; ++i) if (!set[order[i]]) { beforeId = order[i]; break }
    if (keepFocus && beforeId) pendingFocusId = beforeId
    removalSerial += 1
    removals = removals.concat([{
      key: removalSerial, rows: rows, beforeId: beforeId, expiresAt: Date.now() + 5000,
      title: picked.length === 1 ? "«" + String((rows[0].entry.media || ({})).title || L.tr("Видео")) + L.tr("» убрано из очереди")
        : L.tr("Убрано из очереди: ") + picked.length
    }])
    now = Date.now()
    picked.forEach(function(id) { request("queue_remove", { entryId: id }) })
    clearSelection()
  }

  function undoRemoval(key) {
    var group = key === undefined ? removals[removals.length - 1]
      : removals.find(function(row) { return row.key === key })
    if (!group) return false
    removals = removals.filter(function(row) { return row !== group })
    var restoring = Object.assign({}, restoringIds)
    group.rows.forEach(function(row) { restoring[row.entry.entryId] = true })
    restoringIds = restoring
    // Bottom-up, so every row's original neighbour is back before the row itself.
    request("queue_restore", { entries: group.rows.slice().reverse() })
    return true
  }

  function selectEntry(entryId, toggle, range) {
    if (currentEntry && entryId === currentEntry.entryId) return
    var copy = toggle ? Object.assign({}, selectedIds) : ({})
    if (range && selectionAnchor !== "") {
      var from = entries.findIndex(function(entry) { return entry.entryId === selectionAnchor })
      var to = entries.findIndex(function(entry) { return entry.entryId === entryId })
      if (from < 0) from = to
      for (var i = Math.min(from, to); i <= Math.max(from, to); ++i)
        if (!currentEntry || entries[i].entryId !== currentEntry.entryId) copy[entries[i].entryId] = true
    } else {
      if (copy[entryId]) delete copy[entryId]
      else copy[entryId] = true
      selectionAnchor = entryId
    }
    selectedIds = copy
  }

  function clearSelection() {
    selectedIds = ({})
    selectionAnchor = ""
  }

  function bulkAction(action) {
    var picked = selectedInOrder()
    if (action === "next") { playNext(picked.map(function(entry) { return entry.entryId }), false); clearSelection() }
    else if (action === "playlist") playlistPickerRequested(picked.map(function(entry) { return entry.media }))
    else if (action === "remove") removeEntries(picked.map(function(entry) { return entry.entryId }), false)
  }

  function selectedInOrder() {
    return entries.filter(function(entry) { return root.selectedIds[entry.entryId] === true })
  }

  // ---- Drag-and-drop: the row lifts under the cursor, its slot stays as a ghost, a line marks the drop.

  readonly property var dragEntry: dragEntryId === "" ? null
    : (entries.find(function(entry) { return entry.entryId === root.dragEntryId }) || null)
  readonly property var dropTarget: {
    if (!dragEntry || dropSlot < 0) return null
    var before = null, position = 1
    for (var i = 0; i < displayRows.length; ++i) {
      var row = displayRows[i]
      if (row.kind !== "entry" || row.entry.entryId === dragEntryId) continue
      if (i >= dropSlot) { before = row.entry.entryId; break }
      position += 1
    }
    var index = entries.findIndex(function(entry) { return entry.entryId === root.dragEntryId })
    var originalBefore = index + 1 < entries.length ? entries[index + 1].entryId : null
    return before === originalBefore ? null : { beforeEntryId: before, position: position }
  }

  function startDrag(entryId, row, y) {
    dragEntryId = entryId
    dragGrab = y
    dragY = row.mapToItem(queueView.contentItem, 0, y).y
    updateDropSlot()
  }

  function updateDrag(row, y) {
    dragY = row.mapToItem(queueView.contentItem, 0, y).y
    updateDropSlot()
  }

  // Slot boundary by the centre of the lifted row, measured on the untranslated layout.
  function updateDropSlot() {
    var probe = dragY - dragGrab + Style.space(24)
    var index = queueView.indexAt(Style.space(20), probe)
    if (index < 0) { dropSlot = probe < 0 ? 0 : displayRows.length; return }
    var holder = queueView.itemAtIndex(index)
    dropSlot = holder && probe > holder.y + holder.height / 2 ? index + 1 : index
  }

  function rowHeight(index) {
    var row = displayRows[index]
    return row && row.kind === "removal" ? Style.space(36) + Math.max(2, Style.space(2)) : Style.space(48)
  }

  // While dragging, rows between the origin and the drop slot slide over by one row and the
  // dragged row's ghost moves into the opened gap, so the placeholder shows where it will land.
  function dragShift(index) {
    var id = dragEntryId !== "" ? dragEntryId : settleId
    var slot = dragEntryId !== "" ? dropSlot : settleSlot
    if (id === "" || slot < 0) return 0
    var origin = displayIndexOf(id)
    if (origin < 0) return 0
    var target = slot > origin ? slot - 1 : slot
    var size = rowHeight(origin), offset = 0, i
    if (index === origin) {
      if (target > origin) for (i = origin + 1; i <= target; ++i) offset += rowHeight(i)
      else for (i = target; i < origin; ++i) offset -= rowHeight(i)
      return offset
    }
    if (target > origin && index > origin && index <= target) return -size
    if (target < origin && index >= target && index < origin) return size
    return 0
  }

  function finishDrag() {
    var target = dropTarget
    var id = dragEntryId
    if (target) { settleId = id; settleSlot = dropSlot; settleTimer.restart() }
    dragEntryId = ""
    dropSlot = -1
    if (target) moveBefore(id, target.beforeEntryId, true)
  }

  Column {
    anchors.fill: parent
    anchors.leftMargin: root.leftInset
    anchors.rightMargin: root.leftInset
    anchors.topMargin: root.leftInset > 0 ? Style.space(20) : 0
    anchors.bottomMargin: root.leftInset > 0 ? Style.space(16) : 0
    spacing: Style.space(12)

    TabStrip {
      width: parent.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      current: root.tab
      tabs: [{ label: L.tr("ОЧЕРЕДЬ"), value: 0 }, { label: L.tr("ГЛАВЫ"), value: 1 }, { label: L.tr("ТЕКСТ"), value: 3 },
             { label: L.tr("ОПИСАНИЕ"), value: 2 }, { label: L.tr("КОММЕНТАРИИ"), value: 4 }]
      onSelected: value => root.tab = value
    }

    Rectangle {
      visible: root.tab === 0
      width: parent.width
      height: visible ? Style.space(34) : 0
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: urlField.activeFocus ? Color.accent : root.line
      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(10)
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "link"; size: Style.space(14); color: root.dim }
        TextInput {
          id: urlField
          width: parent.width - Style.space(24) - hint.width - parent.spacing * 2
          anchors.verticalCenter: parent.verticalCenter
          color: root.foreground
          selectionColor: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          clip: true
          selectByMouse: true
          onAccepted: root.submitUrl("play")
          Text {
            visible: urlField.text === ""
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
            text: L.tr("Вставьте ссылку на видео или плейлист")
            color: root.dim
            font: urlField.font
            elide: Text.ElideRight
          }
        }
        Text {
          id: hint
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: urlField.text === "" ? "" : L.tr("⏎ играть")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
        }
      }
    }

    Row {
      visible: root.tab === 0
      width: parent.width
      height: visible ? Style.space(24) : 0
      spacing: Style.space(6)
      Text {
        width: Math.max(0, parent.width - clearQueue.width - sessionsButton.width - countLabel.width - parent.spacing * (clearQueue.visible ? 3 : 2))
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: Style.space(12)
        textFormat: Text.PlainText
        text: root.queue.length === 0 ? "" : root.myQueue ? L.tr("МОЯ ОЧЕРЕДЬ")
          : root.stateData.context && root.stateData.context.name ? L.tb(root.stateData.context.name).toUpperCase() : L.tr("ОЧЕРЕДЬ")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        font.letterSpacing: 1
        elide: Text.ElideRight
      }
      Text {
        id: countLabel
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.queue.length > 0 ? (root.currentIndex + 1) + " / " + root.queue.length
          + (root.totalDuration !== "" ? " · " + root.totalDuration : "") : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
      IconButton {
        id: sessionsButton
        width: Style.space(24)
        height: Style.space(24)
        icon: "save"
        iconSize: 14
        tooltipText: L.tr("Сессии очереди")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.sessionsRequested()
      }
      IconButton {
        id: clearQueue
        visible: root.queue.length > 0
        width: visible ? Style.space(24) : 0
        height: Style.space(24)
        icon: "trash-2"
        iconSize: 14
        tooltipText: L.tr("Очистить очередь")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.request("queue_clear")
      }
    }

    Item {
      visible: root.tab === 0
      width: parent.width
      height: visible ? Math.max(0, parent.height - y) : 0
      clip: true

      Column {
        visible: root.displayRows.length === 0
        anchors.centerIn: parent
        width: parent.width - Style.space(32)
        spacing: Style.space(10)
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "list-video"; size: Style.space(28); color: root.dim }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.myQueue ? L.tr("Моя очередь пуста") : L.tr("Очередь пуста")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(13)
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
        }
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: L.tr("Найдите что-нибудь в поиске или вставьте ссылку выше — добавим её в очередь.")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
        Pill {
          visible: root.clipboardUrl !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(32)
          icon: "clipboard-paste"
          text: L.tr("ИЗ БУФЕРА · ") + root.clipboardUrl.replace(/^https?:\/\/(www\.)?/, "").substring(0, 30)
          selected: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { root.request("play_url", { url: root.clipboardUrl, placement: "first" }); root.clipboardUrl = "" }
        }
      }

      Keys.onPressed: event => {
        if (event.key === Qt.Key_Z && event.modifiers === Qt.ControlModifier) {
          if (root.undoRemoval()) event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.dragEntryId !== "") {
          root.dragEntryId = ""
          root.dropSlot = -1
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && root.selectedCount > 0) {
          root.clearSelection()
          event.accepted = true
        } else if (event.key === Qt.Key_Delete && root.selectedCount > 0) {
          root.removeEntries(Object.keys(root.selectedIds), false)
          event.accepted = true
        }
      }

      ListView {
        id: queueView
        visible: root.displayRows.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: bulkBar.visible ? bulkBar.top : parent.bottom
        anchors.bottomMargin: bulkBar.visible ? Style.space(6) : 0
        clip: true
        interactive: root.dragEntryId === ""
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: height
        model: root.displayRows
        delegate: Item {
          id: holder
          required property var modelData
          required property int index
          readonly property var row: modelData.kind === "entry" ? entryRow : null
          width: queueView.width - (queueView.contentHeight > queueView.height ? Style.space(8) : 0)
          height: modelData.kind === "entry" ? entryRow.height : plaque.height
          z: root.dragEntryId !== "" && entryRow.entryId === root.dragEntryId ? -1 : 0
          transform: Translate {
            y: root.dragShift(holder.index)
            Behavior on y { enabled: root.dragEntryId !== ""; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          }

          QueueRow {
            id: entryRow
            readonly property string entryId: holder.modelData.kind === "entry" ? String(holder.modelData.entry.entryId) : ""
            readonly property int entryIndex: holder.modelData.kind === "entry" ? holder.modelData.index : -1
            visible: holder.modelData.kind === "entry"
            width: parent.width
            logic: root.logic
            item: holder.modelData.kind === "entry" ? holder.modelData.entry : ({})
            rowNumber: entryIndex + 1
            current: root.currentEntry !== null && entryId === root.currentEntry.entryId
            played: !root.shuffled && root.entriesCurrentIndex >= 0 && entryIndex < root.entriesCurrentIndex
            isNext: !root.shuffled && root.entriesCurrentIndex >= 0 && entryIndex === root.entriesCurrentIndex + 1
            nextIn: root.currentRemaining
            fresh: root.freshUntil[entryId] > root.now
            flash: root.flashUntil[entryId] > root.now
            selected: root.selectedIds[entryId] === true
            selectionMode: root.selectedCount > 0
            dragRole: root.dragEntryId !== "" && root.dragEntryId === entryId ? "ghost" : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            onActiveFocusChanged: if (activeFocus) queueView.positionViewAtIndex(holder.index, ListView.Contain)
            onPlayRequested: root.request("queue_play", { entryId: entryId })
            onNextRequested: root.playNext([entryId], activeFocus)
            onRemoveRequested: root.removeEntries([entryId], activeFocus)
            onMoveRequested: delta => root.move(entryId, delta, true)
            onNavigateRequested: delta => root.navigate(entryId, delta)
            onSelectRequested: (toggle, range) => root.selectEntry(entryId, toggle, range)
            onSelectionCleared: root.clearSelection()
            onPlaylistRequested: media => root.playlistPickerRequested(media)
            onChannelRequested: entity => root.channelRequested(entity)
            onCommandRequested: (command, payload) => root.request(command, payload)
            onTimecodeRequested: media => Quickshell.execDetached(["/usr/bin/wl-copy", String(media.canonicalUrl) + (String(media.canonicalUrl).indexOf("?") >= 0 ? "&" : "?") + "t=" + Math.floor(root.position)])
            onDragStarted: y => root.startDrag(entryId, entryRow, y)
            onDragMoved: y => root.updateDrag(entryRow, y)
            onDragFinished: root.finishDrag()
          }

          // Removed rows collapse into this plaque for 5 s; Ctrl+Z works as well.
          Column {
            id: plaque
            readonly property var group: holder.modelData.kind === "removal" ? holder.modelData.group : null
            readonly property real remaining: group ? Math.max(0, group.expiresAt - root.now) : 0
            visible: group !== null
            width: parent.width
            Rectangle {
              width: parent.width
              height: Style.space(36)
              color: plaqueMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .04)
              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(16)
                anchors.rightMargin: Style.space(16)
                spacing: Style.space(10)
                Icon { id: plaqueIcon; anchors.verticalCenter: parent.verticalCenter; name: "undo-2"; size: Style.space(13); color: root.dim }
                Text {
                  width: parent.width - plaqueIcon.width - undoLabel.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: plaque.group ? plaque.group.title : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                  elide: Text.ElideRight
                }
                Text {
                  id: undoLabel
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: L.tr("ВЕРНУТЬ · ") + Math.ceil(plaque.remaining / 1000)
                  color: Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  font.bold: true
                  font.letterSpacing: 1
                }
              }
              MouseArea {
                id: plaqueMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (plaque.group) root.undoRemoval(plaque.group.key)
              }
            }
            Item {
              width: parent.width
              height: Math.max(2, Style.space(2))
              Rectangle {
                height: parent.height
                width: parent.width * Math.min(1, plaque.remaining / 5000)
                color: Color.accent
              }
            }
          }
        }

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      QueueRow {
        visible: root.dragEntry !== null
        z: 11
        x: 0
        width: queueView.width - (queueView.contentHeight > queueView.height ? Style.space(8) : 0)
        y: Math.max(-height / 2, Math.min(queueView.height - height / 2,
          root.dragY - root.dragGrab - queueView.contentY))
        enabled: false
        logic: root.logic
        item: root.dragEntry || ({})
        rowNumber: root.dragEntry ? root.entries.indexOf(root.dragEntry) + 1 : 0
        dragRole: "lifted"
        dragHint: root.dropTarget ? L.tr("→ станет ") + root.dropTarget.position + L.tr("-м") : ""
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      // Scroll while the dragged row is held near an edge.
      Timer {
        interval: 16
        repeat: true
        running: root.dragEntryId !== ""
        onTriggered: {
          var edge = Style.space(32)
          var inView = root.dragY - queueView.contentY
          var step = inView < edge ? -Style.space(6) : (inView > queueView.height - edge ? Style.space(6) : 0)
          if (step === 0) return
          var top = queueView.originY
          var bottom = queueView.originY + Math.max(0, queueView.contentHeight - queueView.height)
          var next = Math.max(top, Math.min(bottom, queueView.contentY + step))
          if (next === queueView.contentY) return
          root.dragY += next - queueView.contentY
          queueView.contentY = next
          root.updateDropSlot()
        }
      }

      // Bulk actions for a Ctrl/Shift-click selection.
      Rectangle {
        id: bulkBar
        visible: root.selectedCount > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: visible ? Style.space(37) : 0
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)
          Text {
            width: parent.width - bulkActions.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tr("Выбрано: ") + root.selectedCount
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            font.bold: true
            elide: Text.ElideRight
          }
          Row {
            id: bulkActions
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)
            Repeater {
              model: [
                { action: "next", icon: "list-start", label: L.tr("Следующими") },
                { action: "playlist", icon: "list-plus", label: L.tr("В плейлист") },
                { action: "remove", icon: "x", label: L.tr("Убрать"), danger: true }
              ]
              delegate: Rectangle {
                required property var modelData
                width: bulkRow.implicitWidth + Style.space(16)
                height: bulkRow.implicitHeight + Style.space(8)
                color: bulkMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06) : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: activeFocus ? Color.accent : root.line
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Keys.onReturnPressed: root.bulkAction(modelData.action)
                Keys.onSpacePressed: root.bulkAction(modelData.action)
                Row {
                  id: bulkRow
                  anchors.centerIn: parent
                  spacing: Style.space(5)
                  Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: Style.space(12); color: modelData.danger ? Color.urgent : root.foreground }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: modelData.danger ? Color.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(10)
                  }
                }
                MouseArea {
                  id: bulkMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.bulkAction(modelData.action)
                }
              }
            }
          }
        }
      }
    }

    Item {
      id: chaptersTab
      visible: root.tab === 1
      width: parent.width
      height: visible ? Math.max(0, parent.height - y) : 0

      ListView {
        id: chapterView
        visible: root.chapters.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height - (sponsorPanel.visible ? sponsorPanel.height + Style.space(12) : 0)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.chapters
        delegate: Item {
          required property var modelData
          required property int index
          readonly property bool current: index === root.currentChapter
          readonly property var badge: root.chapterBadge(index)
          readonly property real remaining: Math.max(0, root.chapterEnd(index) - root.position)
          width: chapterView.width - (chapterView.contentHeight > chapterView.height ? Style.space(8) : 0)
          height: Style.space(28)
          Accessible.role: Accessible.Button
          Accessible.name: String(modelData.title)
          Rectangle {
            anchors.fill: parent
            color: current ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
              : (rowMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
          }
          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(14)
            Text {
              width: Style.space(46)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.formatTime(modelData.start)
              color: current ? Color.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(12)
            }
            Text {
              width: parent.width - Style.space(46) - rightInfo.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(modelData.title)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(13)
              font.bold: current
              elide: Text.ElideRight
            }
            Row {
              id: rightInfo
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(10)
              Rectangle {
                visible: badge !== null
                anchors.verticalCenter: parent.verticalCenter
                width: badgeLabel.implicitWidth + Style.space(14)
                height: Style.space(18)
                color: "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: badge ? (root.categoryColors[badge.category] || Color.accent) : "transparent"
                Text {
                  id: badgeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: badge ? badge.label + badge.extra : ""
                  color: badge ? (root.categoryColors[badge.category] || Color.accent) : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  font.letterSpacing: 1
                }
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: current ? L.tr("осталось ") + root.formatTime(remaining) : root.formatTime(root.chapterEnd(index) - modelData.start)
                color: current ? Color.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(11)
              }
            }
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.request("seek", { seconds: modelData.start })
          }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }

      Text {
        visible: root.chapters.length === 0
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.currentEntry ? L.tr("У этого видео нет глав") : L.tr("Включите видео, чтобы увидеть главы")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }

      Rectangle {
        id: sponsorPanel
        visible: root.sponsorSegments.length > 0 || (root.sponsor && root.sponsor.saved > 0)
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: sponsorColumn.implicitHeight + Style.space(24)
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05)
        Column {
          id: sponsorColumn
          anchors.fill: parent
          anchors.margins: Style.space(12)
          spacing: Style.space(10)
          Row {
            width: parent.width
            height: Style.space(22)
            spacing: Style.space(10)
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "shield-check"; size: Style.space(16); color: Color.accent }
            Text {
              width: parent.width - Style.space(26) - savedLabel.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "SPONSORBLOCK"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              font.bold: true
              font.letterSpacing: 1.5
            }
            Text {
              id: savedLabel
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: L.tr("сэкономлено ") + root.formatTime(root.sponsor ? root.sponsor.saved : 0)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
            }
          }
          Flow {
            width: parent.width
            spacing: Style.space(16)
            Repeater {
              model: {
                var seen = {}, rows = []
                root.sponsorSegments.forEach(function(segment) {
                  if (seen[segment.category]) return
                  seen[segment.category] = true
                  rows.push(segment)
                })
                return rows
              }
              delegate: Row {
                required property var modelData
                spacing: Style.space(6)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Style.space(10); height: width; color: root.categoryColors[modelData.category] || Color.accent }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: (root.categoryLabels[modelData.category] || modelData.category).toLowerCase().replace(/^./, function(c) { return c.toUpperCase() })
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: modelData.action === "skip" ? L.tr("пропуск") : (modelData.action === "ask" ? L.tr("спросить") : L.tr("выкл"))
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                }
              }
            }
          }
        }
      }
    }

    Flickable {
      id: descriptionView
      visible: root.tab === 2
      width: parent.width
      height: visible ? Math.max(0, parent.height - y) : 0
      clip: true
      contentWidth: width
      contentHeight: descriptionText.implicitHeight + Style.space(12)
      boundsBehavior: Flickable.StopAtBounds
      Text {
        id: descriptionText
        x: Style.space(12)
        width: descriptionView.width - Style.space(24)
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        text: root.descriptionHtml !== "" ? root.descriptionHtml
          : (root.currentEntry ? L.tr("Описание недоступно") : L.tr("Включите видео, чтобы увидеть описание"))
        color: root.foreground
        linkColor: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.space(12)
        lineHeight: 1.3
        onLinkActivated: link => {
          if (link.indexOf("seek:") === 0) root.request("seek", { seconds: Number(link.substring(5)) })
        }
      }
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }

    LyricsPane {
      visible: root.tab === 3
      width: parent.width
      height: visible ? Math.max(0, parent.height - y) : 0
      active: root.tab === 3
      logic: root.logic
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    CommentsPane {
      visible: root.tab === 4
      width: parent.width
      height: visible ? Math.max(0, parent.height - y) : 0
      active: root.tab === 4
      logic: root.logic
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
  }
}
