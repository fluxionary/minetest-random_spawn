# random_spawn

every new player gets their own unique spawn position.

### why

perhaps you want a multiplayer server where the players usually can't find each other easily. or perhaps you want
to be able to test out multiple randomly chosen parts of the map.

### important settings

this mod works by picking random parts of the map, generating them, and searching for a suitable spawn location.
two values, `y_min` and `y_max`, will bound the y coordinates of the block where a player's spawn may be chosen.
you must make sure that there are enough solid blocks at those levels w/ two non-solid blocks above them, or this
mod may cause significant lag! the default values ought to be good for most people.
