import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "cossssmin.xkcd"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property real openPanelIndicatorWidth: logo.implicitWidth

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

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

  FontLoader {
    id: xkcdFont
    source: Qt.resolvedUrl("xkcd-script.ttf")
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: logo.implicitWidth + scaledHorizontalMargin * 2
    tooltipText: "browse xkcd comics"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Item {
      id: logo
      anchors.centerIn: parent
      // The handwriting glyphs paint past their advance widths, so size and
      // place the rows by tight ink bounds or the slot padding comes out
      // lopsided next to the glyph-icon widgets.
      implicitWidth: Math.max(xkM.tightBoundingRect.width, logo.stagger + cdM.tightBoundingRect.width)
      implicitHeight: cdRow.y + cdRow.implicitHeight
      width: implicitWidth
      height: implicitHeight

      readonly property color inkColor: button.active && button.useActiveColor ? button.activeColor : button.foreground
      readonly property string inkFamily: xkcdFont.status === FontLoader.Ready ? xkcdFont.name : button.fontFamily
      readonly property int inkSize: Style.fontPx(0.92)
      readonly property real stagger: Math.round(xkM.tightBoundingRect.width * 0.2)

      TextMetrics { id: xkM; text: "xk"; font: xkRow.font }
      TextMetrics { id: cdM; text: "cd"; font: cdRow.font }

      Text {
        id: xkRow
        x: -xkM.tightBoundingRect.x
        text: "xk"
        color: logo.inkColor
        font.family: logo.inkFamily
        font.pixelSize: logo.inkSize
        renderType: Text.NativeRendering
      }

      Text {
        id: cdRow
        x: logo.stagger - cdM.tightBoundingRect.x
        y: Math.round(xkRow.implicitHeight * 0.5)
        text: "cd"
        color: logo.inkColor
        font.family: logo.inkFamily
        font.pixelSize: logo.inkSize
        renderType: Text.NativeRendering
      }
    }
  }
}
