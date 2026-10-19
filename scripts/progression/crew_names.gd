class_name CrewNames
extends RefCounted
## Names for hired crew: a given name and a family name, drawn from a seeded
## generator so a save always shows the same people.

const GIVEN := ["Ade", "Aiko", "Amara", "Anders", "Bea", "Chen", "Dara", "Elif", "Ezra", "Farah",
	"Gael", "Hana", "Idris", "Ines", "Jun", "Kai", "Lena", "Malik", "Mei", "Nadia",
	"Niko", "Omar", "Priya", "Quinn", "Rafa", "Rin", "Sami", "Sven", "Tala", "Uma",
	"Vik", "Wen", "Yara", "Yusuf", "Zoe", "Arjun", "Bram", "Cleo", "Dev", "Esme"]
const FAMILY := ["Abara", "Bakker", "Castillo", "Dlamini", "Eriksen", "Fong", "Garcia", "Haddad", "Ibrahim", "Jensen",
	"Kaur", "Lim", "Moreau", "Nakamura", "Okafor", "Petrov", "Quispe", "Rossi", "Sato", "Tan",
	"Umarov", "Varga", "Wong", "Xu", "Yilmaz", "Zhou", "Achebe", "Brandt", "Cruz", "Das"]


static func pick(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [GIVEN[rng.randi() % GIVEN.size()], FAMILY[rng.randi() % FAMILY.size()]]
