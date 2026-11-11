import QtQuick
import QtTest
import qs.Ui as Kit
import "../../ui" as OmaTube

Item {
  Window {
    id: host
    width: 1100
    height: 660
    visible: true
  }

  Component {
    id: lazyComponent
    OmaTube.RetainedLoader {
      width: 300
      height: 200
      sourceComponent: Flickable { contentHeight: 1000; property string filter: "all" }
    }
  }
  Component { id: imageComponent; OmaTube.CatalogImage { fillMode: Image.PreserveAspectCrop } }
  Component { id: panelComponent; OmaTube.Panel { logic: backend } }
  Component { id: logicComponent; OmaTube.WidgetLogic {} }
  SignalSpy { id: stateSpy; signalName: "stateDataChanged" }
  QtObject {
    id: backend
    property var stateData: ({ preferences: ({ onboarded: true, panelFormat: "wide" }) })
    property var details: ({ queue: [] })
    property var sourceContext: null
    property var myQueue: ({ count: 0 })
    property string lane: "source"
    property bool playing: false
    property bool hasTrack: false
    property bool busy: false
    property int actionSerial: 0
    property string busyLabel: ""
    property string loaderTooltip: ""
    signal playlistPickerRequested(var media)
    function request(command, payload) { return 1 }
    function refresh() {}
  }

  TestCase {
    name: "Memory"
    when: windowShown

    function test_lazy_loader_retains_scroll() {
      var loader = createTemporaryObject(lazyComponent, host.contentItem)
      compare(loader.item, null)
      loader.needed = true
      verify(loader.item !== null)
      var original = loader.item
      original.contentY = 123
      loader.needed = false
      loader.visible = false
      wait(30)
      loader.visible = true
      loader.needed = true
      compare(loader.item, original)
      compare(loader.item.contentY, 123)
    }

    function test_panel_first_open_from_widget() {
      var logic = createTemporaryObject(logicComponent, host.contentItem)
      var loader = findChild(logic, "panelLoader")
      compare(loader.item, null)
      logic.open()
      verify(loader.item !== null)
      compare(loader.item.logic, logic)
      compare(logic.opened, true)
      var panel = loader.item
      logic.close()
      logic.toggle()
      compare(loader.item, panel)
      compare(logic.opened, true)
      logic.close()
    }

    function test_inactive_view_released_and_restored() {
      var loader = createTemporaryObject(lazyComponent, host.contentItem, { needed: true, unloadAfter: 30 })
      loader.item.contentY = 123
      loader.item.filter = "continue"
      var original = loader.item
      wait(50)
      compare(loader.item, original)
      loader.needed = false
      tryCompare(loader, "item", null)
      loader.needed = true
      verify(loader.item !== null)
      verify(loader.item !== original)
      compare(loader.item.filter, "continue")
      tryCompare(loader.item, "contentY", 123)
    }

    function test_whole_panel_release_restores_selected_page() {
      var logic = createTemporaryObject(logicComponent, host.contentItem)
      wait(20)
      logic.open()
      var loader = findChild(logic, "panelLoader")
      loader.item.showPage(8)
      loader.item.collectionSection = "history"
      findChild(loader.item, "statsLoader").item.period = "week"
      logic.close()
      tryCompare(logic, "busy", false)
      loader.release()
      compare(loader.item, null)
      compare(Object.keys(logic.details.views).length, 0)
      logic.open()
      compare(loader.item.page, 8)
      compare(loader.item.collectionSection, "history")
      compare(findChild(loader.item, "statsLoader").item.period, "week")
      logic.close()
    }

    function test_position_does_not_invalidate_state() {
      var logic = createTemporaryObject(logicComponent, host.contentItem)
      stateSpy.target = logic
      logic.receiveState(JSON.stringify({ ok: true, event: "state", reset: true,
        result: { backendSessionId: "one", state: "paused", preferences: { language: "en" },
          current: { entryId: "entry", media: { videoId: "video" } }, position: 10 } }))
      var prefs = logic.stateData.preferences
      var current = logic.stateData.current
      stateSpy.clear()
      logic.receiveState(JSON.stringify({ ok: true, event: "state", result: { position: 11 } }))
      compare(logic.stateData.position, 11)
      compare(stateSpy.count, 0)
      compare(logic.stateData.preferences, prefs)
      compare(logic.stateData.current, current)
      logic.receiveState(JSON.stringify({ ok: true, event: "state", result: {
        mainQueue: [{ entryId: "main" }] } }))
      compare(logic.details.mainQueue[0].entryId, "main")
      logic.receiveState(JSON.stringify({ ok: true, event: "state", result: { backendSessionId: "two" } }))
      compare(logic.details.mainQueue.length, 0)
      compare(logic.backendSessionSerial, 1)
      compare(logic.statusError, "")
    }

    function test_panel_navigation() {
      var panel = createTemporaryObject(panelComponent, host.contentItem)
      var names = ["nowLoader", "searchLoader", "collectionLoader", "playlistLoader",
        "subscriptionsLoader", "downloadsLoader", "historyLoader", "statsLoader", "settingsLoader"]
      names.forEach(function(name) { compare(findChild(panel, name).item, null, name) })
      panel.open()
      verify(findChild(panel, "nowLoader").item !== null)
      names.slice(1).forEach(function(name) { compare(findChild(panel, name).item, null, name) })

      panel.openChannel({ id: "channel" }, 4)
      var search = findChild(panel, "searchLoader").item
      compare(search.returnPage, 4)
      compare(search.entity.id, "channel")
      panel.openSearch()
      tryCompare(search, "queryFocused", true)

      panel.openSection("history")
      var collection = findChild(panel, "collectionLoader").item
      compare(collection.section, "history")
      collection.section = "playlists"
      compare(panel.collectionSection, "playlists")
      panel.openSection("history")
      compare(collection.section, "history")
      collection.entityRequested({ id: "from-collection" })
      compare(search.returnToCollection, true)
      compare(search.entity.id, "from-collection")

      panel.openPlaylist("playlist", { videoId: "video" })
      var playlist = findChild(panel, "playlistLoader").item
      compare(playlist.playlistId, "playlist")
      compare(playlist.pendingMedia.videoId, "video")
      playlist.closeRequested()
      compare(panel.page, 2)

      ;[4, 5, 7, 8].forEach(function(page) { panel.showPage(page) })
      panel.settingsOpen = true
      names.forEach(function(name) { verify(findChild(panel, name).item !== null, name) })
      var stats = findChild(panel, "statsLoader").item
      stats.scrollPosition = 456
      panel.close()
      panel.open()
      panel.showPage(8)
      compare(findChild(panel, "statsLoader").item, stats)
      compare(stats.scrollPosition, 456)

      compare(findChild(panel, "sessionsLoader").item, null)
      panel.openSessions()
      verify(findChild(panel, "sessionsLoader").item !== null)
      findChild(panel, "sessionsLoader").item.close()
      compare(findChild(panel, "pickerLoader").item, null)
      panel.openPicker({ videoId: "picked" }, null)
      compare(findChild(panel, "pickerLoader").item.media.videoId, "picked")
      findChild(panel, "pickerLoader").item.close()
    }

    function test_cover_decode_and_scale() {
      var cover = createTemporaryObject(imageComponent, host.contentItem, {
        requestedSource: Kit.TestImage.url
      })
      compare(cover.source.toString(), "")
      cover.width = 200
      compare(cover.source.toString(), "")
      cover.height = 112
      tryCompare(cover, "status", Image.Ready)
      compare(cover.displayScale, host.devicePixelRatio)
      verify(cover.decodeWidth >= 200 * host.devicePixelRatio)
      verify(cover.decodeWidth < 200 * host.devicePixelRatio + 32)
      // Check the actual decoded image, not just the requested sourceSize.
      verify(cover.implicitWidth < 1600 / 2)
      verify(cover.implicitHeight < 900 / 2)

      var bucket = cover.decodeWidth
      cover.width = 201
      compare(cover.decodeWidth, bucket)

      cover.proxyPort = Kit.TestImage.port
      cover.requestedSource = "https://i.ytimg.com/vi/test/maxresdefault.jpg"
      tryCompare(cover, "status", Image.Ready)
      compare(cover.widthBucket, host.devicePixelRatio > 1 ? 0 : 320)
    }
  }
}
