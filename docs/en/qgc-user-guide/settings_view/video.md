# Video

Configure video streaming and recording settings.

## Video Source

- **Source** — Video Stream Disabled / RTSP Video Stream / UDP h.264 / UDP h.265 / TCP-MPEG2 / MPEG-TS / Integrated Camera

## Connection

Connection settings vary by source type:

- **RTSP URL** — full RTSP stream address
- **TCP URL** — TCP stream address
- **UDP URL** — UDP stream address and port (default: `0.0.0.0:5600`)

## Multiple Cameras

- **Multiple camera streams** — show several streams at once (one main stream plus thumbnails) from manually entered URLs and from the MAVLink cameras of all connected vehicles; the **Video Source** above is not used while this is on.
  See [Multiple Cameras](../fly_view/multi_camera.md).
- **Maximum streams** — how many streams are decoded at the same time (default: 4, range: 1–9).

## Manual Camera Streams

Shown when **Multiple camera streams** is on.
One row per stream: **Vehicle ID** (MAVLink system ID, `0` if not tied to a vehicle), **Name**, and **Stream URL** (`rtsp://`, `udp://`, `udp265://`, `mpegts://` or `tcp://`).
Use **Add Stream** to add a row and the trash icon to remove one.

## Settings

- **Aspect Ratio** — aspect ratio for scaling video in the display widget (default: 16:9; set to 0.0 to disable scaling)
- **Stop recording when disarmed** — automatically stop recording when the vehicle disarms
- **Low Latency Mode** — minimize video decode latency at the cost of some smoothness
- **Force CPU video path** — disable hardware-accelerated rendering (use if video displays incorrectly)
- **Force video decoder priority** — override the automatic decoder selection: Default / Software / Hardware / NVIDIA / VA-API / DirectX 3D11 / VideoToolbox / Intel / Vulkan

## Local Video Storage

- **Record File Format** — mp4 / mov / mkv
- **Auto-Delete Saved Recordings** — automatically delete old recordings when storage limit is reached
- **Max Storage Usage** — maximum disk space for saved recordings (default: 10240 MB)
