"""Kundentyp „Student/in“ (jung): Hoodie oder T-Shirt, Jeans/Jogger, Sneaker, Rucksack, Kopfhörer."""

ARCHETYPE = {
	"id": "student",
	"name": {"de": "Student/in", "en": "Student"},
	"weight": 3,
	"bodies": {"m": 1, "w": 1},
	"scale": (0.93, 0.98),
	"palettes": {
		"top": ["#3a6fd8", "#d8483a", "#3aa86b", "#f2f2f2", "#2b2b30", "#f0b428", "#7a3c96", "#e86a8a", "#9bb7d9"],
		"outer": ["#2b2b30"],
		"bottom": ["#2f4a7a", "#4a6fa0", "#1f1f24", "#4a4f57", "#6b7a8f"],
		"shoes": ["#f2f2f2", "#202022", "#d8483a", "#e8e0d0"],
		"hair": ["#1e1914", "#3b2a1c", "#5a3c1e", "#c8a05a", "#8c4f28", "#2a1d14"],
		"accent": ["#f0b428", "#7a3c96", "#2f8f8a", "#e86a2a", "#2b2b30", "#d8483a"],
	},
	"slots": {
		"hair": {
			"m": {"hair_crop": 3, "hair_curly_top": 2, "hair_buzz": 1, "hair_sidepart": 1},
			"w": {"hair_long": 3, "hair_ponytail": 2, "hair_bun": 2, "hair_bob": 1, "hair_curly_long": 2},
		},
		"hat": {"m": {None: 6, "cap": 2, "beanie": 2}, "w": {None: 8, "cap": 1}},
		"beard": {"m": {None: 8, "beard_stubble": 1}, "w": {None: 1}},
		"face": {None: 6, "glasses": 2},
		"top": {"hoodie": 3, "tshirt": 3},
		"bottom": {"m": {"jeans": 3, "joggers": 2}, "w": {"jeans": 3, "joggers": 1, "skirt": 1}},
		"shoes": {"sneakers": 1},
	},
	"extras": {"backpack": 0.6, "headphones": 0.3, "watch": 0.15, "crossbody": {"m": 0.05, "w": 0.2}},
}
