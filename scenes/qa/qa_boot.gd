extends Node

var _runner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var runner_script := load("res://scenes/qa/qa_runner.gd")
	if runner_script == null:
		push_error("QA runner script could not be loaded.")
		get_tree().quit(1)
		return
	_runner = runner_script.new()
	_runner.name = "QARunner"
	add_child(_runner)
	_runner.configure_from_environment()
	_runner.configure_from_args(OS.get_cmdline_args())
	_runner.finished.connect(_on_runner_finished)
	_runner.initialize_runner()


func _on_runner_finished(exit_code: int) -> void:
	get_tree().quit(exit_code)
