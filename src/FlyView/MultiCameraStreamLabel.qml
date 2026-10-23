import QtQuick

import QGroundControl
import QGroundControl.Controls

/// Camera name of a multi-camera stream on a dark pill, with a red dot while it records.
Rectangle {
    id: control

    required property var stream
    property real maximumWidth:     ScreenTools.defaultFontPixelHeight * 20
    property bool small:            false

    readonly property real _margin: ScreenTools.defaultFontPixelWidth * (small ? 0.5 : 1)

    width:      row.width + _margin
    height:     row.height + _margin / 2
    color:      Qt.rgba(0, 0, 0, 0.6)
    radius:     small ? 0 : _margin / 2
    visible:    nameText.text !== ""

    QGCPalette { id: qgcPal }

    Row {
        id:                 row
        anchors.centerIn:   parent
        spacing:            control._margin / 2

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width:                  ScreenTools.defaultFontPixelHeight * (control.small ? 0.4 : 0.5)
            height:                 width
            radius:                 width / 2
            color:                  qgcPal.colorRed
            visible:                !!control.stream && control.stream.recording

            // Blinks while recording waits for a lost stream to come back.
            SequentialAnimation on opacity {
                running:    !!control.stream && control.stream.recordingPaused
                loops:      Animation.Infinite
                onStopped:  parent.opacity = 1

                NumberAnimation { to: 0.15; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }
        }

        QGCLabel {
            id:             nameText
            width:          Math.min(implicitWidth, control.maximumWidth)
            elide:          Text.ElideRight
            text:           control.stream ? control.stream.label : ""
            color:          "white"
            font.pointSize: control.small ? ScreenTools.defaultFontPointSize : ScreenTools.mediumFontPointSize
            font.bold:      true
        }
    }
}
