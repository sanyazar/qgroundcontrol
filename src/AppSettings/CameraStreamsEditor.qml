import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Editable list of camera streams stored as a JSON array (see MultiCameraManager::manualStreamUri for
/// the entry format). Used for the global manual stream list and for the cameras of each comm link.
ColumnLayout {
    id: _root

    Layout.fillWidth: true
    spacing: ScreenTools.defaultFontPixelHeight / 2

    property string streamsJson: "[]"
    property bool showVehicleId: true
    property string addButtonText: qsTr("Add Camera")

    signal edited(string json)

    property var _multiCamera: QGroundControl.videoManager.multiCamera
    property var _entries: []

    readonly property var _types: [
        { value: "custom", text: qsTr("Custom URL") },
        { value: "dahua", text: "Dahua" },
        { value: "hikvision", text: "Hikvision" },
        { value: "unv", text: qsTr("Uniview (UNV)") }
    ]
    readonly property var _streamKinds: [
        { value: "main", text: qsTr("Main stream") },
        { value: "sub", text: qsTr("Sub stream") }
    ]
    readonly property real _fieldWidth: ScreenTools.defaultFontPixelWidth * 16

    function _load() {
        var parsed = []
        try {
            parsed = JSON.parse(streamsJson === "" ? "[]" : streamsJson)
        } catch (e) {
            console.warn("Invalid camera stream JSON, resetting:", e)
        }
        _entries = Array.isArray(parsed) ? parsed : []
    }

    function _save() {
        edited(JSON.stringify(_entries))
    }

    function _update(index, changes) {
        var copy = _entries.slice()
        copy[index] = Object.assign({}, copy[index], changes)
        if (JSON.stringify(copy[index]) === JSON.stringify(_entries[index])) {
            return
        }
        _entries = copy
        _save()
    }

    function _setType(index, type) {
        var entry = _entries[index]
        var changes = { type: type }
        if (type !== "custom") {
            // Vendor defaults: RTSP port 554, first channel, main stream.
            if (entry.port === undefined) {
                changes.port = 554
            }
            if (entry.channel === undefined) {
                changes.channel = 1
            }
            if (entry.stream === undefined) {
                changes.stream = "main"
            }
            if (entry.username === undefined) {
                changes.username = "admin"
            }
        }
        _update(index, changes)
    }

    function _add() {
        var copy = _entries.slice()
        var entry = { name: qsTr("Camera %1").arg(copy.length + 1), type: "custom", uri: "" }
        if (showVehicleId) {
            entry.vehicleId = 1
        }
        copy.push(entry)
        _entries = copy
        _save()
    }

    function _remove(index) {
        var copy = _entries.slice()
        copy.splice(index, 1)
        _entries = copy
        _save()
    }

    function _indexOf(list, value, fallback) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].value === value) {
                return i
            }
        }
        return fallback
    }

    Repeater {
        model: _entries

        Rectangle {
            id: entryCard

            Layout.fillWidth: true
            implicitHeight: entryLayout.implicitHeight + ScreenTools.defaultFontPixelHeight
            color: "transparent"
            border.color: qgcPal.borderSubtle
            radius: ScreenTools.defaultFontPixelWidth / 2

            required property var modelData
            required property int index

            readonly property string _type: modelData.type !== undefined ? modelData.type : "custom"
            readonly property bool _isPreset: _type !== "custom"

            ColumnLayout {
                id: entryLayout
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: ScreenTools.defaultFontPixelHeight / 2
                spacing: ScreenTools.defaultFontPixelHeight / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: ScreenTools.defaultFontPixelWidth

                    ColumnLayout {
                        visible: _root.showVehicleId
                        QGCLabel { text: qsTr("Vehicle ID") }
                        QGCTextField {
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                            text: entryCard.modelData.vehicleId !== undefined ? String(entryCard.modelData.vehicleId) : "0"
                            numericValuesOnly: true
                            validator: IntValidator { bottom: 0; top: 255 }
                            onEditingFinished: _root._update(entryCard.index, { vehicleId: parseInt(text) || 0 })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Name") }
                        QGCTextField {
                            Layout.preferredWidth: _root._fieldWidth
                            text: entryCard.modelData.name !== undefined ? entryCard.modelData.name : ""
                            onEditingFinished: _root._update(entryCard.index, { name: text.trim() })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Camera type") }
                        QGCComboBox {
                            Layout.preferredWidth: _root._fieldWidth
                            model: _root._types.map(function (t) { return t.text })
                            currentIndex: _root._indexOf(_root._types, entryCard._type, 0)
                            onActivated: (comboIndex) => _root._setType(entryCard.index, _root._types[comboIndex].value)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    QGCColoredImage {
                        Layout.alignment: Qt.AlignTop
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
                            onClicked: _root._remove(entryCard.index)
                        }
                    }
                }

                // Custom URL
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !entryCard._isPreset

                    QGCLabel { text: qsTr("Stream URL") }
                    QGCTextField {
                        Layout.fillWidth: true
                        text: entryCard.modelData.uri !== undefined ? entryCard.modelData.uri : ""
                        placeholderText: "rtsp://192.168.1.10:8554/main"
                        onEditingFinished: _root._update(entryCard.index, { uri: text.trim() })
                    }
                }

                // Camera preset
                Flow {
                    Layout.fillWidth: true
                    spacing: ScreenTools.defaultFontPixelWidth
                    visible: entryCard._isPreset

                    ColumnLayout {
                        QGCLabel { text: qsTr("Camera address") }
                        QGCTextField {
                            Layout.preferredWidth: _root._fieldWidth
                            text: entryCard.modelData.host !== undefined ? entryCard.modelData.host : ""
                            placeholderText: "192.168.1.64"
                            onEditingFinished: _root._update(entryCard.index, { host: text.trim() })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("RTSP port") }
                        QGCTextField {
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 8
                            text: entryCard.modelData.port !== undefined ? String(entryCard.modelData.port) : "554"
                            numericValuesOnly: true
                            validator: IntValidator { bottom: 1; top: 65535 }
                            onEditingFinished: _root._update(entryCard.index, { port: parseInt(text) || 554 })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Login") }
                        QGCTextField {
                            Layout.preferredWidth: _root._fieldWidth
                            text: entryCard.modelData.username !== undefined ? entryCard.modelData.username : ""
                            onEditingFinished: _root._update(entryCard.index, { username: text })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Password") }
                        QGCTextField {
                            Layout.preferredWidth: _root._fieldWidth
                            echoMode: TextInput.Password
                            text: entryCard.modelData.password !== undefined ? entryCard.modelData.password : ""
                            onEditingFinished: _root._update(entryCard.index, { password: text })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Channel") }
                        QGCTextField {
                            Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 6
                            text: entryCard.modelData.channel !== undefined ? String(entryCard.modelData.channel) : "1"
                            numericValuesOnly: true
                            validator: IntValidator { bottom: 1; top: 256 }
                            onEditingFinished: _root._update(entryCard.index, { channel: parseInt(text) || 1 })
                        }
                    }

                    ColumnLayout {
                        QGCLabel { text: qsTr("Stream") }
                        QGCComboBox {
                            Layout.preferredWidth: _root._fieldWidth
                            model: _root._streamKinds.map(function (k) { return k.text })
                            currentIndex: _root._indexOf(_root._streamKinds, entryCard.modelData.stream, 0)
                            onActivated: (comboIndex) => _root._update(entryCard.index, { stream: _root._streamKinds[comboIndex].value })
                        }
                    }
                }

                QGCLabel {
                    Layout.fillWidth: true
                    visible: entryCard._isPreset
                    readonly property string _preview: _root._multiCamera ? _root._multiCamera.manualStreamPreview(entryCard.modelData) : ""
                    text: _preview !== "" ? qsTr("Stream URL: %1").arg(_preview) : qsTr("Enter the camera address")
                    font.pointSize: ScreenTools.smallFontPointSize
                    wrapMode: Text.WrapAnywhere
                    color: qgcPal.textSecondary
                }
            }
        }
    }

    QGCButton {
        text: _root.addButtonText
        onClicked: _root._add()
    }

    QGCPalette {
        id: qgcPal
        colorGroupEnabled: _root.enabled
    }

    onStreamsJsonChanged: {
        if (JSON.stringify(_entries) !== streamsJson) {
            _load()
        }
    }

    Component.onCompleted: _load()
}
