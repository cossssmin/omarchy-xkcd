import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// The popup body. Top block (header, search field, status, comic preview) is
// fixed and never scrolls, so the previewed comic stays put. Search matches
// live in their own scrollable, fixed-height list below, navigated with the
// arrow keys. The image sits in a constant-height frame so switching comics
// never resizes the popup.
Column {
  id: view

  required property var engine
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  property int selectedIndex: 0

  readonly property real rowH: Style.space(32)
  readonly property real rowSpacing: Style.space(2)
  readonly property real imageBoxH: Style.space(220)
  readonly property real altBoxH: Style.space(50)
  readonly property real listBoxH: Style.space(224)
  readonly property var months: ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                 "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  readonly property bool searching: view.engine.mode === "search" && view.engine.results.length > 1
  readonly property bool listOverflows: view.engine.results.length * (rowH + rowSpacing) > listBoxH

  spacing: Style.space(10)

  function comicDate(c) {
    if (!c) return ""
    var m = parseInt(c.month, 10)
    var name = (m >= 1 && m <= 12) ? view.months[m] : ""
    return name + " " + parseInt(c.day, 10) + ", " + c.year
  }

  function focusInput() {
    input.selectAll()
    input.forceActiveFocus()
  }

  function runInput() {
    debounce.stop()
    view.selectedIndex = 0
    view.engine.run(input.text)
  }

  function moveSelection(delta) {
    if (!view.searching) return
    var n = view.engine.results.length
    view.selectedIndex = Math.max(0, Math.min(n - 1, view.selectedIndex + delta))
    view.engine.select(view.selectedIndex)
    view.ensureVisible(view.selectedIndex)
  }

  function openCurrent() {
    if (view.engine.current) view.engine.openComic(view.engine.current)
  }

  // Scroll only the results list — the preview above it is outside the scroll.
  function ensureVisible(i) {
    var flick = listScroll.contentItem
    if (!flick || flick.contentY === undefined) return
    var y = i * (view.rowH + view.rowSpacing)
    var b = y + view.rowH
    if (y < flick.contentY) flick.contentY = Math.max(0, y - Style.space(4))
    else if (b > flick.contentY + flick.height) flick.contentY = b - flick.height + Style.space(4)
  }

  Timer { id: debounce; interval: 200; onTriggered: view.runInput() }

  Connections {
    target: view.engine
    function onResultsChanged() {
      view.selectedIndex = 0
      if (listScroll.contentItem) listScroll.contentItem.contentY = 0
    }
  }

  // ---------- Header ----------
  Item {
    width: parent.width
    height: Math.max(glyph.height, headerText.implicitHeight)

    Item {
      id: glyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(xkM.tightBoundingRect.width, glyph.stagger + cdM.tightBoundingRect.width)
      height: cdRow.y + cdRow.implicitHeight

      readonly property string inkFamily: xkcdFont.status === FontLoader.Ready ? xkcdFont.name : view.fontFamily
      readonly property int inkSize: Style.fontPx(1.5)
      readonly property real stagger: Math.round(xkM.tightBoundingRect.width * 0.2)

      FontLoader { id: xkcdFont; source: Qt.resolvedUrl("xkcd-script.ttf") }
      TextMetrics { id: xkM; text: "xk"; font: xkRow.font }
      TextMetrics { id: cdM; text: "cd"; font: cdRow.font }

      Text {
        id: xkRow
        x: -xkM.tightBoundingRect.x
        text: "xk"
        color: Color.accent
        font.family: glyph.inkFamily
        font.pixelSize: glyph.inkSize
        renderType: Text.NativeRendering
      }

      Text {
        id: cdRow
        x: glyph.stagger - cdM.tightBoundingRect.x
        y: Math.round(xkRow.implicitHeight * 0.5)
        text: "cd"
        color: Color.accent
        font.family: glyph.inkFamily
        font.pixelSize: glyph.inkSize
        renderType: Text.NativeRendering
      }
    }

    Column {
      id: headerText
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(12)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        text: "Omaxkcd"
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: "Browse xkcd comics"
        color: Util.alpha(view.foreground, 0.64)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // ---------- Search field ----------
  TextField {
    id: input
    width: parent.width
    focus: true
    placeholderText: "comic title, number, excerpt..."
    foreground: view.foreground
    font.family: view.fontFamily
    onTextChanged: debounce.restart()
    onAccepted: view.openCurrent()
  }

  // ---------- Status line ----------
  Text {
    width: parent.width
    visible: text !== ""
    elide: Text.ElideRight
    text: {
      if (view.engine.loading) return "Loading…"
      if (view.engine.error !== "") return view.engine.error
      if (view.engine.mode === "search")
        return view.engine.results.length + " result" + (view.engine.results.length === 1 ? "" : "s")
      if (view.engine.mode === "latest") return "Latest comic"
      return ""
    }
    color: view.engine.error !== "" ? Color.urgent : Util.alpha(view.foreground, 0.6)
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  // ---------- Comic preview (fixed, never scrolls) ----------
  Column {
    id: preview
    width: parent.width
    spacing: Style.space(6)
    visible: view.engine.current !== null

    readonly property var c: view.engine.current

    // Title (links to xkcd.com, underlines on hover) + copy-image control.
    Item {
      width: parent.width
      height: Math.max(titleText.implicitHeight, copyBtn.implicitHeight)

      Text {
        id: titleText
        anchors.left: parent.left
        anchors.right: copyBtn.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        text: preview.c ? ("#" + preview.c.num + " · " + preview.c.title) : ""
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        font.underline: titleHover.containsMouse

        MouseArea {
          id: titleHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.engine.openComic(preview.c)
        }
      }

      Text {
        id: copyBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: {
          switch (view.engine.copyStatus) {
          case "copying": return "copying…"
          case "done": return "copied ✓"
          case "error": return "copy failed"
          default: return "copy image"
          }
        }
        color: view.engine.copyStatus === "done" ? Color.accent
             : view.engine.copyStatus === "error" ? Color.urgent
             : copyHover.containsMouse ? Color.accent : Util.alpha(view.foreground, 0.6)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.underline: copyHover.containsMouse && view.engine.copyStatus === ""

        MouseArea {
          id: copyHover
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: view.engine.copyImage(preview.c)
        }
      }
    }

    Text {
      width: parent.width
      text: view.comicDate(preview.c)
      color: Util.alpha(view.foreground, 0.55)
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }

    // Constant-height frame: the image scales inside it, so swapping comics
    // never changes the popup's size and the layout never jumps.
    Rectangle {
      width: parent.width
      height: view.imageBoxH
      radius: Style.cornerRadius
      color: "#ffffff"

      Image {
        id: img
        anchors.fill: parent
        anchors.margins: Style.space(6)
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
        source: preview.c && preview.c.img ? preview.c.img : ""
        sourceSize.width: 1024
        asynchronous: true
        cache: true
        // Fade the new comic in once decoded, instead of a hard swap.
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
      }

      Text {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        text: img.status === Image.Error ? "image unavailable" : "…"
        color: "#888888"
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: view.engine.openComic(preview.c)
      }
    }

    // The alt text (the hidden joke), in a fixed-height slot so its length
    // doesn't shift the layout either.
    Item {
      width: parent.width
      height: view.altBoxH

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: preview.c ? preview.c.alt : ""
        color: Util.alpha(view.foreground, 0.75)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.italic: true
      }
    }
  }

  // ---------- Search results (own scroll area, fixed height) ----------
  Column {
    width: parent.width
    spacing: Style.space(4)
    visible: view.searching

    ScrollView {
      id: listScroll
      width: parent.width
      height: view.listBoxH
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: view.listOverflows ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

      Column {
        id: resultsCol
        width: listScroll.availableWidth
        spacing: view.rowSpacing

        Repeater {
          model: view.engine.results

          Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool hot: rowMouse.containsMouse || view.selectedIndex === index

            width: resultsCol.width
            height: view.rowH
            radius: Style.cornerRadius
            color: hot ? Util.alpha(view.foreground, 0.10) : "transparent"

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(40)
              text: "#" + row.modelData.num
              color: Util.alpha(view.foreground, 0.55)
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(50)
              anchors.right: yearText.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              text: row.modelData.title
              color: view.foreground
              font.family: view.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              id: yearText
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.year
              color: Util.alpha(view.foreground, 0.4)
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                view.selectedIndex = row.index
                view.engine.select(row.index)
              }
              onDoubleClicked: view.engine.openComic(row.modelData)
            }
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: view.listOverflows
      horizontalAlignment: Text.AlignHCenter
      text: "↓ scroll for more"
      color: Util.alpha(view.foreground, 0.4)
      font.family: view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
