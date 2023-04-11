futil.check_version({ year = 2023, month = 4, day = 2 })

random_spawn = fmod.create()

local f = string.format
local s = random_spawn.settings
local S = random_spawn.S

local mod_storage = minetest.get_mod_storage()

local ground_content_ids = {}
local non_walkable_content_ids = {}

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
		return
	end
	local player = minetest.get_player_by_name(player_name)
	if not player then
		return
	end
	player:set_pos(spawn_pos)
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
	if calls_remaining == 0 then
		-- if nothing is found, try again
		random_spawn.select_new_spawn(player_name)
	end
end

function random_spawn.select_new_spawn(player_name)
	local min_p, max_p = futil.get_world_bounds()
	local pos = vector.new(math.random(min_p.x, max_p.x), math.random(s.min_y, s.max_y), math.random(min_p.z, max_p.z))
	local bpos = futil.get_blockpos(pos)
	local b_min, b_max = futil.get_block_bounds(bpos)
	minetest.emerge_area(b_min, b_max, emerge_callback, {
		player_name = player_name,
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

if not minetest.registered_privileges["spawn"] then
	minetest.register_privilege("spawn", {
		description = S("spawn"),
		give_to_singleplayer = true,
		give_to_admin = true,
	})
end

minetest.register_chatcommand("spawn", {
	description = S("go to your spawn"),
	privs = { spawn = true },
	func = function(name)
		random_spawn.send_to_spawn(name)
	end,
})
