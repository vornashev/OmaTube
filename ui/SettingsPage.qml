import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "i18n.js" as L

Item {
  id: root

  property var logic: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string group: "bar"
  property var hiddenChannels: []
  readonly property bool compact: width < 700
  property int hiddenRequestId: 0
  property var browserStatus: null
  property string browserError: ""
  signal closeRequested()

  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color lineColor: Qt.rgba(foreground.r, foreground.g, foreground.b, .1)
  readonly property color surface: Qt.rgba(foreground.r, foreground.g, foreground.b, .05)
  readonly property var preferences: logic && logic.stateData.preferences ? logic.stateData.preferences : ({})
  readonly property var youtubeAuth: logic && logic.stateData && logic.stateData.youtubeAuth
    ? logic.stateData.youtubeAuth : ({ configured: false, authenticated: false, cookieCount: 0, browser: "chromium" })
  readonly property var groups: [
    { id: "bar", label: L.tr("Бар"), icon: "panel-top", subtitle: L.tr("Что показывать в панели Omarchy. Изменения применяются сразу.") },
    { id: "playback", label: L.tr("Воспроизведение"), icon: "circle-play", subtitle: L.tr("Звук, качество видео и история.") },
    { id: "sponsor", label: "SponsorBlock", icon: "shield-check", subtitle: L.tr("Сегменты из публичной базы SponsorBlock (запрос по хэшу, без идентификатора видео).") },
    { id: "account", label: L.tr("Аккаунт"), icon: "user-round", subtitle: L.tr("Cookies YouTube и скрытые каналы.") },
    { id: "browser", label: L.tr("Браузер"), icon: "globe", subtitle: L.tr("Расширение «Смотреть в OmaTube»: переносит видео с YouTube вместе с таймкодом.") },
    { id: "storage", label: L.tr("Хранилище"), icon: "hard-drive", subtitle: L.tr("Где лежат загрузки и библиотека.") },
    { id: "language", label: L.tr("Язык"), icon: "languages", subtitle: L.tr("Язык интерфейса. «Авто» следует языку системы; если его нет в плагине, используется English.") },
    { id: "hotkeys", label: L.tr("Хоткеи"), icon: "keyboard", subtitle: L.tr("Клавиши, которые работают в панели.") },
    { id: "about", label: L.tr("О плагине"), icon: "info", subtitle: L.tr("Версия и зависимости.") }
  ]
  readonly property var barToggles: [
    { key: "showCover", label: L.tr("Обложка") },
    { key: "showAuthor", label: L.tr("Автор") },
    { key: "showTitle", label: L.tr("Название") },
    { key: "showControls", label: L.tr("Кнопки управления") },
    { key: "showProgress", label: L.tr("Прогресс под текстом"), description: L.tr("тонкая линия 2 px") }
  ]
  readonly property var behaviorToggles: [
    { key: "marquee", label: L.tr("Бегущая строка"), description: L.tr("плавная прокрутка длинных названий") },
    { key: "hideWhenIdle", label: L.tr("Скрывать, когда ничего не играет") },
    { key: "wheelVolume", label: L.tr("Колесо мыши — громкость") }
  ]
  readonly property var barLayouts: [
    { value: "icon", label: L.tr("Иконка"), description: L.tr("минимум места") },
    { value: "title", label: L.tr("Иконка + название"), description: L.tr("бегущая строка, 180 px") },
    { value: "full", label: L.tr("Полный"), description: L.tr("кнопки, обложка, автор") }
  ]
  readonly property var panelFormats: [
    { value: "compact", label: L.tr("Компакт"), size: "400 × 660", vertical: true, blocks: [{ w: 1, h: .25, a: true }, { w: 1, h: .75, a: false }] },
    { value: "wide", label: L.tr("Широкий"), size: "1100 × 660", vertical: false, blocks: [{ w: .2, h: 1, a: false }, { w: .4, h: 1, a: true }, { w: .4, h: 1, a: false }] },
    { value: "shelf", label: L.tr("Полка"), size: L.tr("на всю ширину"), vertical: false, blocks: [{ w: .2, h: 1, a: true }, { w: .25, h: 1, a: false }, { w: .55, h: 1, a: false }] }
  ]
  readonly property var sponsorCategories: [
    { id: "sponsor", label: L.tr("Спонсор") },
    { id: "intro", label: L.tr("Интро") },
    { id: "outro", label: L.tr("Концовка") },
    { id: "selfpromo", label: L.tr("Самореклама") },
    { id: "interaction", label: L.tr("Напоминание о подписке") },
    { id: "preview", label: L.tr("Превью и рекап") },
    { id: "music_offtopic", label: L.tr("Не музыка") }
  ]
  readonly property var sponsorChoices: [
    { value: "skip", label: L.tr("ПРОПУСК") }, { value: "ask", label: L.tr("СПРОСИТЬ") }, { value: "off", label: L.tr("ВЫКЛ") }
  ]
  readonly property var sponsorActions: preferences.sponsorActions || ({})
  readonly property var hotkeys: [
    { keys: "1 – 5", label: L.tr("Сейчас / Поиск / Медиатека / Подписки / Загрузки") },
    { keys: "Esc", label: L.tr("Закрыть панель или настройки") },
    { keys: "Ctrl + Tab", label: L.tr("Переключить панель в баре") },
    { keys: "Enter", label: L.tr("Воспроизвести ссылку / найти") },
    { keys: L.tr("ПКМ по строке"), label: L.tr("Меню действий") }
  ]
  readonly property var currentGroup: groups.filter(function(row) { return row.id === group })[0]

  onGroupChanged: {
    if (group === "account" && logic) hiddenRequestId = logic.request("hidden_channels", ({}))
    if (group === "browser") refreshBrowserStatus()
  }

  readonly property var browserModes: [
    { value: "keep", label: L.tr("КАК СЕЙЧАС") }, { value: "audio", label: L.tr("АУДИО") },
    { value: "tile", label: L.tr("ПЛИТКА") }, { value: "floating", label: L.tr("ОКНО") }
  ]
  readonly property string extensionPath: browserStatus ? String(browserStatus.extensionPath) : "~/.local/share/omatube/browser-extension"
  readonly property string firefoxExtension: browserStatus && browserStatus.firefoxExtension ? String(browserStatus.firefoxExtension) : "~/.local/share/omatube/omatube-firefox.xpi"
  readonly property string firefoxFolder: extensionPath + "-firefox"
  readonly property color warnColor: Qt.tint(Color.urgent, Qt.rgba(1, .8, .3, .55))

  function runBrowserSetup(args) {
    if (!logic || browserSetupProcess.running) return
    browserSetupProcess.command = [logic.cli, "browser-setup"].concat(args)
    browserSetupProcess.running = true
  }
  function relativeMoment(value) {
    if (!value) return "—"
    var date = new Date(value)
    if (isNaN(date.getTime())) return "—"
    var minutes = Math.floor((Date.now() - date.getTime()) / 60000)
    if (minutes < 1) return L.tr("только что")
    if (minutes < 60) return L.fill(L.tr("%1 мин назад"), [minutes])
    if (minutes < 24 * 60) return L.fill(L.tr("%1 ч назад"), [Math.floor(minutes / 60)])
    if (minutes < 48 * 60) return L.tr("вчера")
    return Qt.formatDateTime(date, "dd.MM.yyyy")
  }
  // Right-hand status of a browser row (the "missing" row shows an install button instead).
  function browserStateText(row) {
    if (row.status === "connected") return L.tr("подключено") + " · " + relativeMoment(row.lastSeen) + (row.extensionVersion ? " · " + row.extensionVersion : "")
    if (row.status === "outdated") return L.tr("перезагрузите расширение")
    if (row.status === "ready") return L.tr("ещё не подключалось")
    if (row.status === "sandboxed") return L.tr("не поддерживается")
    return ""
  }
  function browserDetail(row) {
    var family = row.family === "gecko" ? "Gecko" : "Chromium"
    if (row.status === "outdated") return L.fill(L.tr("был %1 · расширение %2"), [relativeMoment(row.lastSeen), row.extensionVersion || "?"])
    if (row.status === "ready") return L.tr("связка установлена · загрузите расширение, путь ниже")
    if (row.status === "missing") return row.kind === "custom" ? L.tr("добавлен вручную · манифест пропал") : L.tr("профиль найден · манифеста связки нет")
    if (row.status === "sandboxed") return L.tr("песочница не даёт запустить связку · поставьте обычный пакет")
    if (row.kind === "detected") return L.tr("найден по запуску расширения")
    return row.hostsDir ? family + " · " + row.hostsDir : family
  }

  function refreshBrowserStatus() {
    if (!logic || browserStatusProcess.running) return
    browserStatusProcess.command = [logic.cli, "browser-status"]
    browserStatusProcess.running = true
  }

  Process {
    id: browserStatusProcess
    command: []
    stdout: StdioCollector { id: browserStatusOut; waitForEnd: true }
    onExited: function(code) {
      try {
        var envelope = JSON.parse(browserStatusOut.text || "{}")
        if (!envelope.ok) throw new Error("status")
        root.browserStatus = envelope.result
      } catch (error) {
        root.browserStatus = null
      }
    }
  }

  Process {
    id: browserSetupProcess
    command: []
    stderr: StdioCollector { id: browserSetupErr; waitForEnd: true }
    onExited: function(code) {
      root.browserError = code === 0 ? "" : String(browserSetupErr.text || L.tr("Не удалось установить связку")).trim()
      root.refreshBrowserStatus()
    }
  }

  Connections {
    target: root.logic
    function onActionSerialChanged() {
      var result = root.logic.lastResult
      if (result && result.hidden !== undefined) root.hiddenChannels = result.hidden
    }
  }

  function setPreference(key, value) {
    if (logic) logic.request("setting", { key: key, value: value })
  }
  function textWidthStep(delta) {
    setPreference("textWidth", Math.max(80, Math.min(600, Number(preferences.textWidth || 220) + delta)))
  }

  QtObject {
    id: previewLogic
    readonly property var stateData: ({
      state: "playing", volume: 67, duration: 145, position: 60, videoMode: "audio", buffering: false,
      current: { entryId: "preview", media: { title: "Dancing with the Source (Bansuri Version)", author: "Borislav Slavov", thumbnailUrl: "" } },
      preferences: root.preferences
    })
    readonly property bool hasTrack: true
    readonly property bool playing: true
    readonly property bool busy: false
    readonly property string videoMode: "audio"
    readonly property string error: ""
    readonly property string loaderTooltip: ""
    function request(command, payload) {}
    function toggle() {}
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.space(10)
    font.bold: true
    font.letterSpacing: 1.5
  }

  component SwitchRow: Item {
    id: row
    property string label: ""
    property string description: ""
    property bool checked: false
    signal toggled()
    width: parent ? parent.width : 0
    height: Style.space(description !== "" ? 47 : 32)
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.checked: checked
    Keys.onReturnPressed: row.toggled()
    Keys.onSpacePressed: row.toggled()
    Rectangle {
      visible: row.activeFocus
      anchors.fill: parent
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: Color.accent
    }
    Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(10)
      Column {
        width: parent.width - toggleTrack.width - parent.spacing
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.space(12)
          elide: Text.ElideRight
        }
        Text {
          visible: row.description !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: row.description
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          elide: Text.ElideRight
        }
      }
      Rectangle {
        id: toggleTrack
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: Style.space(16)
        radius: height / 2
        color: row.checked ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .12)
        Rectangle {
          width: Style.space(12)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          x: row.checked ? parent.width - width - Style.space(2) : Style.space(2)
          color: row.checked ? Color.background : root.dim
          Behavior on x { NumberAnimation { duration: 100 } }
        }
      }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: row.toggled() }
  }

  Row {
    anchors.fill: parent

    Rectangle {
      id: sidebar
      visible: !root.compact
      width: visible ? Style.space(210) : 0
      height: parent.height
      color: "transparent"
      Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.max(1, Style.space(1))
        color: root.lineColor
      }
      Column {
        anchors.fill: parent
        anchors.topMargin: Style.space(20)
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(11)
        spacing: Style.space(2)
        Text {
          leftPadding: Style.space(12)
          bottomPadding: Style.space(12)
          textFormat: Text.PlainText
          text: L.tr("НАСТРОЙКИ")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.space(10)
          font.bold: true
          font.letterSpacing: 1.5
        }
        Repeater {
          model: root.groups
          delegate: Item {
            required property var modelData
            readonly property bool chosen: root.group === modelData.id
            width: parent.width
            height: Style.space(32)
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.label
            Keys.onReturnPressed: root.group = modelData.id
            Rectangle {
              anchors.fill: parent
              color: chosen ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .1)
                : (mouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .05) : "transparent")
            }
            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(12)
              spacing: Style.space(10)
              Icon { anchors.verticalCenter: parent.verticalCenter; name: modelData.icon; size: Style.space(14); color: chosen ? Color.accent : root.dim }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: chosen ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
                font.weight: chosen ? Font.DemiBold : Font.Normal
              }
            }
            MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.group = modelData.id }
          }
        }
      }
    }

    Flickable {
      id: flick
      width: parent.width - sidebar.width
      height: parent.height
      contentWidth: width
      contentHeight: content.implicitHeight + Style.space(48)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: content
        x: root.compact ? Style.space(16) : Style.space(28)
        y: Style.space(20)
        width: flick.width - (root.compact ? Style.space(32) : Style.space(56)) - (flick.contentHeight > flick.height ? Style.space(8) : 0)
        spacing: Style.space(16)

        Flickable {
          visible: root.compact
          width: parent.width
          height: visible ? Style.space(32) : 0
          contentWidth: groupChips.width
          contentHeight: height
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Row {
            id: groupChips
            height: parent.height
            spacing: Style.space(6)
            Repeater {
              model: root.groups
              delegate: Pill {
                required property var modelData
                height: Style.space(28)
                text: modelData.label
                icon: modelData.icon
                selected: root.group === modelData.id
                labelSize: 11
                letterSpacing: 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.group = modelData.id
              }
            }
          }
        }

        Row {
          width: parent.width
          Column {
            width: parent.width - closeButton.width
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: root.currentGroup.label
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.space(20)
              font.bold: true
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.currentGroup.subtitle
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              wrapMode: Text.WordWrap
            }
          }
          IconButton {
            id: closeButton
            icon: "x"
            iconSize: 14
            tooltipText: L.tr("Закрыть (Esc)")
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.closeRequested()
          }
        }

        Column {
          visible: root.group === "bar"
          width: parent.width
          spacing: Style.space(16)

          Rectangle {
            width: parent.width
            height: Style.space(78)
            color: root.surface
            Column {
              anchors.fill: parent
              anchors.margins: Style.space(14)
              spacing: Style.space(8)
              Text {
                textFormat: Text.PlainText
                text: L.tr("ПРЕВЬЮ")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.space(9)
                font.bold: true
                font.letterSpacing: 1.5
              }
              Rectangle {
                width: parent.width
                height: Style.space(30)
                color: Color.background
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "Mon 5 Oct 23:42"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                }
                Item {
                  id: previewFrame
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.min(previewWidget.implicitWidth + Style.space(16), parent.width - Style.space(150))
                  height: Style.space(24)
                  clip: true
                  Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: Color.accent
                  }
                  BarPlayer {
                    id: previewWidget
                    anchors.centerIn: parent
                    width: previewFrame.width - Style.space(10)
                    height: Style.space(24)
                    logic: previewLogic
                  }
                }
              }
            }
          }

          Grid {
            id: toggleGrid
            width: parent.width
            columns: root.compact ? 1 : 2
            columnSpacing: Style.space(24)
            rowSpacing: Style.space(16)
            readonly property real cellWidth: root.compact ? width : (width - columnSpacing) / 2
            Column {
              width: toggleGrid.cellWidth
              spacing: 0
              SectionLabel { text: L.tr("ЭЛЕМЕНТЫ"); bottomPadding: Style.space(6) }
              Repeater {
                model: root.barToggles
                delegate: SwitchRow {
                  required property var modelData
                  label: modelData.label
                  description: modelData.description || ""
                  checked: root.preferences[modelData.key] === true
                  onToggled: root.setPreference(modelData.key, !checked)
                }
              }
            }
            Column {
              width: toggleGrid.cellWidth
              spacing: 0
              SectionLabel { text: L.tr("ПОВЕДЕНИЕ"); bottomPadding: Style.space(6) }
              Repeater {
                model: root.behaviorToggles
                delegate: SwitchRow {
                  required property var modelData
                  label: modelData.label
                  description: modelData.description || ""
                  checked: root.preferences[modelData.key] === true
                  onToggled: root.setPreference(modelData.key, !checked)
                }
              }
              Row {
                width: parent.width
                height: Style.space(44)
                leftPadding: Style.space(8)
                Text {
                  width: parent.width - stepper.width - Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: L.tr("Ширина текста")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(12)
                }
                Rectangle {
                  id: stepper
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(116)
                  height: Style.space(28)
                  color: "transparent"
                  border.width: Math.max(1, Style.space(1))
                  border.color: root.lineColor
                  Row {
                    anchors.fill: parent
                    IconButton { width: Style.space(28); height: parent.height; icon: "minus"; iconSize: 12; tooltipText: L.tr("Уже"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.textWidthStep(-20) }
                    Text {
                      width: parent.width - Style.space(56)
                      height: parent.height
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      textFormat: Text.PlainText
                      text: Number(root.preferences.textWidth || 220) + " px"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.space(11)
                    }
                    IconButton { width: Style.space(28); height: parent.height; icon: "plus"; iconSize: 12; tooltipText: L.tr("Шире"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.textWidthStep(20) }
                  }
                }
              }
            }
          }

          SectionLabel { text: L.tr("ВИД ВИДЖЕТА") }
          Grid {
            id: layoutGrid
            width: parent.width
            columns: root.compact ? 1 : 3
            columnSpacing: Style.space(12)
            rowSpacing: Style.space(8)
            Repeater {
              model: root.barLayouts
              delegate: Rectangle {
                required property var modelData
                readonly property bool chosen: String(root.preferences.barLayout || "full") === modelData.value
                width: root.compact ? layoutGrid.width : (layoutGrid.width - layoutGrid.columnSpacing * 2) / 3
                height: Style.space(54)
                color: chosen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: chosen ? Color.accent : root.lineColor
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label
                Keys.onReturnPressed: root.setPreference("barLayout", modelData.value)
                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(10)
                  spacing: Style.space(3)
                  Text { width: parent.width; textFormat: Text.PlainText; text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); font.weight: chosen ? Font.Bold : Font.Normal; elide: Text.ElideRight }
                  Text { width: parent.width; textFormat: Text.PlainText; text: modelData.description; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); elide: Text.ElideRight }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPreference("barLayout", modelData.value) }
              }
            }
          }

          SectionLabel { text: L.tr("ФОРМАТ ПАНЕЛИ") }
          Flow {
            width: parent.width
            spacing: Style.space(12)
            Repeater {
              model: root.panelFormats
              delegate: Rectangle {
                id: layoutCard
                required property var modelData
                readonly property bool chosen: String(root.preferences.panelFormat || "wide") === modelData.value
                width: Style.space(150)
                height: Style.space(121)
                color: chosen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, .18) : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: chosen ? Color.accent : root.lineColor
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: modelData.label + ". " + modelData.size
                Keys.onReturnPressed: root.setPreference("panelFormat", modelData.value)
                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(8)
                  Rectangle {
                    width: parent.width
                    height: Style.space(56)
                    color: Color.background
                    Grid {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      columns: layoutCard.modelData.vertical ? 1 : 3
                      spacing: Style.space(3)
                      Repeater {
                        model: layoutCard.modelData.blocks
                        delegate: Rectangle {
                          required property var modelData
                          width: layoutCard.modelData.vertical ? parent.width : Math.round((parent.width - Style.space(6)) * modelData.w)
                          height: layoutCard.modelData.vertical ? Math.round((parent.height - Style.space(3)) * modelData.h) : parent.height
                          color: modelData.a ? Color.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .14)
                        }
                      }
                    }
                  }
                  Row {
                    spacing: Style.space(6)
                    Text { textFormat: Text.PlainText; text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); font.weight: chosen ? Font.Bold : Font.Normal }
                    Icon { visible: chosen; anchors.verticalCenter: parent.verticalCenter; name: "circle-check"; size: Style.space(13); color: Color.accent }
                  }
                  Text { textFormat: Text.PlainText; text: modelData.size; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10) }
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.setPreference("panelFormat", modelData.value) }
              }
            }
          }

          SectionLabel { text: L.tr("ПЛЕЕР ВНЕ «СЕЙЧАС»") }
          Row {
            width: parent.width
            spacing: Style.space(12)
            Segmented {
              id: dockChoice
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: [{ label: L.tr("ТОНКАЯ ПАНЕЛЬ"), value: "thin" }, { label: L.tr("НИЖНЯЯ ПАНЕЛЬ"), value: "bar" }]
              current: String(root.preferences.playerDock || "thin")
              onChosen: value => root.setPreference("playerDock", value)
            }
            Text {
              width: parent.width - dockChoice.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(root.preferences.playerDock || "thin") === "thin"
                ? L.tr("линия таймлайна с главами, ˄ раскрывает плеер поверх вкладки")
                : L.tr("полная строка управления под каждой вкладкой")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              wrapMode: Text.WordWrap
            }
          }

          Row {
            spacing: Style.space(8)
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "palette"; size: Style.space(13); color: root.dim }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: L.tr("Цвета берутся из текущей темы Omarchy")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
            }
          }
        }

        Column {
          visible: root.group === "playback"
          width: parent.width
          spacing: 0
          SwitchRow { label: L.tr("Нормализация громкости"); description: L.tr("loudnorm в mpv, −14 LUFS"); checked: root.preferences.normalize === true; onToggled: root.setPreference("normalize", !checked) }
          SwitchRow { label: L.tr("Пропускать тишину"); description: L.tr("ускорять паузы в подкастах"); checked: root.preferences.skipSilence === true; onToggled: root.setPreference("skipSilence", !checked) }
          SwitchRow { label: L.tr("Готовить поток при наведении"); description: L.tr("заранее получать ссылку на видео под курсором — старт быстрее, но больше запросов"); checked: root.preferences.hoverPrefetch !== false; onToggled: root.setPreference("hoverPrefetch", !checked) }
          SwitchRow { label: L.tr("Сохранять историю"); description: L.tr("запоминать просмотренное в медиатеке"); checked: root.preferences.historyEnabled === true; onToggled: root.setPreference("historyEnabled", !checked) }
          SectionLabel { topPadding: Style.space(16); bottomPadding: Style.space(8); text: L.tr("КАЧЕСТВО ВИДЕО ПО УМОЛЧАНИЮ") }
          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: [360, 480, 720, 1080, 1440, 2160]
              delegate: Pill {
                required property int modelData
                width: (parent.width - parent.spacing * 5) / 6
                text: modelData + "p"
                selected: Number(root.preferences.videoQuality || 1080) === modelData
                labelSize: 11
                letterSpacing: 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.logic.request("video_quality", { value: modelData })
              }
            }
          }
        }

        Column {
          visible: root.group === "sponsor"
          width: parent.width
          spacing: 0
          Text {
            width: parent.width
            bottomPadding: Style.space(10)
            textFormat: Text.PlainText
            text: L.tr("Сэкономлено в этом треке: ")
              + (logic && logic.stateData.sponsor ? Math.floor(logic.stateData.sponsor.saved / 60) + ":" + ("0" + Math.round(logic.stateData.sponsor.saved % 60)).slice(-2) : "0:00")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
          }
          Repeater {
            model: root.sponsorCategories
            delegate: Item {
              required property var modelData
              width: parent.width
              height: Style.space(40)
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
              }
              Segmented {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                foreground: root.foreground
                fontFamily: root.fontFamily
                options: root.sponsorChoices
                current: String(root.sponsorActions[modelData.id] || "off")
                onChosen: value => {
                  var update = ({})
                  update[modelData.id] = value
                  root.setPreference("sponsorActions", update)
                }
              }
            }
          }
        }

        Column {
          visible: root.group === "account"
          width: parent.width
          spacing: Style.space(12)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.youtubeAuth.error ? L.tb(root.youtubeAuth.error)
              : (root.youtubeAuth.authenticated
                ? L.tr("Авторизованная сессия подключена")
                : (root.youtubeAuth.configured
                  ? L.tr("Гостевые cookies. Войдите в Chromium и импортируйте снова")
                  : L.tr("Cookies не подключены. Без аккаунта работает поиск и воспроизведение")))
            color: root.youtubeAuth.error ? Color.urgent : (root.youtubeAuth.authenticated ? Color.accent : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            wrapMode: Text.WordWrap
          }
          Row {
            spacing: Style.space(8)
            Pill {
              height: Style.space(31)
              icon: "download"
              text: root.youtubeAuth.configured ? L.tr("ОБНОВИТЬ ИЗ CHROMIUM") : L.tr("ИМПОРТ ИЗ CHROMIUM")
              selected: true
              bold: true
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.logic.request("youtube_auth_import", { browser: "chromium" })
            }
            Pill {
              visible: Boolean(root.youtubeAuth.configured || root.youtubeAuth.error)
              height: Style.space(31)
              icon: "trash-2"
              text: L.tr("УДАЛИТЬ")
              danger: true
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.logic.request("youtube_auth_clear", ({}))
            }
          }
          SectionLabel { topPadding: Style.space(10); text: L.tr("СКРЫТЫЕ КАНАЛЫ · ") + root.hiddenChannels.length }
          Repeater {
            model: root.hiddenChannels
            delegate: Item {
              required property var modelData
              width: parent.width
              height: Style.space(32)
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.right: restoreLabel.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.title
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.space(12)
                elide: Text.ElideRight
              }
              Text {
                id: restoreLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: L.tr("вернуть")
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.space(10)
                MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); cursorShape: Qt.PointingHandCursor; onClicked: root.logic.request("unhide_channel", { channelId: modelData.id }) }
              }
            }
          }
          Text {
            visible: root.hiddenChannels.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: L.tr("Каналы, помеченные «Не рекомендовать», скрываются из поиска и страниц каталога.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: root.group === "browser"
          width: parent.width
          spacing: 0
          SwitchRow { label: L.tr("Принимать видео из браузера"); description: L.tr("кнопка «Смотреть в OmaTube» на YouTube и пункт в меню ссылок"); checked: root.preferences.browserAccept !== false; onToggled: root.setPreference("browserAccept", !checked) }
          SwitchRow { label: L.tr("Уведомление при переносе"); description: L.tr("«Продолжаю: название · 12:34»"); checked: root.preferences.browserNotify !== false; onToggled: root.setPreference("browserNotify", !checked) }
          Item {
            width: parent.width
            height: Style.space(47)
            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
            Column {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: browserModeChoice.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text { width: parent.width; textFormat: Text.PlainText; text: L.tr("Режим для видео из браузера"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); elide: Text.ElideRight }
              Text { width: parent.width; textFormat: Text.PlainText; text: L.tr("«как сейчас» — оставить текущий режим плеера"); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); elide: Text.ElideRight }
            }
            Segmented {
              id: browserModeChoice
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: root.browserModes
              current: String(root.preferences.browserVideoMode || "keep")
              onChosen: value => root.setPreference("browserVideoMode", value)
            }
          }

          SectionLabel { topPadding: Style.space(18); bottomPadding: Style.space(8); text: L.tr("БРАУЗЕРЫ") }
          Repeater {
            model: root.browserStatus ? root.browserStatus.browsers : []
            delegate: Item {
              id: browserRow
              required property var modelData
              readonly property string status: String(modelData.status || "")
              readonly property color tone: status === "connected" ? Color.accent : (status === "outdated" ? root.warnColor : (status === "missing" ? Color.urgent : root.dim))
              width: parent.width
              height: Style.space(44)
              opacity: status === "sandboxed" ? .75 : 1
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
              Rectangle {
                id: browserDot
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8); height: width; radius: width / 2
                // Hollow: nothing to act on yet (ready) or nothing we can do (sandboxed).
                color: browserRow.status === "ready" || browserRow.status === "sandboxed" ? "transparent" : browserRow.tone
                border.width: color === "transparent" ? Math.max(1, Style.space(1.5)) : 0
                border.color: root.dim
              }
              Column {
                anchors.left: browserDot.right
                anchors.leftMargin: Style.space(10)
                anchors.right: browserState.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text { width: parent.width; textFormat: Text.PlainText; text: String(browserRow.modelData.name || browserRow.modelData.id); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12); elide: Text.ElideRight }
                Text { width: parent.width; textFormat: Text.PlainText; text: root.browserDetail(browserRow.modelData); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(10); elide: Text.ElideMiddle }
              }
              Item {
                id: browserState
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: browserRow.status === "missing" ? installPill.width : stateText.implicitWidth
                height: Style.space(24)
                Text {
                  id: stateText
                  visible: browserRow.status !== "missing"
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: root.browserStateText(browserRow.modelData)
                  color: browserRow.status === "connected" || browserRow.status === "outdated" ? browserRow.tone : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(11)
                }
                Pill {
                  id: installPill
                  visible: browserRow.status === "missing"
                  anchors.right: parent.right
                  height: Style.space(24)
                  text: L.tr("УСТАНОВИТЬ")
                  labelSize: 10
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.runBrowserSetup([])
                }
              }
            }
          }
          Text {
            visible: !!root.browserStatus && root.browserStatus.browsers.length === 0
            width: parent.width
            topPadding: Style.space(4)
            textFormat: Text.PlainText
            text: L.tr("Браузеры не найдены.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            wrapMode: Text.WordWrap
          }
          Text {
            visible: !root.browserStatus
            width: parent.width
            topPadding: Style.space(4)
            textFormat: Text.PlainText
            text: L.tr("Не удалось получить статус связки.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            wrapMode: Text.WordWrap
          }
          Row {
            width: parent.width
            topPadding: Style.space(10)
            spacing: Style.space(8)
            Icon { name: "info"; size: Style.space(13); color: root.dim }
            Text {
              width: parent.width - Style.space(21)
              textFormat: Text.PlainText
              text: L.tr("Новые браузеры подхватываются при каждом запуске OmaTube. Вашего нет в списке? omatube browser-setup --dir ~/.config/<браузер>")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              wrapMode: Text.WordWrap
            }
          }
          Text {
            visible: root.browserError !== ""
            width: parent.width
            topPadding: Style.space(8)
            textFormat: Text.PlainText
            text: root.browserError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.space(11)
            wrapMode: Text.WordWrap
          }
          Row {
            topPadding: Style.space(12)
            spacing: Style.space(8)
            Pill {
              height: Style.space(31)
              icon: "refresh-cw"
              text: L.tr("ПЕРЕУСТАНОВИТЬ СВЯЗКУ")
              selected: true
              bold: true
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.runBrowserSetup([])
            }
            Pill {
              height: Style.space(31)
              icon: "copy"
              text: L.tr("ПАПКА ДЛЯ CHROMIUM")
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", root.extensionPath])
            }
            Pill {
              height: Style.space(31)
              icon: "copy"
              text: L.tr("XPI ДЛЯ FIREFOX / ZEN")
              labelSize: 11
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: Quickshell.execDetached(["/usr/bin/wl-copy", root.firefoxExtension])
            }
          }

          SectionLabel { topPadding: Style.space(18); bottomPadding: Style.space(8); text: L.tr("КАК ПОСТАВИТЬ РАСШИРЕНИЕ") }
          Repeater {
            model: [
              L.tr("Откройте chrome://extensions и включите «Режим разработчика»."),
              L.tr("Нажмите «Загрузить распакованное» и выберите папку ") + root.extensionPath + ".",
              L.tr("Откройте видео на YouTube — под ним появится кнопка «Смотреть в OmaTube». Горячая клавиша по умолчанию — Alt+Shift+O."),
              L.tr("После обновления OmaTube нажмите «Обновить» у расширения на chrome://extensions."),
              L.tr("Firefox и Zen: about:debugging → «Этот Firefox» → «Загрузить временное дополнение» → ") + root.firefoxFolder + L.tr("/manifest.json. Постоянно — файл .xpi в Developer Edition, Nightly или LibreWolf с отключённой проверкой подписи.")
            ]
            delegate: Text {
              required property var modelData
              required property int index
              width: parent.width
              bottomPadding: Style.space(6)
              text: (index + 1) + ". " + modelData
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(11)
              wrapMode: Text.WordWrap
            }
          }
        }

        Column {
          visible: root.group === "storage"
          width: parent.width
          spacing: 0
          Repeater {
            model: [
              { label: L.tr("Загрузки"), value: "~/Videos/OmaTube" },
              { label: L.tr("Библиотека и история"), value: "~/.local/share/omatube/library.sqlite3" },
              { label: L.tr("Настройки и cookies"), value: "~/.config/omatube" }
            ]
            delegate: Item {
              required property var modelData
              width: parent.width
              height: Style.space(36)
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12) }
              Text { anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: modelData.value; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.space(11) }
            }
          }
        }

        Column {
          visible: root.group === "language"
          width: parent.width
          spacing: Style.space(12)
          SectionLabel { text: L.tr("ЯЗЫК ИНТЕРФЕЙСА") }
          Row {
            width: parent.width
            spacing: Style.space(12)
            Segmented {
              id: languageChoice
              anchors.verticalCenter: parent.verticalCenter
              foreground: root.foreground
              fontFamily: root.fontFamily
              options: [{ label: L.tr("АВТО"), value: "auto" }, { label: "ENGLISH", value: "en" }, { label: "РУССКИЙ", value: "ru" }]
              current: String(root.preferences.language || "auto")
              onChosen: value => root.setPreference("language", value)
            }
            Text {
              width: parent.width - languageChoice.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(root.preferences.language || "auto") === "auto"
                ? L.tr("Язык системы: ") + (L.detect() === "ru" ? "Русский" : "English") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.space(10)
              wrapMode: Text.WordWrap
            }
          }
        }

        Column {
          visible: root.group === "hotkeys"
          width: parent.width
          spacing: 0
          Repeater {
            model: root.hotkeys
            delegate: Item {
              required property var modelData
              width: parent.width
              height: Style.space(34)
              Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: Math.max(1, Style.space(1)); color: root.lineColor }
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; width: Style.space(150); textFormat: Text.PlainText; text: modelData.keys; color: Color.accent; font.family: root.fontFamily; font.pixelSize: Style.space(12) }
              Text { anchors.left: parent.left; anchors.leftMargin: Style.space(166); anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText; text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.space(12) }
            }
          }
        }

        Column {
          visible: root.group === "about"
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: L.tr("Нативный плеер YouTube и YouTube Music для Omarchy. Воспроизведение через mpv, каталог через youtubei.js, потоки через yt-dlp.")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.space(12)
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
