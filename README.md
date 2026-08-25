# 🦇 BatPuter — Wayne Tech Tactical Operations HUD

[![Omarchy Plugin](https://img.shields.io/badge/Omarchy-Plugin-00d2ff.svg)](https://omarchyplugins.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> *"The Batcomputer is online, Master Wayne."*  
> **BatPuter** is a Gotham-inspired tactical operations HUD and productivity assistant built for the [Omarchy](https://omarchy.org) desktop shell.

---

## ⚡ Features

- 🦇 **Adaptive Cowl Icon**: High-contrast, theme-aware Dark Knight cowl silhouette that automatically shifts to crisp white on dark bars and deep black on light bars.
- ⏱ **Tactical Patrol Timer**: Pomodoro focus engine with presets (`25m Patrol`, `50m Investigate`, `5m Rest`, `15m Recharge`), radar-pulse animation, session telemetry, and countdown on the status bar.
- 📂 **Active Case Files**: Detective case tracker with classified threat ratings (`OMEGA`, `ALPHA`, `BETA`, `GAMMA`), case resolution checklists, and instant objective logging.
- 📜 **Forensic Dossiers**: Multi-tab forensic scratchpad (`Forensic Analysis`, `Case Dossier`, `Wayne Directives`, plus custom tabs) with auto-save and byte metrics.
- 🎙 **Alfred Pennyworth Comms**: Encrypted comms channel with on-demand tactical briefings and customizable detective callsign (`Master Wayne`, `The Detective`, `Bruce`, or custom).
- ⚡ **Batcave Operations**: One-click quick actions for Batcave Lockdown, Gotham Night Light, HUD Recon Capture, Comms Silence, Reboot Batcomputer, and Bat-Signal Beacon mode.
- 📊 **Real-time Batcave Telemetry**: Live CPU load, memory usage, and quantum encryption link status directly in the HUD header.

---

## 📦 Installation

### Method 1: Via Omarchy CLI (Recommended)
```bash
omarchy plugin add https://github.com/<your-username>/batputer.git --enable
```

### Method 2: Manual Install
```bash
git clone https://github.com/<your-username>/batputer.git ~/.config/omarchy/plugins/batputer
omarchy restart shell
```

---

## 🎮 Controls & Shortcuts

| Action | Control |
| :--- | :--- |
| **Toggle BatPuter HUD** | Left-Click Bar Icon / `SUPER + B` |
| **Start / Pause Patrol Timer** | Right-Click Bar Icon |
| **Reset Patrol Timer** | Middle-Click Bar Icon |
| **Change Detective Callsign** | Click `👤 [Callsign]` badge in HUD Header |

---

## 🗑 Uninstallation

```bash
omarchy plugin remove batputer
omarchy restart shell
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
