import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

/// Buttons for one MultiCameraManager stream: record, photo, camera audio, talk to the camera and open in a
/// separate window. Which buttons show is chosen by the show* properties; record and photo need video.
Row {
    id: control

    required property var stream
    property real buttonSize:       ScreenTools.defaultFontPixelHeight * 2
    property bool showPhoto:        true
    property bool showTalk:         true
    property bool showWindow:       false

    /// The "open in a separate window" button was pressed.
    signal openWindowClicked()

    spacing: buttonSize / 4

    readonly property bool _decoding:   !!stream && stream.decoding
    readonly property bool _audio:      !!stream && stream.audioSupported

    QGCPalette { id: qgcPal }

    component CircleButton: Rectangle {
        id: button

        property real   size:       ScreenTools.defaultFontPixelHeight * 2
        property string iconSource: ""
        property bool   highlighted: false     ///< Red background, e.g. while talking
        property bool   pending:    false      ///< Requested but not running yet: dimmed
        property string toolTip:    ""
        default property alias content: extra.data

        signal clicked()

        width:      size
        height:     size
        radius:     size / 2
        color:      highlighted ? Qt.rgba(0.9, 0.15, 0.15, 0.85) : Qt.rgba(0, 0, 0, 0.6)
        opacity:    enabled ? (pending ? 0.55 : 1) : 0.4

        QGCColoredImage {
            anchors.centerIn:   parent
            width:              parent.width * 0.6
            height:             width
            sourceSize.height:  height
            source:             button.iconSource
            color:              "white"
            visible:            button.iconSource !== ""
        }

        Item {
            id:             extra
            anchors.fill:   parent
        }

        MouseArea {
            id:             mouseArea
            anchors.fill:   parent
            hoverEnabled:   true
            onClicked:      button.clicked()
        }

        ToolTip.visible:    mouseArea.containsMouse && button.toolTip !== ""
        ToolTip.text:       button.toolTip
        ToolTip.delay:      600
    }

    // Record
    CircleButton {
        size:       control.buttonSize
        visible:    control._decoding
        toolTip:    control.stream && control.stream.recording ? qsTr("Stop recording") : qsTr("Record")
        onClicked: {
            if (control.stream.recording) {
                control.stream.stopRecording()
            } else {
                control.stream.startRecording()
            }
        }

        Rectangle {
            anchors.centerIn:   parent
            width:              parent.width * 0.5
            height:             width
            radius:             control.stream && control.stream.recording ? 0 : width / 2
            color:              qgcPal.colorRed
        }
    }

    // Photo from the video frame
    CircleButton {
        size:       control.buttonSize
        visible:    control.showPhoto && control._decoding
        iconSource: "/InstrumentValueIcons/camera.svg"
        toolTip:    qsTr("Save a photo")
        onClicked:  control.stream.grabImage()
    }

    // Camera audio
    CircleButton {
        size:       control.buttonSize
        visible:    control._audio
        iconSource: control.stream && control.stream.audioEnabled ? "/InstrumentValueIcons/volume-up.svg"
                                                                  : "/InstrumentValueIcons/volume-off.svg"
        pending:    control.stream && control.stream.audioEnabled && !control.stream.audioPlaying
        toolTip:    control.stream && control.stream.audioEnabled ? qsTr("Mute camera audio") : qsTr("Play camera audio")
        onClicked:  control.stream.audioEnabled = !control.stream.audioEnabled
    }

    // Talk through the camera's speaker
    CircleButton {
        size:           control.buttonSize
        visible:        control.showTalk && control._audio
        iconSource:     "/InstrumentValueIcons/mic.svg"
        highlighted:    control.stream && control.stream.talkbackEnabled
        pending:        control.stream && control.stream.talkbackEnabled && !control.stream.talkbackActive
        toolTip:        control.stream && control.stream.talkbackEnabled ? qsTr("Stop talking")
                                                                         : qsTr("Talk through the camera speaker")
        onClicked:      control.stream.talkbackEnabled = !control.stream.talkbackEnabled
    }

    // Open in a separate window. Moving the video restarts its stream, so not while recording.
    CircleButton {
        size:       control.buttonSize
        visible:    control.showWindow && !ScreenTools.isMobile
        enabled:    !(control.stream && control.stream.recording)
        iconSource: "/InstrumentValueIcons/window-new.svg"
        toolTip:    enabled ? qsTr("Open in a separate window") : qsTr("Stop recording to open in a separate window")
        onClicked:  control.openWindowClicked()
    }
}
