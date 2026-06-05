import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null
  property string lightboxSource: ""

  readonly property var messages: mainInstance?.messages || []
  readonly property bool isGenerating: mainInstance?.isGenerating || false
  readonly property string currentResponse: mainInstance?.currentResponse || ""
  readonly property string currentThinking: mainInstance?.currentThinking || ""
  readonly property var currentToolEvents: mainInstance?.currentToolEvents || []
  readonly property string errorMessage: mainInstance?.errorMessage || ""
  readonly property string model: mainInstance?.resolvedModel || ""
  readonly property string activeThinkingLevel: mainInstance?.backendThinkingLevel || mainInstance?.thinkingLevel || "medium"
  property int slashSelectionIndex: 0

  readonly property string backendStateLabel: mainInstance?.backendReady ? pluginApi?.tr("chat.backendReady") : pluginApi?.tr("chat.backendNotReady")
  readonly property string inputStatusLabel: mainInstance?.modelStatusLine || backendStateLabel
  readonly property var modelOptions: {
    const options = mainInstance?.availableModels || [];
    if (options.length > 0)
      return options;
    if (model)
      return [{ "key": model, "name": model }];
    return [];
  }
  readonly property var thinkingOptions: [
    { "key": "off", "name": "off" },
    { "key": "minimal", "name": "minimal" },
    { "key": "low", "name": "low" },
    { "key": "medium", "name": "medium" },
    { "key": "high", "name": "high" },
    { "key": "xhigh", "name": "xhigh" }
  ]
  readonly property var slashQuery: getSlashQuery(inputField?.text || "")
  readonly property var slashCommandOptions: filterSlashCommands(slashQuery)
  readonly property bool slashPopupVisible: (slashQuery !== null) && inputField?.activeFocus && !isGenerating && (mainInstance?.backendReady ?? false)

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Image {
        Layout.preferredWidth: Style.fontSizeL * 1.2
        Layout.preferredHeight: Layout.preferredWidth
        source: Qt.resolvedUrl("assets/pi-favicon.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          ComboBox {
            id: modelSelector
            Layout.fillWidth: true
            model: root.modelOptions
            textRole: "name"
            enabled: (mainInstance?.backendReady ?? false) && !isGenerating && !(mainInstance?.modelChangeInProgress ?? false) && ((mainInstance?.availableModels?.length || 0) > 0)
            currentIndex: root.modelIndexForKey(root.model)
            font.pointSize: Math.max(1, Style.fontSizeXS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)

            onActivated: function (index) {
              const entry = root.modelOptions[index];
              if (entry?.key && entry.key !== root.model)
                mainInstance?.setActiveModel(entry.key);
            }
          }

          ComboBox {
            id: thinkingSelector
            Layout.preferredWidth: 110 * Style.uiScaleRatio
            model: root.thinkingOptions
            textRole: "name"
            enabled: (mainInstance?.backendReady ?? false) && !isGenerating
            currentIndex: root.thinkingIndexForKey(root.activeThinkingLevel)
            font.pointSize: Math.max(1, Style.fontSizeXS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)

            onActivated: function (index) {
              const entry = root.thinkingOptions[index];
              if (entry?.key && entry.key !== root.activeThinkingLevel)
                mainInstance?.setActiveThinkingLevel(entry.key);
            }
          }
        }

      }

      NIconButton {
        icon: (mainInstance?.panelPinned ?? false) ? "pinned" : "pin"
        colorFg: (mainInstance?.panelPinned ?? false) ? Color.mPrimary : Color.mOnSurfaceVariant
        tooltipText: (mainInstance?.panelPinned ?? false) ? (pluginApi?.tr("chat.unpinPanel") || "Unpin panel") : (pluginApi?.tr("chat.pinPanel") || "Pin panel")
        onClicked: mainInstance?.togglePanelPinned()
      }

      NIcon {
        icon: "loader-2"
        visible: isGenerating
        color: Color.mPrimary
        pointSize: Style.fontSizeS
        applyUiScale: false

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 1000
          loops: Animation.Infinite
          running: isGenerating
        }
      }

    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: Color.mSurface
      radius: Style.radiusM
      clip: true

      Item {
        anchors.fill: parent
        visible: messages.length === 0 && !isGenerating

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          Image {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Style.fontSizeXXL * 2.4
            Layout.preferredHeight: Layout.preferredWidth
            source: Qt.resolvedUrl("assets/pi-favicon.svg")
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.8
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("chat.emptyTitle")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            applyUiScale: false
            font.weight: Font.Medium
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: pluginApi?.tr("chat.emptyHint")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            applyUiScale: false
          }
        }
      }

      Flickable {
        id: chatFlickable
        anchors.fill: parent
        anchors.margins: Style.marginS
        contentWidth: width
        contentHeight: messageColumn.height
        clip: true
        visible: messages.length > 0 || isGenerating
        boundsBehavior: Flickable.StopAtBounds

        property real wheelScrollMultiplier: 4.0
        property bool autoScrollEnabled: true
        readonly property bool isNearBottom: {
          if (contentHeight <= height)
            return true;
          return contentY >= contentHeight - height - 30;
        }

        function scrollToBottom() {
          if (contentHeight > height)
            contentY = contentHeight - height;
        }

        onContentHeightChanged: {
          if (autoScrollEnabled && contentHeight > height)
            scrollToBottom();
        }
        onMovementEnded: autoScrollEnabled = isNearBottom
        onFlickEnded: autoScrollEnabled = isNearBottom

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
            const newY = chatFlickable.contentY - (delta * chatFlickable.wheelScrollMultiplier);
            chatFlickable.contentY = Math.max(0, Math.min(newY, chatFlickable.contentHeight - chatFlickable.height));
            chatFlickable.autoScrollEnabled = chatFlickable.isNearBottom;
            event.accepted = true;
          }
        }

        Column {
          id: messageColumn
          width: chatFlickable.width
          spacing: Style.marginM

          Repeater {
            model: messages
            MessageBubble {
              width: messageColumn.width
              message: modelData
              pluginApi: root.pluginApi
              onCopyRequested: function (text) {
                Quickshell.clipboardText = text;
                ToastService.showNotice(pluginApi?.tr("toast.copied"));
              }
              onImageOpenRequested: function (source) {
                root.lightboxSource = source || "";
              }
            }
          }

          MessageBubble {
            width: messageColumn.width
            visible: isGenerating && currentResponse.trim() !== ""
            pluginApi: root.pluginApi
            onImageOpenRequested: function (source) {
              root.lightboxSource = source || "";
            }
            message: ({
                "id": "streaming",
                "role": "assistant",
                "content": currentResponse,
                "isStreaming": true
              })
          }
        }
      }

      Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.marginM
        width: 32
        height: 32
        radius: width / 2
        color: Color.mPrimary
        visible: !chatFlickable.autoScrollEnabled && messages.length > 0
        opacity: scrollButtonMouse.containsMouse ? 1.0 : 0.8

        Behavior on opacity {
          NumberAnimation { duration: Style.animationFast }
        }

        NIcon {
          anchors.centerIn: parent
          icon: "chevron-down"
          color: Color.mOnPrimary
          pointSize: Style.fontSizeM
          applyUiScale: false
        }

        MouseArea {
          id: scrollButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            chatFlickable.autoScrollEnabled = true;
            chatFlickable.scrollToBottom();
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      visible: isGenerating && (currentThinking !== "" || currentToolEvents.length > 0)
      color: Qt.alpha(Color.mSurfaceVariant, 0.6)
      radius: Style.radiusM
      implicitHeight: transientPanelsContent.implicitHeight + Style.marginS * 2

      Column {
        id: transientPanelsContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.marginS
        spacing: Style.marginS

        Rectangle {
          id: thinkingPanel
          width: transientPanelsContent.width
          visible: currentThinking !== ""
          radius: Style.radiusS
          color: Qt.alpha(Color.mSurface, 0.8)
          border.color: Qt.alpha(Color.mOnSurfaceVariant, 0.15)
          border.width: 1
          implicitHeight: thinkingHeaderRow.height + ((mainInstance?.thinkingPanelExpanded ?? true) ? thinkingBody.height : 0) + Style.marginS * 2 + Style.marginXS

          Item {
            anchors.fill: parent
            anchors.margins: Style.marginS

            RowLayout {
              id: thinkingHeaderRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: Style.marginS

              NText {
                text: pluginApi?.tr("chat.thinking") || "Thinking"
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
                applyUiScale: false
                font.weight: Font.Medium
              }

              Item { Layout.fillWidth: true }

              NIcon {
                icon: (mainInstance?.thinkingPanelExpanded ?? true) ? "chevron-down" : "chevron-right"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                applyUiScale: false
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: mainInstance.thinkingPanelExpanded = !mainInstance.thinkingPanelExpanded
              }
            }

            Flickable {
              id: thinkingBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: thinkingHeaderRow.bottom
              anchors.topMargin: Style.marginXS
              readonly property real maxVisibleHeight: Math.max(48, root.height * 0.25)
              height: (mainInstance?.thinkingPanelExpanded ?? true) ? Math.min(maxVisibleHeight, Math.max(48, thinkingText.contentHeight)) : 0
              visible: mainInstance?.thinkingPanelExpanded ?? true
              contentWidth: width
              contentHeight: Math.max(height, thinkingText.contentHeight)
              clip: true

              onContentHeightChanged: {
                contentY = contentHeight > height ? contentHeight - height : 0;
              }

              TextEdit {
                id: thinkingText
                width: thinkingBody.width
                height: contentHeight
                text: currentThinking
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: Text.MarkdownText
                color: Color.mOnSurfaceVariant
                font.pointSize: Math.max(1, Style.fontSizeS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
                font.family: Settings.data.ui.fontDefault
                onLinkActivated: link => Qt.openUrlExternally(link)
              }

              ScrollBar.vertical: ScrollBar {}
            }
          }
        }

        Rectangle {
          id: toolsPanel
          width: transientPanelsContent.width
          visible: currentToolEvents.length > 0
          radius: Style.radiusS
          color: Qt.alpha(Color.mSurface, 0.8)
          border.color: Qt.alpha(Color.mOnSurfaceVariant, 0.15)
          border.width: 1
          implicitHeight: toolsHeaderRow.height + ((mainInstance?.toolsPanelExpanded ?? true) ? toolsBody.height : 0) + Style.marginS * 2 + Style.marginXS

          Item {
            anchors.fill: parent
            anchors.margins: Style.marginS

            RowLayout {
              id: toolsHeaderRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: Style.marginS

              NText {
                text: pluginApi?.tr("chat.toolActivity") || "Tool activity"
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
                applyUiScale: false
                font.weight: Font.Medium
              }

              Item { Layout.fillWidth: true }

              NIcon {
                icon: (mainInstance?.toolsPanelExpanded ?? true) ? "chevron-down" : "chevron-right"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
                applyUiScale: false
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: mainInstance.toolsPanelExpanded = !mainInstance.toolsPanelExpanded
              }
            }

            Flickable {
              id: toolsBody
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: toolsHeaderRow.bottom
              anchors.topMargin: Style.marginXS
              readonly property real maxVisibleHeight: Math.max(48, root.height * 0.25)
              height: (mainInstance?.toolsPanelExpanded ?? true) ? Math.min(maxVisibleHeight, Math.max(48, toolsColumn.implicitHeight)) : 0
              visible: mainInstance?.toolsPanelExpanded ?? true
              contentWidth: width
              contentHeight: Math.max(height, toolsColumn.implicitHeight)
              clip: true

              onContentHeightChanged: {
                contentY = contentHeight > height ? contentHeight - height : 0;
              }

              Column {
                id: toolsColumn
                width: toolsBody.width
                spacing: Style.marginS

                Repeater {
                  model: currentToolEvents

                  delegate: Rectangle {
                    required property var modelData
                    width: toolsColumn.width
                    radius: Style.radiusS
                    color: Qt.alpha(modelData.isError ? Color.mError : Color.mSurfaceVariant, 0.18)
                    border.color: Qt.alpha(modelData.isError ? Color.mError : Color.mOnSurfaceVariant, 0.18)
                    border.width: 1
                    implicitHeight: toolEntryContent.implicitHeight + Style.marginS * 2

                    Column {
                      id: toolEntryContent
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.marginS
                      spacing: Style.marginXS

                      NText {
                        width: parent.width
                        text: (modelData.toolName || "tool") + " • " + (modelData.status || "running")
                        color: modelData.isError ? Color.mError : Color.mOnSurface
                        pointSize: Style.fontSizeXS
                        applyUiScale: false
                        font.weight: Font.Medium
                      }

                      TextEdit {
                        width: parent.width
                        visible: !!modelData.summary
                        text: modelData.summary || ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: Text.PlainText
                        color: Color.mOnSurfaceVariant
                        font.pointSize: Math.max(1, Style.fontSizeXS * Settings.data.ui.fontFixedScale * Style.uiScaleRatio)
                        font.family: Settings.data.ui.fontFixed || "monospace"
                        onLinkActivated: link => Qt.openUrlExternally(link)
                      }

                      TextEdit {
                        width: parent.width
                        visible: !!modelData.details
                        text: modelData.details || ""
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: Text.PlainText
                        color: modelData.isError ? Color.mError : Color.mOnSurfaceVariant
                        font.pointSize: Math.max(1, Style.fontSizeXS * Settings.data.ui.fontFixedScale * Style.uiScaleRatio)
                        font.family: Settings.data.ui.fontFixed || "monospace"
                        onLinkActivated: link => Qt.openUrlExternally(link)
                      }
                    }
                  }
                }
              }

              ScrollBar.vertical: ScrollBar {}
            }
          }
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: errorRow.implicitHeight + Style.marginS * 2
      color: Qt.alpha(Color.mError, 0.2)
      radius: Style.radiusS
      visible: errorMessage !== ""

      RowLayout {
        id: errorRow
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginS

        NIcon {
          icon: "alert-triangle"
          color: Color.mError
          pointSize: Style.fontSizeM
        }

        TextEdit {
          Layout.fillWidth: true
          text: errorMessage
          color: Color.mError
          font.pointSize: Math.max(1, Style.fontSizeS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
          font.family: Settings.data.ui.fontDefault
          wrapMode: TextEdit.Wrap
          readOnly: true
          selectByMouse: true
        }
      }
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: inputSection.implicitHeight + Style.marginS * 2
      color: Color.mSurface
      radius: Style.radiusM

      ColumnLayout {
        id: inputSection
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginXS

        RowLayout {
          id: inputLayout
          Layout.fillWidth: true
          spacing: Style.marginS

          ScrollView {
            Layout.fillWidth: true
            Layout.maximumHeight: 100

            TextArea {
              id: inputField
              placeholderText: pluginApi?.tr("chat.placeholder")
              placeholderTextColor: Color.mOnSurfaceVariant
              color: Color.mOnSurface
              font.pointSize: Style.fontSizeM
              wrapMode: TextArea.Wrap
              background: null
              selectByMouse: true
              enabled: mainInstance?.backendReady ?? false

              onTextChanged: {
                if (root.slashSelectionIndex >= root.slashCommandOptions.length)
                  root.slashSelectionIndex = Math.max(0, root.slashCommandOptions.length - 1);
                else if (root.slashSelectionIndex < 0)
                  root.slashSelectionIndex = 0;
                if (root.slashQuery !== null && !mainInstance?.commandsLoading && ((mainInstance?.availableCommands?.length || 0) === 0))
                  mainInstance?.refreshAvailableCommands();
              }

              Keys.onPressed: function (event) {
                if (!root.slashPopupVisible) {
                  if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    sendMessage(isGenerating ? ((event.modifiers & Qt.AltModifier) ? "followUp" : "steer") : "");
                    event.accepted = true;
                  }
                  return;
                }
                if (event.key === Qt.Key_Down && root.slashCommandOptions.length > 0) {
                  root.moveSlashSelection(1);
                  event.accepted = true;
                } else if (event.key === Qt.Key_Up && root.slashCommandOptions.length > 0) {
                  root.moveSlashSelection(-1);
                  event.accepted = true;
                } else if (event.key === Qt.Key_Tab && root.slashCommandOptions.length > 0) {
                  root.applySlashCommand(root.selectedSlashCommand());
                  event.accepted = true;
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier) && root.slashCommandOptions.length > 0) {
                  root.applySlashCommand(root.selectedSlashCommand());
                  event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                  inputField.text = inputField.text.replace(/^\/[^\s]*/, "/");
                  event.accepted = true;
                }
              }

              Keys.onReturnPressed: function (event) {
                if (event.modifiers & Qt.ShiftModifier) {
                  inputField.insert(inputField.cursorPosition, "\n");
                } else if (!root.slashPopupVisible) {
                  sendMessage(isGenerating ? ((event.modifiers & Qt.AltModifier) ? "followUp" : "steer") : "");
                }
                event.accepted = true;
              }
            }
          }

          NIconButton {
            icon: isGenerating ? "player-stop" : "send"
            colorFg: isGenerating ? Color.mError : (inputField.text.trim() !== "" ? Color.mPrimary : Color.mOnSurfaceVariant)
            enabled: isGenerating || (inputField.text.trim() !== "" && (mainInstance?.backendReady ?? false))
            tooltipText: isGenerating ? pluginApi?.tr("chat.stop") : pluginApi?.tr("chat.send")
            onClicked: {
              if (isGenerating) {
                mainInstance?.stopGeneration();
              } else {
                sendMessage();
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          visible: root.slashPopupVisible
          color: Qt.alpha(Color.mSurfaceVariant, 0.55)
          radius: Style.radiusS
          border.color: Qt.alpha(Color.mOnSurfaceVariant, 0.15)
          border.width: 1
          implicitHeight: slashCommandColumn.implicitHeight + Style.marginS * 2

          ColumnLayout {
            id: slashCommandColumn
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginXS

            NText {
              visible: mainInstance?.commandsLoading ?? false
              text: pluginApi?.tr("chat.commandsLoading") || "Loading commands..."
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              applyUiScale: false
            }

            NText {
              visible: !(mainInstance?.commandsLoading ?? false) && root.slashCommandOptions.length === 0
              text: pluginApi?.tr("chat.noSlashCommands") || "No matching slash commands"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              applyUiScale: false
            }

            Repeater {
              model: root.slashCommandOptions.slice(0, 6)

              delegate: Rectangle {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: slashCommandRow.implicitHeight + Style.marginS
                radius: Style.radiusS
                color: index === root.slashSelectionIndex ? Qt.alpha(Color.mPrimary, 0.18) : "transparent"
                border.color: index === root.slashSelectionIndex ? Qt.alpha(Color.mPrimary, 0.35) : "transparent"
                border.width: 1

                RowLayout {
                  id: slashCommandRow
                  anchors.fill: parent
                  anchors.margins: Style.marginS / 2
                  spacing: Style.marginS

                  NText {
                    text: modelData.name
                    color: index === root.slashSelectionIndex ? Color.mPrimary : Color.mOnSurface
                    pointSize: Style.fontSizeS
                    applyUiScale: false
                    font.weight: Font.Medium
                  }

                  NText {
                    Layout.fillWidth: true
                    text: modelData.description || modelData.source || ""
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.slashSelectionIndex = index
                  onClicked: root.applySlashCommand(modelData)
                }
              }
            }
          }
        }
      }
    }

    NText {
      Layout.fillWidth: true
      text: mainInstance?.modelsLoading ? ((pluginApi?.tr("chat.modelsLoading") || "Loading models") + " • " + inputStatusLabel) : inputStatusLabel
      color: Color.mOnSurfaceVariant
      pointSize: Math.max(1, Style.fontSizeXS - 1)
      applyUiScale: false
      elide: Text.ElideRight
      opacity: 0.85
    }
  }

  function getSlashQuery(text) {
    const source = text || "";
    if (!source.startsWith("/") || source.indexOf("\n") >= 0)
      return null;
    return source;
  }

  function filterSlashCommands(query) {
    const commands = mainInstance?.availableCommands || [];
    if (query === null)
      return [];
    const normalized = query.toLowerCase();
    if (normalized === "/")
      return commands;

    if (normalized.startsWith("/thinking") || normalized.startsWith("/think")) {
      const levels = thinkingOptions.map(function (entry) {
        return {
          "key": "/thinking " + entry.key,
          "name": "/thinking " + entry.key,
          "description": "Set thinking level to " + entry.key,
          "source": "builtin"
        };
      });
      const parts = normalized.split(/\s+/, 2);
      const levelPrefix = parts.length > 1 ? parts[1].trim() : "";
      if (!levelPrefix)
        return levels;
      return levels.filter(function (entry) {
        return entry.name.toLowerCase().indexOf("/thinking " + levelPrefix) === 0;
      });
    }

    return commands.filter(function (entry) {
      const name = (entry?.name || "").toLowerCase();
      const description = (entry?.description || "").toLowerCase();
      return name.indexOf(normalized) === 0 || description.indexOf(normalized.slice(1)) >= 0;
    });
  }

  function moveSlashSelection(step) {
    const count = slashCommandOptions.length;
    if (count <= 0)
      return;
    slashSelectionIndex = (slashSelectionIndex + step + count) % count;
  }

  function selectedSlashCommand() {
    if (slashCommandOptions.length <= 0)
      return null;
    const index = Math.max(0, Math.min(slashSelectionIndex, slashCommandOptions.length - 1));
    return slashCommandOptions[index];
  }

  function applySlashCommand(command) {
    if (!command?.name)
      return;
    const source = inputField.text || "";
    const spaceIndex = source.indexOf(" ");
    const suffix = spaceIndex >= 0 ? source.slice(spaceIndex).replace(/^\s+/, "") : "";
    inputField.text = command.name + (suffix ? (" " + suffix) : " ");
    inputField.cursorPosition = inputField.text.length;
    slashSelectionIndex = 0;
    inputField.forceActiveFocus();
  }

  function thinkingIndexForKey(key) {
    for (let index = 0; index < thinkingOptions.length; ++index) {
      if (thinkingOptions[index]?.key === key)
        return index;
    }
    return 0;
  }

  function modelIndexForKey(key) {
    const options = modelOptions || [];
    for (let index = 0; index < options.length; ++index) {
      if (options[index]?.key === key)
        return index;
    }
    return options.length > 0 ? 0 : -1;
  }

  function sendMessage(streamingBehavior) {
    const text = inputField.text.trim();
    if (text === "" || !mainInstance)
      return;
    if (mainInstance.sendMessage(text, streamingBehavior)) {
      inputField.text = "";
      inputField.forceActiveFocus();
    }
  }

  function focusInput() {
    if (typeof inputField !== "undefined" && inputField && inputField.forceActiveFocus)
      inputField.forceActiveFocus();
  }

  Loader {
    active: root.lightboxSource !== "" && !!pluginApi?.panelOpenScreen

    sourceComponent: PanelWindow {
      screen: pluginApi.panelOpenScreen
      visible: true
      color: Qt.alpha("black", 0.92)
      anchors.top: true
      anchors.left: true
      anchors.right: true
      anchors.bottom: true
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "noctalia-pi-assistant-lightbox-" + (screen?.name || "unknown")

      MouseArea {
        anchors.fill: parent
        onClicked: root.lightboxSource = ""
      }

      Image {
        anchors.centerIn: parent
        width: parent.width * 0.94
        height: parent.height * 0.94
        source: root.lightboxSource
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
      }

      NIconButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.marginL
        icon: "x"
        tooltipText: pluginApi?.tr("chat.closeLightbox") || "Close"
        onClicked: root.lightboxSource = ""
      }
    }
  }
}
