class_name Surfaces
extends RefCounted
## Small shared PBR palette, generated in code ($0, no imported textures). Materials are cached by key.
## World-space triplanar mapping keeps textures continuous across box walls and breach parts.
## Keys: plaster, carpet, ceiling, metal_plate, trim, glass, wood, painted_metal, plastic, cork, paper,
## fabric_dark, fabric_tan, foliage, asphalt, siding, case, lamp_warm, lamp_cool, screen.

static var _cache := {}


static func get_mat(key: String) -> StandardMaterial3D:
	if not _cache.has(key):
		_cache[key] = _make(key)
	return _cache[key]


static func _make(key: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	match key:
		"plaster":
			_tri(m, 0.5)
			m.albedo_color = Color(0.6, 0.58, 0.54)
			m.albedo_texture = _noise(0.02, 11, Color(0.86, 0.85, 0.83), Color(1, 1, 1))
			m.normal_enabled = true
			m.normal_texture = _noise_normal(0.09, 12, 1.2)
			m.normal_scale = 0.35
			m.roughness = 0.88
		"carpet":
			_tri(m, 1.0)
			m.albedo_color = Color(0.2, 0.21, 0.24)
			m.albedo_texture = _noise(0.35, 21, Color(0.62, 0.62, 0.66), Color(1.12, 1.12, 1.1))
			m.normal_enabled = true
			m.normal_texture = _noise_normal(0.5, 22, 3.0)
			m.normal_scale = 0.6
			m.roughness = 1.0
		"ceiling":
			_tri(m, 1.0 / 0.6)
			m.albedo_color = Color(0.58, 0.58, 0.56)
			m.albedo_texture = _tile_grid(128, 2, Color(0.62, 0.62, 0.62))
			m.roughness = 0.95
		"metal_plate":
			_tri(m, 1.0 / 0.6)
			m.albedo_color = Color(0.36, 0.4, 0.45)
			var hm := _stripe_height(256, 4)
			m.albedo_texture = _stripe_albedo(hm)
			m.normal_enabled = true
			m.normal_texture = _normal_from(hm, 4.0)
			m.metallic = 0.3
			m.roughness = 0.5
			m.roughness_texture = _noise(0.06, 31, Color(0.75, 0.75, 0.75), Color(1, 1, 1))
		"trim":
			_tri(m, 1.0)
			m.albedo_color = Color(0.11, 0.1, 0.09)
			m.roughness = 0.5
		"glass":
			m.albedo_color = Color(0.55, 0.65, 0.78, 0.16)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.3
			m.roughness = 0.04
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"wood":
			_tri(m, 1.0)
			m.albedo_color = Color(0.42, 0.31, 0.21)
			m.albedo_texture = _noise(0.04, 41, Color(0.8, 0.78, 0.76), Color(1.1, 1.05, 1.0))
			m.roughness = 0.55
		"painted_metal":
			_tri(m, 1.0)
			m.albedo_color = Color(0.4, 0.41, 0.4)
			m.metallic = 0.45
			m.roughness = 0.42
		"plastic":
			m.albedo_color = Color(0.07, 0.07, 0.08)
			m.roughness = 0.6
		"cork":
			_tri(m, 2.0)
			m.albedo_color = Color(0.45, 0.33, 0.2)
			m.albedo_texture = _noise(0.4, 51, Color(0.7, 0.7, 0.7), Color(1.1, 1.1, 1.1))
			m.roughness = 0.95
		"paper":
			m.albedo_color = Color(0.68, 0.67, 0.63)
			m.roughness = 0.9
		"fabric_dark":
			m.albedo_color = Color(0.13, 0.14, 0.13)
			m.roughness = 0.95
		"fabric_tan":
			m.albedo_color = Color(0.5, 0.46, 0.32)
			m.roughness = 0.9
		"foliage":
			m.albedo_color = Color(0.13, 0.26, 0.11)
			m.roughness = 0.7
		"asphalt":
			_tri(m, 0.5)
			m.albedo_color = Color(0.11, 0.11, 0.12)
			m.albedo_texture = _noise(0.15, 61, Color(0.6, 0.6, 0.6), Color(1.2, 1.2, 1.2))
			m.roughness = 0.85
		"siding":
			_tri(m, 1.0)
			m.albedo_color = Color(0.32, 0.35, 0.38)
			var hs := _stripe_height(256, 8)
			m.normal_enabled = true
			m.normal_texture = _normal_from(hs, 3.0)
			m.metallic = 0.5
			m.roughness = 0.6
		"case":
			_tri(m, 1.0)
			m.albedo_color = Color(0.2, 0.23, 0.17)
			m.roughness = 0.55
		"lamp_warm":
			m.albedo_color = Color(1.0, 0.9, 0.75)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.78, 0.5)
			m.emission_energy_multiplier = 3.0
		"lamp_cool":
			m.albedo_color = Color(0.9, 0.95, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.75, 0.85, 1.0)
			m.emission_energy_multiplier = 5.0
		"screen":
			m.albedo_color = Color(0.02, 0.03, 0.04)
			m.emission_enabled = true
			m.emission = Color(0.25, 0.4, 0.6)
			m.emission_energy_multiplier = 0.35
			m.roughness = 0.2
		_:
			push_warning("Surfaces: unknown key " + key)
	return m


static func _tri(m: StandardMaterial3D, scale: float) -> void:
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale


## Seamless value noise, tinted between two colors (multiplied with albedo_color).
static func _noise(freq: float, seed_v: int, lo: Color, hi: Color) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = _fnl(freq, seed_v)
	var g := Gradient.new()
	g.set_color(0, lo)
	g.set_color(1, hi)
	t.color_ramp = g
	return t


static func _noise_normal(freq: float, seed_v: int, strength: float) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = strength
	t.noise = _fnl(freq, seed_v)
	return t


static func _fnl(freq: float, seed_v: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.frequency = freq
	n.fractal_octaves = 4
	return n


## Light tile with darker grid lines (ceiling tiles).
static func _tile_grid(size: int, line: int, line_col: Color) -> ImageTexture:
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for i in size:
		for w in line:
			img.set_pixel(i, w, line_col)
			img.set_pixel(w, i, line_col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Horizontal panel seams (grayscale height): `bands` panels per texture.
static func _stripe_height(size: int, bands: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RF)
	var band := size / bands
	for y in size:
		var v := y % band
		var h := 1.0
		if v < 3:
			h = 0.0
		elif v < 6:
			h = 0.5
		for x in size:
			img.set_pixel(x, y, Color(h, h, h))
	return img


static func _stripe_albedo(height: Image) -> ImageTexture:
	var img := Image.create(height.get_width(), height.get_height(), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		var h := height.get_pixel(0, y).r
		var c := 0.55 + 0.45 * h
		for x in img.get_width():
			img.set_pixel(x, y, Color(c, c, c))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _normal_from(height: Image, strength: float) -> ImageTexture:
	var img := height.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	img.bump_map_to_normal_map(strength)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
