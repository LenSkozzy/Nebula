/datum/trader
	var/name = "unsuspicious trader"                            //The name of the trader in question
	var/origin = "some place"                                   //The place that they are trading from
	var/list/possible_origins                                   //Possible names of the trader origin
	var/disposition = 0                                         //The current disposition of them to us.
	var/trade_flags = TRADER_MONEY                              //Flags
	var/name_language                                           //If this is set to a language name this will generate a name from the language
	var/icon/portrait                                           //The icon that shows up in the menu TODO: IMPLEMENT OR REMOVE
	var/trader_currency
	var/datum/trade_hub/hub

	var/list/wanted_items = list()                              //What items they enjoy trading for. Structure is (type = known/unknown)
	var/list/possible_wanted_items                              //List of all possible wanted items. Structure is (type = mode)
	var/list/possible_trading_items                             //List of all possible trading items. Structure is (type = mode)
	var/list/trading_items = list()                             //What items they are currently trading away.
	var/list/blacklisted_trade_items = list(/mob/living/carbon/human)
	                                                            //Things they will automatically refuse

	var/list/speech = list()                                    //The list of all their replies and messages. Structure is (id = talk)
	/*SPEECH IDS:
	hail_generic		When merchants hail a person
	hail_[race]			Race specific hails
	hail_deny			When merchant denies a hail

	insult_good			When the player insults a merchant while they are on good disposition
	insult_bad			When a player insults a merchatn when they are not on good disposition
	complement_accept	When the merchant accepts a complement
	complement_deny		When the merchant refuses a complement

	how_much			When a merchant tells the player how much something is.
	trade_complete		When a trade is made
	trade_refuse		When a trade is refused

	what_want			What the person says when they are asked if they want something

	*/
	var/want_multiplier = 2                                     //How much wanted items are multiplied by when traded for
	var/margin = 1.2											//Multiplier to price when selling to player
	var/price_rng = 10                                          //Percentage max variance in sell prices.
	var/insult_drop = 5                                         //How far disposition drops on insult
	var/compliment_increase = 5                                 //How far compliments increase disposition
	var/refuse_comms = 0                                        //Whether they refuse further communication

	var/mob_transfer_message = "You are transported to ORIGIN." //What message gets sent to mobs that get sold.

	var/static/list/blacklisted_types = list(
		/obj,
		/obj/structure,
		/obj/machinery,
		/obj/screen,
		/obj/effect,
		/obj/item,
		/obj/item/twohanded,
		/obj/item/organ,
		/obj/item/organ/internal,
		/obj/item/organ/external,
		/obj/item/storage,
		/obj/item/storage/internal,
		/obj/item/chems,
		/obj/item/chems/glass,
		/obj/item/chems/food,
		/obj/item/chems/food/old,
		/obj/item/chems/food/grown,
		/obj/item/chems/food/variable,
		/obj/item/chems/condiment,
		/obj/item/chems/drinks,
		/obj/item/chems/drinks/bottle
	)

/datum/trader/New()
	..()
	if(!ispath(trader_currency, /decl/currency))
		trader_currency = global.using_map.default_currency
	if(name_language)
		if(name_language == TRADER_DEFAULT_NAME)
			name = capitalize(pick(global.first_names_female + global.first_names_male)) + " " + capitalize(pick(global.last_names))
		else
			var/decl/language/L = GET_DECL(name_language)
			if(istype(L))
				name = L.get_random_name(pick(MALE,FEMALE))
	if(possible_origins && possible_origins.len)
		origin = pick(possible_origins)

	for(var/i in 3 to 6)
		add_to_pool(trading_items, possible_trading_items, force = 1)
		add_to_pool(wanted_items, possible_wanted_items, force = 1)

//If this hits 0 then they decide to up and leave.
/datum/trader/proc/tick()
	add_to_pool(trading_items, possible_trading_items, 200)
	add_to_pool(wanted_items, possible_wanted_items, 50)
	remove_from_pool(possible_trading_items, 9) //We want the stock to change every so often, so we make it so that they have roughly 10~11 ish items max
	return 1

/datum/trader/proc/remove_from_pool(var/list/pool, var/chance_per_item)
	if(pool && prob(chance_per_item * pool.len))
		var/i = rand(1,pool.len)
		pool[pool[i]] = null
		pool -= pool[i]

