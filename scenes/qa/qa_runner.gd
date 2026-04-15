class_name QARunner
extends Node

signal finished(exit_code: int)

const RUN_SCENE := preload("res://scenes/run/run.tscn")
const DEFAULT_CHARACTER := preload("res://characters/warrior/warrior.tres")
const REPORT_PATH := "user://qa_autoplay_last_run.json"
const ACTION_LOG_LIMIT := 40
const ROOM_HISTORY_LIMIT := 20
const REPORT_INTERVAL_MSEC := 500

@export_range(1, 100) var runs_to_play := 1
@export_range(0, 10000) var max_actions_per_run := 800
@export_range(0.0, 3600.0, 1.0) var max_seconds_per_run := 180.0
@export_range(0.0, 5.0, 0.01) var action_delay_seconds := 0.05
@export var seed_override := -1
@export var verbose_logging := true

var _active_run: Run
var _current_run_index := 0
var _current_seed := -1
var _actions_taken := 0
var _run_started_at_msec := 0
var _last_action_at_msec := 0
var _last_battle_over_type := -1
var _last_battle_over_text := ""
var _wins := 0
var _losses := 0
var _failures: PackedStringArray = []
var _initialized := false
var _last_action := ""
var _last_view_name := ""
var _action_log: Array[Dictionary] = []
var _room_history: Array[Dictionary] = []
var _last_report_at_msec := 0


func _ready() -> void:
	initialize_runner()


func initialize_runner() -> void:
	if _initialized:
		return
	_initialized = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Events.battle_over_screen_requested.is_connected(_on_battle_over_screen_requested):
		Events.battle_over_screen_requested.connect(_on_battle_over_screen_requested)
	start()


func start() -> void:
	call_deferred("_start_next_run")


func _process(_delta: float) -> void:
	if _active_run == null or not is_instance_valid(_active_run):
		return

	if _run_timed_out():
		_fail_current_run("timeout after %.2fs" % _get_run_elapsed_seconds())
		return

	if max_actions_per_run > 0 and _actions_taken >= max_actions_per_run:
		_fail_current_run("action limit reached (%s)" % max_actions_per_run)
		return

	var now := Time.get_ticks_msec()
	var current_view_name := _get_view_name(_get_current_view())
	if current_view_name != _last_view_name:
		_last_view_name = current_view_name
		_write_running_report()
	elif now - _last_report_at_msec >= REPORT_INTERVAL_MSEC:
		_write_running_report()

	if now - _last_action_at_msec < int(action_delay_seconds * 1000.0):
		return

	_step_current_run()


func configure_from_args(arguments: PackedStringArray) -> void:
	for argument: String in arguments:
		if argument.begins_with("--runs="):
			runs_to_play = maxi(1, argument.trim_prefix("--runs=").to_int())
		elif argument.begins_with("--max-actions="):
			max_actions_per_run = maxi(0, argument.trim_prefix("--max-actions=").to_int())
		elif argument.begins_with("--max-seconds="):
			max_seconds_per_run = maxf(0.0, argument.trim_prefix("--max-seconds=").to_float())
		elif argument.begins_with("--delay="):
			action_delay_seconds = maxf(0.0, argument.trim_prefix("--delay=").to_float())
		elif argument.begins_with("--seed="):
			seed_override = argument.trim_prefix("--seed=").to_int()
		elif argument == "--quiet":
			verbose_logging = false


func configure_from_environment() -> void:
	var env_runs := OS.get_environment("QA_RUNS")
	if not env_runs.is_empty():
		runs_to_play = maxi(1, env_runs.to_int())

	var env_actions := OS.get_environment("QA_MAX_ACTIONS")
	if not env_actions.is_empty():
		max_actions_per_run = maxi(0, env_actions.to_int())

	var env_seconds := OS.get_environment("QA_MAX_SECONDS")
	if not env_seconds.is_empty():
		max_seconds_per_run = maxf(0.0, env_seconds.to_float())

	var env_delay := OS.get_environment("QA_ACTION_DELAY")
	if not env_delay.is_empty():
		action_delay_seconds = maxf(0.0, env_delay.to_float())

	var env_seed := OS.get_environment("QA_SEED")
	if not env_seed.is_empty():
		seed_override = env_seed.to_int()

	var env_quiet := OS.get_environment("QA_QUIET").to_lower()
	if env_quiet in ["1", "true", "yes"]:
		verbose_logging = false


