#define CLOSET_INSERT_END -1
#define CLOSET_INSERT_FAIL 0
#define CLOSET_INSERT_SUCCESS 1


/obj/structure/closet
	name = "closet"
	desc = "It's a basic storage unit."
	icon = 'icons/obj/structures/closet.dmi'
	icon_state = "closed"
	density = TRUE
	anchored = TRUE
	layer = BELOW_OBJ_LAYER
	hit_sound = 'sound/effects/metalhit.ogg'
	blocks_emissive = EMISSIVE_BLOCK_GENERIC
	max_integrity = 200
	coverage = 40
	soft_armor = list(MELEE = 20, BULLET = 10, LASER = 10, ENERGY = 0, BOMB = 10, BIO = 0, FIRE = 70, ACID = 60)
	resistance_flags = XENO_DAMAGEABLE
	var/drop_material = /obj/item/stack/sheet/metal
	var/icon_closed = "closed"
	var/icon_opened = "open"
	var/overlay_welded = "welded"
	var/opened = FALSE
	var/welded = FALSE
	var/locked = FALSE
	var/wall_mounted = FALSE //never solid (You can always pass over it)
	var/breakout_time = 2 MINUTES
	var/lastbang = FALSE
	var/closet_flags = NONE
	var/max_mob_size = MOB_SIZE_HUMAN //Biggest mob_size accepted by the container
	var/mob_storage_capacity = 1 // how many max_mob_size'd mob/living can fit together inside a closet.
	var/storage_capacity = 50 //This is so that someone can't pack hundreds of items in a locker/crate
							//then open it in a populated area to crash clients.
	var/mob_size_counter = 0
	var/item_size_counter = 0
	var/open_sound = 'sound/machines/click.ogg'
	var/close_sound = 'sound/machines/click.ogg'

	var/closet_stun_delay = 2 SECONDS



/obj/structure/closet/Initialize(mapload, ...)
	. = ..()
	RegisterSignal(src, COMSIG_MOVABLE_SHUTTLE_CRUSH, PROC_REF(shuttle_crush))
	return INITIALIZE_HINT_LATELOAD


/obj/structure/closet/LateInitialize(mapload)
	. = ..()
	if(mapload && !opened)		// if closed, any item at the crate's loc is put in the contents
		take_contents()
		update_icon()
	PopulateContents()


/obj/structure/closet/deconstruct(disassembled = TRUE)
	dump_contents()
	return ..()


//USE THIS TO FILL IT, NOT INITIALIZE OR NEW
/obj/structure/closet/proc/PopulateContents()
	return

/obj/structure/closet/proc/shuttle_crush()
	SIGNAL_HANDLER
	for(var/mob/living/L in contents)
		L.gib()
	for(var/atom/movable/AM in contents)
		qdel(AM)

/obj/structure/closet/open
	icon_state = "open"
	density = FALSE
	opened = TRUE


/obj/structure/closet/CanAllowThrough(atom/movable/mover, turf/target)
	. = ..()
	if(wall_mounted)
		return TRUE

/obj/structure/closet/proc/can_open(mob/living/user)
	if(welded || locked)
		if(user)
			to_chat(user, span_notice("It won't budge!"))
		return FALSE
	return TRUE


/obj/structure/closet/proc/can_close(mob/living/user)
	for(var/obj/structure/closet/closet in loc)
		if(closet != src && !closet.wall_mounted)
			if(user)
				to_chat(user, span_danger("There's more than one closet here, it's too cramped to close.") )
			return FALSE
	for(var/mob/living/mob_to_stuff in loc)
		if(mob_to_stuff.anchored || mob_to_stuff.mob_size > max_mob_size)
			if(user)
				to_chat(user, span_danger("[mob_to_stuff] is preventing [src] from closing."))
			return FALSE
	return TRUE


/obj/structure/closet/proc/dump_contents()
	var/atom/drop_loc = drop_location()
	for(var/thing in src)
		var/atom/movable/stuffed_thing = thing
		stuffed_thing.forceMove(drop_loc)
		SEND_SIGNAL(stuffed_thing, COMSIG_MOVABLE_CLOSET_DUMPED, src)
		if(throwing) // you keep some momentum when getting out of a thrown closet
			step(stuffed_thing, dir)
	mob_size_counter = 0
	item_size_counter = 0


