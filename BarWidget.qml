import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.subirats345.echo-shelf"
  ipcTarget: moduleName
  manageIpc: false

  property string mode: "disconnected"
  property var details: ({})
  property string activeTab: "overview"
  property bool ejectArmed: false
  property bool syncArmed: false
  property bool importArmed: false
  property bool firmwarePrepareArmed: false
  property bool firmwareInstallArmed: false
  property string actionKind: ""
  property string actionLabel: ""
  property string actionOutput: ""
  property string actionStatus: ""
  property int actionProgress: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: mode === "disconnected" ? dim : foreground
  readonly property string helperPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/" + moduleName + "/echo-mini-status"
  readonly property bool actionRunning: ejectProbe.running || syncProbe.running
    || importProbe.running || firmwarePrepareProbe.running || firmwareInstallProbe.running
    || firmwareConfirmProbe.running
  readonly property bool firmwareCurrent: details.firmware_installed !== undefined
    && details.firmware_installed !== "unknown"
    && details.firmware_installed === details.firmware_latest
  readonly property bool firmwareAvailable: String(details.firmware || "").indexOf("Installed unknown") === 0
    || String(details.firmware || "").indexOf(" available") > 0

  function connectionMeta() {
    if (detailsProbe.running) return mode === "dac" ? "USB DAC · UPDATING" : "USB DATA · UPDATING"
    if (mode === "dac") return "USB DAC · 48 KHZ"
    if (details.mounted === "yes") return "USB DATA · READY"
    if (details.internal_mounted === "yes") return "USB DATA · INTERNAL ONLY"
    return "USB DATA · SAFE TO DISCONNECT"
  }

  function storageUsage(value) {
    var usage = String(value || "")
    return usage.indexOf(" / ") > 0 ? usage.replace(" / ", "/") : "—"
  }

  function syncSummary() {
    var value = String(details.sync || "")
    if (value.indexOf("0 new · 0 updated") === 0) return ""
    if (value === "SD not mounted") return "Connect the SD card"
    return value || "Checking Inbox…"
  }

  function importSummary() {
    var value = String(details["import"] || "")
    if (value.indexOf("0 new · 0 conflicts") === 0) return ""
    if (value === "SD not mounted") return "Connect the SD card"
    return value || "Checking Library…"
  }

  function firmwareSummary() {
    if (details.firmware_installed === "unknown") return "Check the version on the Echo"
    if (firmwareCurrent) return "Up to date"
    if (details.firmware_pending === "yes") return "Restarted? Confirm the version on the Echo"
    if (details.firmware_prepared === "yes") return details.sd_present === "yes"
      ? "Safely eject, remove SD, then reconnect" : "Ready to install"
    if (firmwareAvailable) return (details.firmware_latest || "Update") + " available"
    return "Checking for updates…"
  }

  function cancelArms() {
    ejectArmed = false; ejectTimer.stop()
    syncArmed = false; syncTimer.stop()
    importArmed = false; importTimer.stop()
    firmwarePrepareArmed = false; firmwarePrepareTimer.stop()
    firmwareInstallArmed = false; firmwareInstallTimer.stop()
  }

  function startAction(kind, label, progress) {
    cancelArms()
    actionKind = kind
    actionLabel = label
    actionOutput = ""
    actionStatus = ""
    actionProgress = progress
  }

  function handleActionLine(line) {
    var value = String(line || "")
    if (value.indexOf("PROGRESS\t") === 0) {
      var parts = value.split("\t")
      actionProgress = Math.max(0, Math.min(100, parseInt(parts[1], 10) || 0))
      actionLabel = parts.slice(2).join(" ")
      return
    }
    value = value.trim()
    if (value !== "") actionOutput = value
  }

  function finishAction(exitCode, success, failure) {
    if (exitCode === 0) actionProgress = 100
    actionStatus = actionOutput || (exitCode === 0 ? success : failure)
    refreshDetails()
  }

  function refreshStatus() {
    if (!statusProbe.running) statusProbe.running = true
  }

  function refreshDetails() {
    if (mode !== "disconnected" && !actionRunning && !detailsProbe.running) detailsProbe.running = true
  }

  function requestEject() {
    if (mode !== "data" || details.internal_mounted !== "yes" || actionRunning) return
    if (!ejectArmed) {
      cancelArms(); ejectArmed = true; ejectTimer.restart(); return
    }
    startAction("overview", "Safely unmounting Echo", 25)
    ejectProbe.running = true
  }

  function requestSync() {
    if (mode !== "data" || details.mounted !== "yes" || actionRunning) return
    if (!syncArmed) {
      cancelArms(); syncArmed = true; syncTimer.restart(); return
    }
    startAction("library", "Checking Inbox", 5)
    syncProbe.running = true
  }

  function requestOpenInbox() {
    if (!openInboxProbe.running) openInboxProbe.running = true
  }

  function requestImport() {
    if (mode !== "data" || details.mounted !== "yes" || actionRunning) return
    if (!importArmed) {
      cancelArms(); importArmed = true; importTimer.restart(); return
    }
    startAction("library", "Checking Echo library", 5)
    importProbe.running = true
  }

  function requestFirmwarePrepare() {
    if (mode !== "data" || details.mounted !== "yes" || actionRunning) return
    if (!firmwarePrepareArmed) {
      cancelArms(); firmwarePrepareArmed = true; firmwarePrepareTimer.restart(); return
    }
    startAction("firmware", "Checking Echo Mini", 5)
    firmwarePrepareProbe.running = true
  }

  function requestFirmwareInstall() {
    if (mode !== "data" || details.internal_mounted !== "yes"
        || details.sd_present !== "no" || actionRunning) return
    if (!firmwareInstallArmed) {
      cancelArms(); firmwareInstallArmed = true; firmwareInstallTimer.restart(); return
    }
    startAction("firmware", "Validating prepared firmware", 5)
    firmwareInstallProbe.running = true
  }

  function requestFirmwareConfirm() {
    if (actionRunning) return
    startAction("firmware", "Recording installed version", 30)
    firmwareConfirmProbe.running = true
  }

  function switchTab(step) {
    var tabs = ["overview", "library", "firmware"]
    var index = tabs.indexOf(activeTab)
    activeTab = tabs[(index + step + tabs.length) % tabs.length]
    panelFlick.contentY = 0
  }

  IpcHandler {
    target: root.moduleName
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function refresh() { root.refreshStatus() }
  }

  onOpenedChanged: {
    if (opened) {
      activeTab = "overview"
      panelFlick.contentY = 0
      refreshDetails()
    } else {
      cancelArms()
    }
  }

  visible: mode !== "disconnected"
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: statusProbe
    command: [root.helperPath]
    onExited: function(exitCode) {
      var nextMode = exitCode === 10 ? "data" : exitCode === 20 ? "dac" : "disconnected"
      var modeChanged = root.mode !== nextMode
      if (modeChanged) {
        root.cancelArms()
        root.actionKind = ""
        root.actionLabel = ""
        root.actionOutput = ""
        root.actionStatus = ""
        root.actionProgress = 0
      }
      if (nextMode === "disconnected") root.close()
      root.mode = nextMode
      if (modeChanged && nextMode !== "disconnected") {
        if (!cachedDetailsProbe.running) cachedDetailsProbe.running = true
        root.refreshDetails()
      }
    }
  }

  Process {
    id: firmwareConfirmProbe
    command: [root.helperPath, "--confirm-firmware"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Firmware confirmed", "Confirmation failed") }
  }

  Process {
    id: firmwarePrepareProbe
    command: [root.helperPath, "--prepare-firmware"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Firmware package ready", "Preparation failed") }
  }

  Process {
    id: firmwareInstallProbe
    command: [root.helperPath, "--install-prepared-firmware"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Restart Echo Mini", "Installation failed") }
  }

  Process {
    id: updateProbe
    command: [root.helperPath, "--check-updates"]
    onExited: root.refreshDetails()
  }

  Process {
    id: importProbe
    command: [root.helperPath, "--import-from-echo"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Library updated", "Import failed") }
  }

  Process {
    id: syncProbe
    command: [root.helperPath, "--sync-to-echo"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Echo library updated", "Sync failed") }
  }

  Process {
    id: openInboxProbe
    command: [root.helperPath, "--open-inbox"]
    onExited: root.refreshDetails()
  }

  Process {
    id: ejectProbe
    command: [root.helperPath, "--eject"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Safe to disconnect", "Eject failed") }
  }

  Process {
    id: cachedDetailsProbe
    command: [root.helperPath, "--cached-details"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cached = Model.parseKeyValue(text)
        if (cached.mode === root.mode) root.details = cached
      }
    }
  }

  Process {
    id: detailsProbe
    command: [root.helperPath, "--details"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.details = Model.parseKeyValue(text)
    }
  }

  Timer {
    interval: 21600000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!updateProbe.running) updateProbe.running = true
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer { id: importTimer; interval: 5000; onTriggered: root.importArmed = false }
  Timer { id: syncTimer; interval: 5000; onTriggered: root.syncArmed = false }
  Timer { id: ejectTimer; interval: 5000; onTriggered: root.ejectArmed = false }
  Timer { id: firmwarePrepareTimer; interval: 5000; onTriggered: root.firmwarePrepareArmed = false }
  Timer { id: firmwareInstallTimer; interval: 5000; onTriggered: root.firmwareInstallArmed = false }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.refreshDetails()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        EchoGlyph {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.barIconColor
        }
      }
    }
    tooltipText: root.mode === "dac" ? "Echo Mini · USB DAC · 48 kHz" : "Echo Mini · USB Data"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.visible
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(344))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.switchTab(dx) }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "1" || key === "o") root.activeTab = "overview"
        else if (key === "2" || key === "l") root.activeTab = "library"
        else if (key === "3" || key === "f") root.activeTab = "firmware"
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Echo Mini"
            meta: root.connectionMeta()
            detail: ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.mode === "disconnected" ? 0.5 : 1.0
            iconComponent: Component {
              EchoGlyph { iconSize: Style.font.display; color: root.foreground }
            }
          }

          Item {
            width: parent.width
            implicitHeight: tabs.implicitHeight

            ButtonGroup {
              id: tabs
              anchors.horizontalCenter: parent.horizontalCenter
              options: [
                { value: "overview", label: "Overview" },
                { value: "library", label: "Library" },
                { value: "firmware", label: "Firmware" }
              ]
              value: root.activeTab
              foreground: root.foreground
              background: root.bar ? root.bar.background : Color.background
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onChanged: function(value) { root.activeTab = value; panelFlick.contentY = 0 }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Column {
            visible: root.activeTab === "overview"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: root.mode === "dac" ? "CONNECTION" : "STORAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ValueRow {
              visible: root.mode === "dac"
              width: parent.width
              label: "Connection"
              value: "USB DAC"
              caption: "Audio at 48 kHz"
            }

            Column {
              visible: root.mode === "data"
              width: parent.width
              spacing: Style.space(10)

              StorageMeter {
                width: parent.width
                label: "Internal"
                meta: root.storageUsage(root.details.internal)
                percent: parseInt(root.details.internal_percent || "0", 10)
                available: root.details.internal_mounted === "yes"
                loading: detailsProbe.running && root.details.internal === undefined
              }

              StorageMeter {
                width: parent.width
                label: "SD card"
                meta: root.storageUsage(root.details.sd)
                percent: parseInt(root.details.sd_percent || "0", 10)
                available: root.details.mounted === "yes"
                loading: detailsProbe.running && root.details.sd === undefined
              }
            }

            PanelSeparator { visible: root.mode === "data"; width: parent.width; foreground: root.foreground }

            ActionRow {
              width: parent.width
              visible: root.mode === "data"
              label: "Disconnect safely"
              caption: root.details.internal_mounted === "yes"
                ? "Before unplugging" : "Safe to unplug"
              buttonText: root.ejectArmed ? "Press again" : "Eject"
              enabled: root.details.internal_mounted === "yes" && !root.actionRunning
              active: root.ejectArmed
              onTriggered: root.requestEject()
            }

            ActionFeedback { width: parent.width; kind: "overview" }
          }

          Column {
            visible: root.activeTab === "library"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "LIBRARY"; foreground: root.foreground; fontFamily: root.fontFamily }

            Row {
              width: parent.width
              spacing: Style.space(8)
              StatBlock { width: (parent.width - parent.spacing) / 2; value: root.details.tracks || "—"; label: "Tracks" }
              StatBlock { width: (parent.width - parent.spacing) / 2; value: root.details.albums || "—"; label: "Albums" }
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }
            PanelSectionHeader { text: "TRANSFER"; foreground: root.foreground; fontFamily: root.fontFamily }

            ActionRow {
              width: parent.width
              label: "Inbox"
              caption: "Add music here"
              buttonText: "Open"
              enabled: !openInboxProbe.running
              onTriggered: root.requestOpenInbox()
            }

            ActionRow {
              width: parent.width
              label: "Send to Echo"
              caption: root.syncSummary()
              statusText: String(root.details.sync || "").indexOf("0 new · 0 updated") === 0 ? "SYNCED" : ""
              buttonText: root.syncArmed ? "Press again" : "Send"
              enabled: root.mode === "data" && root.details.mounted === "yes"
                && !root.actionRunning
                && String(root.details.sync || "").indexOf("0 new · 0 updated") !== 0
              active: root.syncArmed
              onTriggered: root.requestSync()
            }

            ActionRow {
              width: parent.width
              label: "Import from Echo"
              caption: root.importSummary()
              statusText: String(root.details["import"] || "").indexOf("0 new") === 0 ? "UP TO DATE" : ""
              buttonText: root.importArmed ? "Press again" : "Import"
              enabled: root.mode === "data" && root.details.mounted === "yes"
                && !root.actionRunning
                && String(root.details["import"] || "").indexOf("0 new") !== 0
              active: root.importArmed
              onTriggered: root.requestImport()
            }

            ActionFeedback { width: parent.width; kind: "library" }
          }

          Column {
            visible: root.activeTab === "firmware"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "FIRMWARE"; foreground: root.foreground; fontFamily: root.fontFamily }

            ValueRow {
              width: parent.width
              label: "Installed"
              value: root.details.firmware_installed === "unknown" ? "Unknown" : root.details.firmware_installed || "—"
              caption: root.firmwareSummary()
            }

            PanelSeparator {
              visible: !root.firmwareCurrent
              width: parent.width
              foreground: root.foreground
            }
            PanelSectionHeader {
              visible: !root.firmwareCurrent
              text: "NEXT STEP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Button {
              width: parent.width
              visible: root.details.firmware_pending === "yes"
              enabled: !root.actionRunning
              text: "Confirm " + (root.details.firmware_pending_version || "firmware")
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.requestFirmwareConfirm()
            }

            Button {
              width: parent.width
              visible: root.mode === "data" && root.firmwareAvailable
                && root.details.firmware_pending !== "yes" && root.details.firmware_prepared !== "yes"
              enabled: root.details.mounted === "yes" && !root.actionRunning
                && String(root.details["import"] || "").indexOf("0 new · 0 conflicts") === 0
              text: root.firmwarePrepareArmed ? "Press again to prepare" : "Prepare " + root.details.firmware_latest
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.firmwarePrepareArmed
              onClicked: root.requestFirmwarePrepare()
            }

            Button {
              width: parent.width
              visible: root.details.firmware_prepared === "yes"
              enabled: root.mode === "data" && root.details.internal_mounted === "yes"
                && root.details.sd_present === "no" && !root.actionRunning
              text: root.details.sd_present === "yes" ? "Safely eject, remove SD, reconnect"
                : root.details.internal_mounted !== "yes" ? "Reconnect in USB Data"
                : root.firmwareInstallArmed ? "Press again to install"
                : "Install " + root.details.firmware_prepared_version
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.firmwareInstallArmed
              onClicked: root.requestFirmwareInstall()
            }

            ActionFeedback { width: parent.width; kind: "firmware" }
          }
        }
      }
    }
  }

  component EchoGlyph: Item {
    property real iconSize: Style.font.icon
    property color color: root.foreground
    implicitWidth: iconSize
    implicitHeight: iconSize
    Image {
      anchors.fill: parent
      source: "media-tape.svg"
      sourceSize.width: 48
      sourceSize.height: 48
      fillMode: Image.PreserveAspectFit
      smooth: true
    }
  }

  component StatBlock: Item {
    id: statBlock
    property string value: "—"
    property string label: ""
    implicitHeight: statColumn.implicitHeight
    height: implicitHeight
    ColumnLayout {
      id: statColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(2)
      Text {
        Layout.fillWidth: true
        text: statBlock.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
      Text {
        Layout.fillWidth: true
        text: statBlock.label.toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.0
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }

  component ValueRow: Item {
    id: valueRow
    property string label: ""
    property string value: ""
    property string caption: ""
    implicitHeight: valueCopy.implicitHeight
    height: implicitHeight
    ColumnLayout {
      id: valueCopy
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(2)
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(12)
        Text {
          Layout.fillWidth: true
          text: valueRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          text: valueRow.value
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }
      Text {
        visible: text !== ""
        Layout.fillWidth: true
        text: valueRow.caption
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  component StorageMeter: Item {
    id: storageMeter
    property string label: ""
    property string meta: "—"
    property int percent: 0
    property bool available: false
    property bool loading: false
    implicitHeight: storageLayout.implicitHeight
    height: implicitHeight
    RowLayout {
      id: storageLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(8)
      Text {
        Layout.preferredWidth: Style.space(64)
        text: storageMeter.label
        color: root.foreground
        opacity: storageMeter.available ? 1.0 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Rectangle {
        id: storageTrack
        Layout.fillWidth: true
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)
        Rectangle {
          width: storageTrack.width * Math.max(0, Math.min(100, storageMeter.percent)) / 100
          height: parent.height
          radius: parent.radius
          color: root.foreground
          opacity: storageMeter.available ? 1.0 : 0.25
          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
        }
      }
      Text {
        Layout.preferredWidth: Style.space(40)
        text: storageMeter.loading ? "…" : storageMeter.available ? storageMeter.percent + "%" : "—"
        color: root.foreground
        opacity: storageMeter.available ? 1.0 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
      }
      Text {
        Layout.preferredWidth: Style.space(62)
        text: storageMeter.loading ? "Reading…" : storageMeter.available ? storageMeter.meta : "Not mounted"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
      }
    }
  }

  component ProgressMeter: Item {
    id: progressMeter
    property string label: ""
    property string meta: ""
    property int value: 0
    implicitHeight: progressLayout.implicitHeight
    height: implicitHeight
    ColumnLayout {
      id: progressLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(5)
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: progressMeter.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          text: progressMeter.meta
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Rectangle {
        id: progressTrack
        Layout.fillWidth: true
        implicitHeight: Style.space(6)
        radius: height / 2
        color: Qt.darker(root.foreground, 3.2)
        Rectangle {
          width: progressTrack.width * Math.max(0, Math.min(100, progressMeter.value)) / 100
          height: parent.height
          radius: parent.radius
          color: root.foreground
          Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
        }
      }
    }
  }

  component ActionRow: Item {
    id: actionRow
    property string label: ""
    property string caption: ""
    property string buttonText: ""
    property string statusText: ""
    property bool active: false
    signal triggered()
    implicitHeight: actionLayout.implicitHeight
    height: implicitHeight
    RowLayout {
      id: actionLayout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          Layout.fillWidth: true
          text: actionRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          visible: text !== ""
          Layout.fillWidth: true
          text: actionRow.caption
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
      Button {
        Layout.alignment: Qt.AlignVCenter
        visible: actionRow.statusText === ""
        text: actionRow.buttonText
        enabled: actionRow.enabled
        active: actionRow.active
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: actionRow.triggered()
      }
      Text {
        Layout.alignment: Qt.AlignVCenter
        visible: actionRow.statusText !== ""
        text: actionRow.statusText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0.8
      }
    }
  }

  component ActionFeedback: Item {
    id: feedback
    property string kind: ""
    visible: root.actionKind === kind && (root.actionProgress > 0 || root.actionStatus !== "")
    implicitHeight: visible ? feedbackColumn.implicitHeight : 0
    height: implicitHeight
    ColumnLayout {
      id: feedbackColumn
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(6)
      ProgressMeter {
        Layout.fillWidth: true
        label: root.actionLabel
        meta: root.actionProgress + "%"
        value: root.actionProgress
      }
      Text {
        visible: root.actionStatus !== ""
        Layout.fillWidth: true
        text: root.actionStatus
        color: root.actionProgress === 100 ? root.dim : root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
