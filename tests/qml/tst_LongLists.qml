import QtQuick
import QtTest
import "../../ui" as OmaTube

Item {
  Window { id: host; visible: true; width: 1000; height: 600 }
  Component { id: history; OmaTube.RealHistoryPage { width: 1000; height: 600 } }
  Component { id: feed; OmaTube.RealSubscriptionsPage { width: 1000; height: 600 } }
  Component { id: channel; OmaTube.RealChannelPage { width: 1000; height: 600 } }

  TestCase {
    name: "LongLists"
    when: windowShown

    function findList(item, count) {
      if (item.count === count && typeof item.positionViewAtIndex === "function") return item
      var children = item.children || []
      for (var i = 0; i < children.length; ++i) {
        var found = findList(children[i], count)
        if (found) return found
      }
      return null
    }
    function rows() {
      var result = []
      for (var i = 0; i < 1000; ++i) result.push({ videoId: "", title: "row " + i,
        author: "test", playId: String(i), startedAt: Date.now() / 1000,
        publishedTs: Date.now() / 1000, thumbnailUrl: "", isNew: true })
      return result
    }
    function verifyVirtualized(page) {
      var list = findList(page, 1000)
      verify(list !== null)
      wait(100)
      verify(list.contentItem.children.length < 100, "Only visible rows should exist")
      list.positionViewAtIndex(999, ListView.End)
      wait(100)
      verify(list.contentItem.children.length < 100, "Scrolling must not create the entire date group")
      verify(list.contentY > 0)
    }
    function test_history_rows_are_virtualized() {
      var page = createTemporaryObject(history, host.contentItem, { items: rows() })
      verifyVirtualized(page)
    }
    function test_feed_rows_are_virtualized() {
      var page = createTemporaryObject(feed, host.contentItem, { feedItems: rows() })
      verifyVirtualized(page)
    }
    function test_channel_cards_are_virtualized() {
      var page = createTemporaryObject(channel, host.contentItem, {
        view: { entity: { id: "channel", title: "Channel" },
          sections: { videos: { items: rows() } } }
      })
      wait(100)
      var flick = null
      var children = page.children || []
      for (var i = 0; i < children.length; ++i) {
        if (typeof children[i].contentY === "number") flick = children[i]
      }
      verify(flick !== null)
      function cardCount(node) {
        var count = node.objectName === "channelCard" ? 1 : 0
        var kids = node.children || []
        for (var i = 0; i < kids.length; ++i) count += cardCount(kids[i])
        return count
      }
      verify(cardCount(page) < 40)
      flick.contentY = flick.contentHeight - flick.height
      wait(150)
      verify(cardCount(page) > 0)
      verify(cardCount(page) < 40)
    }
  }
}