/datum/trader/proc/add_to_pool(var/list/pool, var/list/possible, var/base_chance = 100, var/force = 0)
	var/divisor = 1
	if(pool && pool.len)
		divisor = pool.len
	if(force || prob(base_chance/divisor))
		var/new_item = get_possible_item(possible)
		if(new_item)
			pool |= new_item

/datum/trader/proc/get_possible_item(var/list/trading_pool)
	if(!trading_pool || !trading_pool.len)
		return
	var/list/possible = list()
	for(var/type in trading_pool)
		var/status = trading_pool[type]
		if(status & TRADER_THIS_TYPE)
			possible += type
		if(status & TRADER_SUBTYPES_ONLY)
			possible += subtypesof(type)
		if(status & TRADER_BLACKLIST)
			possible -= type
		if(status & TRADER_BLACKLIST_SUB)
			possible -= subtypesof(type)

	if(length(possible))
		var/picked = pick_n_take(possible)
		while(length(possible) && (picked in blacklisted_types))
			picked = pick_n_take(possible)
		if(!(picked in blacklisted_types))
			return picked

/datum/trader/proc/get_response(var/key, var/default)
	if(speech && speech[key])
		. = speech[key]
	else
		. = default
	. = replacetext(., "MERCHANT", name)
	. = replacetext(., "ORIGIN", origin)

	var/decl/currency/cur = GET_DECL(trader_currency)
	. = replacetext(.,"CURRENCY_SINGULAR", cur.name_singular)
	. = replacetext(.,"CURRENCY", cur.name)

/datum/trader/proc/print_trading_items(var/num)
	num = clamp(num,1,trading_items.len)
	var/item_type = trading_items[num]
	if(!item_type)
		return
	. = atom_info_repository.get_name_for(item_type)
	if(ispath(item_type, /obj/item/stack))
		var/obj/item/stack/stack = item_type
		. = "[initial(stack.amount)]x [.]"
	. = "<b>[.]</b>"

/datum/trader/proc/skill_curve(skill)
	switch(skill)
		if(SKILL_EXPERT)
			. = 1
		if(SKILL_EXPERT to SKILL_MAX)
			. = 1 + (SKILL_EXPERT - skill) * 0.2
		else
			. = 1 + (SKILL_EXPERT - skill) ** 2
	//This condition ensures that the buy price is higher than the sell price on generic goods, i.e. the merchant can't be exploited
	. = max(., price_rng/((margin - 1)*(200 - price_rng)))

/datum/trader/proc/get_item_value(var/trading_num, skill = SKILL_MAX)
	if(!trading_items[trading_items[trading_num]])
		var/item_type = trading_items[trading_num]
		var/value = atom_info_repository.get_combined_worth_for(item_type)
		value = round(rand(100 - price_rng,100 + price_rng)/100 * value) //For some reason rand doesn't like decimals.
		trading_items[item_type] = value
	. = trading_items[trading_items[trading_num]]
	. *= 1 + (margin - 1) * skill_curve(skill) //Trader will overcharge at lower skill.
	. = max(1, round(.))

/datum/trader/proc/get_buy_price(var/atom/movable/item, is_wanted, skill = SKILL_MAX)
	if(ispath(item, /atom/movable))
		. = atom_info_repository.get_combined_worth_for(item)
	else if(istype(item))
		. = item.get_combined_monetary_worth()
	if(is_wanted)
		. *= want_multiplier
	. *= max(1 - (margin - 1) * skill_curve(skill), 0.1) //Trader will underpay at lower skill.
	. = max(1, round(.))

/datum/trader/proc/offer_money_for_trade(var/trade_num, var/money_amount, skill = SKILL_MAX)
	if(!(trade_flags & TRADER_MONEY))
		return TRADER_NO_MONEY
	var/value = get_item_value(trade_num, skill)
	if(money_amount < value)
		return TRADER_NOT_ENOUGH
	return value

