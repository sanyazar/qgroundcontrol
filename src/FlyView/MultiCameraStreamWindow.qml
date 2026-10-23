import QtQuick
import QtQuick.Window
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

/// One multi-camera stream in a window of its own, e.g. on a second monitor. The stream renders into this
/// window's VideoOutput while it is open; closing the window hands the video back to its Fly View tile.
Window {
    id: window

    required property var stream

    /// The video was detached from this window, which is closing; the tile takes it back.
    signal videoReleased()

    width:          ScreenTools.defaultFontPixelHeight * 48
    height:         width * 9 / 16
    minimumWidth:   ScreenTools.defaultFontPixelHeight * 16
    minimumHeight:  ScreenTools.defaultFontPixelHeight * 9
    title:          stream ? stream.label : ""
    color:          "black"
    visible:        true

    readonly property real _margin: ScreenTools.defaultFontPixelWidth

    /// Hands the video back before the window (and its VideoOutput) goes away.
    function releaseVideo() {
        if (window.stream) {
            window.stream.detachVideoOutput(videoOutput)
        }
        window.videoReleased()
    }

    VideoOutput {
        id:             videoOutput
        anchors.fill:   parent
        fillMode:       QGroundControl.settingsManager.videoSettings.videoFit.rawValue === 2
                            ? VideoOutput.PreserveAspectCrop
                            : VideoOutput.PreserveAspectFit
    }

    QGCLabel {
        anchors.centerIn:   parent
        visible:            !(window.stream && window.stream.decoding)
        text:               qsTr("WAITING FOR VIDEO")
        color:              "white"
        font.bold:          true
    }

    MultiCameraStreamLabel {
        id:                 nameLabel
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.margins:    window._margin
        stream:             window.stream
        maximumWidth:       window.width / 2
    }

    MultiCameraStreamControls {
        anchors.left:           nameLabel.right
        anchors.leftMargin:     window._margin
        anchors.verticalCenter: nameLabel.verticalCenter
        stream:                 window.stream
    }

    Component.onCompleted: {
        if (stream) {
            stream.attachVideoOutput(videoOutput)
        }
    }

    onClosing: releaseVideo()
}
