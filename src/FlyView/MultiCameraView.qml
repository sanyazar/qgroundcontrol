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
    /// Free corner of the main (full size) camera for its name and buttons, clear of the Fly View's toolbar
    /// and tool strip; FlyView sets it.
    property real mainOverlayLeft:  _margin
    property real mainOverlayTop:   _margin
    /// Free band at the right edge of the main camera for its button column, clear of the Fly View's
    /// instrument panels; FlyView sets it.
    property real mainControlsRight:    _margin
    property real mainControlsTop:      _margin
    property real mainControlsBottom:   height - _margin

    /// A camera block other than the main one was clicked; it is now the main camera.
    signal cameraSelected()

    readonly property var  _multiCamera:    QGroundControl.videoManager.multiCamera
    readonly property int  _streamCount:    _multiCamera ? _multiCamera.streams.count : 0
    readonly property int  _mainIndex:      _multiCamera ? _multiCamera.mainIndex : -1
    readonly property real _margin:         ScreenTools.defaultFontPixelWidth
    /// Number of camera blocks in stripHost (every camera except the main one).
    readonly property int  stripCount:      stripHost ? Math.max(0, _streamCount - 1) : 0
    readonly property real _buttonSize:     ScreenTools.defaultFontPixelHeight * 2
    readonly property real _stripButtonSize: ScreenTools.defaultFontPixelHeight * 1.3

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

    Component {
        id: streamWindowComponent

        MultiCameraStreamWindow { }
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
                readonly property bool showsFullControls: isMain && !root.compact
                /// The separate window this stream is shown in, or null.
                property var streamWindow: null

                function openWindow() {
                    if (tile.streamWindow) {
                        tile.streamWindow.raise()
                        tile.streamWindow.requestActivate()
                        return
                    }
                    const popup = streamWindowComponent.createObject(null, { stream: tile.stream })
                    if (!popup) {
                        console.warn("MultiCameraView: could not open the stream window")
                        return
                    }
                    popup.videoReleased.connect(tile._windowClosed)
                    tile.streamWindow = popup
                }

                function _windowClosed() {
                    const popup = tile.streamWindow
                    tile.streamWindow = null
                    if (tile.stream) {
                        tile.stream.attachVideoOutput(videoOutput)
                    }
                    if (popup) {
                        popup.destroy()
                    }
                }

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
                    visible:            !tile.streamWindow && !(tile.stream && tile.stream.decoding)
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

                QGCLabel {
                    anchors.centerIn:       parent
                    width:                  parent.width - root._margin * 2
                    horizontalAlignment:    Text.AlignHCenter
                    wrapMode:               Text.WordWrap
                    visible:                !!tile.streamWindow
                    text:                   qsTr("Shown in a separate window")
                    color:                  "white"
                    font.pointSize:         ScreenTools.smallFontPointSize
                }

                // Camera name in the top left corner of the main video (clear of the toolbar and tool strip)
                // and of every block; the buttons are a column at the right of the main video and a row at the
                // bottom of a block.
                // In the picture-in-picture block the top corners hold its own buttons, so there it goes bottom right.
                MultiCameraStreamLabel {
                    id:                     nameLabel
                    x:                      tile.showsFullControls ? root.mainOverlayLeft
                                                                   : (tile.isMain ? tile.width - width : 0)
                    y:                      tile.showsFullControls ? root.mainOverlayTop
                                                                   : (tile.isMain ? tile.height - height : 0)
                    stream:                 tile.stream
                    small:                  !tile.showsFullControls
                    maximumWidth:           tile.showsFullControls ? tile.width / 3 : tile.width - root._margin * 2
                }

                // Main video: a column at the right edge, centred in the band between the instrument panels.
                MultiCameraStreamControls {
                    x:                      tile.width - root.mainControlsRight - width
                    y:                      Math.max(root.mainControlsTop,
                                                     (root.mainControlsTop + root.mainControlsBottom - height) / 2)
                    visible:                tile.showsFullControls
                    vertical:               true
                    stream:                 tile.stream
                    buttonSize:             root._buttonSize
                    showHide:               true
                }

                MultiCameraStreamControls {
                    anchors.left:           parent.left
                    anchors.bottom:         parent.bottom
                    anchors.margins:        root._margin / 2
                    visible:                tile.inStrip
                    stream:                 tile.stream
                    buttonSize:             root._stripButtonSize
                    showPhoto:              false
                    showTalk:               false
                    showWindow:             true
                    showHide:               true
                    onOpenWindowClicked:    tile.openWindow()
                }

                Component.onCompleted: {
                    if (stream) {
                        stream.attachVideoOutput(videoOutput)
                    }
                }

                // The receiver renders into videoOutput (or the window's), so it has to go first.
                Component.onDestruction: {
                    if (tile.streamWindow) {
                        const popup = tile.streamWindow
                        tile.streamWindow = null
                        popup.videoReleased.disconnect(tile._windowClosed)
                        popup.releaseVideo()
                        popup.destroy()
                    }
                    if (stream) {
                        stream.detachVideoOutput(videoOutput)
                    }
                }
            }
        }
    }
}
