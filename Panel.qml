import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Overview cards and per-category detail views.
Panel {
  id: root
  moduleName: "fernando.jarvis-monitor"
  ipcTarget: "fernando.jarvis-monitor"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var collector: null
  readonly property var barIdentity: hostWidget || root

  readonly property var c: collector

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var categories: [
    { id: "cpu", title: "CPU" },
    { id: "memory", title: "Memory" },
    { id: "thermal", title: "Temperature" },
    { id: "gpu", title: "GPU" },
    { id: "network", title: "Network" },
    { id: "diskio", title: "Disk I/O" },
    { id: "storage", title: "Storage" },
    { id: "battery", title: "Battery" },
    { id: "processes", title: "Processes" }
  ]
  readonly property int columns: 3

  property string view: "overview"
  property int sel: 0

  readonly property bool inDetail: view !== "overview"
  readonly property string viewTitle: {
    for (var i = 0; i < categories.length; i++) if (categories[i].id === view) return categories[i].title
    return ""
  }

  function open() { root.controller.show() }
  function close() {
    root.controller.hide()
    root.view = "overview"
  }
  function toggle() { root.opened ? root.close() : root.open() }

  function openCategory(index) {
    if (index < 0 || index >= categories.length) return
    root.sel = index
    root.view = categories[index].id
    detailScroll.contentY = 0
  }

  function back() {
    root.view = "overview"
  }

  function move(dx, dy) {
    if (root.inDetail) {
      if (dx < 0) root.back()
      if (dy !== 0) {
        var max = Math.max(0, detailScroll.contentHeight - detailScroll.height)
        detailScroll.contentY = Math.max(0, Math.min(max, detailScroll.contentY + dy * 80))
      }
      return
    }
    var col = Math.max(0, Math.min(columns - 1, sel % columns + dx))
    var row = Math.max(0, Math.min(Math.ceil(categories.length / columns) - 1, Math.floor(sel / columns) + dy))
    root.sel = Math.min(categories.length - 1, row * columns + col)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(800))
    contentHeight: panel.fittedContentHeight(Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.move(dx, dy) }
      onActivateRequested: { if (!root.inDetail) root.openCategory(root.sel) }
      onCloseRequested: { if (root.inDetail) root.back(); else root.close() }
      onTabRequested: function(direction) { if (root.bar) root.bar.switchPanelFrom(root.barIdentity, direction) }
      onTextKey: function(t) {
        if (t === "b" || t === "B") root.back()
        else if (t >= "1" && t <= "9") root.openCategory(Number(t) - 1)
      }

      Column {
        anchors.fill: parent
        visible: !root.inDetail
        spacing: Style.space(10)

        Grid {
          id: cardGrid
          width: parent.width
          columns: root.columns
          columnSpacing: Style.space(10)
          rowSpacing: Style.space(10)

          readonly property int rowCount: Math.ceil(root.categories.length / columns)
          readonly property real cardWidth: (width - columnSpacing * (columns - 1)) / columns
          readonly property real cardHeight: (parent.height - hint.implicitHeight - parent.spacing
            - rowSpacing * (rowCount - 1)) / rowCount

          Card {
            index: 0
            title: "CPU"
            value: c ? Model.formatPercent(c.cpu) : "--"
            sub: c ? c.coreCount + " threads  ·  load " + c.load.split("  ")[0] : ""
            history: c ? c.cpuHistory : []
          }

          Card {
            index: 1
            title: "Memory"
            value: c ? Model.formatPercent(c.memPercent) : "--"
            sub: c ? Model.formatBytes(c.memUsed) + " of " + Model.formatBytes(c.memTotal) : ""
            history: c ? c.memHistory : []
          }

          Card {
            index: 2
            title: "Temperature"
            value: c ? Model.formatTemp(c.temp) + "C" : "--"
            sub: "CPU package"
            history: c ? c.tempHistory : []
          }

          Card {
            index: 3
            title: "GPU"
            value: c && c.hasGpu ? Model.formatPercent(c.gpuBusy) : "n/a"
            sub: c && c.hasGpu ? Math.round(c.gpuFreq) + " / " + Math.round(c.gpuMaxFreq) + " MHz" : "No GPU stats"
            history: c ? c.gpuHistory : []
          }

          Card {
            index: 4
            title: "Network"
            value: c ? "↓ " + Model.formatRate(c.netRx) : "--"
            sub: c ? "↑ " + Model.formatRate(c.netTx) : ""
            history: c ? c.netRxHistory : []
            autoScale: true
            graphMax: 100 * 1024
          }

          Card {
            index: 5
            title: "Disk I/O"
            value: c ? "R " + Model.formatRate(c.diskRead) : "--"
            sub: c ? "W " + Model.formatRate(c.diskWrite) : ""
            history: c ? c.diskReadHistory : []
            autoScale: true
            graphMax: 1024 * 1024
          }

          Card {
            index: 6
            title: "Storage"
            value: c && c.disks.length > 0 ? Model.formatPercent(c.disks[0].used / c.disks[0].size * 100) : "--"
            sub: c && c.disks.length > 0 ? Model.formatBytes(c.disks[0].avail) + " free on " + c.disks[0].mount : ""
            fraction: c && c.disks.length > 0 ? c.disks[0].used / c.disks[0].size : -1
          }

          Card {
            index: 7
            title: "Battery"
            value: c && c.hasBattery ? Model.formatPercent(c.batPercent) : "none"
            sub: c && c.hasBattery ? c.batStatus + "  ·  " + c.batWatts.toFixed(1) + " W" : ""
            fraction: c && c.hasBattery ? c.batPercent / 100 : -1
          }

          Card {
            index: 8
            title: "Processes"
            value: c && c.topCpu.length > 0 ? c.topCpu[0].name : "--"
            sub: c && c.topCpu.length > 0 ? c.topCpu[0].cpu.toFixed(1) + "% CPU" : "Sampling…"
          }
        }

        Text {
          id: hint
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "← ↑ ↓ →  navigate   ·   Enter / click  open   ·   1-9  jump   ·   Esc  close"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Column {
        anchors.fill: parent
        visible: root.inDetail
        spacing: Style.space(8)

        Item {
          id: detailHeader
          width: parent.width
          height: backText.implicitHeight + Style.space(4)

          Text {
            id: backText
            text: "←  " + root.viewTitle
            textFormat: Text.PlainText
            color: backMouse.containsMouse ? Style.hoverStateColor(root.fg, Color.accent) : root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true

            MouseArea {
              id: backMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.back()
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Esc / ←  back   ·   ↑ ↓  scroll"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        PanelSeparator { foreground: root.fg }

        Flickable {
          id: detailScroll
          width: parent.width
          height: parent.height - detailHeader.height - parent.spacing * 2 - 1
          contentWidth: width
          contentHeight: detailColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: detailColumn
            width: detailScroll.width
            spacing: Style.space(12)

            Column {
              width: parent.width
              visible: root.view === "cpu"
              spacing: Style.space(12)

              MetricSection {
                title: "Total"
                value: c ? Model.formatPercent(c.cpu) : "--"
                detail: c ? "Load average  " + c.load : ""
                history: c ? c.cpuHistory : []
              }

              SectionTitle { text: "CORES" }

              Grid {
                id: coreGrid
                width: parent.width
                columns: 3
                columnSpacing: Style.space(14)
                rowSpacing: Style.space(10)

                Repeater {
                  model: c ? c.coreUsage : []

                  UsageBar {
                    required property int index
                    required property real modelData
                    width: (coreGrid.width - coreGrid.columnSpacing * (coreGrid.columns - 1)) / coreGrid.columns
                    label: "CPU " + index
                    fraction: modelData / 100
                    valueText: Model.formatPercent(modelData)
                  }
                }
              }
            }

            Column {
              width: parent.width
              visible: root.view === "memory"
              spacing: Style.space(12)

              MetricSection {
                title: "RAM"
                value: c ? Model.formatBytes(c.memUsed) + " / " + Model.formatBytes(c.memTotal) : "--"
                history: c ? c.memHistory : []
              }

              SectionTitle { text: "SWAP" }
              UsageBar {
                width: parent.width
                label: "Swap"
                fraction: c && c.swapTotal > 0 ? c.swapUsed / c.swapTotal : 0
                valueText: c ? Model.formatBytes(c.swapUsed) + " / " + Model.formatBytes(c.swapTotal) : ""
              }

              SectionTitle { text: "ZRAM" }
              Text {
                text: c ? Model.formatBytes(c.zramOriginal) + " stored  ·  "
                  + Model.formatBytes(c.zramCompressed) + " compressed"
                  + (c.zramCompressed > 0 ? "  (" + (c.zramOriginal / c.zramCompressed).toFixed(1) + "x)" : "") : ""
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }

            Column {
              width: parent.width
              visible: root.view === "thermal"
              spacing: Style.space(12)

              MetricSection {
                title: "CPU package"
                value: c ? Model.formatTemp(c.temp) + "C" : "--"
                history: c ? c.tempHistory : []
              }
            }

            Column {
              width: parent.width
              visible: root.view === "gpu"
              spacing: Style.space(12)

              MetricSection {
                title: "Busy"
                value: c && c.hasGpu ? Model.formatPercent(c.gpuBusy) : "n/a"
                detail: c ? Model.gpuSourceLabel(c.gpuKind) : ""
                history: c ? c.gpuHistory : []
              }

              MetricSection {
                title: "Frequency"
                value: c && c.hasGpu ? Math.round(c.gpuFreq) + " MHz" : "n/a"
                detail: c && c.hasGpu && c.gpuMaxFreq > 0 ? "Max " + Math.round(c.gpuMaxFreq) + " MHz" : ""
                history: c ? c.gpuFreqHistory : []
                graphMax: c && c.gpuMaxFreq > 0 ? c.gpuMaxFreq : 1200
              }
            }

            Column {
              width: parent.width
              visible: root.view === "network"
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(14)

                Repeater {
                  model: [
                    { title: "Down", rate: c ? c.netRx : 0, hist: c ? c.netRxHistory : [] },
                    { title: "Up", rate: c ? c.netTx : 0, hist: c ? c.netTxHistory : [] }
                  ]

                  MetricSection {
                    required property var modelData
                    width: (parent.width - Style.space(14)) / 2
                    title: modelData.title
                    value: Model.formatRate(modelData.rate)
                    history: modelData.hist
                    autoScale: true
                    graphMax: 100 * 1024
                  }
                }
              }

              SectionTitle { text: "INTERFACES" }

              Repeater {
                model: c ? c.netIfaces : []

                Text {
                  required property var modelData
                  text: modelData.name + "     ↓ " + Model.formatRate(modelData.rx) + "     ↑ " + Model.formatRate(modelData.tx)
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            Column {
              width: parent.width
              visible: root.view === "diskio"
              spacing: Style.space(12)

              Row {
                width: parent.width
                spacing: Style.space(14)

                Repeater {
                  model: [
                    { title: "Read", rate: c ? c.diskRead : 0, hist: c ? c.diskReadHistory : [] },
                    { title: "Write", rate: c ? c.diskWrite : 0, hist: c ? c.diskWriteHistory : [] }
                  ]

                  MetricSection {
                    required property var modelData
                    width: (parent.width - Style.space(14)) / 2
                    title: modelData.title
                    value: Model.formatRate(modelData.rate)
                    history: modelData.hist
                    autoScale: true
                    graphMax: 1024 * 1024
                  }
                }
              }

              SectionTitle { text: "DEVICES" }

              Repeater {
                model: c ? c.diskIo : []

                UsageBar {
                  required property var modelData
                  width: detailColumn.width
                  label: modelData.name
                  fraction: modelData.busy / 100
                  valueText: "R " + Model.formatRate(modelData.read) + "  ·  W " + Model.formatRate(modelData.write)
                    + "  ·  busy " + Model.formatPercent(modelData.busy)
                }
              }
            }

            Column {
              width: parent.width
              visible: root.view === "storage"
              spacing: Style.space(12)

              Repeater {
                model: c ? c.disks : []

                UsageBar {
                  required property var modelData
                  width: detailColumn.width
                  label: modelData.mount + "   (" + modelData.source + ")"
                  fraction: modelData.size > 0 ? modelData.used / modelData.size : 0
                  valueText: Model.formatBytes(modelData.used) + " used  ·  "
                    + Model.formatBytes(modelData.avail) + " free  ·  "
                    + Model.formatBytes(modelData.size)
                }
              }
            }

            Column {
              width: parent.width
              visible: root.view === "battery"
              spacing: Style.space(12)

              Text {
                visible: !(c && c.hasBattery)
                text: "No battery detected."
                textFormat: Text.PlainText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              UsageBar {
                visible: c && c.hasBattery
                width: parent.width
                label: c ? c.batStatus : ""
                fraction: c ? c.batPercent / 100 : 0
                valueText: c ? Model.formatPercent(c.batPercent) : ""
              }

              MetricSection {
                visible: c && c.hasBattery
                title: "Power draw"
                value: c ? c.batWatts.toFixed(1) + " W" : "--"
                history: c ? c.batHistory : []
                autoScale: true
                graphMax: 20
              }
            }

            Row {
              width: parent.width
              visible: root.view === "processes"
              spacing: Style.space(14)

              ProcessList {
                width: (parent.width - Style.space(14)) / 2
                title: "TOP CPU  (100% = one core)"
                rows: c ? c.topCpu : []
                byMemory: false
              }

              ProcessList {
                width: (parent.width - Style.space(14)) / 2
                title: "TOP MEMORY"
                rows: c ? c.topMem : []
                byMemory: true
              }
            }
          }
        }
      }
    }
  }

  component Card: Rectangle {
    id: card
    required property int index
    property string title: ""
    property string value: ""
    property string sub: ""
    property var history: []
    property real graphMax: 100
    property bool autoScale: false
    property real fraction: -1

    readonly property bool selected: root.sel === index

    width: cardGrid.cardWidth
    height: cardGrid.cardHeight
    color: selected ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08) : "transparent"
    border.width: 1
    border.color: selected ? Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

    Column {
      id: cardColumn
      anchors.fill: parent
      anchors.margins: Style.space(10)
      spacing: Style.space(2)

      Text {
        text: (card.index + 1) + "  " + card.title.toUpperCase()
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        width: parent.width
        text: card.value
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        width: parent.width
        text: card.sub
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Sparkline {
        visible: card.fraction < 0 && card.history.length > 1
        width: parent.width
        height: Math.max(Style.space(20), cardColumn.height - y)
        values: card.history
        maxValue: card.graphMax
        autoScale: card.autoScale
        lineColor: Color.accent
      }

      Rectangle {
        visible: card.fraction >= 0
        width: parent.width
        height: Style.space(8)
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

        Rectangle {
          width: parent.width * Math.max(0, Math.min(1, card.fraction))
          height: parent.height
          color: card.fraction > 0.9 ? Color.urgent : Color.accent
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.sel = card.index
      onClicked: root.openCategory(card.index)
    }
  }

  component SectionTitle: PanelSectionHeader {
    foreground: root.fg
    fontFamily: root.fontFamily
    fontSize: Style.font.body
  }

  component MetricSection: Column {
    property string title: ""
    property string value: ""
    property string detail: ""
    property var history: []
    property real graphMax: 100
    property bool autoScale: false

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    SectionTitle { text: title.toUpperCase() }

    Text {
      text: value
      textFormat: Text.PlainText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      font.bold: true
    }

    Text {
      visible: detail !== ""
      width: parent.width
      wrapMode: Text.WordWrap
      text: detail
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Sparkline {
      width: parent.width
      height: Style.space(48)
      values: history
      maxValue: graphMax
      autoScale: parent.autoScale
      lineColor: Color.accent
    }
  }

  component UsageBar: Column {
    property string label: ""
    property string valueText: ""
    property real fraction: 0

    spacing: Style.space(3)

    Item {
      width: parent.width
      height: labelText.implicitHeight

      Text {
        id: labelText
        text: label
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        anchors.right: parent.right
        text: valueText
        textFormat: Text.PlainText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    Rectangle {
      width: parent.width
      height: Style.space(8)
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, fraction))
        height: parent.height
        color: fraction > 0.9 ? Color.urgent : Color.accent
      }
    }
  }

  component ProcessList: Column {
    property string title: ""
    property var rows: []
    property bool byMemory: false

    spacing: Style.space(6)

    SectionTitle { text: title }

    Text {
      visible: rows.length === 0
      text: "Sampling…"
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: rows

      Item {
        required property var modelData
        width: parent.width
        height: nameText.implicitHeight

        Text {
          id: nameText
          width: parent.width - valueText.implicitWidth - Style.space(8)
          text: modelData.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: valueText
          anchors.right: parent.right
          text: byMemory ? Model.formatBytes(modelData.memKb * 1024) : modelData.cpu.toFixed(1) + "%"
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
