import QtQuick

/// Parking-sensor style guide lines for a ground vehicle's camera: the vehicle's side lines and cross lines at
/// set distances, projected onto the picture from the camera's height, tilt and field of view, so the pilot sees
/// what fits between the vehicle's sides. Distance zones are coloured red (nearest), yellow, then green.
///
/// guides: settings object (see defaults); missing values take their default.
/// area:   the part of this item the video occupies (VideoOutput.contentRect); the whole item when empty.
Item {
    id: control

    property var  guides:   ({})
    property rect area:     Qt.rect(0, 0, 0, 0)

    /// Default settings; units: metres and degrees, shifts in percent of the picture.
    readonly property var defaults: ({
        vehicleWidth:   1.0,    ///< Width of the vehicle (outer sides)
        cameraHeight:   0.6,    ///< Lens height above the ground
        cameraTilt:     20,     ///< Downward tilt of the camera from horizontal
        cameraFov:      90,     ///< Horizontal field of view of the picture
        cameraOffset:   0,      ///< Lens to the right of the vehicle's centre line (negative: left)
        startDistance:  0.3,    ///< From the lens forward to the vehicle's front (bumper); lines start there
        distances:      "0.5, 1, 2, 3", ///< Cross lines, from the vehicle's front
        mirror:         false,  ///< The picture is mirrored (typical for rear cameras)
        shiftX:         0,      ///< Fine adjustment of the drawing, right
        shiftY:         0,      ///< Fine adjustment of the drawing, down
        lineWidth:      3,
        showLabels:     true
    })

    function withDefaults(settings) {
        const result = Object.assign({}, defaults)
        if (settings) {
            for (const key in defaults) {
                if (settings[key] !== undefined && settings[key] !== null && settings[key] !== "") {
                    result[key] = (typeof defaults[key] === "number") ? Number(settings[key]) : settings[key]
                }
            }
        }
        return result
    }

    /// Distances of the cross lines from the vehicle's front, ascending, positive only.
    function parseDistances(text) {
        return String(text).split(/[,;\s]+/).map(Number).filter(d => isFinite(d) && d > 0).sort((a, b) => a - b)
    }

    onGuidesChanged:    canvas.requestPaint()
    onAreaChanged:      canvas.requestPaint()
    onWidthChanged:     canvas.requestPaint()
    onHeightChanged:    canvas.requestPaint()

    Canvas {
        id:             canvas
        anchors.fill:   parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const g = control.withDefaults(control.guides)
            const useArea = control.area.width > 0 && control.area.height > 0
            const ax = useArea ? control.area.x : 0
            const ay = useArea ? control.area.y : 0
            const w = useArea ? control.area.width : width
            const h = useArea ? control.area.height : height
            if (w <= 0 || h <= 0 || g.cameraHeight <= 0 || g.cameraFov <= 0 || g.cameraFov >= 179) {
                return
            }

            const tilt = g.cameraTilt * Math.PI / 180
            const focal = (w / 2) / Math.tan(g.cameraFov * Math.PI / 360)

            // Ground point (x to the right of the lens, d forward of the lens) to picture coordinates.
            function project(x, d) {
                const down = g.cameraHeight * Math.cos(tilt) - d * Math.sin(tilt)
                const forward = g.cameraHeight * Math.sin(tilt) + d * Math.cos(tilt)
                if (forward < 0.05) {
                    return null
                }
                let u = w / 2 + focal * x / forward
                if (g.mirror) {
                    u = w - u
                }
                return { x: ax + u + g.shiftX / 100 * w, y: ay + h / 2 + focal * down / forward + g.shiftY / 100 * h }
            }

            function line(x1, d1, x2, d2, color, lineWidth) {
                const a = project(x1, d1)
                const b = project(x2, d2)
                if (!a || !b) {
                    return
                }
                ctx.beginPath()
                ctx.strokeStyle = color
                ctx.lineWidth = lineWidth
                ctx.moveTo(a.x, a.y)
                ctx.lineTo(b.x, b.y)
                ctx.stroke()
            }

            const marks = control.parseDistances(g.distances)
            if (marks.length === 0) {
                return
            }
            const zoneColors = ["#ff3b30", "#ffcc00", "#34c759"]
            function zoneColor(index) {
                if (marks.length === 1) {
                    return zoneColors[2]
                }
                return zoneColors[Math.min(2, Math.floor(index * 3 / marks.length))]
            }

            ctx.save()
            ctx.beginPath()
            ctx.rect(ax, ay, w, h)
            ctx.clip()
            ctx.lineCap = "round"
            ctx.globalAlpha = 0.9

            const left = -g.vehicleWidth / 2 - g.cameraOffset
            const right = g.vehicleWidth / 2 - g.cameraOffset
            const front = g.startDistance

            // Side lines, coloured by the zone each part is in.
            let from = 0
            for (let i = 0; i < marks.length; i++) {
                const color = zoneColor(i)
                line(left, front + from, left, front + marks[i], color, g.lineWidth)
                line(right, front + from, right, front + marks[i], color, g.lineWidth)
                from = marks[i]
            }

            // Cross lines at each distance; the far ones thinner, as on a parking display.
            ctx.font = "bold " + Math.max(10, Math.round(h / 32)) + "px sans-serif"
            for (let i = 0; i < marks.length; i++) {
                const d = front + marks[i]
                const color = zoneColor(i)
                const thickness = Math.max(1, g.lineWidth * (i === 0 ? 1.5 : 1))
                line(left, d, right, d, color, thickness)
                if (g.showLabels) {
                    const end = project(g.mirror ? left : right, d)
                    if (end) {
                        ctx.fillStyle = color
                        ctx.fillText(marks[i] + " m", end.x + g.lineWidth * 2, end.y)
                    }
                }
            }
            ctx.restore()
        }
    }
}
