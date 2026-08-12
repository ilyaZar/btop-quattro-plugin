import QtQuick

Item {
  id: root

  property real iconSize: 12
  property real cpuUsage: 0
  property real memoryUsage: 0
  property color color: "white"

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Rectangle {
    id: chip
    anchors.centerIn: parent
    width: root.iconSize * 0.82
    height: root.iconSize * 0.82
    radius: root.iconSize * 0.14
    color: "transparent"
    border.width: Math.max(1, root.iconSize * 0.08)
    border.color: root.color

    Row {
      anchors.centerIn: parent
      spacing: root.iconSize * 0.12

      Meter { value: root.cpuUsage }
      Meter { value: root.memoryUsage }
    }
  }

  component Meter: Item {
    required property real value

    width: root.iconSize * 0.18
    height: root.iconSize * 0.48

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: root.color
      opacity: 0.35
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(parent.width, parent.height * value / 100)
      radius: width / 2
      color: root.color

      Behavior on height {
        NumberAnimation {
          duration: 220
          easing.type: Easing.OutCubic
        }
      }
    }
  }
}
