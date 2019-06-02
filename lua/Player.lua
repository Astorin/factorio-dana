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

local DirectedHypergraph = require("lua/DirectedHypergraph")
local Gui = require("lua/Gui")
local GuiElement = require("lua/GuiElement")
local LayerLayout = require("lua/LayerLayout")

-- Class holding data associated to a player in this mod.
--
-- Stored in global: yes
--
-- Fields:
-- * rawPlayer: Associated LuaPlayer instance.
-- * graph: DirectedHypergraph currently displayed to this player.
--
-- RO properties:
-- * gui: rawPlayer.gui wrapped in a Gui object.
--
local Player = {
    new = nil, -- implemented later

    setmetatable = nil, -- implemented later
}

-- Implementation stuff (private scope).
local Impl = {
    -- Metatable of the Player class.
    Metatable = {
        __index = function(self, fieldName)
            local result = nil
            if fieldName == "gui" then
                result = Gui.new({rawGui = self.rawPlayer.gui})
            end
            return result
        end,
    },

    buildGraph = nil,

    -- Turns an entry from a PrototypeDatabase into a DirectedHypergraph edge.
    --
    -- Args:
    -- * entry: An entry from PrototypeDatabase (supported types: recipe, boiler)
    --
    -- Returns: the new edge.
    --
    makeEdge = function(entry)
        local result = {
            index = entry,
            inbound = {},
            outbound = {},
        }
        for _,ingredient in pairs(entry.ingredients) do
            table.insert(result.inbound, ingredient)
        end
        for _,product in pairs(entry.products) do
            table.insert(result.outbound, product)
        end
        return result
    end,

    initGui = nil, -- implemented later

    startCallbacks = {
        index = "startButton",
        on_click = function(self, event)
            self.window.rawElement.visible = not self.window.rawElement.visible
        end,
    },
}

GuiElement.newCallbacks(Impl.startCallbacks)

-- Creates a new Player object.
--
-- Args:
-- * object: table to turn into the Player object (must have a "rawPlayer" field).
--
function Player.new(object)
    setmetatable(object, Impl.Metatable)
    object.graph = DirectedHypergraph.new()
    Impl.buildGraph(object)
    Impl.initGui(object)
    return object
end

-- Restores the metatable of a Player instance, and all its owned objects.
--
-- Args:
-- * object: Table to modify.
--
function Player.setmetatable(object)
    setmetatable(object, Impl.Metatable)
    DirectedHypergraph.setmetatable(object.graph)
end

-- Initialize the "graph" field of a Player object.
--
-- Args:
-- * self: Player whose graph will be built.
--
function Impl.buildGraph(self)
    for _,recipe in pairs(self.prototypes.entries.recipe) do
        self.graph:addEdge(Impl.makeEdge(recipe))
    end
    for _,boiler in pairs(self.prototypes.entries.boiler) do
        self.graph:addEdge(Impl.makeEdge(boiler))
    end
end

-- Initialize the GUI of a player.
--
-- Args:
-- * player: Player whose GUI will be created.
--
function Impl.initGui(player)
    local window = player.gui.center:add({
        type = "frame",
        name = "mainWindow",
        caption = "Chains",
        visible = false,
    })
    player.gui.left:add({
        type = "button",
        name = "menuButton",
        caption = "Chains",
    },{
        callbacksIndex = Impl.startCallbacks.index,
        window = window,
    })
    local rawMaterials = {}
    for _,resource in pairs(player.prototypes.entries.resource) do
        for _,product in pairs(resource.products) do
            rawMaterials[product] = true
        end
    end
    for _,offshorePump in pairs(player.prototypes.entries["offshore-pump"]) do
        for _,product in pairs(offshorePump.products) do
            rawMaterials[product] = true
        end
    end
    local layout = LayerLayout.new(player.graph,rawMaterials)
    local layersFlow = window:add({
        direction = "vertical",
        type = "flow",
    })
    for _,layer in ipairs(layout.layers) do
        local layerFlow = layersFlow:add({
            direction = "horizontal",
            type = "flow",
        })
        for _,vertexIndex in ipairs(layer) do
            layerFlow:add({
                caption = vertexIndex.rawPrototype.name .. " | ",
                type = "label",
            })
        end
        layersFlow:add({
            caption = "------------------------------------------------",
            type = "label",
        })
    end
end

return Player
