import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

BarWidget {
  id: root
  moduleName: "batputer"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  // Global Pomodoro / Focus State
  property int timerMode: 0 // 0: Focus (25m), 1: Deep (50m), 2: Short Break (5m), 3: Long Break (15m)
  property int timeRemaining: 25 * 60
  property int totalDuration: 25 * 60
  property bool timerRunning: false
  property int sessionsCompleted: 0
  property int totalFocusSeconds: 0
  property bool batSignalActive: false
  property string callSign: "Master Wayne"

  // Check-in state
  property bool checkInsEnabled: true
  property int checkInIntervalMinutes: 30
  property int checkInSecondsLeft: 30 * 60

  FileView {
    id: configFile
    path: (Quickshell.env("HOME") || "") + "/.config/omarchy/batputer/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var d = Storage.parseJsonSafe(text(), null)
      if (d && d.callSign) root.callSign = d.callSign
    }
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function startTimer() {
    timerRunning = true
    Quickshell.execDetached(["omarchy-notification-send", "🦇 BatPuter Focus Mode", "Focus session started. Tactical DND active.", "-g", "󰢌"])
  }

  function pauseTimer() {
    timerRunning = false
  }

  function toggleTimer() {
    if (timerRunning) pauseTimer()
    else startTimer()
  }

  function resetTimer() {
    timerRunning = false
    setTimerDuration(timerMode)
  }

  function setTimerDuration(mode) {
    timerMode = mode
    var mins = 25
    if (mode === 1) mins = 50
    else if (mode === 2) mins = 5
    else if (mode === 3) mins = 15
    totalDuration = mins * 60
    timeRemaining = mins * 60
  }

  function onTimerFinished() {
    timerRunning = false
    if (timerMode === 0 || timerMode === 1) {
      sessionsCompleted++
      totalFocusSeconds += totalDuration
      Quickshell.execDetached(["omarchy-notification-send", "🦇 BatPuter Focus Complete", "Excellent work, " + root.callSign + ". Take a tactical break.", "-g", "󰢌"])
      setTimerDuration(2) // switch to short break
    } else {
      Quickshell.execDetached(["omarchy-notification-send", "🦇 BatPuter Break Finished", "Break time is over. Ready for the next objective, " + root.callSign + "?", "-g", "󰢌"])
      setTimerDuration(0) // switch to focus
    }
  }

  function triggerCheckIn() {
    var prompt = Storage.getNextCheckInPrompt(root.callSign)
    Quickshell.execDetached(["omarchy-notification-send", "🦇 Alfred Check-in", prompt, "-u", "normal", "-g", "󰢌"])
    checkInSecondsLeft = checkInIntervalMinutes * 60
  }

  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if (root.timerRunning) {
        if (root.timeRemaining > 0) {
          root.timeRemaining--
        } else {
          root.onTimerFinished()
        }
      }

      if (root.checkInsEnabled) {
        if (root.checkInSecondsLeft > 0) {
          root.checkInSecondsLeft--
        } else {
          root.triggerCheckIn()
        }
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    keepSpace: true
    fixedWidth: root.timerRunning ? -1 : Style.bar.iconSlot
    horizontalMargin: root.timerRunning ? 8.5 : 0
    active: root.timerRunning || root.batSignalActive
    activeColor: Color.accent
    useActiveColor: true
    tooltipText: root.timerRunning 
      ? "BatPuter (" + Storage.formatTime(root.timeRemaining) + " remaining | Right-Click: Pause)" 
      : "BatPuter AI Assistant (Click: Open HUD | Right-Click: Start Focus)"

    RowLayout {
      anchors.centerIn: parent
      spacing: Style.space(6)

      BatmanMaskIcon {
        iconSize: Style.space(18)
        maskColor: button.foreground
        active: root.timerRunning || root.batSignalActive
        pulsing: root.timerRunning
      }

      Text {
        visible: root.timerRunning
        text: Storage.formatTime(root.timeRemaining)
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        color: (root.timerMode === 2 || root.timerMode === 3) ? "#30d158" : Color.accent
      }
    }

    onPressed: (btn) => {
      if (btn === 1) {
        root.togglePanel()
      } else if (btn === 3) {
        root.toggleTimer()
      } else if (btn === 2) {
        root.resetTimer()
      }
    }
  }

  IpcHandler {
    target: "batputer"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function startFocus(): void { root.startTimer() }
    function pauseFocus(): void { root.pauseTimer() }
    function resetFocus(): void { root.resetTimer() }
    function checkIn(): void { root.triggerCheckIn() }
  }
}
