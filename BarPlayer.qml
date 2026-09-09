import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

Item {
  id: root
  property var bar: null
  property var logic: null
  property var hostWidget: null
  readonly property var preferences: logic && logic.stateData && logic.stateData.preferences ? logic.stateData.preferences : ({})
  readonly property bool hasTrack: logic ? logic.hasTrack : false
  readonly property bool playing: logic ? logic.playing : false
  readonly property bool loading: logic ? logic.busy : false
  readonly property bool showControls: preferences.showControls === undefined ? true : Boolean(preferences.showControls)
  readonly property bool showCover: preferences.showCover === undefined ? true : Boolean(preferences.showCover)
  readonly property bool showAuthor: preferences.showAuthor === undefined ? true : Boolean(preferences.showAuthor)
  readonly property bool showTitle: preferences.showTitle === undefined ? true : Boolean(preferences.showTitle)
  readonly property bool showProgress: preferences.showProgress === undefined ? true : Boolean(preferences.showProgress)
  readonly property real informationWidth: Number(preferences.textWidth || 220)
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var media: hasTrack ? logic.stateData.current.media : ({})
  implicitWidth: row.width + Style.space(10)
  implicitHeight: bar ? bar.barSize : Style.bar.sizeHorizontal

  Row {
    id: row; anchors.centerIn: parent; spacing: Style.space(5)
    Repeater {
      model: root.showControls ? [
        { icon: "󰒮", command: "previous", tip: "Предыдущий" },
        { icon: root.playing ? "󰏤" : "󰐊", command: "toggle_pause", tip: root.playing ? "Пауза" : "Продолжить" },
        { icon: "󰒭", command: "next", tip: "Следующий" }
      ] : []
      delegate: Item {
        required property var modelData
        width: Style.space(30); height: root.implicitHeight; opacity: root.hasTrack ? 1 : .35
        Text { anchors.centerIn: parent; text: modelData.icon; textFormat: Text.PlainText; color: root.foreground; font.family: root.fontFamily; font.pixelSize: 19 }
        MouseArea {
          anchors.fill: parent; enabled: root.hasTrack; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: root.logic.request(modelData.command, ({}))
          onEntered: if (root.bar) root.bar.showTooltip(parent, modelData.tip)
          onExited: if (root.bar) root.bar.hideTooltip(parent)
        }
      }
    }
    BorderSurface {
      visible: root.showCover; width: Style.space(20); height: width; anchors.verticalCenter: parent.verticalCenter
      radius: Style.space(2); color: Style.normalFillFor(root.foreground, Color.accent); borderSpec: Border.none()
      CatalogImage {
        anchors.fill: parent
        requestedSource: String(root.media.thumbnailUrl || "")
        foreground: root.foreground
        fontFamily: root.fontFamily
        fillMode: Image.PreserveAspectCrop
      }
      Text {
        anchors.centerIn: parent
        visible: root.loading
        text: "󰦖"
        color: Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        RotationAnimator on rotation {
          running: parent.visible
          from: 0
          to: 360
          duration: 800
          loops: Animation.Infinite
        }
      }
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.logic.toggle() }
    }
    Item {
      id: informationSlot
      visible: root.showAuthor || root.showTitle; width: root.informationWidth; height: root.implicitHeight; clip: true
      Text {
        id: informationLabel
        anchors.verticalCenter: parent.verticalCenter
        width: root.preferences.marquee === true ? implicitWidth : parent.width
        textFormat: Text.PlainText
        text: {
          if (!root.hasTrack) return root.logic && root.logic.error ? "Ошибка OmaTube" : "OmaTube"
          var parts = []
          if (root.showAuthor && root.media.author) parts.push(String(root.media.author))
          if (root.showTitle) parts.push(String(root.media.title || root.media.videoId || ""))
          return parts.join(" — ")
        }
        color: root.logic && root.logic.error ? Color.urgent : root.foreground; font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: root.preferences.marquee === true ? Text.ElideNone : Text.ElideRight
      }
      SequentialAnimation {
        running: root.preferences.marquee === true && informationLabel.implicitWidth > informationSlot.width
        loops: Animation.Infinite
        PauseAnimation { duration: 1200 }
        NumberAnimation { target: informationLabel; property: "x"; to: informationSlot.width - informationLabel.implicitWidth; duration: Math.max(1000, informationLabel.implicitWidth * 18); easing.type: Easing.Linear }
        PauseAnimation { duration: 900 }
        NumberAnimation { target: informationLabel; property: "x"; to: 0; duration: 350 }
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.logic.toggle()
        onEntered: if (root.bar) root.bar.showTooltip(parent,
          root.loading ? root.logic.loaderTooltip : (root.hasTrack
            ? String(root.media.title || "OmaTube") : "Открыть OmaTube"))
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
