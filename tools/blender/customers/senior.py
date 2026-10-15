"""Kundentyp „Senior/in“: Hemd mit Strickjacke, Stoffhose/Rock, Brille, Schiebermütze, Gehstock."""

ARCHETYPE = {
	"id": "senior",
	"name": {"de": "Senior/in", "en": "Senior"},
	"weight": 2,
	"bodies": {"m": 1, "w": 1},
	"scale": (0.94, 0.99),
	"palettes": {
		"top": ["#f2ecd9", "#e2e4e8", "#cfe0f2", "#f2f2f2", "#d9cfc0"],
		"outer": ["#7a5a3a", "#6a7a5a", "#2f3a55", "#7a3c50", "#8a8a80", "#b8a080"],
		"bottom": ["#5a5248", "#3a3a40", "#6a5a48", "#2f3a55", "#7a7268"],
		"shoes": ["#3b2618", "#1b1b1e", "#5a3a28"],
		"hair": ["#d8d8d8", "#b8b8b8", "#9a9a9a", "#eeeeea", "#7a7a7a"],
		"accent": ["#6a5a48", "#3a3a40", "#5a6a50", "#7a6a5a"],
	},
	"slots": {
		"hair": {"m": {"hair_receding": 3, "hair_sidepart": 2, "hair_buzz": 1}, "w": {"hair_perm": 3, "hair_bob": 2, "hair_bun": 2}},
		"hat": {"m": {None: 3, "flat_cap": 2}, "w": {None: 1}},
		"beard": {"m": {None: 3, "beard_full": 1, "beard_stubble": 1}, "w": {None: 1}},
		"face": {"glasses": 3, None: 1},
		"top": {"shirt:A": 2, "tshirt:A": 1},
		"outer": {"cardigan": 3, "blazer": 1, None: 1},
		"bottom": {"m": {"trousers": 1}, "w": {"trousers": 1, "skirt": 2}},
		"shoes": {"dress_shoes": 3, "sneakers": 1},
	},
	"extras": {"cane": 0.3, "watch": 0.5, "crossbody": {"w": 0.3}},
}
