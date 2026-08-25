import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "cossssmin.xkcd"
  ipcTarget: "cossssmin.xkcd"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  onOpenedChanged: if (root.opened) view.focusInput()

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Xkcd { id: engine }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyScope
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(view.implicitHeight)

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        else if (event.key === Qt.Key_Tab) { root.switchPanel(1); event.accepted = true }
        else if (event.key === Qt.Key_Backtab) { root.switchPanel(-1); event.accepted = true }
        else if (event.key === Qt.Key_Down) { view.moveSelection(1); event.accepted = true }
        else if (event.key === Qt.Key_Up) { view.moveSelection(-1); event.accepted = true }
      }

      XkcdView {
        id: view
        width: parent.width
        engine: engine
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
      }
    }
  }
}
