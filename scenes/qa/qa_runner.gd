class_name QARunner
extends Node

signal finished(exit_code: int)

enum PolicyMode {
	NORMAL,
	DUMB,
	BACKLOG_HEAVY,
	COVERAGE_HEAVY,
}

const RUN_SCENE := preload("res://scenes/run/run.tscn")
const DEFAULT_CHARACTER := preload("res://characters/warrior/warrior.tres")
const REPORT_PATH := "user://qa_autoplay_last_run.json"
const ACTION_LOG_LIMIT := 40
const ROOM_HISTORY_LIMIT := 20
const REPORT_INTERVAL_MSEC := 500
const PREFLIGHT_ERROR_LIMIT := 10
const COVERAGE_ROOM_TARGETS := ["monster", "treasure", "campfire", "shop", "boss", "event", "approval"]
const COVERAGE_VIEW_TARGETS := [
	"Map",
	"Battle",
	"BattleReward",
	"Shop",
	"Campfire",
	"Treasure",
	"ApprovalRoom",
	"EventRoom",
	"WinScreen",
]
const COVERAGE_MECHANIC_TARGETS := [
	"damage",
	"block",
	"draw",
	"exposed",
	"budget",
	"backlog_file",
	"backlog_draw",
	"chain",
	"exhaust",
	"power",
]

@export_range(1, 100) var runs_to_play := 1
@export_range(0, 10000) var max_actions_per_run := 800
@export_range(0.0, 3600.0, 1.0) var max_seconds_per_run := 180.0
@export_range(0.0, 120.0, 0.5) var max_idle_seconds := 8.0
@export_range(0.0, 5.0, 0.01) var action_delay_seconds := 0.05
@export_range(1.0, 10.0, 0.5) var engine_time_scale := 4.0
@export var seed_override := -1
@export var verbose_logging := true
@export var run_promoted_card_preflight := true
@export var policy_mode := PolicyMode.NORMAL

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
var _last_progress_at_msec := 0
var _preflight_errors: PackedStringArray = []
var _previous_engine_time_scale := 1.0
var _last_state_snapshot := {}
var _configured_policy_names := PackedStringArray()
var _run_summaries: Array[Dictionary] = []
var _current_views_seen := {}
var _current_room_type_counts := {}
var _current_mechanic_counts := {}
var _current_invariant_warnings := PackedStringArray()


func _ready() -> void:
	initialize_runner()


func initialize_runner() -> void:
	if _initialized:
		return
	_initialized = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_engine_time_scale = Engine.time_scale
	Engine.time_scale = engine_time_scale
	if not Events.battle_over_screen_requested.is_connected(_on_battle_over_screen_requested):
		Events.battle_over_screen_requested.connect(_on_battle_over_screen_requested)
	start()


func start() -> void:
	_run_summaries.clear()
	call_deferred("_start_next_run")


func _process(_delta: float) -> void:
	if _active_run == null or not is_instance_valid(_active_run):
		return

	if _run_timed_out():
		_fail_current_run("timeout after %.2fs" % _get_run_elapsed_seconds())
		return

	if _run_stalled():
		_fail_current_run("stalled in %s after %.2fs idle (last action: %s)" % [
			_get_view_name(_get_current_view()),
			_get_idle_seconds(),
			_last_action,
		])
		return

	if max_actions_per_run > 0 and _actions_taken >= max_actions_per_run:
		_fail_current_run("action limit reached (%s)" % max_actions_per_run)
		return

	var now := Time.get_ticks_msec()
	var current_view_name := _get_view_name(_get_current_view())
	if current_view_name != _last_view_name:
		_last_view_name = current_view_name
		_increment_count(_current_views_seen, current_view_name)
		_mark_progress()
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
		elif argument.begins_with("--max-idle="):
			max_idle_seconds = maxf(0.0, argument.trim_prefix("--max-idle=").to_float())
		elif argument.begins_with("--delay="):
			action_delay_seconds = maxf(0.0, argument.trim_prefix("--delay=").to_float())
		elif argument.begins_with("--seed="):
			seed_override = argument.trim_prefix("--seed=").to_int()
		elif argument.begins_with("--policy="):
			policy_mode = _parse_policy_mode(argument.trim_prefix("--policy="))
		elif argument.begins_with("--policies="):
			_configure_policy_list(argument.trim_prefix("--policies="))
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

	var env_idle := OS.get_environment("QA_MAX_IDLE_SECONDS")
	if not env_idle.is_empty():
		max_idle_seconds = maxf(0.0, env_idle.to_float())

	var env_delay := OS.get_environment("QA_ACTION_DELAY")
	if not env_delay.is_empty():
		action_delay_seconds = maxf(0.0, env_delay.to_float())

	var env_seed := OS.get_environment("QA_SEED")
	if not env_seed.is_empty():
		seed_override = env_seed.to_int()

	var env_policy := OS.get_environment("QA_POLICY")
	if not env_policy.is_empty():
		policy_mode = _parse_policy_mode(env_policy)

	var env_policies := OS.get_environment("QA_POLICIES")
	if not env_policies.is_empty():
		_configure_policy_list(env_policies)

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
	_last_progress_at_msec = Time.get_ticks_msec()
	_preflight_errors.clear()
	_last_state_snapshot = {}
	_current_views_seen = {}
	_current_room_type_counts = {}
	_current_mechanic_counts = {}
	_current_invariant_warnings.clear()
	_current_seed = _resolve_seed(_current_run_index)
	policy_mode = _resolve_policy_mode(_current_run_index)
	_run_started_at_msec = Time.get_ticks_msec()

	if RNG.instance == null:
		RNG.initialize()
	RNG.instance.seed = _current_seed
	seed(_current_seed)
	SaveGame.save_path_override = "user://qa_autoplay_save_%s.tres" % _current_seed
	SaveGame.delete_data()

	var startup := RunStartup.new()
	startup.type = RunStartup.Type.NEW_RUN
	startup.picked_character = DEFAULT_CHARACTER

	if run_promoted_card_preflight:
		_preflight_errors = _get_promoted_card_preflight_errors()
		if not _preflight_errors.is_empty():
			var summary := PackedStringArray(_preflight_errors.slice(0, PREFLIGHT_ERROR_LIMIT))
			var reason := "promoted card preflight failed (%s): %s" % [
				_preflight_errors.size(),
				"; ".join(summary),
			]
			if _preflight_errors.size() > PREFLIGHT_ERROR_LIMIT:
				reason += "; ..."
			_fail_current_run(reason)
			return

	_active_run = RUN_SCENE.instantiate() as Run
	_active_run.run_startup = startup
	add_child(_active_run)

	_log("run_start seed=%s run=%s/%s policy=%s" % [_current_seed, _current_run_index, runs_to_play, _get_policy_mode_name()])
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

	if policy_mode == PolicyMode.DUMB and _should_draw_from_backlog_dumb(battle):
		_record_action("draw backlog")
		battle_ui._on_backlog_button_pressed()
		return

	var choice := _pick_playable_card(battle)
	var playable_card: CardUI = choice.get("card_ui")
	if playable_card != null:
		var target: Node = choice.get("target")
		if playable_card.card.is_single_targeted():
			if target == null:
				_fail_current_run("single-target card %s had no enemy target" % playable_card.card.id)
				return
			playable_card.targets = [target]
		else:
			playable_card.targets = [target if target != null else battle.player]

		_record_action("play %s" % playable_card.card.id)
		_track_card_mechanics(playable_card.card)
		playable_card.play()
		return

	if _should_draw_from_backlog(battle):
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
			if policy_mode == PolicyMode.DUMB:
				_handle_battle_rewards_dumb(card_rewards)
				return

			var best_reward := _pick_best_reward_card(card_rewards.rewards)
			if card_rewards.selected_card == null and best_reward != null:
				_record_action("preview reward %s" % best_reward.id)
				card_rewards._show_tooltip(best_reward)
			elif best_reward == null:
				_record_action("skip card reward")
				card_rewards.skip_card_reward.emit_signal("pressed")
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
	if policy_mode == PolicyMode.DUMB:
		if _handle_shop_dumb(shop):
			return

	var best_card_offer: ShopCard
	var best_card_score := -INF
	for shop_card: Node in shop.cards.get_children():
		if not (shop_card is ShopCard):
			continue

		var card_offer := shop_card as ShopCard
		if not is_instance_valid(card_offer):
			continue

		var card_button := card_offer.buy_button
		if card_button == null or not is_instance_valid(card_button) or card_button.disabled:
			continue
		if card_offer.card == null:
			continue

		var offer_score := _score_reward_card(card_offer.card) - (float(card_offer.gold_cost) / 35.0)
		if offer_score > best_card_score:
			best_card_score = offer_score
			best_card_offer = card_offer

	if best_card_offer != null and best_card_score >= 2.0:
		_record_action("buy card %s" % best_card_offer.card.id)
		best_card_offer.buy_button.emit_signal("pressed")
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
		var candidate := approval_room.candidates[0]
		if policy_mode == PolicyMode.DUMB:
			candidate = _pick_random_from_array(approval_room.candidates)
		_record_action("preview approval %s" % candidate.id)
		approval_room._show_tooltip(candidate)
		return

	_record_action("stamp %s" % approval_room.selected_card.id)
	approval_room._stamp_selected_card()


