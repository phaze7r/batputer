import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.space(18)
  property bool active: false
  property bool pulsing: false
  property bool batSignalActive: false
  property color maskColor: Color.foreground

  // Theme-aware detection:
  // Light bar / light surface (fg is dark, lum < 0.5) -> Solid Black Cowl
  // Dark bar / dark surface (fg is light, lum >= 0.5) -> Solid White Cowl
  readonly property bool useWhiteIcon: {
    try {
      var fg = root.maskColor
      var fgCol = Qt.color(fg)
      var fgLum = 0.299 * fgCol.r + 0.587 * fgCol.g + 0.114 * fgCol.b
      if (fgLum >= 0.5) return true
      if (fgLum < 0.5) return false

      var bg = Color.background
      var bgCol = Qt.color(bg)
      var bgLum = 0.299 * bgCol.r + 0.587 * bgCol.g + 0.114 * bgCol.b
      return (bgLum < 0.5)
    } catch(e) {
      return true
    }
  }

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  // Bat-Signal Illuminated Searchlight Halo
  Rectangle {
    id: signalHalo
    visible: root.batSignalActive
    anchors.centerIn: parent
    width: root.iconSize * 1.45
    height: root.iconSize * 1.45
    radius: width / 2
    color: Qt.rgba(1.0, 0.84, 0.0, 0.25)
    border.color: "#ffd60a"
    border.width: 1.5
    scale: 1.0

    SequentialAnimation on opacity {
      running: root.batSignalActive
      loops: Animation.Infinite
      NumberAnimation { to: 0.95; duration: 800; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 0.30; duration: 800; easing.type: Easing.InOutQuad }
    }

    SequentialAnimation on scale {
      running: root.batSignalActive
      loops: Animation.Infinite
      NumberAnimation { to: 1.25; duration: 800; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 0.95; duration: 800; easing.type: Easing.InOutQuad }
    }
  }

  Image {
    id: img
    anchors.fill: parent
    source: root.useWhiteIcon ? Qt.resolvedUrl("assets/batman_white.png") : Qt.resolvedUrl("assets/batman_black.png")
    sourceSize.width: root.iconSize * 3
    sourceSize.height: root.iconSize * 3
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectFit
    opacity: root.pulsing ? pulseAnim.currentOpacity : 1.0

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
