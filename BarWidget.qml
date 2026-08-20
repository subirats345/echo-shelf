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
  property var statusCandidate: ({})
  property var detailsCandidate: ({})
  property string connectionFingerprint: "disconnected"
  property string connectionToken: "disconnected"
  property string mountToken: "disconnected"
  property bool detailsRefreshFailed: false
  property int mountRetryCount: 0
  property int refreshRetryCount: 0
  property bool updateCheckFailed: false
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
  property bool actionSucceeded: false

  onActiveTabChanged: cancelArms()

  onActionStatusChanged: {
    if (actionStatus !== "" && panel.open)
      panel.Accessible.announce(actionStatus, Accessible.Polite)
  }

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: mode === "error" ? urgent : mode === "disconnected" ? dim : foreground
  readonly property string helperPath: Quickshell.env("HOME")
    + "/.config/omarchy/plugins/" + moduleName + "/echo-mini-status"
  readonly property bool actionRunning: ejectProbe.running || syncProbe.running
    || importProbe.running || firmwarePrepareProbe.running || firmwareInstallProbe.running
    || firmwareConfirmProbe.running
  readonly property bool internalPresent: details.internal_present === "yes"
  readonly property bool internalMounted: details.internal_mounted === "yes"
  readonly property bool sdPresent: details.sd_present === "yes"
  readonly property bool sdMounted: details.sd_mounted === "yes"
  readonly property bool stateAligned: details.mount_token === mountToken
  readonly property bool deviceReady: !details.device_error && stateAligned && !detailsRefreshFailed
  readonly property bool firmwareCurrent: details.firmware_state === "current"
  readonly property bool firmwareAvailable: details.firmware_state === "available"
    || (details.firmware_state === "unknown" && details.firmware_latest
      && details.firmware_latest !== "unknown")
  readonly property bool firmwareActionAvailable: details.firmware_pending === "yes"
    || details.firmware_prepared === "yes" || (mode === "data" && firmwareAvailable)
  readonly property int syncNew: parseInt(details.sync_new || "0", 10)
  readonly property int syncUpdated: parseInt(details.sync_updated || "0", 10)
  readonly property int syncSkipped: parseInt(details.sync_skipped || "0", 10)
  readonly property int syncUnsupported: parseInt(details.sync_unsupported || "0", 10)
  readonly property int importNew: parseInt(details.import_new || "0", 10)
  readonly property int importConflicts: parseInt(details.import_conflicts || "0", 10)
  readonly property int importSkipped: parseInt(details.import_skipped || "0", 10)
  readonly property int importUnsupported: parseInt(details.import_unsupported || "0", 10)
  readonly property bool syncCurrent: details.sync_state === "ok" && syncNew === 0 && syncUpdated === 0
  readonly property bool importCurrent: details.import_state === "ok" && importNew === 0 && importConflicts === 0

  function connectionMeta() {
    if (mode === "error") return "PLUGIN ERROR"
    if (mode === "dac") return "USB DAC MODE · AUDIO ONLY"
    if (detailsProbe.running) return "USB DATA · UPDATING"
    if (detailsRefreshFailed) return refreshRetryCount < 3
      ? "USB DATA · RETRYING" : "USB DATA · REFRESH FAILED"
    if (details.device_error) return "USB DATA · CHECK DEVICES"
    if (internalMounted && sdMounted) return "USB DATA · READY"
    if (mountRetryCount > 0 && ((internalPresent && !internalMounted) || (sdPresent && !sdMounted)))
      return "USB DATA · CONNECTING"
    if (internalMounted && sdPresent && !sdMounted) return "USB DATA · SD NOT MOUNTED"
    if (internalMounted) return "USB DATA · INTERNAL ONLY"
    if (sdMounted) return "USB DATA · SD ONLY"
    return "USB DATA · SAFE TO DISCONNECT"
  }

  function storageUsage(value) {
    var usage = String(value || "")
    return usage.indexOf(" / ") > 0 ? usage.replace(" / ", "/") : "—"
  }

  function syncSummary() {
    if (details.sync_state === "sd_missing") return "Connect or mount the SD card"
    if (details.sync_state === "inbox_missing") return "Inbox unavailable"
    if (details.sync_state !== "ok") return "Checking Inbox…"
    var work = []
    if (syncNew > 0) work.push(syncNew + " new")
    if (syncUpdated > 0) work.push(syncUpdated + " updated")
    if (syncSkipped > 0) work.push(syncSkipped + " skipped")
    if (syncUnsupported > 0) work.push(syncUnsupported + " unsupported audio")
    return work.length > 0 ? work.join(" · ") : "Computer → Echo SD card"
  }

  function importSummary() {
    if (details.import_state === "sd_missing") return "Connect or mount the SD card"
    if (details.import_state !== "ok") return "Checking Library…"
    var work = []
    if (importNew > 0) work.push(importNew + " new")
    if (importConflicts > 0) work.push(importConflicts + " conflict" + (importConflicts === 1 ? " · local kept" : "s · local kept"))
    if (importSkipped > 0) work.push(importSkipped + " skipped")
    if (importUnsupported > 0) work.push(importUnsupported + " unsupported audio")
    return work.length > 0 ? work.join(" · ") : "Echo Shelf / Local Copy · up to date"
  }

  function firmwareSummary() {
    if (updateProbe.running) return "Checking for updates…"
    if (details.firmware_installed === "unknown") return "Check the version on the Echo"
    if (firmwareCurrent) {
      if (updateCheckFailed) return "Up to date · using cached update data"
      return details.firmware_feed === "stale" ? "Up to date · update check stale" : "Up to date"
    }
    if (details.firmware_pending === "yes") return "Restarted? Confirm the version on the Echo"
    if (details.firmware_prepared === "yes") return details.sd_present === "yes"
      ? "Safely eject, remove SD, then reconnect" : "Ready to install"
    if (firmwareAvailable) return (details.firmware_latest || "Update") + " available"
      + (updateCheckFailed ? " · cached" : "")
    return "Checking for updates…"
  }

  function cancelArms() {
    ejectArmed = false
    syncArmed = false
    importArmed = false
    firmwarePrepareArmed = false
    firmwareInstallArmed = false
  }

  function startAction(kind, label, progress) {
    cancelArms()
    actionKind = kind
    actionLabel = label
    actionOutput = ""
    actionStatus = ""
    actionProgress = progress
    actionSucceeded = false
    actionClearTimer.stop()
  }

  function clearAction() {
    actionKind = ""
    actionLabel = ""
    actionOutput = ""
    actionStatus = ""
    actionProgress = 0
    actionSucceeded = false
    actionClearTimer.stop()
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
    if (exitCode === 0 || exitCode === 2) actionProgress = 100
    actionSucceeded = exitCode === 0
    actionStatus = actionOutput || (exitCode === 0 ? success : failure)
    if (actionSucceeded) actionClearTimer.restart()
    refreshStatus()
    refreshDetails()
  }

  function refreshStatus() {
    if (!statusProbe.running) statusProbe.running = true
  }

  function refreshDetails() {
    if ((mode === "data" || mode === "dac") && !actionRunning && !detailsProbe.running)
      detailsProbe.running = true
  }

  function requestEject() {
    if (mode !== "data" || !deviceReady || (!internalMounted && !sdMounted) || actionRunning) return
    if (!ejectArmed) {
      cancelArms(); ejectArmed = true; return
    }
    mountRetryCount = 0
    startAction("overview", "Safely unmounting Echo", 1)
    ejectProbe.running = true
  }

  function requestSync() {
    if (mode !== "data" || !deviceReady || !sdMounted || actionRunning || syncCurrent) return
    if (!syncArmed) {
      cancelArms(); syncArmed = true; return
    }
    startAction("library", "Checking Inbox", 1)
    syncProbe.running = true
  }

  function requestOpenInbox() {
    if (!openInboxProbe.running) openInboxProbe.running = true
  }

  function requestImport() {
    if (mode !== "data" || !deviceReady || !sdMounted || actionRunning) return
    if (importCurrent || (importNew === 0 && importConflicts > 0)) {
      if (!openLibraryProbe.running) openLibraryProbe.running = true
      return
    }
    if (!importArmed) {
      cancelArms(); importArmed = true; return
    }
    startAction("library", "Checking music on Echo", 1)
    importProbe.running = true
  }

  function requestFirmwarePrepare() {
    if (mode !== "data" || !deviceReady || !internalMounted || !sdMounted || actionRunning) return
    if (!firmwarePrepareArmed) {
      cancelArms(); firmwarePrepareArmed = true; return
    }
    startAction("firmware", "Checking Echo Mini", 1)
    firmwarePrepareProbe.running = true
  }

  function requestFirmwareInstall() {
    if (mode !== "data" || !deviceReady || !internalMounted || sdPresent || actionRunning) return
    if (!firmwareInstallArmed) {
      cancelArms(); firmwareInstallArmed = true; return
    }
    startAction("firmware", "Validating prepared firmware", 1)
    firmwareInstallProbe.running = true
  }

  function requestFirmwareConfirm() {
    if (!deviceReady || actionRunning) return
    startAction("firmware", "Recording installed version", 1)
    firmwareConfirmProbe.running = true
  }

  function requestUpdateCheck() {
    if (!updateProbe.running) updateProbe.running = true
  }

  function switchTab(step) {
    var tabs = ["overview", "library", "firmware"]
    var index = tabs.indexOf(activeTab)
    activeTab = tabs[(index + step + tabs.length) % tabs.length]
    panelFlick.contentY = 0
  }

  function tabActions() {
    if (activeTab === "overview") return [ejectRow]
    if (activeTab === "library") return [inboxRow, syncRow, importRow]
    return [firmwareCheckRow, firmwareConfirmButton, firmwarePrepareButton, firmwareInstallButton]
  }

  function focusFirstAction(direction) {
    var actions = tabActions()
    if (direction < 0) actions.reverse()
    for (var i = 0; i < actions.length; i++) {
      var target = actions[i]
      if (target && target.visible && target.enabled) {
        if (target.focusAction) target.focusAction()
        else target.forceActiveFocus()
        return
      }
    }
  }

  function actionFocusActive() {
    var actions = [ejectRow, inboxRow, syncRow, importRow,
      firmwareCheckRow, firmwareConfirmButton, firmwarePrepareButton, firmwareInstallButton]
    for (var i = 0; i < actions.length; i++) {
      var target = actions[i]
      if (target && (target.actionHasFocus || target.activeFocus)) return true
    }
    return false
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
      clearAction()
    }
  }

  visible: mode !== "disconnected"
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Process {
    id: statusProbe
    command: [root.helperPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.statusCandidate = Model.parseKeyValue(text)
    }
    onExited: function(exitCode) {
      var observed = root.statusCandidate || ({})
      var nextMode = observed.mode || (exitCode === 10 ? "data" : exitCode === 20 ? "dac"
        : exitCode === 1 ? "disconnected" : "error")
      var nextFingerprint = observed.fingerprint || nextMode
      var nextToken = observed.connection_token || nextFingerprint
      var nextMountToken = observed.mount_token || nextMode
      var modeChanged = root.mode !== nextMode
      var connectionChanged = root.connectionToken !== nextToken
      var mountChanged = root.mountToken !== nextMountToken
      if (modeChanged || connectionChanged) {
        root.cancelArms()
        root.clearAction()
        root.activeTab = "overview"
        root.detailsRefreshFailed = false
        root.mountRetryCount = nextMode === "data" ? 5 : 0
        root.refreshRetryCount = 0
      }
      if (nextMode === "disconnected") root.close()
      root.mode = nextMode
      root.connectionFingerprint = nextFingerprint
      root.connectionToken = nextToken
      root.mountToken = nextMountToken
      root.statusCandidate = ({})
      if (nextMode === "error") {
        mountRetryTimer.stop()
        if (detailsProbe.running) detailsProbe.running = false
        root.details = ({ device_error: observed.device_error || "Echo Shelf helper failed" })
      } else if ((modeChanged || connectionChanged) && nextMode !== "disconnected") {
        if (!cachedDetailsProbe.running) cachedDetailsProbe.running = true
        root.refreshDetails()
      } else if (mountChanged && nextMode !== "disconnected") {
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
    onExited: function(exitCode) {
      root.updateCheckFailed = exitCode !== 0
      root.refreshDetails()
    }
  }

  Process {
    id: importProbe
    command: [root.helperPath, "--import-from-echo"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Local music copy updated", "Copy failed") }
  }

  Process {
    id: syncProbe
    command: [root.helperPath, "--sync-to-echo"]
    stdout: SplitParser { onRead: function(line) { root.handleActionLine(line) } }
    onExited: function(exitCode) { root.finishAction(exitCode, "Music copied to Echo", "Copy failed") }
  }

  Process {
    id: openInboxProbe
    command: [root.helperPath, "--open-inbox"]
    onExited: root.refreshDetails()
  }

  Process {
    id: openLibraryProbe
    command: [root.helperPath, "--open-library"]
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
        if (cached.mode === root.mode && cached.fingerprint === root.connectionFingerprint)
          root.details = cached
      }
    }
  }

  Process {
    id: detailsProbe
    command: ["timeout", "20", root.helperPath, "--details"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.detailsCandidate = Model.parseKeyValue(text)
    }
    onExited: function(exitCode) {
      var candidate = root.detailsCandidate || ({})
      var accepted = exitCode === 0 && candidate.mode === root.mode
        && candidate.fingerprint === root.connectionFingerprint
        && candidate.mount_token === root.mountToken
        && candidate.refresh_state === "fresh"
      if (accepted) {
        root.details = candidate
        root.detailsRefreshFailed = false
        root.refreshRetryCount = 0
        var waitingForMount = root.mode === "data" && root.mountRetryCount > 0
          && ((candidate.internal_present === "yes" && candidate.internal_mounted !== "yes")
            || (candidate.sd_present === "yes" && candidate.sd_mounted !== "yes"))
        if (waitingForMount) {
          root.mountRetryCount--
          mountRetryTimer.restart()
        } else {
          root.mountRetryCount = 0
        }
      } else if (root.mode === "data" || root.mode === "dac") {
        root.detailsRefreshFailed = true
        if (root.refreshRetryCount < 3) {
          root.refreshRetryCount++
          mountRetryTimer.restart()
        }
      }
      root.detailsCandidate = ({})
    }
  }

  Timer {
    interval: 21600000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.requestUpdateCheck()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer { id: actionClearTimer; interval: 8000; onTriggered: root.clearAction() }

  Timer {
    id: mountRetryTimer
    interval: 2000
    onTriggered: root.refreshDetails()
  }

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
    tooltipText: root.mode === "error" ? "Echo Shelf needs attention"
      : root.mode === "dac" ? "Echo Mini · USB DAC" : "Echo Mini · USB Data"
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
      Accessible.name: "Echo Mini"
      Accessible.role: Accessible.Pane
      blocked: root.actionFocusActive()
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.switchTab(dx) }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.focusFirstAction(direction) }
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (key === "1" || key === "o") root.activeTab = "overview"
        else if (key === "2" || key === "l" || key === "m") root.activeTab = "library"
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
            detail: root.details.device_error || ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: root.mode === "disconnected" ? 0.5 : 1.0
            iconComponent: Component {
              EchoGlyph { iconSize: Style.font.display; color: root.foreground }
            }
          }

          Item {
            visible: root.mode !== "dac"
            width: parent.width
            implicitHeight: visible ? tabs.implicitHeight : 0

            ButtonGroup {
              id: tabs
              anchors.horizontalCenter: parent.horizontalCenter
              options: [
                { value: "overview", label: "Overview" },
                { value: "library", label: "Music" },
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

          PanelSeparator { visible: root.mode !== "dac"; width: parent.width; foreground: root.foreground }

          Column {
            visible: root.mode !== "dac" && root.activeTab === "overview"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader {
              text: root.mode === "data" ? "STORAGE" : "CONNECTION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            ValueRow {
              visible: root.mode === "error"
              width: parent.width
              label: "Status"
              value: "Unavailable"
              caption: root.details.device_error || "Restart the shell or reinstall Echo Shelf"
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
                available: root.internalMounted
                loading: detailsProbe.running && root.details.internal === undefined
              }

              StorageMeter {
                width: parent.width
                label: "SD card"
                meta: root.storageUsage(root.details.sd)
                percent: parseInt(root.details.sd_percent || "0", 10)
                available: root.sdMounted
                loading: detailsProbe.running && root.details.sd === undefined
              }
            }

            PanelSeparator { visible: root.mode === "data"; width: parent.width; foreground: root.foreground }

            ActionRow {
              id: ejectRow
              width: parent.width
              visible: root.mode === "data"
              label: "Disconnect safely"
              caption: root.internalMounted || root.sdMounted
                ? "Before unplugging" : "Safe to unplug"
              buttonText: root.ejectArmed ? "Confirm eject" : "Eject"
              enabled: root.deviceReady && (root.internalMounted || root.sdMounted) && !root.actionRunning
              active: root.ejectArmed
              onTriggered: root.requestEject()
            }

            ActionFeedback { width: parent.width; kind: "overview" }
          }

          Column {
            visible: root.mode !== "dac" && root.activeTab === "library"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "ON THE ECHO"; foreground: root.foreground; fontFamily: root.fontFamily }

            Row {
              width: parent.width
              spacing: Style.space(8)
              StatBlock { width: (parent.width - parent.spacing) / 2; value: root.details.tracks || "—"; label: "Tracks" }
              StatBlock { width: (parent.width - parent.spacing) / 2; value: root.details.albums || "—"; label: "Albums" }
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }
            PanelSectionHeader { text: "TO ECHO"; foreground: root.foreground; fontFamily: root.fontFamily }

            ActionRow {
              id: inboxRow
              width: parent.width
              label: "Music to send"
              caption: "Echo Shelf / To Echo"
              buttonText: "Open"
              enabled: !openInboxProbe.running
              onTriggered: root.requestOpenInbox()
            }

            ActionRow {
              id: syncRow
              width: parent.width
              label: "Copy to Echo"
              caption: root.syncSummary()
              statusText: root.syncCurrent ? "UP TO DATE" : ""
              buttonText: root.syncArmed ? "Confirm copy" : "Copy"
              enabled: root.mode === "data" && root.deviceReady && root.sdMounted
                && !root.actionRunning
                && !root.syncCurrent
              active: root.syncArmed
              onTriggered: root.requestSync()
            }

            PanelSectionHeader { text: "FROM ECHO"; foreground: root.foreground; fontFamily: root.fontFamily }

            ActionRow {
              id: importRow
              width: parent.width
              label: "Local music copy"
              caption: root.importSummary()
              buttonText: root.importCurrent ? "Open"
                : root.importNew === 0 && root.importConflicts > 0 ? "Review"
                : root.importArmed ? "Confirm copy" : "Copy"
              enabled: root.mode === "data" && root.deviceReady && root.sdMounted
                && !root.actionRunning
              active: root.importArmed
              onTriggered: root.requestImport()
            }

            ActionFeedback { width: parent.width; kind: "library" }
          }

          Column {
            visible: root.mode !== "dac" && root.activeTab === "firmware"
            width: parent.width
            spacing: Style.space(12)

            PanelSectionHeader { text: "FIRMWARE"; foreground: root.foreground; fontFamily: root.fontFamily }

            ValueRow {
              width: parent.width
              label: "Installed"
              value: root.details.firmware_installed === "unknown" ? "Unknown" : root.details.firmware_installed || "—"
              caption: root.firmwareSummary()
            }

            ActionRow {
              id: firmwareCheckRow
              width: parent.width
              label: "Updates"
              caption: updateProbe.running ? "Checking official source…" : "Official firmware source"
              buttonText: updateProbe.running ? "Checking" : "Check"
              enabled: root.mode !== "error" && !root.actionRunning && !updateProbe.running
              onTriggered: root.requestUpdateCheck()
            }

            PanelSeparator {
              visible: root.firmwareActionAvailable
              width: parent.width
              foreground: root.foreground
            }
            PanelSectionHeader {
              visible: root.firmwareActionAvailable
              text: "NEXT STEP"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Button {
              id: firmwareConfirmButton
              width: parent.width
              visible: root.details.firmware_pending === "yes"
              enabled: root.deviceReady && !root.actionRunning
              text: "I verified " + (root.details.firmware_pending_version || "firmware") + " on the Echo"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              Accessible.name: text
              Accessible.description: "Records the version shown on the Echo Mini"
              Accessible.role: Accessible.Button
              Accessible.onPressAction: root.requestFirmwareConfirm()
              Keys.onEscapePressed: root.close()
              onClicked: root.requestFirmwareConfirm()
            }

            Button {
              id: firmwarePrepareButton
              width: parent.width
              visible: root.mode === "data" && root.firmwareAvailable
                && root.details.firmware_pending !== "yes" && root.details.firmware_prepared !== "yes"
              enabled: root.deviceReady && root.internalMounted && root.sdMounted && !root.actionRunning
                && root.importCurrent
              text: root.firmwarePrepareArmed ? "Confirm preparation" : "Prepare " + root.details.firmware_latest
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              Accessible.name: text
              Accessible.description: "Downloads, validates, and backs up before preparing firmware"
              Accessible.role: Accessible.Button
              Accessible.onPressAction: root.requestFirmwarePrepare()
              Keys.onEscapePressed: root.close()
              active: root.firmwarePrepareArmed
              onClicked: root.requestFirmwarePrepare()
            }

            Text {
              visible: firmwarePrepareButton.visible && !firmwarePrepareButton.enabled
              width: parent.width
              text: !root.deviceReady ? "Wait for the Echo status to refresh"
                : !root.internalMounted || !root.sdMounted ? "Mount both Echo volumes first"
                : !root.importCurrent ? "Import new files or review conflicts first"
                : "Another operation is running"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              Accessible.name: text
              Accessible.role: Accessible.StaticText
            }

            Button {
              id: firmwareInstallButton
              width: parent.width
              visible: root.details.firmware_prepared === "yes"
              enabled: root.mode === "data" && root.deviceReady && root.internalMounted
                && !root.sdPresent && !root.actionRunning
              text: root.sdPresent ? "Safely eject, remove SD, reconnect"
                : !root.internalMounted ? "Reconnect in USB Data"
                : root.firmwareInstallArmed ? "Confirm installation"
                : "Install " + root.details.firmware_prepared_version
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              Accessible.name: text
              Accessible.description: "Copies and verifies the prepared firmware image"
              Accessible.role: Accessible.Button
              Accessible.onPressAction: root.requestFirmwareInstall()
              Keys.onEscapePressed: root.close()
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
    Accessible.name: label + ", " + (loading ? "reading" : available ? percent + " percent, " + meta : "not mounted")
    Accessible.role: Accessible.StaticText
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
    Accessible.name: label + ", " + value + " percent"
    Accessible.role: Accessible.ProgressBar
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
    readonly property bool actionHasFocus: actionButton.activeFocus
    function focusAction() { if (actionButton.visible && actionButton.enabled) actionButton.forceActiveFocus() }
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
        id: actionButton
        Layout.alignment: Qt.AlignVCenter
        visible: actionRow.statusText === ""
        text: actionRow.buttonText
        enabled: actionRow.enabled
        active: actionRow.active
        bordered: true
        focusable: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        Accessible.name: actionRow.label + ", " + actionRow.buttonText
        Accessible.description: actionRow.caption
        Accessible.role: Accessible.Button
        Accessible.onPressAction: actionRow.triggered()
        Keys.onEscapePressed: root.close()
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
    Accessible.name: root.actionStatus !== "" ? root.actionStatus
      : root.actionLabel + ", " + root.actionProgress + " percent"
    Accessible.role: Accessible.StatusBar
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