func _handle_event_room(event_room: EventRoom) -> void:
	var buttons := _collect_event_buttons(event_room)
	if policy_mode == PolicyMode.DUMB:
		var random_button := _pick_random_enabled_event_button(buttons)
		if random_button != null:
			_record_action("event choice %s" % random_button.name)
			random_button.emit_signal("pressed")
			return

	var chosen_button := _pick_best_event_button(event_room, buttons)
	if chosen_button != null:
		_record_action("event choice %s" % chosen_button.name)
		chosen_button.emit_signal("pressed")
		return

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
	if policy_mode == PolicyMode.DUMB:
		chosen_room = _pick_random_from_array(available_rooms)
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
	_increment_count(_current_room_type_counts, _room_type_name(chosen_room.room.type))
	_record_action("map select %s floor=%s" % [_room_type_name(chosen_room.room.type), chosen_room.room.row])
	_active_run.map._on_map_room_clicked(chosen_room.room)
	_active_run.map._on_map_room_selected(chosen_room.room)


func _pick_playable_card(battle: Battle) -> Dictionary:
	if policy_mode == PolicyMode.DUMB:
		return _pick_playable_card_dumb(battle)
	if battle.player_handler == null or not battle.player_handler.is_player_turn:
		return {}

	var best_card: CardUI
	var best_target: Node
	var best_score := -INF
	for child: Node in battle.battle_ui.hand.get_children():
		if not (child is CardUI):
			continue

		var card_ui := child as CardUI
		if card_ui.disabled or card_ui.card == null:
			continue
		if not card_ui.card.can_play(battle.char_stats, _active_run.stats):
			continue
		var target := _pick_target_for_card(card_ui.card, battle)
		if card_ui.card.is_single_targeted() and target == null:
			continue
		var score := _score_card_play(card_ui.card, battle, target)
		if score > best_score:
			best_score = score
			best_card = card_ui
			best_target = target

	if best_card == null or best_score < -20.0:
		return {}

	return {
		"card_ui": best_card,
		"target": best_target,
		"score": best_score,
	}


func _pick_playable_card_dumb(battle: Battle) -> Dictionary:
	if battle.player_handler == null or not battle.player_handler.is_player_turn:
		return {}

	var playable_choices: Array[Dictionary] = []
	for child: Node in battle.battle_ui.hand.get_children():
		if not (child is CardUI):
			continue
		var card_ui := child as CardUI
		if card_ui.disabled or card_ui.card == null:
			continue
		if not card_ui.card.can_play(battle.char_stats, _active_run.stats):
			continue
		var target := _pick_target_for_card_dumb(card_ui.card, battle)
		if card_ui.card.is_single_targeted() and target == null:
			continue
		playable_choices.append({
			"card_ui": card_ui,
			"target": target,
			"score": 0.0,
		})

	if playable_choices.is_empty():
		return {}
	if _qa_randf() < 0.18:
		return {}
	return _pick_random_from_array(playable_choices)


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


func _pick_target_for_card(card: Card, battle: Battle) -> Node:
	if card == null:
		return null
	if card.is_single_targeted():
		var best_enemy: Enemy
		var best_score := -INF
		for enemy: Enemy in _get_living_enemies(battle.enemy_handler):
			var score := _score_enemy_target(card, enemy)
			if score > best_score:
				best_score = score
				best_enemy = enemy
		return best_enemy
	return battle.player


func _pick_target_for_card_dumb(card: Card, battle: Battle) -> Node:
	if card == null:
		return null
	if card.is_single_targeted():
		return _pick_random_from_array(_get_living_enemies(battle.enemy_handler))
	return battle.player


