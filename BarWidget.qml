import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import qs.Services.System

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property bool backendReady: mainInstance?.backendReady || false
  readonly property int messageCount: mainInstance?.messages?.length || 0
  readonly property string resolvedModel: mainInstance?.resolvedModel || ""

  readonly property string screenName: screen ? screen.name : ""
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real contentWidth: capsuleHeight
  readonly property real contentHeight: capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  Rectangle {
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    radius: Style.radiusL
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    Item {
      id: iconWidget
      anchors.centerIn: parent
      width: Style.fontSizeL * 1.3
      height: width

      Image {
        anchors.fill: parent
        visible: !root.isGenerating
        source: Qt.resolvedUrl("assets/pi-favicon.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        opacity: root.backendReady ? 1.0 : 0.6
      }

      NIcon {
        anchors.centerIn: parent
        visible: root.isGenerating
        icon: "loader-2"
        color: root.backendReady ? Color.mOnSurface : Color.mOnSurfaceVariant
        applyUiScale: false

        RotationAnimation on rotation {
          running: root.isGenerating
          from: 0
          to: 360
          duration: 1000
          loops: Animation.Infinite
        }
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onEntered: TooltipService.show(root, buildTooltip(), BarService.getTooltipDirection())
    onExited: TooltipService.hide()

    onClicked: function (mouse) {
      if (mouse.button === Qt.LeftButton) {
        if (mainInstance?.openPreferredUI)
          mainInstance.openPreferredUI(root.screen, root);
        else
          pluginApi?.openPanel(root.screen, root);
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen);
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("menu.openPanel"),
        "action": "open",
        "icon": "external-link"
      },
      {
        "label": pluginApi?.tr("menu.clearHistory"),
        "action": "clear",
        "icon": "trash"
      },
      {
        "label": pluginApi?.tr("menu.settings"),
        "action": "settings",
        "icon": "settings"
      }
    ]

    onTriggered: function (action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "open") {
        if (mainInstance?.openPreferredUI)
          mainInstance.openPreferredUI(root.screen, root);
        else
          pluginApi?.openPanel(root.screen, root);
      } else if (action === "clear") {
        mainInstance?.clearMessages();
      } else if (action === "settings") {
        BarService.openPluginSettings(screen, pluginApi.manifest);
      }
    }
  }

  function buildTooltip() {
    var tooltip = pluginApi?.tr("widget.tooltipTitle") || "Pi Assistant";
    tooltip += "\n" + ((backendReady ? pluginApi?.tr("chat.backendReady") : pluginApi?.tr("chat.backendNotReady")) || "");
    if (resolvedModel)
      tooltip += "\n" + (pluginApi?.tr("widget.model") || "Model") + ": " + resolvedModel;
    if (messageCount > 0)
      tooltip += "\n" + (pluginApi?.tr("widget.messages") || "Messages") + ": " + messageCount;
    if (isGenerating)
      tooltip += "\n...";
    tooltip += "\n\n" + (pluginApi?.tr("widget.rightClickHint") || "Right-click for options");
    return tooltip;
  }
}
