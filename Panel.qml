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

  // User & Configuration State
  property string callSign: "Master Wayne"
  property bool editingCallSign: false
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

  // Secure File & Clipboard Process Writers (Data streams over stdin, never in process argv)
  Process {
    id: configSaver
    property string payload: ""
    command: ["tee", root.batputerDir + "/config.json"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
    }
  }

  Process {
    id: agendaSaver
    property string payload: ""
    command: ["tee", root.batputerDir + "/agenda.json"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
    }
  }

  Process {
    id: notesSaver
    property string payload: ""
    command: ["tee", root.batputerDir + "/notes.json"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
    }
  }

  Process {
    id: clipboardCopyProcess
    property string payload: ""
    command: ["wl-copy"]
    stdinEnabled: true
    onStarted: {
      write(payload)
      payload = ""
    }
  }

  // Telemetry FileViews
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
    id: diskFile
    path: "/tmp/batputer_disk"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var t = text().trim()
      if (t) root.diskUsage = t.substring(0, 20)
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

  FileView {
    id: configFile
    path: root.batputerDir + "/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = Storage.parseJsonSafe(text(), null, 32768)
      var d = Storage.sanitizeConfig(raw)
      if (d && d.callSign) root.callSign = d.callSign
    }
  }

  FileView {
    id: agendaFile
    path: root.batputerDir + "/agenda.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = Storage.parseJsonSafe(text(), [], 65536)
      root.agendaList = Storage.sanitizeAgenda(raw)
    }
  }

  FileView {
    id: notesFile
    path: root.batputerDir + "/notes.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = Storage.parseJsonSafe(text(), null, 131072)
      var data = Storage.sanitizeNotes(raw)
      root.notesData = data
      root.activeNoteTabIndex = Math.min(Math.max(0, data.activeTab || 0), data.tabs.length - 1)
      if (noteArea && data.tabs[root.activeNoteTabIndex]) {
        noteArea.text = data.tabs[root.activeNoteTabIndex].content || ""
      }
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
      root.updateDisk()
    }
  }

  function updateDisk() {
    Quickshell.execDetached(["bash", "-c",
      "df -h / | awk 'NR==2 {print $3 \"/\" $2}' > /tmp/batputer_disk"
    ])
    diskFile.reload()
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
    Quickshell.execDetached(["mkdir", "-p", root.batputerDir])
    updateDisk()
    configFile.reload()
    agendaFile.reload()
    notesFile.reload()
    loadFile.reload()
    memFile.reload()
    netFile.reload()
  }

  function saveConfig() {
    var data = Storage.sanitizeConfig({
      callSign: root.callSign,
      sessionsCompleted: root.hostWidget ? root.hostWidget.sessionsCompleted : 0,
      totalFocusSeconds: root.hostWidget ? root.hostWidget.totalFocusSeconds : 0,
      streakDays: root.hostWidget ? root.hostWidget.streakDays : 1,
      lastActiveDate: root.hostWidget ? root.hostWidget.lastActiveDate : ""
    })
    configSaver.payload = JSON.stringify(data, null, 2)
    configSaver.running = true
  }

  function saveCurrentNote() {
    if (!noteArea) return
    var data = Storage.sanitizeNotes(root.notesData)
    if (!data || !data.tabs || data.tabs.length === 0) return
    if (!data.tabs[root.activeNoteTabIndex]) return

    data.tabs[root.activeNoteTabIndex].content = noteArea.text.substring(0, 16384)
    data.activeTab = root.activeNoteTabIndex
    root.notesData = data

    notesSaver.payload = JSON.stringify(data, null, 2)
    notesSaver.running = true
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

  function clearResolvedMissions() {
    var list = root.agendaList.filter(function(it) { return !it.completed })
    root.agendaList = list
    saveMissions(list)
    Quickshell.execDetached(["omarchy-notification-send", "Cases Cleared", "Completed tasks cleared from active list.", "-g", "󰢌"])
  }

  function saveMissions(list) {
    var cleanList = Storage.sanitizeAgenda(list)
    agendaSaver.payload = JSON.stringify(cleanList, null, 2)
    agendaSaver.running = true
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
    Quickshell.execDetached(["omarchy-notification-send", "Case Dossier Created", "Note promoted to active ALPHA case objective.", "-g", "󰢌"])
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
    Quickshell.execDetached(["omarchy-notification-send", "Tactical Debrief Copied", "Daily standup report copied to clipboard.", "-g", "󰢌"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: Style.space(520)
    contentHeight: Style.space(590)

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
                  text: "BATCAVE v3.0"
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
                text: root.callSign
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.accent
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editingCallSign = !root.editingCallSign
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

      // Callsign In-line Editor Row
      RowLayout {
        visible: root.editingCallSign
        Layout.fillWidth: true
        spacing: Style.space(6)

        Text {
          text: "Detective Callsign:"
          textFormat: Text.PlainText
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          color: Color.foreground
        }

        TextField {
          id: callSignInput
          Layout.fillWidth: true
          text: root.callSign
          placeholderText: "e.g. Master Wayne, The Detective, Bruce..."
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          color: Color.foreground
          maximumLength: 32
          background: Rectangle {
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1
          }
          onAccepted: {
            if (text.trim() !== "") {
              root.callSign = text.trim().substring(0, 32)
              root.saveConfig()
            }
            root.editingCallSign = false
          }
        }

        Rectangle {
          height: Style.space(30)
          implicitWidth: Style.space(60)
          radius: Style.space(4)
          color: Color.accent

          Text {
            anchors.centerIn: parent
            text: "Save"
            textFormat: Text.PlainText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            color: Color.background
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (callSignInput.text.trim() !== "") {
                root.callSign = callSignInput.text.trim().substring(0, 32)
                root.saveConfig()
              }
              root.editingCallSign = false
            }
          }
        }
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
          spacing: Style.space(10)

          // Radar-style circular timer
          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: Style.space(136)
            height: Style.space(136)
            radius: width / 2
            color: Color.background
            border.color: (root.hostWidget && root.hostWidget.timerRunning) ? Color.accent : Color.muted
            border.width: 2

            Rectangle {
              anchors.centerIn: parent
              width: parent.width - Style.space(16)
              height: parent.height - Style.space(16)
              radius: width / 2
              color: "transparent"
              border.color: Color.accent
              border.width: 1
              opacity: (root.hostWidget && root.hostWidget.timerRunning) ? 0.6 : 0.2
            }

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.space(2)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.hostWidget ? Storage.formatTime(root.hostWidget.timeRemaining) : "25:00"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
                color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                  ? "#30d158" : Color.accent
              }
              Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                  if (!root.hostWidget) return "Patrol Session"
                  if (root.hostWidget.timerMode === -1) return "Custom Duration"
                  var modes = ["25m Focus", "50m Deep Work", "5m Rest", "15m Recharge"]
                  return modes[root.hostWidget.timerMode] || "Patrol Session"
                }
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: Color.foreground
                opacity: 0.8
              }
            }
          }

          // Quick Presets
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Repeater {
              model: [
                { label: "15m", mode: 3, mins: 15 },
                { label: "25m", mode: 0, mins: 25 },
                { label: "45m", mode: -1, mins: 45 },
                { label: "60m", mode: 1, mins: 60 }
              ]
              delegate: Rectangle {
                Layout.fillWidth: true
                height: Style.space(28)
                radius: Style.space(4)
                color: (root.hostWidget && (root.hostWidget.timerMode === modelData.mode || Math.round(root.hostWidget.totalDuration / 60) === modelData.mins)) ? Color.accent : Color.background
                border.color: Color.accent
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: (root.hostWidget && (root.hostWidget.timerMode === modelData.mode || Math.round(root.hostWidget.totalDuration / 60) === modelData.mins)) ? Color.background : Color.foreground
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
          }

          // Custom Duration Adjuster
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Rectangle {
              height: Style.space(30)
              implicitWidth: Style.space(70)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "- 5m"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.foreground
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.adjustMinutes(-5)
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(30)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: Style.space(6)
                Text {
                  text: "Duration:"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Text {
                  text: (root.hostWidget ? Math.round(root.hostWidget.totalDuration / 60) : 25) + " min"
                  textFormat: Text.PlainText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: Color.accent
                }
              }
            }

            Rectangle {
              height: Style.space(30)
              implicitWidth: Style.space(70)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "+ 5m"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
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

          // Patrol Controls
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(38)
              radius: Style.space(4)
              color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                ? "#30d158" : Color.accent

              Text {
                anchors.centerIn: parent
                text: (root.hostWidget && root.hostWidget.timerRunning) ? "PAUSE PATROL" : "COMMENCE PATROL"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.bold: true
                font.pixelSize: Style.font.body
                color: Color.background
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.toggleTimer()
              }
            }

            Rectangle {
              height: Style.space(38)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1
              implicitWidth: Style.space(90)

              Text {
                anchors.centerIn: parent
                text: "Reset"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.foreground
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.resetTimer()
              }
            }
          }

          // Standup Export Button
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
            background: Rectangle {
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1
            }
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

            Rectangle {
              height: Style.space(32)
              radius: Style.space(4)
              color: Color.accent
              implicitWidth: Style.space(100)

              Text {
                anchors.centerIn: parent
                text: "Save Note"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.background
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.saveCurrentNote()
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
                  Quickshell.execDetached(["bash", "-c", "pactl set-sink-mute @DEFAULT_SINK@ toggle"])
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