/datum/trader/proc/offer_items_for_trade(var/list/offers, var/num, var/turf/location, skill = SKILL_MAX)
	if(!offers || !offers.len)
		return TRADER_NOT_ENOUGH
	num = clamp(num, 1, trading_items.len)
	var/offer_worth = 0
	for(var/item in offers)
		var/atom/movable/offer = item
		var/is_wanted = 0
		if((trade_flags & TRADER_WANTED_ONLY) && is_type_in_list(offer,wanted_items))
			is_wanted = 2
		if((trade_flags & TRADER_WANTED_ALL) && is_type_in_list(offer,possible_wanted_items))
			is_wanted = 1
		if(blacklisted_trade_items && blacklisted_trade_items.len && is_type_in_list(offer,blacklisted_trade_items))
			return 0

		if(istype(offer,/obj/item/cash))
			if(!(trade_flags & TRADER_MONEY))
				return TRADER_NO_MONEY
		else
			if(!(trade_flags & TRADER_GOODS))
				return TRADER_NO_GOODS
			else if((trade_flags & TRADER_WANTED_ONLY|TRADER_WANTED_ALL) && !is_wanted)
				return TRADER_FOUND_UNWANTED

		offer_worth += get_buy_price(offer, is_wanted - 1, skill)
	if(!offer_worth)
		return TRADER_NOT_ENOUGH
	var/trading_worth = get_item_value(num, skill)
	if(!trading_worth)
		return TRADER_NOT_ENOUGH
	var/percent = offer_worth/trading_worth
	if(percent > max(0.9,0.9-disposition/100))
		return trade(offers, num, location)
	return TRADER_NOT_ENOUGH

/datum/trader/proc/hail(var/mob/user)
	var/specific
	if(istype(user, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = user
		if(H.species)
			specific = H.species.name
	else if(istype(user, /mob/living/silicon))
		specific = "silicon"
	if(!speech["hail_[specific]"])
		specific = "generic"
	. = get_response("hail_[specific]", "Greetings, MOB!")
	. = replacetext(., "MOB", user.name)

/datum/trader/proc/can_hail()
	if(!refuse_comms && prob(-disposition))
		refuse_comms = 1
	return !refuse_comms

/datum/trader/proc/insult()
	disposition -= rand(insult_drop, insult_drop * 2)
	if(prob(-disposition/10))
		refuse_comms = 1
	if(disposition > 50)
		return get_response("insult_good","What? I thought we were cool!")
	else
		return get_response("insult_bad", "Right back at you asshole!")

/datum/trader/proc/compliment()
	if(prob(-disposition))
		return get_response("compliment_deny", "Fuck you!")
	if(prob(100-disposition))
		disposition += rand(compliment_increase, compliment_increase * 2)
	return get_response("compliment_accept", "Thank you!")

/datum/trader/proc/trade(var/list/offers, var/num, var/turf/location)
	if(offers && offers.len)
		for(var/offer in offers)
			if(istype(offer,/mob))
				var/text = mob_transfer_message
				to_chat(offer, replacetext(text, "ORIGIN", origin))
			qdel(offer)

	var/type = trading_items[num]

	var/atom/movable/M = new type(location)
	playsound(location, 'sound/effects/teleport.ogg', 50, 1)

	disposition += rand(compliment_increase,compliment_increase*3) //Traders like it when you trade with them

	return M

/datum/trader/proc/how_much_do_you_want(var/num, skill = SKILL_MAX)
	. = get_response("how_much", "Hmm.... how about VALUE CURRENCY?")
	. = replacetext(.,"VALUE",get_item_value(num, skill))
	. = replacetext(.,"ITEM", atom_info_repository.get_name_for(trading_items[num]))

/datum/trader/proc/what_do_you_want()
	if(!(trade_flags & TRADER_GOODS))
		return get_response(TRADER_NO_GOODS, "I don't deal in goods.")
	. = get_response("what_want", "Hm, I want")
	var/list/want_english = list()
	for(var/wtype in wanted_items)
		var/item_name = atom_info_repository.get_name_for(wtype)
		want_english += item_name
	. += " [english_list(want_english)]"

/datum/trader/proc/sell_items(var/list/offers, skill = SKILL_MAX)
	if(!(trade_flags & TRADER_GOODS))
		return TRADER_NO_GOODS
	if(!offers || !offers.len)
		return TRADER_NOT_ENOUGH

	var/wanted
	. = 0
	for(var/offer in offers)
		if((trade_flags & TRADER_WANTED_ONLY) && is_type_in_list(offer,wanted_items))
			wanted = 1
		else if((trade_flags & TRADER_WANTED_ALL) && is_type_in_list(offer,possible_wanted_items))
			wanted = 0
		else
			return TRADER_FOUND_UNWANTED
		. += get_buy_price(offer, wanted, skill)

	playsound(get_turf(offers[1]), 'sound/effects/teleport.ogg', 50, 1)
	for(var/offer in offers)
		qdel(offer)

/datum/trader/proc/bribe_to_stay_longer(var/amt)
	return get_response("bribe_refusal", "How about... no?")

/datum/trader/Destroy(force)
	if(hub)
		hub.traders -= src
	. = ..()
