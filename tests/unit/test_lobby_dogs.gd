extends "res://tests/lib/test_case.gd"
## Lobby.dog_label (F7: the lobby shows each player's dog). Static, pure text: no scene needed.


func test_dog_label_uses_the_ptbr_name_of_every_dog() -> void:
	var ids: Array = Data.get_dog_ids()
	ok(ids.size() >= 3, "dogs.json tem os cachorros (%d)" % ids.size())
	for id: StringName in ids:
		var name_ptbr: String = str(Data.get_dog(id).get("name", ""))
		ne(name_ptbr, "", "cao %s tem nome" % id)
		eq(Lobby.dog_label(id), "Cão: %s" % name_ptbr, "rotulo do cao %s" % id)


func test_dog_label_known_names() -> void:
	eq(Lobby.dog_label(&"caramelo"), "Cão: Vira-lata Caramelo", "caramelo")
	eq(Lobby.dog_label(&"foxhound"), "Cão: Foxhound Americano", "foxhound")
	eq(Lobby.dog_label(&"dogo"), "Cão: Dogo Argentino", "dogo")


## The lobby only calls dog_label for a non-empty id (lobby.gd: "if dog_id != &''"), so the empty id is outside the
## contract; it must at least not crash and must not invent a breed.
func test_dog_label_empty_id_does_not_crash() -> void:
	var text: String = Lobby.dog_label(&"")
	ok(text.begins_with("Cão:"), "id vazio devolve so o prefixo ('%s')" % text)
	for id: StringName in Data.get_dog_ids():
		ok(not text.contains(str(Data.get_dog(id).get("name", "?"))), "id vazio nao cita %s" % id)


func test_dog_label_unknown_id_falls_back_to_the_id() -> void:
	eq(Lobby.dog_label(&"cao_inexistente"), "Cão: cao_inexistente", "id desconhecido mostra o proprio id")
