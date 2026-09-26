class_name EnvTexts
extends RefCounted
## DIDASCALIE DEI TESTI AMBIENTALI (insegne, poster, graffiti, murales): cosa c'è
## scritto nelle texture, mostrato sotto il mirino quando il giocatore guarda la
## scritta (vedi hud.gd). I testi sono in inglese, come le scritte dipinte, e si
## traducono quando si mostrano (italiano in locale/it.po).
##
## Da dove viene la didascalia di un PropQuad o PropBox:
##   - la sua proprietà Caption, se scritta («-» = nessuna didascalia);
##   - altrimenti la tabella BY_TEXTURE qui sotto, in base al nome della texture.
##
## Opzione del giocatore (Game.settings.env_captions, nella pausa):
##   "off"     mai;
##   "auto"    solo se la scritta non è nella lingua del giocatore: lingua diversa
##             dall'inglese, nessuna texture <nome>_<lingua>.png e una traduzione
##             diversa dal testo (SERAPH BIOTEK resta uguale: niente didascalia);
##   "always"  sempre, anche per leggere meglio le scritte piccole o lontane.

const MODES := ["off", "auto", "always"]

## Nome del file della texture (quella inglese, senza estensione) -> [tipo, testo].
# i18n
const BY_TEXTURE := {
	"sign_seraph": ["Sign", "SERAPH BIOTEK"],
	"sign_lab": ["Sign", "LAB C > SERAPH-7"],
	"sign_sec": ["Sign", "SECURITY"],
	"sign_relax": ["Sign", "BREAK ROOM"],
	"sign_store": ["Sign", "STOREROOM"],
	"sign_lift": ["Sign", "SERVICE 14"],
	"poster": ["Poster", "SERAPH BIOTEK: THE FUTURE"],
	"graffiti": ["Graffiti", "NO CALMA"],
	"vending": ["Vending machine", "KAFFA-NOVA"],
}


## [tipo, testo] per un oggetto: la sua Caption («-» = nessuna), altrimenti quella
## della texture. [] = niente da mostrare.
static func resolve(caption: String, texture: Texture2D) -> Array:
	if caption == "-":
		return []
	if caption != "":
		return ["", caption]
	if texture == null:
		return []
	return BY_TEXTURE.get(texture.resource_path.get_file().get_basename(), [])


## La didascalia serve, con questa opzione e la lingua attiva?
static func wanted(mode: String, text: String, texture: Texture2D) -> bool:
	match mode:
		"always":
			return true
		"auto":
			if TranslationServer.get_locale().get_slice("_", 0) == "en":
				return false   # le scritte sono in inglese
			if texture != null and Util.localized(texture) != texture:
				return false   # c'è la texture nella lingua del giocatore
			return String(TranslationServer.translate(text)) != text
	return false
