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

local AbstractStepWindow = require("lua/apps/query/step/AbstractStepWindow")
local AbstractApp = require("lua/apps/AbstractApp")
local AbstractQuery = require("lua/query/AbstractQuery")
local EmptyGraphWindow = require("lua/apps/query/step/EmptyGraphWindow")
local ErrorOnInvalidRead = require("lua/containers/ErrorOnInvalidRead")
local FullGraphQuery = require("lua/query/FullGraphQuery")
local Stack = require("lua/containers/Stack")
local TemplateSelectWindow = require("lua/apps/query/step/TemplateSelectWindow")

local AppName
local Metatable

-- Application to build crafting hypergraphs from a Force's database.
--
-- Inherits from AbstractApp.
--
-- RO Fields:
-- * query: Query object being built and run.
-- * stepWindows: Stack of AbstractStepWindow objects (the top one is the only active).
--
local QueryApp = ErrorOnInvalidRead.new{
    -- Creates a new QueryApp object.
    --
    -- Args:
    -- * object: Table to turn into a QueryApp object.
    --
    -- Returns: The argument turned into a QueryApp object.
    --
    new = function(object)
        object.appName = AppName
        object.query = FullGraphQuery.new()

        AbstractApp.new(object, Metatable)

        object.stepWindows = Stack.new()
        object.stepWindows:push(TemplateSelectWindow.new{
            app = object,
        })

        return object
    end,

    -- Restores the metatable of a QueryApp object, and all its owned objects.
    --
    -- Args:
    -- * object: table to modify.
    --
    setmetatable = function(object)
        setmetatable(object, Metatable)
        AbstractQuery.Factory:restoreMetatable(object.query)

        local stack = object.stepWindows
        Stack.setmetatable(stack)
        for index=1,stack.topIndex do
            AbstractStepWindow.Factory:restoreMetatable(stack[index])
        end
    end,
}

-- Metatable of the QueryApp class.
Metatable = {
    __index = {
        -- Implements AbstractApp:close().
        close = function(self)
            local stack = self.stepWindows
            for index=stack.topIndex,1,-1 do
                stack[index]:close()
            end
        end,

        -- Implements AbstractApp:hide().
        hide = function(self)
            local stack = self.stepWindows
            stack[stack.topIndex]:close()
        end,

        -- Closes the top window, and shows the previous one.
        --
        -- Args:
        -- * self: QueryApp object.
        --
        popStepWindow = function(self)
            local window = self.stepWindows:pop()
            window:close()
            self:show()
        end,

        -- Hides the current window, and shows a new one.
        --
        -- Args:
        -- * self: QueryApp object.
        --
        pushStepWindow = function(self, newWindow)
            self:hide()
            self.stepWindows:push(newWindow)
            self:show()
        end,

        -- Runs the query, and switch to the Graph app.
        --
        -- Args:
        -- * self: QueryApp object.
        --
        runQueryAndDraw = function(self)
            local query = self.query
            local force = self.appResources.force
            local graph,vertexDists = query:execute(force)

            if next(graph.vertices) then
                self.appResources:makeAndSwitchApp{
                    appName = "graph",
                    graph = graph,
                    vertexDists = vertexDists,
                }
            else
                self:pushStepWindow(EmptyGraphWindow.new{
                    app = self,
                })
            end
        end,

        -- Implements AbstractApp:show().
        show = function(self)
            local stack = self.stepWindows
            local stepWindow = stack[stack.topIndex]
            if not rawget(stepWindow, "gui") then
                stepWindow:open(self.appResources.rawPlayer.gui.center)
            end
        end,
    },
}
setmetatable(Metatable.__index, {__index = AbstractApp.Metatable.__index})

-- Unique name for this application.
AppName = "query"

AbstractApp.Factory:registerClass(AppName, QueryApp)
return QueryApp
