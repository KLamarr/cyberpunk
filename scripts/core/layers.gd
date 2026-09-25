class_name Layers
extends RefCounted
## Layer di collisione (bitmask). Stessi nomi in Impostazioni progetto >
## Nomi layer > Fisica 3D. Sono costanti di classe, quindi valgono anche negli
## script @tool che girano dentro l'editor (dove gli autoload non esistono).

const WORLD := 1
const PLAYER := 2
const NPC := 4
const DOOR := 8
const GLASS := 16
const PROP := 32
const INTERACT := 64
const DEVICE := 128
