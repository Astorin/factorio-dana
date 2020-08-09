-- This file is part of Dana.
-- Copyright (C) 2019,2020 Vincent Saulue-Laborde <vincent_saulue@hotmail.fr>
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

local Array = require("lua/containers/Array")
local ClassLogger = require("lua/logger/ClassLogger")
local DirectedHypergraph = require("lua/hypergraph/DirectedHypergraph")
local DirectedHypergraphEdge = require("lua/hypergraph/DirectedHypergraphEdge")
local ErrorOnInvalidRead = require("lua/containers/ErrorOnInvalidRead")
local HyperPreprocessor = require("lua/layouts/preprocess/HyperPreprocessor")
local LayerCoordinateGenerator = require("lua/layouts/layer/coordinates/LayerCoordinateGenerator")
local LayerLinkBuilder = require("lua/layouts/layer/LayerLinkBuilder")
local Layers = require("lua/layouts/layer/Layers")
local LayersSorter = require("lua/layouts/layer/sorter/LayersSorter")
local PrepGraph = require("lua/layouts/preprocess/PrepGraph")
local PrepSCC = require("lua/layouts/preprocess/algorithms/PrepSCC")
local SlotsSorter = require("lua/layouts/layer/SlotsSorter")
local Stack = require("lua/containers/Stack")

local cLogger = ClassLogger.new{className = "LayerLayout"}

local assignToLayers
local makeSubgraphLeaves
local makeSubgraphWithDists
local placeInLayers
local Metatable

-- Computes a layer layout for an hypergraph.
--
-- Interesting doc: http://publications.lib.chalmers.se/records/fulltext/161388.pdf
--
-- RO properties:
-- * channelLayers: Array of ChannelLayer objects (1st channel layer is before the 1st entry layer).
-- * graph: input graph.
-- * layers: Layers object holding the computed layout.
-- * linkIndices: Set of LayerLinkIndex generated by this layout.
-- * vertexDists[vertexIndex] -> int: suggested partial order of vertices.
--
-- Methods: See Metatable.__index.
--
local LayerLayout = ErrorOnInvalidRead.new{
    -- Creates a new layer layout.
    --
    -- Args:
    -- * object: Table to turn into a LayerLayout object (mandatory fields: 'graph' & 'vertexDists')
    --
    -- Returns: The argument turned into a LayerLayout object.
    --
    new = function(object)
        local graph = cLogger:assertField(object, "graph")
        local vertexDists = cLogger:assertField(object, "vertexDists")

        local prepGraph, prepDists = HyperPreprocessor.run(graph, vertexDists)
        object.prepGraph = prepGraph
        object.prepDists = prepDists
        object.layers = Layers.new()
        object.linkIndices = {}

        -- 1) Assign nodes to layers & add dummy linkNodes.
        assignToLayers(object)
        LayerLinkBuilder.run(object)

        -- 2) Order nodes within their layers (link crossing minimization).
        LayersSorter.run(object.layers)

        -- 3) Channel layers (= connection layers between node layers).
        local channelLayers = object.layers:generateChannelLayers()

        -- 4) Build the new LayerLayout object.
        object.channelLayers = channelLayers
        setmetatable(object, Metatable)

        -- 5) Bonus: Little things to make the result slightly less incomprehensible
        SlotsSorter.run(object)

        return object
    end
}

-- Metatable of the LayerLayout class.
Metatable = {
    __index = ErrorOnInvalidRead.new{
        -- Computes the final X/Y coordinates according to the given parameters.
        --
        -- Args:
        -- * self: LayerLayout object.
        -- * parameters: LayoutParameter object.
        --
        computeCoordinates = LayerCoordinateGenerator.run,
    },
}

-- Splits nodes of the input graph into multiple layers.
--
-- This function does NOT order the layers themselves.
--
-- Args:
-- * self: LayerLayout object.
--
assignToLayers = function(self)
    local layers = self.layers
    local prepGraph = self.prepGraph
    local nodeOrder = self.prepDists

    local order = Array.new()

    -- 1) Assign using the topological order of SCCs in the input graph.
    local sccs = PrepSCC.run(prepGraph).components
    for index=sccs.count,1,-1 do
        local scc = sccs[index]
        -- 2) For each SCC sugraph, use nodeOrder to select & remove some "feedback" edges.
        local subgraph = makeSubgraphWithDists(prepGraph, scc, nodeOrder)
        -- 3) Refine the ordering using the topological order on this subgraph.
        local sccs2 = PrepSCC.run(subgraph).components
        for index2=sccs2.count,1,-1 do
            order:pushBack(sccs2[index2])
        end
    end

    -- 4) Place by PrepNode.orderPriority.
    local nodeToLayer = {}
    local firstPass = Stack.new()
    local secondPass = Stack.new()
    for index=1,order.count do
        local scc = order[index]
        for nodeIndex in pairs(scc) do
            local node = prepGraph.nodes[nodeIndex]
            if node.orderPriority == 1 then
                firstPass:push(nodeIndex)
            else
                secondPass:push(nodeIndex)
            end
        end
        local minLayerId = placeInLayers(self, nodeToLayer, firstPass, 1)
        placeInLayers(self, nodeToLayer, secondPass, minLayerId)
    end