/obj/structure/closet/proc/take_contents()
	for(var/mapped_thing in drop_location())
		if(mapped_thing == src)
			continue
		if(insert(mapped_thing) == CLOSET_INSERT_END) // limit reached
			break


/obj/structure/closet/proc/open(mob/living/user)
	if(opened || !can_open(user))
		return FALSE
	opened = TRUE
	density = FALSE
	dump_contents()
	update_icon()
	playsound(loc, open_sound, 15, 1)
	return TRUE


/obj/structure/closet/proc/insert(atom/movable/thing_to_insert)
	if(length(contents) >= storage_capacity)
		return CLOSET_INSERT_END
	if(!thing_to_insert.closet_insertion_allowed(src))
		return CLOSET_INSERT_FAIL
	thing_to_insert.forceMove(src)
	return CLOSET_INSERT_SUCCESS


/obj/structure/closet/proc/close(mob/living/user)
	if(!opened || !can_close(user))
		return FALSE
	take_contents()
	playsound(loc, close_sound, 15, 1)
	opened = FALSE
	density = TRUE
	update_icon()
	return TRUE


/obj/structure/closet/proc/toggle(mob/living/user)
	return opened ? close(user) : open(user)

/obj/structure/closet/ex_act(severity)
	var/dmg
	switch(severity)
		if(EXPLODE_DEVASTATE)
			contents_explosion(severity)
			dump_contents()
			qdel(src)
		if(EXPLODE_HEAVY)
			dmg = rand()
			if(!locked || dmg > 0.1)
				contents_explosion(severity)
				break_open()
				if(dmg > 0.5)
					qdel(src)
		if(EXPLODE_LIGHT)
			dmg = rand()
			if(!locked || dmg > 0.5)
				contents_explosion(severity)
				break_open()
				if(dmg > 0.95)
					qdel(src)

/obj/structure/closet/attack_animal(mob/living/user)
	if(user.wall_smash)
		visible_message(span_warning(" [user] destroys the [src]. "))
		dump_contents()
		qdel(src)

/obj/structure/closet/attack_alien(mob/living/carbon/xenomorph/X, damage_amount = X.xeno_caste.melee_damage, damage_type = BRUTE, damage_flag = "", effects = TRUE, armor_penetration = 0, isrightclick = FALSE)
	. = ..()
	if(!.)
		return
	if(X.a_intent == INTENT_HARM && !opened && prob(70))
		break_open()

/obj/structure/closet/attackby(obj/item/I, mob/user, params)
	if(user in src)
		return FALSE
	if(I.flags_item & ITEM_ABSTRACT)
		return FALSE
	. = ..()
	if(opened)
		if(istype(I, /obj/item/grab))
			var/obj/item/grab/G = I
			if(!G.grabbed_thing)
				CRASH("/obj/item/grab without a grabbed_thing in tool_interact()")
			MouseDrop_T(G.grabbed_thing, user)      //act like they were dragged onto the closet
			return
		if(.)
			return TRUE
		return user.transferItemToLoc(I, drop_location())

	var/obj/item/card/id/ID = user.get_idcard()
	if(istype(ID))
		if(!togglelock(user, TRUE))
			toggle(user)


/obj/structure/closet/welder_act(mob/living/user, obj/item/tool/weldingtool/welder)
	if(!welder.isOn())
		return FALSE

	if(opened)
		if(!welder.use_tool(src, user, 2 SECONDS, 1, 50))
			to_chat(user, span_notice("You need more welding fuel to complete this task."))
			return TRUE
		if(drop_material)
			new drop_material(drop_location())
		visible_message(span_notice("\The [src] has been cut apart by [user] with [welder]."), "You hear welding.")
		qdel(src)
		return TRUE

	if(!welder.use_tool(src, user, 2 SECONDS, 1, 50))
		to_chat(user, span_notice("You need more welding fuel to complete this task."))
		return TRUE
	welded = !welded
	update_icon()
	visible_message(span_warning("[src] has been [welded ? "welded shut" : "unwelded"] by [user.name]."), "You hear welding.")
	return TRUE


