import QtQuick
import QtQuick.Controls
import QtMultimedia

import QGroundControl
import QGroundControl.Controls

// One tile per MultiCameraManager stream. The selected (main) camera fills this item, which FlyView shows full
// screen or in the picture-in-picture block. Every other camera is a block of its own in stripHost: by default
// in a column next to the PiP block, and each block can be dragged anywhere and resized (remembered per camera).
// A camera shown in a separate window leaves its block until the window closes. Each tile keeps its VideoOutput
// for its whole life, so switching cameras only moves tiles and never restarts a stream.
Item {
    id: root

    property bool compact: false        ///< true: this item is in the PiP block; main tile without controls
    /// FlyView-level item covering the Fly View that holds the camera blocks. It describes the default column:
    /// columnX, columnStart (edge next to the PiP block), columnUp (the column grows upwards from columnStart),
    /// and the band the blocks are kept in: blocksTop, blocksBottom.
    property Item stripHost: null
    property real stripTileWidth: ScreenTools.defaultFontPixelHeight * 10
    property real stripSpacing: ScreenTools.defaultFontPixelWidth * 0.75
    /// Free corner of the main (full size) camera for its name, clear of the Fly View's toolbar and tool strip;
    /// FlyView sets it.
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
    readonly property real _buttonSize:     ScreenTools.defaultFontPixelHeight * 2
    readonly property real _stripButtonSize: ScreenTools.defaultFontPixelHeight * 1.3
    readonly property real _handleSize:     ScreenTools.defaultFontPixelHeight * 2

    /// Stream keys whose block is not in the default column: placed by the user or shown in a window.
    property var _offColumn: ({})

    /// Number of camera blocks in the default column.
    readonly property int stripCount: _columnCount(_offColumn, _streamCount, _mainIndex)

    function _setOffColumn(key, off) {
        if (!!_offColumn[key] === off) {
            return
        }
        const copy = Object.assign({}, _offColumn)
        if (off) {
            copy[key] = true
        } else {
            delete copy[key]
        }
        _offColumn = copy
    }

    function _inColumn(index, offColumn, mainIndex) {
        if (!_multiCamera || index === mainIndex) {
            return false
        }
        const stream = _multiCamera.streams.get(index)
        return !!stream && !offColumn[stream.key]
    }

    function _columnCount(offColumn, streamCount, mainIndex) {
        let count = 0
        for (let i = 0; i < streamCount; i++) {
            if (_inColumn(i, offColumn, mainIndex)) {
                count++
            }
        }
        return count
    }

    function _columnSlot(index, offColumn, mainIndex) {
        let slot = 0
        for (let i = 0; i < index; i++) {
            if (_inColumn(i, offColumn, mainIndex)) {
                slot++
            }
        }
        return slot
    }

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
                readonly property bool inStrip:     !isMain && !!root.stripHost
                readonly property bool showsFullControls: isMain && !root.compact
                /// The separate window this stream is shown in, or null.
                property var streamWindow: null

                // Block placement: in the default column, or where the user dragged it (left/top as fractions
                // of the Fly View, so it stays inside on a resize) with its own width.
                property bool placed:       false
                property real placedX:      0
                property real placedY:      0
                property real placedWidth:  root.stripTileWidth

                readonly property string _placementKey: stream ? "MultiCameraBlock_" + stream.key : ""
                readonly property real   _blockWidth:   placed ? placedWidth : root.stripTileWidth
                readonly property real   _blockHeight:  _blockWidth * 9 / 16
                readonly property int    _slot:         root._columnSlot(index, root._offColumn, root._mainIndex)
                readonly property real   _top:          root.stripHost ? root.stripHost.blocksTop : 0
                readonly property real   _bottom:       root.stripHost ? root.stripHost.blocksBottom : 0
                readonly property real   _columnY:      !root.stripHost ? 0
                                                            : (root.stripHost.columnUp
                                                               ? root.stripHost.columnStart - (_slot + 1) * _blockHeight - _slot * root.stripSpacing
                                                               : root.stripHost.columnStart + _slot * (_blockHeight + root.stripSpacing))

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
                    root._setOffColumn(tile.stream.key, true)
                }

                function _windowClosed() {
                    const popup = tile.streamWindow
                    tile.streamWindow = null
                    if (tile.stream) {
                        root._setOffColumn(tile.stream.key, tile.placed)
                        tile.stream.attachVideoOutput(videoOutput)
                    }
                    if (popup) {
                        popup.destroy()
                    }
                }

                /// Takes the block out of the column at its current place, before it is dragged or resized.
                function _place() {
                    if (tile.placed || !root.stripHost) {
                        return
                    }
                    tile.placedX = tile.x / Math.max(1, root.stripHost.width)
                    tile.placedY = tile.y / Math.max(1, root.stripHost.height)
                    tile.placedWidth = tile.width
                    tile.placed = true
                    root._setOffColumn(tile.stream.key, true)
                }

                function _savePlacement() {
                    if (tile.placed) {
                        QGroundControl.saveGlobalSetting(tile._placementKey,
                                                         [tile.placedX, tile.placedY, tile.placedWidth].join(";"))
                    }
                }

                /// Back into the default column.
                function _unplace() {
                    tile.placed = false
                    QGroundControl.saveGlobalSetting(tile._placementKey, "")
                    root._setOffColumn(tile.stream.key, !!tile.streamWindow)
                }

                function _loadPlacement() {
                    const parts = QGroundControl.loadGlobalSetting(tile._placementKey, "").split(";").map(Number)
                    if (parts.length === 3 && parts.every(isFinite) && parts[2] > 0) {
                        tile.placedX = parts[0]
                        tile.placedY = parts[1]
                        tile.placedWidth = parts[2]
                        tile.placed = true
                        root._setOffColumn(tile.stream.key, true)
                    }
                }

                parent:         inStrip ? root.stripHost : root
                anchors.fill:   isMain ? parent : undefined
                x:              !inStrip ? 0
                                         : (placed ? Math.max(0, Math.min(placedX * root.stripHost.width, root.stripHost.width - width))
                                                   : root.stripHost.columnX)
                y:              !inStrip ? 0
                                         : (placed ? Math.max(_top, Math.min(placedY * root.stripHost.height, _bottom - height))
                                                   : _columnY)
                width:          inStrip ? _blockWidth : 0
                height:         inStrip ? _blockHeight : 0
                visible:        isMain || (inStrip && !streamWindow)

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
                    id:             tileMouseArea
                    anchors.fill:   parent
                    hoverEnabled:   tile.inStrip
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
                    visible:                tile.isMain && !!tile.streamWindow
                    text:                   qsTr("Shown in a separate window")
                    color:                  "white"
                    font.pointSize:         ScreenTools.smallFontPointSize
                }

                // Camera name in the top left corner of the main video (clear of the toolbar and tool strip)
                // and of every block. In the picture-in-picture block the top corners hold its own buttons, so
                // there it goes bottom right.
                MultiCameraStreamLabel {
                    id:                     nameLabel
                    x:                      tile.showsFullControls ? root.mainOverlayLeft
                                                                   : (tile.isMain ? tile.width - width : 0)
                    y:                      tile.showsFullControls ? root.mainOverlayTop
                                                                   : (tile.isMain ? tile.height - height : 0)
                    stream:                 tile.stream
                    small:                  !tile.showsFullControls
                    maximumWidth:           tile.showsFullControls ? tile.width / 3
                                                                   : tile.width - root._handleSize * 2 - root._margin
                }

                // Main video: a column at the right edge, centred in the band between the instrument panels.
                MultiCameraStreamControls {
                    id:                     mainControls
                    x:                      tile.width - root.mainControlsRight - width
                    y:                      Math.max(root.mainControlsTop,
                                                     (root.mainControlsTop + root.mainControlsBottom - height) / 2)
                    visible:                tile.showsFullControls
                    vertical:               true
                    stream:                 tile.stream
                    buttonSize:             root._buttonSize
                    showHide:               true
                }

                // Above the column: all preset cameras on their main (HD) or sub (SD) stream at once. Long press:
                // back to each camera's own setting.
                Rectangle {
                    anchors.bottom:             mainControls.top
                    anchors.bottomMargin:       mainControls.spacing * 2
                    anchors.horizontalCenter:   mainControls.horizontalCenter
                    width:                      root._buttonSize
                    height:                     width
                    radius:                     width / 2
                    color:                      Qt.rgba(0, 0, 0, 0.6)
                    border.color:               "white"
                    border.width:               root._multiCamera && root._multiCamera.streamQuality !== "" ? 1 : 0
                    visible:                    tile.showsFullControls && !!root._multiCamera && root._multiCamera.hasPresetStreams

                    readonly property string _quality: root._multiCamera ? root._multiCamera.streamQuality : ""

                    QGCLabel {
                        anchors.centerIn:   parent
                        text:               parent._quality === "main" ? "HD" : (parent._quality === "sub" ? "SD" : "HD/SD")
                        color:              "white"
                        font.bold:          true
                        font.pointSize:     parent._quality === "" ? ScreenTools.smallFontPointSize * 0.8
                                                                   : ScreenTools.smallFontPointSize
                    }

                    MouseArea {
                        id:             qualityArea
                        anchors.fill:   parent
                        hoverEnabled:   true
                        onClicked:      root._multiCamera.streamQuality = (parent._quality === "main" ? "sub" : "main")
                        onPressAndHold: root._multiCamera.streamQuality = ""
                    }

                    ToolTip.visible:    qualityArea.containsMouse
                    ToolTip.delay:      600
                    ToolTip.text: (_quality === "main" ? qsTr("All cameras on the main stream; click for the sub stream")
                                   : _quality === "sub" ? qsTr("All cameras on the sub stream; click for the main stream")
                                   : qsTr("Each camera on its own stream setting; click for the main stream"))
                                  + "\n" + qsTr("Long press: each camera's own setting")
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

                // Drag handle (top centre): moves the block anywhere; double-click puts it back in the column.
                Rectangle {
                    id:                         moveHandle
                    anchors.top:                parent.top
                    anchors.horizontalCenter:   parent.horizontalCenter
                    width:                      root._handleSize * 1.25
                    height:                     root._handleSize * 0.6
                    radius:                     height / 4
                    color:                      Qt.rgba(0, 0, 0, 0.6)
                    visible:                    tile.inStrip && (ScreenTools.isMobile || tileMouseArea.containsMouse ||
                                                                 moveArea.pressed || resizeArea.pressed)

                    Grid {
                        anchors.centerIn:   parent
                        columns:            3
                        spacing:            ScreenTools.defaultFontPixelHeight * 0.2

                        Repeater {
                            model: 6

                            Rectangle {
                                width:  ScreenTools.defaultFontPixelHeight * 0.2
                                height: width
                                radius: width / 2
                                color:  "white"
                            }
                        }
                    }

                    MouseArea {
                        id:                 moveArea
                        anchors.fill:       parent
                        preventStealing:    true
                        cursorShape:        Qt.SizeAllCursor

                        property point _last

                        onPressed: (mouse) => {
                            tile._place()
                            moveArea._last = moveArea.mapToItem(root.stripHost, mouse.x, mouse.y)
                        }
                        onPositionChanged: (mouse) => {
                            if (!moveArea.pressed) {
                                return
                            }
                            const position = moveArea.mapToItem(root.stripHost, mouse.x, mouse.y)
                            const host = root.stripHost
                            const newX = Math.max(0, Math.min(tile.x + position.x - moveArea._last.x, host.width - tile.width))
                            const newY = Math.max(tile._top, Math.min(tile.y + position.y - moveArea._last.y, tile._bottom - tile.height))
                            tile.placedX = newX / Math.max(1, host.width)
                            tile.placedY = newY / Math.max(1, host.height)
                            moveArea._last = position
                        }
                        onReleased:         tile._savePlacement()
                        onCanceled:         tile._savePlacement()
                        onDoubleClicked:    tile._unplace()
                    }
                }

                // Resize handle (top right), like the PiP block's: keeps the top left corner in place.
                Image {
                    id:                 resizeIcon
                    anchors.right:      parent.right
                    anchors.top:        parent.top
                    width:              root._handleSize
                    height:             width
                    sourceSize.height:  height
                    source:             "/qmlimages/pipResize.svg"
                    fillMode:           Image.PreserveAspectFit
                    mipmap:             true
                    visible:            moveHandle.visible
                }

                MouseArea {
                    id:                 resizeArea
                    anchors.fill:       resizeIcon
                    enabled:            tile.inStrip
                    preventStealing:    true
                    cursorShape:        Qt.SizeFDiagCursor

                    property real _startX:      0
                    property real _startWidth:  0

                    onPressed: (mouse) => {
                        tile._place()
                        resizeArea._startX = resizeArea.mapToItem(root.stripHost, mouse.x, mouse.y).x
                        resizeArea._startWidth = tile.width
                    }
                    onPositionChanged: (mouse) => {
                        if (!resizeArea.pressed) {
                            return
                        }
                        const x = resizeArea.mapToItem(root.stripHost, mouse.x, mouse.y).x
                        const maxWidth = Math.min(root.stripHost.width * 0.75, root.stripHost.width - tile.x,
                                                  (tile._bottom - tile.y) * 16 / 9)
                        tile.placedWidth = Math.max(ScreenTools.defaultFontPixelHeight * 6,
                                                    Math.min(maxWidth, resizeArea._startWidth + x - resizeArea._startX))
                    }
                    onReleased: tile._savePlacement()
                    onCanceled: tile._savePlacement()
                }

                Component.onCompleted: {
                    _loadPlacement()
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
                        root._setOffColumn(stream.key, false)
                        stream.detachVideoOutput(videoOutput)
                    }
                }
            }
        }
    }
}
