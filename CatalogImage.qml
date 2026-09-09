import QtQuick
import qs.Ui

Image {
  id: root

  property string requestedSource: ""
  property color foreground: "white"
  property string fontFamily: ""
  property string emptyIcon: "󰝚"
  property int maxRetryAttempts: 3
  property int retryAttempt: 0
  property int retryNonce: 0
  readonly property string normalizedSource: normalizeSource(requestedSource)
  readonly property bool retrying: retryTimer.running
  readonly property bool exhausted: requestedSource !== "" && status === Image.Error
    && !retrying && retryAttempt >= maxRetryAttempts

  source: normalizedSource === "" ? "" : normalizedSource
    + (normalizedSource.indexOf("?") >= 0 ? "&" : "?")
    + "omatubeRetry=" + retryNonce
  asynchronous: true
  cache: true
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
    anchors.centerIn: parent
    visible: root.status === Image.Loading || root.retrying
    text: "󰦖"
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.min(root.width, root.height) * .3
    RotationAnimator on rotation {
      running: parent.visible
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
    text: root.exhausted ? "Обложка недоступна после " + root.maxRetryAttempts + " повторов"
      : (root.retrying ? "Повтор загрузки обложки · попытка " + root.retryAttempt
      : "Загружаем обложку")
    fontFamily: root.fontFamily
  }

  Timer {
    id: retryTimer
    interval: Math.min(2400, 600 * Math.pow(2, Math.max(0, root.retryAttempt - 1)))
    repeat: false
    onTriggered: root.retryNonce += 1
  }
}
