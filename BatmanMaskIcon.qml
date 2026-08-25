import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.space(18)
  property bool active: false
  property bool pulsing: false
  property color maskColor: Color.foreground

  // Theme-aware detection:
  // Light background (lum >= 0.5) -> black icon
  // Dark background (lum < 0.5) -> white icon
  readonly property bool useWhiteIcon: {
    try {
      var bg = Color.background
      var bgCol = Qt.color(bg)
      var bgLum = 0.299 * bgCol.r + 0.587 * bgCol.g + 0.114 * bgCol.b
      if (bgLum >= 0.5) return false

      var fg = root.maskColor
      var fgCol = Qt.color(fg)
      var fgLum = 0.299 * fgCol.r + 0.587 * fgCol.g + 0.114 * fgCol.b
      if (fgLum < 0.35) return false

      return true
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
