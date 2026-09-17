class_name Icons
extends RefCounted
## Little textures drawn pixel by pixel in code, so every type and personality has a badge
## you can tell apart at a glance in a row of five robots. Godot's bundled font has no
## emoji and nothing here ships an image file, so the icons are drawn rather than typed.
##
## Shape carries the meaning, colour reinforces it - the key is on the hover, and on the
## "?" button beside each row.

enum Shape { DISC, SQUARE, TRI_UP, DIAMOND, CROSS, RING, TRI_DOWN, BOLT, STAR, BARS, HOURGLASS, SHIELD }

const SIZE := 20

static var _cache := {}


static func get_icon(shape: Shape, color: Color) -> ImageTexture:
	var key := "%d_%s" % [int(shape), color.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := float(SIZE) * 0.5
	for y in SIZE:
		for x in SIZE:
			# sample at pixel centres, in a -1..1 box, so the shapes are symmetrical
			var u := (float(x) + 0.5 - c) / (c - 1.0)
			var v := (float(y) + 0.5 - c) / (c - 1.0)
			var a := _coverage(shape, u, v)
			if a > 0.0:
				# a darker rim keeps the badge readable on a pale button
				var edge: float = clampf((a - 0.5) * 2.0, 0.0, 1.0)
				var col: Color = color.lerp(color.darkened(0.45), 1.0 - edge)
				col.a = clampf(a, 0.0, 1.0)
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Rough antialiasing: 1 inside, 0 outside, a soft band between.
static func _band(d: float, w: float = 0.09) -> float:
	return clampf(0.5 - d / w, 0.0, 1.0)


static func _coverage(shape: Shape, u: float, v: float) -> float:
	match shape:
		Shape.DISC:
			return _band(sqrt(u * u + v * v) - 0.86)
		Shape.SQUARE:
			return _band(maxf(absf(u), absf(v)) - 0.76)
		Shape.TRI_UP:
			# inside the triangle: above the base, below both slopes
			var d1: float = -v - 0.62
			var d2: float = (absf(u) * 0.95 + v * 0.55) - 0.46
			return _band(maxf(d1, d2))
		Shape.TRI_DOWN:
			var e1: float = v - 0.62
			var e2: float = (absf(u) * 0.95 - v * 0.55) - 0.46
			return _band(maxf(e1, e2))
		Shape.DIAMOND:
			return _band(absf(u) + absf(v) - 0.98)
		Shape.CROSS:
			var arm: float = minf(maxf(absf(u) - 0.86, absf(v) - 0.3), maxf(absf(u) - 0.3, absf(v) - 0.86))
			return _band(arm)
		Shape.RING:
			var r: float = sqrt(u * u + v * v)
			return minf(_band(r - 0.88), _band(0.46 - r))
		Shape.BOLT:
			# a lightning zigzag: two offset wedges
			var top: float = maxf(absf(u * 1.5 + 0.35) - 0.42, absf(v + 0.42) - 0.46)
			var bot: float = maxf(absf(u * 1.5 - 0.35) - 0.42, absf(v - 0.42) - 0.46)
			return _band(minf(top, bot))
		Shape.STAR:
			# four-point star: the union of two thin diamonds
			var d_a: float = absf(u) * 2.2 + absf(v) * 0.75 - 0.92
			var d_b: float = absf(u) * 0.75 + absf(v) * 2.2 - 0.92
			return _band(minf(d_a, d_b))
		Shape.BARS:
			var b1: float = maxf(absf(u + 0.52) - 0.2, absf(v) - 0.84)
			var b2: float = maxf(absf(u) - 0.2, absf(v) - 0.58)
			var b3: float = maxf(absf(u - 0.52) - 0.2, absf(v) - 0.32)
			return _band(minf(b1, minf(b2, b3)))
		Shape.HOURGLASS:
			var h: float = maxf(absf(u) * 0.9 + absf(v) * 0.1 - 0.5 - absf(v) * 0.55, absf(v) - 0.82)
			return _band(h)
		Shape.SHIELD:
			# a rounded top that tapers to a point
			var w: float = 0.9 - 0.62 * clampf((v + 0.5) * 0.9, 0.0, 1.4)
			return _band(maxf(absf(u) - w, absf(v + 0.02) - 0.85))
	return 0.0


# ---------------------------------------------------------------- the two rosters

## Robot types: shape and colour per preset, plus the fallbacks.
const TYPE_LOOK := {
	"Team":    [Shape.RING, Color(0.78, 0.78, 0.84)],
	"Even":    [Shape.DISC, Color(0.72, 0.74, 0.80)],
	"Bruiser": [Shape.SQUARE, Color(0.90, 0.42, 0.28)],
	"Runner":  [Shape.TRI_UP, Color(0.36, 0.82, 0.52)],
	"Tank":    [Shape.SHIELD, Color(0.55, 0.60, 0.72)],
	"Sniper":  [Shape.STAR, Color(0.95, 0.80, 0.30)],
	"Ghost":   [Shape.DIAMOND, Color(0.60, 0.55, 0.92)],
	"Random":  [Shape.BOLT, Color(0.85, 0.55, 0.85)],
	"Custom":  [Shape.BARS, Color(0.70, 0.72, 0.78)],
}

## Personalities: deliberately different shapes from the types so the two rows never blur.
const PERSONALITY_LOOK := {
	"Team":      [Shape.RING, Color(0.78, 0.78, 0.84)],
	"Balanced":  [Shape.DISC, Color(0.70, 0.76, 0.82)],
	"Brawler":   [Shape.CROSS, Color(0.92, 0.35, 0.30)],
	"Slinger":   [Shape.TRI_DOWN, Color(0.95, 0.70, 0.25)],
	"Coward":    [Shape.HOURGLASS, Color(0.55, 0.78, 0.85)],
	"Tactician": [Shape.BARS, Color(0.45, 0.70, 0.95)],
	"Guardian":  [Shape.SHIELD, Color(0.45, 0.85, 0.60)],
	"Random":    [Shape.BOLT, Color(0.85, 0.55, 0.85)],
	"Custom":    [Shape.STAR, Color(0.72, 0.72, 0.78)],
}


static func type_icon(n: String) -> ImageTexture:
	var look: Array = TYPE_LOOK.get(n, TYPE_LOOK["Custom"])
	return get_icon(look[0], look[1])


static func personality_icon(n: String) -> ImageTexture:
	var look: Array = PERSONALITY_LOOK.get(n, PERSONALITY_LOOK["Custom"])
	return get_icon(look[0], look[1])
