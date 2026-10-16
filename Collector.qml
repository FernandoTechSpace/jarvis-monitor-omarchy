import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Reads /proc and /sys on one timer and keeps a short history.
Item {
  id: root
  visible: false

  property bool running: true
  property int interval: 2000
  property int historyLength: 60

  property real cpu: 0
  property real memUsed: 0
  property real memTotal: 0
  property real swapUsed: 0
  property real swapTotal: 0
  property real zramOriginal: 0
  property real zramCompressed: 0
  property real temp: 0
  property var coreUsage: []
  property var disks: []

  property var netIfaces: []
  property real netRx: 0
  property real netTx: 0
  property var netRxHistory: []
  property var netTxHistory: []

  property var diskIo: []
  property real diskRead: 0
  property real diskWrite: 0
  property var diskReadHistory: []
  property var diskWriteHistory: []

  property string gpuPath: ""
  property string gpuKind: ""
  property bool hasGpu: false
  property real gpuBusy: 0
  property real gpuFreq: 0
  property real gpuMaxFreq: 0
  property var gpuHistory: []
  property var gpuFreqHistory: []

  property string load: ""
  property int coreCount: coreUsage.length

  property bool processesActive: false
  property var topCpu: []
  property var topMem: []

  property var batHistory: []

  property string batPath: ""
  property var batFiles: []
  property bool hasBattery: false
  property real batPercent: 0
  property string batStatus: ""
  property real batWatts: 0

  property var cpuHistory: []
  property var memHistory: []
  property var tempHistory: []

  readonly property real memPercent: memTotal > 0 ? memUsed / memTotal * 100 : 0

  property var _prevCpu: null
  property var _prevCores: null
  property var _prevNet: null
  property var _prevDisk: null
  property real _prevAt: 0
  property real _prevRc6: -1
  property string tempPath: ""

  function readText(view) {
    try { view.reload(); return String(view.text()).trim() } catch (e) { return "" }
  }
  function readNumber(view) {
    var t = readText(view)
    return t === "" ? NaN : Number(t)
  }

  function tick() {
    statFile.reload()
    var cur = Model.parseCpu(statFile.text())
    root.cpu = Model.cpuPercent(root._prevCpu, cur)
    root._prevCpu = cur

    var cores = Model.parseCpuCores(statFile.text())
    root.coreUsage = Model.coresPercent(root._prevCores, cores)
    root._prevCores = cores

    memFile.reload()
    var mem = Model.parseMeminfo(memFile.text())
    root.memTotal = mem.MemTotal || 0
    root.memUsed = root.memTotal - (mem.MemAvailable || 0)
    root.swapTotal = mem.SwapTotal || 0
    root.swapUsed = root.swapTotal - (mem.SwapFree || 0)

    zramFile.reload()
    var z = Model.parseZram(zramFile.text())
    root.zramOriginal = z ? z.original : 0
    root.zramCompressed = z ? z.compressed : 0

    if (root.tempPath !== "") {
      tempFile.reload()
      var raw = parseInt(tempFile.text())
      root.temp = isNaN(raw) ? 0 : raw / 1000
    }

    var now = Date.now()
    var dt = now - root._prevAt

    netFile.reload()
    var net = Model.parseNet(netFile.text())
    root.netIfaces = Model.rates(root._prevNet, net, dt, ["rx", "tx"])
    root.netRx = Model.sum(root.netIfaces, "rx")
    root.netTx = Model.sum(root.netIfaces, "tx")
    root._prevNet = net

    diskFile.reload()
    var dsk = Model.parseDiskstats(diskFile.text())
    var rows = Model.rates(root._prevDisk, dsk, dt, ["read", "write", "ioMs"])
    for (var i = 0; i < rows.length; i++) rows[i].busy = Math.min(100, rows[i].ioMs / 10)
    root.diskIo = rows
    root.diskRead = Model.sum(rows, "read")
    root.diskWrite = Model.sum(rows, "write")
    root._prevDisk = dsk

    root._prevAt = now

    if (root.gpuKind === "nvidia") {
      if (!nvidiaSmi.running) nvidiaSmi.running = true
    } else if (root.gpuPath !== "") {
      var rc6 = readNumber(gpuRc6)
      var act = readNumber(gpuAct)
      root.hasGpu = !isNaN(rc6) || !isNaN(act)
      root.gpuBusy = isNaN(rc6) ? 0 : Model.gpuBusyPercent(root._prevRc6, rc6, dt)
      root._prevRc6 = isNaN(rc6) ? -1 : rc6
      root.gpuFreq = isNaN(act) ? 0 : act
      root.gpuMaxFreq = readNumber(gpuMax) || 0
      root.gpuHistory = Model.push(root.gpuHistory, root.gpuBusy, root.historyLength)
      root.gpuFreqHistory = Model.push(root.gpuFreqHistory, root.gpuFreq, root.historyLength)
    }

    root.load = Model.parseLoad(readText(loadFile))

    if (root.batPath !== "") {
      var bat = Model.parseUevent(readText(batUevent))
      var cap = Number(bat.POWER_SUPPLY_CAPACITY)
      root.hasBattery = bat.POWER_SUPPLY_PRESENT === "1" && !isNaN(cap)
      root.batPercent = root.hasBattery ? cap : 0
      root.batStatus = bat.POWER_SUPPLY_STATUS || ""
      if (root.hasBattery && root.batStatus !== "Full") {
        root.batWatts = Model.batteryWatts(readNumber(batPower), readNumber(batCurrent), Number(bat.POWER_SUPPLY_VOLTAGE_NOW))
      } else {
        root.batWatts = 0
      }
    }

    root.batHistory = Model.push(root.batHistory, root.batWatts, root.historyLength)
    root.netRxHistory = Model.push(root.netRxHistory, root.netRx, root.historyLength)
    root.netTxHistory = Model.push(root.netTxHistory, root.netTx, root.historyLength)
    root.diskReadHistory = Model.push(root.diskReadHistory, root.diskRead, root.historyLength)
    root.diskWriteHistory = Model.push(root.diskWriteHistory, root.diskWrite, root.historyLength)
    root.cpuHistory = Model.push(root.cpuHistory, root.cpu, root.historyLength)
    root.memHistory = Model.push(root.memHistory, root.memPercent, root.historyLength)
    root.tempHistory = Model.push(root.tempHistory, root.temp, root.historyLength)
  }

  FileView { id: statFile; path: "/proc/stat"; blockLoading: true }
  FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true }
  FileView { id: zramFile; path: "/sys/block/zram0/mm_stat"; blockLoading: true }
  FileView { id: netFile; path: "/proc/net/dev"; blockLoading: true }
  FileView { id: diskFile; path: "/proc/diskstats"; blockLoading: true }
  FileView { id: batUevent; path: root.batPath !== "" ? root.batPath + "/uevent" : ""; blockLoading: true }
  FileView { id: batPower; path: root.batPath !== "" && root.batFiles.indexOf("power_now") >= 0 ? root.batPath + "/power_now" : ""; blockLoading: true }
  FileView { id: batCurrent; path: root.batPath !== "" && root.batFiles.indexOf("current_now") >= 0 ? root.batPath + "/current_now" : ""; blockLoading: true }
  FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true }
  FileView { id: gpuRc6; path: root.gpuPath !== "" ? root.gpuPath + "/gt/gt0/rc6_residency_ms" : ""; blockLoading: true }
  FileView { id: gpuAct; path: root.gpuPath !== "" ? root.gpuPath + "/gt_act_freq_mhz" : ""; blockLoading: true }
  FileView { id: gpuMax; path: root.gpuPath !== "" ? root.gpuPath + "/gt_max_freq_mhz" : ""; blockLoading: true }
  FileView { id: tempFile; path: root.tempPath; blockLoading: true }

  // Locates the CPU package sensor by name.
  Process {
    id: findTemp
    command: ["sh", "-c",
      "for d in /sys/class/hwmon/hwmon*; do case \"$(cat $d/name 2>/dev/null)\" in coretemp|k10temp|zenpower) echo $d/temp1_input; exit;; esac; done; " +
      "for z in /sys/class/thermal/thermal_zone*; do case \"$(cat $z/type 2>/dev/null)\" in x86_pkg_temp) echo $z/temp; exit;; esac; done"]
    stdout: StdioCollector {
      onStreamFinished: root.tempPath = text.trim()
    }
  }

  // Prefers the NVIDIA GPU when nvidia-smi reports values, otherwise the DRM card that exposes Intel frequency.
  Process {
    id: findGpuSource
    command: ["sh", "-c",
      "if out=$(nvidia-smi --query-gpu=utilization.gpu,clocks.current.graphics,clocks.max.graphics --format=csv,noheader,nounits 2>/dev/null) && [ -n \"$out\" ]; then echo nvidia; exit 0; fi; " +
      "for c in /sys/class/drm/card[0-9]; do [ -e $c/gt_act_freq_mhz ] && echo intel $c && break; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = text.trim().split(/\s+/)
        root.gpuKind = parts[0] === "nvidia" ? "nvidia" : (parts[0] === "intel" ? "intel" : "")
        root.gpuPath = root.gpuKind === "intel" ? parts[1] : ""
      }
    }
  }

  // NVIDIA utilization and frequencies are only exposed through nvidia-smi.
  Process {
    id: nvidiaSmi
    command: ["nvidia-smi", "--query-gpu=utilization.gpu,clocks.current.graphics,clocks.max.graphics", "--format=csv,noheader,nounits"]
    stdout: StdioCollector {
      onStreamFinished: {
        var g = Model.parseNvidiaSmi(text)
        if (!g) {
          root.hasGpu = false
          return
        }
        root.hasGpu = true
        root.gpuBusy = g.busy
        root.gpuFreq = g.freq
        root.gpuMaxFreq = g.maxFreq
        root.gpuHistory = Model.push(root.gpuHistory, root.gpuBusy, root.historyLength)
        root.gpuFreqHistory = Model.push(root.gpuFreqHistory, root.gpuFreq, root.historyLength)
      }
    }
  }

  // Only the second top iteration reflects current usage.
  Process {
    id: topProc
    command: ["env", "LC_ALL=C", "top", "-b", "-n", "2", "-d", "1", "-w", "512", "-e", "k", "-o", "%CPU"]
    stdout: StdioCollector {
      onStreamFinished: {
        var all = Model.parseTop(text)
        root.topCpu = Model.topBy(all, "cpu", 10)
        root.topMem = Model.topBy(all, "memKb", 10)
      }
    }
  }

  Timer {
    interval: 3000
    running: root.running && root.processesActive
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!topProc.running) topProc.running = true
  }

  Process {
    id: findBattery
    command: ["sh", "-c",
      "d=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1); [ -n \"$d\" ] || exit 0; echo $d; " +
      "for f in power_now current_now; do [ -e $d/$f ] && echo $f; done"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.batFiles = lines.slice(1)
        root.batPath = lines[0] || ""
      }
    }
  }

  // df runs on a slower timer than the other metrics.
  Process {
    id: dfProc
    command: ["df", "-B1", "--output=source,target,size,used,avail",
      "-x", "tmpfs", "-x", "devtmpfs", "-x", "efivarfs", "-x", "squashfs", "-x", "overlay"]
    stdout: StdioCollector {
      onStreamFinished: root.disks = Model.parseDf(text)
    }
  }

  Timer {
    interval: 15000
    running: root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: dfProc.running = true
  }

  Timer {
    interval: root.interval
    running: root.running
    repeat: true
    triggeredOnStart: true
    onTriggered: root.tick()
  }

  Component.onCompleted: {
    findTemp.running = true
    findBattery.running = true
    findGpuSource.running = true
  }
}