/obj/structure/closet/wrench_act(mob/living/user, obj/item/tool/wrench/wrenchy_tool)
	if(opened)
		return FALSE
	if(isspaceturf(loc) && !anchored)
		to_chat(user, span_warning("You need a firmer floor to wrench [src] down."))
		return TRUE
	setAnchored(!anchored)
	wrenchy_tool.play_tool_sound(src, 75)
	user.visible_message(span_notice("[user] [anchored ? "anchored" : "unanchored"] \the [src] [anchored ? "to" : "from"] the ground."), \
					span_notice("You [anchored ? "anchored" : "unanchored"] \the [src] [anchored ? "to" : "from"] the ground."), \
					span_italics("You hear a ratchet."))
	return TRUE


/obj/structure/closet/MouseDrop_T(atom/movable/O, mob/user)
	if(!isliving(user))
		return
	if(isxenohivemind(user))
		return
	if(!opened)
		return
	if(!isturf(O.loc))
		return
	if(user.incapacitated())
		return
	if(O.anchored || get_dist(user, src) > 1 || get_dist(user, O) > 1)
		return
	if(!isturf(user.loc))
		return
	if(ismob(O))
		var/mob/M = O
		if(M.buckled)
			return
	else if(!istype(O, /obj/item))
		return

	if(user == O)
		if(climbable)
			do_climb(user)
		return
	else
		step_towards(O, loc)
		user.visible_message(span_danger("[user] stuffs [O] into [src]!"))



/obj/structure/closet/relaymove(mob/user, direct)
	if(!isturf(loc))
		return
	if(user.incapacitated(TRUE))
		return
	if(!direct)
		return

	user.changeNext_move(5)

	if(!open())
		to_chat(user, span_notice("It won't budge!"))
		if(!lastbang)
			lastbang = TRUE
			for(var/mob/M in hearers(src, null))
				to_chat(M, text("<FONT size=[]>BANG, bang!</FONT>", max(0, 5 - get_dist(src, M))))
			addtimer(VARSET_CALLBACK(src, lastbang, FALSE), 3 SECONDS)


/obj/structure/closet/attack_hand(mob/living/user)
	. = ..()
	if(.)
		return
	return toggle(user)


/obj/structure/closet/verb/verb_toggleopen()
	set src in oview(1)
	set category = "Object"
	set name = "Toggle Open"

	if(!usr.canmove || usr.stat || usr.restrained())
		return

	if(ishuman(usr))
		src.toggle(usr)
	else
		to_chat(usr, span_warning("This mob type can't use this verb."))

/obj/structure/closet/update_icon()//Putting the welded stuff in updateicon() so it's easy to overwrite for special cases (Fridges, cabinets, and whatnot)
	overlays.Cut()
	if(!opened)
		icon_state = icon_closed
		if(welded)
			overlays += image(icon, overlay_welded)
	else
		icon_state = icon_opened


/obj/structure/closet/resisted_against(datum/source)
	container_resist(source)


/obj/structure/closet/proc/container_resist(mob/living/user)
	if(opened)
		return FALSE
	if(!welded && !locked)
		open()
		return FALSE
	if(user.do_actions) //Already resisting or doing something like it.
		return FALSE
	if(TIMER_COOLDOWN_CHECK(user, COOLDOWN_RESIST))
		return FALSE
	//okay, so the closet is either welded or locked... resist!!!
	user.changeNext_move(CLICK_CD_BREAKOUT)
	TIMER_COOLDOWN_START(user, COOLDOWN_RESIST, CLICK_CD_BREAKOUT)
	user.visible_message(span_warning("[src] begins to shake violently!"), \
		span_notice("You lean on the back of [src] and start pushing the door open... (this will take about [DisplayTimeText(breakout_time)].)"), \
		span_italics("You hear banging from [src]."))
	if(!do_after(user, breakout_time, target = src))
		if(!opened) //Didn't get opened in the meatime.
			to_chat(user, span_warning("You fail to break out of [src]!"))
		return FALSE
	if(opened || (!locked && !welded) ) //Did get opened in the meatime.
		return TRUE
	user.visible_message(span_danger("[user] successfully broke out of [src]!"),
		span_notice("You successfully break out of [src]!"))
	return bust_open()


