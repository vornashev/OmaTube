import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property var feedItems: []
  property var channels: []
  property real lastChecked: 0
  property int feedRequestId: 0
  property int channelsRequestId: 0
  property int seenRevision: -1
  property bool loading: false
  property bool refreshing: false
  property bool unseenOnly: false
  property bool importing: false
  property int importRequestId: 0
  property string importMessage: ""
  property bool importFailed: false
  signal channelRequested(var entity)

  readonly property bool compact: width < Style.space(700)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property int newCount: logic && logic.stateData.newCount ? Number(logic.stateData.newCount) : 0
  readonly property var groups: {
    var now = new Date()
    var startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime() / 1000
    var result = [{ label: L.tr("СЕГОДНЯ"), min: startToday, items: [] }, { label: L.tr("ВЧЕРА"), min: startToday - 86400, items: [] },
      { label: L.tr("НА ЭТОЙ НЕДЕЛЕ"), min: startToday - 6 * 86400, items: [] }, { label: L.tr("РАНЬШЕ"), min: -1, items: [] }]
    feedItems.forEach(function(item) {
      if (unseenOnly && item.isNew !== true) return
      for (var i = 0; i < result.length; ++i) {
        if (Number(item.publishedTs) >= result[i].min) { result[i].items.push(item); break }
      }
    })
    return result.filter(function(group) { return group.items.length > 0 })
  }
  readonly property string updatedLabel: {
    if (!(lastChecked > 0)) return L.tr("ещё не обновлялось")
    var minutes = Math.max(0, Math.round((Date.now() / 1000 - lastChecked) / 60))
    return minutes < 1 ? L.tr("только что") : (minutes < 60 ? minutes + L.tr(" мин назад") : Math.round(minutes / 60) + L.tr(" ч назад"))
  }

  function importFromAccount() {
    if (!logic || importing) return
    importing = true
    importFailed = false
    importMessage = ""
    importRequestId = logic.request("subscriptions_import", ({}))
  }

  function load() {
    if (!logic) return
    loading = true
    feedRequestId = logic.request("feed", { offset: 0 })
    channelsRequestId = logic.request("subscriptions", ({}))
  }

  onLogicChanged: if (logic) load()
  onVisibleChanged: if (visible) load()

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      var result = root.logic.lastResult
      if (id === root.feedRequestId && result && result.items) {
        root.feedItems = result.items
        root.loading = false
      } else if (id === root.channelsRequestId && result && result.items) {
        root.channels = result.items
        root.lastChecked = Number(result.lastChecked || 0)
      } else if (id === root.importRequestId && root.importing) {
        root.importing = false
        root.importFailed = !(result && result.total !== undefined)
        root.importMessage = root.importFailed ? L.tr("Не удалось импортировать — проверьте вход в аккаунт в настройках")
          : (result.imported > 0 ? L.tr("Добавлено каналов: ") + result.imported : L.tr("Новых каналов нет · всего ") + result.total)
        root.load()
      } else if (root.logic.lastCommand === "feed_refresh") {
        root.refreshing = false
        root.load()
      } else if (root.logic.lastCommand === "feed_mark_seen" || root.logic.lastCommand === "subscribe"
                 || root.logic.lastCommand === "unsubscribe") {
        root.load()
      }
    }
    function onStateDataChanged() {
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenRevision < 0) root.seenRevision = revision
      else if (revision !== root.seenRevision) { root.seenRevision = revision; if (root.visible) root.load() }
    }
  }

  function formatCount(value) {
    var count = Number(value)
    if (!(count >= 0)) return ""
    if (count >= 1000000) return (count / 1000000).toFixed(1).replace(".", L.decimal()) + L.tr(" млн")
    if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1).replace(".", L.decimal()) + L.tr(" тыс.")
    return String(Math.floor(count))
  }

  function ago(seconds) {
    var days = Math.floor((Date.now() / 1000 - Number(seconds)) / 86400)
    if (days < 1) return L.tr("сегодня")
    if (days < 7) return days + L.tr(" дн.")
    if (days < 30) return Math.floor(days / 7) + L.tr(" нед.")
    return Math.floor(days / 30) + L.tr(" мес.")
  }

  Row {
    anchors.fill: parent
    spacing: 0

    Item {
      width: root.compact ? parent.width : parent.width - Style.space(230)
      height: parent.height
    Column {
      anchors.fill: parent
      anchors.leftMargin: Style.space(root.compact ? 12 : 24)
      anchors.rightMargin: Style.space(root.compact ? 12 : 24)
      anchors.topMargin: Style.space(root.compact ? 12 : 20)
      spacing: Style.space(root.compact ? 10 : 14)

      Row {
        width: parent.width
        height: Style.space(44)
        spacing: Style.space(10)
        Column {
          width: parent.width - filters.width - refreshButton.width - markSeen.width - importIcon.width - parent.spacing * (importIcon.visible ? 4 : 3)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(3)
          Text {
            text: L.tr("Подписки")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(20)
            font.bold: true
          }
          Text {
            width: parent.width
            text: (root.newCount > 0 ? root.newCount + L.tr(" новых · ") : "") + L.tr("обновлено ") + root.updatedLabel + (root.compact ? "" : L.tr(" · RSS, без авторизации"))
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
        }
        Row {
          id: filters
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          Pill {
            text: root.compact ? L.tr("НОВЫЕ") : L.tr("НЕПРОСМОТРЕННЫЕ")
            height: Style.space(25)
            selected: root.unseenOnly
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.unseenOnly = true
          }
          Pill {
            text: L.tr("ВСЁ")
            height: Style.space(25)
            selected: !root.unseenOnly
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.unseenOnly = false
          }
        }
        IconButton {
          id: refreshButton
          anchors.verticalCenter: parent.verticalCenter
          icon: "refresh-cw"
          iconSize: 14
          spinning: root.refreshing
          tooltipText: L.tr("Обновить ленту")
          enabled: !root.refreshing
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: { root.refreshing = true; root.logic.request("feed_refresh") }
        }
        IconButton {
          id: importIcon
          visible: root.compact
          width: visible ? implicitWidth : 0
          anchors.verticalCenter: parent.verticalCenter
          icon: "download"
          iconSize: 14
          spinning: root.importing
          tooltipText: L.tr("Импорт подписок из аккаунта")
          enabled: !root.importing
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.importFromAccount()
        }
        IconButton {
          id: markSeen
          anchors.verticalCenter: parent.verticalCenter
          icon: "check-check"
          iconSize: 14
          tooltipText: L.tr("Отметить всё просмотренным")
          enabled: root.newCount > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.logic.request("feed_mark_seen")
        }
      }

      ListView {
        id: chipStrip
        visible: root.compact && root.channels.length > 0
        width: parent.width
        height: visible ? Style.space(30) : 0
        orientation: ListView.Horizontal
        spacing: Style.space(6)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.channels
        delegate: Pill {
          required property var modelData
          height: Style.space(28)
          text: String(modelData.title) + (Number(modelData.newCount) > 0 ? "  " + modelData.newCount : "")
          labelSize: 11
          letterSpacing: 0
          selected: Number(modelData.newCount) > 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.channelRequested({ source: "youtube", kind: "channel", id: modelData.id, title: modelData.title, thumbnailUrl: modelData.thumbnailUrl })
        }
      }

      ListView {
        id: feedList
        width: parent.width
        height: Math.max(0, parent.height - y)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.groups
        spacing: Style.space(14)
        delegate: Column {
          required property var modelData
          width: feedList.width - (feedList.contentHeight > feedList.height ? Style.space(8) : 0)
          spacing: Style.space(2)
          Row {
            width: parent.width
            height: Style.space(17)
            spacing: Style.space(10)
            leftPadding: Style.space(4)
            Text {
              id: groupLabel
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.bold: true
              font.letterSpacing: 1.5
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - groupLabel.width - parent.spacing - parent.leftPadding)
              height: Math.max(1, Style.space(1))
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
            }
          }
          Repeater {
            model: modelData.items
            delegate: Item {
              id: feedRow
              required property var modelData
              readonly property bool unseen: modelData.isNew === true
              width: parent.width
              height: Style.space(58)
              HoverHandler { id: rowHover }
              Rectangle {
                anchors.fill: parent
                color: rowHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent"
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.logic.request("play_url", { url: modelData.canonicalUrl })
              }
              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(2)
                anchors.rightMargin: Style.space(2)
                spacing: Style.space(14)
                Rectangle {
                  width: Style.space(6); height: width; radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: feedRow.unseen ? Color.accent : "transparent"
                }
                Rectangle {
                  width: Style.space(root.compact ? 80 : 96)
                  height: Style.space(root.compact ? 45 : 54)
                  anchors.verticalCenter: parent.verticalCenter
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06)
                  clip: true
                  CatalogImage {
                    anchors.fill: parent
                    requestedSource: String(modelData.thumbnailUrl || "")
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fillMode: Image.PreserveAspectCrop
                  }
                }
                Column {
                  width: parent.width - Style.space(6) - Style.space(root.compact ? 80 : 96) - rowActions.width - (feedMark.visible ? feedMark.width + parent.spacing : 0) - parent.spacing * 3
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(modelData.title)
                    color: feedRow.unseen ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(13)
                    font.weight: feedRow.unseen ? Font.DemiBold : Font.Normal
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: String(modelData.author) + (modelData.viewCount ? " · " + root.formatCount(modelData.viewCount) : "") + " · " + root.ago(modelData.publishedTs)
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.space(11)
                    elide: Text.ElideRight
                  }
                }
                QueueMark {
                  id: feedMark
                  anchors.verticalCenter: parent.verticalCenter
                  logic: root.logic
                  videoId: String(modelData.videoId || "")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                Row {
                  id: rowActions
                  visible: rowHover.hovered
                  width: visible ? implicitWidth : 0
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  IconButton { icon: "clock-plus"; iconSize: 14; tooltipText: L.tr("Смотреть позже"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.logic.request("watch_later", { media: modelData }) }
                  IconButton { visible: !feedMark.visible; width: visible ? implicitWidth : 0; icon: "list-plus"; iconSize: 14; tooltipText: L.tr("В мою очередь"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.logic.request("enqueue_url", { url: modelData.canonicalUrl, placement: "end" }) }
                  IconButton { icon: "play"; iconSize: 14; tooltipText: L.tr("Играть"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.logic.request("play_url", { url: modelData.canonicalUrl }) }
                }
              }
            }
          }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Text {
          visible: !root.loading && root.groups.length === 0
          anchors.centerIn: parent
          width: parent.width - Style.space(40)
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.channels.length === 0 ? L.tr("Подписок пока нет. Откройте канал и нажмите «Отслеживать».")
            : (root.unseenOnly ? L.tr("Непросмотренных нет") : L.tr("В ленте пока пусто — обновите её позже"))
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
      }
    }
    }

    Rectangle {
      visible: !root.compact
      width: visible ? Math.max(1, Style.space(1)) : 0
      height: parent.height
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
    }

    Column {
      visible: !root.compact
      width: visible ? Style.space(230) - Math.max(1, Style.space(1)) : 0
      height: parent.height
      spacing: Style.space(4)
      topPadding: Style.space(20)
      leftPadding: Style.space(14)
      rightPadding: Style.space(14)
      Item {
        width: parent.width - Style.space(28)
        height: Style.space(30)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: L.tr("КАНАЛЫ · ") + root.channels.length
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          font.bold: true
          font.letterSpacing: 1.5
        }
      }
      ListView {
        id: channelList
        width: parent.width - Style.space(28)
        height: Math.max(0, parent.height - y - importButton.height - importNote.height - Style.space(38))
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.channels
        spacing: Style.space(2)
        delegate: Item {
          required property var modelData
          readonly property bool hasNew: Number(modelData.newCount) > 0
          width: channelList.width
          height: Style.space(38)
          HoverHandler { id: channelHover }
          Rectangle {
            anchors.fill: parent
            color: channelHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .06) : "transparent"
          }
          Accessible.role: Accessible.Button
          Accessible.name: String(modelData.title)
          Row {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(10)
            Rectangle {
              width: Style.space(26); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .08)
              clip: true
              CatalogImage {
                anchors.fill: parent
                requestedSource: String(modelData.thumbnailUrl || "")
                foreground: root.foreground
                fontFamily: root.fontFamily
                emptyIcon: "󰀄"
                fillMode: Image.PreserveAspectCrop
              }
            }
            Text {
              width: parent.width - Style.space(36) - (badge.visible ? badge.width + parent.spacing : 0)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(modelData.title)
              color: hasNew ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              elide: Text.ElideRight
            }
            Rectangle {
              id: badge
              visible: hasNew
              anchors.verticalCenter: parent.verticalCenter
              width: badgeLabel.implicitWidth + Style.space(12)
              height: Style.space(15)
              color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18)
              Text {
                id: badgeLabel
                anchors.centerIn: parent
                text: String(modelData.newCount)
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                font.bold: true
              }
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.channelRequested({ source: "youtube", kind: "channel", id: modelData.id, title: modelData.title, thumbnailUrl: modelData.thumbnailUrl })
          }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      }
      Text {
        id: importNote
        visible: root.importMessage !== ""
        width: parent.width - Style.space(28)
        height: visible ? implicitHeight : 0
        text: root.importMessage
        wrapMode: Text.WordWrap
        color: root.importFailed ? Color.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
      }
      Pill {
        id: importButton
        width: parent.width - Style.space(28)
        height: Style.space(31)
        icon: "download"
        iconSize: 13
        text: root.importing ? L.tr("Импортируем…") : L.tr("Импорт из аккаунта")
        labelSize: 11
        letterSpacing: 0
        enabled: !root.importing
        tooltipText: L.tr("Импортировать подписки аккаунта YouTube (нужен вход в настройках)")
        onClicked: root.importFromAccount()
        foreground: root.foreground
        fontFamily: root.fontFamily
      }
    }
  }
}
