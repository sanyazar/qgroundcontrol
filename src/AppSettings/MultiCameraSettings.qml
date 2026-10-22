import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

QGCGroupBox {
    Layout.fillWidth: true
    heading: qsTr("Other Camera Streams")
    headingDescription: qsTr("Cameras of a vehicle are best added to its comm link (Comm Links > Edit > Cameras). "
                             + "Streams listed here are shown in addition to those and to MAVLink camera streams. "
                             + "Vehicle ID is the MAVLink system ID (0: not tied to a vehicle). "
                             + "For Dahua, Hikvision and Uniview cameras pick the camera type and enter its address "
                             + "and login; the RTSP URL is built automatically. "
                             + "Other cameras: rtsp://192.168.1.10:8554/main, udp://0.0.0.0:5600, "
                             + "udp265://0.0.0.0:5601, mpegts://0.0.0.0:5602, tcp://192.168.1.10:5000")

    property Fact _streamsFact: QGroundControl.settingsManager.videoSettings.multiCameraStreams

    CameraStreamsEditor {
        streamsJson: _streamsFact.rawValue
        addButtonText: qsTr("Add Stream")
        onEdited: (json) => _streamsFact.rawValue = json
    }
}
