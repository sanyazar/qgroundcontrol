import QtQuick
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

// One main video plus a row of thumbnails, one tile per MultiCameraManager stream.
// Each tile keeps its own VideoOutput for its whole life; selecting a thumbnail only
// swaps tile geometry, so no stream has to be rebound or restarted.
Item {
    id: root

    property bool compact: false    ///< true: shown small (PiP), only the main stream without controls

    readonly property var  _multiCamera:    QGroundControl.videoManager.multiCamera
    readonly property int  _streamCount:    _multiCamera ? _multiCamera.streams.count : 0
    readonly property int  _mainIndex:      _multiCamera ? _multiCamera.mainIndex : -1
    readonly property real _margin:         ScreenTools.defaultFontPixelWidth
    readonly property real _thumbHeight:    ScreenTools.defaultFontPixelHeight * 6
    readonly property real _thumbWidth:     _thumbHeight * 16 / 9
    readonly property int  _thumbCount:     Math.max(0, _streamCount - 1)
    readonly property real _thumbRowWidth:  _thumbCount * _thumbWidth + Math.max(0, _thumbCount - 1) * _margin
    readonly property real _thumbTop:       (typeof mainWindow !== "undefined" && mainWindow.header ? mainWindow.header.height : 0) + _margin
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

        delegate: Item {
            id: tile

            required property var object
            required property int index

            readonly property var  stream:      object
            readonly property bool isMain:      index === root._mainIndex
            readonly property int  thumbSlot:   index < root._mainIndex ? index : index - 1

            x:          isMain ? 0 : (root.width - root._thumbRowWidth) / 2 + thumbSlot * (root._thumbWidth + root._margin)
            y:          isMain ? 0 : root._thumbTop
            width:      isMain ? root.width : root._thumbWidth
            height:     isMain ? root.height : root._thumbHeight
            z:          isMain ? 0 : 1
            visible:    isMain || !root.compact

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
                visible:                !root.compact || tile.isMain

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
                        // Leave room for the record/photo buttons on the left of the tile.
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
                anchors.left:       parent.left
                anchors.bottom:     parent.bottom
                anchors.margins:    tile.isMain ? root._margin : root._margin / 2
                spacing:            root._margin / 2
                visible:            !root.compact && !!tile.stream && tile.stream.decoding

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
