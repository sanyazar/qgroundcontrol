# Comm Links

Configure how QGroundControl connects to vehicles.

## Auto-Connect

By default, QGC auto-detects and connects to common devices:

- **Pixhawk** — auto-connect Pixhawk flight controllers via USB
- **SiK Radio** — auto-connect SiK telemetry radios
- **LibrePilot** — auto-connect LibrePilot controllers
- **UDP** — auto-connect via UDP broadcast

GNSS receivers, including NMEA devices that provide the GCS position, are connected in the [GNSS Receiver](gnss_receiver.md) settings.

## Link Management

Manually create and manage communication links when auto-connect is insufficient:

- **Add New Link** — create a link with a name, type, and connection-specific settings:
  - **Serial** — port, baud rate, flow control
  - **TCP** — host address, port
  - **UDP** — local port, remote hosts
  - **Bluetooth** — device selection
- **Auto Connect on Start** — automatically connect this link when QGC starts
- **High Latency** — mark the link as high-latency (reduces message rate)

Existing links can be edited, deleted, connected, or disconnected from the link list.

### Cameras

Below the link settings, the **Cameras** section lists the cameras of the vehicle on this link.
Press **Add Camera** for each camera and fill in its group: **Name** (shown in the bottom right corner of the video), **Camera type** (**Dahua**, **Hikvision**, **Uniview (UNV)** or **Custom URL**) and either the camera address, RTSP port, login, password, channel and main/sub stream, or the stream URL.
The cameras are shown in the Fly View while the link is connected and [multi-camera mode](../fly_view/multi_camera.md) is on.
