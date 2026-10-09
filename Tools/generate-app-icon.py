#!/usr/bin/env python3
"""Generate the layered AppIcon.icon SVG artwork from exact geometry.

Usage: Tools/generate-app-icon.py [assets-dir]

The two sync arrows are the same constant-width ribbon on a true circular
arc, rotated 180 degrees about the canvas centre. The heart is a mirrored
cubic outline and the house a rounded pentagon, so every curve and corner can
be tuned from the constants below.
"""

import math
import sys
from pathlib import Path

CANVAS = 1024
MID = CANVAS / 2
# Uniform scale about the canvas centre, applied to every layer, so the
# composition fills the icon grid without retuning each shape.
ARTWORK_SCALE = 1.06

# Hand-off arrows: the send arrow rises straight off the heart, arcs over the
# top on a flattened ellipse and points straight down onto the house roof; the return arrow is
# its 180-degree rotation, from under the house up into the heart's tip.
ARROW_CENTER = (MID, 262.0)
ARROW_RADII = (212.0, 136.0)
ARROW_WIDTH = 66.0
ARROW_TAIL_DEG = 180.0
ARROW_HEAD_DEG = 360.0
ARROW_SAMPLES = 32
HEAD_HALF_WIDTH = 72.0
HEAD_LENGTH = 78.0
HEAD_CORNER = 22.0

# Heart: cubic outline in a 100-unit box (tip at the bottom), scaled into place.
HEART_CENTER = (300.0, 512.0)
HEART_WIDTH = 330.0
HEART_RIGHT_HALF = [
    # Each segment: two control points and an end point, tip -> cusp.
    ((76.0, 72.5), (97.0, 54.0), (97.0, 32.0)),
    ((97.0, 16.0), (85.0, 5.0), (71.0, 5.0)),
    ((61.0, 5.0), (54.0, 11.0), (50.0, 19.5)),
]
HEART_TIP = (50.0, 91.0)
HEART_TIP_CORNER = 3.2

# House: rounded pentagon with a four-pane window.
HOUSE_LEFT = 574.0
HOUSE_RIGHT = 874.0
HOUSE_EAVE_Y = 485.0
HOUSE_PEAK_Y = 357.0
HOUSE_BASE_Y = 667.0
HOUSE_CORNER = 30.0
HOUSE_PEAK_CORNER = 34.0
PANE_SIZE = 54.0
PANE_GAP = 14.0
PANE_RADIUS = 10.0
WINDOW_CENTER_Y = 574.0


