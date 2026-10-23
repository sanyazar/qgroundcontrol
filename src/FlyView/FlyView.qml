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

    // Area of the PiP block plus the camera block row, in the coordinates of an item at (originX, originY),
    // so the widget layer keeps its controls clear of both.
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
        if (right < left) {
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

            readonly property bool _cameraOverlayClear: QGroundControl.videoManager.fullScreen ||
                                                        pipState.state !== pipState.fullState

            // Clicking a camera block shows that camera full size, also when the map was the full item.
            onCameraSelected: {
                if (_mainWindowIsMap) {
                    _pipView._swapPip()
                }
            }
        }

        PipView {
            id:                     _pipView
            objectName:             "flyViewPipView"
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  _mapControl
            item2:                  _videoAvailable ? videoControl : null
            show:                   _videoAvailable && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState ||
                                         (_mapControl && _mapControl.pipState.state === _mapControl.pipState.pipState))
            z:                      QGroundControl.zOrderWidgets
        }

        // Multi-camera mode: one block per camera that is not the selected one, in a row next to the
        // PiP block (which holds the map or the selected camera), so every camera and the map stay visible.
        Item {
            id:                     cameraStrip
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.margins:        _toolsMargin
            // Right of the PiP block, or of its restore button while the block is collapsed.
            anchors.leftMargin:     _toolsMargin + (_pipView.visible ? _pipView.occupiedRect.x + _pipView.occupiedRect.width + _toolsMargin : 0)
            width:                  count > 0 ? count * tileWidth + (count - 1) * _toolsMargin : 0
            height:                 count > 0 ? tileWidth * 9 / 16 : 0
            visible:                count > 0 && !QGroundControl.videoManager.fullScreen
            z:                      QGroundControl.zOrderWidgets

            readonly property int  count:       videoControl.cameraStripCount
            // Same size as the PiP block, shrunk when the row would run past three quarters of the view.
            readonly property real _pipWidth:   _pipView.visible ? _pipView.width : _root.width * 0.2
            readonly property real _room:       _root.width * 0.75 - x
            readonly property real tileWidth:   count > 0 ? Math.max(ScreenTools.defaultFontPixelHeight * 6,
                                                                     Math.min(_pipWidth, (_room - (count - 1) * _toolsMargin) / count))
                                                          : _pipWidth
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
