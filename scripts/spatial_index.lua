local tools = require("scripts.tools")
local commons = require("scripts.commons")
local defs = require("scripts._defs")

local abs = math.abs
local spatial_index = {}

spatial_index.index_x = 1
spatial_index.index_y = 2

local index_x = spatial_index.index_x
local index_y = spatial_index.index_y

---@param node SpatialIndexLink
---@param indexable IndexableEntity
---@return SpatialIndexLink
local function add(node, indexable)
    if not node then
        return indexable
    elseif node.spatial_type == index_x then
        if indexable.position.x < node.value then
            node.left = add(node.left, indexable)
        else
            node.right = add(node.right, indexable)
        end
        return node
    elseif node.spatial_type == index_y then
        if indexable.position.y < node.value then
            node.left = add(node.left, indexable)
        else
            node.right = add(node.right, indexable)
        end
        return node
    else
        local node_indexable = node --[[@as IndexableEntity]]
        local indexable_position = indexable.position
        local node_position = node_indexable.position
        local x1, y1, x2, y2 = indexable_position.x, indexable_position.y,
            node_position.x, node_position.y
        local dx = abs(x1 - x2)
        local dy = abs(y1 - y2)
        if dx > dy then
            return {
                spatial_type = index_x,
                left = (x1 < x2) and indexable or node_indexable,
                right = (x1 < x2) and node_indexable or indexable,
                value = (x1 + x2) / 2
            }
        else
            return {
                spatial_type = index_y,
                left = (y1 < y2) and indexable or node_indexable,
                right = (y1 < y2) and node_indexable or indexable,
                value = (y1 + y2) / 2
            }
        end
    end
end

---@param node SpatialIndexLink
---@param indexable IndexableEntity
---@return SpatialIndexLink?
local function remove(node, indexable)
    local position = indexable.position
    if node.spatial_type == index_x then
        if position.x < node.value then
            local left = remove(node.left, indexable)
            if not left then
                return node.right
            else
                node.left = left
                return node
            end
        else
            local right = remove(node.right, indexable)
            if not right then
                return node.left
            else
                node.right = right
                return node
            end
        end
    elseif node.spatial_type == index_y then
        if position.y < node.value then
            local left = remove(node.left, indexable)
            if not left then
                return node.right
            else
                node.left = left
                return node
            end
        else
            local right = remove(node.right, indexable)
            if not right then
                return node.left
            else
                node.right = right
                return node
            end
        end
    elseif node == indexable then
        return nil
    else
        return indexable
    end
end

---@type integer
local temp_x
---@type integer
local temp_y
---@type (fun(r:IndexableEntity):IndexableEntity?,integer) | nil
local temp_notMatched

---@param node SpatialIndexLink
---@return IndexableEntity?
---@return integer
local function search(node)
    if not node then return nil, 0 end
    if node.spatial_type == index_x then
        if temp_x < node.value then
            local candidate, dist = search(node.left)
            if not candidate or node.value - temp_x < dist then
                return search(node.right)
            else
                return candidate, dist
            end
        else
            local candidate, dist = search(node.right)
            if not candidate or temp_x - node.value < dist then
                return search(node.left)
            else
                return candidate, dist
            end
        end
    elseif node.spatial_type == index_y then
        if temp_y < node.value then
            local candidate, dist = search(node.left)
            if not candidate or node.value - temp_y < dist then
                return search(node.right)
            else
                return candidate, dist
            end
        else
            local candidate, dist = search(node.right)
            if not candidate or temp_y - node.value < dist then
                return search(node.left)
            else
                return candidate, dist
            end
        end
    else
        if temp_notMatched then
            return
                temp_notMatched --[[@as fun(r:IndexableEntity):IndexableEntity?, integer]](node --[[@as IndexableEntity]])
        else
            return node --[[@as IndexableEntity]], 0
        end
    end
end

---comment
---@param indexables table<integer, IndexableEntity>
---@return SpatialIndexLink?
local function build(indexables)
    if not indexables then return nil end
    local n = table_size(indexables)
    if n == 1 then
        local _, r = next(indexables)
        return r
    end

    local xmin, ymin, xmax, ymax
    for _, indexable in pairs(indexables) do
        local position = indexable.position
        if not xmin then
            xmin, ymin = position.x, position.y
            xmax, ymax = xmin, ymin
        else
            if position.x < xmin then xmin = position.x end
            if position.y < ymin then ymin = position.y end
            if position.x > xmax then xmax = position.x end
            if position.y > ymax then ymax = position.y end
        end
    end

    if xmax - xmin > ymax - ymin then
        local middle = (xmin + xmax) / 2
        local set1 = {}
        local set2 = {}
        local limit1
        local limit2
        for _, indexable in pairs(indexables) do
            local value = indexable.position.x
            if indexable.position.x < middle then
                if not limit1 or limit1 < value then
                    limit1 = value
                end
                table.insert(set1, indexable)
            else
                if not limit2 or limit2 > value then
                    limit2 = value
                end
                table.insert(set2, indexable)
            end
        end
        local node1 = build(set1)
        local node2 = build(set2)

        ---@type SpatialIndexNode
        return {
            spatial_type = index_x,
            left = node1,
            right = node2,
            value = (limit1 + limit2) / 2
        }
    else
        local middle = (ymin + ymax) / 2
        local set1 = {}
        local set2 = {}
        local limit1
        local limit2
        for _, indexable in pairs(indexables) do
            local value = indexable.position.y
            if indexable.position.y < middle then
                if not limit1 or limit1 < value then
                    limit1 = value
                end
                table.insert(set1, indexable)
            else
                if not limit2 or limit2 > value then
                    limit2 = value
                end
                table.insert(set2, indexable)
            end
        end
        local node1 = build(set1)
        local node2 = build(set2)

        ---@type SpatialIndexNode
        return {
            spatial_type = index_y,
            left = node1,
            right = node2,
            value = (limit1 + limit2) / 2
        }
    end
