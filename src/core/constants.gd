class_name Constants
extends RefCounted
## Project-wide tuning constants. Single source of truth for values referenced
## across unrelated base classes (which can't share via inheritance).


## Side length, in pixels, of one level tile. Drives collision-shape sizes and
## proximity-zone dimensions across the Entity and ProximityInteractable trees.
const TILE := 64
