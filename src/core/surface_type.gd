class_name SurfaceType
extends RefCounted
## Tile surface types. Values mirror the TileSet `surface_type` custom-data
## layer (0 = normal ground). Used by the player to select ground-movement
## rules; see SurfacePhysics and the surface dispatch in player.gd.

enum Kind { NONE = 0, ICE1 = 1, ICE2 = 2 }
