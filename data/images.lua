local commons = require("scripts.commons")

local prefix = commons.prefix
local png = commons.png

local declarations = {}

local sprite = {
    type = "sprite",
    name = prefix .. "_x1",
    filename = png("images/x1"),
    width = 64,
    height = 64
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_xstack",
    filename = png("images/x_stack"),
    width = 64,
    height = 64
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_xwagon",
    filename = png("images/x_wagon"),
    width = 64,
    height = 64
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_xtrain",
    filename = png("images/x_train"),
    width = 64,
    height = 64
}

table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_on_off",
    filename = png("images/on_off"),
    width = 40,
    height = 40
}

table.insert(declarations, sprite)

local sprite = {
    type = "sprite",
    name = prefix .. "_arrow",
    filename = png("images/arrow"),
    width = 16,
    height = 16
}

table.insert(declarations, sprite)

local sprite = {
    type = "sprite",
    name = prefix .. "_down",
    filename = png("images/down"),
    width = 16,
    height = 16
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_refresh_black",
    filename = png("images/refresh_black"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_refresh_white",
    filename = png("images/refresh_white"),
    width = 32,
    height = 32
}
table.insert(declarations, sprite)

for name, index in pairs(commons.colors) do
    sprite = {
        type = "sprite",
        name = prefix .. "_state_" .. index,
        filename = png("images/base_state"),
        width = 16,
        height = 16,
        tint = commons.color_def[index]
    }
    table.insert(declarations, sprite)
end

sprite = {
    type = "sprite",
    name = prefix .. "_any_stock",
    filename = png("images/trains/any_stock"),
    width = 16,
    height = 16
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "_teleport1",
    width = 64,
    height = 64,
    filename = png("images/teleportation1")
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = commons.locomotive_sprite,
    width = 64,
    height = 64,
    filename = png("images/trains/locomotive"),
    mipmap_count = 4,
    flags= {"icon"}
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = commons.cargo_wagon_sprite,
    width = 64,
    height = 64,
    filename = png("images/trains/cargo-wagon"),
    mipmap_count = 4,
    flags= {"icon"}
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = commons.fluid_wagon_sprite,
    width = 64,
    height = 64,
    filename = png("images/trains/fluid-wagon"),
    mipmap_count = 4,
    flags= {"icon"}
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = commons.revert_sprite,
    width = 16,
    height = 64,
    filename = png("images/revert"),
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = commons.direct_sprite,
    width = 16,
    height = 64,
    filename = png("images/direct"),
}
table.insert(declarations, sprite)

sprite = {
    type = "sprite",
    name = prefix .. "-delete",
    width = 64,
    height = 64,
    filename = png("images/delete"),
}
table.insert(declarations, sprite)


data:extend(declarations)
