class_name Credits
extends RefCounted
## Credits and licences, shown in game (F1 → Credits & licences) and written
## next to the executable as THIRD_PARTY_NOTICES.txt by tools/write_notices.gd.
## The data sources are those of data/ATTRIBUTION.md; Godot's MIT licence and
## its third-party components come from the engine itself.

const PUBLISHER := "TheBooleanJulian"

const DATA_CREDITS := [
	"Star positions and colours: Yale Bright Star Catalogue, 5th revised ed. (Hoffleit & Warren 1991), via CDS (catalogue V/50).",
	"Earth: NASA Blue Marble: Next Generation (Reto Stöckli, NASA Earth Observatory), via NASA's Scientific Visualization Studio. Public domain.",
	"Moon: NASA CGI Moon Kit (Ernie Wright, USRA; Noah Petro, NASA/GSFC), from LRO LROC WAC (Arizona State University) and LOLA data, via NASA's Scientific Visualization Studio. Public domain.",
	"Moon elevation: LRO LOLA (Lunar Orbiter Laser Altimeter) heights from the same CGI Moon Kit, 8 pixels a degree. Public domain.",
	"Mars: Mars Viking Colorized Global Mosaic (MDIM 2.1), USGS Astrogeology Science Center and NASA Ames. Public domain.",
	"Mercury: MESSENGER MDIS global mosaic (PIA16298), NASA/Johns Hopkins University Applied Physics Laboratory/Carnegie Institution of Washington. Public domain.",
	"Jupiter: Cassini's best maps of Jupiter (PIA07782), NASA/JPL/Space Science Institute. Public domain.",
	"Phobos: Phobos Viking Global Mosaic (DLR control), USGS Astrogeology Science Center. Public domain.",
	"Deimos: Viking Orbiter mosaic map by Philip J. Stooke, via NASA's Planetary Data System Small Bodies Node.",
	"Venus, Saturn, Uranus and Neptune: cloud-top maps made for the game from their colours in Voyager, Cassini and Hubble images (procedural, not imagery).",
	"Planet positions: E. M. Standish (JPL), Keplerian elements for the approximate positions of the major planets.",
	"Artifact positions (ISS, Hubble, LRO, MRO, Mars Odyssey, the Tesla Roadster, New Horizons, the Voyagers and the Pioneers) and the orbits of Phobos and Deimos: NASA/JPL Horizons On-Line Ephemeris System.",
	"Sound effects: Kenney (www.kenney.nl) — Sci-Fi Sounds, Impact Sounds, Interface Sounds. CC0 1.0.",
]


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## The short credits: title, version, publisher, data sources, the engine.
static func summary() -> String:
	var lines := PackedStringArray()
	lines.append("%s %s" % [str(ProjectSettings.get_setting("application/config/name", "")), version()])
	lines.append("© 2026 %s. All rights reserved." % PUBLISHER)
	lines.append("")
	lines.append("DATA AND SOUND")
	for line: String in DATA_CREDITS:
		lines.append("• " + line)
	lines.append("")
	lines.append("ENGINE")
	lines.append("Made with Godot Engine %s (godotengine.org)." % Engine.get_version_info().string)
	return "\n".join(lines)


## Everything, including the Godot licence and the licences of the
## components it is built from (Godot's requirement for shipped games).
static func full_text() -> String:
	var lines := PackedStringArray([summary(), ""])
	lines.append("This game uses Godot Engine, available under the following license:")
	lines.append("")
	lines.append(Engine.get_license_text())
	lines.append("")
	lines.append("THIRD-PARTY COMPONENTS OF GODOT ENGINE")
	var licences := Engine.get_license_info()
	for info: Dictionary in Engine.get_copyright_info():
		lines.append("")
		lines.append("— %s" % info.get("name", ""))
		for part: Dictionary in info.get("parts", []):
			for c: String in part.get("copyright", PackedStringArray()):
				lines.append("  © %s" % c)
			lines.append("  License: %s" % part.get("license", ""))
	lines.append("")
	lines.append("LICENSE TEXTS")
	var names: Array = licences.keys()
	names.sort()
	for name: String in names:
		lines.append("")
		lines.append("— %s" % name)
		lines.append(str(licences[name]))
	return "\n".join(lines)
