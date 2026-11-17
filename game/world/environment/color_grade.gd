class_name ColorGrade
extends RefCounted
## The Table's one colour grade as a 1D lookup texture (per-channel curves, applied after tonemapping in
## display space): a gentle S-curve, warm highlights, slightly cool shadows. Saturation is set next to it
## in the Environment adjustments.

const SIZE := 256


## contrast: S-curve amount (0 = none); warmth: highlight warmth / shadow coolness (0 = neutral);
## lift: how far pure black is raised (keeps the shadows soft instead of crushed).
static func build_lut(contrast: float = 0.12, warmth: float = 0.035, lift: float = 0.006) -> ImageTexture:
	var data := PackedByteArray()
	data.resize(SIZE * 3)
	for i in SIZE:
		var x := float(i) / float(SIZE - 1)
		var s := x * x * (3.0 - 2.0 * x)
		var y := lerpf(x, s, contrast)
		y = lift + (1.0 - lift) * y
		# Split toning: weight w moves from -1 in the shadows to +1 in the highlights.
		var w := 2.0 * y - 1.0
		var mid := 1.0 - w * w   # strongest in the midtones' shoulders, zero at pure black and white
		var r := y + warmth * (0.55 * w * mid + 0.25 * mid)
		var g := y + warmth * (0.08 * mid)
		var b := y - warmth * (0.75 * w * mid + 0.10 * mid)
		data[i * 3] = int(clampf(r, 0.0, 1.0) * 255.0 + 0.5)
		data[i * 3 + 1] = int(clampf(g, 0.0, 1.0) * 255.0 + 0.5)
		data[i * 3 + 2] = int(clampf(b, 0.0, 1.0) * 255.0 + 0.5)
	var img := Image.create_from_data(SIZE, 1, false, Image.FORMAT_RGB8, data)
	return ImageTexture.create_from_image(img)
