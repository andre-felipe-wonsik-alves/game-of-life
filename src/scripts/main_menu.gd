extends Node2D

var button_type = null;

func _ready():
	pass # Replace with function body.
func run_start_animation():
	$Fade_transition.show();
	$Fade_transition/fade_timer.start();
	$Fade_transition/AnimationPlayer.play("fade");
	
func check_start():
	if Input.is_action_just_pressed("toggle_play"):
		run_start_animation();

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	check_start();
	pass


func _on_quit_pressed():
	get_tree().quit();


func _on_fade_timer_timeout():
	get_tree().change_scene_to_file("res://scenes/main.tscn");
	pass # Replace with function body.
