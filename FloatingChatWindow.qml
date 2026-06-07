import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

FloatingWindow {
  id: root

  property var pluginApi: null
  property var mainInstance: null

  title: "Pi Assistant"
  color: "transparent"
  visible: true

  readonly property int panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  readonly property real panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? 0.85
  readonly property real uiScale: pluginApi?.pluginSettings?.scale ?? 1
  readonly property real dragHandleHeight: Math.max(18 * Style.uiScaleRatio, Style.marginL)
  readonly property real initialHeight: screen ? (screen.height * panelHeightRatio) : 620 * Style.uiScaleRatio

  minimumSize: Qt.size(320 * Style.uiScaleRatio, 360 * Style.uiScaleRatio)
  implicitWidth: Math.round(panelWidth)
  implicitHeight: Math.round(initialHeight)

  function persistSize() {
    if (!pluginApi)
      return;
    pluginApi.pluginSettings.panelWidth = Math.round(root.width || root.implicitWidth);
    if (screen && screen.height > 0)
      pluginApi.pluginSettings.panelHeightRatio = Math.max(0.1, Math.min(1, (root.height || root.implicitHeight) / screen.height));
    pluginApi.saveSettings();
  }

  function closeWindow() {
    persistSize();
    if (mainInstance?.closeStandaloneWindow)
      mainInstance.closeStandaloneWindow();
    else
      visible = false;
  }

  onClosed: closeWindow()

  Timer {
    id: persistSizeTimer
    interval: 350
    repeat: false
    onTriggered: root.persistSize()
  }

  onWidthChanged: persistSizeTimer.restart()
  onHeightChanged: persistSizeTimer.restart()

  Rectangle {
    anchors.fill: parent
    radius: Style.radiusL
    color: Color.mSurfaceVariant
    clip: true

    Item {
      id: scaledContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: root.dragHandleHeight
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

    Rectangle {
      id: dragHandle
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: root.dragHandleHeight
      color: dragArea.pressed ? Color.mHover : "transparent"
      radius: Style.radiusL

      Rectangle {
        width: 48 * Style.uiScaleRatio
        height: Math.max(3, 3 * Style.uiScaleRatio)
        radius: height / 2
        anchors.centerIn: parent
        color: Color.mOnSurfaceVariant
        opacity: dragArea.containsMouse || dragArea.pressed ? 0.55 : 0.28
      }

      MouseArea {
        id: dragArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: root.startSystemMove()
      }
    }

    MouseArea {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 8 * Style.uiScaleRatio
      cursorShape: Qt.SizeHorCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.LeftEdge)
    }

    MouseArea {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 8 * Style.uiScaleRatio
      cursorShape: Qt.SizeHorCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.RightEdge)
    }

    MouseArea {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 8 * Style.uiScaleRatio
      cursorShape: Qt.SizeVerCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.TopEdge)
    }

    MouseArea {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 8 * Style.uiScaleRatio
      cursorShape: Qt.SizeVerCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.BottomEdge)
    }

    MouseArea {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      width: 18 * Style.uiScaleRatio
      height: 18 * Style.uiScaleRatio
      cursorShape: Qt.SizeFDiagCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
    }

    MouseArea {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      width: 18 * Style.uiScaleRatio
      height: 18 * Style.uiScaleRatio
      cursorShape: Qt.SizeBDiagCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
    }

    MouseArea {
      anchors.right: parent.right
      anchors.top: parent.top
      width: 18 * Style.uiScaleRatio
      height: 18 * Style.uiScaleRatio
      cursorShape: Qt.SizeBDiagCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.RightEdge | Qt.TopEdge)
    }

    MouseArea {
      anchors.left: parent.left
      anchors.top: parent.top
      width: 18 * Style.uiScaleRatio
      height: 18 * Style.uiScaleRatio
      cursorShape: Qt.SizeFDiagCursor
      acceptedButtons: Qt.LeftButton
      onPressed: root.startSystemResize(Qt.LeftEdge | Qt.TopEdge)
    }

    Rectangle {
      id: closeButton
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Math.max(4, Style.marginXS)
      width: Math.max(22 * Style.uiScaleRatio, root.dragHandleHeight)
      height: width
      radius: width / 2
      color: closeMouse.containsMouse ? Qt.alpha(Color.mError, 0.18) : "transparent"
      z: 10

      NIcon {
        anchors.centerIn: parent
        icon: "x"
        color: closeMouse.containsMouse ? Color.mError : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        applyUiScale: false
      }

      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.closeWindow()
      }
    }
  }
}
