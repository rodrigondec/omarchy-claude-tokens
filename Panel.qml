import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Claude token usage: current 5-hour session (consumption + reset countdown)
// and a per-day, per-model history. The collector runs only while the panel is open.
Panel {
  id: root

  moduleName: "io.github.rodrigondec.claude-tokens"
  ipcTarget: "io.github.rodrigondec.claude-tokens"

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
  // Fixed colour per model family (Okabe-Ito based, colour-blind safe, all
  // >= 6:1 on dark backgrounds) so a model keeps its colour across days.
  readonly property var familyColors: ({
    "sonnet": "#6f9fd0",
    "opus": "#e69f00",
    "haiku": "#1fb589",
    "fable": "#d983b6"
  })
  readonly property var extraColors: ["#f0e442", "#9aa0b4"]

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
    var name = String(model).toLowerCase()
    for (var family in familyColors)
      if (name.indexOf(family) >= 0) return familyColors[family]
    var others = modelList.filter(function(m) {
      var n = String(m).toLowerCase()
      for (var f in familyColors) if (n.indexOf(f) >= 0) return false
      return true
    })
    var i = others.indexOf(model)
    return extraColors[Math.min(i < 0 ? 0 : i, extraColors.length - 1)]
  }


  function countdown(sec) {
    sec = Math.max(0, Math.floor(sec))
    var d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    return h > 0 ? h + "h " + m + "m" : m + "m"
  }

  function weekly() {
    if (!stats || !stats.limits) return null
    for (var i = 0; i < stats.limits.length; i++)
      if (String(stats.limits[i].label).indexOf("Weekly") === 0 && String(stats.limits[i].label).indexOf("Fable") < 0)
        return stats.limits[i]
    return null
  }

  // Starts the default coding agent in a terminal (same command the built-in
  // Agents panel uses); offers to pick one if none is set.
  function openAgent() {
    if (bar) bar.run("omarchy-agent --pick")
    close()
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
    text: "󰚩"
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
        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, headerRight.implicitHeight)

          Text {
            id: title
            anchors.verticalCenter: parent.verticalCenter
            text: "CLAUDE TOKENS"
            font.letterSpacing: 0.6
            color: root.accent
            font.family: root.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Row {
            id: headerRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.lg

            Rectangle {
              id: agentButton
              anchors.verticalCenter: parent.verticalCenter
              width: agentLabel.implicitWidth + Style.space(16)
              height: agentLabel.implicitHeight + Style.space(6)
              radius: Style.cornerRadius
              color: agentArea.containsMouse ? Util.alpha(root.accent, 0.25) : Util.alpha(root.foreground, 0.16)
              border.width: 1
              border.color: Util.alpha(root.accent, 0.5)
              Text {
                id: agentLabel
                anchors.centerIn: parent
                text: "open agent"
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.family
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: agentArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAgent()
              }
            }

            KeyHint {
              id: hint
              anchors.verticalCenter: parent.verticalCenter
              keyName: "c"
              label: root.withCache ? "hide cache reads" : "show cache reads"
              textColor: root.foreground
              fontFamily: root.family
              onActivated: root.withCache = !root.withCache
            }
          }
        }

        // Current session
        Column {
          id: sessionCol
          width: parent.width
          spacing: Style.spacing.sm
          readonly property var s: root.stats ? root.stats.session : null

          Item {
            width: parent.width
            height: sessTotal.implicitHeight
            Text {
              text: "CURRENT SESSION (5h)"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.body
              font.letterSpacing: 0.6
            }
            Text {
              id: sessTotal
              anchors.right: parent.right
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

        }

        // Weekly limit
        Column {
          id: weeklyCol
          width: parent.width
          spacing: Style.spacing.sm
          visible: weeklyCol.w !== null
          readonly property var w: root.weekly()
          readonly property real pct: w ? Math.max(0, Math.min(1, Number(w.percent) || 0)) : 0
          readonly property real endSec: w && w.resetsAt ? new Date(w.resetsAt).getTime() / 1000 : 0
          readonly property color level: pct >= 0.85 ? Color.urgent : (pct >= 0.6 ? "#e0a030" : root.accent)

          Item {
            width: parent.width
            height: weeklyPct.implicitHeight
            Text {
              text: "WEEKLY LIMIT (7d)"
              color: root.dim
              font.family: root.family
              font.pixelSize: Style.font.body
              font.letterSpacing: 0.6
            }
            Text {
              id: weeklyPct
              anchors.right: parent.right
              text: Math.round(weeklyCol.pct * 100) + "%"
              color: weeklyCol.level
              font.family: root.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          Item {
            width: parent.width
            height: Style.space(8)
            Rectangle { anchors.fill: parent; radius: 3; color: Util.alpha(root.foreground, 0.16) }
            Rectangle {
              width: parent.width * weeklyCol.pct
              height: parent.height
              radius: 3
              color: weeklyCol.level
            }
          }

          Text {
            visible: weeklyCol.endSec > 0
            text: weeklyCol.endSec > 0
              ? "Resets in " + root.countdown(weeklyCol.endSec - root.nowSec) + " ("
                + Qt.formatDateTime(new Date(weeklyCol.endSec * 1000), "ddd HH:mm") + ")"
              : ""
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
                      // 1px gap so neighbouring segments don't blur together.
                      Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: Color.popups.background
                        visible: index < Object.keys(models).length - 1 && parent.width > 2
                      }
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