end

-- Place a set of PrepNodeIndex into a Layers object.
--
-- Args:
-- * self: LayerLayout object.
-- * nodeToLayer[nodeIndex] -> int. Map giving the layer index of a node (edited by this function).
-- * nodeIndices: Stack of PrepNodeIndex to place (cleared by this function).
-- * minLayerId: Minimum layer index where the nodes should be placed.
--
placeInLayers = function(self, nodeToLayer, nodeIndices, minLayerId)
    local layers = self.layers
    local links = self.prepGraph.links
    local nodes = self.prepGraph.nodes

    local layerId = minLayerId
    for i=1,nodeIndices.topIndex do
        local nodeIndex = nodeIndices[i]
        local node = nodes[nodeIndex]
        for linkIndex in pairs(node.inboundSlots) do
            local leaves = links[linkIndex]
            if linkIndex.isFromRoot then
                layerId = math.max(layerId, 1 + (nodeToLayer[linkIndex.rootNodeIndex] or 0))
            else
                for neighbourIndex in pairs(leaves) do
                    layerId = math.max(layerId, 1 + (nodeToLayer[neighbourIndex] or 0))
                end
            end
        end
        for i=1,nodeIndices.topIndex do
            local nodeIndex = nodeIndices[i]
            local node = nodes[nodeIndex]
            layers:newEntry(layerId, {
                type = "node",
                index = nodeIndex,
            })
            nodeToLayer[nodeIndex] = layerId
        end
        nodeIndices.topIndex = 0
    end

    return layerId
end

-- Makes the set of leaves of a link in a subgraph.
--
-- Args:
-- * linkIndex: LinkIndex of the link.
-- * leaves: Set of leave from the parent graph.
-- * nodeIndices: Set of PrepNodeIndex of the subgraph.
-- * nodeOrder[nodeIndex] -> int. Suggested partial order of nodes, used to edit the links.
--
-- Returns: The new set of leaves for the subgraph.
--
makeSubgraphLeaves = function(linkIndex, leaves, nodeIndices, nodeOrder)
    local rootRank = nodeOrder[linkIndex.rootNodeIndex]
    local result = {}
    if linkIndex.isFromRoot then
        for nodeIndex in pairs(leaves) do
            if nodeIndices[nodeIndex] and nodeOrder[nodeIndex] >= rootRank then
                result[nodeIndex] = true
            end
        end
    else
        for nodeIndex in pairs(leaves) do
            if nodeIndices[nodeIndex] and nodeOrder[nodeIndex] <= rootRank then
                result[nodeIndex] = true
            end
        end
    end
    return result
end

-- Makes a subgraph, editing edges that don't follow a given partial order on the nodes.
--
-- An link L in the subgraph is modified such that: max(L.inbound) <= min(L.outbound). This is done by
-- removing any leaf in the node that breaks the constraint.
--
-- Args:
-- * graph: Input PrepGraph.
-- * nodeIndices: Set of PrepNodeIndex of the ndoes to include in the subgraph.
-- * nodeOrder[nodeIndex] -> int. Suggested partial order of nodes, used to edit the links.
--
-- Returns: The generated DirectedHypergraph.
--
makeSubgraphWithDists = function(graph, nodeIndices, nodeOrder)
    local result = PrepGraph.new()
    for nodeIndex,node in pairs(nodeIndices) do
        result:newNode(nodeIndex)
    end
    for nodeIndex,node in pairs(nodeIndices) do
        for linkIndex in pairs(node.inboundSlots) do
            if linkIndex.rootNodeIndex == nodeIndex then
                local newLeaves = makeSubgraphLeaves(linkIndex, graph.links[linkIndex], nodeIndices, nodeOrder)
                if next(newLeaves) then
                    result:addLink(linkIndex, newLeaves)
                end
            end
        end
        for linkIndex in pairs(node.outboundSlots) do
            if linkIndex.rootNodeIndex == nodeIndex then
                local newLeaves = makeSubgraphLeaves(linkIndex, graph.links[linkIndex], nodeIndices, nodeOrder)
                if next(newLeaves) then
                    result:addLink(linkIndex, newLeaves)
                end
            end
        end
    end

    return result
end

return LayerLayout