func _score_card_play(card: Card, battle: Battle, target: Node) -> float:
	if card == null:
		return -INF

	if card.id == "bureaucracy_misfiled_notice":
		return -1000.0

	var living_enemies: Array[Enemy] = _get_living_enemies(battle.enemy_handler)
	var enemy_count: int = living_enemies.size()
	var threat: int = _estimate_enemy_threat(battle.enemy_handler)
	var missing_block: int = maxi(0, threat - battle.char_stats.block)
	var score := 0.0
	var effective_damage := card.damage + card.chain_bonus_damage
	var effective_block := card.block_amount + card.chain_bonus_block
	var effective_draw := card.cards_to_draw + card.chain_bonus_cards_to_draw
	var effective_exposed := card.exposed_to_apply + card.chain_bonus_exposed_to_apply
	var top_backlog_card := _get_top_backlog_card(battle.player_handler)
	var has_immediate_value := (
		effective_damage > 0
		or effective_block > 0
		or effective_draw > 0
		or effective_exposed > 0
		or card.draw_from_backlog > 0
		or card.budget_gain > 0
	)

	match card.target:
		Card.Target.SINGLE_ENEMY:
			var enemy := target as Enemy
			effective_damage = maxi(effective_damage, card.damage)
			score += effective_damage * 5.0
			if enemy != null and enemy.stats != null:
				if effective_damage >= enemy.stats.health:
					score += 100.0
				else:
					score += clampf(float(enemy.stats.max_health - enemy.stats.health), 0.0, 30.0)
		Card.Target.ALL_ENEMIES:
			score += float(effective_damage) * enemy_count * 4.0
			score += float(effective_exposed) * enemy_count * 3.0
		Card.Target.EVERYONE:
			score += float(effective_damage) * enemy_count * 3.0
			score += float(effective_block) * 0.5
		_:
			pass

	if effective_block > 0:
		score += minf(float(effective_block), float(missing_block)) * 2.0
		score += maxf(0.0, float(effective_block - missing_block)) * 0.25

	score += float(effective_draw) * 3.0
	score += _get_backlog_draw_score(card, top_backlog_card)
	score += float(card.budget_gain) * 3.0
	score += float(effective_exposed) * max(enemy_count, 1) * 2.0

	if card.file_to_backlog and score <= 0.0:
		score -= 10.0
	if card.exhausts and score <= 0.0:
		score -= 5.0
	if card.type == Card.Type.POWER:
		if has_immediate_value:
			score += 8.0
		else:
			score += 1.5
			score -= float(missing_block) * 1.75
			score -= float(threat) * 0.35
	if policy_mode == PolicyMode.COVERAGE_HEAVY:
		score += _get_card_coverage_bonus(card, 5.0)

	score -= float(card.cost) * 0.35
	return score


func _score_enemy_target(card: Card, enemy: Enemy) -> float:
	if card == null or enemy == null or enemy.stats == null:
		return -INF

	var score := 0.0
	var incoming := 0
	if enemy.current_action != null and enemy.current_action.intent != null:
		incoming = _parse_intent_damage(str(enemy.current_action.intent.current_text))

	var effective_damage := card.damage + card.chain_bonus_damage
	var effective_exposed := card.exposed_to_apply + card.chain_bonus_exposed_to_apply

	if effective_damage > 0:
		score += float(effective_damage) * 4.0
		if effective_damage >= enemy.stats.health:
			score += 120.0 + float(incoming) * 4.0
		else:
			score += clampf(float(enemy.stats.max_health - enemy.stats.health), 0.0, 25.0)

	score += float(incoming) * 2.5
	score += float(effective_exposed) * maxf(1.0, float(incoming))
	score += float(enemy.stats.max_health - enemy.stats.health) * 0.2

	return score


func _get_living_enemies(enemy_handler: EnemyHandler) -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	for child: Node in enemy_handler.get_children():
		if not (child is Enemy):
			continue
		var enemy := child as Enemy
		if enemy.stats == null or enemy.stats.health <= 0:
			continue
		enemies.append(enemy)
	return enemies


func _estimate_enemy_threat(enemy_handler: EnemyHandler) -> int:
	var total := 0
	for enemy: Enemy in _get_living_enemies(enemy_handler):
		if enemy.current_action == null or enemy.current_action.intent == null:
			continue
		total += _parse_intent_damage(str(enemy.current_action.intent.current_text))
	return total


func _parse_intent_damage(intent_text: String) -> int:
	var text := intent_text.strip_edges()
	if text.is_empty():
		return 0

	var multi_match := RegEx.new()
	if multi_match.compile("(\\d+)x(\\d+)") == OK:
		var found := multi_match.search(text)
		if found != null:
			return found.get_string(1).to_int() * found.get_string(2).to_int()

	var number_match := RegEx.new()
	if number_match.compile("(\\d+)") == OK:
		var number := number_match.search(text)
		if number != null:
			return number.get_string(1).to_int()

	return 0


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
	var health_ratio := _get_health_ratio()
	var gold := 0
	if _active_run != null and is_instance_valid(_active_run) and _active_run.stats != null:
		gold = _active_run.stats.gold

	var type_score := 0
	match room.type:
		Room.Type.APPROVAL:
			type_score = 65 if health_ratio >= 0.4 else 40
		Room.Type.EVENT:
			type_score = 60 if health_ratio >= 0.45 else 35
		Room.Type.TREASURE:
			type_score = 75
		Room.Type.CAMPFIRE:
			type_score = 110 if health_ratio < 0.6 else 55
		Room.Type.SHOP:
			type_score = 70 if gold >= 150 else 30
		Room.Type.MONSTER:
			type_score = 20
			if health_ratio < 0.45:
				type_score -= 25
		Room.Type.BOSS:
			type_score = 1000

	if policy_mode == PolicyMode.COVERAGE_HEAVY and room.type != Room.Type.BOSS:
		var room_name := _room_type_name(room.type)
		var visits := int(_current_room_type_counts.get(room_name, 0))
		if visits == 0:
			type_score += 45
		elif visits == 1:
			type_score += 15

	return type_score - int(room.position.x)


func _pick_best_reward_card(rewards: Array[Card]) -> Card:
	var best_card: Card
	var best_score := -INF
	for reward: Card in rewards:
		if reward == null:
			continue
		var score := _score_reward_card(reward)
		if score > best_score:
			best_score = score
			best_card = reward

	if best_score < 1.0:
		return null
	return best_card


func _score_reward_card(card: Card) -> float:
	if card == null:
		return -INF
	if card.id == "bureaucracy_misfiled_notice":
		return -1000.0

	var current_budget := 0
	if _active_run != null and is_instance_valid(_active_run) and _active_run.stats != null:
		current_budget = _active_run.stats.budget

	var score := 0.0
	score += float(card.damage) * (4.5 if card.target == Card.Target.SINGLE_ENEMY else 3.5)
	score += float(card.block_amount) * 2.5
	score += float(card.cards_to_draw) * 4.0
	score += float(card.draw_from_backlog) * 6.0
	score += float(card.budget_gain) * 3.5
	score += float(card.exposed_to_apply) * 2.5
	score += float(card.chain_bonus_damage) * 1.5
	score += float(card.chain_bonus_block) * 1.2
	score += float(card.chain_bonus_cards_to_draw) * 2.0
	score += float(card.chain_bonus_exposed_to_apply) * 1.2

	if card.type == Card.Type.POWER:
		score += 10.0
	if card.file_to_backlog:
		score += 2.0 if card.draw_from_backlog > 0 or card.damage > 0 or card.block_amount > 0 else -4.0
		if policy_mode == PolicyMode.BACKLOG_HEAVY:
			score += 12.0
	if policy_mode == PolicyMode.BACKLOG_HEAVY:
		score += float(card.draw_from_backlog) * 10.0
	if policy_mode == PolicyMode.COVERAGE_HEAVY:
		score += _get_card_coverage_bonus(card, 8.0)
	if card.exhausts:
		score -= 2.5
	if card.budget_cost > 0:
		score -= float(card.budget_cost) * 1.5
		if current_budget < card.budget_cost:
			score -= 12.0 + float(card.budget_cost - current_budget) * 4.0

	score -= float(card.cost) * 0.3
	return score


