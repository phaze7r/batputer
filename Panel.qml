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

  // Telemetry properties
  property string cpuLoad: "0.0"
  property string memUsage: "0%"

  // Data models
  property var agendaList: []
  property var notesData: ({ activeTab: 0, tabs: [
    { title: "Forensic Analysis", content: "# GOTHAM FORENSIC DOSSIER\n- Target: Arkham Security Perimeter\n- Status: Under Investigation\n- Evidence: Encrypted micro-drives recovered at site." },
    { title: "Case Dossier", content: "# CASE FILE: J-89\n- Telemetry: High frequency radio bursts detected downtown.\n- Hypothesis: Rogue transmission grid." },
    { title: "Wayne Directives", content: "# WAYNE TECH PROTOCOLS\n- Maintain quantum encryption at all times.\n- Batmobile remote standby: Ready." }
  ]})
  property int activeNoteTabIndex: 0
  property int currentTab: 0
  property string agendaFilter: "all"
  property string newMissionTitle: ""
  property string newMissionPriority: "high"

  // Telemetry FileViews
  FileView {
    id: loadFile
    path: "/proc/loadavg"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parts = text().trim().split(" ")
      if (parts.length > 0) root.cpuLoad = parts[0]
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
    id: configFile
    path: root.batputerDir + "/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var d = Storage.parseJsonSafe(text(), null)
      if (d && d.callSign) root.callSign = d.callSign
    }
  }

  FileView {
    id: agendaFile
    path: root.batputerDir + "/agenda.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var data = Storage.parseJsonSafe(text(), [])
      if (Array.isArray(data)) root.agendaList = data
    }
  }

  FileView {
    id: notesFile
    path: root.batputerDir + "/notes.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var data = Storage.parseJsonSafe(text(), null)
      if (data && data.tabs && data.tabs.length > 0) {
        root.notesData = data
        root.activeNoteTabIndex = Math.min(Math.max(0, data.activeTab || 0), data.tabs.length - 1)
        if (noteArea && data.tabs[root.activeNoteTabIndex]) {
          noteArea.text = data.tabs[root.activeNoteTabIndex].content || ""
        }
      }
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: {
      loadFile.reload()
      memFile.reload()
    }
  }

  function refreshData() {
    Quickshell.execDetached(["mkdir", "-p", root.batputerDir])
    configFile.reload()
    agendaFile.reload()
    notesFile.reload()
    loadFile.reload()
    memFile.reload()
  }

  function saveConfig() {
    var data = { callSign: root.callSign }
    Quickshell.execDetached(["bash", "-c",
      "printf '%s' '" + JSON.stringify(data).replace(/'/g, "'\\''") +
      "' > '" + root.batputerDir + "/config.json'"])
  }

  function saveCurrentNote() {
    if (!noteArea) return
    var data = root.notesData
    if (!data || !data.tabs || data.tabs.length === 0) return
    if (!data.tabs[root.activeNoteTabIndex]) return

    data.tabs[root.activeNoteTabIndex].content = noteArea.text
    data.activeTab = root.activeNoteTabIndex
    root.notesData = data

    Quickshell.execDetached(["bash", "-c",
      "printf '%s' '" + JSON.stringify(data).replace(/'/g, "'\\''") +
      "' > '" + root.batputerDir + "/notes.json'"])
  }

  function switchNoteTab(idx) {
    saveCurrentNote()
    root.activeNoteTabIndex = idx
    if (root.notesData && root.notesData.tabs && root.notesData.tabs[idx]) {
      noteArea.text = root.notesData.tabs[idx].content || ""
    }
  }

  function addNoteTab() {
    saveCurrentNote()
    var data = root.notesData
    if (!data.tabs) data.tabs = []
    data.tabs.push({
      title: "Dossier " + (data.tabs.length + 1),
      content: "# DOSSIER " + (data.tabs.length + 1) + "\n"
    })
    root.notesData = data
    root.activeNoteTabIndex = data.tabs.length - 1
    if (noteArea) noteArea.text = "# DOSSIER " + data.tabs.length + "\n"
    saveCurrentNote()
  }

  function deleteNoteTab(idx) {
    var data = root.notesData
    if (!data.tabs || data.tabs.length <= 1) return
    data.tabs.splice(idx, 1)
    root.activeNoteTabIndex = Math.max(0, idx - 1)
    root.notesData = data
    if (noteArea && data.tabs[root.activeNoteTabIndex]) {
      noteArea.text = data.tabs[root.activeNoteTabIndex].content || ""
    }
    saveCurrentNote()
  }

  function addMission() {
    var title = root.newMissionTitle.trim()
    if (!title) return
    var list = root.agendaList.slice()
    list.unshift({
      id: Date.now(),
      title: title,
      section: "today",
      priority: root.newMissionPriority,
      completed: false,
      created: new Date().toISOString().split("T")[0]
    })
    root.agendaList = list
    root.newMissionTitle = ""
    saveMissions(list)
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

  function saveMissions(list) {
    Quickshell.execDetached(["bash", "-c",
      "printf '%s' '" + JSON.stringify(list).replace(/'/g, "'\\''") +
      "' > '" + root.batputerDir + "/agenda.json'"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    contentWidth: Style.space(510)
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
          width: Style.space(42)
          height: Style.space(42)
          radius: Style.space(6)
          color: Color.background
          border.color: Color.accent
          border.width: 1.5

          BatmanMaskIcon {
            anchors.centerIn: parent
            iconSize: Style.space(28)
            maskColor: Color.accent
            active: true
            pulsing: root.hostWidget ? root.hostWidget.timerRunning : false
          }
        }

        ColumnLayout {
          spacing: 1

          RowLayout {
            spacing: Style.space(6)

            Text {
              text: "BATPUTER"
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 2
              color: Color.accent
            }

            Rectangle {
              height: Style.space(16)
              implicitWidth: Style.space(76)
              radius: Style.space(3)
              color: Color.background
              border.color: "#30d158"
              border.width: 1

              RowLayout {
                anchors.centerIn: parent
                spacing: 3
                Rectangle { width: 5; height: 5; radius: 2.5; color: "#30d158" }
                Text {
                  text: "BATCAVE v2.4"
                  font.family: Style.font.family
                  font.pixelSize: 8
                  font.bold: true
                  color: "#30d158"
                }
              }
            }

            // Callsign pill badge
            Rectangle {
              height: Style.space(18)
              implicitWidth: callSignTxt.implicitWidth + Style.space(10)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.accent
              border.width: 1

              Text {
                id: callSignTxt
                anchors.centerIn: parent
                text: "👤 " + root.callSign
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
          }

          Text {
            text: (root.hostWidget && root.hostWidget.timerRunning)
              ? "⚡ SURVEILLANCE ACTIVE — " + Storage.formatTime(root.hostWidget.timeRemaining)
              : "Gotham Tactical Terminal // Detective " + root.callSign
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: (root.hostWidget && root.hostWidget.timerRunning) ? Color.accent : Color.muted
          }
        }

        Item { Layout.fillWidth: true }

        Rectangle {
          width: Style.space(28)
          height: Style.space(28)
          radius: Style.space(4)
          color: Color.background
          border.color: Color.muted
          border.width: 1

          Text {
            anchors.centerIn: parent
            text: "✕"
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            color: Color.muted
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close()
          }
        }
      }

      // Callsign In-line Editor Row (Appears when clicked)
      RowLayout {
        visible: root.editingCallSign
        Layout.fillWidth: true
        spacing: Style.space(6)

        Text {
          text: "Detective Callsign:"
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.muted
        }

        TextField {
          id: callSignInput
          Layout.fillWidth: true
          text: root.callSign
          placeholderText: "e.g. Master Wayne, The Detective, Bruce..."
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          color: Color.foreground
          background: Rectangle {
            radius: Style.space(4)
            color: Color.background
            border.color: Color.accent
            border.width: 1
          }
          onAccepted: {
            if (text.trim() !== "") {
              root.callSign = text.trim()
              root.saveConfig()
            }
            root.editingCallSign = false
          }
        }

        Rectangle {
          height: Style.space(26)
          implicitWidth: Style.space(55)
          radius: Style.space(4)
          color: Color.accent

          Text {
            anchors.centerIn: parent
            text: "Save"
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
                root.callSign = callSignInput.text.trim()
                root.saveConfig()
              }
              root.editingCallSign = false
            }
          }
        }
      }

      // ── Batcave Telemetry Banner ──────────────────────────────────────────
      Rectangle {
        Layout.fillWidth: true
        height: Style.space(24)
        radius: Style.space(4)
        color: Color.background
        border.color: Color.muted
        border.width: 1

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(12)

          RowLayout {
            spacing: 4
            Text { text: "CPU LOAD:"; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; color: Color.muted }
            Text { text: root.cpuLoad; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; color: Color.accent }
          }

          RowLayout {
            spacing: 4
            Text { text: "MEM USAGE:"; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; color: Color.muted }
            Text { text: root.memUsage; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; color: Color.foreground }
          }

          Item { Layout.fillWidth: true }

          RowLayout {
            spacing: 4
            Rectangle { width: 6; height: 6; radius: 3; color: "#30d158" }
            Text { text: "WAYNE SECURE LINK"; font.family: Style.font.family; font.pixelSize: 9; font.bold: true; color: Color.muted }
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
            { name: "Cases", icon: "📂" },
            { name: "Forensics", icon: "📜" },
            { name: "Alfred Comms", icon: "🎙" },
            { name: "Batcave Ops", icon: "⚡" }
          ]
          delegate: Rectangle {
            Layout.fillWidth: true
            height: Style.space(30)
            radius: Style.space(4)
            color: root.currentTab === index ? Color.accent : Color.background
            border.color: root.currentTab === index ? Color.accent : Color.muted
            border.width: 1

            RowLayout {
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: modelData.icon
                font.pixelSize: Style.font.caption
              }
              Text {
                text: modelData.name
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
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
        // Tab 0: Tactical Patrol (Pomodoro Focus)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 0
          anchors.fill: parent
          spacing: Style.space(12)

          // Radar-style circular timer
          Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: Style.space(150)
            height: Style.space(150)
            radius: width / 2
            color: Color.background
            border.color: (root.hostWidget && root.hostWidget.timerRunning) ? Color.accent : Color.muted
            border.width: 2

            // Outer radar pulse circle
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
                font.family: Style.font.family
                font.pixelSize: Style.font.display
                font.bold: true
                color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                  ? "#30d158" : Color.accent
              }
              Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                  if (!root.hostWidget) return "Patrol Focus"
                  var modes = ["25m Surveillance", "50m Deep Investigation", "5m Tactical Rest", "15m Batcave Recharge"]
                  return modes[root.hostWidget.timerMode] || "Patrol Focus"
                }
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.muted
              }
            }
          }

          // Tactical Patrol Presets
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)
            Repeater {
              model: [
                { label: "25m Patrol", mode: 0 },
                { label: "50m Investigate", mode: 1 },
                { label: "5m Rest", mode: 2 },
                { label: "15m Recharge", mode: 3 }
              ]
              delegate: Rectangle {
                Layout.fillWidth: true
                height: Style.space(32)
                radius: Style.space(4)
                color: (root.hostWidget && root.hostWidget.timerMode === modelData.mode) ? Color.accent : Color.background
                border.color: Color.accent
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: root.hostWidget && root.hostWidget.timerMode === modelData.mode
                  color: (root.hostWidget && root.hostWidget.timerMode === modelData.mode) ? Color.background : Color.foreground
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hostWidget) root.hostWidget.setTimerDuration(modelData.mode)
                }
              }
            }
          }

          // Patrol Controls
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)

            Rectangle {
              Layout.fillWidth: true
              height: Style.space(40)
              radius: Style.space(4)
              color: (root.hostWidget && (root.hostWidget.timerMode === 2 || root.hostWidget.timerMode === 3)) 
                ? "#30d158" : Color.accent

              Text {
                anchors.centerIn: parent
                text: (root.hostWidget && root.hostWidget.timerRunning) ? "⏸  PAUSE PATROL" : "▶  COMMENCE PATROL"
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
              height: Style.space(40)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1
              implicitWidth: Style.space(90)

              Text {
                anchors.centerIn: parent
                text: "↺  Reset"
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

          // Tactical Summary
          Rectangle {
            Layout.fillWidth: true
            height: Style.space(48)
            radius: Style.space(4)
            color: Color.background
            border.color: Color.muted
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.margins: Style.space(8)

              ColumnLayout {
                spacing: 1
                Text {
                  text: "Patrol Sessions Completed"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Text {
                  text: (root.hostWidget ? root.hostWidget.sessionsCompleted : 0) + " Missions"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.accent
                }
              }

              Item { Layout.fillWidth: true }

              ColumnLayout {
                spacing: 1
                Text {
                  text: "Total Gotham Surveillance"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Text {
                  text: Storage.formatDuration(root.hostWidget ? root.hostWidget.totalFocusSeconds : 0)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }
              }
            }
          }

          Item { Layout.fillHeight: true }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 1: Case Files (Active Dossiers)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 1
          anchors.fill: parent
          spacing: Style.space(8)

          // Input Row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            TextField {
              id: missionInput
              Layout.fillWidth: true
              placeholderText: "Log new active case objective / target..."
              text: root.newMissionTitle
              onTextChanged: root.newMissionTitle = text
              onAccepted: root.addMission()
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              color: Color.foreground
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
              implicitWidth: Style.space(90)
              
              background: Rectangle {
                radius: Style.space(4)
                color: Color.background
                border.color: Storage.priorityColor(priorityCombo.currentValue, Color.accent)
                border.width: 1
              }

              contentItem: Text {
                leftPadding: Style.space(8)
                rightPadding: Style.space(8)
                text: priorityCombo.displayText
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Storage.priorityColor(priorityCombo.currentValue, Color.accent)
                verticalAlignment: Text.AlignVCenter
              }

              delegate: ItemDelegate {
                width: priorityCombo.width
                highlighted: priorityCombo.highlightedIndex === index
                background: Rectangle {
                  radius: Style.space(2)
                  color: priorityCombo.highlightedIndex === index ? Color.accent : Color.background
                }
                contentItem: Text {
                  leftPadding: Style.space(6)
                  text: modelData.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: priorityCombo.highlightedIndex === index ? Color.background : Storage.priorityColor(modelData.value, Color.accent)
                  verticalAlignment: Text.AlignVCenter
                }
              }

              popup: Popup {
                y: priorityCombo.height + Style.space(2)
                width: priorityCombo.width
                padding: Style.space(2)
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
                      font.family: Style.font.family
                      font.pixelSize: 9
                      font.bold: true
                      color: Storage.priorityColor(modelData.priority, Color.accent)
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.title || modelData.text || ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    color: Color.foreground
                    wrapMode: Text.WordWrap
                    font.strikeout: modelData.completed
                  }

                  // Resolve Case
                  Text {
                    text: modelData.completed ? "✓" : "○"
                    font.pixelSize: Style.font.heading
                    color: modelData.completed ? "#30d158" : Color.muted
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleMission(modelData.id)
                    }
                  }

                  // Purge Dossier
                  Text {
                    text: "✕"
                    font.pixelSize: Style.font.body
                    color: Color.muted
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
        // Tab 2: Forensics (Multi-Tab Detective Scratchpad)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 2
          anchors.fill: parent
          spacing: Style.space(8)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Repeater {
              model: root.notesData && root.notesData.tabs ? root.notesData.tabs : []
              delegate: Rectangle {
                height: Style.space(26)
                implicitWidth: tabRow.implicitWidth + Style.space(12)
                radius: Style.space(4)
                color: root.activeNoteTabIndex === index ? Color.accent : Color.background
                border.color: root.activeNoteTabIndex === index ? Color.accent : Color.muted
                border.width: 1

                RowLayout {
                  id: tabRow
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    text: modelData.title || "Dossier " + (index + 1)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: root.activeNoteTabIndex === index
                    color: root.activeNoteTabIndex === index ? Color.background : Color.foreground
                  }

                  Text {
                    visible: root.notesData.tabs.length > 1
                    text: "×"
                    font.pixelSize: Style.font.caption
                    color: root.activeNoteTabIndex === index ? Color.background : Color.muted
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.deleteNoteTab(index)
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.switchNoteTab(index)
                }
              }
            }

            Rectangle {
              height: Style.space(26)
              width: Style.space(26)
              radius: Style.space(4)
              color: Color.background
              border.color: Color.muted
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "+"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Color.muted
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addNoteTab()
              }
            }
          }

          TextArea {
            id: noteArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            placeholderText: "Log forensic data, cryptographic hashes, crime scene observations..."
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

            Text {
              text: "FORENSIC LOG SIZE: " + (noteArea ? noteArea.text.length : 0) + " BYTES"
              font.family: Style.font.family
              font.pixelSize: 9
              font.bold: true
              color: Color.muted
            }

            Item { Layout.fillWidth: true }

            Rectangle {
              height: Style.space(34)
              radius: Style.space(4)
              color: Color.accent
              implicitWidth: Style.space(130)

              Text {
                anchors.centerIn: parent
                text: "💾  Save Dossier"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
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
                  font.family: Style.font.family
                  font.bold: true
                  font.pixelSize: Style.font.bodySmall
                  color: Color.accent
                }
              }

              Text {
                text: "Next scheduled briefing for " + root.callSign + " in: " + (root.hostWidget ? Storage.formatTime(root.hostWidget.checkInSecondsLeft) : "--:--")
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Color.muted
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
              spacing: 6
              Text { text: "🎙"; font.pixelSize: Style.font.body }
              Text {
                text: "Request Tactical Briefing from Alfred"
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
                font.family: Style.font.family
                font.pixelSize: 9
                font.bold: true
                color: Color.muted
              }

              Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "“Remember, " + root.callSign + ", the mind is your sharpest batarang. Periodic tactical pauses prevent forensic fatigue and sharpen your deduction.”"
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Color.foreground
              }

              Item { Layout.fillHeight: true }
            }
          }
        }

        // ═════════════════════════════════════════════════════════════════════
        // Tab 4: Batcave Operations (Quick Ops)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
          visible: root.currentTab === 4
          anchors.fill: parent
          spacing: Style.space(10)

          Text {
            text: "Batcave Terminal Operations"
            font.family: Style.font.family
            font.bold: true
            font.pixelSize: Style.font.body
            color: Color.accent
          }

          GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(8)

            Repeater {
              model: [
                { label: "🔒  Batcave Lockdown",  cmd: ["omarchy", "system", "lock"] },
                { label: "🌙  Gotham Night Light", cmd: ["omarchy", "toggle", "nightlight"] },
                { label: "📸  HUD Recon Capture",   cmd: ["omarchy", "capture", "screenshot"] },
                { label: "🔇  Comms Silence",       cmd: ["bash", "-c", "pactl set-sink-mute @DEFAULT_SINK@ toggle"] },
                { label: "🔄  Reboot Batcomputer",  cmd: ["omarchy", "restart", "shell"] },
                { label: "⚡  Bat-Signal Beacon",   cmd: [] }
              ]
              delegate: Rectangle {
                Layout.fillWidth: true
                height: Style.space(38)
                radius: Style.space(4)
                color: Color.background
                border.color: Color.muted
                border.width: 1

                Text {
                  anchors.centerIn: parent
                  text: modelData.label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.label.indexOf("Bat-Signal") >= 0) {
                      if (root.hostWidget) root.hostWidget.batSignalActive = !root.hostWidget.batSignalActive
                    } else {
                      Quickshell.execDetached(modelData.cmd)
                    }
                    root.close()
                  }
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
