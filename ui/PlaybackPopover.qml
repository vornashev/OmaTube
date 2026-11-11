import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "i18n.js" as L

Popup {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property Item anchorItem: null
  property Item boundsItem: null

  readonly property color muted: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property var stateData: logic ? logic.stateData : ({})
  readonly property var preferences: stateData.preferences || ({})
  readonly property string videoMode: logic ? logic.videoMode : "audio"
  readonly property real speed: Number(stateData.speed || 1)
  readonly property var sleepTimer: stateData.sleepTimer || null
  readonly property var qualities: [2160, 1440, 1080, 720, 480, 360]
  readonly property var sleepOptions: [
    { label: L.tr("Выкл"), mode: "off" },
    { label: L.tr("После трека"), mode: "after_track" },
    { label: L.tr("15 мин"), mode: "timer", minutes: 15 },
    { label: L.tr("30 мин"), mode: "timer", minutes: 30 },
    { label: L.tr("60 мин"), mode: "timer", minutes: 60 }
  ]

  function request(command, payload) { if (logic) logic.request(command, payload || ({})) }
  function sleepActive(option) {
    if (!sleepTimer) return option.mode === "off"
    if (option.mode !== sleepTimer.mode) return false
    if (option.mode !== "timer") return true
    return Math.abs(Math.round((Number(sleepTimer.endsAt) - Date.now() / 1000) / 60) - option.minutes) <= 1
  }
  function speedLabel(value) { return (value === 1 || value === 2 ? value : value.toFixed(2).replace(/0$/, "")) + "×" }

  parent: anchorItem
  objectName: "playbackPopover"
  readonly property Item popupOverlay: parent ? parent.Overlay.overlay : null
  readonly property point anchorPosition: {
    anchorWatcher.transform
    return popupOverlay && anchorItem ? anchorItem.mapToItem(popupOverlay, 0, 0) : Qt.point(0, 0)
  }
  readonly property point boundsPosition: {
    anchorWatcher.transform
    return popupOverlay && boundsItem ? boundsItem.mapToItem(popupOverlay, 0, 0) : Qt.point(0, 0)
  }
  width: Style.space(400)
  height: popoverColumn.implicitHeight + padding * 2
  readonly property point popupPosition: {
    anchorWatcher.transform
    if (!parent || !popupOverlay || !anchorItem) return Qt.point(0, 0)
    var bounds = boundsItem || popupOverlay
    var boundsOrigin = boundsItem ? boundsPosition : Qt.point(0, 0)
    var insetX = Math.min(Style.space(8), Math.max(0, (bounds.width - width) / 2))
    var insetY = Math.min(Style.space(8), Math.max(0, (bounds.height - height) / 2))
    var minX = boundsOrigin.x + insetX
    var maxX = boundsOrigin.x + bounds.width - width - insetX
    var minY = boundsOrigin.y + insetY
    var maxY = boundsOrigin.y + bounds.height - height - insetY
    var overlayX = Math.max(minX, Math.min(maxX, anchorPosition.x + anchorItem.width - width))
    var overlayY = Math.max(minY, Math.min(maxY, anchorPosition.y - height - Style.space(6)))
    return parent.mapFromItem(popupOverlay, overlayX, overlayY)
  }
  x: popupPosition.x
  y: popupPosition.y
  padding: Style.space(16)
  modal: false
  focus: true
  closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
  popupType: Popup.Item

  TransformWatcher {
    id: anchorWatcher
    a: root.parent
    b: root.popupOverlay
  }

  background: Rectangle {
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
    border.width: Math.max(1, Style.space(1))
    border.color: Color.accent
  }

  component Section: Text {
    textFormat: Text.PlainText
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: Style.space(10)
    font.bold: true
    font.letterSpacing: 1.5
  }

  contentItem: Column {
    id: popoverColumn
    spacing: Style.space(14)

    Section { text: L.tr("РЕЖИМ") }
    Rectangle {
      width: parent.width
      height: Style.space(35)
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: root.lineColor
      Row {
        anchors.fill: parent
        anchors.margins: Style.space(3)
        spacing: Style.space(3)
        Repeater {
          model: [{ value: "audio", label: L.tr("Аудио"), icon: "headphones" }, { value: "tile", label: L.tr("Тайл"), icon: "panels-top-left" }, { value: "floating", label: L.tr("Окно"), icon: "picture-in-picture-2" }]
          delegate: Rectangle {
            required property var modelData
            readonly property bool on: root.videoMode === modelData.value
            width: (parent.width - parent.spacing * 2) / 3
            height: parent.height
            color: on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : (modeMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
            opacity: root.logic && root.logic.videoLoading ? .5 : 1
            Row {
              anchors.centerIn: parent
              spacing: Style.space(6)
              Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: Style.space(13); color: on ? Color.accent : root.muted }
              Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: modelData.label; color: on ? root.foreground : root.muted; font.family: root.fontFamily; font.pixelSize: Style.space(11); font.bold: on }
            }
            MouseArea {
              id: modeMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.videoMode !== modelData.value && !(root.logic && root.logic.videoLoading)) root.request("video_mode", { value: modelData.value })
            }
          }
        }
      }
    }

    Section { text: L.tr("КАЧЕСТВО"); visible: root.videoMode !== "audio" }
    Row {
      visible: root.videoMode !== "audio"
      width: parent.width
      spacing: Style.space(4)
      Repeater {
        model: root.qualities
        delegate: Pill {
          required property int modelData
          width: (parent.width - parent.spacing * 5) / 6
          height: Style.space(25)
          text: modelData + "p"
          selected: Number(root.preferences.videoQuality || 1080) === modelData
          labelSize: 10
          letterSpacing: 0
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.request("video_quality", { value: modelData })
        }
      }
    }

    Section { text: L.tr("СКОРОСТЬ") }
    Rectangle {
      width: parent.width
      height: Style.space(35)
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: root.lineColor
      Row {
        anchors.fill: parent
        anchors.margins: Style.space(3)
        spacing: Style.space(3)
        Repeater {
          model: [0.75, 1, 1.25, 1.5, 1.75, 2]
          delegate: Rectangle {
            required property real modelData
            readonly property bool on: Math.abs(root.speed - modelData) < 0.01
            width: (parent.width - parent.spacing * 5) / 6
            height: parent.height
            color: on ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : (speedMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
            Text { anchors.centerIn: parent; textFormat: Text.PlainText; text: root.speedLabel(modelData); color: on ? root.foreground : root.muted; font.family: root.fontFamily; font.pixelSize: Style.space(11); font.bold: on }
            MouseArea { id: speedMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.request("speed", { value: modelData }) }
          }
        }
      }
    }

    Section { text: L.tr("ТАЙМЕР СНА") }
    Flow {
      width: parent.width
      spacing: Style.space(4)
      Repeater {
        model: root.sleepOptions
        delegate: Pill {
          required property var modelData
          height: Style.space(25)
          text: modelData.label
          selected: root.sleepActive(modelData)
          labelSize: 10
          letterSpacing: 0
          icon: modelData.mode === "off" ? "" : "moon"
          iconSize: 11
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.request("sleep_timer", { mode: modelData.mode, minutes: modelData.minutes })
        }
      }
    }

    Rectangle { width: parent.width; height: Math.max(1, Style.space(1)); color: root.lineColor }

    Column {
      width: parent.width
      spacing: Style.space(2)
      ToggleRow {
        label: L.tr("Нормализация громкости")
        description: L.tr("loudnorm в mpv, −14 LUFS")
        separator: false
        checked: root.preferences.normalize === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onToggled: root.request("setting", { key: "normalize", value: !checked })
      }
      ToggleRow {
        label: L.tr("Пропускать тишину")
        description: L.tr("ускорять паузы в подкастах")
        separator: false
        checked: root.preferences.skipSilence === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onToggled: root.request("setting", { key: "skipSilence", value: !checked })
      }
    }

    Pill {
      width: parent.width
      height: Style.space(30)
      icon: "download"
      text: L.tr("СКАЧАТЬ ТЕКУЩИЙ ТРЕК")
      enabled: Boolean(root.stateData.current)
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: { root.request("download_add", { media: root.stateData.current.media }); root.close() }
    }
  }
}
