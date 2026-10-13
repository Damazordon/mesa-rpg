class_name LoreBook
extends PanelContainer
## A lore em papel, escrita na frente de quem está lendo: o texto aparece aos poucos, com uma pena
## correndo na linha e um risco de tinta logo atrás. Serve na criação de sala (quando a história é
## reescrita com os personagens) e para reler a lore depois.
##
## write(texto) escreve com animação; show_text(texto) mostra de uma vez. Clicar ou chamar skip()
## solta o resto do texto na hora.

signal finished

const CPS := 42.0        # caracteres por segundo
const QUILL_H := 26.0

var title_l: Label
var text_l: RichTextLabel
var quill: Control
var full := ""
var shown := 0.0
var writing := false


func build(heading := "") -> void:
	add_theme_stylebox_override("panel", UiTheme.paper_box(8, 26))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	title_l = UiTheme.label(heading, 28, UiTheme.INK, UiTheme.serif())
	title_l.visible = heading != ""
	v.add_child(title_l)
	var rule := ColorRect.new()
	rule.color = Color(UiTheme.INK, 0.25)
	rule.custom_minimum_size = Vector2(0, 1)
	v.add_child(rule)
	text_l = RichTextLabel.new()
	text_l.bbcode_enabled = false
	text_l.fit_content = true
	text_l.scroll_active = false
	text_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_l.add_theme_font_override("normal_font", UiTheme.serif())
	text_l.add_theme_font_size_override("normal_font_size", 19)
	text_l.add_theme_color_override("default_color", UiTheme.INK)
	text_l.add_theme_constant_override("line_separation", 5)
	v.add_child(text_l)
	quill = Control.new()
	quill.custom_minimum_size = Vector2(0, QUILL_H)
	quill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quill.draw.connect(_draw_quill)
	v.add_child(quill)
	set_process(false)


func set_heading(text: String) -> void:
	title_l.text = text
	title_l.visible = text != ""


## Escreve o texto com animação.
func write(text: String) -> void:
	full = text
	shown = 0.0
	writing = true
	text_l.text = ""
	quill.visible = true
	set_process(true)


## Mostra o texto inteiro, sem animação.
func show_text(text: String) -> void:
	full = text
	shown = float(text.length())
	writing = false
	text_l.text = text
	quill.visible = false
	set_process(false)


## Solta o resto do texto de uma vez.
func skip() -> void:
	if not writing:
		return
	show_text(full)
	finished.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and writing:
		accept_event()
		skip()


func _process(delta: float) -> void:
	if not writing:
		return
	shown += CPS * delta
	var n := mini(int(shown), full.length())
	text_l.text = full.substr(0, n)
	quill.queue_redraw()
	if n >= full.length():
		writing = false
		quill.visible = false
		set_process(false)
		finished.emit()


## Pena correndo na última linha, com o risco de tinta atrás dela.
func _draw_quill() -> void:
	if not writing:
		return
	var w: float = quill.size.x
	if w <= 1.0:
		return
	var t := fmod(shown / 18.0, 1.0)
	var x := 6.0 + t * maxf(20.0, w - 40.0)
	var y := QUILL_H * 0.72
	quill.draw_line(Vector2(6, y + 1), Vector2(x, y + 1), Color(UiTheme.INK, 0.35), 1.5)
	# a pena: um traço inclinado com a ponta na linha
	quill.draw_line(Vector2(x, y), Vector2(x + 7, y - 17), Color(UiTheme.INK, 0.85), 2.0)
	quill.draw_line(Vector2(x + 7, y - 17), Vector2(x + 11, y - 21), Color(UiTheme.INK, 0.5), 1.5)
	quill.draw_circle(Vector2(x, y), 1.6, UiTheme.INK)
