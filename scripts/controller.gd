extends Node2D

enum ACTIONS {NO_ACTION, MOVE_DOWN, MOVE_LEFT, MOVE_RIGHT, MOVE_UP}
enum STATES {AWAITING_ROUND, ONGOING_ROUND, AWAITING_RESULT, ONGOING_ANIMATION}

const MAX_MOVES: int = 5
const Piece = preload("res://scripts/piece.gd")

var MSG_FILTER := PackedStringArray([
	DSGMessageType.ROUND_RESULT,
	DSGMessageType.ROUND_START,
])

var _selected_piece_id: String = ""
var _moves_left: int = 0
var _next_moves: Array
var _current_state: STATES
var _round_number: int = 0
var _latest_round_result: Dictionary

@export var _message: Label
@export var _moves_message: Label
@export var _timer_message: Label
@export var _control: HBoxContainer

@onready var _board = $Board
@onready var _timer = $Timer

func _ready():
	_handle_screen_resize()
	get_tree().get_root().connect("size_changed", _handle_screen_resize)
	DSGNetwork.message_received.connect(self._on_ws_received_message)
	self._board.update_selected_piece.connect(self._on_update_selected_piece)
	self._board.ready_for_next_round.connect(_ready_for_next_round)
	self._current_state = STATES.AWAITING_ROUND
	self._place_pieces(GlobalVariables.pieces)

	# catch up on all the messages we missed while loading
	self._on_ws_received_message("")


func _handle_screen_resize():
	var viewport = get_tree().get_root().size
	_control.hide()
	if Utils.is_mobile_device():
		_control.show()
	position.x = max(viewport.x / 2 - viewport.y / 2, 0)
	position.y = max(viewport.y / 2 - viewport.x / 2, 0)


func _process(_delta):
	self._update_labels()


func _input(_event):
	if self._current_state != STATES.ONGOING_ROUND:
		return
	if Input.is_action_just_pressed("MOVE_DOWN"):
		self._append_move(ACTIONS.MOVE_DOWN, Vector2.DOWN)
	elif Input.is_action_just_pressed("MOVE_LEFT"):
		self._append_move(ACTIONS.MOVE_LEFT, Vector2.LEFT)
	elif Input.is_action_just_pressed("MOVE_RIGHT"):
		self._append_move(ACTIONS.MOVE_RIGHT, Vector2.RIGHT)
	elif Input.is_action_just_pressed("MOVE_UP"):
		self._append_move(ACTIONS.MOVE_UP, Vector2.UP)
	elif Input.is_action_just_pressed("NO_ACTION"):
		self._append_move(ACTIONS.NO_ACTION, Vector2.ZERO)
	elif Input.is_action_just_pressed("REMOVE_MOVE"):
		self._remove_latest_move()
	elif Input.is_action_just_pressed("SELECT_NEXT"):
		self._select_next_piece()


func _on_ws_received_message(_msg_type: String) -> void:
	while true:
		var msg: Variant = DSGNetwork.pop_pending_message(MSG_FILTER)
		if msg == null:
			break

		match msg["type"]:
			DSGMessageType.ROUND_START:
				if self._current_state == STATES.AWAITING_ROUND:
					self._current_state = STATES.ONGOING_ROUND
					self._start_round(msg["payload"])
			DSGMessageType.ROUND_RESULT:
				if self._current_state == STATES.AWAITING_RESULT:
					self._current_state = STATES.ONGOING_ANIMATION
					self._animate_round(msg["payload"])


func _start_round(payload: Dictionary):
	self._next_moves = []
	self._moves_left = 5
	self._selected_piece_id = ""
	self._round_number = payload["round_number"]
	self._timer.start(payload["round_duration"])
	var pieces = payload["board_state"]
	self._place_pieces(pieces)
	self._board.turn_all_player_piece_lights_on()


func _place_pieces(pieces: Array):
	for piece in pieces:
		var piece_pos = Position.get_obj_from_dict(piece["position"])
		self._board.place_piece(piece["piece_id"], piece["player_id"], piece_pos.get_vec())


func _animate_round(payload: Dictionary):
	self._latest_round_result = payload
	self._board.animate_events(payload["timeline"])


func _ready_for_next_round():
	self._current_state = STATES.AWAITING_ROUND
	GlobalVariables.winner_id = ""
	DSGNetwork.send({
		"type": DSGMessageType.READY_FOR_NEXT_ROUND,
		"payload": {}
	})
	var payload = self._latest_round_result
	var game_over = payload["game_over"]
	if game_over == null:
		return
	var winner_player_id = game_over["winner_player_id"]
	if winner_player_id != null:
		GlobalVariables.winner_id = winner_player_id
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _on_update_selected_piece(piece_id, piece_player_id):
	if GlobalVariables.player_id == piece_player_id:
		self._selected_piece_id = piece_id
		self._update_lights()


func _remove_latest_move():
	if self._next_moves.size() <= 0:
		return
	self._next_moves.pop_back()
	self._board.remove_latest_arrow()
	self._moves_left += 1


func _append_move(action: ACTIONS, direction: Vector2):
	if self._selected_piece_id == "" or self._moves_left <= 0:
		return
	self._next_moves.append({
		"piece_id": self._selected_piece_id,
		"action": ACTIONS.keys()[action].to_lower()
	})
	if direction != Vector2.ZERO:
		self._board.place_input_arrow(self._selected_piece_id, direction)
	self._moves_left -= 1


func _on_timer_timeout():
	$GongAudio.play()
	self._current_state = STATES.AWAITING_RESULT
	DSGNetwork.send({
		"type": DSGMessageType.PLAYER_MOVES,
		"payload": {
			"moves": self._next_moves
		}
	})
	self._board.purge_arrows()
	self._board.turn_all_piece_lights_off()


func _select_next_piece():
	self._selected_piece_id = self._get_next_piece_id()
	self._update_lights()


func _get_next_piece_id() -> String:
	var sorted = self._board.get_sorted_player_pieces()
	if sorted.is_empty():
		return ""
	if self._selected_piece_id == "":
		return sorted[0]
	var idx = sorted.find(self._selected_piece_id)
	var next_idx = (idx + 1) % len(sorted)
	return sorted[next_idx]


func _update_lights():
	if self._current_state != STATES.ONGOING_ROUND:
		return
	self._board.turn_all_player_piece_lights_on()
	var piece: Piece = self._board.get_piece_by_id(self._selected_piece_id)
	if piece != null:
		piece.turn_light_on(true)


func _update_labels():
	self._moves_message.text = "Moves left: " + str(self._moves_left)
	self._timer_message.text = "Time left: %.1f" % self._timer.time_left
	self._message.text = "Round " + str(self._round_number)


func _on_up_button_pressed():
	self._append_move(ACTIONS.MOVE_UP, Vector2.UP)


func _on_down_button_pressed():
	self._append_move(ACTIONS.MOVE_DOWN, Vector2.DOWN)


func _on_left_button_pressed():
	self._append_move(ACTIONS.MOVE_LEFT, Vector2.LEFT)


func _on_right_button_pressed():
	self._append_move(ACTIONS.MOVE_RIGHT, Vector2.RIGHT)
