-- Template-based customer dialogue (German/Austrian + English). No external AI needed.
-- Every line is a {de, en} pair so the client can switch language at any time.
-- To plug in an AI dialogue provider later, replace DialogueConfig.Line()/OrderSpeech() with a
-- provider that returns the same {de, en} structure; the rest of the game only consumes that.

local IngredientData = require(script.Parent.IngredientData)
local MenuData = require(script.Parent.MenuData)

local DialogueConfig = {}

local function L(de, en)
	return { de = de, en = en }
end

-- customer first names by sex ("m" / "w", as in Shared/CustomerLooks), so name and look match
DialogueConfig.FirstNames = {
	m = {
		"Lukas", "Mehmet", "Florian", "David", "Emre", "Stefan", "Maximilian", "Burak", "Tobias", "Kerem",
		"Felix", "Can", "Dominik", "Paul", "Ali", "Jakob", "Marko", "Peter", "Franz", "Moritz",
	},
	w = {
		"Anna", "Sophie", "Elif", "Lena", "Julia", "Ayşe", "Katharina", "Sarah", "Zeynep", "Johanna",
		"Marie", "Laura", "Selin", "Hannah", "Theresa", "Nina", "Ivana", "Gerti", "Resi", "Leonie",
	},
}

function DialogueConfig.RandomName(rng: Random, sex: string): string
	local list = DialogueConfig.FirstNames[sex] or DialogueConfig.FirstNames.m
	return list[rng:NextInteger(1, #list)]
end

-- sex of a known name ("Frau …" / "Herr …" or a first name from the lists), nil if unknown
function DialogueConfig.SexOfName(name: string?): string?
	if not name then
		return nil
	elseif name:match("^Frau ") then
		return "w"
	elseif name:match("^Herr ") then
		return "m"
	end
	for sex, list in DialogueConfig.FirstNames do
		if table.find(list, name) then
			return sex
		end
	end
	return nil
end

-- Personalities shape patience, pickiness, tips and dialogue tone
DialogueConfig.Personalities = {
	friendly = { weight = 30, patience = 1.15, tip = 1.2, picky = 0.25, emoji = "😊" },
	impatient = { weight = 15, patience = 0.6, tip = 0.8, picky = 0.2, emoji = "😤" },
	picky = { weight = 15, patience = 1.0, tip = 1.0, picky = 0.85, emoji = "🧐" },
	generous = { weight = 10, patience = 1.1, tip = 2.0, picky = 0.3, emoji = "🤑" },
	funny = { weight = 15, patience = 1.0, tip = 1.1, picky = 0.3, emoji = "😄" },
	bro = { weight = 15, patience = 0.9, tip = 1.0, picky = 0.35, emoji = "😎" },
	aggressive = { weight = 9, patience = 0.75, tip = 0.4, picky = 0.5, emoji = "😡" },
}

DialogueConfig.Lines = {
	greet = {
		default = {
			L("Servus!", "Hi there!"),
			L("Grüß dich!", "Hey, good to see you!"),
			L("Hallo!", "Hello!"),
			L("Griaß di!", "Howdy!"),
			L("Guten Tag!", "Good afternoon!"),
		},
		impatient = { L("Ja, hallo, ich hab's eilig.", "Yeah, hi, I'm in a hurry."), L("Hallo. Schnell bitte.", "Hi. Quickly, please.") },
		bro = { L("Bruder, was geht!", "Bro, what's up!"), L("Ey Chef, alles klar?", "Yo boss, all good?") },
		aggressive = { L("Was schaust du so? Mach hinne!", "What are you looking at? Hurry up!"), L("Endlich. Hat ja ewig gedauert, Oida.", "Finally. Took forever, mate.") },
		funny = { L("Servus! Ich hab Hunger wie ein Bär!", "Hey! I'm hungry as a bear!"), L("Hallo! Riecht ja wieder herrlich hier!", "Hi! Smells amazing in here again!") },
		picky = { L("Guten Tag. Ich hätte da ganz genaue Wünsche.", "Good day. I have very specific wishes."), L("Hallo. Bitte genau zuhören.", "Hello. Please listen carefully.") },
		generous = { L("Servus, mein Lieblingskebapstand!", "Hey, my favourite kebab place!"), L("Grüß dich, Chef! Wie läuft's?", "Hi boss! How's business?") },
	},
	order_wrap = {
		default = {
			L("Kann ich bitte {order} haben?", "Can I please have {order}?"),
			L("Ich hätte gerne {order}.", "I'd like {order}."),
			L("Ich nehme {order}. Danke!", "I'll take {order}. Thanks!"),
			L("{order}, bitte.", "{order}, please."),
		},
		bro = { L("Mach mir {order}, Bruder!", "Make me {order}, bro!") },
		impatient = { L("{order}. Aber zack zack!", "{order}. And make it snappy!") },
		aggressive = { L("{order}. Und zwar dalli, sonst gibt's Ärger!", "{order}. And quick, or there'll be trouble!"), L("Gib mir {order}. Und trödel nicht!", "Give me {order}. And don't dawdle!") },
		funny = { L("Ich träume schon die ganze Woche von {order}!", "I've been dreaming all week of {order}!") },
		picky = { L("Ich möchte {order}. Genau so, bitte.", "I'd like {order}. Exactly like that, please.") },
	},
	drink_wrap = {
		default = {
			L("Und dazu {drinks}.", "And {drinks} with that."),
			L("Und noch {drinks}, bitte.", "Plus {drinks}, please."),
		},
	},
	place = {
		takeaway = { L("Zum Mitnehmen.", "To go."), L("Nehm ich mit.", "I'll take it with me.") },
		plate = { L("Ich ess hier.", "I'll eat here."), L("Zum Hieressen, bitte.", "For here, please.") },
	},
	ack = {
		default = { L("Passt, danke!", "Great, thanks!"), L("Super, ich warte drüben.", "Super, I'll wait over there.") },
		impatient = { L("Ja, aber bitte schnell.", "Yeah, but please hurry.") },
		bro = { L("Ehrenmann!", "Legend!") },
	},
	waiting = {
		default = { L("Hmm, das riecht gut.", "Mmm, that smells good."), L("Ich schau dir gern zu.", "I like watching you work.") },
		funny = { L("Mein Magen knurrt schon lauter als die Straßenbahn.", "My stomach is louder than the tram."), L("Ist das Fleisch frisch vom Spieß? Hehe.", "Is that meat fresh off the spit? Hehe.") },
		bro = { L("Viel Fleisch, Bruder, ja?", "Lots of meat, bro, yeah?") },
	},
	impatient = {
		default = {
			L("Dauert's noch lange?", "Will it take much longer?"),
			L("Hallo? Ich warte schon ewig.", "Hello? I've been waiting forever."),
			L("Geht's ein bisserl schneller?", "Could you go a bit faster?"),
		},
		impatient = { L("Das gibt's ja nicht! Wie lange noch?!", "Unbelievable! How much longer?!") },
		funny = { L("Ich werd hier noch zum Skelett!", "I'm turning into a skeleton here!") },
	},
	-- aggressive customers shouting at the staff
	rant = {
		default = {
			L("Wie lange dauert das noch?!", "How much longer is this going to take?!"),
			L("Ich warte hier seit Stunden, Oida!", "I've been waiting here for hours!"),
			L("Bist du eingeschlafen oder was?!", "Did you fall asleep or what?!"),
			L("Das ist der langsamste Laden in ganz Wien!", "This is the slowest shop in all of Vienna!"),
			L("Ich will sofort den Chef sprechen!", "I want to speak to the manager right now!"),
			L("Beweg dich, ich hab Hunger!", "Move it, I'm starving!"),
			L("Soll ich's vielleicht selber machen?!", "Should I just make it myself?!"),
			L("Hallo?! Schläfst du?! HALLO?!", "Hello?! Are you asleep?! HELLO?!"),
			L("Das gibt eine Ein-Stern-Bewertung, Freundchen!", "That's a one-star review, buddy!"),
			L("Unglaublich! Schneller, Meister!", "Unbelievable! Faster, chief!"),
		},
	},
	-- reaction after a slap
	slapped = {
		default = {
			L("AU! Schon gut, schon gut, ich geh ja!", "OW! Fine, fine, I'm leaving!"),
			L("Aua! Das sag ich meiner Mama!", "Ouch! I'm telling my mum!"),
			L("Okay… okay… ich komm nie wieder!", "Okay… okay… I'm never coming back!"),
			L("Hey! Ich hab ja nur gefragt…", "Hey! I was only asking…"),
			L("Autsch! Ich hab's verstanden…", "Ouch! I get it…"),
		},
	},
	leave_angry = {
		default = {
			L("Das ist mir zu blöd. Ich geh woanders hin!", "Forget it. I'm going somewhere else!"),
			L("Ich hab keine Zeit mehr. Pfiat di!", "I'm out of time. Bye!"),
		},
		bro = { L("Bruder, nicht dein Ernst. Tschüss.", "Bro, seriously? I'm out.") },
	},
	refuse = {
		default = {
			L("Das hab ich so nicht bestellt!", "That's not what I ordered!"),
			L("Nein, nein, das ist falsch. Bitte nochmal.", "No, no, that's wrong. Please make it again."),
		},
		picky = { L("Das ist ja völlig falsch! Schau aufs Ticket!", "That's completely wrong! Look at the ticket!") },
	},
	partial = {
		default = { L("Danke! Und der Rest?", "Thanks! And the rest?"), L("Ok, fehlt aber noch was.", "OK, but something's still missing.") },
	},
	react_great = {
		default = { L("Perfekt! Genau so wollte ich's!", "Perfect! Exactly how I wanted it!"), L("Wow, schaut super aus!", "Wow, that looks great!"), L("Leiwand, danke!", "Awesome, thanks!") },
		bro = { L("Bruder, du bist der Beste!", "Bro, you're the best!") },
		funny = { L("Ich könnte dich umarmen! Mach ich aber nicht.", "I could hug you! I won't, though.") },
	},
	react_ok = {
		default = { L("Passt schon, danke.", "That'll do, thanks."), L("Ok, danke.", "OK, thanks.") },
		picky = { L("Hm. Nicht ganz, aber gut.", "Hm. Not quite, but fine.") },
	},
	react_bad = {
		default = { L("Naja... das war nicht ganz meine Bestellung.", "Well... that wasn't really my order."), L("Hm, da fehlt einiges.", "Hm, quite a lot is missing.") },
		impatient = { L("Falsch UND langsam. Super.", "Wrong AND slow. Great.") },
	},
	tip = {
		default = { L("Stimmt so!", "Keep the change!"), L("Das Trinkgeld ist für dich.", "The tip is for you.") },
		generous = { L("Hier, für die Kaffeekassa!", "Here, for the tip jar!") },
	},
	goodbye = {
		default = { L("Baba!", "Bye!"), L("Schönen Tag noch!", "Have a nice day!"), L("Bis zum nächsten Mal!", "See you next time!") },
	},
	eating = {
		default = { L("Mmmh!", "Mmmh!"), L("So gut!", "So good!") },
	},
	cancel = {
		default = { L("Weißt du was, ich storniere.", "You know what, I'm cancelling.") },
	},
	vip = {
		default = { L("Ich bin Restaurantkritiker. Mal sehen, was du kannst.", "I'm a food critic. Let's see what you've got.") },
	},
	group = {
		default = { L("Ich bestelle für meine Kollegen mit.", "I'm ordering for my colleagues too.") },
	},
}

function DialogueConfig.Line(category: string, personality: string?, rng: Random?)
	local cat = DialogueConfig.Lines[category]
	if not cat then
		return L("...", "...")
	end
	local pool = {}
	local specific = personality and cat[personality]
	if specific then
		for _, l in ipairs(specific) do
			table.insert(pool, l)
			table.insert(pool, l) -- personality lines are twice as likely
		end
	end
	for _, l in ipairs(cat.default or {}) do
		table.insert(pool, l)
	end
	if #pool == 0 then
		return L("...", "...")
	end
	local r = rng or Random.new()
	return pool[r:NextInteger(1, #pool)]
end

---------------------------------------------------------------------------
-- Natural-language order descriptions built from structured order data
---------------------------------------------------------------------------
local ARTICLE = {
	de = { kebap = "einen Kebap", duerum = "einen Dürüm", veggie = "einen Veggie-Kebap", box = "eine Kebap-Box" },
	en = { kebap = "a kebab", duerum = "a dürüm", veggie = "a veggie kebab", box = "a kebab box" },
}
local NUM = { de = { "einen", "zwei", "drei", "vier" }, en = { "one", "two", "three", "four" } }

local MEAT_PHRASE = {
	chicken = L("mit Hühnerfleisch", "with chicken"),
	veal = L("mit Kalbfleisch", "with veal"),
	mixed = L("gemischt", "with mixed meat"),
}

-- German dative forms where they differ (used after "mit")
local DATIVE_DE = { sauce_spicy = "scharfer Sauce", spicy = "scharfer Sauce" }
local DRINK_IDS = { ayran = true, cola = true, almdudler = true }

local function ingName(id, lang)
	local def = IngredientData.Find(id)
	local name = def and def.name[lang] or id
	if lang == "de" and DATIVE_DE[id] then
		return DATIVE_DE[id]
	end
	if lang == "en" and not DRINK_IDS[id] then
		name = string.lower(name)
	end
	return name
end

local function joinList(parts, lang)
	if #parts == 0 then
		return ""
	elseif #parts == 1 then
		return parts[1]
	end
	local last = parts[#parts]
	local head = table.concat(parts, ", ", 1, #parts - 1)
	return head .. (lang == "de" and " und " or " and ") .. last
end

local MOD_TEXT = {
	toasted = L("getoastet", "toasted"),
	extra_meat = L("mit extra Fleisch", "with extra meat"),
	cheese = L("mit Käse", "with cheese"),
	extra_spicy = L("extra scharf", "extra spicy"),
	not_spicy = L("nicht scharf", "not spicy"),
	everything = L("mit allem", "with everything"),
}

local function modPhrase(mod, lang)
	if MOD_TEXT[mod] then
		return MOD_TEXT[mod][lang]
	end
	local v = string.match(mod, "^no_(.+)$")
	if v then
		return (lang == "de" and "ohne " or "no ") .. ingName(v, lang)
	end
	v = string.match(mod, "^add_(.+)$")
	if v then
		return (lang == "de" and "mit " or "with ") .. ingName(v, lang)
	end
	v = string.match(mod, "^sauce_only_(.+)$")
	if v then
		return (lang == "de" and "nur mit " or "only ") .. ingName(v, lang)
	end
	v = string.match(mod, "^extra_sauce_(.+)$")
	if v then
		return (lang == "de" and "mit extra " or "with extra ") .. ingName(v, lang)
	end
	return mod
end

-- style "mods": "einen Kebap mit Hühnerfleisch, ohne Zwiebeln und extra scharf"
-- style "explicit": "einen Dürüm mit Kalbfleisch, Salat, Rotkraut und Joghurtsauce"
function DialogueConfig.DescribeItem(item, lang: string, style: string?)
	local head = ARTICLE[lang][item.menu] or item.menu
	local parts = {}
	if style == "explicit" then
		local listParts = {}
		if item.meat ~= "none" then
			table.insert(parts, MEAT_PHRASE[item.meat][lang])
		end
		for _, v in ipairs(IngredientData.VegOrder) do
			if item.veg[v] then
				table.insert(listParts, ingName(v, lang))
			end
		end
		for _, s in ipairs(IngredientData.SauceOrder) do
			local n = item.sauces[s]
			if n and n > 0 then
				local name = ingName(s, lang)
				if n > 1 then
					name = (lang == "de" and "extra " or "extra ") .. name
				end
				table.insert(listParts, name)
			end
		end
		if item.cheese and item.menu ~= "veggie" then
			table.insert(listParts, ingName("cheese", lang))
		end
		local s = head
		if #parts > 0 then
			s ..= " " .. parts[1]
			if #listParts > 0 then
				s ..= ", " .. joinList(listParts, lang)
			end
		elseif #listParts > 0 then
			s ..= (lang == "de" and " mit " or " with ") .. joinList(listParts, lang)
		end
		if item.meatPortions > (MenuData.Items[item.menu].meatPortions or 0) then
			s ..= (lang == "de" and ", extra Fleisch" or ", extra meat")
		end
		if item.heat and MenuData.Items[item.menu].toastOption then
			s ..= (lang == "de" and ", getoastet" or ", toasted")
		end
		return s
	end

	local everything = table.find(item.mods, "everything") ~= nil
	if item.meat ~= "none" then
		local meatText = MEAT_PHRASE[item.meat][lang]
		if everything then
			if lang == "de" then
				meatText ..= (item.meat == "mixed" and " mit allem" or " und allem")
			else
				meatText ..= " and everything"
			end
		end
		table.insert(parts, meatText)
	end
	for _, mod in ipairs(item.mods) do
		if not (mod == "everything" and item.meat ~= "none") then
			table.insert(parts, modPhrase(mod, lang))
		end
	end
	if #parts == 0 then
		return head
	end
	local sep = " "
	if lang == "en" and string.sub(parts[1], 1, 5) ~= "with " then
		sep = ", "
	end
	return head .. sep .. joinList(parts, lang)
end

function DialogueConfig.DescribeDrinks(drinks, lang)
	if #drinks == 0 then
		return ""
	end
	local counts, orderList = {}, {}
	for _, d in ipairs(drinks) do
		if not counts[d] then
			table.insert(orderList, d)
		end
		counts[d] = (counts[d] or 0) + 1
	end
	local parts = {}
	for _, d in ipairs(orderList) do
		local n = counts[d]
		local name = IngredientData.Drinks[d].name[lang]
		if n == 1 then
			local article = "a "
			if lang == "de" then
				article = "ein "
			elseif string.find(string.lower(string.sub(name, 1, 1)), "[aeiou]") then
				article = "an "
			end
			table.insert(parts, article .. name)
		else
			table.insert(parts, NUM[lang][n] .. " " .. name)
		end
	end
	return joinList(parts, lang)
end

-- Full order speech as {de, en}
function DialogueConfig.OrderSpeech(order, personality, rng: Random)
	local style = rng:NextNumber() < 0.35 and "explicit" or "mods"
	local wrap = DialogueConfig.Line("order_wrap", personality, rng)
	local drinkWrap = DialogueConfig.Line("drink_wrap", personality, rng)
	local placeKey = order.items[1] and order.items[1].takeaway and "takeaway" or "plate"
	local placeLines = DialogueConfig.Lines.place[placeKey]
	local place = placeLines[rng:NextInteger(1, #placeLines)]
	local out = {}
	for _, lang in ipairs({ "de", "en" }) do
		local itemTexts = {}
		-- merge identical items ("zwei Kebap mit allem") is overkill; list each
		for _, it in ipairs(order.items) do
			table.insert(itemTexts, DialogueConfig.DescribeItem(it, lang, style))
		end
		local orderText = joinList(itemTexts, lang)
		local text = string.gsub(wrap[lang], "{order}", function()
			return orderText
		end)
		-- capitalise first letter
		text = string.upper(string.sub(text, 1, 1)) .. string.sub(text, 2)
		if #order.drinks > 0 then
			local dText = DialogueConfig.DescribeDrinks(order.drinks, lang)
			text ..= " " .. string.gsub(drinkWrap[lang], "{drinks}", function()
				return dText
			end)
		end
		text ..= " " .. place[lang]
		out[lang] = text
	end
	return out
end

return DialogueConfig
