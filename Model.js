.pragma library

// Pure parsing and formatting helpers for the collector.
function parseCpu(text) {
  var line = String(text).split("\n", 1)[0].trim().split(/\s+/).slice(1).map(Number)
  if (line.length < 4) return null
  var idle = line[3] + (line[4] || 0)
  var total = 0
  for (var i = 0; i < Math.min(line.length, 8); i++) total += line[i]
  return { idle: idle, total: total }
}

function cpuPercent(prev, cur) {
  if (!prev || !cur) return 0
  var dt = cur.total - prev.total
  if (dt <= 0) return 0
  return Math.max(0, Math.min(100, (1 - (cur.idle - prev.idle) / dt) * 100))
}

function parseMeminfo(text) {
  var out = {}
  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^(\w+):\s+(\d+)/)
    if (m) out[m[1]] = Number(m[2]) * 1024
  }
  return out
}

function parseZram(text) {
  var f = String(text).trim().split(/\s+/).map(Number)
  if (f.length < 3 || isNaN(f[0])) return null
  return { original: f[0], compressed: f[1], used: f[2] }
}

function push(list, value, max) {
  var next = list.concat([value])
  return next.length > max ? next.slice(next.length - max) : next
}

function formatBytes(bytes) {
  var units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var v = Number(bytes)
  var i = 0
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
  return v.toFixed(i >= 3 ? 1 : 0) + " " + units[i]
}

function formatPercent(value) {
  return Math.round(value) + "%"
}

function formatTemp(celsius) {
  return celsius > 0 ? Math.round(celsius) + "°" : "--"
}

function parseCpuCores(text) {
  var out = []
  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (!/^cpu\d+\s/.test(lines[i])) continue
    var f = lines[i].trim().split(/\s+/).slice(1).map(Number)
    var total = 0
    for (var j = 0; j < Math.min(f.length, 8); j++) total += f[j]
    out.push({ idle: f[3] + (f[4] || 0), total: total })
  }
  return out
}

function coresPercent(prev, cur) {
  var out = []
  for (var i = 0; i < cur.length; i++) out.push(prev && prev[i] ? cpuPercent(prev[i], cur[i]) : 0)
  return out
}

function parseDf(text) {
  var lines = String(text).trim().split("\n").slice(1)
  var seen = {}
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 5 || seen[f[0]]) continue
    var size = Number(f[2])
    if (!(size > 0)) continue
    seen[f[0]] = true
    out.push({ source: f[0], mount: f[1], size: size, used: Number(f[3]), avail: Number(f[4]) })
  }
  return out
}

function parseNet(text) {
  var out = {}
  var lines = String(text).split("\n").slice(2)
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([^:\s]+):\s*(.*)$/)
    if (!m || /^(lo|veth|docker|br-|virbr)/.test(m[1])) continue
    var f = m[2].trim().split(/\s+/).map(Number)
    if (f.length < 9) continue
    out[m[1]] = { rx: f[0], tx: f[8] }
  }
  return out
}

function parseDiskstats(text) {
  var out = {}
  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(/\s+/)
    if (f.length < 14) continue
    var name = f[2]
    if (!/^(nvme\d+n\d+|sd[a-z]+|vd[a-z]+|mmcblk\d+)$/.test(name)) continue
    out[name] = { read: Number(f[5]) * 512, write: Number(f[9]) * 512, ioMs: Number(f[12]) }
  }
  return out
}

function rates(prev, cur, dtMs, fields) {
  var out = []
  if (!prev || dtMs <= 0) return out
  var keys = Object.keys(cur).sort()
  for (var i = 0; i < keys.length; i++) {
    var a = prev[keys[i]], b = cur[keys[i]]
    if (!a) continue
    var row = { name: keys[i] }
    for (var j = 0; j < fields.length; j++)
      row[fields[j]] = Math.max(0, (b[fields[j]] - a[fields[j]]) * 1000 / dtMs)
    out.push(row)
  }
  return out
}

function sum(rows, field) {
  var t = 0
  for (var i = 0; i < rows.length; i++) t += rows[i][field]
  return t
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

function batteryWatts(powerNowUw, currentNowUa, voltageNowUv) {
  if (powerNowUw > 0) return powerNowUw / 1e6
  return Math.abs(currentNowUa) * voltageNowUv / 1e12
}

function _toKb(token) {
  var m = String(token).match(/^([\d.]+)([kmgt]?)$/i)
  if (!m) return 0
  var mult = { "": 1, k: 1, m: 1024, g: 1024 * 1024, t: 1024 * 1024 * 1024 }
  return Number(m[1]) * mult[m[2].toLowerCase()]
}

function parseTop(text) {
  var lines = String(text).split("\n")
  var start = -1
  for (var i = lines.length - 1; i >= 0; i--) {
    if (/^\s*PID\s+USER/.test(lines[i])) { start = i; break }
  }
  if (start < 0) return []
  var out = []
  for (var j = start + 1; j < lines.length; j++) {
    var f = lines[j].trim().split(/\s+/)
    if (f.length < 12) continue
    out.push({ pid: Number(f[0]), cpu: Number(f[8]), memPct: Number(f[9]), memKb: _toKb(f[5]), name: f.slice(11).join(" ") })
  }
  return out
}

function topBy(procs, field, n) {
  return procs.slice().sort(function(a, b) { return b[field] - a[field] }).slice(0, n)
}

function gpuBusyPercent(prevRc6Ms, curRc6Ms, dtMs) {
  if (dtMs <= 0 || prevRc6Ms < 0) return 0
  return Math.max(0, Math.min(100, 100 - (curRc6Ms - prevRc6Ms) / dtMs * 100))
}

function parseLoad(text) {
  var f = String(text).trim().split(/\s+/)
  return f.length >= 3 ? f.slice(0, 3).join("  ") : ""
}

function parseUevent(text) {
  var out = {}
  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var k = lines[i].indexOf("=")
    if (k > 0) out[lines[i].slice(0, k)] = lines[i].slice(k + 1)
  }
  return out
}

// Fields: utilization.gpu, clocks.current.graphics, clocks.max.graphics.
// An unavailable field ("N/A") carries no number; busy and freq must parse or the sample is rejected.
function parseNvidiaSmi(text) {
  var f = String(text).trim().split("\n")[0].split(",")
  if (f.length < 3) return null
  var busy = _nvidiaNum(f[0])
  var freq = _nvidiaNum(f[1])
  if (isNaN(busy) || isNaN(freq)) return null
  return { busy: busy, freq: freq, maxFreq: _nvidiaNum(f[2]) || 0 }
}

function _nvidiaNum(field) {
  var s = String(field).replace(/[^0-9.]/g, "")
  return s === "" ? NaN : Number(s)
}

function gpuSourceLabel(kind) {
  if (kind === "nvidia") return "Reported by nvidia-smi on the NVIDIA GPU."
  if (kind === "intel") return "Estimated from the time the GPU is not in RC6 power-down (no privileges needed)."
  return ""
}