func _start_next_run() -> void:
	if _current_run_index >= runs_to_play:
		_finish_suite()
		return

	get_tree().paused = false
	_clear_active_run()

	_current_run_index += 1
	_actions_taken = 0
	_last_action_at_msec = 0
	_last_battle_over_type = -1
	_last_battle_over_text = ""
	_last_action = ""
	_last_view_name = ""
	_action_log.clear()
	_room_history.clear()
	_last_report_at_msec = 0
	_current_seed = _resolve_seed(_current_run_index)
	_run_started_at_msec = Time.get_ticks_msec()

	if RNG.instance == null:
		RNG.initialize()
	RNG.instance.seed = _current_seed
	SaveGame.save_path_override = "user://qa_autoplay_save_%s.tres" % _current_seed
	SaveGame.delete_data()

	var startup := RunStartup.new()
	startup.type = RunStartup.Type.NEW_RUN
	startup.picked_character = DEFAULT_CHARACTER

	_active_run = RUN_SCENE.instantiate() as Run
	_active_run.run_startup = startup
	add_child(_active_run)

	_log("run_start seed=%s run=%s/%s" % [_current_seed, _current_run_index, runs_to_play])
	_write_report("running")


func _step_current_run() -> void:
	if get_tree().paused:
		_handle_paused_state()
		return

	if _active_run == null or not is_instance_valid(_active_run):
		return

	var current_view := _get_current_view()
	_last_view_name = _get_view_name(current_view)
	if current_view is WinScreen:
		_complete_run(true, "victory")
		return

	if _active_run.map.visible:
		_select_next_map_room()
		return

	if current_view == null:
		return

	if current_view is Battle:
		_handle_battle(current_view)
	elif current_view is BattleReward:
		_handle_battle_rewards(current_view)
	elif current_view is Shop:
		_handle_shop(current_view)
	elif current_view is Campfire:
		_handle_campfire(current_view)
	elif current_view is Treasure:
		_handle_treasure(current_view)
	elif current_view is ApprovalRoom:
		_handle_approval_room(current_view)
	elif current_view is EventRoom:
		_handle_event_room(current_view)


func _handle_paused_state() -> void:
	match _last_battle_over_type:
		BattleOverPanel.Type.WIN:
			_record_action("battle_panel_continue")
			_last_battle_over_type = -1
			_last_battle_over_text = ""
			Events.battle_won.emit()
		BattleOverPanel.Type.LOSE:
			_complete_run(false, _last_battle_over_text if not _last_battle_over_text.is_empty() else "battle lost")


func _handle_battle(battle: Battle) -> void:
	var player_handler := battle.player_handler
	var battle_ui := battle.battle_ui
	if player_handler == null or battle_ui == null:
		return

	var playable_card := _pick_playable_card(battle)
	if playable_card != null:
		if playable_card.card.is_single_targeted():
			var target := _pick_enemy_target(battle.enemy_handler)
			if target == null:
				_fail_current_run("single-target card %s had no enemy target" % playable_card.card.id)
				return
			playable_card.targets = [target]
		else:
			playable_card.targets = [battle.player]

		_record_action("play %s" % playable_card.card.id)
		playable_card.play()
		return

	if player_handler.can_draw_from_backlog():
		_record_action("draw backlog")
		battle_ui._on_backlog_button_pressed()
		return

	if player_handler.is_player_turn and not battle_ui.end_turn_button.disabled:
		_record_action("end turn")
		battle_ui._on_end_turn_button_pressed()


func _handle_battle_rewards(reward_view: BattleReward) -> void:
	for child: Node in reward_view.get_children():
		if child is CardRewards:
			var card_rewards := child as CardRewards
			if card_rewards.selected_card == null and not card_rewards.rewards.is_empty():
				_record_action("preview reward %s" % card_rewards.rewards[0].id)
				card_rewards._show_tooltip(card_rewards.rewards[0])
			else:
				_record_action("take card reward")
				card_rewards.take_button.emit_signal("pressed")
			return

	for child: Node in reward_view.rewards.get_children():
		if child is RewardButton:
			_record_action("take reward button")
			(child as RewardButton).emit_signal("pressed")
			return

	_record_action("leave rewards")
	reward_view._on_back_button_pressed()


func _handle_shop(shop: Shop) -> void:
	for shop_card: Node in shop.cards.get_children():
		if not (shop_card is ShopCard):
			continue

		var card_offer := shop_card as ShopCard
		if not is_instance_valid(card_offer):
			continue

		var card_button := card_offer.buy_button
		if card_button == null or not is_instance_valid(card_button) or card_button.disabled:
			continue

		_record_action("buy card %s" % card_offer.card.id)
		card_button.emit_signal("pressed")
		call_deferred("_write_running_report")
			return

	for shop_relic: Node in shop.relics.get_children():
		if not (shop_relic is ShopRelic):
			continue

		var relic_offer := shop_relic as ShopRelic
		if not is_instance_valid(relic_offer):
			continue

		var relic_button := relic_offer.buy_button
		if relic_button == null or not is_instance_valid(relic_button) or relic_button.disabled:
			continue

		_record_action("buy relic")
		relic_button.emit_signal("pressed")
		call_deferred("_write_running_report")
			return

	_record_action("leave shop")
	shop._on_back_button_pressed()


