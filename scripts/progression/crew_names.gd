class_name CrewNames
extends RefCounted
## Names for hired crew: a given name and a family name, drawn from a seeded
## generator so a save always shows the same people — 120 × 100 of them, and
## `pick_unique` rerolls a name already taken (play-test batch 11: the old
## 40 × 30 showed the same names twice on a big ship). Each crew member also
## has a previous occupation: flavour only.

const GIVEN := ["Ade", "Aiko", "Amara", "Anders", "Bea", "Chen", "Dara", "Elif", "Ezra", "Farah",
	"Gael", "Hana", "Idris", "Ines", "Jun", "Kai", "Lena", "Malik", "Mei", "Nadia",
	"Niko", "Omar", "Priya", "Quinn", "Rafa", "Rin", "Sami", "Sven", "Tala", "Uma",
	"Vik", "Wen", "Yara", "Yusuf", "Zoe", "Arjun", "Bram", "Cleo", "Dev", "Esme",
	"Aleksei", "Anya", "Bashir", "Bjorn", "Calla", "Dmitri", "Eamon", "Freya", "Gideon", "Hakan",
	"Ilse", "Imani", "Jalen", "Jonas", "Kenji", "Kofi", "Lars", "Leilani", "Mateo", "Mira",
	"Nasser", "Noor", "Oksana", "Olu", "Paz", "Pita", "Rania", "Ravi", "Rosa", "Sanjay",
	"Saoirse", "Selin", "Tariq", "Thea", "Tomas", "Ulla", "Valentin", "Vesna", "Wiremu", "Ximena",
	"Yaw", "Yuki", "Zainab", "Zeno", "Aroha", "Basil", "Catalina", "Dong", "Eero", "Fatima",
	"Goran", "Hiro", "Isla", "Jovan", "Keoni", "Lucia", "Mbali", "Nils", "Ondine", "Pavel",
	"Rashida", "Soren", "Tomoko", "Ugo", "Vera", "Wanjiru", "Xiadani", "Yoshi", "Zuri", "Abebe",
	"Beatriz", "Cyrus", "Delphine", "Emeka", "Fumiko", "Gunnar", "Halima", "Ivo", "Jia", "Kalani"]
const FAMILY := ["Abara", "Bakker", "Castillo", "Dlamini", "Eriksen", "Fong", "Garcia", "Haddad", "Ibrahim", "Jensen",
	"Kaur", "Lim", "Moreau", "Nakamura", "Okafor", "Petrov", "Quispe", "Rossi", "Sato", "Tan",
	"Umarov", "Varga", "Wong", "Xu", "Yilmaz", "Zhou", "Achebe", "Brandt", "Cruz", "Das",
	"Adeyemi", "Bergstrom", "Chaudhry", "Delacroix", "Esposito", "Fitzgerald", "Gonzaga", "Halvorsen", "Iwasaki", "Jovanovic",
	"Kowalski", "Laurent", "Mbeki", "Novak", "Oyelaran", "Pereira", "Quinlan", "Rahimi", "Svensson", "Tanaka",
	"Ueda", "Vasquez", "Whitfield", "Xavier", "Yamamoto", "Zielinski", "Afolabi", "Bianchi", "Coetzee", "Dimitriou",
	"Engstrom", "Ferrari", "Grigoryan", "Horvat", "Ishikawa", "Juarez", "Kim", "Lindqvist", "Mendoza", "Nair",
	"Ortega", "Park", "Rasmussen", "Silva", "Takahashi", "Ulloa", "Volkov", "Waititi", "Yeo", "Zhang",
	"Agarwal", "Baptiste", "Cohen", "Diallo", "Eze", "Fujita", "Gallagher", "Hosseini", "Ivanova", "Kariuki",
	"Lopez", "Mwangi", "Nguyen", "Obi", "Patel", "Reyes", "Suzuki", "Tremblay", "Vargas", "Wiśniewski"]
## What they did before they signed on (no effect on play).
const OCCUPATIONS := ["asteroid miner", "ice hauler", "orbital welder", "hydroponics tech", "cargo loader",
	"station medic", "customs officer", "racing pilot", "schoolteacher", "line cook", "deckhand", "surveyor",
	"archivist", "brewer", "drone wrangler", "comms operator", "bounty hunter", "court clerk", "farmer",
	"street musician", "tug pilot", "salvage diver", "reactor fitter", "chaplain", "insurance assessor",
	"freight broker", "botanist", "tattoo artist", "librarian", "ferry steward", "dockworker", "geologist",
	"barber", "security guard", "paramedic", "radio host", "pastry chef", "mechanic", "translator",
	"glassblower", "cartographer", "accountant", "stunt pilot", "zookeeper", "smuggler (allegedly)",
	"debt collector", "ballet dancer", "prospector", "beekeeper", "data clerk"]


static func pick(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [GIVEN[rng.randi() % GIVEN.size()], FAMILY[rng.randi() % FAMILY.size()]]


## A name not in `taken` (name -> true); it is added to `taken`.
static func pick_unique(rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var name := pick(rng)
	for k in 64:
		if not taken.has(name):
			break
		name = pick(rng)
	taken[name] = true
	return name


static func occupation(rng: RandomNumberGenerator) -> String:
	return OCCUPATIONS[rng.randi() % OCCUPATIONS.size()]


## A stable occupation for a crew member saved before there were any.
static func occupation_for(name: String) -> String:
	return OCCUPATIONS[absi(hash(name)) % OCCUPATIONS.size()]