end

---comment
---@param indexables table<integer, IndexableEntity>
---@param no_reload boolean ?
---@return SpatialIndexLink?
local function build_1(indexables, no_reload)
    if not indexables then return nil end
    local n = table_size(indexables)
    if n == 1 then
        local _, r = next(indexables)
        return r
    end

    if not no_reload then
        local dup = {}
        for _, index in pairs(indexables) do
            table.insert(dup, index)
        end
        indexables = dup
    end



    local xmin, ymin, xmax, ymax
    for _, indexable in pairs(indexables) do
        local position = indexable.position
        if not xmin then
            xmin, ymin = position.x, position.y
            xmax, ymax = xmin, ymin
        else
            if position.x < xmin then xmin = position.x end
            if position.y < ymin then ymin = position.y end
            if position.x > xmax then xmax = position.x end
            if position.y > ymax then ymax = position.y end
        end
    end

    if xmax - xmin > ymax - ymin then
        local set1 = {}
        local set2 = {}

        table.sort(indexables, function(i1, i2) return i1.position.x < i2.position.x end)

        local imiddle = math.floor(n / 2)
        while (indexables[imiddle].position.x == indexables[imiddle + 1].position.x
                and imiddle < n) do
            imiddle = imiddle + 1
        end
        local middle = (indexables[imiddle].position.x + indexables[imiddle + 1].position.x) / 2

        for _, indexable in pairs(indexables) do
            if indexable.position.x < middle then
                table.insert(set1, indexable)
            else
                table.insert(set2, indexable)
            end
        end
        local node1 = build_1(set1, true)
        local node2 = build_1(set2, true)

        ---@type SpatialIndexNode
        return {
            spatial_type = index_x,
            left = node1,
            right = node2,
            value = middle
        }
    else
        local set1 = {}
        local set2 = {}
        table.sort(indexables, function(i1, i2) return i1.position.y < i2.position.y end)

        local imiddle = math.ceil(n / 2)
        while (indexables[imiddle].position.y == indexables[imiddle + 1].position.y) do
            imiddle = imiddle + 1
        end
        local middle = (indexables[imiddle].position.y + indexables[imiddle + 1].position.y) / 2

        for _, indexable in pairs(indexables) do
            if indexable.position.y < middle then
                table.insert(set1, indexable)
            else
                table.insert(set2, indexable)
            end
        end
        local node1 = build_1(set1, true)
        local node2 = build_1(set2, true)

        ---@type SpatialIndexNode
        return {
            spatial_type = index_y,
            left = node1,
            right = node2,
            value = middle
        }
    end
end


---@param node SpatialIndexLink
---@param device IndexableEntity
---@return IndexableEntity
local function find_device(node, device)

    local position = device
    temp_x = position.x
    temp_y = position.y
    temp_notMatched = nil
    node = search(node)
    return node
end

---@param node SpatialIndexLink?
local function count_node(node)
    if not node then return 0 end

    if node.spatial_type then
        return count_node(node.left) + count_node(node.right)
    else
        return 1
    end
end

---@param network SurfaceNetwork
---@param name string
---@return integer
local function count(network, name)
    local indexes = network.production_indexes[name]
    if not indexes then return 0 end

    local n = 0
    for _, index in pairs(indexes) do n = n + count_node(index.node_index) end
    return n
end

---@param index SpatialIndexLink?
function spatial_index.dump(index, tab)
    if not tab then tab = 0 end
    if not index then return end
    local margin = string.rep("    ", 2 * tab)
    if index.spatial_type then
        log(margin .. "Node " .. index.spatial_type .. ", value=" ..
            tostring(index.value))
        spatial_index.dump(index.left, tab + 1)
        spatial_index.dump(index.right, tab + 1)
    else
        ---@type Device
        local device = index.device
        if device then
            log(margin .. "Device " .. device.position.x .. "," ..
                device.position.y .. ", " .. device.trainstop.backer_name)
        elseif index.position then
            log(margin .. "Indexable " .. index.position.x .. "," ..
                index.position.y)
        end
    end
end

spatial_index.add = add
spatial_index.remove = remove
spatial_index.build = build
spatial_index.find_device = find_device
spatial_index.count_node = count_node
spatial_index.count = count

return spatial_index
