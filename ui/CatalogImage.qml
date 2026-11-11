import QtQuick
import qs.Ui
import "i18n.js" as L

Image {
  id: root

  property string requestedSource: ""
  property color foreground: "white"
  property string fontFamily: ""
  property string emptyIcon: "󰝚"
  property int maxRetryAttempts: 3
  property int retryAttempt: 0
  property int retryNonce: 0
  property int proxyPort: 47865
  readonly property bool sized: width > 0 && height > 0
  readonly property real displayScale: Window.window ? Window.window.devicePixelRatio : 1
  readonly property int pixelWidth: Math.ceil(width * displayScale)
  readonly property int pixelHeight: Math.ceil(height * displayScale)
  // Reuse decoded images across small layout changes instead of caching every pixel size.
  readonly property int decodeWidth: sized ? Math.ceil(pixelWidth / 32) * 32 : 1
  readonly property int decodeHeight: sized ? Math.ceil(pixelHeight / 32) * 32 : 1
  // mqdefault is 320x180: don't request it when the screen needs more pixels.
  readonly property int widthBucket: sized && pixelWidth <= 320 && pixelHeight <= 180 ? 320 : 0
  readonly property string normalizedSource: normalizeSource(requestedSource)
  // Thumbnails go through the backend's local cache (disk cache, keep-alive, proxy);
  // after the first failure the image is fetched straight from YouTube instead.
  readonly property bool proxied: retryAttempt === 0 && /^https:\/\/(i\.ytimg\.com|yt3\.ggpht\.com|yt3\.googleusercontent\.com)\//.test(normalizedSource)
  readonly property string loadSource: proxied ? "http://127.0.0.1:" + proxyPort + "/img?w=" + widthBucket + "&u=" + encodeURIComponent(normalizedSource) : normalizedSource
  readonly property bool retrying: retryTimer.running
  readonly property bool exhausted: requestedSource !== "" && status === Image.Error
    && !retrying && retryAttempt >= maxRetryAttempts

  source: loadSource === "" || !sized ? "" : loadSource
    + (loadSource.indexOf("?") >= 0 ? "&" : "?")
    + "omatubeRetry=" + retryNonce
  asynchronous: true
  cache: true
  sourceSize: Qt.size(decodeWidth, decodeHeight)
  function normalizeSource(value) {
    var candidate = String(value || "").trim()
    if (candidate.indexOf("//") === 0) return "https:" + candidate
    if (candidate.indexOf("yt3.") === 0 || candidate.indexOf("i.ytimg.com/") === 0)
      return "https://" + candidate
    return candidate
  }

  onRequestedSourceChanged: {
    retryTimer.stop()
    retryAttempt = 0
    retryNonce = 0
  }

  onStatusChanged: {
    if (status === Image.Ready) {
      retryTimer.stop()
      retryAttempt = 0
    } else if (status === Image.Error && requestedSource !== ""
               && retryAttempt < maxRetryAttempts) {
      retryAttempt += 1
      retryTimer.restart()
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.requestedSource === "" || root.exhausted
    text: root.requestedSource === "" ? root.emptyIcon : "󰋦"
    textFormat: Text.PlainText
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, .45)
    font.family: root.fontFamily
    font.pixelSize: Math.min(root.width, root.height) * .34
  }

  Text {
    id: loadingSpinner
    anchors.centerIn: parent
    visible: root.status === Image.Loading || root.retrying
    text: "󰦖"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.min(root.width, root.height) * .3
    RotationAnimator on rotation {
      running: loadingSpinner.visible && loadingSpinner.Window.window !== null && loadingSpinner.Window.window.visible
      from: 0
      to: 360
      duration: 800
      loops: Animation.Infinite
    }
  }

  MouseArea {
    id: imageStatusMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
  PanelToolTip {
    visible: imageStatusMouse.containsMouse && (root.status === Image.Loading || root.retrying || root.exhausted)
    text: root.exhausted ? L.tr("Обложка недоступна после ") + root.maxRetryAttempts + L.tr(" повторов")
      : (root.retrying ? L.tr("Повтор загрузки обложки · попытка ") + root.retryAttempt
      : L.tr("Загружаем обложку"))
    fontFamily: root.fontFamily
  }

  Timer {
    id: retryTimer
    interval: Math.min(2400, 600 * Math.pow(2, Math.max(0, root.retryAttempt - 1)))
    repeat: false
    onTriggered: root.retryNonce += 1
  }
}
