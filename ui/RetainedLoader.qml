import QtQuick

// Keep fast reopenings; optionally release the view after a long inactive period.
Loader {
  id: root
  property bool needed: false
  property bool requested: false
  property int unloadAfter: 0
  property var savedState: null
  property var pendingScroll: []
  property int restoreAttempts: 0
  signal released()
  active: requested
  focus: true

  function ensureLoaded() {
    requested = true
    return item
  }

  function captureState() {
    if (!item) return savedState
    var state = { properties: ({}), scroll: [], custom: null }
    if (typeof item.saveViewState === "function") state.custom = item.saveViewState()
    else ["source", "filter", "query", "section", "period", "tab", "unseenOnly"].forEach(function(key) {
      if (item[key] !== undefined && typeof item[key] !== "function") state.properties[key] = item[key]
    })
    function visit(node, path) {
      if (typeof node.contentY === "number" && typeof node.contentHeight === "number") {
        state.scroll.push({ path: path, y: node.contentY })
        return
      }
      var children = node.children || []
      for (var i = 0; i < children.length; ++i) visit(children[i], path.concat([i]))
    }
    visit(item, [])
    return state
  }

  function restoreState() {
    if (!savedState || !item) return
    if (typeof item.restoreViewState === "function") item.restoreViewState(savedState.custom)
    else Object.keys(savedState.properties || ({})).forEach(function(key) { item[key] = savedState.properties[key] })
    pendingScroll = (savedState.scroll || []).slice()
    restoreAttempts = 0
    if (pendingScroll.length) scrollRestore.restart()
  }

  function release() {
    if (needed || !item) return
    savedState = captureState()
    scrollRestore.stop()
    pendingScroll = []
    requested = false
    released()
  }

  onStatusChanged: if (status === Loader.Ready) restoreState()

  Timer {
    interval: Math.max(1, root.unloadAfter)
    running: root.active && !root.needed && root.unloadAfter > 0
    onTriggered: root.release()
  }
  Timer {
    id: scrollRestore
    interval: 100
    repeat: true
    onTriggered: {
      if (!root.item || ++root.restoreAttempts > 200) { stop(); return }
      var pending = []
      root.pendingScroll.forEach(function(entry) {
        var node = root.item
        for (var i = 0; node && i < entry.path.length; ++i) node = (node.children || [])[entry.path[i]]
        if (!node || node.dragging || node.moving) return
        if (entry.y > Math.max(0, node.contentHeight - node.height)) { pending.push(entry); return }
        node.contentY = entry.y
      })
      root.pendingScroll = pending
      if (!pending.length) stop()
      // Rebuild paginated history far enough to reach the saved position.
      else if (typeof root.item.loadMore === "function" && !root.item.loading
               && root.item.nextOffset !== null && root.item.nextOffset !== undefined) root.item.loadMore()
      else if (typeof root.item.requestMore === "function" && typeof root.item.hasMore === "function"
               && !root.item.morePending && root.item.hasMore(root.item.view)) root.item.requestMore()
    }
  }

  onNeededChanged: {
    if (needed) {
      ensureLoaded()
      if (pendingScroll.length) scrollRestore.restart()
    } else scrollRestore.stop()
  }
  Component.onCompleted: if (needed) ensureLoaded()
}
