import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root
  property var bar: null
  property var logic: null
  property var hostWidget: null
  readonly property var preferences: logic && logic.stateData && logic.stateData.preferences ? logic.stateData.preferences : ({})
  readonly property bool hasTrack: logic ? logic.hasTrack : false
  readonly property bool playing: logic ? logic.playing : false
  readonly property bool loading: logic ? logic.busy : false
  readonly property string videoMode: logic ? logic.videoMode : "audio"
  readonly property string barLayout: String(preferences.barLayout || "full")
  readonly property bool iconOnly: barLayout === "icon"
  readonly property bool compactTitle: barLayout === "title"
  readonly property bool showControls: !iconOnly && !compactTitle && (preferences.showControls === undefined ? true : Boolean(preferences.showControls))
  readonly property bool showCover: iconOnly || compactTitle || (preferences.showCover === undefined ? true : Boolean(preferences.showCover))
  readonly property bool showAuthor: !iconOnly && !compactTitle && (preferences.showAuthor === undefined ? true : Boolean(preferences.showAuthor))
  readonly property bool showTitle: !iconOnly && (compactTitle || (preferences.showTitle === undefined ? true : Boolean(preferences.showTitle)))
  readonly property bool showProgress: !iconOnly && (preferences.showProgress === undefined ? true : Boolean(preferences.showProgress))
  readonly property bool marquee: compactTitle || preferences.marquee === true
  readonly property bool hiddenWhenIdle: preferences.hideWhenIdle === true && !hasTrack
  readonly property bool buffering: Boolean(logic && logic.stateData && logic.stateData.buffering) || loading
  readonly property bool paused: hasTrack && !playing
  readonly property bool failed: Boolean(logic && logic.error)
  readonly property real informationWidth: compactTitle ? Math.min(180, Number(preferences.textWidth || 220)) : Number(preferences.textWidth || 220)
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var media: hasTrack ? logic.stateData.current.media : ({})
  readonly property real fixedContentWidth: Style.space((showControls ? 105 : 0) + (showCover ? 25 : 0)
    + (videoMode !== "audio" && !iconOnly ? 34 : 0))
  implicitWidth: hiddenWhenIdle ? 0 : fixedContentWidth + Style.space(10)
    + (showAuthor || showTitle ? informationWidth + Style.space(5) : 0)
  visible: !hiddenWhenIdle
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: row; anchors.centerIn: parent; spacing: Style.space(5)
    Repeater {
      model: root.showControls ? [
        { icon: "skip-back", command: "previous", tip: L.tr("Предыдущий") },
        { icon: root.playing ? "pause" : "play", command: "toggle_pause", tip: root.playing ? L.tr("Пауза") : L.tr("Продолжить") },
        { icon: "skip-forward", command: "next", tip: L.tr("Следующий") }
      ] : []
      delegate: Item {
        id: transportButton
        required property var modelData
        readonly property bool hovered: controlMouse.containsMouse
        readonly property bool pressed: controlMouse.pressed
        width: Style.space(30); height: root.implicitHeight; opacity: root.hasTrack ? 1 : .35
        Rectangle {
          anchors.centerIn: parent; width: Style.space(28); height: Style.space(24); radius: Style.cornerRadius
          color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b,
            transportButton.pressed ? .24 : (transportButton.hovered ? .14 : 0))
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b,
            transportButton.pressed ? .3 : (transportButton.hovered ? .18 : 0))
          scale: transportButton.pressed ? .94 : (transportButton.hovered ? 1 : .9)
          Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
          Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: transportButton.pressed ? 80 : 160; easing.type: Easing.OutCubic } }
        }
        Icon {
          anchors.centerIn: parent; name: modelData.icon; size: Style.space(14)
          color: transportButton.hovered || transportButton.pressed ? Color.accent : root.foreground
          scale: transportButton.pressed ? .9 : (transportButton.hovered ? 1.12 : 1)
          Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
          Behavior on scale { NumberAnimation { duration: transportButton.pressed ? 80 : 160; easing.type: Easing.OutCubic } }
        }
        MouseArea {
          id: controlMouse
          anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.logic.request(modelData.command, ({}))
          onEntered: if (root.bar) root.bar.showTooltip(parent, modelData.tip)
          onExited: if (root.bar) root.bar.hideTooltip(parent)
        }
      }
    }
    Item {
      visible: root.showCover || root.showAuthor || root.showTitle || (root.videoMode !== "audio" && !root.iconOnly)
      width: mediaRow.width; height: root.implicitHeight
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(24); radius: Style.cornerRadius
        color: mediaMouse.pressed ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .18) : (mediaMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1) : "transparent")
        Behavior on color { ColorAnimation { duration: 120 } }
      }
      Row {
        id: mediaRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(5)
        BorderSurface {
          visible: root.showCover; width: Style.space(20); height: width; anchors.verticalCenter: parent.verticalCenter
          opacity: root.paused ? .6 : 1
          scale: mediaMouse.pressed ? .94 : (mediaMouse.containsMouse ? 1.08 : 1)
          Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          radius: Style.space(2); color: Style.normalFillFor(root.foreground, Color.accent); borderSpec: Border.none()
          CatalogImage {
            anchors.fill: parent
            requestedSource: String(root.media.thumbnailUrl || "")
            foreground: root.foreground
            fontFamily: root.fontFamily
            fillMode: Image.PreserveAspectCrop
          }
          Icon {
            id: bufferingSpinner
            anchors.centerIn: parent
            visible: root.buffering
            name: "loader-circle"
            size: Style.space(12)
            color: Color.accent
            RotationAnimator on rotation { running: bufferingSpinner.animationVisible; from: 0; to: 360; duration: 800; loops: Animation.Infinite; onRunningChanged: if (!running && bufferingSpinner) bufferingSpinner.rotation = 0 }
          }
        }
        Rectangle {
          visible: root.videoMode !== "audio" && !root.iconOnly
          width: resolutionLabel.implicitWidth + Style.space(8); height: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          radius: Style.space(2)
          color: "transparent"
          border.width: Math.max(1, Style.space(1)); border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .4)
          Text {
            id: resolutionLabel
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: String(root.preferences.videoQuality || 1080)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Item {
          id: informationSlot
          visible: root.showAuthor || root.showTitle
          width: Math.max(0, Math.min(root.informationWidth,
            root.width - root.fixedContentWidth - Style.space(15)))
          height: root.implicitHeight
          clip: true
          Text {
            id: informationLabel
            anchors.verticalCenter: parent.verticalCenter
            width: root.marquee ? implicitWidth : parent.width
            textFormat: Text.PlainText
            text: {
              if (root.failed) return String(root.logic.error)
              if (root.buffering && root.hasTrack && root.logic.stateData.state === "loading") return L.tr("Загрузка потока…")
              if (!root.hasTrack) return "OmaTube"
              var parts = []
              if (root.showAuthor && root.media.author) parts.push(L.tb(root.media.author))
              if (root.showTitle) parts.push(String(root.media.title || root.media.videoId || ""))
              return parts.join(" — ")
            }
            color: root.failed ? Color.urgent : root.foreground; opacity: root.paused ? .55 : 1; font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: root.marquee ? Text.ElideNone : Text.ElideRight
          }
          SequentialAnimation {
            running: informationLabel.visible && informationLabel.Window.window !== null && informationLabel.Window.window.visible
              && root.marquee && informationLabel.implicitWidth > informationSlot.width
            loops: Animation.Infinite
            PauseAnimation { duration: 1200 }
            NumberAnimation { target: informationLabel; property: "x"; to: informationSlot.width - informationLabel.implicitWidth; duration: Math.max(1000, informationLabel.implicitWidth * 18); easing.type: Easing.Linear }
            PauseAnimation { duration: 900 }
            NumberAnimation { target: informationLabel; property: "x"; to: 0; duration: 350 }
          }
        }
      }
      MouseArea {
        id: mediaMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.toggle()
        onWheel: wheel => {
          if (root.preferences.wheelVolume !== true || !root.hasTrack) { wheel.accepted = false; return }
          var current = Number(root.logic.stateData.volume === undefined ? 100 : root.logic.stateData.volume)
          root.logic.request("volume", { value: Math.max(0, Math.min(100, current + (wheel.angleDelta.y > 0 ? 5 : -5))) })
        }
        onEntered: if (root.bar) root.bar.showTooltip(parent,
          root.loading ? root.logic.loaderTooltip : (root.hasTrack
            ? String(root.media.title || "OmaTube") : L.tr("Открыть OmaTube")))
        onExited: if (root.bar) root.bar.hideTooltip(parent)
      }
    }
  }
  Rectangle {
    visible: root.showProgress && Number(root.logic && root.logic.stateData ? root.logic.stateData.duration : 0) > 0
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.spacing.hairline)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .15)
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, Number(root.logic && root.logic.stateData ? root.logic.stateData.position || 0 : 0) / Number(root.logic && root.logic.stateData ? root.logic.stateData.duration || 1 : 1)))
      height: parent.height; color: Color.accent
    }
  }
}
