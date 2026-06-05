import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property string editPiCommand: pluginApi?.pluginSettings?.ai?.piCommand || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.piCommand || "pi"
  property string editModel: pluginApi?.pluginSettings?.ai?.model || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.model || ""
  property string editThinkingLevel: pluginApi?.pluginSettings?.ai?.thinkingLevel || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.thinkingLevel || "medium"
  property string editToolsMode: pluginApi?.pluginSettings?.ai?.toolsMode || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.toolsMode || "none"
  property bool editPersistentSession: pluginApi?.pluginSettings?.ai?.persistentSession ?? pluginApi?.manifest?.metadata?.defaultSettings?.ai?.persistentSession ?? false
  property string editSessionName: pluginApi?.pluginSettings?.ai?.sessionName || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.sessionName || "Noctalia Pi Assistant"

  property int editPanelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property real editPanelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio || 0.85
  property bool editPanelDetached: pluginApi?.pluginSettings?.panelDetached ?? true
  property string editPanelPosition: pluginApi?.pluginSettings?.panelPosition || "right"
  property string editAttachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || "connected"
  property real editScale: pluginApi?.pluginSettings?.scale || 1
  property bool editPanelPinned: pluginApi?.pluginSettings?.panelPinned ?? false

  spacing: Style.marginM

  NText {
    text: pluginApi?.tr("settings.aiSection")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.piCommand")
    description: pluginApi?.tr("settings.piCommandDesc")
    text: root.editPiCommand
    placeholderText: "pi"
    onTextChanged: root.editPiCommand = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.model")
    description: pluginApi?.tr("settings.modelDesc")
    text: root.editModel
    placeholderText: pluginApi?.tr("settings.modelPlaceholder")
    onTextChanged: root.editModel = text
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.thinkingLevel")
    description: pluginApi?.tr("settings.thinkingLevelDesc")
    model: [
      { "key": "off", "name": "off" },
      { "key": "minimal", "name": "minimal" },
      { "key": "low", "name": "low" },
      { "key": "medium", "name": "medium" },
      { "key": "high", "name": "high" },
      { "key": "xhigh", "name": "xhigh" }
    ]
    currentKey: root.editThinkingLevel
    onSelected: function (key) {
      root.editThinkingLevel = key;
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.toolsMode")
    description: pluginApi?.tr("settings.toolsModeDesc")
    model: [
      { "key": "none", "name": pluginApi?.tr("settings.toolsNone") },
      { "key": "readonly", "name": pluginApi?.tr("settings.toolsReadonly") },
      { "key": "full", "name": pluginApi?.tr("settings.toolsFull") }
    ]
    currentKey: root.editToolsMode
    onSelected: function (key) {
      root.editToolsMode = key;
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.persistentSession")
    description: pluginApi?.tr("settings.persistentSessionDesc")
    checked: root.editPersistentSession
    onToggled: function (checked) {
      root.editPersistentSession = checked;
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.sessionName")
    description: pluginApi?.tr("settings.sessionNameDesc")
    text: root.editSessionName
    placeholderText: "Noctalia Pi Assistant"
    onTextChanged: root.editSessionName = text
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NText {
    text: pluginApi?.tr("settings.panelSection")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelDetached")
    description: pluginApi?.tr("settings.panelDetachedDesc")
    checked: root.editPanelDetached
    onToggled: function (checked) {
      root.editPanelDetached = checked;
      if (checked) {
        if (root.editPanelPosition === "top" || root.editPanelPosition === "bottom")
          root.editPanelPosition = "right";
      } else if (root.editPanelPosition === "center") {
        root.editPanelPosition = "right";
      }
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelPinned")
    description: pluginApi?.tr("settings.panelPinnedDesc")
    checked: root.editPanelPinned
    onToggled: function (checked) {
      root.editPanelPinned = checked;
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelPosition")
    description: pluginApi?.tr("settings.panelPositionDesc")
    model: root.editPanelDetached ? [
      { "key": "left", "name": pluginApi?.tr("settings.panelPositionLeft") },
      { "key": "center", "name": pluginApi?.tr("settings.panelPositionCenter") },
      { "key": "right", "name": pluginApi?.tr("settings.panelPositionRight") }
    ] : [
      { "key": "left", "name": pluginApi?.tr("settings.panelPositionLeft") },
      { "key": "top", "name": pluginApi?.tr("settings.panelPositionTop") },
      { "key": "bottom", "name": pluginApi?.tr("settings.panelPositionBottom") },
      { "key": "right", "name": pluginApi?.tr("settings.panelPositionRight") }
    ]
    currentKey: root.editPanelPosition
    onSelected: function (key) {
      root.editPanelPosition = key;
    }
  }

  NComboBox {
    Layout.fillWidth: true
    visible: !root.editPanelDetached
    label: pluginApi?.tr("settings.attachmentStyle")
    description: pluginApi?.tr("settings.attachmentStyleDesc")
    model: [
      { "key": "connected", "name": pluginApi?.tr("settings.attachConnected") },
      { "key": "floating", "name": pluginApi?.tr("settings.attachFloating") }
    ]
    currentKey: root.editAttachmentStyle
    onSelected: function (key) {
      root.editAttachmentStyle = key;
    }
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: pluginApi?.tr("settings.panelHeightRatio") + ": " + (root.editPanelHeightRatio * 100).toFixed(0) + "%"
      description: pluginApi?.tr("settings.panelHeightRatioDesc")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0.3
      to: 1.0
      stepSize: 0.01
      value: root.editPanelHeightRatio
      onValueChanged: root.editPanelHeightRatio = value
    }

    NLabel {
      label: pluginApi?.tr("settings.panelWidth") + ": " + root.editPanelWidth + "px"
      description: pluginApi?.tr("settings.panelWidthDesc")
    }

    NSlider {
      Layout.fillWidth: true
      from: 320
      to: 1200
      stepSize: 1
      value: root.editPanelWidth
      onValueChanged: root.editPanelWidth = value
    }

    NLabel {
      label: pluginApi?.tr("settings.uiScale") + ": " + (root.editScale * 100).toFixed(0) + "%"
      description: pluginApi?.tr("settings.uiScaleDesc")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0.5
      to: 2.0
      stepSize: 0.01
      value: root.editScale
      onValueChanged: root.editScale = value
    }
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    if (!pluginApi.pluginSettings.ai)
      pluginApi.pluginSettings.ai = {};

    pluginApi.pluginSettings.ai.piCommand = root.editPiCommand.trim() || "pi";
    pluginApi.pluginSettings.ai.model = root.editModel.trim();
    pluginApi.pluginSettings.ai.thinkingLevel = root.editThinkingLevel;
    pluginApi.pluginSettings.ai.toolsMode = root.editToolsMode;
    pluginApi.pluginSettings.ai.persistentSession = root.editPersistentSession;
    pluginApi.pluginSettings.ai.sessionName = root.editSessionName.trim() || "Noctalia Pi Assistant";

    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPinned = root.editPanelPinned;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;
    pluginApi.pluginSettings.attachmentStyle = root.editAttachmentStyle;
    pluginApi.pluginSettings.scale = root.editScale;

    pluginApi.saveSettings();
    pluginApi.mainInstance?.restartBackend();
  }
}
