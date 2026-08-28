import QtQuick 2.15
import QtQuick.Window 2.15
import Quickshell 1.0

Window {
  visible: true
  Process {
    id: proc
    command: ["python3", "-c", "import sys; print(f'READ: {sys.stdin.read()}')"]
    running: true
    stdinEnabled: true
    onStarted: {
      write("test")
      if (typeof closeWriteChannel === "function") { closeWriteChannel(); }
      else if (typeof closeInput === "function") { closeInput(); }
    }
    stdout: function(data) { console.log(data); Qt.quit() }
  }
}
