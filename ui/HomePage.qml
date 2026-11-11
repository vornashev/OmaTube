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
  property var home: ({})
  property bool loading: false
  property int requestId: 0
  property int seenRevision: -1
  // Inside the empty search page: no title, the search page already sets the margins.
  property bool embedded: false
  signal navigate(int page)
  signal channelRequested(var entity)
  signal playlistPickerRequested(var media)
  signal openRequested(var entity)

  readonly property bool compact: width < Style.space(600)
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property int columns: compact ? 2 : 4
  readonly property var sections: [
    { label: L.tr("ПРОДОЛЖИТЬ ПРОСМОТР"), link: L.tr("вся история →"), page: 7, items: home.continue || [], resume: true },
    { label: L.tr("НОВОЕ В ПОДПИСКАХ") + (Number(home.newCount) > 0 ? " · " + home.newCount : ""), link: L.tr("все подписки →"), page: 4, items: home.new || [] },
    { label: L.tr("РЕКОМЕНДАЦИИ"), link: L.tr("обновить →"), refresh: true, items: home.recommended || [] }
  ].filter(function(section) { return section.items.length > 0 })

  function load() {
    if (!logic) return
    loading = true
    requestId = logic.request("home", ({}))
  }

  function play(row, resume) {
    if (!logic || !row.canonicalUrl) return
    var p = row.watchProgress
    logic.request("play_url", { url: row.canonicalUrl, start: resume && p ? Math.floor(p.position) : 0, media: row, placement: "first" })
  }

  onLogicChanged: if (logic) load()
  onVisibleChanged: if (visible) load()

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var id = Number(root.logic.lastRequestId || 0)
      if (id === root.requestId) {
        root.loading = false
        if (root.logic.lastResult && root.logic.lastResult.continue !== undefined) root.home = root.logic.lastResult
      }
    }
    function onStateDataChanged() {
      var revision = Number(root.logic.stateData.collectionRevision || 0)
      if (root.seenRevision < 0) root.seenRevision = revision
      else if (revision !== root.seenRevision) { root.seenRevision = revision; if (root.visible) root.load() }
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: Style.space(root.compact || root.embedded ? 0 : 24)
    anchors.rightMargin: Style.space(root.compact || root.embedded ? 0 : 24)
    anchors.topMargin: Style.space(root.embedded ? 0 : (root.compact ? 10 : 20))
    contentWidth: width
    contentHeight: page.implicitHeight + Style.space(20)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: page
      width: flick.width - (flick.contentHeight > flick.height ? Style.space(8) : 0)
      spacing: Style.space(root.compact ? 14 : 18)

      Row {
        visible: !root.embedded
        width: parent.width
        height: visible ? implicitHeight : 0
        spacing: Style.space(10)
        Column {
          width: parent.width - refreshButton.width - parent.spacing
          spacing: Style.space(3)
          Text {
            textFormat: Text.PlainText
            text: L.tr("Главная")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(20)
            font.bold: true
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: L.tr("подобрано по истории и подпискам")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            elide: Text.ElideRight
          }
        }
        IconButton {
          id: refreshButton
          anchors.verticalCenter: parent.verticalCenter
          icon: "refresh-cw"
          iconSize: 14
          spinning: root.loading
          tooltipText: L.tr("Обновить")
          enabled: !root.loading
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.load()
        }
      }

      Repeater {
        model: root.sections
        delegate: Column {
          id: section
          required property var modelData
          readonly property real cardWidth: Math.floor((width - Style.space(16) * (root.columns - 1)) / root.columns)
          width: page.width
          spacing: Style.space(10)

          Row {
            width: parent.width
            height: Style.space(17)
            spacing: Style.space(10)
            Text {
              id: sectionLabel
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.label
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              font.bold: true
              font.letterSpacing: 1.5
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - sectionLabel.width - sectionLink.width - parent.spacing * 2)
              height: Math.max(1, Style.space(1))
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
            }
            Text {
              id: sectionLink
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: modelData.link
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              MouseArea {
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.page !== undefined ? root.navigate(modelData.page) : root.load()
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(16)
            Repeater {
              model: modelData.items.slice(0, root.compact ? 4 : 4)
              delegate: MediaCard {
                logic: root.logic
                required property var modelData
                width: section.cardWidth
                height: Math.round(section.cardWidth * 9 / 16) + Style.space(54)
                item: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                onPlayRequested: row => root.play(row, section.modelData.resume === true)
                onEndRequested: media => root.logic.request("enqueue_url", { url: media.canonicalUrl, placement: "end", media: media })
                onOpenRequested: entity => root.openRequested(entity)
                onPlaylistRequested: media => root.playlistPickerRequested(media)
                onChannelRequested: entity => root.channelRequested(entity)
                onPrefetchRequested: videoId => root.logic.request("prefetch", { videoId: videoId })
              }
            }
          }
        }
      }

      Text {
        visible: !root.loading && root.sections.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        topPadding: Style.space(60)
        textFormat: Text.PlainText
        text: root.embedded ? L.tr("Здесь появятся недосмотренные видео, новинки подписок и рекомендации по вашей истории.")
          : L.tr("Здесь появятся недосмотренные видео, новинки подписок и рекомендации по вашей истории. Найдите что-нибудь через поиск.")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(11)
      }
    }
  }
}
