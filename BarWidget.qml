import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar readout and host for the detail panel.
BarWidget {
  id: root
  moduleName: "fernando.jarvis-monitor"

  readonly property alias collector: collector

  readonly property string label: "󰻠 " + Model.formatPercent(collector.cpu)
    + "  󰍛 " + Model.formatPercent(collector.memPercent)
    + "  󰔏 " + Model.formatTemp(collector.temp)
    + (collector.hasGpu ? "  󰢮 " + Model.formatPercent(collector.gpuBusy) : "")

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("collector" in target) target.collector = collector
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Collector {
    id: collector
    interval: Number(root.setting("interval", 2000))
    processesActive: root.opened
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "fernando.jarvis-monitor"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    tooltipText: "Jarvis Monitor"
    horizontalMargin: 8.75
    onPressed: function(b) {
      if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop") }
      else root.togglePanel()
    }
  }
}
