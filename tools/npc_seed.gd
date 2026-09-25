extends SceneTree
## Scrive su disco la libreria di forme predefinite (assets/npc/segments) e le definizioni
## dei personaggi della slice (assets/npc/characters). Da usare una volta, o per ripristinare:
##   godot --headless --path . --script tools/npc_seed.gd            (solo i file mancanti)
##   godot --headless --path . --script tools/npc_seed.gd -- --force (sovrascrive)
## Dopo, forme e personaggi si modificano con il creatore di NPC nell'editor.

var force := false


func _initialize() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(NPCLibrary.SHAPES_DIR)
	DirAccess.make_dir_recursive_absolute(NPCLibrary.CHARACTERS_DIR)
	var shapes := NPCLibrary.builtin_shapes()
	var names := shapes.keys()
	names.sort()
	for n in names:
		var p := NPCLibrary.shape_path(n)
		if force or not ResourceLoader.exists(p):
			_save(shapes[n], p)
	for c in _characters():
		var p := NPCLibrary.CHARACTERS_DIR.path_join(c[0] + ".tres")
		if force or not ResourceLoader.exists(p):
			_save(c[1], p)
	quit()


func _save(r: Resource, p: String) -> void:
	var err := ResourceSaver.save(r, p)
	print(("salvato  " if err == OK else "ERRORE %d " % err) + p)


func _swap(d: NPCDefinition, part: String, shape_name: String) -> void:
	d.get_part(part).shape = NPCLibrary.shape(shape_name)


func _drop(d: NPCDefinition, shape_name: String) -> void:
	for a in d.attachments.duplicate():
		if NPCLibrary.shape_name_of(a.shape) == shape_name:
			d.remove_attachment(a)


func _ensure(d: NPCDefinition, shape_name: String) -> void:
	for a in d.attachments:
		if NPCLibrary.shape_name_of(a.shape) == shape_name:
			return
	d.add_attachment(NPCLibrary.attachment_from(shape_name))


## I quattro agenti della Seraph della vertical slice. Il bottino è quello del livello
## originale (Ruiz ha la Tessera Sicurezza); i dati di gameplay sono quelli standard.
func _characters() -> Array:
	var G := NPCDefinition.Archetype.GUARDIA
	var out := []
	var ruiz := NPCLibrary.random_npc(G, 1401)
	ruiz.display_name = "Ag. Ruiz"
	ruiz.keycard_id = "sicurezza"
	ruiz.keycard_name = "Tessera Sicurezza"
	ruiz.ammo = 6
	ruiz.credits = 30
	ruiz.medpatch = 0
	_ensure(ruiz, "spallaccio")
	out.append(["ruiz", ruiz])

	var hale := NPCLibrary.random_npc(G, 1402)
	hale.display_name = "Op. Hale"
	hale.mass = 1.12
	hale.posture = 0.35
	hale.height = 1.74
	_swap(hale, "addome", "addome_pancia")
	_drop(hale, "casco")
	_drop(hale, "visore")
	_drop(hale, "spallaccio")
	_ensure(hale, "capelli")
	_ensure(hale, "cuffia")
	hale.ammo = 4
	hale.credits = 20
	hale.medpatch = 1
	hale.idle_barks = PackedStringArray([
		"Telecamera tre di nuovo in ritardo. Ma chi le ha installate?",
		"...lo senti anche tu, il ronzio?",
		"Altre sei ore di turno.",
		"Mi fa male la testa. Sempre dopo l'aggiornamento.",
	])
	out.append(["hale", hale])

	var kovac := NPCLibrary.random_npc(G, 1403)
	kovac.display_name = "Ag. Kovač"
	kovac.height = 1.9
	kovac.mass = 1.15
	kovac.shoulders = 1.12
	_swap(kovac, "braccio", "braccio_muscoloso")
	_swap(kovac, "coscia", "coscia_robusta")
	_ensure(kovac, "spallaccio")
	kovac.ammo = 6
	kovac.credits = 15
	kovac.medpatch = 0
	out.append(["kovac", kovac])

	var mori := NPCLibrary.random_npc(G, 1404)
	mori.display_name = "Ag. Mori"
	_ensure(mori, "spallaccio")
	mori.ammo = 8
	mori.credits = 10
	mori.medpatch = 0
	out.append(["mori", mori])
	return out