func _get_backlog_draw_score(card: Card, top_backlog_card: Card) -> float:
	if card == null or card.draw_from_backlog <= 0:
		return 0.0
	if top_backlog_card == null:
		return -6.0
	if top_backlog_card.id == "bureaucracy_misfiled_notice":
		return -60.0 * float(card.draw_from_backlog)

	return float(card.draw_from_backlog) * 2.0 + _score_reward_card(top_backlog_card) * 0.4


func _get_card_coverage_bonus(card: Card, unseen_bonus: float) -> float:
	var bonus := 0.0
	for tag: String in _get_card_mechanic_tags(card):
		if int(_current_mechanic_counts.get(tag, 0)) == 0:
			bonus += unseen_bonus
		elif int(_current_mechanic_counts.get(tag, 0)) == 1:
			bonus += unseen_bonus * 0.25
	return bonus


func _should_draw_from_backlog(battle: Battle) -> bool:
	if battle == null or battle.player_handler == null or not battle.player_handler.can_draw_from_backlog():
		return false
	if battle.player_handler.character == null or battle.player_handler.character.backlog == null:
		return false
	if battle.player_handler.character.backlog.cards.is_empty():
		return false

	var top_backlog_card := _get_top_backlog_card(battle.player_handler)
	if top_backlog_card == null or top_backlog_card.id == "bureaucracy_misfiled_notice":
		return false

	var threat := _estimate_enemy_threat(battle.enemy_handler)
	var health_ratio := 1.0
	if battle.char_stats != null and battle.char_stats.max_health > 0:
		health_ratio = float(battle.char_stats.health) / float(battle.char_stats.max_health)

	if threat > battle.char_stats.block:
		return false
	if health_ratio < 0.55:
		return false

	var score_threshold := 8.0
	if policy_mode == PolicyMode.BACKLOG_HEAVY:
		score_threshold = 4.0

	return _score_reward_card(top_backlog_card) >= score_threshold


func _should_draw_from_backlog_dumb(battle: Battle) -> bool:
	if battle == null or battle.player_handler == null or not battle.player_handler.can_draw_from_backlog():
		return false
	return _qa_randf() < 0.28


func _get_top_backlog_card(player_handler: PlayerHandler) -> Card:
	if player_handler == null or player_handler.character == null or player_handler.character.backlog == null:
		return null
	if player_handler.character.backlog.cards.is_empty():
		return null
	return player_handler.character.backlog.cards[0]


func _track_card_mechanics(card: Card) -> void:
	for tag: String in _get_card_mechanic_tags(card):
		_increment_count(_current_mechanic_counts, tag)


func _get_card_mechanic_tags(card: Card) -> PackedStringArray:
	var tags := PackedStringArray()
	if card == null:
		return tags
	if card.damage > 0 or card.chain_bonus_damage > 0:
		tags.append("damage")
	if card.block_amount > 0 or card.chain_bonus_block > 0:
		tags.append("block")
	if card.cards_to_draw > 0 or card.chain_bonus_cards_to_draw > 0:
		tags.append("draw")
	if card.exposed_to_apply > 0 or card.chain_bonus_exposed_to_apply > 0:
		tags.append("exposed")
	if card.budget_gain > 0 or card.budget_cost > 0:
		tags.append("budget")
	if card.file_to_backlog:
		tags.append("backlog_file")
	if card.draw_from_backlog > 0:
		tags.append("backlog_draw")
	if card.chain_step > 0 or not card.chain_id.is_empty():
		tags.append("chain")
	if card.exhausts:
		tags.append("exhaust")
	if card.type == Card.Type.POWER:
		tags.append("power")
	return tags


func _handle_battle_rewards_dumb(card_rewards: CardRewards) -> void:
	if card_rewards.selected_card == null:
		if not card_rewards.rewards.is_empty() and _qa_randf() < 0.8:
			var reward := _pick_random_from_array(card_rewards.rewards) as Card
			_record_action("preview reward %s" % reward.id)
			card_rewards._show_tooltip(reward)
		else:
			_record_action("skip card reward")
			card_rewards.skip_card_reward.emit_signal("pressed")
		return

	if _qa_randf() < 0.85:
		_record_action("take card reward")
		card_rewards.take_button.emit_signal("pressed")
	else:
		_record_action("skip card reward")
		card_rewards.skip_card_reward.emit_signal("pressed")


func _handle_shop_dumb(shop: Shop) -> bool:
	var card_offers: Array[ShopCard] = []
	for shop_card: Node in shop.cards.get_children():
		if shop_card is ShopCard:
			var offer := shop_card as ShopCard
			if is_instance_valid(offer) and offer.buy_button != null and is_instance_valid(offer.buy_button) and not offer.buy_button.disabled:
				card_offers.append(offer)

	var relic_offers: Array[ShopRelic] = []
	for shop_relic: Node in shop.relics.get_children():
		if shop_relic is ShopRelic:
			var relic_offer := shop_relic as ShopRelic
			if is_instance_valid(relic_offer) and relic_offer.buy_button != null and is_instance_valid(relic_offer.buy_button) and not relic_offer.buy_button.disabled:
				relic_offers.append(relic_offer)

	var roll := _qa_randf()
	if not card_offers.is_empty() and roll < 0.45:
		var chosen_card := _pick_random_from_array(card_offers) as ShopCard
		_record_action("buy card %s" % chosen_card.card.id)
		chosen_card.buy_button.emit_signal("pressed")
		call_deferred("_write_running_report")
		return true
	if not relic_offers.is_empty() and roll < 0.7:
		var chosen_relic := _pick_random_from_array(relic_offers) as ShopRelic
		_record_action("buy relic")
		chosen_relic.buy_button.emit_signal("pressed")
		call_deferred("_write_running_report")
		return true

	_record_action("leave shop")
	shop._on_back_button_pressed()
	return true


func _pick_random_enabled_event_button(buttons: Array[EventRoomButton]) -> EventRoomButton:
	var enabled_buttons: Array[EventRoomButton] = []
	for button in buttons:
		if button.visible and not button.disabled:
			enabled_buttons.append(button)
	return _pick_random_from_array(enabled_buttons)


func _pick_random_from_array(array: Array):
	if array.is_empty():
		return null
	if RNG.instance == null:
		RNG.initialize()
	return RNG.array_pick_random(array)


func _qa_randf() -> float:
	if RNG.instance == null:
		RNG.initialize()
	return RNG.instance.randf()


func _configure_policy_list(value: String) -> void:
	_configured_policy_names.clear()
	for raw_name: String in value.split(","):
		var normalized := raw_name.strip_edges().to_lower().replace("-", "_")
		if normalized.is_empty():
			continue
		_configured_policy_names.append(normalized)


