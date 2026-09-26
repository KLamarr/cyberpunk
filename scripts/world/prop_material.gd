@tool
class_name PropMaterial
extends Resource
## MATERIALE di un oggetto fisico (Throwable): quanto pesa, che rumore fa quando urta,
## quanto danneggia ciò che colpisce, se e come si rompe.
## Quelli di Seraph sono in assets/prop_materials/ (uno per ogni Kind dei Throwable): aprili
## nell'Inspector per cambiare i numeri, oppure duplicane uno (tasto destro → Duplicate…)
## e trascinalo nella proprietà Material di un Throwable per dargli un comportamento suo.
## Vedi la guida, «Materiali e stimoli».

@export_range(0.05, 100.0, 0.05, "suffix:kg") var mass := 1.0
## Forza che serve per sollevarlo (0 = chiunque).
@export_range(0, 4) var strength_required := 0
## Rumore degli urti: moltiplica il raggio in cui le guardie lo sentono (1 = lattina).
@export_range(0.0, 3.0, 0.05) var impact_noise := 1.0
## Suono degli urti (un file di assets/sounds).
@export_enum("clatter", "hit_metal", "impact") var impact_sound := "clatter"
## Quanto danneggia ciò che colpisce quando lo lanci (luci, telecamere, grate):
## moltiplica l'energia dell'urto. 0 = mai.
@export_range(0.0, 4.0, 0.05) var impact_damage := 1.0

@export_group("Rottura")
## Cosa diventa quando si rompe:
## none: non si rompe; shards: cocci di vetro per terra (rumorosi da calpestare);
## water: una pozza (rumorosa, conduce la corrente); smoke: una nube che blocca la
## vista (l'oggetto resta, vuoto).
@export_enum("none", "shards", "water", "smoke") var breaks_into := "none"
## Si rompe se urta qualcosa a questa velocità o più. 0 = solo se colpito.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var break_speed := 0.0
## Si rompe se colpito (chiave inglese, proiettili, oggetti lanciati) con almeno questo danno.
@export_range(0.0, 100.0, 0.5) var break_damage := 1.0
## Raggio di cocci, pozza o nube.
@export_range(0.2, 6.0, 0.05, "suffix:m") var effect_radius := 1.0
## Quanto dura la nube (cocci e pozze restano).
@export_range(1.0, 120.0, 0.5, "suffix:s") var effect_duration := 15.0


func breaks() -> bool:
	return breaks_into != "none"
