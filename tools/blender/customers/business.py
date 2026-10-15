"""Kundentyp „Büro“ (Erwachsene): Hemd, Sakko, Anzughose oder Rock, Lederschuhe, Krawatte, Uhr."""

ARCHETYPE = {
	"id": "business",
	"name": {"de": "Büroangestellte/r", "en": "Office worker"},
	"weight": 2,
	"bodies": {"m": 1, "w": 1},
	"scale": (0.97, 1.03),
	"palettes": {
		"top": ["#f4f4f2", "#cfe0f2", "#f2d9dc", "#e2e4e8", "#f2ecd9"],
		"outer": ["#1f2a44", "#2b2d33", "#1b1b1e", "#5b6068", "#7a6a55", "#3c2f4a"],
		"bottom": "outer",
		"shoes": ["#1b1b1e", "#3b2618", "#5a3a28"],
		"hair": ["#1e1914", "#3b2a1c", "#5a3c1e", "#c8a05a", "#8a8a8a"],
		"accent": ["#8a1f2b", "#1f2a5a", "#2f6f6a", "#b8862f", "#5a2a5a"],
	},
	"slots": {
		"hair": {
			"m": {"hair_sidepart": 3, "hair_crop": 2, "hair_buzz": 1},
			"w": {"hair_bun": 3, "hair_bob": 2, "hair_long": 2, "hair_ponytail": 2},
		},
		"beard": {"m": {None: 4, "beard_stubble": 2, "beard_full": 1}, "w": {None: 1}},
		"face": {None: 3, "glasses:B": 2},
		"top": {"shirt:A": 1},
		"tie": {"m": {None: 1, "tie": 2}, "w": {None: 1}},
		"outer": {"blazer": 3, None: 1},
		"bottom": {"m": {"trousers": 1}, "w": {"trousers": 1, "skirt:A": 1}},
		"shoes": {"dress_shoes": 1},
	},
	"extras": {"watch": 0.7, "belt": {"m": 0.8}, "crossbody": {"w": 0.3}},
}
