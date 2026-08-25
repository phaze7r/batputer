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
