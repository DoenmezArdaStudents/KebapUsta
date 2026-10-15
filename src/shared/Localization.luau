-- UI strings (de/en). Server notifications send a key + params; the client formats them.

local IngredientData = require(script.Parent.IngredientData)
local MenuData = require(script.Parent.MenuData)

local Localization = {}

local S = {
	-- HUD
	cash = { de = "Kassa", en = "Cash" },
	level = { de = "Level", en = "Level" },
	day = { de = "Tag", en = "Day" },
	reputation = { de = "Ruf", en = "Reputation" },
	open = { de = "GEÖFFNET", en = "OPEN" },
	closed = { de = "GESCHLOSSEN", en = "CLOSED" },
	period_morning = { de = "Vormittag", en = "Morning" },
	period_lunch = { de = "Mittagsansturm!", en = "Lunch rush!" },
	period_quiet = { de = "Ruhige Zeit", en = "Quiet time" },
	period_evening = { de = "Abendansturm!", en = "Evening rush!" },
	period_late = { de = "Später Abend", en = "Late evening" },
	period_closed = { de = "Feierabend", en = "Closing time" },
	btn_upgrades = { de = "Upgrades", en = "Upgrades" },
	btn_stock = { de = "Lager", en = "Stock" },
	btn_goals = { de = "Ziele", en = "Goals" },
	btn_settings = { de = "Optionen", en = "Settings" },
	no_save = { de = "⚠ Speichern derzeit nicht möglich – Fortschritt wird nicht gesichert.", en = "⚠ Saving unavailable – progress is not being saved." },
	role_owner = { de = "Chef", en = "Owner" },
	role_staff = { de = "Mitarbeiter", en = "Staff" },

	-- tickets & meal
	tickets = { de = "Bestellungen", en = "Orders" },
	no_tickets = { de = "Noch keine Bestellungen", en = "No orders yet" },
	takeaway = { de = "Zum Mitnehmen", en = "To go" },
	plate = { de = "Zum Hieressen", en = "For here" },
	toasted = { de = "getoastet", en = "toasted" },
	warmed = { de = "aufgewärmt", en = "warmed" },
	heat_req = { de = "Brot erwärmen", en = "Heat bread" },
	extra = { de = "extra", en = "extra" },
	without = { de = "OHNE", en = "NO" },
	cheese = { de = "Käse", en = "Cheese" },
	meal_title = { de = "Dein Gericht", en = "Your meal" },
	meal_empty = { de = "Nimm Brot, Dürüm oder eine Box aus der Brotstation.", en = "Grab bread, dürüm or a box from the bread station." },
	meal_for = { de = "Vergleich mit: {name}", en = "Compared to: {name}" },
	meal_pick = { de = "Tippe auf ein Ticket, um es zu vergleichen.", en = "Tap a ticket to compare against it." },
	tray = { de = "Tablett", en = "Tray" },
	tray_empty = { de = "leer", en = "empty" },
	state_missing = { de = "fehlt", en = "missing" },
	state_wrong = { de = "falsch", en = "wrong" },
	state_extra = { de = "zu viel", en = "too much" },
	state_partial = { de = "unvollständig", en = "incomplete" },
	close_close = { de = "Brot schließen", en = "Close the bread" },
	close_wrap = { de = "Dürüm rollen", en = "Wrap the dürüm" },
	close_lid = { de = "Box schließen", en = "Close the box" },
	pack_takeaway = { de = "Einpacken (Mitnehmen)", en = "Pack to go" },
	pack_plate = { de = "Auf Teller (Hieressen)", en = "On a plate (for here)" },
	meat_label = { de = "Fleisch", en = "Meat" },
	meat_none = { de = "kein Fleisch", en = "no meat" },
	meat_mixed = { de = "Gemischt", en = "Mixed" },
	bread_heated = { de = "Brot: aufgewärmt", en = "Bread: heated" },
	bread_cold = { de = "Brot: kalt", en = "Bread: cold" },
	bread_burnt = { de = "Brot: verbrannt!", en = "Bread: burnt!" },
	portions = { de = "{n}/{need} Portionen", en = "{n}/{need} portions" },

	-- prompts
	p_take = { de = "Nehmen", en = "Take" },
	p_add = { de = "Hinzufügen", en = "Add" },
	p_cut = { de = "Fleisch schneiden", en = "Carve meat" },
	p_heat = { de = "Hitze umschalten", en = "Toggle heat" },
	p_toast_in = { de = "Brot in den Grill", en = "Put bread in grill" },
	p_toast_out = { de = "Brot herausnehmen", en = "Take bread out" },
	p_close = { de = "Schließen / Rollen", en = "Close / Wrap" },
	p_pack_takeaway = { de = "Einpacken", en = "Pack to go" },
	p_pack_plate = { de = "Auf Teller", en = "Serve on plate" },
	p_discard = { de = "Wegwerfen", en = "Throw away" },
	p_take_order = { de = "Bestellung aufnehmen", en = "Take order" },
	p_serve = { de = "Servieren", en = "Serve" },
	p_drink = { de = "Getränk nehmen", en = "Take drink" },
	p_stock = { de = "Ware bestellen", en = "Order supplies" },
	p_upgrades = { de = "Upgrades", en = "Upgrades" },
	p_to_tray = { de = "Aufs Tablett", en = "Put on tray" },

	-- notifications
	n_need_meal = { de = "Nimm zuerst Brot, Dürüm oder eine Box.", en = "Grab bread, a dürüm or a box first." },
	n_have_meal = { de = "Du bereitest schon ein Gericht zu.", en = "You are already preparing a meal." },
	n_out_of_stock = { de = "{item} ist ausverkauft! Bestelle im Lager nach.", en = "{item} is out of stock! Restock in storage." },
	n_closed_meal = { de = "Das Gericht ist schon geschlossen.", en = "The meal is already closed." },
	n_not_closed = { de = "Schließe/rolle das Gericht zuerst.", en = "Close/wrap the meal first." },
	n_not_packed = { de = "Pack das Gericht zuerst ein oder leg es auf einen Teller.", en = "Pack the meal or put it on a plate first." },
	n_too_much = { de = "Mehr passt nicht drauf.", en = "That won't fit." },
	n_undercooked = { de = "Das Fleisch ist noch roh! Warte, bis es durch ist.", en = "The meat is still raw! Wait until it's cooked." },
	n_burnt_meat = { de = "Verbranntes Fleisch! Dreh die Hitze runter.", en = "Burnt meat! Turn the heat down." },
	n_box_no_heat = { de = "Die Box gehört nicht in den Grill.", en = "The box doesn't go in the grill." },
	n_toast_busy = { de = "Der Grill ist besetzt.", en = "The grill is busy." },
	n_toast_burnt = { de = "Das Brot ist verbrannt!", en = "The bread got burnt!" },
	n_toast_perfect = { de = "Brot perfekt getoastet.", en = "Bread toasted perfectly." },
	n_tray_full = { de = "Dein Tablett ist voll.", en = "Your tray is full." },
	n_tray_empty = { de = "Dein Tablett ist leer.", en = "Your tray is empty." },
	n_nothing_for = { de = "Nichts auf dem Tablett passt zu dieser Bestellung.", en = "Nothing on your tray fits this order." },
	n_discarded = { de = "Gericht weggeworfen.", en = "Meal thrown away." },
	n_level_up = { de = "Level {level} erreicht!", en = "Reached level {level}!" },
	n_upgrade_bought = { de = "Upgrade gekauft: {name}", en = "Upgrade purchased: {name}" },
	n_not_enough_cash = { de = "Nicht genug Geld.", en = "Not enough cash." },
	n_level_req = { de = "Benötigt Level {level}.", en = "Requires level {level}." },
	-- progression & unlocks
	n_first_stock = { de = "🆕 {item} ist eingelagert – Kunden bestellen es ab jetzt!", en = "🆕 {item} is in stock – customers will order it from now on!" },
	n_not_unlocked = { de = "Noch nicht freigeschaltet – kauf es zuerst im Shop-Ausbau.", en = "Not unlocked yet – buy it in Shop Upgrades first." },
	n_unlock_requires = { de = "Benötigt zuerst: {need}.", en = "Requires first: {need}." },
	n_unlock_owned = { de = "Schon gekauft.", en = "Already bought." },
	n_unlock_shipping = { de = "📦 {name} gekauft – Lieferung in {s}s.", en = "📦 {name} bought – delivered in {s}s." },
	n_unlock_arrived = { de = "📦 {name} ist angekommen! Kiste in der Küche auspacken [E halten].", en = "📦 {name} has arrived! Unpack the crate in the kitchen [hold E]." },
	n_unlock_ready = { de = "✨ {name} freigeschaltet!", en = "✨ {name} unlocked!" },
	n_knife_ready = { de = "🔪 Neues Messer: {name} – ab sofort im Einsatz.", en = "🔪 New knife: {name} – in use right away." },
	n_installed = { de = "🔧 {name} eingebaut ({by}).", en = "🔧 {name} installed ({by})." },
	n_installed_restock = { de = "🔧 {name} eingebaut! Jetzt am Laptop beim Lieferanten nachbestellen.", en = "🔧 {name} installed! Now order it from the supplier on the laptop." },
	n_new_available = { de = "🔓 Neu verfügbar: {name} ({price}) – Laptop → Shop-Ausbau", en = "🔓 Now available: {name} ({price}) – Laptop → Shop Upgrades" },
	n_upgrade_needs = { de = "Dafür brauchst du zuerst: {name}.", en = "You need this first: {name}." },
	n_short_goal_done = { de = "🎯 Ziel geschafft! +{reward} · +{xp} XP", en = "🎯 Goal complete! +{reward} · +{xp} XP" },
	n_spit_busy = { de = "{name} schneidet gerade an diesem Spieß.", en = "{name} is carving at this spit right now." },
	lobby_tp_failed = { de = "Teleport fehlgeschlagen – bitte nochmal versuchen.", en = "Teleport failed – please try again." },
	p_unpack = { de = "Auspacken & einbauen", en = "Unpack & install" },
	n_owner_only = { de = "Nur der Chef kann das kaufen.", en = "Only the owner can buy this." },
	n_stage_building = { de = "🚧 Bauarbeiten: {name} wird gebaut …", en = "🚧 Construction: building {name} …" },
	n_stage_built = { de = "🎉 Ausbau fertig: {name}!", en = "🎉 Expansion done: {name}!" },
	n_hired = { de = "🤝 {name} arbeitet jetzt bei dir ({role}).", en = "🤝 {name} now works for you ({role})." },
	n_fired = { de = "{name} hat den Laden verlassen.", en = "{name} has left the shop." },
	n_trained = { de = "📚 {name} hat das Training abgeschlossen: Stufe {skill}.", en = "📚 {name} finished training: level {skill}." },
	n_wages = { de = "💶 Löhne bezahlt: {amount}", en = "💶 Wages paid: {amount}" },
	n_dirty = { de = "🧽 Der Laden ist schmutzig – Kunden sind unzufrieden!", en = "🧽 The shop is dirty – customers are unhappy!" },
	n_new_regular = { de = "💛 {name} ist jetzt Stammkunde!", en = "💛 {name} is now a regular!" },
	n_regular_back = { de = "💛 Stammkunde {name} ist wieder da (Besuch {n}).", en = "💛 Regular {name} is back (visit {n})." },
	n_critic = { de = "🖋️ Gastrokritiker/in {name} ist im Laden – gib dein Bestes!", en = "🖋️ Food critic {name} is here – do your best!" },
	n_critic_good = { de = "📰 Top-Kritik im Stadtanzeiger: {stars} – dein Ruf steigt!", en = "📰 Great review in the city paper: {stars} – reputation up!" },
	n_critic_bad = { de = "📰 Schlechte Kritik im Stadtanzeiger: {stars}", en = "📰 Bad review in the city paper: {stars}" },
	n_delivery_new = { de = "📞 Neue Lieferbestellung: {name}", en = "📞 New delivery order: {name}" },
	n_delivery_done = { de = "🛵 Lieferung für {name} ist unterwegs!", en = "🛵 Delivery for {name} is on its way!" },
	n_delivery_lost = { de = "📞 {name} hat die Lieferung storniert – zu lange gewartet.", en = "📞 {name} cancelled the delivery – waited too long." },
	n_no_delivery = { de = "Gerade gibt es keine Lieferbestellung.", en = "There is no delivery order right now." },
	n_branch_income = { de = "🏪 Einnahmen deiner Filialen: {amount}", en = "🏪 Income from your branches: {amount}" },
	n_branch_new = { de = "🏪 Neue Filiale eröffnet: {name}!", en = "🏪 New branch opened: {name}!" },
	n_branch_up = { de = "🏪 {name} ausgebaut – Stufe {level}.", en = "🏪 {name} upgraded – level {level}." },
	n_theme_set = { de = "🎨 Neue Einrichtung: {name}", en = "🎨 New interior: {name}" },
	n_slapped_innocent = { de = "😳 Du hast {name} grundlos geschlagen – dein Ruf leidet!", en = "😳 You slapped {name} for no reason – your reputation suffers!" },
	n_meat_coldroom = { de = "❄️ {item} ist im Kühlraum eingelagert – ab morgen kannst du es auf den Spieß stecken.", en = "❄️ {item} is stored in the cold room – from tomorrow you can mount it on the spit." },
	n_cone_taken = { de = "🥩 Spieß genommen – bring ihn zum Grill und drück [F].", en = "🥩 Cone taken – bring it to the spit and press [F]." },
	n_cone_loaded = { de = "🔥 Neuer {item}-Spieß aufgesteckt!", en = "🔥 New {item} cone mounted!" },
	n_cone_resting = { de = "❄️ Dieses Fleisch muss erst über Nacht ruhen.", en = "❄️ This meat has to rest overnight first." },
	n_carry_full = { de = "Du trägst schon einen Spieß.", en = "You're already carrying a cone." },
	n_no_cone = { de = "Hol erst einen Spieß aus dem Kühlraum.", en = "Get a cone from the cold room first." },
	n_wrong_spit = { de = "Das ist der falsche Spieß für dieses Fleisch.", en = "That's the wrong spit for this meat." },
	n_spit_full = { de = "Der Spieß ist noch zu voll – schneide erst mehr ab.", en = "The spit is still too full – carve more first." },
	n_price_set = { de = "Preise: {name}", en = "Prices: {name}" },
	n_price_locked = { de = "Premium-Preise gibt es erst ab Ausbau „{name}“.", en = "Premium prices need the “{name}” expansion." },
	n_storage_full = { de = "Das Lager ist voll.", en = "Storage is full." },
	n_restock_ordered = { de = "{item} bestellt – Lieferung in {s}s.", en = "{item} ordered – arrives in {s}s." },
	n_restock_arrived = { de = "Lieferung angekommen: {item}", en = "Delivery arrived: {item}" },
	n_walkout = { de = "{name} ist wütend gegangen!", en = "{name} walked out angry!" },
	n_refused = { de = "{name} hat das Gericht abgelehnt.", en = "{name} refused the meal." },
	n_rate_limited = { de = "Langsamer!", en = "Slow down!" },
	n_queue_full = { de = "Die Schlange ist voll.", en = "The queue is full." },
	n_achievement = { de = "🏆 Erfolg: {name} (+{reward})", en = "🏆 Achievement: {name} (+{reward})" },
	n_goal_done = { de = "🎯 Tagesziel geschafft! +{reward}", en = "🎯 Daily goal complete! +{reward}" },
	n_new_owner = { de = "{name} ist jetzt der Chef des Ladens.", en = "{name} is now the shop owner." },
	n_day_start = { de = "Tag {day} beginnt – der Laden ist offen!", en = "Day {day} begins – the shop is open!" },
	n_closing = { de = "Feierabend! Keine neuen Kunden mehr.", en = "Closing time! No new customers." },
	n_closing_lock = { de = "🌙 22:00 – Feierabend! Sperr den Laden an der Tür ab (oder am Laptop), um den Tag zu beenden.", en = "🌙 22:00 – Closing time! Lock the shop at the door (or on the laptop) to end the day." },
	n_lock_reminder = { de = "🔑 Der Laden ist noch nicht abgesperrt.", en = "🔑 The shop is not locked yet." },
	n_lock_too_early = { de = "Absperren geht erst nach 22:00 Uhr.", en = "You can only lock up after 22:00." },
	n_locked = { de = "🔒 {name} hat den Laden abgesperrt. Gute Nacht!", en = "🔒 {name} locked the shop. Good night!" },
	n_new_order = { de = "🧾 Neue Bestellung von {name}", en = "🧾 New order from {name}" },
	p_laptop = { de = "Laptop benutzen", en = "Use laptop" },
	p_slap = { de = "Backpfeife geben", en = "Slap" },
	n_slapped = { de = "👋 {name} hat eine Backpfeife bekommen und geht.", en = "👋 {name} got slapped and leaves." },
	p_lock = { de = "Laden absperren", en = "Lock the shop" },
	p_lock_early = { de = "Absperren (ab 22:00)", en = "Lock up (after 22:00)" },
	sleep_title = { de = "Gute Nacht…", en = "Good night…" },
	wake_title = { de = "Tag {day} · 10:00", en = "Day {day} · 10:00" },
	wake_sub = { de = "Ausgeschlafen! Ab in den Laden.", en = "Well rested! Head into the shop." },
	n_event_start = { de = "{icon} {name} {desc}", en = "{icon} {name} {desc}" },
	n_event_end = { de = "{icon} {name} ist vorbei.", en = "{icon} {name} is over." },
	n_rush = { de = "{period} Mehr Kunden kommen!", en = "{period} More customers incoming!" },
	n_drink_taken = { de = "{item} aufs Tablett gestellt.", en = "{item} put on your tray." },
	n_meal_to_tray = { de = "Gericht aufs Tablett gestellt.", en = "Meal put on your tray." },
	n_spit_empty = { de = "Der Spieß ist leer! Bestelle Fleisch nach.", en = "The spit is empty! Restock meat." },
	n_in_grill = { de = "Das Brot ist gerade im Grill.", en = "The bread is in the grill right now." },
	n_board_busy = { de = "Beide Arbeitsbretter sind belegt.", en = "Both prep boards are in use." },
	n_not_your_board = { de = "Das ist nicht dein Brett.", en = "That's not your board." },
	n_need_bread_first = { de = "Erst ein Gericht beginnen.", en = "Start a meal first." },
	n_vip = { de = "⭐ Ein Restaurantkritiker ist da! Doppelte Belohnung bei perfekter Bedienung.", en = "⭐ A food critic arrived! Double reward for perfect service." },

	-- feedback
	fb_stars = { de = "Bewertung", en = "Rating" },
	fb_tip = { de = "Trinkgeld", en = "Tip" },
	fb_xp = { de = "EP", en = "XP" },
	fb_accuracy = { de = "Genauigkeit", en = "Accuracy" },
	fb_quality = { de = "Qualität", en = "Quality" },
	fb_speed = { de = "Wartezeit", en = "Waiting" },

	-- panels
	upgrades_title = { de = "Upgrades & Ausbau", en = "Upgrades & Expansion" },
	tier = { de = "Stufe", en = "Tier" },
	maxed = { de = "MAX", en = "MAX" },
	buy = { de = "Kaufen", en = "Buy" },
	stock_title = { de = "Lager & Nachbestellung", en = "Stock & Restocking" },
	restock = { de = "Nachbestellen", en = "Restock" },
	in_transit = { de = "unterwegs", en = "in transit" },
	goals_title = { de = "Tagesziele & Statistik", en = "Daily Goals & Stats" },
	settings_title = { de = "Einstellungen", en = "Settings" },
	language = { de = "Sprache", en = "Language" },
	music_volume = { de = "Atmosphäre", en = "Ambience" },
	sfx_volume = { de = "Effekte", en = "Effects" },
	hints = { de = "Tipps anzeigen", en = "Show hints" },
	on = { de = "An", en = "On" },
	off = { de = "Aus", en = "Off" },
	close = { de = "Schließen", en = "Close" },
	replay_tutorial = { de = "Tutorial wiederholen", en = "Replay tutorial" },
	stat_served = { de = "Kunden bedient", en = "Customers served" },
	stat_perfect = { de = "Perfekte Bestellungen", en = "Perfect orders" },
	stat_earned = { de = "Gesamt verdient", en = "Total earned" },
	stat_days = { de = "Arbeitstage", en = "Days worked" },
	stat_walkouts = { de = "Verlorene Kunden", en = "Customers lost" },
	achievements = { de = "Erfolge", en = "Achievements" },
	today = { de = "Heute", en = "Today" },
	revenue = { de = "Umsatz", en = "Revenue" },
	expenses = { de = "Ausgaben (Ware)", en = "Expenses (supplies)" },
	rent = { de = "Miete & Strom", en = "Rent & power" },
	profit = { de = "Gewinn", en = "Profit" },
	avg_rating = { de = "Ø Bewertung", en = "Avg rating" },
	day_summary = { de = "Tagesabschluss – Tag {day}", en = "Day {day} summary" },
	next_day = { de = "Nächster Tag beginnt gleich...", en = "Next day starts shortly..." },

	goal_serve = { de = "Bediene {n} Kunden", en = "Serve {n} customers" },
	goal_perfect = { de = "{n} perfekte Bestellungen", en = "{n} perfect orders" },
	goal_earn = { de = "Verdiene {n}", en = "Earn {n}" },
	goal_duerum = { de = "Verkaufe {n} Dürüm", en = "Sell {n} dürüm" },
	goal_drinks = { de = "Verkaufe {n} Getränke", en = "Sell {n} drinks" },
	goal_nowalk = { de = "Höchstens {n} verlorene Kunden", en = "Lose at most {n} customers" },

	-- tutorial
	tut_title = { de = "Tutorial", en = "Tutorial" },
	tut_skip = { de = "Überspringen", en = "Skip" },
	tut_1 = { de = "Willkommen in deinem Kebap-Laden! Ein Kunde kommt gleich zur Kassa. Geh hinter die Theke und nimm seine Bestellung auf – [F] beim Kunden oder am Laptop „Bestellung aufnehmen“.", en = "Welcome to your kebab shop! A customer is coming to the register. Go behind the counter and take their order – [F] at the customer or 'Take order' on the laptop." },
	tut_2 = { de = "Die Bestellung ist jetzt im Laptop und unten in der Zutatenliste. Nimm ein Kebap-Brot aus der Brotstation hinten.", en = "The order is now on the laptop and in the ingredient list below. Take a kebab bread from the bread station at the back." },
	tut_3 = { de = "Geh zum Hühnerspieß und drück [E]. Schneide im Takt (Klick / Leertaste) – im grünen Bereich wird das Fleisch am besten. Das Ticket zeigt, wie viele Portionen nötig sind. [E] = fertig.", en = "Go to the chicken spit and press [E]. Cut in rhythm (click / space) – the green zone gives the best meat. The ticket shows how many portions are needed. [E] = done." },
	tut_4 = { de = "Füge Gemüse aus der Kühltheke und Saucen aus den Spendern hinzu. Grüne Häkchen zeigen, was schon passt.", en = "Add vegetables from the cold counter and sauces from the dispensers. Green ticks show what's already right." },
	tut_5 = { de = "Schließe das Brot am Brett und pack es ein. Dann wandert es auf dein Tablett.", en = "Close the bread at the board and pack it. It then goes on your tray." },
	tut_6 = { de = "Der Kunde wartet vorne an der Theke beim Einpacken – serviere ihm das Gericht!", en = "The customer waits at the counter in front of the packing area – serve the meal!" },
	tut_7 = { de = "Super! Du hast Geld verdient. Zutaten werden verbraucht – im Lagerraum oder in der Lieferanten-App am Laptop kannst du nachbestellen. Neue Zutaten & Geräte kaufst du am Laptop im Shop-Ausbau – die NÄCHSTEN ZIELE links zeigen dir den Weg. Um 22 Uhr Laden an der Tür absperren. Viel Erfolg!", en = "Great! You earned money. Ingredients get used up – restock in the storage room or with the supplier app on the laptop. Buy new ingredients & equipment in Shop Upgrades on the laptop – the NEXT GOALS on the left show the way. At 22:00 lock the shop at the door. Good luck!" },
}

Localization.Strings = S

function Localization.Get(key: string, lang: string, params: { [string]: any }?): string
	local entry = S[key]
	local text = entry and (entry[lang] or entry.en) or key
	if params then
		text = string.gsub(text, "{(%w+)}", function(k)
			local v = params[k]
			if v == nil then
				return "{" .. k .. "}"
			end
			if type(v) == "table" then
				return v[lang] or v.en or "?"
			end
			return tostring(v)
		end)
	end
	return text
end

function Localization.Ingredient(id: string, lang: string): string
	local def = IngredientData.Find(id)
	if def then
		return def.name[lang]
	end
	local stock = IngredientData.Stock[id]
	if stock then
		return stock.name[lang]
	end
	return id
end

function Localization.Menu(id: string, lang: string): string
	local def = MenuData.Items[id]
	return def and def.name[lang] or id
end

function Localization.Money(n: number): string
	local neg = n < 0
	n = math.abs(n)
	local whole = math.floor(n)
	local cents = math.floor((n - whole) * 100 + 0.5)
	if cents >= 100 then
		whole += 1
		cents -= 100
	end
	return string.format("%s€%d,%02d", neg and "-" or "", whole, cents)
end

return Localization
