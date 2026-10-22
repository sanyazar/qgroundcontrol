import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

QGCGroupBox {
    id: _root

    Layout.fillWidth: true
    heading: qsTr("Manual Camera Streams")
    headingDescription: qsTr("Streams listed here are shown in addition to MAVLink camera streams. "
                             + "Vehicle ID is the MAVLink system ID (0: not tied to a vehicle). "
                             + "URL examples: rtsp://192.168.1.10:8554/main, udp://0.0.0.0:5600, "
                             + "udp265://0.0.0.0:5601, mpegts://0.0.0.0:5602, tcp://192.168.1.10:5000")

    property Fact _streamsFact: QGroundControl.settingsManager.videoSettings.multiCameraStreams
    property var _entries: []

    function _load() {
        var parsed = []
        try {
            parsed = JSON.parse(_streamsFact.rawValue)
        } catch (e) {
            console.warn("Invalid multiCameraStreams JSON, resetting:", e)
        }
        _entries = Array.isArray(parsed) ? parsed : []
    }

    function _save() {
        _streamsFact.rawValue = JSON.stringify(_entries)
    }

    function _setField(index, field, value) {
        if (_entries[index][field] === value) {
            return
        }
        var copy = _entries.slice()
        copy[index] = Object.assign({}, copy[index])
        copy[index][field] = value
        _entries = copy
        _save()
    }

    function _add() {
        var copy = _entries.slice()
        copy.push({ vehicleId: 1, name: qsTr("Camera %1").arg(copy.length + 1), uri: "" })
        _entries = copy
        _save()
    }

    function _remove(index) {
        var copy = _entries.slice()
        copy.splice(index, 1)
        _entries = copy
        _save()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ScreenTools.defaultFontPixelWidth
        visible: _entries.length > 0

        QGCLabel {
            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
            text: qsTr("Vehicle ID")
        }
        QGCLabel {
            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
            text: qsTr("Name")
        }
        QGCLabel {
            Layout.fillWidth: true
            text: qsTr("Stream URL")
        }
        Item {
            Layout.preferredWidth: ScreenTools.minTouchPixels
        }
    }

    Repeater {
        model: _entries

        RowLayout {
            Layout.fillWidth: true
            spacing: ScreenTools.defaultFontPixelWidth

            required property var modelData
            required property int index

            QGCTextField {
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10
                text: modelData.vehicleId !== undefined ? String(modelData.vehicleId) : "0"
                numericValuesOnly: true
                validator: IntValidator { bottom: 0; top: 255 }
                onEditingFinished: _root._setField(index, "vehicleId", parseInt(text) || 0)
            }

            QGCTextField {
                Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 16
                text: modelData.name !== undefined ? modelData.name : ""
                onEditingFinished: _root._setField(index, "name", text.trim())
            }

            QGCTextField {
                Layout.fillWidth: true
                Layout.minimumWidth: ScreenTools.defaultFontPixelWidth * 30
                text: modelData.uri !== undefined ? modelData.uri : ""
                placeholderText: "rtsp://192.168.1.10:8554/main"
                onEditingFinished: _root._setField(index, "uri", text.trim())
            }

            QGCColoredImage {
                Layout.preferredWidth: ScreenTools.minTouchPixels
                Layout.preferredHeight: ScreenTools.minTouchPixels
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                mipmap: true
                smooth: true
                color: qgcPal.textPrimary
                source: "/res/TrashDelete.svg"

                QGCMouseArea {
                    fillItem: parent
                    onClicked: _root._remove(index)
                }
            }
        }
    }

    QGCButton {
        text: qsTr("Add Stream")
        onClicked: _root._add()
    }

    QGCPalette {
        id: qgcPal
        colorGroupEnabled: _root.enabled
    }

    Connections {
        target: _streamsFact
        function onRawValueChanged() {
            if (JSON.stringify(_root._entries) !== _root._streamsFact.rawValue) {
                _root._load()
            }
        }
    }

    Component.onCompleted: _load()
}