def fmt(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def pt(point):
    return f"{fmt(point[0])} {fmt(point[1])}"


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def scale(a, k):
    return (a[0] * k, a[1] * k)


def unit(a):
    length = math.hypot(*a)
    return (a[0] / length, a[1] / length)


def polar(center, radius, degrees):
    angle = math.radians(degrees)
    return (center[0] + radius * math.cos(angle), center[1] + radius * math.sin(angle))


def rounded_corner(previous, corner, following, radius):
    """Return the two cut points and the quadratic control for a soft corner."""
    entry = add(corner, scale(unit(sub(previous, corner)), radius))
    exit_ = add(corner, scale(unit(sub(following, corner)), radius))
    return entry, corner, exit_


def rotate_180(point):
    return (CANVAS - point[0], CANVAS - point[1])


def arrow_point(degrees, offset=0.0):
    """Point on the arrow centreline ellipse, pushed `offset` along its outward normal."""
    angle = math.radians(degrees)
    rx, ry = ARROW_RADII
    normal = unit((ry * math.cos(angle), rx * math.sin(angle)))
    centre = (ARROW_CENTER[0] + rx * math.cos(angle), ARROW_CENTER[1] + ry * math.sin(angle))
    return add(centre, scale(normal, offset))


def arrow_curve(offset, start_deg, end_deg):
    step = (end_deg - start_deg) / ARROW_SAMPLES
    return [arrow_point(start_deg + i * step, offset) for i in range(ARROW_SAMPLES + 1)]


def smooth_open_segments(points, transform):
    """Catmull-Rom cubic segments through the points, continuing from points[0]."""
    path = ""
    count = len(points)
    for i in range(count - 1):
        p0 = points[max(i - 1, 0)]
        p1, p2 = points[i], points[i + 1]
        p3 = points[min(i + 2, count - 1)]
        c1 = add(p1, scale(sub(p2, p0), 1 / 6))
        c2 = sub(p2, scale(sub(p3, p1), 1 / 6))
        path += f"C{pt(transform(c1))} {pt(transform(c2))} {pt(transform(p2))}"
    return path


def arrow_head():
    """Base point, unit direction and wing normal for the head, aimed along the tangent."""
    angle = math.radians(ARROW_HEAD_DEG)
    rx, ry = ARROW_RADII
    direction = unit((-rx * math.sin(angle), ry * math.cos(angle)))
    return arrow_point(ARROW_HEAD_DEG), direction, (-direction[1], direction[0])


def arrow_path(transform=lambda p: p):
    half = ARROW_WIDTH / 2
    outer = arrow_curve(half, ARROW_TAIL_DEG, ARROW_HEAD_DEG)
    inner = arrow_curve(-half, ARROW_TAIL_DEG, ARROW_HEAD_DEG)

    base, direction, normal = arrow_head()
    # Clockwise travel puts the outward side on the left of the direction.
    if math.dist(add(base, normal), ARROW_CENTER) < math.dist(base, ARROW_CENTER):
        normal = scale(normal, -1)
    wing_out = add(base, scale(normal, HEAD_HALF_WIDTH))
    wing_in = add(base, scale(normal, -HEAD_HALF_WIDTH))
    tip = add(base, scale(direction, HEAD_LENGTH))

    a1, c1, b1 = rounded_corner(outer[-1], wing_out, tip, HEAD_CORNER)
    a2, c2, b2 = rounded_corner(wing_out, tip, wing_in, HEAD_CORNER)
    a3, c3, b3 = rounded_corner(tip, wing_in, inner[-1], HEAD_CORNER)

    t = transform
    return (
        f"M{pt(t(outer[0]))}"
        + smooth_open_segments(outer, t)
        + f"L{pt(t(a1))}Q{pt(t(c1))} {pt(t(b1))}"
        f"L{pt(t(a2))}Q{pt(t(c2))} {pt(t(b2))}"
        f"L{pt(t(a3))}Q{pt(t(c3))} {pt(t(b3))}"
        f"L{pt(t(inner[-1]))}"
        + smooth_open_segments(list(reversed(inner)), t)
        + f"A{fmt(half)} {fmt(half)} 0 0 1 {pt(t(outer[0]))}Z"
    )


def arrow_highlight(transform=lambda p: p):
    points = arrow_curve(ARROW_WIDTH * 0.14, ARROW_TAIL_DEG + 14, ARROW_HEAD_DEG - 16)
    return f"M{pt(transform(points[0]))}" + smooth_open_segments(points, transform)


def heart_transform(point):
    unit_scale = HEART_WIDTH / 94
    return (
        HEART_CENTER[0] + (point[0] - 50) * unit_scale,
        HEART_CENTER[1] + (point[1] - 48) * unit_scale,
    )


def heart_segments():
    """Cubic segments (start, c1, c2, end) running tip -> left lobe -> cusp -> right lobe -> tip.

    The tip itself is left open; heart_path closes it with a small quadratic fillet.
    """
    tip_offset = scale(unit(sub(HEART_RIGHT_HALF[0][0], HEART_TIP)), HEART_TIP_CORNER)
    right_start = add(HEART_TIP, tip_offset)

    right_up = []
    start = right_start
    for c1, c2, end in HEART_RIGHT_HALF:
        right_up.append((start, c1, c2, end))
        start = end

    def mirror(point):
        return (100 - point[0], point[1])

    left_up = [tuple(mirror(p) for p in segment) for segment in right_up]
    right_down = [(end, c2, c1, start) for start, c1, c2, end in reversed(right_up)]
    return left_up + right_down


def heart_path():
    segments = heart_segments()
    t = heart_transform
    path = f"M{pt(t(segments[0][0]))}"
    for _, c1, c2, end in segments:
        path += f"C{pt(t(c1))} {pt(t(c2))} {pt(t(end))}"
    return path + f"Q{pt(t(HEART_TIP))} {pt(t(segments[0][0]))}Z"


def heart_points():
    points = []
    for start, c1, c2, end in heart_segments():
        for step in range(8):
            u = step / 8
            v = 1 - u
            weights = (v**3, 3 * v * v * u, 3 * v * u * u, u**3)
            controls = (start, c1, c2, end)
            points.append(heart_transform((
                sum(w * c[0] for w, c in zip(weights, controls)),
                sum(w * c[1] for w, c in zip(weights, controls)),
            )))
    return points


def heart_highlight():
    unit_scale = HEART_WIDTH / 94
    lobe = heart_transform((28.5, 30.0))
    r = 15.0 * unit_scale
    start = polar(lobe, r, 196)
    end = polar(lobe, r, 252)
    return f"M{pt(start)}A{fmt(r)} {fmt(r)} 0 0 1 {pt(end)}"


def rounded_polygon(points, radii):
    count = len(points)
    corners = [
        rounded_corner(points[i - 1], points[i], points[(i + 1) % count], radii[i])
        for i in range(count)
    ]
    path = f"M{pt(corners[0][2])}"
    for entry, control, exit_ in corners[1:] + corners[:1]:
        path += f"L{pt(entry)}Q{pt(control)} {pt(exit_)}"
    return path + "Z"


def house_points():
    return [
        (HOUSE_LEFT, HOUSE_BASE_Y),
        (HOUSE_LEFT, HOUSE_EAVE_Y),
        ((HOUSE_LEFT + HOUSE_RIGHT) / 2, HOUSE_PEAK_Y),
        (HOUSE_RIGHT, HOUSE_EAVE_Y),
        (HOUSE_RIGHT, HOUSE_BASE_Y),
    ]


def house_path():
    radii = [HOUSE_CORNER, HOUSE_CORNER, HOUSE_PEAK_CORNER, HOUSE_CORNER, HOUSE_CORNER]
    return rounded_polygon(house_points(), radii)


def house_highlight():
    inset = 34.0
    peak_x = (HOUSE_LEFT + HOUSE_RIGHT) / 2
    slope = (HOUSE_EAVE_Y - HOUSE_PEAK_Y) / ((HOUSE_RIGHT - HOUSE_LEFT) / 2)
    peak_y = HOUSE_PEAK_Y + inset * math.sqrt(1 + slope * slope)
    left = (HOUSE_LEFT + inset, peak_y + slope * (peak_x - HOUSE_LEFT - inset))
    right = (HOUSE_RIGHT - inset, left[1])
    return f"M{pt(left)}L{fmt(peak_x)} {fmt(peak_y)}L{pt(right)}"


def window_panes():
    center_x = (HOUSE_LEFT + HOUSE_RIGHT) / 2
    rects = []
    for row in (-1, 1):
        for column in (-1, 1):
            x = center_x + column * (PANE_GAP / 2) - (PANE_SIZE if column < 0 else 0)
            y = WINDOW_CENTER_Y + row * (PANE_GAP / 2) - (PANE_SIZE if row < 0 else 0)
            rects.append(
                f'    <rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(PANE_SIZE)}" '
                f'height="{fmt(PANE_SIZE)}" rx="{fmt(PANE_RADIUS)}" fill="#FFF9EE"/>'
            )
    return "\n".join(rects)


def svg(defs, body):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" '
        f'viewBox="0 0 {CANVAS} {CANVAS}">\n'
        f"  <defs>\n{defs}\n  </defs>\n\n"
        f'  <g transform="translate({fmt(MID)} {fmt(MID)}) scale({ARTWORK_SCALE}) '
        f'translate({fmt(-MID)} {fmt(-MID)})">\n{body}\n  </g>\n</svg>\n'
    )


