extends Node2D

@onready var character = $character
@onready var sprite = $sprite
@onready var sprite2 = $sprite2
@onready var ufo = $ufo

var x = 2152.0
var y = 1648.0
var r = 30.0
var dstx = x
var dsty = y
var s = 0.0


func  _ready() -> void:
	character.position = Vector2i.ZERO
	s = Vector2(x, y).length()
	sprite.target = character
	sprite.position = Vector2(0, y)
	sprite2.target = character
	sprite2.position = Vector2(x, 0)
	ufo.target = character

func  _physics_process(delta: float) -> void:
		var target_pos = Vector2(dstx, dsty)
		var character_pos = character.global_position
		var to_vect =  target_pos - character_pos
		var dst = to_vect.length()
		if dst < r:
			dstx = 0.0 if dstx == x else x
			dsty = 0.0 if dsty == y else y
		else:
			var to_vect_normalized = to_vect / dst
			character.velocity = to_vect_normalized * 100.0
			character.move_and_slide()
		
		
		
	
