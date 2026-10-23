import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

/// Settings of one camera's vehicle width guide lines (CameraGuidesOverlay), with a live preview. The guides
/// show on that camera's video while it is the main camera or in a separate window.
QGCPopupDialog {
    id: dialog

    buttons: Dialog.Save | Dialog.Cancel

    property int entryIndex: -1
    property var initialGuides: ({})

    /// Save was pressed: the new settings for the camera at @p index.
    signal guidesAccepted(int index, var guides)

    property var _guides: preview.withDefaults(initialGuides)
    readonly property real _fieldWidth: ScreenTools.defaultFontPixelWidth * 10

    function _set(key, value) {
        const copy = Object.assign({}, _guides)
        copy[key] = value
        _guides = copy
    }

    onAccepted: guidesAccepted(entryIndex, _guides)

    // A number field for one setting; empty or invalid input keeps the previous value. Inline components do not
    // see the dialog's ids, so the value comes in and the edit goes out through the instance.
    component NumberField: ColumnLayout {
        id: numberField

        property string label
        property real value: 0
        property real minimum: -1000
        property real maximum: 1000
        property real fieldWidth: ScreenTools.defaultFontPixelWidth * 10

        signal valueEdited(real newValue)

        QGCLabel { text: numberField.label }
        QGCTextField {
            Layout.preferredWidth: numberField.fieldWidth
            text: String(numberField.value)
            onEditingFinished: {
                const newValue = Number(text.replace(",", "."))
                if (isFinite(newValue) && newValue >= numberField.minimum && newValue <= numberField.maximum) {
                    numberField.valueEdited(newValue)
                } else {
                    text = String(numberField.value)
                }
            }
        }
    }

    RowLayout {
        spacing: ScreenTools.defaultFontPixelWidth * 2

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: ScreenTools.defaultFontPixelHeight / 2

            QGCLabel {
                text: qsTr("Vehicle")
                font.bold: true
            }
            GridLayout {
                columns: 2
                columnSpacing: ScreenTools.defaultFontPixelWidth

                NumberField { label: qsTr("Width, m"); minimum: 0.05; maximum: 20; value: dialog._guides.vehicleWidth; onValueEdited: (v) => dialog._set("vehicleWidth", v) }
                NumberField { label: qsTr("Lens to front, m"); minimum: 0; maximum: 20; value: dialog._guides.startDistance; onValueEdited: (v) => dialog._set("startDistance", v) }
            }

            QGCLabel {
                text: qsTr("Camera")
                font.bold: true
            }
            GridLayout {
                columns: 2
                columnSpacing: ScreenTools.defaultFontPixelWidth

                NumberField { label: qsTr("Height, m"); minimum: 0.01; maximum: 20; value: dialog._guides.cameraHeight; onValueEdited: (v) => dialog._set("cameraHeight", v) }
                NumberField { label: qsTr("Tilt down, °"); minimum: -45; maximum: 90; value: dialog._guides.cameraTilt; onValueEdited: (v) => dialog._set("cameraTilt", v) }
                NumberField { label: qsTr("Horizontal FOV, °"); minimum: 10; maximum: 170; value: dialog._guides.cameraFov; onValueEdited: (v) => dialog._set("cameraFov", v) }
                NumberField { label: qsTr("Offset right, m"); minimum: -10; maximum: 10; value: dialog._guides.cameraOffset; onValueEdited: (v) => dialog._set("cameraOffset", v) }
            }
            QGCCheckBox {
                text: qsTr("Mirrored picture (rear camera)")
                checked: dialog._guides.mirror === true
                onClicked: dialog._set("mirror", checked)
            }

            QGCLabel {
                text: qsTr("Lines")
                font.bold: true
            }
            ColumnLayout {
                QGCLabel { text: qsTr("Distance lines from the front, m") }
                QGCTextField {
                    Layout.preferredWidth: dialog._fieldWidth * 2
                    text: String(dialog._guides.distances)
                    placeholderText: "0.5, 1, 2, 3"
                    onEditingFinished: {
                        if (preview.parseDistances(text).length > 0) {
                            dialog._set("distances", text)
                        } else {
                            text = String(dialog._guides.distances)
                        }
                    }
                }
            }
            GridLayout {
                columns: 3
                columnSpacing: ScreenTools.defaultFontPixelWidth

                NumberField { label: qsTr("Shift right, %"); minimum: -50; maximum: 50; value: dialog._guides.shiftX; onValueEdited: (v) => dialog._set("shiftX", v) }
                NumberField { label: qsTr("Shift down, %"); minimum: -50; maximum: 50; value: dialog._guides.shiftY; onValueEdited: (v) => dialog._set("shiftY", v) }
                NumberField { label: qsTr("Line width"); minimum: 1; maximum: 20; value: dialog._guides.lineWidth; onValueEdited: (v) => dialog._set("lineWidth", v) }
            }
            QGCCheckBox {
                text: qsTr("Distance labels")
                checked: dialog._guides.showLabels !== false
                onClicked: dialog._set("showLabels", checked)
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop

            QGCLabel {
                text: qsTr("Preview")
                font.bold: true
            }

            // Sky and ground stand in for the picture; the horizon sits where the camera tilt puts it.
            Rectangle {
                id: previewFrame

                width: ScreenTools.defaultFontPixelWidth * 48
                height: width * 9 / 16
                clip: true
                color: "#1d2733"

                readonly property real _horizon: {
                    const fov = Math.max(10, Math.min(170, Number(dialog._guides.cameraFov)))
                    const focal = (width / 2) / Math.tan(fov * Math.PI / 360)
                    return height / 2 - focal * Math.tan(Number(dialog._guides.cameraTilt) * Math.PI / 180)
                           + Number(dialog._guides.shiftY) / 100 * height
                }

                Rectangle {
                    x: 0
                    y: Math.max(0, Math.min(previewFrame.height, previewFrame._horizon))
                    width: previewFrame.width
                    height: previewFrame.height - y
                    color: "#3b3f36"
                }

                CameraGuidesOverlay {
                    id: preview
                    anchors.fill: parent
                    guides: dialog._guides
                }
            }

            QGCLabel {
                Layout.maximumWidth: previewFrame.width
                wrapMode: Text.WordWrap
                font.pointSize: ScreenTools.smallFontPointSize
                text: qsTr("Measure the camera's height and tilt on the vehicle, then fine-tune with the main video open: the lines follow these settings live once saved. Park against a wall or lay a tape at the marked distances to check them.")
            }
        }
    }
}