def gradient(identifier, start, end, stops):
    lines = [
        f'    <linearGradient id="{identifier}" x1="{fmt(start[0])}" y1="{fmt(start[1])}" '
        f'x2="{fmt(end[0])}" y2="{fmt(end[1])}" gradientUnits="userSpaceOnUse">'
    ]
    for offset, color, *opacity in stops:
        extra = f' stop-opacity="{opacity[0]}"' if opacity else ""
        lines.append(f'      <stop offset="{offset}" stop-color="{color}"{extra}/>')
    lines.append("    </linearGradient>")
    return "\n".join(lines)


def send_layer():
    defs = "\n".join([
        gradient("send-ribbon", (260, 360), (760, 300), [
            (0, "#FF3157"), (0.55, "#FF5A64"), (1, "#FF9079"),
        ]),
        gradient("send-highlight", (280, 300), (720, 240), [
            (0, "#FFFFFF", 0), (0.45, "#FFF2EA", 0.5), (1, "#FFFFFF", 0.1),
        ]),
    ])
    body = (
        f'    <path d="{arrow_path()}" fill="url(#send-ribbon)"/>\n'
        f'    <path d="{arrow_highlight()}" fill="none" stroke="url(#send-highlight)" '
        f'stroke-width="14" stroke-linecap="round"/>'
    )
    return svg(defs, body)


