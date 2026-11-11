import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property var view: ({})
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string tab: ""
  property string initialTab: ""
  property string sort: "Latest"
  property string backLabel: L.tr("НАЗАД")
  property bool subscribedOverride: false
  property bool overrideActive: false
  property bool sectionLoading: false
  signal backRequested()
  signal playVideo(var item)
  signal enqueueVideo(var media)
  signal playlistPickerRequested(var media)
  signal openRequested(var entity)
  signal loadMoreRequested()
  signal sectionRequested(string tab, string sort)
  signal copyRequested(var item)

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property var entity: view.entity || ({})
  readonly property var meta: view.meta || ({})
  readonly property var sections: view.sections || ({})
  readonly property var tabLabels: ({ videos: L.tr("ВИДЕО"), playlists: L.tr("ПЛЕЙЛИСТЫ"), shorts: "SHORTS", podcasts: L.tr("ПОДКАСТЫ"), live: L.tr("ЭФИРЫ") })
  readonly property var tabNames: ["videos", "playlists", "shorts", "podcasts", "live"].filter(function(name) {
    return sections[name] && ((sections[name].items || []).length > 0 || name === activeTabRaw)
  })
  readonly property string activeTabRaw: tab
  readonly property string activeTab: tabNames.indexOf(tab) >= 0 ? tab : (tabNames.length > 0 ? tabNames[0] : "")
  readonly property var rows: activeTab !== "" ? (sections[activeTab].items || []) : []
  readonly property bool hasMore: activeTab !== "" && Boolean(sections[activeTab].nextCursor)
  readonly property bool sortable: activeTab === "videos" || activeTab === "shorts" || activeTab === "live"
  readonly property bool subscribed: overrideActive ? subscribedOverride : view.subscribed === true
  readonly property string metaLine: [meta.handle, meta.subscribers, meta.videosCount].filter(function(part) { return part }).join(" · ")
  readonly property var channelPlaylists: sections.playlists ? (sections.playlists.items || []) : []
  readonly property bool compact: width < Style.space(600)
  readonly property real gutter: Style.space(compact ? 12 : 24)
  readonly property real contentWidth: width - gutter * 2
  readonly property int columns: Math.max(2, Math.floor((contentWidth + Style.space(16)) / Style.space(216)))
  readonly property real cardWidth: Math.floor((contentWidth - Style.space(16) * (columns - 1)) / columns)
  readonly property string channelId: String(entity.id || "")
  property bool cardsReady: false
  function enableCards() { cardsReady = true }
  function prepareCards() { cardsReady = false; Qt.callLater(enableCards) }
  onRowsChanged: prepareCards()
  onColumnsChanged: prepareCards()
  Component.onCompleted: prepareCards()

  onViewChanged: { overrideActive = false; sectionLoading = false }
  onChannelIdChanged: { sort = "Latest"; tab = initialTab }

  function toggleSubscription() {
    if (!logic || channelId === "") return
    subscribedOverride = !subscribed
    overrideActive = true
    if (subscribedOverride) logic.request("subscribe", { channel: entity })
    else logic.request("unsubscribe", { channelId: channelId })
  }

  function playAll() {
    var first = rows.filter(function(row) { return row.videoId })[0]
    if (first) playVideo(first)
  }

  function chooseTab(name) {
    tab = name
  }

  function chooseSort(value) {
    if (sort === value) return
    sort = value
    sectionLoading = true
    sectionRequested(activeTab, value)
  }

  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: page.implicitHeight + Style.space(24)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: page
      width: flick.width
      spacing: 0

      Rectangle {
        id: banner
        width: parent.width
        height: Style.space(110)
        color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .1)
        clip: true
        CatalogImage {
          anchors.fill: parent
          requestedSource: String(root.meta.bannerUrl || "")
          foreground: root.foreground
          fontFamily: root.fontFamily
          emptyIcon: ""
          fillMode: Image.PreserveAspectCrop
        }
        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: Style.space(16)
          width: backRow.implicitWidth + Style.space(20)
          height: Style.space(23)
          color: "#000000B3"
          Row {
            id: backRow
            anchors.centerIn: parent
            spacing: Style.space(6)
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "arrow-left"; size: Style.space(12); color: "#FFFFFF" }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.backLabel
              color: "#FFFFFF"
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.letterSpacing: 1
            }
          }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.backRequested() }
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: L.tr("Назад")
          Keys.onReturnPressed: root.backRequested()
        }
      }

      Column {
        x: root.gutter
        width: parent.width - root.gutter * 2
        topPadding: Style.space(root.compact ? 12 : 18)
        spacing: Style.space(root.compact ? 12 : 16)

        Row {
          id: headerRow
          width: parent.width
          spacing: Style.space(16)

          Rectangle {
            width: Style.space(64)
            height: width
            radius: width / 2
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
            border.width: Style.space(3)
            border.color: Color.popups.background
            clip: true
            CatalogImage {
              anchors.fill: parent
              anchors.margins: Style.space(3)
              requestedSource: String(root.entity.thumbnailUrl || root.meta.avatarUrl || "")
              foreground: root.foreground
              fontFamily: root.fontFamily
              emptyIcon: "󰀄"
              fillMode: Image.PreserveAspectCrop
            }
          }

          Column {
            width: parent.width - Style.space(64) - (root.compact ? 0 : buttonRow.width + parent.spacing) - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Row {
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                text: String(root.entity.title || L.tr("Канал"))
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(20)
                font.bold: true
              }
              Icon {
                visible: root.meta.verified === true
                anchors.verticalCenter: parent.verticalCenter
                name: "badge-check"
                size: Style.space(16)
                color: Color.accent
              }
            }
            Text {
              visible: root.metaLine !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: root.metaLine
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              elide: Text.ElideRight
            }
            Text {
              visible: String(root.meta.description || "") !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: String(root.meta.description || "").replace(/\s+/g, " ")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              maximumLineCount: 1
              elide: Text.ElideRight
            }
          }

          Row {
            id: buttonRow
            parent: root.compact ? buttonSlot : headerRow
            anchors.left: root.compact ? parent.left : undefined
            anchors.verticalCenter: root.compact ? parent.verticalCenter : parent.verticalCenter
            spacing: Style.space(8)
            Pill {
              objectName: "subscribeButton"
              height: Style.space(31)
              text: root.subscribed ? L.tr("ОТСЛЕЖИВАЕТСЯ") : L.tr("ОТСЛЕЖИВАТЬ")
              icon: root.subscribed ? "check" : "bell-plus"
              filled: !root.subscribed
              selected: root.subscribed
              bold: true
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.toggleSubscription()
            }
            Pill {
              height: Style.space(31)
              text: L.tr("ИГРАТЬ ВСЁ")
              icon: "play"
              bold: true
              labelSize: 11
              enabled: root.rows.length > 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.playAll()
            }
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              icon: "rss"
              iconSize: 14
              tooltipText: L.tr("Копировать RSS-ссылку")
              enabled: root.channelId !== ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", "https://www.youtube.com/feeds/videos.xml?channel_id=" + root.channelId])
            }
            IconButton {
              anchors.verticalCenter: parent.verticalCenter
              icon: "external-link"
              iconSize: 14
              tooltipText: L.tr("Открыть в браузере")
              enabled: root.channelId !== ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: Quickshell.execDetached(["/usr/bin/xdg-open", "https://www.youtube.com/channel/" + root.channelId])
            }
          }
        }

        Item {
          id: buttonSlot
          visible: root.compact
          width: parent.width
          height: visible ? Style.space(31) : 0
        }

        Flow {
          width: parent.width
          spacing: Style.space(root.compact ? 4 : 16)
          TabStrip {
            width: root.compact ? parent.width : parent.width - (sortRow.visible ? sortRow.width + parent.spacing : 0)
            labelSize: root.compact ? 10 : 11
            tabSpacing: root.compact ? 14 : 24
            leftInset: root.compact ? 2 : 12
            foreground: root.foreground
            fontFamily: root.fontFamily
            current: root.activeTab
            tabs: root.tabNames.map(function(name) { return { label: root.tabLabels[name], value: name } })
            onSelected: value => root.chooseTab(value)
          }
          Item {
            visible: root.sortable
            width: sortRow.width
            height: Style.space(root.compact ? 28 : 35)
          Row {
            id: sortRow
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(root.compact ? 2 : 6)
            spacing: Style.space(6)
            Pill {
              height: Style.space(23)
              text: L.tr("НОВЫЕ")
              selected: root.sort === "Latest"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.chooseSort("Latest")
            }
            Pill {
              height: Style.space(23)
              text: L.tr("ПОПУЛЯРНЫЕ")
              selected: root.sort === "Popular"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.chooseSort("Popular")
            }
          }
          }
        }

        Item {
          width: parent.width
          height: Math.max(Style.space(60), grid.implicitHeight)
          opacity: root.sectionLoading ? .35 : 1

          Grid {
            id: grid
            columns: root.columns
            columnSpacing: Style.space(16)
            rowSpacing: Style.space(root.compact ? 14 : 20)
            Repeater {
              model: root.rows
              delegate: Loader {
                id: cardSlot
                required property var modelData
                width: root.cardWidth
                height: Math.round(root.cardWidth * 9 / 16) + Style.space(54)
                readonly property real pageY: {
                  grid.parent.y; grid.y
                  return y + grid.mapToItem(flick.contentItem, 0, 0).y
                }
                active: root.cardsReady && root.visible && root.Window.window !== null && root.Window.window.visible
                  && pageY + height >= flick.contentY - height
                  && pageY <= flick.contentY + flick.height + height
                sourceComponent: MediaCard {
                  objectName: "channelCard"
                  logic: root.logic
                  item: cardSlot.modelData
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onPlayRequested: row => root.playVideo(row)
                  onPrefetchRequested: videoId => { if (root.logic) root.logic.request("prefetch", { videoId: videoId }) }
                  onEndRequested: media => root.enqueueVideo(media)
                  onOpenRequested: entity => root.openRequested(entity)
                  onPlaylistRequested: media => root.playlistPickerRequested(media)
                  onCopyRequested: item => root.copyRequested(item)
                }
              }
            }
          }
          Text {
            visible: root.rows.length === 0
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.sectionLoading ? L.tr("Загружаем…") : L.tr("В этом разделе пока пусто")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
          }
        }

        Pill {
          visible: root.hasMore
          anchors.horizontalCenter: parent.horizontalCenter
          height: Style.space(32)
          text: L.tr("ЗАГРУЗИТЬ ЕЩЁ")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.loadMoreRequested()
        }

        Row {
          visible: root.activeTab !== "playlists" && root.channelPlaylists.length > 0
          width: parent.width
          height: Style.space(19)
          spacing: Style.space(10)
          Text {
            id: playlistsHead
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tr("ПЛЕЙЛИСТЫ КАНАЛА")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            font.bold: true
            font.letterSpacing: 1.5
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - playlistsHead.width - allLink.width - parent.spacing * 2)
            height: Math.max(1, Style.space(1))
            color: root.lineColor
          }
          Text {
            id: allLink
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: L.tr("все ") + root.channelPlaylists.length + " →"
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.chooseTab("playlists") }
          }
        }

        Row {
          visible: root.activeTab !== "playlists" && root.channelPlaylists.length > 0
          width: parent.width
          spacing: Style.space(16)
          Repeater {
            model: root.channelPlaylists.slice(0, root.compact ? 2 : 3)
            delegate: Item {
              required property var modelData
              width: (parent.width - Style.space(root.compact ? 16 : 32)) / (root.compact ? 2 : 3)
              height: Style.space(45)
              Accessible.role: Accessible.Button
              Accessible.name: String(modelData.title)
              Row {
                anchors.fill: parent
                spacing: Style.space(12)
                Rectangle {
                  width: Style.space(80); height: parent.height
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
                  clip: true
                  CatalogImage {
                    anchors.fill: parent
                    requestedSource: String(modelData.thumbnailUrl || "")
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    emptyIcon: ""
                    fillMode: Image.PreserveAspectCrop
                  }
                  Icon { anchors.centerIn: parent; visible: !modelData.thumbnailUrl; name: "list-video"; size: Style.space(16); color: root.dim }
                }
                Column {
                  width: parent.width - Style.space(92)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(3)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(modelData.title)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(12)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: L.tb(modelData.author || L.tr("Плейлист"))
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(10)
                    elide: Text.ElideRight
                  }
                }
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openRequested(modelData) }
            }
          }
        }
      }
    }
  }
}
