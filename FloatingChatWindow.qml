import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
  id: root

  required property ShellScreen screen
  property var pluginApi: null
  property var mainInstance: null

  color: "transparent"
  visible: true

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "noctalia-pi-assistant-standalone-" + (screen?.name || "unknown")

  anchors.top: true
  anchors.left: true
  anchors.right: true
  anchors.bottom: true

  readonly property int panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  readonly property real panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? 0.85
  readonly property string panelPosition: (pluginApi?.pluginSettings?.panelPosition ?? "right")
  readonly property real uiScale: pluginApi?.pluginSettings?.scale ?? 1
  readonly property real contentWidth: panelWidth
  readonly property real contentHeight: screen ? (screen.height * panelHeightRatio) : 620 * Style.uiScaleRatio
  readonly property real panelX: {
    const margin = Style.marginL * 2;
    if (!screen)
      return margin;
    if (panelPosition === "left")
      return margin;
    if (panelPosition === "center")
      return Math.round((screen.width - contentWidth) / 2);
    if (panelPosition === "top" || panelPosition === "bottom")
      return Math.round((screen.width - contentWidth) / 2);
    return Math.round(screen.width - contentWidth - margin);
  }
  readonly property real panelY: {
    const margin = Style.marginL * 2;
    if (!screen)
      return margin;
    if (panelPosition === "top")
      return margin;
    if (panelPosition === "bottom")
      return Math.round(screen.height - contentHeight - margin);
    return Math.round((screen.height - contentHeight) / 2);
  }

  mask: Region {
    x: 0
    y: 0
    width: root.width
    height: root.height
    intersection: Intersection.Xor

    Region {
      x: root.panelX
      y: root.panelY
      width: root.contentWidth
      height: root.contentHeight
      intersection: Intersection.Subtract
      radius: Style.radiusL
    }
  }

  Rectangle {
    x: root.panelX
    y: root.panelY
    width: root.contentWidth
    height: root.contentHeight
    radius: Style.radiusL
    color: Color.mSurfaceVariant
    clip: true

    Item {
      anchors.fill: parent
      property real s: root.uiScale

      Item {
        width: parent.width / (parent.s || 1)
        height: parent.height / (parent.s || 1)
        scale: parent.s || 1
        anchors.centerIn: parent
        transformOrigin: Item.Center

        ChatView {
          anchors.fill: parent
          anchors.margins: Style.marginM
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
      }
    }
  }
}
