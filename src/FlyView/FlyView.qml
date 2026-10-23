import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

Item {
    id: _root

    readonly property bool _is3DMode:       QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    property bool   _mainWindowIsMap:       _mapControl ? _mapControl.pipState.state === _mapControl.pipState.fullState : true
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? (_mapControl ? _mapControl.isSatelliteMap : true) : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property bool   _videoAvailable:        QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.multiCamera.enabled
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapEngineLoader.item
    property real   _widgetMargin:          ScreenTools.defaultFontPixelWidth * 0.75
    property var    _layerOccluders:        widgetLayer.occluders
    property var    _mapOccluders:          _layerOccluders.all.concat(customOverlay.customOccluders).map(r => Qt.rect(r.x + widgetLayer.x, r.y + widgetLayer.y, r.width, r.height))

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    readonly property var  _multiCamera:        QGroundControl.videoManager.multiCamera
    readonly property int  _hiddenCameraCount:  _multiCamera && _multiCamera.enabled ? _multiCamera.hiddenStreams.length : 0
    /// The camera blocks show with the PiP block: not in full screen, not while the PiP is collapsed.
    readonly property bool _blocksShown:        !QGroundControl.videoManager.fullScreen && (!_pipView.visible || _pipView.isExpanded)

    // Place of the PiP/camera-block group (see _pipView): 0..1 of the free room, default bottom left.
    readonly property string _blocksFxSettingsKey: "FlyViewBlocksX"
    readonly property string _blocksFySettingsKey: "FlyViewBlocksY"
    property real _blocksFx: Number(QGroundControl.loadGlobalSetting(_blocksFxSettingsKey, "0"))
    property real _blocksFy: Number(QGroundControl.loadGlobalSetting(_blocksFySettingsKey, "1"))
    readonly property real _blocksTop: toolbar.height + _toolsMargin
    /// Full width of the group, so it can be kept inside the view.
    readonly property real _blocksWidth: (_pipView.visible ? _pipView.width : 0) +
                                         (cameraStrip.count > 0 ? cameraStrip.width + _toolsMargin : 0) +
                                         (_hiddenCameraCount > 0 ? hiddenCamerasButton.width + _toolsMargin : 0)

    // Area of the PiP block, the camera block row and the hidden-cameras button, in the coordinates of an item
    // at (originX, originY), so the widget layer keeps its controls (e.g. the tool strip's height) clear of them.
    // Once the group is moved to the upper half it no longer limits the layer.
    function _bottomLeftBlocksRect(originX, originY, emptyY) {
        var left = Number.MAX_VALUE, top = Number.MAX_VALUE, right = -Number.MAX_VALUE, bottom = -Number.MAX_VALUE
        if (_pipView.visible) {
            left = _pipView.x + _pipView.occupiedRect.x
            top = _pipView.y + _pipView.occupiedRect.y
            right = left + _pipView.occupiedRect.width
            bottom = top + _pipView.occupiedRect.height
        }
        if (cameraStrip.visible) {
            left = Math.min(left, cameraStrip.x)
            top = Math.min(top, cameraStrip.y)
            right = Math.max(right, cameraStrip.x + cameraStrip.width)
            bottom = Math.max(bottom, cameraStrip.y + cameraStrip.height)
        }
        if (hiddenCamerasButton.visible) {
            left = Math.min(left, hiddenCamerasButton.x)
            top = Math.min(top, hiddenCamerasButton.y)
            right = Math.max(right, hiddenCamerasButton.x + hiddenCamerasButton.width)
            bottom = Math.max(bottom, hiddenCamerasButton.y + hiddenCamerasButton.height)
        }
        if ((right < left) || (top < _root.height / 2)) {
            return Qt.rect(0, emptyY, 0, 0)
        }
        return Qt.rect(left - originX, top - originY, right - left, bottom - top)
    }

    function dropMainStatusIndicatorTool(showMessages = false) {
        toolbar.dropMainStatusIndicatorTool(showMessages);
    }

    Item {
        id:                 mapHolder
        anchors.fill:       parent

        // Map engine switch (issue #14901): QtLocation FlyViewMap or the
        // experimental GeoMap engine, only one instantiated at a time. The
        // loaded item is positioned/reparented by its PipState, not the Loader.
        // Engine choice is snapshotted at startup (setting is
        // qgcRebootRequired): a live swap would leave stale cross-map state
        // (guided controller registrations, ROI coordinate).
        Loader {
            id: mapEngineLoader
            Component.onCompleted: sourceComponent = QGroundControl.settingsManager.flyViewSettings.useGeoMapEngine.rawValue ? geoMapEngineComponent : qtLocationEngineComponent
        }

        Component {
            id: qtLocationEngineComponent

            FlyViewMap {
                objectName:             "flyViewMap"
                planMasterController:   _planController
                rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
                pipView:                _pipView
                pipMode:                !_mainWindowIsMap
                viewportRect:           Qt.rect(widgetLayer.x, widgetLayer.y, widgetLayer.width, widgetLayer.height)
                occluders:              _mapOccluders
                mapName:                "FlightDisplayView"
                enabled:                !_is3DMode
                visible:                !_is3DMode
            }
        }

        Component {
            id: geoMapEngineComponent

            FlyViewGeoMapAdapter {
                objectName:             "flyViewGeoMapAdapter"
                planMasterController:   _planController
                rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
                pipView:                _pipView
                pipMode:                !_mainWindowIsMap
                viewportRect:           Qt.rect(widgetLayer.x, widgetLayer.y, widgetLayer.width, widgetLayer.height)
                occluders:              _mapOccluders
                chromeTopMargin:        widgetLayer.y + _layerOccluders.topRight.y + _layerOccluders.topRight.height + _widgetMargin
                chromeBottomMargin:     mapHolder.height - widgetLayer.y - Math.min(_layerOccluders.pipView.y, _layerOccluders.virtualJoystickLeft.y) + ScreenTools.defaultFontPixelWidth / 2
                mapName:                "FlightDisplayView"
                enabled:                !_is3DMode
                visible:                !_is3DMode
            }
        }

        FlyViewVideo {
            id:                     videoControl
            pipView:                _pipView
            cameraStripHost:        cameraStrip
            cameraStripTileWidth:   cameraStrip.tileWidth
            // Right of the tool strip and below the toolbar while the video is the full size item with the
            // Fly View controls over it; the plain corner otherwise (full screen, own window).
            cameraOverlayLeft:      _cameraOverlayClear ? _toolsMargin
                                                        : widgetLayer.x + _layerOccluders.toolStrip.x + _layerOccluders.toolStrip.width + _toolsMargin
            cameraOverlayTop:       _cameraOverlayClear ? _toolsMargin : widgetLayer.y
            // Between the top right and bottom right instrument panels, left of the guided value slider.
            cameraControlsRight:    _cameraOverlayClear ? _toolsMargin
                                                        : width - (widgetLayer.x + widgetLayer.width) + _toolsMargin
            cameraControlsTop:      _cameraOverlayClear ? _toolsMargin
                                                        : widgetLayer.y + _layerOccluders.topRight.y + _layerOccluders.topRight.height + _toolsMargin
            cameraControlsBottom:   _cameraOverlayClear ? height - _toolsMargin
                                                        : widgetLayer.y + _layerOccluders.bottomRight.y - _toolsMargin

            readonly property bool _cameraOverlayClear: QGroundControl.videoManager.fullScreen ||
                                                        pipState.state !== pipState.fullState

            // Clicking a camera block shows that camera full size, also when the map was the full item.
            onCameraSelected: {
                if (_mainWindowIsMap) {
                    _pipView._swapPip()
                }
            }
        }

        // The PiP block, the camera blocks and the hidden-cameras button form one group, at the bottom left by
        // default. The PiP's drag handle moves the group anywhere; its place is kept as fractions of the free room
        // so it survives window resizes.
        PipView {
            id:                     _pipView
            objectName:             "flyViewPipView"
            x:                      _toolsMargin + _blocksFx * Math.max(0, _root.width - _blocksWidth - _toolsMargin * 2)
            y:                      _blocksTop + _blocksFy * Math.max(0, _root.height - height - _toolsMargin - _blocksTop)
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  _mapControl
            item2:                  _videoAvailable ? videoControl : null
            show:                   _videoAvailable && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState ||
                                         (_mapControl && _mapControl.pipState.state === _mapControl.pipState.pipState))
            movable:                true
            z:                      QGroundControl.zOrderWidgets

            onMoveBy: (dx, dy) => {
                const rangeX = _root.width - _blocksWidth - _toolsMargin * 2
                const rangeY = _root.height - height - _toolsMargin - _blocksTop
                if (rangeX > 0) {
                    _blocksFx = Math.min(1, Math.max(0, _blocksFx + dx / rangeX))
                }
                if (rangeY > 0) {
                    _blocksFy = Math.min(1, Math.max(0, _blocksFy + dy / rangeY))
                }
            }
            onMoveFinished: {
                QGroundControl.saveGlobalSetting(_blocksFxSettingsKey, String(_blocksFx))
                QGroundControl.saveGlobalSetting(_blocksFySettingsKey, String(_blocksFy))
            }
        }

        // Multi-camera mode: one block per camera that is not the selected one, in a row next to the
        // PiP block (which holds the map or the selected camera), so every camera and the map stay visible.
        // Hidden with the PiP block when that is collapsed.
        Item {
            id:                     cameraStrip
            // Right of the PiP block, or of its restore button while the block is collapsed; bottoms aligned.
            x:                      _pipView.x + (_pipView.visible ? _pipView.occupiedRect.x + _pipView.occupiedRect.width + _toolsMargin : 0)
            y:                      _pipView.y + _pipView.height - height
            width:                  count > 0 ? count * tileWidth + (count - 1) * _toolsMargin : 0
            height:                 count > 0 ? tileWidth * 9 / 16 : 0
            visible:                count > 0 && _blocksShown
            z:                      QGroundControl.zOrderWidgets

            readonly property int  count:       videoControl.cameraStripCount
            // Same size as the PiP block, shrunk when the row would run past three quarters of the view.
            readonly property real _pipWidth:   _pipView.visible ? _pipView.width : _root.width * 0.2
            readonly property real _room:       _root.width * 0.75 - _pipWidth - _toolsMargin
            readonly property real tileWidth:   count > 0 ? Math.max(ScreenTools.defaultFontPixelHeight * 6,
                                                                     Math.min(_pipWidth, (_room - (count - 1) * _toolsMargin) / count))
                                                          : _pipWidth
        }

        // Cameras removed from the view: shows how many, and a menu to bring each one (or all) back.
        Rectangle {
            id:             hiddenCamerasButton
            x:              cameraStrip.visible ? cameraStrip.x + cameraStrip.width + _toolsMargin
                                                : _pipView.x + (_pipView.visible ? _pipView.occupiedRect.x + _pipView.occupiedRect.width + _toolsMargin : 0)
            y:              _pipView.y + _pipView.height - height
            width:          hiddenCamerasRow.width + ScreenTools.defaultFontPixelWidth * 1.5
            height:         ScreenTools.defaultFontPixelHeight * 2
            radius:         height / 2
            color:          Qt.rgba(0, 0, 0, 0.6)
            visible:        _hiddenCameraCount > 0 && _blocksShown
            z:              QGroundControl.zOrderWidgets

            Row {
                id:                 hiddenCamerasRow
                anchors.centerIn:   parent
                spacing:            ScreenTools.defaultFontPixelWidth / 2

                QGCColoredImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width:                  ScreenTools.defaultFontPixelHeight * 1.2
                    height:                 width
                    sourceSize.height:      height
                    source:                 "/InstrumentValueIcons/view-hide.svg"
                    color:                  "white"
                }

                QGCLabel {
                    anchors.verticalCenter: parent.verticalCenter
                    text:                   _hiddenCameraCount
                    color:                  "white"
                    font.bold:              true
                }
            }

            MouseArea {
                anchors.fill:   parent
                onClicked:      hiddenCamerasMenu.popup()
            }

            QGCMenu {
                id: hiddenCamerasMenu

                Instantiator {
                    model: _multiCamera ? _multiCamera.hiddenStreams : []

                    QGCMenuItem {
                        text:           qsTr("Show %1").arg(modelData.label)
                        onTriggered:    _multiCamera.showStream(modelData.key)
                    }

                    onObjectAdded:      (index, object) => hiddenCamerasMenu.insertItem(index, object)
                    onObjectRemoved:    (index, object) => hiddenCamerasMenu.removeItem(object)
                }

                QGCMenuSeparator { }

                QGCMenuItem {
                    text:           qsTr("Show all cameras")
                    onTriggered:    _multiCamera.showAllStreams()
                }
            }
        }

        FlyViewWidgetLayer {
            id:                     widgetLayer
            objectName:             "flyViewWidgetLayer"
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _widgetMargin
            anchors.topMargin:      toolbar.height + _widgetMargin
            z:                      _fullItemZorder + 2
            pipViewRect:            _bottomLeftBlocksRect(x, y, height)
            mapControl:             _mapControl
            viewer3DCameraController: viewer3DLoader.item ? viewer3DLoader.item.cameraController : null
            visible:                !QGroundControl.videoManager.fullScreen
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            occluders:          _layerOccluders
            mapControl:         _mapControl
            visible:            !QGroundControl.videoManager.fullScreen
        }

        // Development tool for visualizing the occluders, show if needed
        FlyViewOccluderViewer {
            id:                     occluderViewer
            anchors.fill:           widgetLayer
            z:                      widgetLayer.z + 1
            occluders:              _layerOccluders
            customOccluders:        customOverlay.customOccluders
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:     _guidedValueSlider
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            objectName:         "guidedValueSlider"
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  toolbar.height
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        Loader {
            id:           viewer3DLoader
            z:            1
            anchors.fill: parent
            visible:      _is3DMode
        }

        Connections {
            target: QGCViewer3DManager
            function onDisplayModeChanged() {
                if (QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D) {
                    if (!viewer3DLoader.item) {
                        viewer3DLoader.setSource("qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml")
                    }
                } else if (!_keepSceneAlive) {
                    viewer3DLoader.source = ""
                }
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        guidedValueSlider:  _guidedValueSlider
        visible:            !QGroundControl.videoManager.fullScreen
    }
}