def return_layer():
    defs = "\n".join([
        gradient("return-ribbon", rotate_180((260, 360)), rotate_180((760, 300)), [
            (0, "#0A8FDC"), (0.5, "#14CBEA"), (1, "#36F7EC"),
        ]),
        gradient("return-highlight", rotate_180((280, 300)), rotate_180((720, 240)), [
            (0, "#FFFFFF", 0), (0.45, "#E6FFFD", 0.5), (1, "#FFFFFF", 0.1),
        ]),
    ])
    body = (
        f'    <path d="{arrow_path(rotate_180)}" fill="url(#return-ribbon)"/>\n'
        f'    <path d="{arrow_highlight(rotate_180)}" fill="none" '
        f'stroke="url(#return-highlight)" stroke-width="14" stroke-linecap="round"/>'
    )
    return svg(defs, body)


def emblem_layer():
    defs = "\n".join([
        gradient("heart-fill", (170, 361), (420, 663), [
            (0, "#FFAE97"), (0.45, "#FF6A68"), (1, "#FF3157"),
        ]),
        gradient("house-fill", (724, 357), (724, 667), [
            (0, "#6CF8F4"), (0.5, "#1ACDEB"), (1, "#0A8BD3"),
        ]),
    ])
    body = (
        f'    <path d="{heart_path()}" fill="url(#heart-fill)"/>\n'
        f'    <path d="{heart_highlight()}" fill="none" stroke="#FFF1E8" stroke-width="16" '
        f'stroke-linecap="round" opacity="0.5"/>\n\n'
        f'    <path d="{house_path()}" fill="url(#house-fill)"/>\n'
        f'    <path d="{house_highlight()}" fill="none" stroke="#C9FFFF" stroke-width="14" '
        f'stroke-linecap="round" stroke-linejoin="round" opacity="0.45"/>\n'
        f"{window_panes()}"
    )
    return svg(defs, body)


def main():
    default = Path(__file__).resolve().parent.parent / "HAHealthSync/Resources/AppIcon.icon/Assets"
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    output.mkdir(parents=True, exist_ok=True)
    (output / "01-home-to-health.svg").write_text(return_layer())
    (output / "02-health-to-home.svg").write_text(send_layer())
    (output / "03-health-and-home.svg").write_text(emblem_layer())


if __name__ == "__main__":
    main()
