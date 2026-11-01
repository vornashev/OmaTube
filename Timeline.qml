import QtQuick
import qs.Commons
import qs.Ui
import "i18n.js" as L

// Seek line with chapters (1 px gaps), SponsorBlock segments, a storyboard preview on hover,
// dragging with a ghost mark, click/keys/wheel seeking and the "sponsor ahead" tag.
Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property color gapColor: Color.background
  // Thin variant lives on a panel edge: 3 px at rest, 8 px while the panel is hovered.
  property bool thin: true
  property bool expanded: false
  property real restHeight: Style.space(3)
  property real activeHeight: Style.space(8)
  // How far the cursor guide line reaches below the bar (through the panel row).
  property real guideHeight: 0
  property bool showUpcoming: true

  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var media: stateData.current ? stateData.current.media || ({}) : ({})
  readonly property real duration: Number(stateData.duration || media.duration || 0)
  readonly property real livePosition: Number(stateData.position || 0)
  readonly property bool seekable: stateData.canSeek === true && duration > 0
  readonly property var info: stateData.info || ({})
  readonly property var chapters: info.chapters || []
  readonly property var storyboard: info.storyboard || null
  readonly property var segments: stateData.sponsor && stateData.sponsor.segments ? stateData.sponsor.segments : []
  readonly property var upcoming: stateData.sponsor ? stateData.sponsor.upcoming || null : null
  readonly property var categoryColors: ({
    sponsor: "#00d400", intro: "#00ffff", outro: "#4a4aff", selfpromo: "#ffff00",
    interaction: "#cc00ff", preview: "#008fd6", music_offtopic: "#ff9900"
  })
  readonly property var categoryLabels: ({
    sponsor: L.tr("Спонсор"), intro: L.tr("Интро"), outro: L.tr("Концовка"), selfpromo: L.tr("Самореклама"),
    interaction: L.tr("Напоминание"), preview: L.tr("Превью"), music_offtopic: L.tr("Не музыка")
  })

  property real hoverX: -1
  property bool dragging: false
  property bool dragCancelled: false
  property real dragOrigin: 0
  property real dragTarget: 0
  property real pressX: 0
  property real pendingTarget: -1

  readonly property bool hot: dragging || hoverX >= 0
  property real barHeight: thin ? (expanded || hot ? activeHeight : restHeight) : activeHeight
  readonly property real position: dragging ? dragTarget : (pendingTarget >= 0 ? pendingTarget : livePosition)
  readonly property real hoverSeconds: hoverX >= 0 ? secondsAt(hoverX) : -1
  readonly property real previewSeconds: dragging ? dragTarget : hoverSeconds

  signal flashed(string text)
  signal scrubbing(bool active, real seconds)

  implicitHeight: barHeight
  height: barHeight
  activeFocusOnTab: seekable
  Accessible.role: Accessible.Slider
  Accessible.name: L.tr("Позиция воспроизведения")

  Behavior on barHeight { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value || 0)))
    var rest = seconds % 60
    return Math.floor(seconds / 60) + ":" + (rest < 10 ? "0" : "") + rest
  }
  function formatDelta(value) {
    var sign = value < 0 ? "−" : "+"
    return sign + formatTime(Math.abs(value))
  }
  function xAt(seconds) { return duration > 0 ? width * Math.max(0, Math.min(1, seconds / duration)) : 0 }
  function secondsAt(x) { return duration > 0 ? Math.max(0, Math.min(duration, duration * x / Math.max(1, width))) : 0 }
  function chapterAt(seconds) {
    var found = -1
    for (var i = 0; i < chapters.length; ++i) if (seconds >= Number(chapters[i].start)) found = i
    return found
  }
  function chapterLabel(seconds) {
    var index = chapterAt(seconds)
    if (index < 0) return ""
    return L.tr("Глава ") + (index + 1) + "/" + chapters.length + " · «" + String(chapters[index].title || "") + "»"
  }
  // Boundary under the cursor (±3 px) so a click on a gap jumps exactly to the chapter start.
  function boundaryNear(x) {
    for (var i = 1; i < chapters.length; ++i)
      if (Math.abs(xAt(Number(chapters[i].start)) - x) <= Style.space(3)) return Number(chapters[i].start)
    return -1
  }

  function seekTo(seconds, flash) {
    if (!seekable || !logic) return
    var target = Math.max(0, Math.min(duration - 1, seconds))
    pendingTarget = target
    settleTimer.restart()
    logic.request("seek", { seconds: target })
    if (flash) flashed(flash)
  }
  function seekBy(delta) {
    var base = pendingTarget >= 0 ? pendingTarget : livePosition
    seekTo(base + delta, (delta > 0 ? "+" : "−") + (Math.abs(delta) >= 60 ? Math.round(Math.abs(delta) / 60) + L.tr(" мин") : Math.abs(delta) + L.tr(" с")))
  }
  function chapterStep(direction) {
    if (chapters.length === 0) return
    var base = pendingTarget >= 0 ? pendingTarget : livePosition
    var index = chapterAt(base)
    // "Previous" restarts the current chapter unless we are at its very beginning.
    if (direction < 0 && index >= 0 && base - Number(chapters[index].start) > 3) index += 1
    var target = Math.max(0, Math.min(chapters.length - 1, index + direction))
    seekTo(Number(chapters[target].start), L.tr("гл. ") + (target + 1) + "/" + chapters.length)
  }

  Timer { id: settleTimer; interval: 900; onTriggered: root.pendingTarget = -1 }

  Keys.onPressed: event => {
    if (!root.seekable) return
    var step = event.modifiers & Qt.ShiftModifier ? 60 : 10
    if (event.key === Qt.Key_Escape && root.dragging) {
      root.dragCancelled = true
      root.dragging = false
      root.scrubbing(false, root.livePosition)
    } else if (event.key === Qt.Key_Left) root.seekBy(-step)
    else if (event.key === Qt.Key_Right) root.seekBy(step)
    else if (event.key === Qt.Key_BracketLeft) root.chapterStep(-1)
    else if (event.key === Qt.Key_BracketRight) root.chapterStep(1)
    else return
    event.accepted = true
  }

  Item {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.barHeight
    clip: true

    Rectangle { anchors.fill: parent; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14) }
    Rectangle {
      // Light fill between the playhead and the cursor shows how far a click would jump.
      visible: root.hoverX >= 0 && !root.dragging && root.seekable
      x: Math.min(root.xAt(root.position), root.hoverX)
      width: Math.abs(root.hoverX - root.xAt(root.position))
      height: parent.height
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .22)
    }
    Rectangle { width: root.xAt(root.position); height: parent.height; color: Color.accent }
    Repeater {
      model: root.duration > 0 ? root.segments : []
      delegate: Rectangle {
        required property var modelData
        x: root.xAt(modelData.start)
        width: Math.max(Style.space(2), root.xAt(modelData.end) - root.xAt(modelData.start))
        height: parent.height
        color: root.categoryColors[modelData.category] || Color.accent
        opacity: modelData.action === "off" ? .35 : 1
      }
    }
    Rectangle {
      // Indeterminate stripe while the stream is being resolved.
      id: loadingStripe
      visible: root.stateData.state === "loading"
      width: parent.width * .3
      height: parent.height
      color: Color.accent
      opacity: .8
      NumberAnimation on x {
        running: loadingStripe.visible
        loops: Animation.Infinite
        from: -loadingStripe.width
        to: track.width
        duration: 1100
        easing.type: Easing.InOutQuad
      }
    }
    Repeater {
      model: root.duration > 0 ? root.chapters : []
      delegate: Rectangle {
        required property var modelData
        visible: Number(modelData.start) > 1
        x: Math.round(root.xAt(Number(modelData.start))) - width
        width: Math.max(1, Style.space(1))
        height: parent.height
        color: root.gapColor
      }
    }
  }

  Rectangle {
    // Ghost mark: where the drag started (playback continues from there until release).
    visible: root.dragging
    x: root.xAt(root.dragOrigin) - width / 2
    anchors.verticalCenter: track.verticalCenter
    width: Math.max(2, Style.space(2))
    height: root.barHeight + Style.space(8)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .7)
  }
  Rectangle {
    visible: root.guideHeight > 0 && (root.dragging || root.hoverX >= 0) && root.seekable
    x: (root.dragging ? root.xAt(root.dragTarget) : root.hoverX) - width / 2
    y: track.y + track.height
    width: Math.max(1, Style.space(1))
    height: root.guideHeight
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.dragging ? .5 : .3)
  }
  Rectangle {
    visible: root.dragging
    x: root.xAt(root.dragTarget) - width / 2
    anchors.verticalCenter: track.verticalCenter
    width: Style.space(14)
    height: width
    radius: width / 2
    color: Color.accent
    border.width: Math.max(1, Style.space(1.5))
    border.color: Qt.rgba(1, 1, 1, .75)
  }

  MouseArea {
    id: mouse
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: track.verticalCenter
    height: Math.max(Style.space(14), root.barHeight + Style.space(8))
    enabled: root.seekable
    hoverEnabled: true
    preventStealing: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPositionChanged: mouse => {
      root.hoverX = Math.max(0, Math.min(width, mouse.x))
      if (!pressed || root.dragCancelled) return
      if (!root.dragging && Math.abs(mouse.x - root.pressX) > Style.space(3)) {
        root.dragging = true
        root.dragOrigin = root.livePosition
      }
      if (root.dragging) {
        root.dragTarget = root.secondsAt(root.hoverX)
        root.scrubbing(true, root.dragTarget)
      }
    }
    onExited: if (!pressed) root.hoverX = -1
    onPressed: mouse => {
      root.forceActiveFocus()
      root.pressX = mouse.x
      root.dragCancelled = false
    }
    onReleased: mouse => {
      if (root.dragCancelled) { root.dragCancelled = false; return }
      if (root.dragging) {
        root.dragging = false
        root.scrubbing(false, root.dragTarget)
        root.seekTo(root.dragTarget, "")
      } else {
        var boundary = root.boundaryNear(mouse.x)
        root.seekTo(boundary >= 0 ? boundary : root.secondsAt(mouse.x), "")
      }
      if (!containsMouse) root.hoverX = -1
    }
    onCanceled: { root.dragging = false; root.scrubbing(false, root.livePosition) }
    onWheel: wheel => {
      var notches = wheel.angleDelta.y / 120
      if (notches === 0) return
      root.seekBy(notches > 0 ? 5 : -5)
    }
  }

  Rectangle {
    id: preview
    visible: root.seekable && root.previewSeconds >= 0 && (root.hoverX >= 0 || root.dragging)
    readonly property real anchorX: root.dragging ? root.xAt(root.dragTarget) : root.hoverX
    x: Math.max(0, Math.min(root.width - width, anchorX - width / 2))
    y: track.y - height - Style.space(6)
    z: 10
    width: Style.space(176)
    height: previewColumn.implicitHeight
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .98)
    border.width: Math.max(1, Style.space(1))
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14)

    Column {
      id: previewColumn
      width: parent.width
      Item {
        id: frame
        readonly property var board: root.storyboard
        readonly property int perSheet: board ? board.rows * board.columns : 1
        readonly property int frameIndex: board ? Math.floor(Math.max(0, root.previewSeconds) / Math.max(.1, board.interval)) : 0
        readonly property int sheet: board ? Math.max(0, Math.min(board.urls.length - 1, Math.floor(frameIndex / perSheet))) : 0
        readonly property int cell: frameIndex - Math.floor(frameIndex / perSheet) * perSheet
        visible: board !== null
        width: parent.width
        height: visible ? Math.round(width * 9 / 16) : 0
        clip: true
        Image {
          anchors.fill: parent
          asynchronous: true
          cache: true
          fillMode: Image.PreserveAspectCrop
          source: frame.board && preview.visible ? String(frame.board.urls[frame.sheet] || "") : ""
          sourceClipRect: frame.board ? Qt.rect((frame.cell % frame.board.columns) * frame.board.width,
            Math.floor(frame.cell / frame.board.columns) * frame.board.height, frame.board.width, frame.board.height) : Qt.rect(0, 0, 0, 0)
        }
      }
      Column {
        width: parent.width
        topPadding: Style.space(8)
        bottomPadding: Style.space(8)
        leftPadding: Style.space(10)
        rightPadding: Style.space(10)
        spacing: Style.space(3)
        Row {
          spacing: Style.space(7)
          Text {
            id: previewTime
            text: root.formatTime(root.previewSeconds)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.space(13)
            font.bold: true
          }
          Text {
            anchors.baseline: previewTime.baseline
            text: root.formatDelta(root.previewSeconds - (root.dragging ? root.dragOrigin : root.livePosition))
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.space(10)
            font.bold: true
          }
        }
        Text {
          visible: text !== ""
          width: parent.width - Style.space(20)
          textFormat: Text.PlainText
          text: root.chapterLabel(root.previewSeconds)
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }
    }
  }

  Item {
    id: upcomingTag
    visible: root.showUpcoming && root.upcoming !== null && root.duration > 0 && !preview.visible
    readonly property real anchorX: root.upcoming ? root.xAt(root.upcoming.start) : 0
    readonly property color tone: root.upcoming ? root.categoryColors[root.upcoming.category] || Color.accent : Color.accent
    x: Math.max(0, Math.min(root.width - width, anchorX - Style.space(12)))
    y: track.y - height - Style.space(4)
    z: 9
    width: tagBox.width
    height: tagBox.height + Style.space(6)

    Rectangle {
      x: upcomingTag.anchorX - upcomingTag.x
      anchors.bottom: parent.bottom
      width: Math.max(1, Style.space(2))
      height: Style.space(6)
      color: upcomingTag.tone
    }
    Rectangle {
      id: tagBox
      width: tagRow.implicitWidth + Style.space(22)
      height: Style.space(26)
      color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, .98)
      border.width: Math.max(1, Style.space(1))
      border.color: upcomingTag.tone
      Row {
        id: tagRow
        anchors.centerIn: parent
        spacing: Style.space(7)
        Icon { anchors.verticalCenter: parent.verticalCenter; name: "skip-forward"; size: Style.space(12); color: upcomingTag.tone }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.upcoming ? (root.categoryLabels[root.upcoming.category] || L.tr("Сегмент")) + L.tr(" через ")
            + Math.max(1, Math.ceil(Number(root.upcoming.start) - root.livePosition)) + L.tr(" с") : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(11)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: L.tr("НЕ ПРОПУСКАТЬ")
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          font.bold: true
          font.letterSpacing: 1
        }
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.logic && root.upcoming) root.logic.request("sponsor_keep", { id: String(root.upcoming.id) })
      }
    }
  }
}
