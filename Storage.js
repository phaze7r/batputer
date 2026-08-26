.pragma library

function formatTime(seconds) {
  var mins = Math.floor(seconds / 60);
  var secs = seconds % 60;
  return (mins < 10 ? "0" : "") + mins + ":" + (secs < 10 ? "0" : "") + secs;
}

function formatDuration(totalSeconds) {
  var hrs = Math.floor(totalSeconds / 3600);
  var mins = Math.floor((totalSeconds % 3600) / 60);
  if (hrs > 0) {
    return hrs + "h " + mins + "m";
  }
  return mins + "m";
}

function formatSpeed(bytesPerSec) {
  if (bytesPerSec >= 1048576) {
    return (bytesPerSec / 1048576).toFixed(1) + " MB/s";
  }
  if (bytesPerSec >= 1024) {
    return (bytesPerSec / 1024).toFixed(0) + " KB/s";
  }
  return Math.round(bytesPerSec) + " B/s";
}

function parseJsonSafe(text, fallback) {
  try {
    if (!text || text.trim() === "") return fallback;
    return JSON.parse(text);
  } catch (e) {
    console.warn("BatPuter JSON parse error:", e);
    return fallback;
  }
}

// Detective Threat Level Colors
function priorityColor(priority, fallbackAccent) {
  switch (priority) {
    case "critical":
    case "omega":
      return "#ff3b30"; // Omega Level Threat (Red)
    case "high":
    case "alpha":
      return "#ff9500"; // Alpha Level Threat (Amber/Orange)
    case "medium":
    case "beta":
      return "#ffd60a"; // Beta Level Threat (Yellow)
    case "low":
    case "gamma":
      return "#30d158"; // Gamma Level Threat (Green)
    default:
      return fallbackAccent || "#00d2ff";
  }
}

// Detective Threat Labels
function priorityLabel(priority) {
  switch (priority) {
    case "critical":
    case "omega":
      return "OMEGA";
    case "high":
    case "alpha":
      return "ALPHA";
    case "medium":
    case "beta":
      return "BETA";
    case "low":
    case "gamma":
      return "GAMMA";
    default:
      return "CASE";
  }
}

function getDetectiveRank(sessions) {
  if (sessions >= 25) return "The Dark Knight";
  if (sessions >= 10) return "Caped Crusader";
  if (sessions >= 3) return "Gotham Detective";
  return "Cadet Investigator";
}

function getNextCheckInPrompt(callSign) {
  var name = callSign || "Master Wayne";
  var prompts = [
    "Status report, " + name + ". Gotham surveillance telemetry is active. What is your primary objective?",
    "Alfred here. The Batcave computer has compiled forensic data. Do you require tactical analysis, " + name + "?",
    "Batcave Diagnostics: " + name + ", remember to monitor your physical vitals and stay hydrated during deep surveillance.",
    "Detective Protocol: Eliminating cognitive clutter is key to solving the case. Review your Active Dossiers, " + name + ".",
    "Wayne Tech Alert: Perimeter sensors are quiet. Proceed with your current tactical investigation, " + name + ".",
    "Alfred Check-in: The city relies on your sharp focus, " + name + ". Have you completed your current milestone?"
  ];
  return prompts[Math.floor(Math.random() * prompts.length)];
}

function generateDebriefReport(callSign, sessions, focusSeconds, streak, agendaList, notesData) {
  var today = new Date().toISOString().split("T")[0];
  var rank = getDetectiveRank(sessions);
  var totalTime = formatDuration(focusSeconds);
  
  var lines = [];
  lines.push("# 🦇 Wayne Tech Tactical Debrief // " + today);
  lines.push("**Detective:** " + (callSign || "Master Wayne"));
  lines.push("**Rank:** " + rank + " | **Active Streak:** " + (streak || 1) + " Days");
  lines.push("**Patrol Surveillance:** " + totalTime + " (" + sessions + " missions completed)\n");
  
  lines.push("### 📂 Resolved Objectives");
  var completedCount = 0;
  if (agendaList && agendaList.length > 0) {
    for (var i = 0; i < agendaList.length; i++) {
      var item = agendaList[i];
      if (item.completed) {
        lines.push("- [x] `[" + priorityLabel(item.priority) + "]` " + (item.title || item.text));
        completedCount++;
      }
    }
  }
  if (completedCount === 0) lines.push("- *No resolved cases logged today.*");
  
  lines.push("\n### 📌 Active Case Files");
  var activeCount = 0;
  if (agendaList && agendaList.length > 0) {
    for (var j = 0; j < agendaList.length; j++) {
      var it = agendaList[j];
      if (!it.completed) {
        lines.push("- [ ] `[" + priorityLabel(it.priority) + "]` " + (it.title || it.text));
        activeCount++;
      }
    }
  }
  if (activeCount === 0) lines.push("- *All active cases resolved.*");
  
  lines.push("\n### 📝 Forensic Summary");
  if (notesData && notesData.tabs && notesData.tabs.length > 0) {
    var primaryNote = notesData.tabs[0].content || "";
    lines.push(primaryNote.trim().substring(0, 500) + (primaryNote.length > 500 ? "\n..." : ""));
  } else {
    lines.push("*No notes recorded.*");
  }
  
  lines.push("\n---\n*Transmitted securely via BatPuter v3.0 // Omarchy*");
  return lines.join("\n");
}