func _parse_policy_mode(value: String) -> int:
	match value.strip_edges().to_lower():
		"dumb":
			return PolicyMode.DUMB
		"backlog-heavy", "backlog_heavy", "backlog":
			return PolicyMode.BACKLOG_HEAVY
		"coverage-heavy", "coverage_heavy", "coverage":
			return PolicyMode.COVERAGE_HEAVY
		_, "normal":
			return PolicyMode.NORMAL


func _resolve_policy_mode(run_index: int) -> int:
	if _configured_policy_names.is_empty():
		return policy_mode
	var slot := (run_index - 1) % _configured_policy_names.size()
	return _parse_policy_mode(_configured_policy_names[slot])


func _get_configured_policy_names() -> PackedStringArray:
	if not _configured_policy_names.is_empty():
		return _configured_policy_names
	return PackedStringArray([_get_policy_mode_name()])


func _get_policy_mode_name() -> String:
	match policy_mode:
		PolicyMode.DUMB:
			return "dumb"
		PolicyMode.BACKLOG_HEAVY:
			return "backlog_heavy"
		PolicyMode.COVERAGE_HEAVY:
			return "coverage_heavy"
		_:
			return "normal"


func _pick_best_event_button(event_room: EventRoom, buttons: Array[EventRoomButton]) -> EventRoomButton:
	var health_ratio := _get_health_ratio()
	var enabled_buttons: Array[EventRoomButton] = []
	for button in buttons:
		if button.visible and not button.disabled:
			enabled_buttons.append(button)

	if enabled_buttons.is_empty():
		return null

	for button in enabled_buttons:
		if button.name == "SkipButton":
			return button

	if event_room is HelpfulBoiEvent:
		for button in enabled_buttons:
			if button.name == "PlusMaxHPButton" and health_ratio < 0.85:
				return button
		for button in enabled_buttons:
			if button.name == "DuplicateLastCardButton":
				return button

	for button in enabled_buttons:
		if button.name == "ThirtyButton":
			return button
	for button in enabled_buttons:
		if button.name == "FiftyButton":
			return button

	return enabled_buttons[0]


func _get_health_ratio() -> float:
	if _active_run == null or not is_instance_valid(_active_run) or _active_run.character == null:
		return 1.0
	if _active_run.character.max_health <= 0:
		return 1.0
	return float(_active_run.character.health) / float(_active_run.character.max_health)


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


func _run_stalled() -> bool:
	if max_idle_seconds <= 0.0:
		return false
	return _get_idle_seconds() > max_idle_seconds


func _get_idle_seconds() -> float:
	return float(Time.get_ticks_msec() - _last_progress_at_msec) / 1000.0


func _complete_run(won: bool, reason: String) -> void:
	get_tree().paused = false
	var failure_category := _get_failure_category(reason, won)
	if won:
		_wins += 1
	else:
		_losses += 1
		_failures.append("Run %s failed [%s]: %s" % [_current_run_index, failure_category, reason])

	_log("run_complete run=%s won=%s actions=%s time=%.2fs reason=%s" % [
		_current_run_index,
		won,
		_actions_taken,
		_get_run_elapsed_seconds(),
		reason,
	])

	_last_state_snapshot = _capture_state_snapshot()
	_current_invariant_warnings = _collect_invariant_warnings(_last_state_snapshot)
	_run_summaries.append({
		"run": _current_run_index,
		"seed": _current_seed,
		"policy": _get_policy_mode_name(),
		"won": won,
		"reason": reason,
		"failure_category": failure_category,
		"actions_taken": _actions_taken,
		"elapsed_seconds": _get_run_elapsed_seconds(),
		"last_action": _last_action,
		"battle_over": {
			"text": _last_battle_over_text,
			"type": _get_battle_over_type_name(_last_battle_over_type),
		},
		"preflight_error_count": _preflight_errors.size(),
		"invariant_warnings": _current_invariant_warnings,
		"room_types": _copy_dictionary(_current_room_type_counts),
		"mechanics_seen": _copy_dictionary(_current_mechanic_counts),
		"views_seen": _copy_dictionary(_current_views_seen),
		"last_room": _room_history[-1] if not _room_history.is_empty() else {},
	})
	_clear_active_run()
	call_deferred("_start_next_run")


func _fail_current_run(reason: String) -> void:
	_complete_run(false, reason)


func _finish_suite() -> void:
	get_tree().paused = false
	Engine.time_scale = _previous_engine_time_scale
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
	_mark_progress()
	call_deferred("_write_running_report")


func _on_battle_over_screen_requested(text: String, type: BattleOverPanel.Type) -> void:
	_last_battle_over_text = text
	_last_battle_over_type = type
	_log("battle_over type=%s text=%s" % [type, text])
	_mark_progress()
	call_deferred("_write_running_report")


func _mark_progress() -> void:
	_last_progress_at_msec = Time.get_ticks_msec()


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
		"policy": _get_policy_mode_name(),
		"configured_policies": _get_configured_policy_names(),
		"actions_taken": _actions_taken,
		"wins": _wins,
		"losses": _losses,
		"failures": _failures,
		"elapsed_seconds": _get_run_elapsed_seconds(),
		"idle_seconds": _get_idle_seconds(),
		"exit_code": exit_code,
		"last_action": _last_action,
		"current_view": _get_snapshot_value("current_view", _get_view_name(_get_current_view())),
		"preflight_errors": _preflight_errors,
		"invariant_warnings": _current_invariant_warnings,
		"paused": get_tree().paused,
		"battle_over": {
			"text": _last_battle_over_text,
			"type": _get_battle_over_type_name(_last_battle_over_type),
		},
		"room_history": _room_history,
		"action_log_tail": _action_log,
		"run_summaries": _run_summaries,
		"suite_summary": _build_suite_summary(),
		"player_state": _get_snapshot_value("player_state", _get_player_state()),
		"pile_counts": _get_snapshot_value("pile_counts", _get_pile_counts()),
		"hand_state": _get_snapshot_value("hand_state", _get_hand_state()),
		"enemy_state": _get_snapshot_value("enemy_state", _get_enemy_state()),
		"map_state": _get_snapshot_value("map_state", _get_map_state()),
	}

	var report_file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if report_file == null:
		push_warning("Could not write QA report to %s" % REPORT_PATH)
		return

	report_file.store_string(JSON.stringify(report, "\t"))


func _write_running_report() -> void:
	_last_report_at_msec = Time.get_ticks_msec()
	_last_state_snapshot = _capture_state_snapshot()
	_current_invariant_warnings = _collect_invariant_warnings(_last_state_snapshot)
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


func _capture_state_snapshot() -> Dictionary:
	return {
		"current_view": _get_view_name(_get_current_view()),
		"player_state": _get_player_state(),
		"pile_counts": _get_pile_counts(),
		"hand_state": _get_hand_state(),
		"enemy_state": _get_enemy_state(),
		"map_state": _get_map_state(),
	}


