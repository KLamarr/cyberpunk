class_name Logs
extends RefCounted
## Testi dei registri (datapad, terminali, messaggi). Aggiungi qui nuove voci:
## la chiave è l'id usato da Datapad/terminali e da Game.read_log().

const ENTRIES := {
	"vesper": {
		"title": "Vesper — Briefing",
		"author": "VESPER (canale cifrato)",
		"text": "Sei dentro. Livello 14 dell'arcologia Nysa, ala laboratori della Seraph Biotek.\n\nIl nucleo SERAPH-7 è nel server del Laboratorio C, a nord della hall. Estrailo e torna a quest'ascensore di servizio: resta al piano finché non hai il pacco.\n\nLa sicurezza è ridotta al turno di notte: un paio di guardie, telecamere nella hall e una torretta davanti al laboratorio. Come ci arrivi è affar tuo. Ma ricorda: meno cadaveri lasci, meno domande faranno a me.\n\n— V.",
	},
	"turni": {
		"title": "Promemoria turni",
		"author": "M. RUIZ, vigilanza",
		"text": "Ragazzi, qualcuno continua a lasciare aperta la sala sicurezza.\n\nIl codice del tastierino è ancora 0451 (sì, lo so: sempre quello). Hale dice che lo cambierà \"appena ha tempo\", quindi mai.\n\nE chi ha finito le lattine di Kaffa-Nova si ricordi di rifornire il distributore. Non ce la faccio a fare il turno di notte senza.",
	},
	"okafor1": {
		"title": "Circolare interna — impianti CALMA",
		"author": "Dr. E. OKAFOR, direzione scientifica",
		"text": "A tutto il personale di vigilanza del livello 14.\n\nDa lunedì riceverete l'aggiornamento obbligatorio dell'impianto neurale CALMA v2. Gli effetti collaterali — emicrania, sogni ricorrenti, un leggero ronzio percepito, la sensazione di \"essere osservati\" — sono temporanei e previsti.\n\nVi preghiamo di non discuterne con personale esterno. CALMA vi rende più lucidi, più sereni, più sicuri.\n\nSeraph Biotek. Il futuro è calmo.",
	},
	"manutenzione": {
		"title": "Ticket #2291 — Manutenzione",
		"author": "Squadra tecnica, turno B",
		"text": "La grata del condotto di ventilazione nella SALA RELAX è quasi staccata: con un minimo di forza si toglie a mano. Il condotto porta dritto al Laboratorio C, quindi SIGILLATELA prima che qualcuno se ne accorga.\n\nNota a margine: la torretta del corridoio usa ancora i vecchi sensori ottici. Se salta la luce lì dentro è cieca come una talpa. Abbiamo chiesto il ricambio tre volte.",
	},
	"sicurezza": {
		"title": "Registro turno — sala sicurezza",
		"author": "Op. J. HALE",
		"text": "02:10 — Kovač di nuovo in laboratorio da solo. Dice che \"il server lo chiama\". Gli ho detto di smetterla con le battute.\n\n02:40 — Tessera del Laboratorio C riposta nell'armadietto, come da procedura.\n\n03:15 — Ricordarsi: telecamere e torretta si gestiscono da questo terminale. NON spegnerle per sbaglio come la settimana scorsa.\n\n03:50 — Il ronzio è più forte stanotte. Anche Ruiz lo sente.",
	},
	"okafor2": {
		"title": "Diario personale — voce 17",
		"author": "Dr. E. OKAFOR",
		"text": "SERAPH-7 non è un archivio. È un'impronta.\n\nOgni impianto CALMA trasmette al nucleo una copia dei pattern neurali di chi lo porta. Le guardie non lo sanno, ma una parte di loro vive già lì dentro. Per questo si fermano, a volte, e ascoltano.\n\nStanotte ho aggiunto il mio. Il corpo nella capsula è solo un corpo.\n\nSe qualcuno sta leggendo queste righe: il nucleo non è vuoto. Io sono ancora qui dentro. E non sono solo.",
	},
	"intruso": {
		"title": "Datapad incrinato",
		"author": "firmato \"K.\"",
		"text": "Terzo giorno nel condotto.\n\nLe guardie non parlano più tra loro: si fermano, ascoltano il ronzio del server e poi riprendono il giro come se nulla fosse.\n\nLascio qui il modulo che ho rubato: a me non serve più. Se sei un altro corriere di Vesper, fai il lavoro e vattene.\n\nE qualunque cosa succeda: non ascoltare il nucleo.",
	},
	"magazzino": {
		"title": "Bolla di carico SB-14",
		"author": "Logistica Seraph",
		"text": "Consegna: 12 casse componenti, 2 kit medipatch, 1 cassa munizioni 9mm per vigilanza.\n\nNOTA: le casse leggere si possono spostare a mano. Quelle marcate SB-14 pesano 40 kg: usare il carrello.\n\nFirmato: nessuno, come al solito.",
	},
}