func _handle_campfire(campfire: Campfire) -> void:
	if not campfire.rest_button.disabled:
		_record_action("campfire rest")
		campfire._on_rest_button_pressed()
		return

	_record_action("leave campfire")
	campfire._on_fade_out_finished()


func _handle_treasure(treasure: Treasure) -> void:
	_record_action("open treasure")
	treasure._on_treasure_opened()


func _handle_approval_room(approval_room: ApprovalRoom) -> void:
	if approval_room.candidates.is_empty():
		_record_action("leave approval (no candidates)")
		approval_room._leave_room()
		return

	if approval_room.selected_card == null:
		_record_action("preview approval %s" % approval_room.candidates[0].id)
		approval_room._show_tooltip(approval_room.candidates[0])
		return

	_record_action("stamp %s" % approval_room.selected_card.id)
	approval_room._stamp_selected_card()


func _handle_event_room(event_room: EventRoom) -> void:
	var buttons := _collect_event_buttons(event_room)
	for button in buttons:
		if button.visible and not button.disabled:
			_record_action("event choice %s" % button.name)
			button.emit_signal("pressed")
			return

	_record_action("leave event")
	Events.event_room_exited.emit()


func _select_next_map_room() -> void:
	var available_rooms: Array[MapRoom] = []
	for child: Node in _active_run.map.rooms.get_children():
		if child is MapRoom and (child as MapRoom).available:
			available_rooms.append(child as MapRoom)

	if available_rooms.is_empty():
		return

	var chosen_room := _pick_best_room(available_rooms)
	chosen_room.room.selected = true
	_room_history.append({
		"step": _actions_taken + 1,
		"elapsed_seconds": _get_run_elapsed_seconds(),
		"floor": chosen_room.room.row,
		"type": _room_type_name(chosen_room.room.type),
		"x": chosen_room.room.position.x,
		"y": chosen_room.room.position.y,
	})
	if _room_history.size() > ROOM_HISTORY_LIMIT:
		_room_history.pop_front()
	_record_action("map select %s floor=%s" % [_room_type_name(chosen_room.room.type), chosen_room.room.row])
	_active_run.map._on_map_room_clicked(chosen_room.room)
	_active_run.map._on_map_room_selected(chosen_room.room)


func _pick_playable_card(battle: Battle) -> CardUI:
	if battle.player_handler == null or not battle.player_handler.is_player_turn:
		return null

	for child: Node in battle.battle_ui.hand.get_children():
		if not (child is CardUI):
			continue

		var card_ui := child as CardUI
		if card_ui.disabled or card_ui.card == null:
			continue
		if not card_ui.card.can_play(battle.char_stats, _active_run.stats):
			continue
		if card_ui.card.is_single_targeted() and _pick_enemy_target(battle.enemy_handler) == null:
			continue
		return card_ui

	return null


func _pick_enemy_target(enemy_handler: EnemyHandler) -> Enemy:
	var chosen_enemy: Enemy
	for child: Node in enemy_handler.get_children():
		if not (child is Enemy):
			continue

		var enemy := child as Enemy
		if enemy.stats == null or enemy.stats.health <= 0:
			continue
		if chosen_enemy == null or enemy.stats.health < chosen_enemy.stats.health:
			chosen_enemy = enemy

	return chosen_enemy


func _pick_best_room(available_rooms: Array[MapRoom]) -> MapRoom:
	var chosen_room := available_rooms[0]
	var chosen_score := _get_room_score(chosen_room.room)

	for map_room: MapRoom in available_rooms:
		var score := _get_room_score(map_room.room)
		if score > chosen_score:
			chosen_room = map_room
			chosen_score = score

	return chosen_room


func _get_room_score(room: Room) -> int:
	var type_score := 0
	match room.type:
		Room.Type.APPROVAL:
			type_score = 70
		Room.Type.EVENT:
			type_score = 60
		Room.Type.TREASURE:
			type_score = 50
		Room.Type.CAMPFIRE:
			type_score = 40
		Room.Type.SHOP:
			type_score = 30
		Room.Type.MONSTER:
			type_score = 20
		Room.Type.BOSS:
			type_score = 10

	return type_score - int(room.position.x)


