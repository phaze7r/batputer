import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.space(18)
  property bool active: false
  property bool pulsing: false
  property color maskColor: Color.foreground

  // Determine light vs dark
  readonly property bool useWhiteIcon: {
    var c = root.maskColor
    if (!c) return true
    try {
      var col = Qt.color(c)
      var lum = 0.299 * col.r + 0.587 * col.g + 0.114 * col.b
      return lum > 0.35
    } catch(e) {
      return true
    }
  }

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Image {
    id: img
    anchors.fill: parent
    source: root.useWhiteIcon ? Qt.resolvedUrl("assets/batman_white.png") : Qt.resolvedUrl("assets/batman_black.png")
    sourceSize.width: root.iconSize * 3
    sourceSize.height: root.iconSize * 3
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectFit
    opacity: root.pulsing ? pulseAnim.currentOpacity : (root.active ? 1.0 : 0.95)

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }
  }

  Item {
    id: pulseAnim
    property real currentOpacity: 1.0
    SequentialAnimation on currentOpacity {
      running: root.pulsing
      loops: Animation.Infinite
      alwaysRunToEnd: false
      NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 0.7; duration: 200; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1.0; duration: 300; easing.type: Easing.InOutQuad }
    }
  }
}
