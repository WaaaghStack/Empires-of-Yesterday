# SoldierResource.gd
class_name SoldierResource
extends Resource

@export var soldier_name: String = "Rookie"
@export var health: int = 100
@export var damage: int = 25
@export var speed: float = 120.0
@export var portrait: Texture2D
@export var description: String = "Standard Rifleman"