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

// Bounded and Safe JSON Parser (Max Byte Limit)
function parseJsonSafe(text, fallback, maxBytes) {
  try {
    if (!text || typeof text !== "string" || text.trim() === "") return fallback;
    var limit = maxBytes || 65536; // Default 64KB bound
    if (text.length > limit) {
      console.warn("BatPuter: Payload exceeded maximum byte limit (" + text.length + " > " + limit + ")");
      return fallback;
    }
    return JSON.parse(text);
  } catch (e) {
    console.warn("BatPuter JSON parse error:", e);
    return fallback;
  }
}

// Strict Bounded Config Sanitizer
function sanitizeConfig(raw) {
  if (!raw || typeof raw !== "object") raw = {};
  var callSign = typeof raw.callSign === "string" ? raw.callSign.trim().substring(0, 32) : "Master Wayne";
  if (!callSign) callSign = "Master Wayne";
  return {
    callSign: callSign,
    sessionsCompleted: Math.max(0, Math.min(100000, parseInt(raw.sessionsCompleted) || 0)),
    totalFocusSeconds: Math.max(0, Math.min(100000000, parseInt(raw.totalFocusSeconds) || 0)),
    streakDays: Math.max(1, Math.min(10000, parseInt(raw.streakDays) || 1)),
    lastActiveDate: (typeof raw.lastActiveDate === "string" && /^\d{4}-\d{2}-\d{2}$/.test(raw.lastActiveDate)) ? raw.lastActiveDate : ""
  };
}

// Strict Bounded Agenda Sanitizer (Max 50 items, max 140 chars per title)
function sanitizeAgenda(raw) {
  if (!Array.isArray(raw)) return [];
  var list = raw.slice(0, 50);
  var validPriorities = { "omega": 1, "alpha": 1, "beta": 1, "gamma": 1 };
  var result = [];
  for (var i = 0; i < list.length; i++) {
    var it = list[i];
    if (!it || typeof it !== "object") continue;
    var title = typeof it.title === "string" ? it.title.trim().substring(0, 140) : (typeof it.text === "string" ? it.text.trim().substring(0, 140) : "");
    if (!title) continue;
    var p = typeof it.priority === "string" ? it.priority.toLowerCase().trim() : "alpha";
    if (!validPriorities[p]) p = "alpha";
    result.push({
      id: Number(it.id) || (Date.now() + i),
      title: title,
      section: typeof it.section === "string" ? it.section.substring(0, 20) : "today",
      priority: p,
      completed: Boolean(it.completed),
      created: (typeof it.created === "string" && /^\d{4}-\d{2}-\d{2}$/.test(it.created)) ? it.created : new Date().toISOString().split("T")[0]
    });
  }
  return result;
}

// Strict Bounded Notes Sanitizer (Max 5 tabs, max 16KB per tab)
function sanitizeNotes(raw) {
  var fallback = {
    activeTab: 0,
    tabs: [
      { title: "Daily Log", content: "# DAILY MISSION LOG\n- Status: All systems operational\n- Focus: Complete primary objectives." },
      { title: "Scratchpad", content: "Quick ideas, tactical observations, thoughts..." },
      { title: "Snippets", content: "# USEFUL COMMANDS\nomarchy theme current\nhyprctl reload" }
    ]
  };
  if (!raw || typeof raw !== "object") return fallback;
  var tabs = Array.isArray(raw.tabs) ? raw.tabs.slice(0, 5) : fallback.tabs;
  var cleanTabs = [];
  for (var i = 0; i < tabs.length; i++) {
    var t = tabs[i];
    if (!t || typeof t !== "object") continue;
    var title = typeof t.title === "string" ? t.title.trim().substring(0, 32) : ("Tab " + (i + 1));
    var content = typeof t.content === "string" ? t.content.substring(0, 16384) : "";
    cleanTabs.push({ title: title || ("Tab " + (i + 1)), content: content });
  }
  if (cleanTabs.length === 0) cleanTabs = fallback.tabs;
  var activeTab = Math.max(0, Math.min(cleanTabs.length - 1, parseInt(raw.activeTab) || 0));
  return { activeTab: activeTab, tabs: cleanTabs };
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
  var name = (callSign || "Master Wayne").substring(0, 32);
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
  var safeCallSign = (callSign || "Master Wayne").substring(0, 32);
  var rank = getDetectiveRank(sessions);
  var totalTime = formatDuration(focusSeconds);
  
  var lines = [];
  lines.push("# 🦇 Wayne Tech Tactical Debrief // " + today);
  lines.push("**Detective:** " + safeCallSign);
  lines.push("**Rank:** " + rank + " | **Active Streak:** " + (streak || 1) + " Days");
  lines.push("**Patrol Surveillance:** " + totalTime + " (" + sessions + " missions completed)\n");
  
  lines.push("### 📂 Resolved Objectives");
  var completedCount = 0;
  if (agendaList && Array.isArray(agendaList)) {
    for (var i = 0; i < agendaList.length; i++) {
      var item = agendaList[i];
      if (item && item.completed) {
        var itemTitle = (typeof item.title === "string" ? item.title : (item.text || "")).substring(0, 140);
        lines.push("- [x] `[" + priorityLabel(item.priority) + "]` " + itemTitle);
        completedCount++;
      }
    }
  }
  if (completedCount === 0) lines.push("- *No resolved cases logged today.*");
  
  lines.push("\n### 📌 Active Case Files");
  var activeCount = 0;
  if (agendaList && Array.isArray(agendaList)) {
    for (var j = 0; j < agendaList.length; j++) {
      var it = agendaList[j];
      if (it && !it.completed) {
        var itTitle = (typeof it.title === "string" ? it.title : (it.text || "")).substring(0, 140);
        lines.push("- [ ] `[" + priorityLabel(it.priority) + "]` " + itTitle);
        activeCount++;
      }
    }
  }
  if (activeCount === 0) lines.push("- *All active cases resolved.*");
  
  lines.push("\n### 📝 Forensic Summary");
  if (notesData && notesData.tabs && Array.isArray(notesData.tabs) && notesData.tabs.length > 0) {
    var primaryNote = (notesData.tabs[0] && typeof notesData.tabs[0].content === "string") ? notesData.tabs[0].content : "";
    lines.push(primaryNote.trim().substring(0, 500) + (primaryNote.length > 500 ? "\n..." : ""));
  } else {
    lines.push("*No notes recorded.*");
  }
  
  lines.push("\n---\n*Transmitted securely via BatPuter v3.0 // Omarchy*");
  return lines.join("\n");
}