func _collect_event_buttons(event_room: EventRoom) -> Array[EventRoomButton]:
	var buttons: Array[EventRoomButton] = []
	_collect_event_buttons_recursive(event_room, buttons)
	return buttons


func _collect_event_buttons_recursive(node: Node, buttons: Array[EventRoomButton]) -> void:
	for child: Node in node.get_children():
		if child is EventRoomButton:
			buttons.append(child as EventRoomButton)
		_collect_event_buttons_recursive(child, buttons)


func _get_current_view() -> Node:
	if _active_run == null or not is_instance_valid(_active_run):
		return null
	if _active_run.current_view == null or _active_run.current_view.get_child_count() == 0:
		return null
	return _active_run.current_view.get_child(0)


func _run_timed_out() -> bool:
	if max_seconds_per_run <= 0.0:
		return false
	return _get_run_elapsed_seconds() > max_seconds_per_run


func _get_run_elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _run_started_at_msec) / 1000.0


func _resolve_seed(run_index: int) -> int:
	if seed_override >= 0:
		return seed_override + run_index - 1
	return int(Time.get_unix_time_from_system()) + run_index - 1


func _complete_run(won: bool, reason: String) -> void:
	get_tree().paused = false
	if won:
		_wins += 1
	else:
		_losses += 1
		_failures.append("Run %s failed: %s" % [_current_run_index, reason])

	_log("run_complete run=%s won=%s actions=%s time=%.2fs reason=%s" % [
		_current_run_index,
		won,
		_actions_taken,
		_get_run_elapsed_seconds(),
		reason,
	])

	_clear_active_run()
	call_deferred("_start_next_run")


func _fail_current_run(reason: String) -> void:
	_complete_run(false, reason)


func _finish_suite() -> void:
	get_tree().paused = false
	SaveGame.delete_data()
	SaveGame.save_path_override = ""

	for failure: String in _failures:
		_log(failure)

	_log("suite_complete wins=%s losses=%s" % [_wins, _losses])
	var exit_code := 0 if _failures.is_empty() else 1
	_write_report("completed", exit_code)
	finished.emit(exit_code)


func _clear_active_run() -> void:
	if _active_run != null and is_instance_valid(_active_run):
		_active_run.queue_free()
	_active_run = null


func _record_action(description: String) -> void:
	_actions_taken += 1
	_last_action_at_msec = Time.get_ticks_msec()
	_last_action = description
	_action_log.append({
		"step": _actions_taken,
		"elapsed_seconds": _get_run_elapsed_seconds(),
		"view": _get_view_name(_get_current_view()),
		"action": description,
	})
	if _action_log.size() > ACTION_LOG_LIMIT:
		_action_log.pop_front()
	_log("action run=%s step=%s %s" % [_current_run_index, _actions_taken, description])
	call_deferred("_write_running_report")


func _on_battle_over_screen_requested(text: String, type: BattleOverPanel.Type) -> void:
	_last_battle_over_text = text
	_last_battle_over_type = type
	_log("battle_over type=%s text=%s" % [type, text])
	call_deferred("_write_running_report")


func _room_type_name(type: int) -> String:
	match type:
		Room.Type.MONSTER:
			return "monster"
		Room.Type.TREASURE:
			return "treasure"
		Room.Type.CAMPFIRE:
			return "campfire"
		Room.Type.SHOP:
			return "shop"
		Room.Type.BOSS:
			return "boss"
		Room.Type.EVENT:
			return "event"
		Room.Type.APPROVAL:
			return "approval"
	return "unknown"


func _log(message: String) -> void:
	if verbose_logging:
		print("[QA] %s" % message)


func _write_report(status: String, exit_code: int = -1) -> void:
	var report := {
		"status": status,
		"runs_requested": runs_to_play,
		"current_run": _current_run_index,
		"seed": _current_seed,
		"actions_taken": _actions_taken,
		"wins": _wins,
		"losses": _losses,
		"failures": _failures,
		"elapsed_seconds": _get_run_elapsed_seconds(),
		"exit_code": exit_code,
		"last_action": _last_action,
		"current_view": _get_view_name(_get_current_view()),
		"paused": get_tree().paused,
		"battle_over": {
			"text": _last_battle_over_text,
			"type": _get_battle_over_type_name(_last_battle_over_type),
		},
		"room_history": _room_history,
		"action_log_tail": _action_log,
		"player_state": _get_player_state(),
		"pile_counts": _get_pile_counts(),
		"hand_state": _get_hand_state(),
		"enemy_state": _get_enemy_state(),
		"map_state": _get_map_state(),
	}

	var report_file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if report_file == null:
		push_warning("Could not write QA report to %s" % REPORT_PATH)
		return

	report_file.store_string(JSON.stringify(report, "\t"))