/obj/structure/closet/proc/bust_open()
	welded = FALSE //applies to all lockers
	locked = FALSE //applies to critter crates and secure lockers only
	broken = TRUE //applies to secure lockers only
	open()


/obj/structure/closet/proc/break_open()
	if(!opened)
		dump_contents()
		opened = TRUE
		playsound(loc, open_sound, 15, 1) //Could use a more telltale sound for "being smashed open"
		density = FALSE
		welded = FALSE
		update_icon()


/obj/structure/closet/AltClick(mob/user)
	. = ..()
	return togglelock(user)


/obj/structure/closet/proc/togglelock(mob/living/user, silent)
	if(!CHECK_BITFIELD(closet_flags, CLOSET_IS_SECURE))
		return FALSE
	if(!user.dextrous)
		if(!silent)
			to_chat(user, span_warning("You don't have the dexterity to do this!"))
		return
	if(opened)
		if(!silent)
			to_chat(user, span_notice("Close \the [src] first."))
		return
	if(broken)
		if(!silent)
			to_chat(user, span_warning("\The [src] is broken!"))
		return FALSE

	if(!allowed(user))
		if(!silent)
			to_chat(user, span_notice("Access Denied"))
		return FALSE

	locked = !locked
	user.visible_message(span_notice("[user] [locked ? null : "un"]locks [src]."),
						span_notice("You [locked ? null : "un"]lock [src]."))
	update_icon()
	return TRUE


/obj/structure/closet/contents_explosion(severity)
	for(var/i in contents)
		var/atom/movable/closet_contents = i
		closet_contents.ex_act(severity)


/obj/structure/closet/proc/closet_special_handling(mob/living/mob_to_stuff)
	return TRUE //We are permisive by default.


//Redefined procs for closets

/atom/movable/proc/closet_insertion_allowed(obj/structure/closet/destination)
	return FALSE


/mob/living/closet_insertion_allowed(obj/structure/closet/destination)
	if(anchored || buckled)
		return FALSE
	if(mob_size + destination.mob_size_counter > destination.mob_storage_capacity * destination.max_mob_size)
		return FALSE
	if(!destination.closet_special_handling(src))
		return FALSE
	destination.mob_size_counter += mob_size
	stop_pulling()
	smokecloak_off()
	destination.RegisterSignal(src, COMSIG_LIVING_DO_RESIST, TYPE_PROC_REF(/atom/movable, resisted_against))
	RegisterSignal(src, COMSIG_MOVABLE_CLOSET_DUMPED, PROC_REF(on_closet_dump))
	return TRUE


/obj/closet_insertion_allowed(obj/structure/closet/destination)
	if(!CHECK_BITFIELD(destination.closet_flags, CLOSET_ALLOW_OBJS))
		return FALSE
	if(anchored)
		return FALSE
	if(!CHECK_BITFIELD(destination.closet_flags, CLOSET_ALLOW_DENSE_OBJ) && density)
		return FALSE
	return TRUE


/obj/item/closet_insertion_allowed(obj/structure/closet/destination)
	if(anchored)
		return FALSE
	if(!CHECK_BITFIELD(destination.closet_flags, CLOSET_ALLOW_DENSE_OBJ) && density)
		return FALSE
	if(CHECK_BITFIELD(flags_item, DELONDROP))
		return FALSE
	var/item_size = CEILING(w_class * 0.5, 1)
	if(item_size + destination.item_size_counter > destination.storage_capacity)
		return FALSE
	destination.item_size_counter += item_size
	return TRUE


/obj/structure/closet/closet_insertion_allowed(obj/structure/closet/destination)
	return FALSE


/mob/living/proc/on_closet_dump(datum/source, obj/structure/closet/origin)
	SIGNAL_HANDLER
	SetStun(origin.closet_stun_delay)//Action delay when going out of a closet
	if(!lying_angle && IsStun())
		visible_message(span_warning("[src] suddenly gets out of [origin]!"),
		span_warning("You get out of [origin] and get your bearings!"))
	origin.UnregisterSignal(src, COMSIG_LIVING_DO_RESIST)
	UnregisterSignal(src, COMSIG_MOVABLE_CLOSET_DUMPED)


#undef CLOSET_INSERT_END
#undef CLOSET_INSERT_FAIL
#undef CLOSET_INSERT_SUCCESS
