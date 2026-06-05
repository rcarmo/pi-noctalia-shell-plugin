import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var message
  property var pluginApi

  readonly property int bubblePadding: Style.marginM
  readonly property int copyButtonSize: 28
  readonly property real maxUserBubbleWidth: width * 0.8
  readonly property real userBubbleWidth: Math.min(maxUserBubbleWidth, Math.max(72 * Style.uiScaleRatio, userTextMetrics.width + (bubblePadding * 2) + (message?.isStreaming ? 0 : copyButtonSize + Style.marginS)))
  readonly property var segments: buildSegments(message?.content || "")

  signal copyRequested(string text)
  signal imageOpenRequested(string source)

  height: mainLayout.implicitHeight
  width: parent ? parent.width : 400

  function svgDataUri(svg) {
    const source = (svg || "").trim();
    if (!source)
      return "";
    return "data:image/svg+xml;utf8," + encodeURIComponent(source);
  }

  function extractImgSrc(tag) {
    const match = (tag || "").match(/src\s*=\s*["']([^"']+)["']/i);
    return match && match[1] ? match[1] : "";
  }

  function buildSegments(text) {
    const source = text || "";
    if (!source)
      return [];
    if (message?.role !== "assistant")
      return [{ "type": "text", "content": source }];

    const pattern = /```svg\s*\r?\n([\s\S]*?)```|<svg\b[\s\S]*?<\/svg>|<img\b[^>]*src\s*=\s*["'][^"']+["'][^>]*>|!\[[^\]]*\]\(([^)]+)\)/ig;
    const next = [];
    let lastIndex = 0;
    let match;

    while ((match = pattern.exec(source)) !== null) {
      const raw = match[0] || "";
      const start = match.index;
      if (start > lastIndex) {
        const before = source.slice(lastIndex, start);
        if (before)
          next.push({ "type": "text", "content": before });
      }

      if (match[1] !== undefined) {
        const svg = (match[1] || "").trim();
        if (svg)
          next.push({ "type": "image", "src": svgDataUri(svg), "raw": raw });
      } else if (/^<svg\b/i.test(raw)) {
        next.push({ "type": "image", "src": svgDataUri(raw), "raw": raw });
      } else if (/^<img\b/i.test(raw)) {
        const src = extractImgSrc(raw);
        if (src)
          next.push({ "type": "image", "src": src, "raw": raw });
      } else if (match[2] !== undefined) {
        const src = (match[2] || "").trim();
        if (src)
          next.push({ "type": "image", "src": src, "raw": raw });
      }

      lastIndex = start + raw.length;
    }

    if (lastIndex < source.length) {
      const tail = source.slice(lastIndex);
      if (tail)
        next.push({ "type": "text", "content": tail });
    }

    if (next.length === 0)
      next.push({ "type": "text", "content": source });

    return next;
  }

  TextMetrics {
    id: userTextMetrics
    text: message?.role === "user" ? (message?.content || "") : ""
    font.family: Settings.data.ui.fontDefault
    font.pointSize: Math.max(1, Style.fontSizeM * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
    font.weight: Style.fontWeightMedium
  }

  RowLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.marginS

    Image {
      Layout.alignment: Qt.AlignTop
      visible: message.role === "assistant"
      Layout.preferredWidth: Style.fontSizeL * 1.4
      Layout.preferredHeight: Layout.preferredWidth
      source: Qt.resolvedUrl("assets/pi-favicon.svg")
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Item {
      visible: message.role === "user"
      Layout.fillWidth: true
    }

    Rectangle {
      id: bubbleRect
      Layout.fillWidth: message.role === "assistant"
      Layout.maximumWidth: message.role === "assistant" ? parent.width : root.maxUserBubbleWidth
      Layout.preferredWidth: message.role === "assistant" ? parent.width : root.userBubbleWidth
      Layout.preferredHeight: contentCol.implicitHeight + (root.bubblePadding * 2)
      color: message.role === "user" ? Color.mSurfaceVariant : Color.mSurface
      radius: Style.radiusM

      Rectangle {
        visible: message.role === "user"
        anchors.top: parent.top
        anchors.right: parent.right
        width: parent.radius
        height: parent.radius
        color: parent.color
      }

      Rectangle {
        id: copyButton
        visible: !message.isStreaming
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.marginS
        width: root.copyButtonSize
        height: root.copyButtonSize
        radius: 4
        color: copyMouse.containsMouse ? Color.mSurfaceVariant : "transparent"

        NIcon {
          anchors.centerIn: parent
          icon: "copy"
          pointSize: Style.fontSizeM
          applyUiScale: false
          color: copyMouse.containsMouse ? Color.mPrimary : Color.mOnSurfaceVariant
        }

        MouseArea {
          id: copyMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.copyRequested(message.content)
          ToolTip.visible: containsMouse
          ToolTip.text: pluginApi?.tr("chat.copy") ?? "Copy"
        }
      }

      Column {
        id: contentCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.bubblePadding
        anchors.rightMargin: root.bubblePadding + (copyButton.visible ? copyButton.width + Style.marginS : 0)
        anchors.topMargin: root.bubblePadding
        spacing: Style.marginS

        Repeater {
          model: root.segments

          delegate: Item {
            required property var modelData
            width: contentCol.width
            implicitHeight: modelData.type === "image" ? imageContainer.implicitHeight : textBlock.implicitHeight

            TextEdit {
              id: textBlock
              visible: modelData.type === "text"
              width: parent.width
              wrapMode: TextEdit.Wrap
              text: modelData.content || ""
              textFormat: message.role === "assistant" ? Text.MarkdownText : Text.PlainText
              readOnly: true
              selectByMouse: true
              color: Color.mOnSurface
              font.family: Settings.data.ui.fontDefault
              font.pointSize: Math.max(1, Style.fontSizeM * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
              font.weight: Style.fontWeightMedium
              selectionColor: Color.mPrimary
              selectedTextColor: Color.mOnPrimary
              onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Rectangle {
              id: imageContainer
              visible: modelData.type === "image"
              width: parent.width
              radius: Style.radiusS
              color: Qt.alpha(Color.mSurfaceVariant, 0.35)
              border.color: Qt.alpha(Color.mOnSurfaceVariant, 0.15)
              border.width: 1
              implicitHeight: (imageItem.status === Image.Ready && imageItem.implicitWidth > 0 ? Math.min(360, width * (imageItem.implicitHeight / imageItem.implicitWidth)) : 200) + Style.marginS * 2

              Image {
                id: imageItem
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginS
                source: modelData.src || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                smooth: true
                sourceSize.width: Math.max(1, width * 2)
                height: status === Image.Ready && implicitWidth > 0 ? Math.min(360, width * (implicitHeight / implicitWidth)) : 200
              }

              MouseArea {
                anchors.fill: parent
                enabled: !!modelData.src
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.imageOpenRequested(modelData.src)
              }

              TextEdit {
                anchors.fill: parent
                anchors.margins: Style.marginS
                visible: imageItem.status === Image.Error
                wrapMode: TextEdit.Wrap
                text: modelData.raw || modelData.src || ""
                textFormat: Text.PlainText
                readOnly: true
                selectByMouse: true
                color: Color.mOnSurfaceVariant
                font.family: Settings.data.ui.fontDefault
                font.pointSize: Math.max(1, Style.fontSizeS * Settings.data.ui.fontDefaultScale * Style.uiScaleRatio)
              }
            }
          }
        }
      }
    }

    Item {
      visible: message.role === "assistant"
      Layout.fillWidth: true
    }

    NIcon {
      Layout.alignment: Qt.AlignTop
      visible: message.role === "user"
      icon: "user"
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeL
      applyUiScale: false
    }
  }
}
