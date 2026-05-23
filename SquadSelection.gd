# SquadSelection.gd
extends Control

func _ready():
    print("DEBUG: SquadSelection _ready() called successfully!")
    print("DEBUG: Node name: ", name)
    print("DEBUG: SoldierContainer exists: ", has_node("SoldierContainer"))
    print("DEBUG: DeployButton exists: ", has_node("DeployButton"))