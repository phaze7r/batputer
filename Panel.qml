import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Storage.js" as Storage

Item {
  id: root

  property var bar: null
  property string moduleName: "batputer"
  property var settings: ({})
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool opened: panelController.open

  function open() {
    refreshData()
    panelController.show()
  }

  function close() {
    saveCurrentNote()
    panelController.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function closeForPopoutSwitch() {
    close()
  }

  PanelController {
    id: panelController
  }

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string batputerDir: home + "/.config/omarchy/batputer"

  // User & Configuration State (config is owned by the host BarWidget)
  readonly property string callSign: (root.hostWidget && root.hostWidget.callSign) ? root.hostWidget.callSign : "Batman"
  property string customMinsInput: "30"

  // Live Telemetry properties
  property string cpuLoad: "0.0"
  property string memUsage: "0%"
  property string diskUsage: "--"
  property string netDown: "0 KB/s"
  property string netUp: "0 KB/s"
  property real lastRxBytes: 0
  property real lastTxBytes: 0

  // Data models with strict bounded fallbacks
  property var agendaList: []
  property var notesData: ({ activeTab: 0, tabs: [
    { title: "Daily Log", content: "# DAILY MISSION LOG\n- Status: All systems operational\n- Focus: Complete primary objectives." },
    { title: "Scratchpad", content: "Quick ideas, tactical observations, thoughts..." },
    { title: "Snippets", content: "# USEFUL COMMANDS\nomarchy theme current\nhyprctl reload" }
  ]})
  property int activeNoteTabIndex: 0
  property int currentTab: 0
  property string newMissionTitle: ""
  property string newMissionPriority: "alpha"

  readonly property string agendaPath: root.batputerDir + "/agenda.json"
  readonly property string notesPath: root.batputerDir + "/notes.json"
  readonly property string ioScript: root.home + "/.config/omarchy/plugins/batputer/bat_read.py"

  Process {
    id: ensureDir
    command: ["mkdir", "-p", "-m", "700", root.batputerDir]
    running: false
    onExited: { agendaReader.running = true; notesReader.running = true }
  }

  // Writes: native atomic writer. Reads: bat_read.py (bounded, O_NOFOLLOW).
  FileView {
    id: agendaFile
    path: root.agendaPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    preload: false
  }

  FileView {
    id: notesFile
    path: root.notesPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    preload: false
  }

  Process {
    id: agendaReader
    command: ["python3", root.ioScript, root.agendaPath, "65536"]
    stdout: StdioCollector {
      onStreamFinished: root.agendaList = Storage.sanitizeAgenda(Storage.parseJsonSafe(text, [], 65536))
    }
  }

  Process {
    id: notesReader
    command: ["python3", root.ioScript, root.notesPath, "131072"]
    stdout: StdioCollector {
      onStreamFinished: root.applyNotes(Storage.sanitizeNotes(Storage.parseJsonSafe(text, null, 131072)))
    }
  }

  function applyNotes(data) {
    root.notesData = data
    root.activeNoteTabIndex = Math.min(Math.max(0, data.activeTab || 0), data.tabs.length - 1)
    if (noteArea && data.tabs[root.activeNoteTabIndex]) {
      noteArea.text = data.tabs[root.activeNoteTabIndex].content || ""
    }
  }

  Process {
    id: clipboardCopyProcess
    property string payload: ""
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      payload = ""
    }
  }

  // Telemetry: Direct df Process without temporary file
  Process {
    id: diskProc
    command: ["df", "-h", "/"]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = line.trim().split(/\s+/)
        if (parts.length >= 5 && parts[0] !== "Filesystem") {
          root.diskUsage = (parts[2] + "/" + parts[1]).substring(0, 20)
        }
      }
    }
  }

  // Telemetry FileViews (Standard system /proc endpoints)
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parts = text().trim().split(" ")
      if (parts.length > 0) root.cpuLoad = parts[0].substring(0, 10)
    }
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var txt = text()
      var matchTotal = txt.match(/MemTotal:\s+(\d+)/)
      var matchAvail = txt.match(/MemAvailable:\s+(\d+)/)
      if (matchTotal && matchAvail) {
        var total = parseInt(matchTotal[1])
        var avail = parseInt(matchAvail[1])
        var used = total - avail
        var pct = Math.round((used / total) * 100)
        root.memUsage = pct + "%"
      }
    }
  }

  FileView {
    id: netFile
    path: "/proc/net/dev"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.updateNetStats(text())
    }
  }

  Component.onCompleted: {
    ensureDir.running = true
    root.refreshData()
  }

  onOpenedChanged: {
    if (root.opened) {
      root.refreshData()
    }
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: {
      loadFile.reload()
      memFile.reload()
      netFile.reload()
      diskProc.running = true
    }
  }

  function updateNetStats(text) {
    if (!text) return
    var lines = text.split("\n")
    var totalRx = 0
    var totalTx = 0
    for (var i = 2; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line || line.indexOf("lo:") === 0) continue
      var parts = line.split(/\s+/)
      if (parts.length >= 10) {
        var rx = parseInt(parts[1]) || 0
        var tx = parseInt(parts[9]) || 0
        totalRx += rx
        totalTx += tx
      }
    }
    if (root.lastRxBytes > 0 && totalRx >= root.lastRxBytes) {
      var rxDiff = (totalRx - root.lastRxBytes) / 2
      var txDiff = (totalTx - root.lastTxBytes) / 2
      root.netDown = Storage.formatSpeed(rxDiff)
      root.netUp = Storage.formatSpeed(txDiff)
    }
    root.lastRxBytes = totalRx
    root.lastTxBytes = totalTx
  }

  function refreshData() {
    diskProc.running = true
    agendaReader.running = true
    notesReader.running = true
    loadFile.reload()
    memFile.reload()
    netFile.reload()
  }

  function saveCurrentNote() {
    if (!noteArea) return
    var data = Storage.sanitizeNotes(root.notesData)
    if (!data || !data.tabs || data.tabs.length === 0) return
    if (!data.tabs[root.activeNoteTabIndex]) return

    data.tabs[root.activeNoteTabIndex].content = noteArea.text.substring(0, 16384)
    data.activeTab = root.activeNoteTabIndex
    root.notesData = data

    notesFile.setText(JSON.stringify(data) + "\n")
  }

  function switchNoteTab(idx) {
    saveCurrentNote()
    root.activeNoteTabIndex = idx
    if (root.notesData && root.notesData.tabs && root.notesData.tabs[idx]) {
      noteArea.text = root.notesData.tabs[idx].content || ""
    }
  }

  function addMission() {
    var title = root.newMissionTitle.trim().substring(0, 140)
    if (!title) return
    var list = root.agendaList.slice(0, 49)
    list.unshift({
      id: Date.now(),
      title: title,
      section: "today",
      priority: root.newMissionPriority,
      completed: false,
      created: new Date().toISOString().split("T")[0]
    })
    root.agendaList = Storage.sanitizeAgenda(list)
    root.newMissionTitle = ""
    saveMissions(root.agendaList)
  }

  function toggleMission(id) {
    var list = root.agendaList.map(function(it) {
      return it.id === id ? Object.assign({}, it, { completed: !it.completed }) : it
    })
    root.agendaList = list
    saveMissions(list)
  }

  function deleteMission(id) {
    var list = root.agendaList.filter(function(it) { return it.id !== id })
    root.agendaList = list
    saveMissions(list)
  }

  function sendNotification(title, message) {
    var isLightTheme = Color.background && ((Color.background.r * 0.299 + Color.background.g * 0.587 + Color.background.b * 0.114) > 0.5)
    var iconName = isLightTheme ? "batman_black.png" : "batman_white.png"
    var iconPath = root.home + "/.config/omarchy/plugins/batputer/assets/" + iconName

    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "BatPuter",
      "-i", iconPath,
      "--image", iconPath,
      title,
      message
    ])
  }

  function clearResolvedMissions() {
    var list = root.agendaList.filter(function(it) { return !it.completed })
    root.agendaList = list
    saveMissions(list)
    sendNotification("Cases Cleared", "Completed tasks cleared from active list.")
  }

  function saveMissions(list) {
    var cleanList = Storage.sanitizeAgenda(list)
    root.agendaList = cleanList
    agendaFile.setText(JSON.stringify(cleanList) + "\n")
  }

  function promoteNoteToCase() {
    if (!noteArea) return
    var txt = noteArea.text.trim()
    if (!txt) return
    var firstLine = txt.split("\n")[0].replace(/^[#\-\*\s]+/, "").trim().substring(0, 140)
    if (!firstLine) firstLine = "Forensic Note Objective"
    
    var list = root.agendaList.slice(0, 49)
    list.unshift({
      id: Date.now(),
      title: firstLine,
      section: "today",
      priority: "alpha",
      completed: false,
      created: new Date().toISOString().split("T")[0]
    })
    root.agendaList = Storage.sanitizeAgenda(list)
    saveMissions(root.agendaList)
    root.currentTab = 1
    sendNotification("Case Dossier Created", "Note promoted to active ALPHA case objective.")
  }

  function exportDebrief() {
    var report = Storage.generateDebriefReport(
      root.callSign,
      root.hostWidget ? root.hostWidget.sessionsCompleted : 0,
      root.hostWidget ? root.hostWidget.totalFocusSeconds : 0,
      root.hostWidget ? root.hostWidget.streakDays : 1,
      root.agendaList,
      root.notesData
    )
    clipboardCopyProcess.payload = report
    clipboardCopyProcess.running = true
    sendNotification("Tactical Debrief Copied", "Daily standup report copied to clipboard.")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(520)
    contentHeight: Style.space(610)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.space(14)
      spacing: Style.space(10)

      // ── Detective Batcave Header ──────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(44)
          height: Style.space(44)
          radius: Style.space(6)
          color: Color.background
          border.color: Color.accent
          border.width: 1.5

          BatmanMaskIcon {
            anchors.centerIn: parent
            iconSize: Style.space(30)
            maskColor: Color.foreground
            active: true
            pulsing: root.hostWidget ? root.hostWidget.timerRunning : false
            batSignalActive: root.hostWidget ? root.hostWidget.batSignalActive : false
          }
        }

        ColumnLayout {
          spacing: 2

          RowLayout {
            spacing: Style.space(6)

            Text {
              text: "BATPUTER"
              textFormat: Text.PlainText
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 2
              color: Color.accent
            }

            Rectangle {
              height: Style.space(18)
              implicitWidth: Style.space(78)
              radius: Style.space(4)
              color: Color.background
              border.color: "#30d158"
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 4
                Rectangle { width: 6; height: 6; radius: 3; color: "#30d158" }
                Text {
                  text: "BATCAVE v3.1"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: 9
                  font.bold: true
                  color: "#30d158"
                }
              }
            }

            // Callsign pill badge
            Rectangle {
              height: Style.space(18)
              implicitWidth: callSignTxt.implicitWidth + Style.space(12)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.accent
              border.width: 1

              Text {
                id: callSignTxt
                anchors.centerIn: parent
                text: "🦇 " + root.callSign
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.accent
              }
            }

            // Streak Badge
            Rectangle {
              height: Style.space(18)
              implicitWidth: streakTxt.implicitWidth + Style.space(10)
              radius: Style.space(4)
              color: Color.background
              border.color: "#ff9500"
              border.width: 1

              Text {
                id: streakTxt
                anchors.centerIn: parent
                text: "🔥 " + (root.hostWidget ? root.hostWidget.streakDays : 1) + "d Streak"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: "#ff9500"
              }
            }
          }

          Text {
            text: (root.hostWidget && root.hostWidget.timerRunning)
              ? "⚡ SURVEILLANCE ACTIVE — " + Storage.formatTime(root.hostWidget.timeRemaining)
              : Storage.getDetectiveRank(root.hostWidget ? root.hostWidget.sessionsCompleted : 0) + "  //  " + root.callSign
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: (root.hostWidget && root.hostWidget.timerRunning) ? Color.accent : Color.foreground
          }
        }

        Item { Layout.fillWidth: true }
      }

      // ── High-Contrast Batcave Telemetry HUD (CPU, RAM, DISK, NET) ─────────
      Rectangle {
        Layout.fillWidth: true
        height: Style.space(28)
        radius: Style.space(4)
        color: Color.background
        border.color: Color.muted
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(8)

          // CPU
          RowLayout {
            spacing: 3
            Text { text: "CPU"; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: Color.muted }
            Text { text: root.cpuLoad; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; color: Color.accent }
          }

          // RAM
          RowLayout {
            spacing: 3
            Text { text: "RAM"; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: Color.muted }
            Text { text: root.memUsage; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; color: Color.foreground }
          }

          // DISK
          RowLayout {
            spacing: 3
            Text { text: "DISK"; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: Color.muted }
            Text { text: root.diskUsage; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 11; font.bold: true; color: Color.foreground }
          }

          // NET DOWN / UP
          RowLayout {
            spacing: 3
            Text { text: "NET"; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: Color.muted }
            Text { text: "↓ " + root.netDown; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: "#30d158" }
            Text { text: "↑ " + root.netUp; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: Color.accent }
          }

          Item { Layout.fillWidth: true }

          // SECURE LINK
          RowLayout {
            spacing: 4
            Rectangle { width: 6; height: 6; radius: 3; color: "#30d158" }
            Text { text: "LINK OK"; textFormat: Text.PlainText; font.family: Style.font.family; font.pixelSize: 10; font.bold: true; color: "#30d158" }
          }
        }
      }

      // ── Tab Bar Navigation ────────────────────────────────────────────────
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(4)

        Repeater {
          model: [
            { name: "Patrol", icon: "⏱" },
            { name: "Cases", icon: "📋" },
            { name: "Notes", icon: "📝" },
            { name: "Alfred", icon: "🦇" },
            { name: "Dashboard", icon: "📊" }
          ]
          delegate: Rectangle {
            Layout.fillWidth: true
            height: Style.space(32)
            radius: Style.space(4)
            color: root.currentTab === index ? Color.accent : Color.background
            border.color: root.currentTab === index ? Color.accent : Color.muted
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: modelData.icon
                textFormat: Text.PlainText
                font.pixelSize: Style.font.caption
              }
              Text {
                text: modelData.name
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: root.currentTab === index
                color: root.currentTab === index ? Color.background : Color.foreground
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.currentTab = index
            }
          }
        }
      }

      // ── Tab Contents ──────────────────────────────────────────────────────
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // ═════════════════════════════════════════════════════════════════════
        // Tab 0: Tactical Patrol (Pomodoro Focus + Customizable Duration)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 0
          anchors.fill: parent
          spacing: Style.space(12)

          // ── Exact Dark Knight Batarang Chronometer (From User Blueprint) ────
          Item {
            Layout.alignment: Qt.AlignHCenter
            width: Style.space(330)
            height: Style.space(175)

            Canvas {
              id: batarangCanvas
              anchors.fill: parent

              property var batPts: [
                [-1.0, -0.0033], [-0.9647, -0.1973], [-0.8941, -0.4649], [-0.7922, -0.7993], [-0.7255, -0.9666], 
                [-0.7216, -0.5251], [-0.698, -0.5117], [-0.4941, -0.4582], [-0.2471, -0.4716], [-0.2235, -0.4916], 
                [-0.1922, -0.5853], [-0.1255, -1.0], [-0.0784, -0.7124], [-0.0588, -0.7124], [-0.0196, -0.7592], 
                [0.0157, -0.7592], [0.0549, -0.7057], [0.0784, -0.7057], [0.0902, -0.7324], [0.1255, -1.0], 
                [0.2, -0.505], [0.2196, -0.4783], [0.2706, -0.4582], [0.4, -0.4582], [0.5686, -0.4916], 
                [0.7176, -0.5452], [0.7216, -0.9933], [0.8078, -0.7993], [0.902, -0.4783], [0.9922, -0.0702], 
                [1.0, 0.0702], [0.9529, 0.311], [0.8627, 0.6388], [0.8039, 0.7993], [0.7098, 0.9866], 
                [0.7059, 0.5251], [0.6863, 0.5117], [0.6078, 0.5117], [0.5255, 0.5652], [0.451, 0.6656], 
                [0.4039, 0.7726], [0.3569, 0.6589], [0.2941, 0.5719], [0.2588, 0.5518], [0.1843, 0.5652], 
                [0.1373, 0.6187], [0.0941, 0.7057], [0.0039, 1.0], [-0.0941, 0.7057], [-0.1882, 0.5652], 
                [-0.2353, 0.5452], [-0.2941, 0.5585], [-0.3412, 0.6054], [-0.4078, 0.7391], [-0.4431, 0.6522], 
                [-0.502, 0.5585], [-0.5686, 0.505], [-0.6392, 0.4916], [-0.702, 0.5184], [-0.7059, 1.0], 
                [-0.7686, 0.8796], [-0.8549, 0.6388], [-0.9569, 0.2642], [-1.0, 0.01]
              ]

              function drawExactBatarang(ctx, cx, cy, rx, ry) {
                ctx.beginPath()
                ctx.moveTo(cx + batPts[0][0] * rx, cy + batPts[0][1] * ry)
                for (var i = 1; i < batPts.length; i++) {
                  ctx.lineTo(cx + batPts[i][0] * rx, cy + batPts[i][1] * ry)
                }
                ctx.closePath()
              }

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2
                var cy = height / 2
                var rx = (width - 16) / 2
                var ry = (height - 16) / 2

                var progress = (root.hostWidget && root.hostWidget.totalDuration > 0)
                  ? (root.hostWidget.timeRemaining / root.hostWidget.totalDuration)
                  : 1.0

                var isBreak = root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)
                var arcColor = isBreak ? "#30d158" : Color.accent

                // 1. Translucent Carbon Armor Composite Body Fill
                drawExactBatarang(ctx, cx, cy, rx, ry)
                ctx.fillStyle = Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
                ctx.fill()

                // 2. Subtle Background Track Silhouette (Needle Miter Join)
                drawExactBatarang(ctx, cx, cy, rx, ry)
                ctx.strokeStyle = Qt.rgba(Color.muted.r, Color.muted.g, Color.muted.b, 0.25)
                ctx.lineWidth = 1.8
                ctx.lineJoin = "miter"
                ctx.miterLimit = 5.0
                ctx.stroke()

                // 3. Dynamic Progress Glow Tracing the Exact Batarang Perimeter
                if (progress > 0) {
                  var totalPerimeter = (rx + ry) * 4.4
                  var dashLength = totalPerimeter * progress

                  ctx.save()
                  drawExactBatarang(ctx, cx, cy, rx, ry)
                  ctx.setLineDash([dashLength, totalPerimeter])
                  ctx.lineDashOffset = 0
                  ctx.strokeStyle = arcColor
                  ctx.lineWidth = 2.8
                  ctx.lineJoin = "miter"
                  ctx.miterLimit = 5.0
                  ctx.stroke()
                  ctx.restore()
                }
              }

              Connections {
                target: root.hostWidget
                function onTimeRemainingChanged() { batarangCanvas.requestPaint() }
                function onTimerRunningChanged() { batarangCanvas.requestPaint() }
                function onTotalDurationChanged() { batarangCanvas.requestPaint() }
              }
            }

            // Minimal Center Digital Readout (Inside Batarang Core)
            ColumnLayout {
              anchors.centerIn: parent
              anchors.verticalCenterOffset: Style.space(4)
              spacing: 0

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.hostWidget ? Storage.formatTime(root.hostWidget.timeRemaining) : "25:00"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.display + Style.space(4)
                font.bold: true
                font.letterSpacing: 1.5
                color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                  ? "#30d158" : Color.accent
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                  if (!root.hostWidget) return "FOCUS // 25M"
                  if (root.hostWidget.timerMode === -1) return "CUSTOM // " + Math.round(root.hostWidget.totalDuration / 60) + "M"
                  var modes = ["FOCUS // 25M", "DEEP WORK // 60M", "REST // 5M", "RECHARGE // 15M"]
                  return modes[root.hostWidget.timerMode] || ("PATROL // " + Math.round(root.hostWidget.totalDuration / 60) + "M")
                }
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 1.0
                color: Color.foreground
                opacity: 0.85
              }
            }
          }

          // ── Row 1: Unified Tactical Time Bar (Stepper + Presets in 1 Clean Dock) ──
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(34)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.muted
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: 2
              spacing: 2

              // Quick -5m Stepper
              Rectangle {
                Layout.preferredWidth: Style.space(38)
                Layout.fillHeight: true
                radius: Style.space(3)
                color: Color.background
                border.color: Color.muted
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "-5m"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: 10
                  font.bold: true
                  color: Color.foreground
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(-5)
                }
              }

              // 4 Tactical Preset Chips
              Repeater {
                model: [
                  { label: "15m", mode: 3, mins: 15 },
                  { label: "25m", mode: 0, mins: 25 },
                  { label: "45m", mode: -1, mins: 45 },
                  { label: "60m", mode: 1, mins: 60 }
                ]

                delegate: Rectangle {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  radius: Style.space(3)

                  property bool isSelected: root.hostWidget && (
                    (modelData.mode >= 0 && root.hostWidget.timerMode === modelData.mode) ||
                    (modelData.mode === -1 && root.hostWidget.timerMode === -1 && Math.round(root.hostWidget.totalDuration / 60) === modelData.mins)
                  )

                  color: isSelected ? Color.accent : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: 11
                    font.bold: true
                    color: parent.isSelected ? Color.background : Color.foreground
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.hostWidget) {
                        if (modelData.mode >= 0) root.hostWidget.setTimerDuration(modelData.mode)
                        else root.hostWidget.setCustomMinutes(modelData.mins)
                      }
                    }
                  }
                }
              }

              // Quick +5m Stepper
              Rectangle {
                Layout.preferredWidth: Style.space(38)
                Layout.fillHeight: true
                radius: Style.space(3)
                color: Color.background
                border.color: Color.muted
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: "+5m"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: 10
                  font.bold: true
                  color: Color.foreground
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(5)
                }
              }
            }
          }

          // ── Row 2: Master Tactical Action Trigger (Start/Pause & Reset) ────
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(40)
              radius: Style.space(4)
              color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                ? "#30d158" : Color.accent

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(8)

                Text {
                  text: (root.hostWidget && root.hostWidget.timerRunning) ? "⏸" : "▶"
                  textFormat: Text.PlainText
                  font.pixelSize: 13
                  color: Color.background
                }

                Text {
                  text: (root.hostWidget && root.hostWidget.timerRunning) ? "PAUSE PATROL" : "COMMENCE PATROL"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1.0
                  color: Color.background
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.toggleTimer()
              }
            }

            Rectangle {
              height: Style.space(40)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1
              implicitWidth: Style.space(88)

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text { text: "↺"; textFormat: Text.PlainText; font.pixelSize: 13; color: Color.foreground }
                Text {
                  text: "Reset"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.foreground
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.resetTimer()
              }
            }
          }

          // ── Row 3: Standup Debrief Export ─────────────────────────────────
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(32)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)
              Text { text: "📋"; textFormat: Text.PlainText; font.pixelSize: Style.font.caption }
              Text {
                text: "Export Daily Standup Debrief"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.accent
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.exportDebrief()
            }
          }

          Item { Layout.fillHeight: true }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 1: Case Files (Active Agenda & To-Do List)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 1
          anchors.fill: parent
          spacing: Style.space(8)

          // Input Row (Proportional 38px height)
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            TextField {
              id: missionInput
              Layout.fillWidth: true
              implicitHeight: Style.space(38)
              placeholderText: "Log new case objective / to-do..."
              text: root.newMissionTitle
              maximumLength: 140
              onTextChanged: root.newMissionTitle = text
              onAccepted: root.addMission()
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.foreground
              leftPadding: Style.space(10)
              rightPadding: Style.space(10)
              background: Rectangle {
                radius: Style.space(4)
                color: Color.background
                border.color: Color.accent
                border.width: 1
              }
            }

            ComboBox {
              id: priorityCombo
              textRole: "text"
              valueRole: "value"
              model: [
                { text: "OMEGA", value: "omega" },
                { text: "ALPHA", value: "alpha" },
                { text: "BETA",  value: "beta" },
                { text: "GAMMA", value: "gamma" }
              ]
              currentIndex: 1
              onCurrentValueChanged: root.newMissionPriority = currentValue
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              implicitWidth: Style.space(100)
              implicitHeight: Style.space(38)
              
              background: Rectangle {
                implicitHeight: Style.space(38)
                radius: Style.space(4)
                color: Color.background
                border.color: Storage.priorityColor(priorityCombo.currentValue, Color.accent)
                border.width: 1
              }

              contentItem: Text {
                leftPadding: Style.space(10)
                rightPadding: Style.space(10)
                text: priorityCombo.displayText
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Storage.priorityColor(priorityCombo.currentValue, Color.accent)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
              }

              delegate: ItemDelegate {
                width: priorityCombo.width
                implicitHeight: Style.space(32)
                highlighted: priorityCombo.highlightedIndex === index
                background: Rectangle {
                  radius: Style.space(3)
                  color: priorityCombo.highlightedIndex === index ? Color.accent : Color.background
                }
                contentItem: Text {
                  leftPadding: Style.space(8)
                  text: modelData.text
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: priorityCombo.highlightedIndex === index ? Color.background : Storage.priorityColor(modelData.value, Color.accent)
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              popup: Popup {
                y: priorityCombo.height + Style.space(3)
                width: priorityCombo.width
                padding: Style.space(3)
                background: Rectangle {
                  radius: Style.space(4)
                  color: Color.background
                  border.color: Color.accent
                  border.width: 1
                }
                contentItem: ListView {
                  implicitHeight: contentHeight
                  model: priorityCombo.popup.visible ? priorityCombo.delegateModel : null
                  clip: true
                  spacing: Style.space(2)
                }
              }
            }

            Rectangle {
              width: Style.space(38)
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.accent

              Text {
                anchors.centerIn: parent
                text: "+"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Style.font.heading
                color: Color.background
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addMission()
              }
            }
          }

          // Case Dossiers List
          ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
              model: root.agendaList
              spacing: Style.space(6)

              delegate: Item {
                width: ListView.view.width
                height: mRow.implicitHeight + Style.space(16)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: Color.background
                  border.color: Storage.priorityColor(modelData.priority, Color.accent)
                  border.width: 1
                  opacity: modelData.completed ? 0.45 : 1.0
                }

                RowLayout {
                  id: mRow
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(8)

                  // Threat Badge
                  Rectangle {
                    height: Style.space(20)
                    implicitWidth: threatTxt.implicitWidth + Style.space(8)
                    radius: Style.space(3)
                    color: Color.background
                    border.color: Storage.priorityColor(modelData.priority, Color.accent)
                    border.width: 1

                    Text {
                      id: threatTxt
                      anchors.centerIn: parent
                      text: Storage.priorityLabel(modelData.priority)
                      textFormat: Text.PlainText
                      font.family: Style.font.family
                      font.pixelSize: 9
                      font.bold: true
                      color: Storage.priorityColor(modelData.priority, Color.accent)
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.title || modelData.text || ""
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: Color.foreground
                    wrapMode: Text.WordWrap
                    font.strikeout: modelData.completed
                  }

                  // Resolve Case
                  Text {
                    text: modelData.completed ? "✓" : "○"
                    textFormat: Text.PlainText
                    font.pixelSize: Style.font.heading
                    color: modelData.completed ? "#30d158" : Color.muted
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleMission(modelData.id)
                    }
                  }

                  // Minimal Delete
                  Rectangle {
                    height: Style.space(20)
                    implicitWidth: Style.space(28)
                    radius: Style.space(3)
                    color: Color.background
                    border.color: Color.muted
                    border.width: 1

                    Text {
                      anchors.centerIn: parent
                      text: "Del"
                      textFormat: Text.PlainText
                      font.family: Style.font.family
                      font.pixelSize: 9
                      color: Color.muted
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.deleteMission(modelData.id)
                    }
                  }
                }
              }
            }
          }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 2: Notes (Simplified 3-Category Scratchpad + Note-to-Case Promo)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 2
          anchors.fill: parent
          spacing: Style.space(8)

          // Fixed category switcher
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
              model: ["Daily Log", "Scratchpad", "Snippets"]
              delegate: Rectangle {
                Layout.fillWidth: true
                height: Style.space(28)
                radius: Style.space(4)
                color: root.activeNoteTabIndex === index ? Color.accent : Color.background
                border.color: root.activeNoteTabIndex === index ? Color.accent : Color.muted
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: modelData
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: root.activeNoteTabIndex === index
                  color: root.activeNoteTabIndex === index ? Color.background : Color.foreground
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchNoteTab(index)
                }
              }
            }
          }

          TextArea {
            id: noteArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            textFormat: TextEdit.PlainText
            placeholderText: "Type notes, thoughts, tasks, code snippets here..."
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.foreground
            wrapMode: TextEdit.WordWrap
            onTextChanged: noteSaveTimer.restart()
            background: Rectangle {
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1
            }
          }

          // Debounced autosave (same pattern omarchy's notifications plugin
          // uses to flush its settings). Notes also save on tab switch / close.
          Timer {
            id: noteSaveTimer
            interval: 400
            onTriggered: root.saveCurrentNote()
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Text {
              text: (noteArea ? noteArea.text.length : 0) + " characters"
              textFormat: Text.PlainText
              font.family: Style.font.family
              font.pixelSize: 10
              font.bold: true
              color: Color.muted
            }

            Item { Layout.fillWidth: true }

            Rectangle {
              height: Style.space(32)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.accent
              border.width: 1
              implicitWidth: Style.space(130)

              Text {
                anchors.centerIn: parent
                text: "Promote to Case"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.accent
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.promoteNoteToCase()
              }
            }
          }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 3: Alfred Comms (Tactical Comms Channel)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 3
          anchors.fill: parent
          spacing: Style.space(12)

          Rectangle {
            Layout.fillWidth: true
            height: Style.space(85)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(4)

              RowLayout {
                spacing: 6
                Rectangle { width: 7; height: 7; radius: 3.5; color: "#30d158" }
                Text {
                  text: "ALFRED PENNYWORTH // ENCRYPTED COMMS"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.font.bodySmall
                  color: Color.accent
                }
              }

              Text {
                text: "Next scheduled briefing for " + root.callSign + " in: " + (root.hostWidget ? Storage.formatTime(root.hostWidget.checkInSecondsLeft) : "--:--")
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Color.foreground
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            height: Style.space(42)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(6)
              Text { text: "🎙"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
              Text {
                text: "Request Tactical Briefing from Alfred"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: Color.accent
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.hostWidget) root.hostWidget.triggerCheckIn()
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Style.space(4)
            color: Color.background
            border.color: Color.muted
            border.width: 1

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              spacing: Style.space(6)

              Text {
                text: "ALFRED'S DIRECTIVE:"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: 10
                font.bold: true
                color: Color.muted
              }

              Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: "“Remember, " + root.callSign + ", the mind is your sharpest batarang. Periodic tactical pauses prevent forensic fatigue and sharpen your deduction.”"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.foreground
              }

              Item { Layout.fillHeight: true }
            }
          }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 4: Daily Productivity Dashboard & Tactical System Controls
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 4
          anchors.fill: parent
          spacing: Style.space(10)

          // ── Today's Mission Stats Card ────────────────────────────────────
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(110)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Text { text: "📊"; textFormat: Text.PlainText; font.pixelSize: Style.font.caption }
                Text {
                  text: "TODAY'S MISSION DASHBOARD"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.font.caption
                  color: Color.accent
                }
                Item { Layout.fillWidth: true }
                Text {
                  text: Storage.getDetectiveRank(root.hostWidget ? root.hostWidget.sessionsCompleted : 0)
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: 10
                  color: Color.foreground
                }
              }

              // Row 1: Cases Summary + Clear Done Button
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  text: "Case Files:"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.muted
                }

                Text {
                  readonly property int activeCount: root.agendaList.filter(function(it){ return !it.completed }).length
                  readonly property int resolvedCount: root.agendaList.filter(function(it){ return it.completed }).length
                  text: activeCount + " Active  •  " + resolvedCount + " Resolved"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                  height: Style.space(24)
                  implicitWidth: Style.space(80)
                  radius: Style.space(3)
                  color: Color.background
                  border.color: Color.muted
                  border.width: 1

                  Text {
                    anchors.centerIn: parent
                    text: "Clear Done"
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: 9
                    font.bold: true
                    color: Color.foreground
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearResolvedMissions()
                  }
                }
              }

              // Row 2: Focus Time + Copy Standup Button
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)

                Text {
                  text: "Patrol Time:"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.muted
                }

                Text {
                  text: Storage.formatDuration(root.hostWidget ? root.hostWidget.totalFocusSeconds : 0) + " (" + (root.hostWidget ? root.hostWidget.sessionsCompleted : 0) + " missions)"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.accent
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                  height: Style.space(24)
                  implicitWidth: Style.space(90)
                  radius: Style.space(3)
                  color: Color.accent

                  Text {
                    anchors.centerIn: parent
                    text: "Copy Standup"
                    textFormat: Text.PlainText
                    font.family: Style.font.family
                    font.pixelSize: 9
                    font.bold: true
                    color: Color.background
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.exportDebrief()
                  }
                }
              }
            }
          }

          // ── Tactical System Controls ──────────────────────────────────────
          Text {
            text: "Tactical System Controls"
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.bodySmall
            color: Color.foreground
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            // Bat-Signal Mode
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: (root.hostWidget && root.hostWidget.batSignalActive) ? Color.accent : Color.muted
              border.width: (root.hostWidget && root.hostWidget.batSignalActive) ? 1.5 : 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "⚡"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Bat-Signal Mode"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: (root.hostWidget && root.hostWidget.batSignalActive) ? Color.accent : Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.hostWidget) root.hostWidget.toggleBatSignal()
                }
              }
            }

            // Mute
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "🔇"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Toggle Mute"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"])
                  root.close()
                }
              }
            }

            // Night Light
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "🌙"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Night Light"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["omarchy", "toggle", "nightlight"])
                  root.close()
                }
              }
            }

            // Screenshot
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "📸"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Screenshot"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["omarchy", "capture", "screenshot"])
                  root.close()
                }
              }
            }

            // Lockdown
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "🔒"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Lock Screen"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["omarchy", "system", "lock"])
                  root.close()
                }
              }
            }

            // Reload Shell
            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 6
                Text { text: "🔄"; textFormat: Text.PlainText; font.pixelSize: Style.font.body }
                Text {
                  text: "Reload Shell"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["omarchy", "restart", "shell"])
                  root.close()
                }
              }
            }
          }

          Item { Layout.fillHeight: true }
        }
      }
    }
  }
}
