class_name ItemIDs
extends RefCounted
## Inventory item id constants, shared by granters (pickups), consumers
## (player), and UI (hud). Namespaced "<episode>.<item>". Single source of
## truth so a rename touches one place.


## Pogo stick (Keen 1). Granted by the PogoStick pickup; consumed by Player
## to toggle pogo mode; shown as an overworld inventory icon.
const POGO := "keen1.pogo"

## Raygun/blaster. Find-to-own: granted by the keen1.raygun ammo pickup entity
## on first contact; gates shooting. Persists across levels + save/load via the
## Inventory autoload (like POGO). Cleared on new game by clear_progress().
const BLASTER := "keen1.blaster"

## Ship parts (Keen 1). Battery is granted by the keen1.battery pickup entity;
## the other three are forward-declarations (HUD slots + Ship.REQUIRED_PARTS)
## awaiting their own pickups. Each episode is expected to define its own
## battery/joystick/vacuum/everclear ids as episodes are authored.
const BATTERY   := "keen1.battery"
const JOYSTICK  := "keen1.joystick"
const VACUUM    := "keen1.vacuum"
const EVERCLEAR := "keen1.everclear"
