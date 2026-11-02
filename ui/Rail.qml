import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

Rectangle {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property int page: 0
  property string section: ""
  property var playlists: []
  property string openPlaylistId: ""
  property string playingPlaylistId: ""
  property bool playlistPlaying: false
  // My queue: pinned above the playlists; while it plays, the playlist behind Now playing waits paused.
  property bool queueActive: false
  property int queueCount: 0
  property real queueDuration: 0
  property string sourcePlace: ""
  property bool settingsActive: false
  property int newCount: 0
  property int downloadsActive: 0
  property int downloadsFailed: 0
  // Overall share downloaded, 0..1, or -1 when sizes are not known yet.
  property real downloadsProgress: -1
  signal navigate(int page)
  signal searchRequested()
  signal sectionRequested(string section)
  signal playlistRequested(string playlistId)
  signal myQueueRequested()
  signal settingsRequested()
  signal shrinkRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)
  // Now card: the active lane (details.queue) around the current entry.
  readonly property var playerState: logic ? logic.stateData : ({})
  readonly property string playerPhase: String(playerState.state || "idle")
  readonly property bool queueLane: logic !== null && logic.lane === "main"
  readonly property var laneRows: logic && logic.details && logic.details.queue ? logic.details.queue : []
  readonly property int laneIndex: {
    var currentId = playerState.current ? playerState.current.entryId : ""
    return laneRows.findIndex(function(row) { return row.entryId === currentId })
  }
  readonly property var playlistContext: logic && !queueLane ? logic.sourceContext : null
  readonly property int lanePosition: playlistContext ? Number(playlistContext.index || 0) : laneIndex + 1
  readonly property int laneTotal: playlistContext ? Number(playlistContext.total || 0) : laneRows.length
  readonly property real laneProgress: laneTotal > 0 ? Math.min(1, Math.max(0, lanePosition / laneTotal)) : 0
  readonly property var nextRow: laneIndex >= 0 && laneIndex + 1 < laneRows.length ? laneRows[laneIndex + 1] : null
  readonly property real laneRemaining: {
    var total = 0
    for (var i = Math.max(0, laneIndex + 1); i < laneRows.length; ++i) {
      var duration = Number((laneRows[i].media || ({})).duration)
      if (duration > 0) total += duration
    }
    return total
  }
  // A playlist waiting behind My queue resumes when My queue runs out.
  readonly property var waitingPlaylist: logic && queueLane && playerState.lanes && playerState.lanes.source
    && playerState.lanes.source.count > 0 ? logic.sourceContext : null
  readonly property string nowState: !(logic && logic.hasTrack) ? "idle"
    : playerPhase === "error" ? "error"
    : playerPhase === "loading" ? "loading"
    : playerPhase === "paused" ? "paused"
    : nextRow ? "playing" : "last"
  readonly property color nowColor: nowState === "error" ? Color.urgent
    : (nowState === "idle" || nowState === "paused" ? dim : Color.accent)

  implicitWidth: Style.space(226)
  color: "transparent"

  function trackCount(count) {
    return count + " " + L.plural(count, L.tr("трек"), L.tr("трека"), L.tr("треков"))
  }
  function span(seconds) {
    var minutes = Math.round(Number(seconds || 0) / 60)
    if (minutes <= 0) return ""
    return minutes >= 60 ? Math.floor(minutes / 60) + L.tr(" ч ") + (minutes % 60) + L.tr(" мин") : minutes + L.tr(" мин")
  }
  function joined(parts) { return parts.filter(function(part) { return part !== "" }).join(" · ") }
  function nowHead() {
    var place = laneTotal > 0 ? lanePosition + " / " + laneTotal : ""
    var lane = queueLane ? L.tr("МОЯ ОЧЕРЕДЬ") + " " : ""
    if (nowState === "idle") return L.tr("СЕЙЧАС")
    if (nowState === "error") return joined([L.tr("ОШИБКА ПОТОКА"), place])
    if (nowState === "last") return joined([L.tr("ПОСЛЕДНИЙ"), lane + place])
    var next = nextRow && laneTotal > 0 ? lane + Math.min(laneTotal, lanePosition + 1) + " / " + laneTotal : ""
    if (nowState === "loading") return joined([L.tr("ЗАГРУЗКА"), lane + place])
    if (nowState === "paused") return joined([L.tr("ПАУЗА"), lane + place])
    return joined([L.tr("ДАЛЕЕ"), next])
  }
  // What takes over when the active lane runs out.
  function afterLane() {
    if (waitingPlaylist) return L.tb(waitingPlaylist.name || L.tr("Плейлист"))
    if (!queueLane && myQueue.count > 0) return L.tr("Моя очередь")
    return ""
  }
  readonly property var myQueue: logic ? logic.myQueue : ({ count: 0, duration: null })
  function nowTitle() {
    if (nowState === "idle") return L.tr("Ничего не играет")
    if (nowState === "error") return L.tb(((playerState.current || ({})).media || ({})).title || "")
    if (nextRow) return L.tb((nextRow.media || ({})).title || "")
    var after = afterLane()
    return after !== "" ? L.tr("Дальше — ") + after : L.tr("Конец очереди")
  }
  function nowSubtitle() {
    if (nowState === "idle") return L.tr("выберите плейлист или нажмите /")
    if (nowState === "error") {
      var error = playerState.error || ({})
      return L.tb(error.message || L.tr("Не удалось открыть поток"))
    }
    var after = afterLane()
    if (!nextRow) {
      if (waitingPlaylist) return waitingPlaylist.index + " / " + waitingPlaylist.total
      if (after !== "") return queueMeta()
      return L.tr("после этого — тишина")
    }
    if (waitingPlaylist) return L.tr("затем ") + joined([after, waitingPlaylist.index + " / " + waitingPlaylist.total])
    if (after !== "") return L.tr("затем ") + joined([after, String(myQueue.count), span(myQueue.duration)])
    return joined([L.tr("очередь закончится"), span(laneRemaining)])
  }
  function queueMeta() {
    if (queueActive) return (queueCount > 0 ? L.tr("играет") : L.tr("пусто"))
    if (queueCount === 0) return L.tr("пусто")
    var text = queueCount + " " + L.plural(queueCount, L.tr("видео"), "видео", "видео")
    var minutes = Math.round(queueDuration / 60)
    if (minutes > 0) text += " · " + (minutes >= 60 ? Math.floor(minutes / 60) + L.tr(" ч ") + (minutes % 60) + L.tr(" мин") : minutes + L.tr(" мин"))
    return text
  }
  function fade(alpha) { return Qt.rgba(foreground.r, foreground.g, foreground.b, alpha) }
  function soft(alpha) { return Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, alpha) }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(1, Style.space(1))
    color: root.fade(.08)
  }

  component FooterButton: Rectangle {
    id: button
    property string icon: ""
    property string label: ""
    property bool selected: false
    property bool badge: false
    signal clicked()

    width: Style.space(34)
    height: Style.space(32)
    radius: Style.space(6)
    color: selected ? root.soft(.18) : (buttonMouse.containsMouse ? root.fade(.05) : "transparent")
    border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: label
    Keys.onReturnPressed: button.clicked()
    Keys.onSpacePressed: button.clicked()

    Icon {
      anchors.centerIn: parent
      name: button.icon
      size: Style.space(16)
      color: button.selected ? Color.accent : root.dim
    }
    Rectangle {
      visible: button.badge
      x: Style.space(22)
      y: Style.space(6)
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Color.accent
    }
    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: button.clicked()
    }
  }

  // Downloads in the footer: a ring fills with overall progress, a red dot marks failures.
  component DownloadsKey: Rectangle {
    id: key
    property bool selected: false
    signal clicked()

    readonly property bool busy: root.downloadsActive > 0
    readonly property real progress: busy && root.downloadsProgress >= 0 ? root.downloadsProgress : 0

    width: Style.space(34)
    height: Style.space(32)
    radius: Style.space(6)
    color: selected || busy ? root.soft(selected ? .18 : .1) : (keyMouse.containsMouse ? root.fade(.05) : "transparent")
    border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: keyTip.text
    Keys.onReturnPressed: key.clicked()
    Keys.onSpacePressed: key.clicked()

    Canvas {
      id: ring
      visible: key.busy
      anchors.centerIn: parent
      width: Style.space(24)
      height: width
      property real value: key.progress
      onValueChanged: requestPaint()
      onVisibleChanged: requestPaint()
      onPaint: {
        var context = getContext("2d")
        var line = Math.max(1.5, Style.space(2))
        var radius = width / 2 - line / 2
        context.reset()
        context.lineWidth = line
        context.strokeStyle = root.fade(.2)
        context.beginPath(); context.arc(width / 2, height / 2, radius, 0, Math.PI * 2); context.stroke()
        if (value <= 0) return
        context.strokeStyle = Color.accent
        context.beginPath()
        context.arc(width / 2, height / 2, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * value)
        context.stroke()
      }
    }
    Icon {
      anchors.centerIn: parent
      name: "download"
      size: Style.space(key.busy ? 11 : 16)
      color: key.selected || key.busy ? Color.accent : root.dim
    }
    Rectangle {
      visible: root.downloadsFailed > 0
      x: Style.space(23)
      y: Style.space(4)
      width: Style.space(7)
      height: width
      radius: width / 2
      color: Color.urgent
      border.width: Math.max(1, Style.space(1.5))
      border.color: root.color
    }
    MouseArea {
      id: keyMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: key.clicked()
    }
    PanelToolTip {
      id: keyTip
      visible: keyMouse.containsMouse
      fontFamily: root.fontFamily
      text: {
        var parts = []
        if (key.busy) parts.push(L.tr("качается: ") + root.downloadsActive
          + (root.downloadsProgress >= 0 ? " · " + Math.round(root.downloadsProgress * 100) + "%" : ""))
        if (root.downloadsFailed > 0) parts.push(L.tr("ошибок: ") + root.downloadsFailed)
        return L.tr("Загрузки") + (parts.length ? "\n" + parts.join(" · ") : "")
      }
    }
  }

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(10)
    spacing: Style.space(2)

    // Now: what comes next rather than what plays (the player bar already shows that).
    Rectangle {
      id: nowCard
      readonly property bool selected: !root.settingsActive && root.page === 0
      readonly property bool idle: root.nowState === "idle"
      width: parent.width
      height: Style.space(68)
      radius: Style.space(6)
      color: idle ? (nowMouse.containsMouse ? root.fade(.08) : root.fade(.04))
        : (nowMouse.containsMouse ? root.fade(.12) : root.fade(.08))
      border.width: selected || activeFocus || idle ? Math.max(1, Style.space(1)) : 0
      border.color: selected || activeFocus ? Color.accent : root.fade(.1)
      activeFocusOnTab: true
      Accessible.role: Accessible.Button
      Accessible.name: L.tr("Сейчас") + ". " + nowTitle.text + ". " + nowSubtitle.text
      Keys.onReturnPressed: root.navigate(0)
      Keys.onSpacePressed: root.navigate(0)

      Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(nowCard.idle ? 40 : 10)
        spacing: Style.space(4)
        Text {
          width: parent.width
          text: root.nowHead()
          color: root.nowColor
          font.family: root.fontFamily
          font.pixelSize: Style.space(9)
          font.bold: true
          font.letterSpacing: 1.2
          elide: Text.ElideRight
        }
        Text {
          id: nowTitle
          width: parent.width
          textFormat: Text.PlainText
          text: root.nowTitle()
          color: nowCard.idle ? root.fade(.7) : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          id: nowSubtitle
          width: parent.width
          textFormat: Text.PlainText
          text: root.nowSubtitle()
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          elide: Text.ElideRight
        }
        Rectangle {
          width: parent.width
          height: Math.max(2, Style.space(2))
          radius: height / 2
          color: root.fade(.14)
          Rectangle {
            visible: !nowCard.idle
            width: parent.width * root.laneProgress
            height: parent.height
            radius: height / 2
            color: root.nowColor
          }
        }
      }
      Icon {
        visible: nowCard.idle
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        name: "audio-lines"
        size: Style.space(18)
        color: root.dim
        opacity: .5
      }
      MouseArea {
        id: nowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.navigate(0)
      }
    }

    Item { width: 1; height: Style.space(4) }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Rectangle {
        id: libraryButton
        readonly property bool selected: !root.settingsActive && (root.page === 2 || root.page === 3)
        width: parent.width - searchButton.width - parent.spacing
        height: Style.space(36)
        radius: Style.space(6)
        color: selected ? root.soft(.18) : (libraryMouse.containsMouse ? root.fade(.1) : root.fade(.04))
        border.width: selected || activeFocus ? Math.max(1, Style.space(1)) : 0
        border.color: Color.accent
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: L.tr("Медиатека")
        Keys.onReturnPressed: root.navigate(2)
        Keys.onSpacePressed: root.navigate(2)

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          spacing: Style.space(10)
          Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: "library"
            size: Style.space(16)
            color: libraryButton.selected ? Color.accent : root.dim
          }
          Text {
            width: parent.width - Style.space(16) - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: L.tr("Медиатека")
            color: libraryButton.selected ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            font.bold: true
            elide: Text.ElideRight
          }
        }
        MouseArea {
          id: libraryMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.navigate(2)
        }
      }

      // Search opens its own page, so the rail keeps only a key for it (also bound to "/").
      Rectangle {
        id: searchButton
        readonly property bool selected: !root.settingsActive && root.page === 1
        width: Style.space(36)
        height: Style.space(36)
        radius: Style.space(6)
        color: selected ? root.soft(.18) : (searchMouse.containsMouse ? root.fade(.1) : root.fade(.04))
        border.width: selected || activeFocus ? Math.max(1, Style.space(1)) : 0
        border.color: Color.accent
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: L.tr("Поиск") + " (/)"
        Keys.onReturnPressed: root.searchRequested()
        Keys.onSpacePressed: root.searchRequested()

        Icon {
          anchors.centerIn: parent
          name: "search"
          size: Style.space(15)
          color: searchButton.selected ? Color.accent : root.dim
        }
        MouseArea {
          id: searchMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.searchRequested()
        }
      }
    }

    Row {
      width: parent.width
      height: Style.space(34)
      leftPadding: Style.space(12)
      rightPadding: Style.space(6)
      topPadding: Style.space(14)
      Text {
        width: parent.width - parent.leftPadding - parent.rightPadding - countLabel.width
        text: L.tr("ПЛЕЙЛИСТЫ")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
      Text {
        id: countLabel
        text: String(root.playlists.length)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.space(10)
        font.bold: true
        font.letterSpacing: 1.5
      }
    }

    Flickable {
      id: playlistFlick
      width: parent.width
      height: Math.max(0, parent.height - y - Style.space(50))
      contentWidth: width
      contentHeight: playlistColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      Column {
        id: playlistColumn
        width: playlistFlick.width
        spacing: Style.space(2)
        Rectangle {
          id: queueRow
          width: parent.width
          height: Style.space(38)
          radius: Style.space(6)
          color: queueMouse.containsMouse ? root.fade(.05) : "transparent"
          border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
          border.color: Color.accent
          activeFocusOnTab: true
          Accessible.role: Accessible.Button
          Accessible.name: L.tr("Моя очередь")
          Keys.onReturnPressed: root.myQueueRequested()
          Keys.onSpacePressed: root.myQueueRequested()

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(6)
            spacing: Style.space(10)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(30)
              height: width
              radius: Style.space(4)
              color: root.soft(.16)
              Icon {
                anchors.centerIn: parent
                name: "list-video"
                size: Style.space(15)
                color: Color.accent
              }
            }
            Column {
              width: parent.width - Style.space(30) - parent.spacing - (queueEq.visible ? queueEq.width + parent.spacing : 0)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: L.tr("Моя очередь")
                color: root.queueActive ? Color.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
                font.bold: root.queueActive
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: root.queueMeta()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                elide: Text.ElideRight
              }
            }
            Equalizer {
              id: queueEq
              visible: root.queueActive && root.queueCount > 0
              anchors.verticalCenter: parent.verticalCenter
              running: root.playlistPlaying
              maxHeight: Style.space(12)
            }
          }
          MouseArea {
            id: queueMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.myQueueRequested()
          }
        }

        Rectangle {
          width: parent.width
          height: Math.max(1, Style.space(1))
          color: root.fade(.08)
        }

        Repeater {
          model: root.playlists.slice(0, 40)
          delegate: Rectangle {
            id: row
            required property var modelData
            readonly property string playlistId: String(modelData.id || modelData.playlistId || "")
            readonly property bool selected: !root.settingsActive && playlistId !== "" && playlistId === root.openPlaylistId
            readonly property bool current: playlistId !== "" && playlistId === root.playingPlaylistId
            readonly property bool playing: current && !root.queueActive
            readonly property bool paused: current && root.queueActive
            readonly property int count: Number(modelData.itemCount || 0)
            width: parent.width
            height: Style.space(38)
            radius: Style.space(6)
            color: selected ? root.fade(.04) : (rowMouse.containsMouse ? root.fade(.05) : "transparent")
            border.width: activeFocus ? Math.max(1, Style.space(1)) : 0
            border.color: Color.accent
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: nameLabel.text
            Keys.onReturnPressed: root.playlistRequested(playlistId)
            Keys.onSpacePressed: root.playlistRequested(playlistId)

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              spacing: Style.space(10)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: width
                radius: Style.space(4)
                color: root.fade(.08)
                clip: true
                CatalogImage {
                  anchors.fill: parent
                  requestedSource: String(row.modelData.thumbnailUrl || "")
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fillMode: Image.PreserveAspectCrop
                }
              }
              Column {
                width: parent.width - Style.space(30) - parent.spacing - (rowEq.visible ? rowEq.width + parent.spacing : 0)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  id: nameLabel
                  width: parent.width
                  textFormat: Text.PlainText
                  text: L.tb(row.modelData.name || row.modelData.title || L.tr("Плейлист"))
                  color: row.playing || row.selected ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(12)
                  font.bold: row.playing || row.selected
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.trackCount(row.count) + (row.playing ? " · " + L.tr("играет")
                    : row.paused ? " · " + L.tr("на паузе") + (root.sourcePlace !== "" ? " " + root.sourcePlace : "") : "")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(10)
                  elide: Text.ElideRight
                }
              }
              Equalizer {
                id: rowEq
                visible: row.playing
                anchors.verticalCenter: parent.verticalCenter
                running: root.playlistPlaying
                maxHeight: Style.space(12)
              }
            }
            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.playlistRequested(row.playlistId)
            }
          }
        }
      }
    }
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(10)
    height: Style.space(41)

    Rectangle {
      anchors.top: parent.top
      width: parent.width
      height: Math.max(1, Style.space(1))
      color: root.fade(.08)
    }
    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      spacing: Style.space(2)
      FooterButton {
        icon: "rss"
        label: L.tr("Подписки")
        selected: !root.settingsActive && root.page === 4
        badge: root.newCount > 0
        onClicked: root.navigate(4)
      }
      DownloadsKey {
        selected: !root.settingsActive && root.page === 5
        onClicked: root.navigate(5)
      }
    }
    FooterButton {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      icon: "settings"
      label: L.tr("Настройки")
      selected: root.settingsActive
      onClicked: root.settingsRequested()
    }
  }
}
