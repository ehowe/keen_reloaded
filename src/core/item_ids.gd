class_name ItemIDs
extends RefCounted
## Inventory item id constants, shared by granters (pickups), consumers
## (player), and UI (hud). Namespaced "<episode>.<item>". Single source of
## truth so a rename touches one place.


## Pogo stick (Keen 1). Granted by the PogoStick pickup; consumed by Player
## to toggle pogo mode; shown as an overworld inventory icon.
const POGO := "keen1.pogo"

## Raygun/blaster. Always owned (granted in Player._ready); gates shooting.
const BLASTER := "keen1.blaster"
