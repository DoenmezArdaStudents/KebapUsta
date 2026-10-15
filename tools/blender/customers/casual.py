"""Kundentyp „Freizeit“ (Erwachsene): T-Shirt, Hoodie oder Kurzarmhemd, Jeans/Chino, Sneaker."""

ARCHETYPE = {
	"id": "casual",
	"name": {"de": "Freizeit", "en": "Casual"},
	"weight": 3,
	"bodies": {"m": 1, "w": 1},
	"scale": (0.96, 1.03),
	"palettes": {
		"top": ["#2f5d8a", "#8a2f3a", "#3a7a5a", "#e8e0d0", "#2b2b30", "#d98c3a", "#6a8caf", "#c25a7a", "#f2f2f2"],
		"outer": ["#6a5a48", "#2f3a55", "#7a3c50", "#4a5a3a", "#c8b89a"],
		"bottom": ["#2f4a7a", "#4a6fa0", "#1f1f24", "#8a7a5a", "#5a5f4a", "#c8b89a"],
		"shoes": ["#f2f2f2", "#202022", "#5a3a28", "#3a4a6a"],
		"hair": ["#1e1914", "#3b2a1c", "#5a3c1e", "#c8a05a", "#8c4f28", "#a07040"],
		"accent": ["#d8483a", "#f0b428", "#2f8f8a", "#2b2b30", "#3a6fd8"],
	},
	"slots": {
		"hair": {
			"m": {"hair_crop": 2, "hair_sidepart": 1, "hair_curly_top": 2, "hair_buzz": 2},
			"w": {"hair_long": 3, "hair_bob": 2, "hair_ponytail": 2, "hair_curly_long": 2, "hair_bun": 1},
		},
		"hat": {"m": {None: 7, "cap": 2, "beanie": 1}, "w": {None: 9, "cap": 1}},
		"beard": {"m": {None: 3, "beard_stubble": 3, "beard_full": 2}, "w": {None: 1}},
		"face": {None: 4, "glasses": 1},
		"top": {"tshirt": 3, "hoodie": 2, "shirt:B": 2},
		"outer": {"m": {None: 5, "cardigan": 1}, "w": {None: 3, "cardigan": 1}},
		"bottom": {"m": {"jeans": 3, "trousers": 1, "joggers": 1}, "w": {"jeans": 3, "skirt": 1, "trousers": 1}},
		"shoes": {"sneakers": 3, "dress_shoes": 1},
	},
	"extras": {"watch": 0.4, "crossbody": {"m": 0.1, "w": 0.3}},
}
