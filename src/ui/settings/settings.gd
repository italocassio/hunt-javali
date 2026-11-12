extends Control
## Settings screen: a page with the reusable SettingsPanel inside. %BackButton -> MAIN_MENU.

const PANEL_SCENE: PackedScene = preload("res://src/ui/settings/settings_panel.tscn")


func _ready() -> void:
	var page: Dictionary = UiKit.build_page(self, "Configurações", false)
	var panel: Control = PANEL_SCENE.instantiate()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set("show_close_button", false)
	(page["body"] as VBoxContainer).add_child(panel)
	var back: Button = UiKit.button("Voltar", "PrimaryButton", 72)
	back.custom_minimum_size.x = 260
	UiKit.mark(back, self, "BackButton")
	(page["footer"] as HBoxContainer).add_child(back)
	back.pressed.connect(func() -> void: Router.goto(ScenePaths.MAIN_MENU))
	back.grab_focus()
