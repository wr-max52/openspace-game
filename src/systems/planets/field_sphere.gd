class_name FieldSphere
extends GasSphere
## Issue #880: an asteroid field's ball (the field type in content/core/planets/
## types.json, the red system's field: content/core/planets/scatter_field.json).
## The gas ball's shape (GasSphere) with nothing drawn and nothing deadly: its
## radius is the town deck's level and its "surface" is far below, out of play.
## What you stand on and fly round out here are the field's rocks (FieldRocks:
## each a gravity body of this ball, PlanetSphere.add_gravity_body), the wrecks
## among them and the outposts on the biggest; between them the ball's own up
## holds, so a drifter falls back toward the deck's side of the field, slowly
## (the field's own gravity, FieldWorld), until FieldWorld pulls them back to
## their ship.
##
## Settings: the field type's "surface".


func _init(r: float = 6000.0, surface: Dictionary = {}) -> void:
	super._init(r, surface)
