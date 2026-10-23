import QtQuick
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

// One tile per MultiCameraManager stream. The selected (main) camera fills this item, which
// FlyView shows full screen or in the picture-in-picture block; every other camera is
// reparented into stripHost as a block of its own. Each tile keeps its VideoOutput for its
// whole life, so switching cameras only moves tiles and never rebinds or restarts a stream.
Item {
    id: root

    property bool compact: false        ///< true: this item is in the PiP block; main tile without controls
    property Item stripHost: null       ///< Container (FlyView level) for the blocks of the other cameras
    property real stripTileWidth: ScreenTools.defaultFontPixelHeight * 10
    property real stripTileHeight: stripTileWidth * 9 / 16
    property real stripSpacing: ScreenTools.defaultFontPixelWidth * 0.75

    /// A camera block other than the main one was clicked; it is now the main camera.
    signal cameraSelected()

    readonly property var  _multiCamera:    QGroundControl.videoManager.multiCamera
    readonly property int  _streamCount:    _multiCamera ? _multiCamera.streams.count : 0
    readonly property int  _mainIndex:      _multiCamera ? _multiCamera.mainIndex : -1
    readonly property real _margin:         ScreenTools.defaultFontPixelWidth
    /// Number of camera blocks in stripHost (every camera except the main one).
    readonly property int  stripCount:      stripHost ? Math.max(0, _streamCount - 1) : 0
    readonly property real _buttonSize:     ScreenTools.defaultFontPixelHeight * (compact ? 1.5 : 2)

    QGCPalette { id: qgcPal }

    Rectangle {
        anchors.fill:   parent
        color:          "black"
    }

    QGCLabel {
        anchors.centerIn:   parent
        visible:            root._streamCount === 0
        text:               qsTr("NO CAMERA STREAMS")
        color:              "white"
        font.bold:          true
        font.pointSize:     root.compact ? ScreenTools.smallFontPointSize : ScreenTools.largeFontPointSize
    }

    Repeater {
        model: root._multiCamera ? root._multiCamera.streams : null

        // Repeater reparents its delegates, so the tile that moves between root and stripHost is a child.
        delegate: Item {
            id: delegateRoot

            required property var object
            required property int index

            Item {
                id: tile

                readonly property int  index:       delegateRoot.index
                readonly property var  stream:      delegateRoot.object
                readonly property bool isMain:      index === root._mainIndex
                readonly property int  thumbSlot:   index < root._mainIndex ? index : index - 1

                readonly property bool inStrip:     !isMain && !!root.stripHost

                parent:         inStrip ? root.stripHost : root
                anchors.fill:   isMain ? parent : undefined
                x:              inStrip ? thumbSlot * (root.stripTileWidth + root.stripSpacing) : 0
                y:              0
                width:          inStrip ? root.stripTileWidth : 0
                height:         inStrip ? root.stripTileHeight : 0
                visible:        isMain || inStrip

                Rectangle {
                    anchors.fill:   parent
                    color:          "black"
                    visible:        tile.inStrip
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
                    visible:            !(tile.stream && tile.stream.decoding)
                    text:               qsTr("WAITING FOR VIDEO")
                    color:              "white"
                    font.bold:          true
                    font.pointSize:     ScreenTools.smallFontPointSize
                }

                Rectangle {
                    anchors.fill:   parent
                    visible:        !tile.isMain
                    color:          "transparent"
                    border.color:   "white"
                    border.width:   1
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (!tile.isMain && root._multiCamera) {
                            root._multiCamera.mainIndex = tile.index
                            root.cameraSelected()
                        }
                    }
                    onDoubleClicked: {
                        if (tile.isMain && !root.compact) {
                            QGroundControl.videoManager.fullScreen = !QGroundControl.videoManager.fullScreen
                        }
                    }
                }

                // Camera name in the bottom right corner of both the main video and the thumbnails.
                Rectangle {
                    id:                     labelBackground
                    anchors.right:          parent.right
                    anchors.bottom:         parent.bottom
                    anchors.margins:        tile.isMain ? root._margin : 0
                    width:                  labelRow.width + root._margin
                    height:                 labelRow.height + root._margin / 2
                    color:                  Qt.rgba(0, 0, 0, 0.6)
                    radius:                 tile.isMain ? root._margin / 2 : 0
                    visible:                true

                    Row {
                        id:                 labelRow
                        anchors.centerIn:   parent
                        spacing:            root._margin / 2

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width:                  ScreenTools.defaultFontPixelHeight * 0.5
                            height:                 width
                            radius:                 width / 2
                            color:                  qgcPal.colorRed
                            visible:                !!tile.stream && tile.stream.recording
                        }

                        QGCLabel {
                            // Leave room for the record/photo buttons left of the name.
                            width:          Math.min(implicitWidth,
                                                     tile.width - (controlsRow.visible ? controlsRow.width : 0) - root._margin * 4)
                            elide:          Text.ElideRight
                            text:           tile.stream ? tile.stream.label : ""
                            color:          "white"
                            font.pointSize: tile.isMain ? ScreenTools.defaultFontPointSize : ScreenTools.smallFontPointSize
                        }
                    }
                }

                Row {
                    id:                 controlsRow
                    // Next to the camera name: the bottom left corner of the main video is under the PiP block.
                    anchors.right:          labelBackground.left
                    anchors.rightMargin:    root._margin / 2
                    anchors.verticalCenter: labelBackground.verticalCenter
                    spacing:            root._margin / 2
                    visible:            (tile.inStrip || !root.compact) && !!tile.stream && tile.stream.decoding

                    // Record
                    Rectangle {
                        width:  root._buttonSize
                        height: width
                        radius: width / 2
                        color:  Qt.rgba(0, 0, 0, 0.6)

                        Rectangle {
                            anchors.centerIn:   parent
                            width:              parent.width * 0.5
                            height:             width
                            radius:             !!tile.stream && tile.stream.recording ? 0 : width / 2
                            color:              qgcPal.colorRed
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (tile.stream.recording) {
                                    tile.stream.stopRecording()
                                } else {
                                    tile.stream.startRecording()
                                }
                            }
                        }
                    }

                    // Photo from the video frame
                    Rectangle {
                        width:  root._buttonSize
                        height: width
                        radius: width / 2
                        color:  Qt.rgba(0, 0, 0, 0.6)

                        QGCColoredImage {
                            anchors.centerIn:   parent
                            width:              parent.width * 0.6
                            height:             width
                            sourceSize.height:  height
                            source:             "/InstrumentValueIcons/camera.svg"
                            color:              "white"
                        }

                        MouseArea {
                            anchors.fill:   parent
                            onClicked:      tile.stream.grabImage()
                        }
                    }
                }

                Component.onCompleted: {
                    if (stream) {
                        stream.attachVideoOutput(videoOutput)
                    }
                }

                // The receiver renders into videoOutput, so it has to go first.
                Component.onDestruction: {
                    if (stream) {
                        stream.detachVideoOutput(videoOutput)
                    }
                }
            }
        }
    }
}
