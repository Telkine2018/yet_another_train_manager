local commons = require("scripts.commons")

local prefix = commons.prefix
local png = commons.png

local declarations = {}
local order = string.byte("a")

table.insert(declarations, {
    type = "item-subgroup",
    name = prefix .. "-signal",
    group = "signals",
    order = "f"
})

local function declare_signal(name)

    table.insert(declarations, {
        type = "virtual-signal",
        name = prefix .. "-" .. name,
        icon = png("signals/" .. name),
        icon_size = 64,
        icon_mipmaps = 4,
        subgroup = prefix .. "-signal",
        order = string.char(order)
    })
    order = order + 1
end

declare_signal("max_delivery")
declare_signal("network_mask")
declare_signal("priority")
declare_signal("delivery_timeout")
declare_signal("threshold")
declare_signal("locked_slots")
declare_signal("delivery_penalty")
declare_signal("loco_mask")
declare_signal("cargo_mask")
declare_signal("fluid_mask")
declare_signal("inactivity_delay")
declare_signal("builder_stop_create")
declare_signal("builder_stop_remove")
declare_signal("builder_remove_destroy")
declare_signal("operation")
declare_signal("identifier")
declare_signal("create_count")
declare_signal("train_count")
declare_signal("teleporter_range")
declare_signal("inactive")

data:extend(declarations)

