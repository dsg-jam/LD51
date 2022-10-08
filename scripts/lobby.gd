extends Node2D

const MapsDb := preload("res://scripts/db/maps.gd")

var _amount_of_players = 1

@export var start_button: Button
@export var label_id_value: Label
@export var label_amount_of_players: Label
@export var label_players: Label
@export var ws_address = "127.0.0.1:8000"

@onready var board_scene = preload("res://scenes/board_game.tscn")

func _ready():
	#self._parse_maps(MapsDb.MAPS)
	self._update_labels()
	DSGNetwork.ws_received_message.connect(_on_ws_received_message)
	assert(DSGNetwork.connect_websocket("ws://%s/lobby/%s/join" % [ws_address, GlobalVariables.id]))

func _on_start_game_button_pressed():
	var start_message = {
		"type": "host_start_game",
		"payload": {
			"platform": Utils.parse_map_to_dict("oooooooo;oooxxooo;ooxxxxoo;oxxxxxxo;oxxxxxxo;ooxxxxoo;oooxxooo;oooooooo")
		}
	}
	print(JSON.stringify(start_message))
	DSGNetwork.send(JSON.stringify(start_message).to_utf8_buffer())
	get_tree().change_scene_to_packed(self.board_scene)

func _on_ws_received_message(stream: String):
	var message = JSON.parse_string(stream)
	if message["type"] == "server_hello":
		self._server_hello(message["payload"])
	elif message["type"] == "player_joined":
		self._player_joined(message["payload"])

func _server_hello(payload: Variant):
	if not payload["is_host"]:
		self._setup_non_host()
	GlobalVariables.player_id = payload["player_id"]

func _player_joined(_payload: Variant):
	self._amount_of_players += 1
	self._update_labels()

func _setup_non_host():
	self.start_button.queue_free()
	self.label_amount_of_players.visible = false
	self.label_players.visible = false
	GlobalVariables.is_host = false

func _update_labels():
	self.label_id_value.text = GlobalVariables.id
	self.label_amount_of_players.text = str(self._amount_of_players)

func _parse_maps(maps: Array):
	for map in maps:
		print(map)
