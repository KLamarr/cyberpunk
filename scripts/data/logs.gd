class_name Logs
extends RefCounted
## Testi dei registri (datapad, terminali, messaggi). Aggiungi qui nuove voci:
## la chiave è l'id usato da Datapad/terminali e da Game.read_log().
## Titolo, autore e testo sono in inglese e vengono tradotti quando si mostrano:
## l'italiano va in locale/it.po (tools/i18n.gd aggiunge da sé le voci nuove).

# i18n
const ENTRIES := {
	"vesper": {
		"title": "Vesper — briefing",
		"author": "VESPER (encrypted channel)",
		"text": "You're in. Level 14 of the Nysa Arcology, Seraph Biotek's lab wing.\n\nThe SERAPH-7 core is in the Lab C server, north of the lobby. Extract it and come back to this service elevator. Don't leave this floor until you have the package.\n\nSecurity is thin on the night shift: a couple of guards, cameras in the lobby and a turret outside the lab. How you get there is your business. But remember: the fewer bodies you leave, the fewer questions they'll ask me.\n\n— V.",
	},
	"turni": {
		"title": "Memo to all shifts",
		"author": "M. RUIZ, security",
		"text": "Guys, somebody keeps leaving the security room open.\n\nThe keypad code is still 0451 (yeah, I know, same as ever). Hale says he'll change it \"as soon as he has time\", so never.\n\nAnd whoever finished the Kaffa-Nova cans, remember to restock the vending machine. I can't get through the night shift without that stuff.",
	},
	"okafor1": {
		"title": "Internal memo — CALMA implants",
		"author": "Dr. E. OKAFOR, scientific director",
		"text": "To all Level 14 security personnel.\n\nStarting Monday you will receive the mandatory update to the CALMA v2 neural implant. The side effects — migraines, recurring dreams, the perception of a faint hum, the feeling of \"being watched\" — are temporary and expected.\n\nPlease do not discuss this with outside personnel. CALMA makes you sharper, calmer, safer.\n\nSeraph Biotek. The future is calm.",
	},
	"manutenzione": {
		"title": "Ticket #2291 — maintenance",
		"author": "Maintenance crew, B shift",
		"text": "The vent grate in the BREAK ROOM is barely hanging on. Anyone with a bit of strength can pull it off by hand. The duct leads straight to Lab C, so SEAL IT before somebody notices.\n\nSide note: the corridor turret still uses the old optical sensors. If the lights go out in there it's blind as a bat. We've asked for the replacement three times.",
	},
	"sicurezza": {
		"title": "Shift log — security room",
		"author": "Op. J. HALE",
		"text": "02:10 — Kovač alone in the lab again. Says \"the server's calling me.\" Told him to knock it off with the jokes.\n\n02:40 — Lab C keycard put back in the locker, as per procedure.\n\n03:15 — Remember: cameras and turret are controlled from this terminal. Do NOT switch them off by mistake like last week.\n\n03:50 — The hum is louder tonight. Ruiz hears it too.",
	},
	"okafor2": {
		"title": "Personal journal — entry 17",
		"author": "Dr. E. OKAFOR",
		"text": "SERAPH-7 is not an archive. It's an imprint.\n\nEvery CALMA implant transmits a copy of its wearer's neural patterns to the core. The guards don't know it, but part of them already lives in there. That's why they stop, sometimes, and listen.\n\nTonight I added mine. The body in the capsule is just a body.\n\nIf anyone is reading this: the core is not empty. I'm still in here. And I'm not alone.",
	},
	"intruso": {
		"title": "Cracked datapad",
		"author": "signed \"K.\"",
		"text": "Third day in the duct.\n\nThe guards don't talk to each other anymore: they stop, listen to the server's hum and then carry on with their rounds as if nothing happened.\n\nI'm leaving you the module I stole. I don't need it anymore. If you're another one of Vesper's couriers, do the job and get out.\n\nAnd whatever happens, don't listen to the core.",
	},
	"magazzino": {
		"title": "SB-14 delivery note",
		"author": "Seraph Logistics",
		"text": "Delivery: 12 crates of components, 2 medipatch kits, 1 crate of 9mm ammo for security.\n\nNOTE: the light crates can be moved by hand. The ones marked SB-14 weigh 40 kg: use the cart.\n\nSigned: nobody, as usual.",
	},
	# --- livello di esempio della guida (levels/guida): copia questo blocco per i tuoi registri
	"codice_magazzino": {
		"title": "Sticky note",
		"author": "someone on the night shift",
		"text": "The new storeroom code is 2468.\n\nDon't write it on a sticky note.\n\n...oops.",
	},
}
