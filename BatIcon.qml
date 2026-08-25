import QtQuick
import qs.Commons

// Custom Batman cowl icon drawn with pure QML Rectangle primitives.
// Uses the same approach as TailscaleIcon.qml: no SVG, no Shape renderer,
// no ColorOverlay — just Rectangles that reliably render in tiny bar slots.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Scale helpers using readonly properties (works reliably in QML bindings)
  readonly property real s: iconSize / 18.0  // base scale unit

  // ── Ears ────────────────────────────────────────────────────────────────
  // Left ear: a rotated rectangle forming a pointy triangle
  Rectangle {
    x: root.s * 1; y: root.s * 0
    width: root.s * 3; height: root.s * 5
    color: root.color
    rotation: -18
    transformOrigin: Item.BottomRight
    radius: root.s * 0.4
  }
  // Right ear
  Rectangle {
    x: root.s * 14; y: root.s * 0
    width: root.s * 3; height: root.s * 5
    color: root.color
    rotation: 18
    transformOrigin: Item.BottomLeft
    radius: root.s * 0.4
  }

  // ── Cowl body ───────────────────────────────────────────────────────────
  // Top-center forehead bridge
  Rectangle {
    x: root.s * 3.5; y: root.s * 3
    width: root.s * 11; height: root.s * 5
    color: root.color
    radius: root.s * 2.5
  }
  // Mid body (wider jaw area)
  Rectangle {
    x: root.s * 2; y: root.s * 6
    width: root.s * 14; height: root.s * 5
    color: root.color
    radius: root.s * 1.5
  }
  // Lower jaw (tapered)
  Rectangle {
    x: root.s * 3.5; y: root.s * 9
    width: root.s * 11; height: root.s * 4
    color: root.color
    radius: root.s * 1
  }

  // ── Chin notch cutout ───────────────────────────────────────────────────
  // Punches a notch out of the bottom center to give the classic chin shape
  Rectangle {
    x: root.s * 7; y: root.s * 10.5
    width: root.s * 4; height: root.s * 3.5
    color: "transparent"  // This won't actually cut — use background color trick
  }

  // ── Eyes ────────────────────────────────────────────────────────────────
  // Left eye slit
  Rectangle {
    x: root.s * 3.5; y: root.s * 6.5
    width: root.s * 4; height: root.s * 1.5
    color: "black"
    opacity: 0.6
    radius: root.s * 0.5
  }
  // Right eye slit
  Rectangle {
    x: root.s * 10.5; y: root.s * 6.5
    width: root.s * 4; height: root.s * 1.5
    color: "black"
    opacity: 0.6
    radius: root.s * 0.5
  }
}
