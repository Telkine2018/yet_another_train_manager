
local yutils = require("scripts.yutils")
local defs = require("scripts._defs")


remote.add_interface("yet_another_train_manager", {

    ---@param train_id integer      -- train id
    ---@param controller_id integer
    ---@param isMain boolean        -- Main controller
    ---@return table<string, int>?
    register_transfert_controller = function(train_id, controller_id, isMain)

        local context = yutils.get_context()
        local train = context.trains[train_id]

        if not train then return nil end
        if not train.train.valid then return nil end

        local station = train.train.station
        if not station then return nil end

        local device = context.trainstop_map[station.unit_number]
        if not device then return nil end

        if isMain then
            device.main_controller = controller_id
        else
            if not device.secondary_controllers then
                device.secondary_controllers = {}
            end
            device.secondary_controllers[controller_id] = true
        end
        if train.delivery and train.state == defs.train_states.loading then
            local train_contents = yutils.get_train_content(train)
            local target_content = {}
            for name, count in pairs(train.delivery.content) do
                target_content[name] = (train_contents[name] or 0) + count
            end
            local item_map = yutils.content_to_item_map(target_content)
            return item_map
        end
        return nil
    end
})