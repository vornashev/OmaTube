import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "vornashev.omatube"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var logic: null
  property int page: 0
  property string playlistId: ""
  property var pickerMedia: null
  property bool settingsOpen: false
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show(); if (logic) logic.refresh() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function closeForPopoutSwitch() { close() }
  function openPlaylist(id, media) { playlistId = id || ""; pickerMedia = media || null; page = 3 }
  function openPicker(media) {
    pickerMedia = media
    page = 2
    if (collectionLoader.item) {
      collectionLoader.item.section = "playlists"
      collectionLoader.item.load()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyScope
    contentWidth: panel.fittedContentWidth(Style.space(600))
    contentHeight: panel.fittedContentHeight(Style.space(780), Style.space(900))

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onPressed: event => {
        if (event.key === Qt.Key_Tab
            && (event.modifiers & Qt.ControlModifier)) {
          if (root.bar && typeof root.bar.switchPanelFrom === "function")
            root.bar.switchPanelFrom(
              root.barIdentity,
              event.modifiers & Qt.ShiftModifier ? -1 : 1
            )
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          if (root.settingsOpen) root.settingsOpen = false
          else root.close()
          event.accepted = true
        }
      }
      Column {
        id: content
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        PlayerHeader {
          id: playerHeader
          width: parent.width
          logic: root.logic
          foreground: root.foreground
          fontFamily: root.fontFamily
          onSettingsRequested: root.settingsOpen = true
        }

        Row {
          id: tabs
          width: parent.width
          height: Style.space(36)
          spacing: Style.space(4)
          Repeater {
            model: [
              { label: "СЕЙЧАС", page: 0 },
              { label: "ПОИСК", page: 1 },
              { label: "МЕДИАТЕКА", page: 2 }
            ]
            delegate: Button {
              id: tabButton
              required property var modelData
              objectName: "tab-" + modelData.page
              readonly property bool currentTab: root.page === modelData.page
                || (modelData.page === 2 && root.page === 3)
              width: (tabs.width - tabs.spacing * 2) / 3
              height: tabs.height
              text: modelData.label
              selected: currentTab
              active: currentTab
              focusable: true
              Accessible.name: text
              foreground: currentTab ? root.foreground : root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(4)
              verticalPadding: 0
              onClicked: root.page = modelData.page
            }
          }
        }

        Rectangle {
          id: errorCard
          visible: root.logic && root.logic.error !== ""
            && !(root.page === 1 && root.logic.failedOperation)
          width: parent.width
          height: visible ? errorContent.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .08)
          border.width: Math.max(1, Style.space(1))
          border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, .5)
          Row {
            id: errorContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Text {
              width: parent.width - retryError.width - dismissError.width - parent.spacing * 2
              textFormat: Text.PlainText
              text: root.logic ? root.logic.error : ""
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Button {
              focusable: true
              Accessible.name: tooltipText
              id: retryError
              width: Style.space(30)
              height: Style.space(30)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰑐"
              tooltipText: "Повторить последнее действие"
              foreground: Color.urgent
              horizontalPadding: 0
              verticalPadding: 0
              onClicked: root.logic.retryLastOperation()
            }
            Button {
              focusable: true
              Accessible.name: tooltipText
              id: dismissError
              width: Style.space(30)
              height: Style.space(30)
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰅖"
              tooltipText: "Скрыть ошибку"
              foreground: root.dim
              horizontalPadding: 0
              verticalPadding: 0
              onClicked: root.logic.dismissError()
            }
          }
        }

        StackLayout {
          width: parent.width
          height: Math.max(0, parent.height - playerHeader.height - tabs.height
            - errorCard.height - parent.spacing * (errorCard.visible ? 3 : 2))
          currentIndex: root.page

          NowPage {
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            onPlaylistPickerRequested: media => root.openPicker(media)
          }
          SearchPage {
            id: searchPage
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            onPlaylistPickerRequested: media => root.openPicker(media)
            onCollectionRequested: root.page = 2
          }
          Loader {
            id: collectionLoader
            active: true
            sourceComponent: CollectionPage {
              logic: root.logic
              foreground: root.foreground
              fontFamily: root.fontFamily
              onPlaylistRequested: playlistId => root.openPlaylist(playlistId, root.pickerMedia)
              onMediaPickerRequested: media => root.openPicker(media)
              onEntityRequested: entity => {
                root.page = 1
                searchPage.returnToCollection = true
                searchPage.openEntity(entity)
              }
            }
          }
          PlaylistPage {
            logic: root.logic
            foreground: root.foreground
            fontFamily: root.fontFamily
            playlistId: root.playlistId
            pendingMedia: root.pickerMedia
            onPendingMediaChanged: root.pickerMedia = pendingMedia
            onCloseRequested: {
              root.page = 2
              root.playlistId = ""
              root.pickerMedia = null
              if (collectionLoader.item) collectionLoader.item.load()
            }
          }
        }
      }

      Item {
        id: busyIndicator
        visible: root.logic && root.logic.busy
        z: 80
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(10)
        width: Style.space(28)
        height: width
        Text {
          anchors.centerIn: parent
          text: "󰦖"
          textFormat: Text.PlainText
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.space(18)
          RotationAnimator on rotation {
            running: busyIndicator.visible
            from: 0
            to: 360
            duration: 800
            loops: Animation.Infinite
          }
        }
        MouseArea {
          id: busyMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
        PanelToolTip {
          visible: busyMouse.containsMouse
          text: root.logic ? root.logic.loaderTooltip : "Загрузка…"
          fontFamily: root.fontFamily
        }
      }

      Item {
        anchors.fill: parent
        visible: root.settingsOpen
        z: 100

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(0, 0, 0, .7)
          MouseArea { anchors.fill: parent; onClicked: root.settingsOpen = false }
        }

        Rectangle {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.space(24), Style.space(370))
          height: settingsContent.implicitHeight + Style.space(28)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
          border.width: Math.max(1, Style.space(1))
          border.color: Color.popups.border
          MouseArea { anchors.fill: parent }

          Column {
            id: settingsContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(14)
            spacing: Style.space(5)

            Row {
              width: parent.width
              height: Style.space(34)
              Text {
                width: parent.width - closeSettings.width
                anchors.verticalCenter: parent.verticalCenter
                text: "НАСТРОЙКИ OMATUBE"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                font.letterSpacing: .8
              }
              Button {
                focusable: true
                Accessible.name: tooltipText
                id: closeSettings
                width: Style.space(30)
                height: Style.space(30)
                iconText: "󰅖"
                tooltipText: "Закрыть"
                foreground: root.dim
                horizontalPadding: 0
                verticalPadding: 0
                onClicked: root.settingsOpen = false
              }
            }

            Repeater {
              model: [
                { key: "showCover", label: "Обложка в панели" },
                { key: "showAuthor", label: "Автор в панели" },
                { key: "showTitle", label: "Название в панели" },
                { key: "showControls", label: "Кнопки управления" },
                { key: "showProgress", label: "Прогресс воспроизведения" },
                { key: "marquee", label: "Плавная прокрутка названия" },
                { key: "historyEnabled", label: "Сохранять историю" }
              ]
              delegate: Button {
                id: preferenceRow
                required property var modelData
                readonly property bool preferenceEnabled: root.logic
                  && root.logic.stateData.preferences[modelData.key] === true
                width: settingsContent.width
                height: Style.space(34)
                text: modelData.label
                iconText: preferenceEnabled ? "󰄬" : "󰄱"
                selected: preferenceEnabled
                active: preferenceEnabled
                focusable: true
                Accessible.name: text
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                iconSize: Style.font.icon
                leftAlign: true
                horizontalPadding: 0
                verticalPadding: 0
                onClicked: root.logic.request("setting", {
                  key: modelData.key,
                  value: !preferenceEnabled
                })
              }
            }

            Row {
              width: parent.width
              height: Style.space(36)
              Text {
                width: parent.width - widthControls.width
                anchors.verticalCenter: parent.verticalCenter
                text: "Ширина текста в баре"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Row {
                id: widthControls
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Button {
                  focusable: true
                  Accessible.name: "Уменьшить ширину текста"
                  width: Style.space(28); height: Style.space(28)
                  text: "−"; foreground: root.dim; horizontalPadding: 0; verticalPadding: 0
                  onClicked: root.logic.request("setting", { key: "textWidth", value: Math.max(80, Number(root.logic.stateData.preferences.textWidth || 220) - 20) })
                }
                Text {
                  width: Style.space(42)
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignHCenter
                  text: String(root.logic ? Number(root.logic.stateData.preferences.textWidth || 220) : 220)
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Button {
                  focusable: true
                  Accessible.name: "Увеличить ширину текста"
                  width: Style.space(28); height: Style.space(28)
                  text: "+"; foreground: root.dim; horizontalPadding: 0; verticalPadding: 0
                  onClicked: root.logic.request("setting", { key: "textWidth", value: Math.min(600, Number(root.logic.stateData.preferences.textWidth || 220) + 20) })
                }
              }
            }
          }
        }
      }
    }
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      if (root.page === 2 && root.pickerMedia && root.logic.lastCommand === "playlist_create"
          && root.logic.lastResult && root.logic.lastResult.id) {
        var createdId = root.logic.lastResult.id
        root.logic.request("playlist_add", { playlistId: createdId, media: root.pickerMedia })
        root.openPlaylist(createdId, null)
      }
    }
  }
}