func _write_running_report() -> void:
	_last_report_at_msec = Time.get_ticks_msec()
	_write_report("running")


func _get_view_name(view: Node) -> String:
	if view == null:
		if _active_run != null and is_instance_valid(_active_run) and _active_run.map.visible:
			return "Map"
		return "None"
	if view is Battle:
		return "Battle"
	if view is BattleReward:
		return "BattleReward"
	if view is Shop:
		return "Shop"
	if view is Campfire:
		return "Campfire"
	if view is Treasure:
		return "Treasure"
	if view is ApprovalRoom:
		return "ApprovalRoom"
	if view is EventRoom:
		return "EventRoom"
	if view is WinScreen:
		return "WinScreen"
	return view.get_class()


func _get_battle_over_type_name(type: int) -> String:
	match type:
		BattleOverPanel.Type.WIN:
			return "win"
		BattleOverPanel.Type.LOSE:
			return "lose"
	return ""


func _get_player_state() -> Dictionary:
	if _active_run == null or not is_instance_valid(_active_run):
		return {}

	var character := _active_run.character
	var run_stats := _active_run.stats
	if character == null:
		return {}

	return {
		"health": character.health,
		"max_health": character.max_health,
		"block": character.block,
		"mana": character.mana,
		"max_mana": character.max_mana,
		"cards_per_turn": character.cards_per_turn,
		"gold": run_stats.gold if run_stats != null else 0,
		"budget": run_stats.budget if run_stats != null else 0,
	}


func _get_pile_counts() -> Dictionary:
	if _active_run == null or not is_instance_valid(_active_run):
		return {}

	var character := _active_run.character
	if character == null:
		return {}

	character.ensure_runtime_piles()
	var hand_count := 0
	var current_view := _get_current_view()
	if current_view is Battle:
		hand_count = (current_view as Battle).battle_ui.hand.get_child_count()

	return {
		"deck": character.deck.cards.size(),
		"draw_pile": character.draw_pile.cards.size(),
		"discard": character.discard.cards.size(),
		"backlog": character.backlog.cards.size(),
		"hand": hand_count,
	}


func _get_hand_state() -> Array[Dictionary]:
	var current_view := _get_current_view()
	if not (current_view is Battle):
		return []

	var hand_cards: Array[Dictionary] = []
	for child: Node in (current_view as Battle).battle_ui.hand.get_children():
		if not (child is CardUI):
			continue
		var card_ui := child as CardUI
		if card_ui.card == null:
			continue
		hand_cards.append({
			"id": card_ui.card.id,
			"cost": card_ui.card.cost,
			"single_target": card_ui.card.is_single_targeted(),
			"disabled": card_ui.disabled,
			"playable": card_ui.card.can_play((current_view as Battle).char_stats, _active_run.stats),
		})
	return hand_cards


func _get_enemy_state() -> Array[Dictionary]:
	var current_view := _get_current_view()
	if not (current_view is Battle):
		return []

	var enemy_state: Array[Dictionary] = []
	for child: Node in (current_view as Battle).enemy_handler.get_children():
		if not (child is Enemy):
			continue
		var enemy := child as Enemy
		if enemy.stats == null:
			continue
		enemy_state.append({
			"name": enemy.name,
			"health": enemy.stats.health,
			"max_health": enemy.stats.max_health,
			"block": enemy.stats.block,
			"has_action": enemy.current_action != null,
		})
	return enemy_state


func _get_map_state() -> Dictionary:
	if _active_run == null or not is_instance_valid(_active_run):
		return {}

	var available_rooms: Array[Dictionary] = []
	for child: Node in _active_run.map.rooms.get_children():
		if not (child is MapRoom):
			continue
		var map_room := child as MapRoom
		if not map_room.available:
			continue
		available_rooms.append({
			"floor": map_room.room.row,
			"type": _room_type_name(map_room.room.type),
			"x": map_room.room.position.x,
			"y": map_room.room.position.y,
		})

	var last_room := {}
	if _active_run.map.last_room != null:
		last_room = {
			"floor": _active_run.map.last_room.row,
			"type": _room_type_name(_active_run.map.last_room.type),
			"x": _active_run.map.last_room.position.x,
			"y": _active_run.map.last_room.position.y,
		}

	return {
		"map_visible": _active_run.map.visible,
		"floors_climbed": _active_run.map.floors_climbed,
		"last_room": last_room,
		"available_rooms": available_rooms,
	}
