extends Node
class_name Dispatcher

# ========== Settings ==========
@export_range(1, 1000) var _update_frequency: int = 60
@export var _auto_start: bool = false
@export var _data_texture: Texture2D

# ========== Requirements ==========
# Recomendo exportar como RDShaderFile para evitar problemas de load.
@export var _compute_shader: RDShaderFile
@export var _renderer: Sprite2D

# ========== Internals ==========
var _rd: RenderingDevice

var _input_texture: RID
var _output_texture: RID
var _uniform_set: RID
var _shader: RID
var _pipeline: RID

var _bindings: Array[RDUniform] = []

var _input_image: Image
var _output_image: Image
var _render_texture: ImageTexture

var _input_format: RDTextureFormat
var _output_format: RDTextureFormat
var _processing: bool = false

const TEX_SIZE := 1024

# Mesmos bits de uso do seu C#
var _texture_usage := (
	RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
)

# ---------------- MAIN LOOP ----------------
func _ready() -> void:
	_create_and_validate_images()
	_setup_compute_shader()

	if _auto_start:
		_start_process_loop()

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.keycode == KEY_SPACE and key.pressed and not key.echo:
		if _processing:
			_processing = false
		else:
			_start_process_loop()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_cleanup_gpu()

# ---------------- IMAGE SETUP ----------------
func _merge_images() -> void:
	var output_w := _output_image.get_width()
	var output_h := _output_image.get_height()
	var input_w := _input_image.get_width()
	var input_h := _input_image.get_height()

	var start_x := int((output_w - input_w) / 2)
	var start_y := int((output_h - input_h) / 2)

	for x in input_w:
		for y in input_h:
			var color := _input_image.get_pixel(x, y)
			var dx := start_x + x
			var dy := start_y + y
			if dx >= 0 and dx < output_w and dy >= 0 and dy < output_h:
				_output_image.set_pixel(dx, dy, color)

	# Copia a imagem mesclada para a _input_image no formato L8 1024x1024
	_input_image.set_data(
		TEX_SIZE,
		TEX_SIZE,
		false,
		Image.FORMAT_L8,
		_output_image.get_data()
	)

func _link_output_texture_to_renderer() -> void:
	var mat := _renderer.material as ShaderMaterial
	_render_texture = ImageTexture.create_from_image(_output_image)
	if mat:
		mat.set_shader_parameter("binaryDataTexture", _render_texture)

func _create_and_validate_images() -> void:
	_output_image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_L8)

	if _data_texture == null:
		var noise := FastNoiseLite.new()
		noise.frequency = 0.1
		var noise_image := noise.get_image(TEX_SIZE, TEX_SIZE)
		_input_image = noise_image
	else:
		_input_image = _data_texture.get_image()

	_merge_images()
	_link_output_texture_to_renderer()

# ---------------- SHADER SETUP ----------------
func _create_rendering_device() -> void:
	_rd = RenderingServer.create_local_rendering_device()

func _create_shader() -> void:
	if _compute_shader == null:
		push_error("Dispatcher: _compute_shader (RDShaderFile) não atribuído no Inspector.")
		return
	var spirv: RDShaderSPIRV = _compute_shader.get_spirv()
	_shader = _rd.shader_create_from_spirv(spirv)

func _create_pipeline() -> void:
	_pipeline = _rd.compute_pipeline_create(_shader)

func _default_texture_format() -> RDTextureFormat:
	var fmt := RDTextureFormat.new()
	fmt.width = TEX_SIZE
	fmt.height = TEX_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	fmt.usage_bits = _texture_usage
	return fmt

func _create_texture_formats() -> void:
	_input_format = _default_texture_format()
	_output_format = _default_texture_format()

func _create_texture_and_uniform(image: Image, format: RDTextureFormat, binding: int) -> RID:
	var view := RDTextureView.new()
	var data := [image.get_data()]  # Array de PackedByteArray
	var tex := _rd.texture_create(format, view, data)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	uniform.add_id(tex)

	_bindings.append(uniform)
	return tex

func _create_uniforms() -> void:
	_input_texture = _create_texture_and_uniform(_input_image, _input_format, 0)
	_output_texture = _create_texture_and_uniform(_output_image, _output_format, 1)
	_uniform_set = _rd.uniform_set_create(_bindings, _shader, 0)

func _setup_compute_shader() -> void:
	_create_rendering_device()
	_create_shader()
	_create_pipeline()
	_create_texture_formats()
	_create_uniforms()

# ---------------- PROCESSING ----------------
func _start_process_loop() -> void:
	_processing = true
	# período em segundos (mais natural em GDScript)
	var period_s := 1.0 / float(_update_frequency)
	_async_process_loop(period_s)

# loop assíncrono (sem bloquear o thread principal)
func _async_process_loop(period_s: float) -> void:
	await get_tree().process_frame  # dá um respiro antes de iniciar
	while _processing:
		_update_gpu()
		await get_tree().create_timer(period_s).timeout
		_render_to_texture()

func _update_gpu() -> void:
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	# 32x32 grupos para 1024x1024 com local_size de 32 (ajuste se seu shader usar outro local_size)
	_rd.compute_list_dispatch(cl, 32, 32, 1)
	_rd.compute_list_end()
	_rd.submit()

func _render_to_texture() -> void:
	_rd.sync()  # garante que a GPU terminou
	var bytes: PackedByteArray = _rd.texture_get_data(_output_texture, 0)
	_rd.texture_update(_input_texture, 0, bytes)
	_output_image.set_data(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_L8, bytes)
	if _render_texture:
		_render_texture.update(_output_image)

# ---------------- CLEANUP ----------------
func _cleanup_gpu() -> void:
	if _rd == null:
		return
	_rd.free_rid(_input_texture)
	_rd.free_rid(_output_texture)
	_rd.free_rid(_uniform_set)
	_rd.free_rid(_pipeline)
	_rd.free_rid(_shader)
	_rd.free()
	_rd = null
