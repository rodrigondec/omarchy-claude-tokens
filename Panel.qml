import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Claude token usage: current 5-hour session (consumption + reset countdown)
// and a per-day, per-model history. The collector runs only while the panel is open.
Panel {
  id: root

  moduleName: "io.github.rodrigondec.claude-usage"
  ipcTarget: "io.github.rodrigondec.claude-usage"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property var stats: null
  property bool withCache: false
  property real nowSec: Date.now() / 1000

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  // Color.muted is ~1.9:1 on dark themes; derive from the text colour for >=4.5:1.
  readonly property color dim: Util.alpha(Color.popups.text, 0.75)
  readonly property int historyDays: Math.max(7, Math.min(60,
    Math.round(Number(setting("historyDays", 14)) || 14)))
  readonly property string family: bar ? bar.fontFamily : Style.font.family
  readonly property string collectorPath: decodeURIComponent(
    String(Qt.resolvedUrl("claude-usage-collect")).replace("file://", ""))
  readonly property var palette: [accent, "#e0a030", "#5fb0d8", "#b07ad8", "#6fc47a", "#d86f6f"]

  // [input, output, cacheRead, cacheCreate] -> tokens counted
  function total(t) { return t[0] + t[1] + t[3] + (withCache ? t[2] : 0) }

  function fmt(n) {
    n = Number(n) || 0
    if (n >= 1e9) return (n / 1e9).toFixed(2) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
    return String(Math.round(n))
  }

  function shortModel(m) {
    return String(m).replace(/^claude-/, "").replace(/-\d{8}$/, "")
  }

  function sumModels(models) {
    var s = 0
    for (var m in models) s += total(models[m])
    return s
  }

  // All models seen in the window, biggest first (stable colour per model).
  readonly property var modelList: {
    if (!stats || !stats.days) return []
    var acc = {}
    for (var d in stats.days)
      for (var m in stats.days[d]) acc[m] = (acc[m] || 0) + total(stats.days[d][m])
    return Object.keys(acc).sort(function(a, b) { return acc[b] - acc[a] })
  }

  readonly property var dayList: {
    if (!stats || !stats.days) return []
    return Object.keys(stats.days).sort()
  }

  readonly property real maxDay: {
    var mx = 1
    for (var i = 0; i < dayList.length; i++)
      mx = Math.max(mx, sumModels(stats.days[dayList[i]]))
    return mx
  }

  function colorFor(model) {
    var i = modelList.indexOf(model)
    return palette[(i < 0 ? 0 : i) % palette.length]
  }

  function countdown(sec) {
    sec = Math.max(0, Math.floor(sec))
    var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60)
    return h > 0 ? h + "h " + m + "m" : m + "m"
  }

  function weekly() {
    if (!stats || !stats.limits) return null
    for (var i = 0; i < stats.limits.length; i++)
      if (String(stats.limits[i].label).indexOf("Weekly") === 0 && String(stats.limits[i].label).indexOf("Fable") < 0)
        return stats.limits[i]
    return null
  }

  function refresh() { if (!collector.running) collector.running = true }

  onOpenedChanged: {
    if (opened) { nowSec = Date.now() / 1000; refresh() }
  }

  Timer {
    interval: 30000; repeat: true; running: root.opened
    onTriggered: { root.nowSec = Date.now() / 1000; root.refresh() }
  }
  Timer {
    interval: 1000; repeat: true; running: root.opened
    onTriggered: root.nowSec = Date.now() / 1000
  }

  Process {
    id: collector
    command: [root.collectorPath, String(root.historyDays)]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.stats = JSON.parse(text) } catch (e) {}
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄨"
    tooltipText: "Claude Tokens"
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onActivateRequested: root.withCache = !root.withCache
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var k = String(text).toLowerCase()
        if (k === "c") root.withCache = !root.withCache
        else if (k === "r") root.refresh()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.panelGap

        // Header
        Row {
          width: parent.width
          Text {
            text: "CLAUDE TOKENS"
            font.letterSpacing: 0.6
            color: root.accent
            font.family: root.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Item { width: parent.width - hint.implicitWidth - 150; height: 1 }
          KeyHint {
            id: hint
            keyName: "c"
            label: root.withCache ? "hide cache reads" : "show cache reads"
            textColor: root.foreground
            fontFamily: root.family
            onActivated: root.withCache = !root.withCache
          }
        }

        // Current session
        Column {
          id: sessionCol
          width: parent.width
          spacing: Style.spacing.sm
          readonly property var s: root.stats ? root.stats.session : null

          Row {
            width: parent.width
            Text {
              text: "CURRENT SESSION (5h)"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.body
            }
            Item { width: parent.width - sessTotal.implicitWidth - 175; height: 1 }
            Text {
              id: sessTotal
              text: parent.parent.s && parent.parent.s.active ? root.fmt(root.sumModels(parent.parent.s.models)) + " tokens" : "—"
              color: root.foreground
              font.family: root.family
              font.pixelSize: Style.font.subtitle
            }
          }

          Item {
            width: parent.width
            height: Style.space(8)
            Rectangle { anchors.fill: parent; radius: 3; color: Util.alpha(root.foreground, 0.16) }
            Rectangle {
              readonly property var s: parent.parent.s
              width: s && s.active
                ? parent.width * Math.max(0, Math.min(1, (root.nowSec - s.start) / (s.end - s.start))) : 0
              height: parent.height
              radius: 3
              color: root.accent
            }
          }

          Text {
            readonly property var s: parent.s
            text: s && s.active
              ? "Resets in " + root.countdown(s.end - root.nowSec) + " (" + Qt.formatTime(new Date(s.end * 1000), "HH:mm") + ")  ·  "
                + s.messages + " replies"
              : (root.stats ? "No active session" : "Loading…")
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: parent.s && parent.s.active
              ? Object.keys(parent.s.models).sort(function(a, b) {
                  return root.total(parent.s.models[b]) - root.total(parent.s.models[a]) })
              : []
            delegate: Row {
              width: content.width
              Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: root.colorFor(modelData) }
              Item { width: Style.spacing.sm; height: 1 }
              Text {
                width: parent.width * 0.6
                text: root.shortModel(modelData)
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.family
                font.pixelSize: Style.font.subtitle
              }
              Text {
                width: parent.width * 0.4 - 8 - Style.spacing.sm
                text: root.fmt(root.total(sessionCol.s.models[modelData]))
                color: root.foreground
                horizontalAlignment: Text.AlignRight
                font.family: root.family
                font.pixelSize: Style.font.subtitle
              }
            }
          }

          Text {
            visible: root.weekly() !== null
            text: root.weekly() ? "Weekly limit: " + Math.round(root.weekly().percent * (root.weekly().percent <= 1 ? 100 : 1))
              + "%  ·  resets " + Qt.formatDateTime(new Date(root.weekly().resetsAt), "ddd HH:mm") : ""
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.body
          }
        }

        // History
        Column {
          width: parent.width
          spacing: 2
          Text {
            text: "HISTORY BY DAY (last " + root.historyDays + " days)"
            font.letterSpacing: 0.6
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Item { width: 1; height: Style.spacing.sm }
          Repeater {
            model: root.dayList.slice().reverse()
            delegate: Row {
              width: content.width
              spacing: Style.spacing.sm
              readonly property var models: root.stats.days[modelData]
              Text {
                width: Style.space(44)
                text: Qt.formatDate(new Date(modelData + "T12:00:00"), "dd MMM")
                color: root.dim
                font.family: root.family
                font.pixelSize: Style.font.body
              }
              Item {
                width: parent.width - Style.space(44) - Style.space(60) - 2 * Style.spacing.sm
                height: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { anchors.fill: parent; radius: 2; color: Util.alpha(root.foreground, 0.16) }
                Row {
                  height: parent.height
                  width: parent.width * root.sumModels(models) / root.maxDay
                  Repeater {
                    model: Object.keys(models)
                    delegate: Rectangle {
                      height: parent.height
                      width: root.sumModels(models) > 0
                        ? parent.width * root.total(models[modelData]) / root.sumModels(models) : 0
                      color: root.colorFor(modelData)
                    }
                  }
                }
              }
              Text {
                width: Style.space(60)
                text: root.fmt(root.sumModels(models))
                color: root.foreground
                horizontalAlignment: Text.AlignRight
                font.family: root.family
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        // Totals per model over the window
        Column {
          width: parent.width
          spacing: 2
          Text {
            text: "TOTAL PER MODEL"
            font.letterSpacing: 0.6
            color: root.dim
            font.family: root.family
            font.pixelSize: Style.font.body
          }
          Repeater {
            model: root.modelList
            delegate: Row {
              width: content.width
              readonly property real sum: {
                var s = 0
                for (var d in root.stats.days)
                  if (root.stats.days[d][modelData]) s += root.total(root.stats.days[d][modelData])
                return s
              }
              Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: root.colorFor(modelData) }
              Item { width: Style.spacing.sm; height: 1 }
              Text {
                width: parent.width * 0.6
                text: root.shortModel(modelData)
                color: root.foreground
                elide: Text.ElideRight
                font.family: root.family
                font.pixelSize: Style.font.subtitle
              }
              Text {
                width: parent.width * 0.4 - 8 - Style.spacing.sm
                text: root.fmt(sum)
                color: root.foreground
                horizontalAlignment: Text.AlignRight
                font.family: root.family
                font.pixelSize: Style.font.subtitle
              }
            }
          }
        }
      }
    }
  }
}
