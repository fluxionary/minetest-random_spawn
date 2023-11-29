futil.check_version({ year = 2023, month = 4, day = 2 })

random_spawn = fmod.create()

local f = string.format
local s = random_spawn.settings
local S = random_spawn.S

local mod_storage = minetest.get_mod_storage()

local ground_content_ids = {}
local non_walkable_content_ids = {}

if not minetest.registered_privileges["spawn"] then
	minetest.register_privilege("spawn", {
		description = S("spawn"),
		give_to_singleplayer = true,
		give_to_admin = true,
	})
end

if not minetest.registered_privileges[s.admin_priv] then
	minetest.register_privilege(s.admin_priv, {
		description = S("spawn admin"),
		give_to_singleplayer = true,
		give_to_admin = true,
	})
end

minetest.register_on_mods_loaded(function()
	for name, def in pairs(minetest.registered_nodes) do
		if def.is_ground_content and def.walkable then
			ground_content_ids[minetest.get_content_id(name)] = true
		elseif not def.walkable then
			non_walkable_content_ids[minetest.get_content_id(name)] = true
		end
	end
end)

local function spawn_key(player_name)
	return f("spawn:%s", player_name)
end

function random_spawn.get_spawn(player_name)
	return minetest.string_to_pos(mod_storage:get_string(spawn_key(player_name)))
end

function random_spawn.set_spawn(player_name, pos)
	mod_storage:set_string(spawn_key(player_name), minetest.pos_to_string(pos))
end

function random_spawn.send_to_spawn(player_name)
	local spawn_pos = random_spawn.get_spawn(player_name)
	if not spawn_pos then
		return false
	end
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return false
	end
	player:set_pos(spawn_pos)
	return true
end

local function emerge_callback(blockpos, action, calls_remaining, param)
	local player_name = param.player_name
	if random_spawn.get_spawn(player_name) then
		-- player already has a spawn
		return
	elseif action == minetest.EMERGE_CANCELLED or action == minetest.EMERGE_ERRORED then
		random_spawn.select_new_spawn(player_name)
		return
	end
	local pmin, pmax = futil.get_block_bounds(blockpos)
	local vm = VoxelManip(pmin, pmax)
	local data = vm:get_data()
	local va = VoxelArea(pmin, pmax)
	for x = pmin.x, pmax.x do
		for z = pmin.z, pmax.z do
			for y = pmax.y - 2, pmin.y, -1 do
				local i_ground = va:index(x, y, z)
				local i_air1 = va:index(x, y + 1, z)
				local i_air2 = va:index(x, y + 2, z)
				if
					ground_content_ids[data[i_ground]]
					and non_walkable_content_ids[data[i_air1]]
					and non_walkable_content_ids[data[i_air2]]
				then
					random_spawn.set_spawn(player_name, vector.new(x, y + 1, z))
					random_spawn.send_to_spawn(player_name)
					return
				end
			end
		end
	end
	-- if nothing is found, try again
	random_spawn.select_new_spawn(player_name)
end

function random_spawn.select_new_spawn(player_name)
	mod_storage:set_string(spawn_key(player_name), "") -- reset any old spawn
	local min_p, max_p = futil.get_world_bounds()
	local pos
	while not pos do
		local x = math.random(min_p.x, max_p.x)
		local z = math.random(min_p.z, max_p.z)
		local y = minetest.get_spawn_level(x, z)
		if y then
			pos = vector.new(x, y, z)
		end
	end
	local bpos = futil.get_blockpos(pos)
	local b_min, b_max = futil.get_block_bounds(bpos)
	minetest.emerge_area(b_min, b_max, emerge_callback, {
		player_name = player_name,
	})
	-- the new spawn actually gets set in the emerge callback
end

minetest.register_on_joinplayer(function(player, last_login)
	local player_name = player:get_player_name()
	if not random_spawn.get_spawn(player_name) then
		random_spawn.select_new_spawn(player_name)
	end
end)

minetest.register_on_respawnplayer(function(player)
	local player_name = player:get_player_name()
	if random_spawn.get_spawn(player_name) then
		random_spawn.send_to_spawn(player_name)
		return true
	end
end)

minetest.register_chatcommand("spawn", {
	description = S("go to your spawn"),
	privs = { spawn = true },
	func = function(name)
		random_spawn.send_to_spawn(name)
	end,
})

minetest.register_chatcommand("select_new_spawn", {
	description = S("select a new spawn for a player"),
	params = "<player_name>",
	privs = { [s.admin_priv] = true },
	func = function(name, player_name)
		player_name = player_name:trim()
		if player_name == "" then
			return false, S("please provide a player name")
		end
		local cname = canonical_name.get(player_name)
		if not cname then
			return false, S("@1 is not a known player", player_name)
		end
		random_spawn.select_new_spawn(cname)
		return true, S("new spawn should be getting chosen...")
	end,
})

minetest.register_chatcommand("set_spawn", {
	description = S("set the spawn coordinates for a player. if none are provided, uses the caller's location."),
	params = "<player_name> [<x, y, z>]",
	privs = { [s.admin_priv] = true },
	func = function(name, param)
		local player_name, coords = unpack(param:trim():split("%s", false, 1, true))

		if not player_name then
			return false, S("please provide a player name")
		end

		local cname = canonical_name.get(player_name)
		if not cname then
			return false, S("@1 is not a known player", player_name)
		end

		local pos
		if coords then
			local x, y, z = coords:match("(-?%d+)[ ,]+(-?%d+)[ ,]+(-?%d+)")
			if not (x and y and z) then
				return false, S("can't parse coords '@1'", coords)
			end
			pos = vector.new(x, y, z)
		else
			local player = minetest.get_player_by_name(name)
			if not player then
				return false, S("you don't have any coordinates, probably because you're using the admin console.")
			end
			pos = player:get_pos()
			if not pos then
				return false, S("weirdly, you don't have a position.")
			end
		end

		random_spawn.set_spawn(player_name, pos)
		return true, S("@1's spawn set to @2", cname, minetest.pos_to_string(pos))
	end,
})
