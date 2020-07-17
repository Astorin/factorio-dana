-- This file is part of Dana.
-- Copyright (C) 2020 Vincent Saulue-Laborde <vincent_saulue@hotmail.fr>
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

local ClassLogger = require("lua/logger/ClassLogger")
local ErrorOnInvalidRead = require("lua/containers/ErrorOnInvalidRead")

local cLogger = ClassLogger.new{className = "PositionController"}

local Metatable

-- Class managing the position of the player between the game and the application's surface.
--
-- Private fields:
-- * previousCharacter: Character of the player before opening the app.
-- * previousControllerType: Controller of the player before opening the app.
-- * previousPosition: Position of the player on the previous surface.
-- * previousSurface: LuaSurface on which the player was before opening this app.
-- * rawPlayer: LuaPlayer object from Factorio.
-- * appSurface: LuaSurface that this application can use to draw.
--
local PositionController = ErrorOnInvalidRead.new{
    -- Creates a new PositionController object.
    --
    -- Args:
    -- * object: Table to turn into a PositionController object (required fields: rawPlayer, appSurface).
    --
    -- Returns: The argument turned into a PositionController object.
    --
    new = function(object)
        cLogger:assertField(object, "rawPlayer")
        cLogger:assertField(object, "appSurface")
        object.previousPosition = {0,0}
        setmetatable(object, Metatable)
        return object
    end,

    -- Restores the metatable of a PositionController object, and all its owned objects.
    --
    -- Args:
    -- * object: table to modify.
    --
    setmetatable = function(object)
        setmetatable(object, Metatable)
    end,
}

-- Metatable of the PositionController class.
Metatable = {
    __index = ErrorOnInvalidRead.new{
        -- Sets the player on the app surface.
        --
        -- If the GUI is opened, the player is teleported. Otherwise the position will be stored for
        -- the next time the GUI is opened.
        --
        -- Args:
        -- * self: PositionController object.
        -- * position: Position object (see Factorio API).
        --
        setPosition = function(self, position)
            if self.rawPlayer.surface == self.appSurface then
                self.rawPlayer.teleport(position)
            else
                self.previousPosition = position
            end
        end,

        -- Teleports the player to the app's surface, with "god" controller type.
        --
        -- His current position/surface/controller his saved to be restored later by :teleportBack().
        --
        -- Args:
        -- * self: PositionController object.
        --
        teleportToApp = function(self)
            cLogger:assert(self.rawPlayer.surface ~= self.appSurface, "Player is already on Dana's surface.")
            local targetPosition = self.previousPosition
            self.previousControllerType = self.rawPlayer.controller_type
            if self.previousControllerType == defines.controllers.character then
                self.previousCharacter = self.rawPlayer.character
            end
            self.previousPosition = self.rawPlayer.position
            self.previousSurface = self.rawPlayer.surface
            self.rawPlayer.set_controller{type = defines.controllers.god}
            self.rawPlayer.teleport(targetPosition, self.appSurface)
        end,

        -- Teleports the player back to its previous surface, and restores his controller.
        --
        -- Args:
        -- * self: PositionController object.
        --
        teleportBack = function(self)
            cLogger:assert(self.rawPlayer.surface == self.appSurface, "Player is not on Dana's surface.")

            local targetPosition = self.previousPosition
            self.previousPosition = self.rawPlayer.position
            self.rawPlayer.teleport(targetPosition, self.previousSurface)

            local newController = {
                type = self.previousControllerType,
            }
            if newController.type == defines.controllers.character then
                if self.previousCharacter.valid then
                    newController.character = self.previousCharacter
                else
                    newController.type = defines.controllers.ghost
                end
            end
            self.rawPlayer.set_controller(newController)

            self.previousSurface = nil
            self.previousControllerType = nil
            self.previousCharacter = nil
        end,
    }
}

return PositionController
