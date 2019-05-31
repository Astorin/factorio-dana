-- This file is part of Dana.
-- Copyright (C) 2019 Vincent Saulue-Laborde <vincent_saulue@hotmail.fr>
--
-- Dana is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Dana is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with Dana.  If not, see <https://www.gnu.org/licenses/>.

local PrototypeDatabase = require("lua/PrototypeDatabase")
local Player = require("lua/Player")

-- Main class of this mod.
--
-- Singleton class.
--
-- Stored in global: yes.
--
-- Fields:
-- * players: map of Player objects, indexed by their Factorio index.
-- * prototypes: PrototypeDatabase wrapping all useful prototypes from Factorio.
--
local Main = {
    -- Function to call in Factorio's on_load event.
    on_load = nil, -- implemented later

    -- Function to call in Factorio's on_init event.
    on_init = nil, -- implemented later
}

-- Implementation stuff (private scope).
local Impl = {
    new = nil, -- implemented later.

    -- Restores the metatable of a Main instance, and all its owned objects.
    --
    -- Args:
    -- * object: table to modify.
    --
    setmetatable = function(object)
        PrototypeDatabase.setmetatable(object.prototypes)
        for _,player in pairs(object.players) do
            Player.setmetatable(player)
        end
    end
}

function Impl.new(gameScript)
    local result = {
        players = {},
        prototypes = PrototypeDatabase.new(gameScript),
    }
    for _,rawPlayer in pairs(game.players) do
        result.players[rawPlayer.index] = Player.new({
            prototypes = result.prototypes,
            rawPlayer = rawPlayer,
        })
    end
    return result
end

function Main.on_load()
    Impl.setmetatable(global.Main)
end

function Main.on_init()
    global.Main = Impl.new(game)
end

return Main
