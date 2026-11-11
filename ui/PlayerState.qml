import QtQuick

// Separate notify signals keep position updates from invalidating every binding.
QtObject {
  id: root
  property string state: "idle"
  property var current: null
  property real position: 0
  property var duration: null
  property real volume: 100
  property bool muted: false
  property bool shuffle: false
  property string repeat: "off"
  property bool canSeek: false
  property int queueRevision: -1
  property var error: null
  property string videoMode: "audio"
  property bool buffering: false
  property real speed: 1
  property var sleepTimer: null
  property var info: null
  property var sponsor: null
  property var context: null
  property string lane: "source"
  property var lanes: ({})
  property var notice: null
  property string backendSessionId: ""
  property int catalogRevision: -1
  property int collectionRevision: -1
  property int newCount: 0
  property int downloadsActive: 0
  property int downloadsFailed: 0
  property var downloadsProgress: null
  property bool netSlow: false
  property int imagePort: 47865
  property var preferences: ({ videoQuality: 1080 })
  property var youtubeAuth: ({ configured: false, authenticated: false, cookieCount: 0, browser: "chromium" })

  function apply(values) {
    var meaningful = false
    Object.keys(values).forEach(function(key) {
      if (root[key] === undefined || typeof root[key] === "function") return
      var next = values[key]
      var same = root[key] === next
        || (typeof next === "object" && JSON.stringify(root[key]) === JSON.stringify(next))
      if (same) return
      root[key] = next
      if (key !== "position") meaningful = true
    })
    return meaningful
  }
}
