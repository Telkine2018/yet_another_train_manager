
---@class XDevice
---@field id integer
---@field out_red integer
---@field out_green integer
---@field in_red integer
---@field in_green integer
---@field train integer
---@field dconfig DeviceConfig
XDevice = {}

---@class XTrain
---@field id integer
---@field depot integer
---@field refueler integer
XTrain = {}


---@class XContext
---@field delivery_id integer
---@field event_id integer
---@field config_id integer
XContext = {}

local xdef = {}

return xdef