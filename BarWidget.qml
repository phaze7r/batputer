import QtQuick
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
  property int timerMode: 0 // 0: Focus (25m), 1: Deep (50m), 2: Short Break (5m), 3: Long Break (15m), -1: Custom
  property int timeRemaining: 25 * 60
  property int totalDuration: 25 * 60
  property bool timerRunning: false
  property int sessionsCompleted: 0
  property int totalFocusSeconds: 0
  property bool batSignalActive: false
  property string callSign: "Batman"
  property int streakDays: 1
  property string lastActiveDate: ""

  // Check-in state
  property bool checkInsEnabled: true
  property int checkInIntervalMinutes: 30
  property int checkInSecondsLeft: 30 * 60
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string batputerDir: home + "/.config/omarchy/batputer"
  readonly property string configPath: root.batputerDir + "/config.json"

  Process {
    id: ensureDir
    command: ["mkdir", "-p", "-m", "700", root.batputerDir]
    running: false
    onExited: configFile.reload()
  }

  // Config persistence via the shell's native atomic file writer (temp + rename)
  // — the same primitive omarchy-shell uses for shell.json / notification
  // settings. This plugin is the only writer, so watchChanges stays off.
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      var d = Storage.sanitizeConfig(Storage.parseJsonSafe(text(), null, 32768))
      root.callSign = d.callSign
      root.sessionsCompleted = d.sessionsCompleted
      root.totalFocusSeconds = d.totalFocusSeconds
      root.streakDays = d.streakDays
      root.lastActiveDate = d.lastActiveDate
      root.checkStreak()
    }
    onLoadFailed: root.checkStreak()
  }

  Component.onCompleted: {
    ensureDir.running = true
  }

  function saveConfig() {
    var data = Storage.sanitizeConfig({
      callSign: root.callSign,
      sessionsCompleted: root.sessionsCompleted,
      totalFocusSeconds: root.totalFocusSeconds,
      streakDays: root.streakDays,
      lastActiveDate: root.lastActiveDate
    })
    configFile.setText(JSON.stringify(data) + "\n")
  }

  function checkStreak() {
    var today = new Date().toISOString().split("T")[0]
    if (root.lastActiveDate === "") {
      root.lastActiveDate = today
      root.streakDays = 1
      root.saveConfig()
    } else if (root.lastActiveDate !== today) {
      var last = new Date(root.lastActiveDate)
      var now = new Date(today)
      var diffDays = Math.round((now - last) / (1000 * 60 * 60 * 24))
      if (diffDays === 1) {
        root.streakDays += 1
      } else if (diffDays > 1) {
        root.streakDays = 1
      }
      root.lastActiveDate = today
      root.saveConfig()
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

  function playChime() {
    Quickshell.execDetached([
      "bash", "-c",
      "pw-play \"$1\" 2>/dev/null || paplay \"$1\" 2>/dev/null || aplay \"$1\" 2>/dev/null",
      "--",
      root.home + "/.config/omarchy/plugins/batputer/assets/bat_finish.wav"
    ])
  }

  function sendNotification(title, message, urgencyLevel) {
    var isLightTheme = Color.background && ((Color.background.r * 0.299 + Color.background.g * 0.587 + Color.background.b * 0.114) > 0.5)
    var iconName = isLightTheme ? "batman_black.png" : "batman_white.png"
    var iconPath = root.home + "/.config/omarchy/plugins/batputer/assets/" + iconName
    var args = [
      "omarchy-notification-send",
      "--app-name", "BatPuter",
      "-i", iconPath,
      "--image", iconPath
    ]
    if (urgencyLevel) {
      args.push("-u", urgencyLevel)
    }
    args.push(title)
    if (message) {
      args.push(message)
    }
    Quickshell.execDetached(args)
  }

  function toggleBatSignal() {
    batSignalActive = !batSignalActive
    if (batSignalActive) {
      playChime()
      sendNotification("Bat-Signal Activated", "Gotham beacon searchlight illuminated.")
    } else {
      sendNotification("Bat-Signal Standby", "Beacon returned to passive surveillance.")
    }
  }

  function startTimer() {
    timerRunning = true
    sendNotification("BatPuter Focus Mode", "Patrol session started for " + root.callSign + ". Tactical DND active.")
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
    if (timerMode === -1) {
      timeRemaining = totalDuration
    } else {
      setTimerDuration(timerMode)
    }
  }

  function setTimerDuration(mode) {
    timerMode = mode
    var mins = 25
    if (mode === 1) mins = 60
    else if (mode === 2) mins = 5
    else if (mode === 3) mins = 15
    totalDuration = mins * 60
    timeRemaining = mins * 60
  }

  function setCustomMinutes(mins) {
    if (mins < 1) mins = 1
    if (mins > 180) mins = 180
    timerMode = -1
    totalDuration = mins * 60
    timeRemaining = mins * 60
  }

  function adjustMinutes(delta) {
    var cur = Math.ceil(timeRemaining / 60)
    setCustomMinutes(cur + delta)
  }

  function onTimerFinished() {
    timerRunning = false
    playChime()

    if (timerMode === 0 || timerMode === 1 || timerMode === -1) {
      sessionsCompleted++
      totalFocusSeconds += totalDuration
      root.checkStreak()
      root.saveConfig()
      sendNotification("BatPuter Focus Complete", "Patrol complete, " + root.callSign + ". Rank: " + Storage.getDetectiveRank(root.sessionsCompleted) + ". Take a tactical break.")
      setTimerDuration(2)
    } else {
      sendNotification("BatPuter Break Finished", "Break concluded. Ready for next objective, " + root.callSign + "?")
      setTimerDuration(0)
    }
  }

  function triggerCheckIn() {
    var prompt = Storage.getNextCheckInPrompt(root.callSign)
    sendNotification("Alfred Check-in", prompt, "normal")
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
    fixedWidth: Style.bar.iconSlot
    horizontalMargin: 0
    active: root.timerRunning || root.batSignalActive
    activeColor: Color.accent
    useActiveColor: true
    tooltipText: root.batSignalActive 
      ? "Bat-Signal Beacon: ACTIVE // Click to open HUD"
      : (root.timerRunning 
          ? "BatPuter Patrol (" + Storage.formatTime(root.timeRemaining) + " remaining | Right-Click: Pause)" 
          : "BatPuter AI Assistant (Click: Open HUD | Right-Click: Start Patrol)")

    Item {
      anchors.centerIn: parent
      width: Style.space(22)
      height: Style.space(22)

      // Circular Radial Progress Ring
      Canvas {
        id: progressRing
        anchors.fill: parent
        visible: root.timerRunning

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var cx = width / 2
          var cy = height / 2
          var radius = (width / 2) - 1.5
          var progress = (root.totalDuration > 0) ? (root.timeRemaining / root.totalDuration) : 0

          ctx.beginPath()
          ctx.arc(cx, cy, radius, 0, 2 * Math.PI)
          ctx.strokeStyle = Qt.rgba(button.foreground.r, button.foreground.g, button.foreground.b, 0.2)
          ctx.lineWidth = 1.8
          ctx.stroke()

          if (progress > 0) {
            ctx.beginPath()
            var startAngle = -Math.PI / 2
            var endAngle = startAngle + (2 * Math.PI * progress)
            ctx.arc(cx, cy, radius, startAngle, endAngle, false)
            ctx.strokeStyle = (root.timerMode === 2 || root.timerMode === 3) ? "#30d158" : Color.accent
            ctx.lineWidth = 1.8
            ctx.lineCap = "round"
            ctx.stroke()
          }
        }

        Connections {
          target: root
          function onTimeRemainingChanged() { progressRing.requestPaint() }
          function onTimerRunningChanged() { progressRing.requestPaint() }
        }
      }

      // Centered Batman Cowl Icon with Bat-Signal Halo
      BatmanMaskIcon {
        anchors.centerIn: parent
        iconSize: Style.space(14)
        maskColor: button.foreground
        active: root.timerRunning || root.batSignalActive
        pulsing: root.timerRunning
        batSignalActive: root.batSignalActive
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
    function toggleSignal(): void { root.toggleBatSignal() }
    function checkIn(): void { root.triggerCheckIn() }
  }
}