func _get_snapshot_value(key: String, fallback):
	if _active_run != null and is_instance_valid(_active_run):
		return fallback
	if _last_state_snapshot.has(key):
		return _last_state_snapshot[key]
	return fallback


func _increment_count(counter: Dictionary, key: String, amount: int = 1) -> void:
	if key.is_empty():
		return
	counter[key] = int(counter.get(key, 0)) + amount


func _copy_dictionary(source: Dictionary) -> Dictionary:
	var copy := {}
	for key in source.keys():
		copy[key] = source[key]
	return copy


func _get_missing_targets(targets: Array, totals: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	for target in targets:
		var target_name := str(target)
		if int(totals.get(target_name, 0)) <= 0:
			missing.append(target_name)
	return missing


func _build_coverage_summary(targets: Array, totals: Dictionary) -> Dictionary:
	var missing := _get_missing_targets(targets, totals)
	return {
		"targets": PackedStringArray(targets),
		"missing": missing,
		"covered": targets.size() - missing.size(),
		"total_targets": targets.size(),
		"complete": missing.is_empty(),
	}


func _get_failure_category(reason: String, won: bool) -> String:
	if won:
		return "victory"

	var normalized_reason := reason.to_lower()
	if normalized_reason.contains("preflight"):
		return "preflight"
	if normalized_reason.contains("action limit"):
		return "action_limit"
	if normalized_reason.contains("timeout"):
		return "timeout"
	if normalized_reason.contains("stalled"):
		return "stall"
	if normalized_reason.contains("battle lost") or normalized_reason.contains("game over"):
		return "combat_loss"
	return "other_failure"


func _build_next_pass_recommendations(
	room_coverage: Dictionary,
	view_coverage: Dictionary,
	mechanic_coverage: Dictionary,
	failure_category_totals: Dictionary
) -> PackedStringArray:
	var recommendations := PackedStringArray()
	var missing_rooms: PackedStringArray = room_coverage.get("missing", PackedStringArray())
	var missing_views: PackedStringArray = view_coverage.get("missing", PackedStringArray())
	var missing_mechanics: PackedStringArray = mechanic_coverage.get("missing", PackedStringArray())

	if int(failure_category_totals.get("action_limit", 0)) > 0:
		recommendations.append("Increase QA_MAX_ACTIONS or QA_MAX_SECONDS before trusting coverage gaps; this suite was action-limited.")
	if int(failure_category_totals.get("stall", 0)) > 0:
		recommendations.append("Investigate stall runs first; stalled suites can hide real flow bugs behind missing coverage.")
	if not missing_rooms.is_empty() or not missing_views.is_empty():
		recommendations.append("Run a longer coverage_heavy batch to hit missing rooms/views: rooms=%s views=%s" % [
			", ".join(missing_rooms),
			", ".join(missing_views),
		])
	if missing_mechanics.has("backlog_file") or missing_mechanics.has("backlog_draw"):
		recommendations.append("Run backlog_heavy with promoted backlog cards enabled so Backlog coverage is exercised deliberately.")
	if not missing_mechanics.is_empty():
		recommendations.append("Seed the promoted reward pool with cards for uncovered mechanics, then rerun: %s" % ", ".join(missing_mechanics))
	if recommendations.is_empty():
		recommendations.append("Coverage targets hit. Next step is a longer mixed-policy soak looking for invariant warnings or low-frequency runtime failures.")
	return recommendations


func _create_policy_bucket() -> Dictionary:
	return {
		"runs": 0,
		"wins": 0,
		"losses": 0,
		"failure_category_totals": {},
		"room_type_totals": {},
		"view_totals": {},
		"mechanic_totals": {},
		"invariant_warning_totals": {},
	}


func _get_exclusive_targets(targets: Array, policy_buckets: Dictionary, current_policy_name: String, totals_key: String) -> PackedStringArray:
	var exclusive := PackedStringArray()
	var current_bucket: Dictionary = policy_buckets.get(current_policy_name, {})
	var current_totals: Dictionary = current_bucket.get(totals_key, {})
	for target in targets:
		var target_name := str(target)
		if int(current_totals.get(target_name, 0)) <= 0:
			continue

		var seen_elsewhere := false
		for policy_name in policy_buckets.keys():
			var other_policy_name := str(policy_name)
			if other_policy_name == current_policy_name:
				continue
			var other_bucket: Dictionary = policy_buckets.get(other_policy_name, {})
			var other_totals: Dictionary = other_bucket.get(totals_key, {})
			if int(other_totals.get(target_name, 0)) > 0:
				seen_elsewhere = true
				break

		if not seen_elsewhere:
			exclusive.append(target_name)
	return exclusive


func _get_investigation_priority(source: String, category: String) -> String:
	if source == "invariant_warning":
		return "high"

	match category:
		"preflight", "stall", "timeout":
			return "high"
		"other_failure":
			return "medium"
		"combat_loss":
			return "low"
		"action_limit", "victory":
			return "low"
	return "medium"


func _get_investigation_hint(source: String, category: String) -> String:
	if source == "invariant_warning":
		match category:
			"duplicate_instance_uid":
				return "Inspect deck/backlog/draw/discard ownership mutations around instance_uid preservation."
			"targeting_without_enemy", "battle_without_enemies":
				return "Inspect battle state transitions and targetable enemy refresh when entering or ending combat."
			"negative_pile_count":
				return "Inspect pile mutation ordering and defensive guards around add/remove card operations."
			_, "negative_health", "negative_mana", "negative_gold", "negative_budget", "health_above_max", "mana_above_max":
				return "Inspect resource mutation order and cap/clamp logic around the affected stat."
		return "Inspect the warning category and reproduce with the recorded run evidence."

	match category:
		"preflight":
			return "Fix broken promoted resources first; runtime QA is not trustworthy until preflight passes."
		"stall":
			return "Inspect the last active view and last action to find a blocked UI flow or missing state transition."
		"timeout":
			return "Inspect long-running room or combat flows; determine whether this is a real hang or an undersized time budget."
		"action_limit":
			return "Raise action/time caps before treating this as a gameplay bug; current evidence mostly indicates truncated coverage."
		"combat_loss":
			return "Not necessarily a bug; only investigate if paired with invariant warnings or obviously broken state."
		"other_failure":
			return "Inspect the recorded reason text and sample run to decide whether this is a true runtime defect."
		"victory":
			return "No investigation needed."
	return "Inspect the recorded evidence for this category."


func _build_investigation_queue() -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var failure_samples := {}
	var warning_samples := {}

	for run_summary: Dictionary in _run_summaries:
		var failure_category := str(run_summary.get("failure_category", ""))
		if not failure_category.is_empty() and not bool(run_summary.get("won", false)) and not failure_samples.has(failure_category):
			failure_samples[failure_category] = {
				"run": int(run_summary.get("run", 0)),
				"policy": str(run_summary.get("policy", "unknown")),
				"reason": str(run_summary.get("reason", "")),
			}

		for warning in run_summary.get("invariant_warnings", PackedStringArray()):
			var warning_text := str(warning)
			var category := warning_text.get_slice(":", 0)
			if category.is_empty():
				category = "unknown"
			if warning_samples.has(category):
				continue
			warning_samples[category] = {
				"run": int(run_summary.get("run", 0)),
				"policy": str(run_summary.get("policy", "unknown")),
				"warning": warning_text,
			}

	var suite_summary := _build_suite_summary_core()
	var failure_category_totals: Dictionary = suite_summary.get("failure_category_totals", {})
	for category_key in failure_category_totals.keys():
		var category := str(category_key)
		if category == "victory":
			continue
		var sample: Dictionary = failure_samples.get(category, {})
		queue.append({
			"source": "failure",
			"category": category,
			"count": int(failure_category_totals.get(category, 0)),
			"priority": _get_investigation_priority("failure", category),
			"sample_run": int(sample.get("run", 0)),
			"sample_policy": str(sample.get("policy", "unknown")),
			"sample_reason": str(sample.get("reason", "")),
			"hint": _get_investigation_hint("failure", category),
		})

	var invariant_warning_totals: Dictionary = suite_summary.get("invariant_warning_totals", {})
	for category_key in invariant_warning_totals.keys():
		var category := str(category_key)
		var sample: Dictionary = warning_samples.get(category, {})
		queue.append({
			"source": "invariant_warning",
			"category": category,
			"count": int(invariant_warning_totals.get(category, 0)),
			"priority": _get_investigation_priority("invariant_warning", category),
			"sample_run": int(sample.get("run", 0)),
			"sample_policy": str(sample.get("policy", "unknown")),
			"sample_warning": str(sample.get("warning", "")),
			"hint": _get_investigation_hint("invariant_warning", category),
		})

	return queue


func _build_suite_summary_core() -> Dictionary:
	var by_policy := {}
	var room_type_totals := {}
	var view_totals := {}
	var mechanic_totals := {}
	var invariant_warning_totals := {}
	var failure_category_totals := {}

	for run_summary: Dictionary in _run_summaries:
		var policy_name := str(run_summary.get("policy", "unknown"))
		if not by_policy.has(policy_name):
			by_policy[policy_name] = _create_policy_bucket()

		var policy_bucket: Dictionary = by_policy[policy_name]
		policy_bucket["runs"] = int(policy_bucket.get("runs", 0)) + 1
		if bool(run_summary.get("won", false)):
			policy_bucket["wins"] = int(policy_bucket.get("wins", 0)) + 1
		else:
			policy_bucket["losses"] = int(policy_bucket.get("losses", 0)) + 1

		var policy_failure_category_totals: Dictionary = policy_bucket.get("failure_category_totals", {})
		_increment_count(policy_failure_category_totals, str(run_summary.get("failure_category", "other_failure")))

		var room_counts: Dictionary = run_summary.get("room_types", {})
		var policy_room_type_totals: Dictionary = policy_bucket.get("room_type_totals", {})
		for room_type in room_counts.keys():
			_increment_count(room_type_totals, str(room_type), int(room_counts[room_type]))
			_increment_count(policy_room_type_totals, str(room_type), int(room_counts[room_type]))

		var seen_views: Dictionary = run_summary.get("views_seen", {})
		var policy_view_totals: Dictionary = policy_bucket.get("view_totals", {})
		for view_name in seen_views.keys():
			_increment_count(view_totals, str(view_name), int(seen_views[view_name]))
			_increment_count(policy_view_totals, str(view_name), int(seen_views[view_name]))

		var seen_mechanics: Dictionary = run_summary.get("mechanics_seen", {})
		var policy_mechanic_totals: Dictionary = policy_bucket.get("mechanic_totals", {})
		for mechanic_name in seen_mechanics.keys():
			_increment_count(mechanic_totals, str(mechanic_name), int(seen_mechanics[mechanic_name]))
			_increment_count(policy_mechanic_totals, str(mechanic_name), int(seen_mechanics[mechanic_name]))

		var policy_invariant_warning_totals: Dictionary = policy_bucket.get("invariant_warning_totals", {})
		for warning in run_summary.get("invariant_warnings", PackedStringArray()):
			var warning_text := str(warning)
			var category := warning_text.get_slice(":", 0)
			if category.is_empty():
				category = "unknown"
			_increment_count(invariant_warning_totals, category)
			_increment_count(policy_invariant_warning_totals, category)

		_increment_count(failure_category_totals, str(run_summary.get("failure_category", "other_failure")))
		by_policy[policy_name] = policy_bucket

	var room_coverage := _build_coverage_summary(COVERAGE_ROOM_TARGETS, room_type_totals)
	var view_coverage := _build_coverage_summary(COVERAGE_VIEW_TARGETS, view_totals)
	var mechanic_coverage := _build_coverage_summary(COVERAGE_MECHANIC_TARGETS, mechanic_totals)
	var next_pass_recommendations := _build_next_pass_recommendations(
		room_coverage,
		view_coverage,
		mechanic_coverage,
		failure_category_totals,
	)
	for policy_name in by_policy.keys():
		var policy_bucket: Dictionary = by_policy[policy_name]
		var policy_name_text := str(policy_name)
		var policy_room_coverage := _build_coverage_summary(COVERAGE_ROOM_TARGETS, policy_bucket.get("room_type_totals", {}))
		var policy_view_coverage := _build_coverage_summary(COVERAGE_VIEW_TARGETS, policy_bucket.get("view_totals", {}))
		var policy_mechanic_coverage := _build_coverage_summary(COVERAGE_MECHANIC_TARGETS, policy_bucket.get("mechanic_totals", {}))
		var exclusive_room_types := _get_exclusive_targets(COVERAGE_ROOM_TARGETS, by_policy, policy_name_text, "room_type_totals")
		var exclusive_views := _get_exclusive_targets(COVERAGE_VIEW_TARGETS, by_policy, policy_name_text, "view_totals")
		var exclusive_mechanics := _get_exclusive_targets(COVERAGE_MECHANIC_TARGETS, by_policy, policy_name_text, "mechanic_totals")
		policy_bucket["missing_room_types"] = policy_room_coverage["missing"]
		policy_bucket["missing_views"] = policy_view_coverage["missing"]
		policy_bucket["missing_mechanics"] = policy_mechanic_coverage["missing"]
		policy_bucket["exclusive_room_types"] = exclusive_room_types
		policy_bucket["exclusive_views"] = exclusive_views
		policy_bucket["exclusive_mechanics"] = exclusive_mechanics
		policy_bucket["coverage"] = {
			"rooms": policy_room_coverage,
			"views": policy_view_coverage,
			"mechanics": policy_mechanic_coverage,
			"complete": bool(policy_room_coverage["complete"]) and bool(policy_view_coverage["complete"]) and bool(policy_mechanic_coverage["complete"]),
			"has_unique_coverage": not exclusive_room_types.is_empty() or not exclusive_views.is_empty() or not exclusive_mechanics.is_empty(),
		}
		by_policy[policy_name_text] = policy_bucket

	return {
		"runs_completed": _run_summaries.size(),
		"configured_policies": _get_configured_policy_names(),
		"by_policy": by_policy,
		"room_type_totals": room_type_totals,
		"view_totals": view_totals,
		"mechanic_totals": mechanic_totals,
		"coverage_targets": {
			"rooms": PackedStringArray(COVERAGE_ROOM_TARGETS),
			"views": PackedStringArray(COVERAGE_VIEW_TARGETS),
			"mechanics": PackedStringArray(COVERAGE_MECHANIC_TARGETS),
		},
		"missing_room_types": room_coverage["missing"],
		"missing_views": view_coverage["missing"],
		"missing_mechanics": mechanic_coverage["missing"],
		"coverage": {
			"rooms": room_coverage,
			"views": view_coverage,
			"mechanics": mechanic_coverage,
			"complete": bool(room_coverage["complete"]) and bool(view_coverage["complete"]) and bool(mechanic_coverage["complete"]),
		},
		"failure_category_totals": failure_category_totals,
		"next_pass_recommendations": next_pass_recommendations,
		"invariant_warning_totals": invariant_warning_totals,
	}


func _build_suite_summary() -> Dictionary:
	var summary := _build_suite_summary_core()
	summary["investigation_queue"] = _build_investigation_queue()
	return summary


func _collect_invariant_warnings(snapshot: Dictionary) -> PackedStringArray:
	var warnings := PackedStringArray()
	var player_state: Dictionary = snapshot.get("player_state", {})
	var pile_counts: Dictionary = snapshot.get("pile_counts", {})
	var hand_state = snapshot.get("hand_state", [])
	var enemy_state = snapshot.get("enemy_state", [])
	var current_view := str(snapshot.get("current_view", ""))

	if not player_state.is_empty():
		var health := int(player_state.get("health", 0))
		var max_health := int(player_state.get("max_health", 0))
		var mana := int(player_state.get("mana", 0))
		var max_mana := int(player_state.get("max_mana", 0))
		var gold := int(player_state.get("gold", 0))
		var budget := int(player_state.get("budget", 0))

		if health < 0:
			warnings.append("negative_health: player health below zero")
		if health > max_health and max_health > 0:
			warnings.append("health_above_max: player health exceeds max health")
		if mana < 0:
			warnings.append("negative_mana: player mana below zero")
		if mana > max_mana and max_mana > 0:
			warnings.append("mana_above_max: player mana exceeds max mana")
		if gold < 0:
			warnings.append("negative_gold: gold below zero")
		if budget < 0:
			warnings.append("negative_budget: budget below zero")

	if current_view == "Battle" and enemy_state.is_empty():
		warnings.append("battle_without_enemies: battle view active without visible enemies")

	if current_view == "Battle" and not hand_state.is_empty() and enemy_state.is_empty():
		for hand_card in hand_state:
			if bool(hand_card.get("single_target", false)):
				warnings.append("targeting_without_enemy: single-target card present with no enemy state")
				break

	var live_uid_counts := {}
	var deck_uid_counts := {}
	var character := _active_run.character if _active_run != null and is_instance_valid(_active_run) else null
	if character != null:
		character.ensure_runtime_piles()
		var deck_pile = character.deck
		if deck_pile != null:
			for card: Card in deck_pile.cards:
				if card == null or card.instance_uid.is_empty():
					continue
				deck_uid_counts[card.instance_uid] = int(deck_uid_counts.get(card.instance_uid, 0)) + 1

		for pile_name in ["draw_pile", "discard", "backlog"]:
			var pile = character.get(pile_name)
			if pile == null:
				continue
			for card: Card in pile.cards:
				if card == null or card.instance_uid.is_empty():
					continue
				live_uid_counts[card.instance_uid] = int(live_uid_counts.get(card.instance_uid, 0)) + 1

		var current_view_node := _get_current_view()
		if current_view_node is Battle:
			for child: Node in (current_view_node as Battle).battle_ui.hand.get_children():
				if child is CardUI and (child as CardUI).card != null:
					var hand_card := (child as CardUI).card
					if not hand_card.instance_uid.is_empty():
						live_uid_counts[hand_card.instance_uid] = int(live_uid_counts.get(hand_card.instance_uid, 0)) + 1

	for instance_uid in deck_uid_counts.keys():
		if int(deck_uid_counts[instance_uid]) > 1:
			warnings.append("duplicate_instance_uid: %s appears %s times in deck" % [instance_uid, deck_uid_counts[instance_uid]])
			break

	for instance_uid in live_uid_counts.keys():
		if int(live_uid_counts[instance_uid]) > 1:
			warnings.append("duplicate_instance_uid: %s appears %s times across combat/backlog zones" % [instance_uid, live_uid_counts[instance_uid]])
			break

	if not pile_counts.is_empty():
		for pile_name in ["deck", "draw_pile", "discard", "backlog", "hand"]:
			if int(pile_counts.get(pile_name, 0)) < 0:
				warnings.append("negative_pile_count: %s below zero" % pile_name)

	return warnings


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


func _get_promoted_card_preflight_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var promoted_dir := DirAccess.open("res://common_cards/promoted")
	if promoted_dir == null:
		errors.append("missing directory res://common_cards/promoted")
		return errors

	promoted_dir.list_dir_begin()
	var file_name := promoted_dir.get_next()
	while not file_name.is_empty():
		if promoted_dir.current_is_dir():
			file_name = promoted_dir.get_next()
			continue
		if file_name.get_extension().to_lower() != "tres":
			file_name = promoted_dir.get_next()
			continue

		var resource_path := "res://common_cards/promoted/%s" % file_name
		var missing_dependencies := _get_missing_resource_dependencies(resource_path)
		if not missing_dependencies.is_empty():
			errors.append("%s -> %s" % [resource_path, ", ".join(missing_dependencies)])
			file_name = promoted_dir.get_next()
			continue

		var card_resource := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if card_resource == null:
			errors.append(resource_path)

		file_name = promoted_dir.get_next()

	promoted_dir.list_dir_end()
	return errors


func _get_missing_resource_dependencies(resource_path: String) -> PackedStringArray:
	var missing := PackedStringArray()
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		missing.append("missing file")
		return missing

	while not file.eof_reached():
		var line := file.get_line()
		var path_start := line.find('path="res://')
		if path_start == -1:
			continue

		var type_hint := ""
		var type_start := line.find('type="')
		if type_start != -1:
			type_start += 6
			var type_end := line.find('"', type_start)
			if type_end != -1:
				type_hint = line.substr(type_start, type_end - type_start)

		path_start += 6
		var path_end := line.find('"', path_start)
		if path_end == -1:
			continue

		var dependency_path := line.substr(path_start, path_end - path_start)
		if not ResourceLoader.exists(dependency_path, type_hint):
			missing.append("%s (%s)" % [dependency_path, type_hint if not type_hint.is_empty() else "unknown"])

	return missing
