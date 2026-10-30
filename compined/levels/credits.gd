extends Control

const PRIMITIVE_REPO_URL: String = "https://github.com/fogleman/primitive/"

@onready var repo_link_button: Button = $CreditsCard/MarginContainer/VBoxContainer/RepoLinkButton
@onready var back_button: Button = $CreditsCard/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	if is_instance_valid(LevelManager.debug_win_button):
		LevelManager.debug_win_button.visible = false

	repo_link_button.pressed.connect(_on_repo_link_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_repo_link_pressed() -> void:
	# Opens the GitHub repository in the user's default web browser
	OS.shell_open(PRIMITIVE_REPO_URL)


func _on_back_pressed() -> void:
	# Fades out and loads the Start Menu
	LevelManager.go_to_start_menu()
