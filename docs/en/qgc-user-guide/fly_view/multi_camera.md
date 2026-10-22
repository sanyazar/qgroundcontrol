# Multiple Cameras

Multi-camera mode shows several video streams at the same time: more than one camera on a vehicle, cameras on several vehicles, or both.
One stream is shown large (the _main_ stream) and the others appear as thumbnails along the top of the video view.

![Multi-camera layout](../../../assets/fly/multi_camera_layout.svg)

## Enabling

Open **Application Settings > Video** and turn on **Multiple camera streams**.
While multi-camera mode is enabled the single-stream **Video Source** setting is not used.

**Maximum streams** (default: 4, range: 1–9) limits how many streams are decoded at the same time.
Every stream is decoded separately, so raise the limit only if the ground station has CPU/GPU headroom.

## Where Streams Come From

_QGroundControl_ combines two sources:

1. **Manual camera streams** — a list you enter in **Application Settings > Video > Manual Camera Streams**.
   Use it for cameras that do not implement the MAVLink camera protocol, or for video that reaches the ground station over a separate link.
2. **MAVLink cameras** — every stream reported with [VIDEO_STREAM_INFORMATION](https://mavlink.io/en/messages/common.html#VIDEO_STREAM_INFORMATION) by any camera on any connected vehicle, including thermal streams.
   _QGroundControl_ requests streaming from each of these cameras (`MAV_CMD_VIDEO_START_STREAMING`) when the stream first appears.

Manual streams are taken first, then MAVLink streams, until **Maximum streams** is reached.
If a MAVLink stream has the same URL as a manual one it is skipped, because two receivers cannot share one UDP port or RTSP session.
Streams are added and removed automatically as vehicles connect and disconnect.

### Manual Camera Streams

Each row of the list describes one stream:

- **Vehicle ID** — MAVLink system ID of the vehicle the camera is on (shown in the stream label).
  Use `0` for a stream that is not tied to a vehicle.
- **Name** — label shown on the video tile, for example `Front` or `Thermal`.
- **Stream URL** — one of:

  | Format | Example |
  | ------ | ------- |
  | RTSP | `rtsp://192.168.1.10:8554/main` |
  | UDP H.264 (RTP) | `udp://0.0.0.0:5600` |
  | UDP H.265 (RTP) | `udp265://0.0.0.0:5601` |
  | MPEG-TS over UDP | `mpegts://0.0.0.0:5602` |
  | TCP MPEG | `tcp://192.168.1.10:5000` |

Press **Add Stream** to add a row and the trash icon to delete one.
Changes apply immediately; there is no need to restart _QGroundControl_.

::: tip
Give every UDP stream its own port.
A typical two-vehicle, two-camera setup is `udp://0.0.0.0:5600` and `udp://0.0.0.0:5601` for vehicle 1, and `udp://0.0.0.0:5602` and `udp://0.0.0.0:5603` for vehicle 2.
:::

## Using the Video View

- **Switch the main stream** — click a thumbnail. Streams keep running while you switch, so there is no reconnect delay.
- **Full screen** — double-click the main stream (requires a connected vehicle).
- **Record** — press the red circle on a tile to start recording that stream; it turns into a square while recording, and a red dot appears next to the stream name.
  Each stream records into its own file.
- **Photo** — press the camera icon on a tile to save the current frame of that stream.

The record and photo buttons are shown on a tile once its video is decoding.
A tile shows **WAITING FOR VIDEO** until the first frame arrives, and the view shows **NO CAMERA STREAMS** when no stream is configured or discovered.

When the video is in the small picture-in-picture window, only the main stream is shown, without thumbnails or buttons.

### Saved Files

Recordings use the **Record File Format** and storage limit from **Application Settings > Video > Local Video Storage** and are saved in the application's video folder:

```text
<Video folder>/2026-10-22_20.15.03.Vehicle_1_Front.mkv
<Photo folder>/2026-10-22_20.15.07.512.Vehicle_2_Down.jpg
```

The stream label is part of the file name, so recordings from different cameras never overwrite each other.

## Limitations

- On-screen gimbal control and camera tracking by clicking the video are disabled in multi-camera mode, because the main stream may belong to a vehicle other than the active one.
- Telemetry subtitle files are not written for multi-camera recordings.
- Streams use the shared **Low Latency Mode**, **RTP jitter buffer**, **RTSP timeout** and **auto-reconnect** settings from **Application Settings > Video**.

## Testing Without Hardware

Two SITL vehicles and GStreamer test sources on the ground station are enough to try the feature:

```sh
gst-launch-1.0 videotestsrc pattern=ball ! video/x-raw,width=1280,height=720 ! \
    x264enc tune=zerolatency ! rtph264pay ! udpsink host=127.0.0.1 port=5600
gst-launch-1.0 videotestsrc pattern=smpte ! video/x-raw,width=1280,height=720 ! \
    x264enc tune=zerolatency ! rtph264pay ! udpsink host=127.0.0.1 port=5601
```

Then add `udp://0.0.0.0:5600` (vehicle 1) and `udp://0.0.0.0:5601` (vehicle 2) as manual streams.
