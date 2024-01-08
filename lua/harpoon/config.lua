local Extensions = require("harpoon.extensions")
local Logger = require("harpoon.logger")
local Path = require("plenary.path")

local M = {}
function M.normalize_path(buf_name, root)
    return Path:new(buf_name):make_relative(root)
end

local DEFAULT_LIST = "__harpoon_files"
M.DEFAULT_LIST = DEFAULT_LIST

---@alias HarpoonListItem {value: any, context: any}
---@alias HarpoonListFileItem {value: string, context: {row: number, col: number}}
---@alias HarpoonListFileOptions {split: boolean, vsplit: boolean, tabedit: boolean}

---@class HarpoonPartialConfigItem
---@field select_with_nil? boolean defaults to false
---@field encode? (fun(list_item: HarpoonListItem): string) | boolean
---@field decode? (fun(obj: string): any)
---@field display? (fun(list_item: HarpoonListItem): string)
---@field select? (fun(list_item?: HarpoonListItem, list: HarpoonList, options: any?): nil)
---@field equals? (fun(list_line_a: HarpoonListItem, list_line_b: HarpoonListItem): boolean)
---@field create_list_item? fun(config: HarpoonPartialConfigItem, item: any?): HarpoonListItem
---@field BufLeave? fun(evt: any, list: HarpoonList): nil
---@field VimLeavePre? fun(evt: any, list: HarpoonList): nil
---@field get_root_dir? fun(): string

---@class HarpoonSettings
---@field save_on_toggle boolean defaults to false
---@field sync_on_ui_close? boolean
---@field key (fun(): string)

---@class HarpoonPartialSettings
---@field save_on_toggle? boolean
---@field sync_on_ui_close? boolean
---@field key? (fun(): string)

---@class HarpoonConfig
---@field default HarpoonPartialConfigItem
---@field settings HarpoonSettings
---@field [string] HarpoonPartialConfigItem

---@class HarpoonPartialConfig
---@field default? HarpoonPartialConfigItem
---@field settings? HarpoonPartialSettings
---@field [string] HarpoonPartialConfigItem

---@return HarpoonPartialConfigItem
function M.get_config(config, name)
    return vim.tbl_extend("force", {}, config.default, config[name] or {})
end

--- An `init` function to build a set of children components for LSP breadcrumbs
---@param opts? table # options for configuring the breadcrumbs { separator = string, max_depth = number }
---@return string
local function breadcrumbs(opts, locations)
    opts = opts or {}
    opts.separator = opts.separator or ":"
    local data = locations
    local children = {}
    -- add prefix if needed, use the separator if true, or use the provided character
    local start_idx = 0

    if opts.max_depth and opts.max_depth > 0 then
        start_idx = #data - opts.max_depth
        -- if start_idx > 0 then
        --     table.insert(children, opts.separator)
        -- end
    end
    -- create a child for each level
    for i, d in ipairs(data) do
        if i > start_idx then
            local child = {
                -- string.gsub(d.name, "%%", "%%%%"):gsub("%s*->%s*", ""), -- add symbol name
                d.name
            }
            if #data > 1 and i < #data then
                table.insert(child, opts.separator)
            end -- add a separator only if needed
            table.insert(children, child)
        end
    end
    -- stringify all children
    local ret = ""
    for _, child in ipairs(children) do
        ret = ret .. table.concat(child)
    end
    return ret
end

---@return HarpoonConfig
function M.get_default_config()
    return {

        settings = {
            save_on_toggle = false,
            sync_on_ui_close = false,
            key = function()
                return vim.loop.cwd()
            end,
        },

        default = {

            --- select_with_nill allows for a list to call select even if the provided item is nil
            select_with_nil = false,

            ---@param obj HarpoonListItem
            ---@return string
            encode = function(obj)
                return vim.json.encode(obj)
            end,

            ---@param str string
            ---@return HarpoonListItem
            decode = function(str)
                return vim.json.decode(str)
            end,

            ---@param list_item HarpoonListItem
            display = function(list_item)
                return list_item.value
            end,

            --- the select function is called when a user selects an item from
            --- the corresponding list and can be nil if select_with_nil is true
            ---@param list_item? HarpoonListFileItem
            ---@param list HarpoonList
            ---@param options HarpoonListFileOptions
            select = function(list_item, list, options)
                Logger:log(
                    "config_default#select",
                    list_item,
                    list.name,
                    options
                )
                options = options or {}
                if list_item == nil then
                    return
                end

                local bufnr = vim.fn.bufnr(list_item.value)
                local set_position = false
                if bufnr == -1 then
                    set_position = true
                    bufnr = vim.fn.bufnr(list_item.value, true)
                end
                if not vim.api.nvim_buf_is_loaded(bufnr) then
                    vim.fn.bufload(bufnr)
                    vim.api.nvim_set_option_value("buflisted", true, {
                        buf = bufnr,
                    })
                end

                if options.vsplit then
                    vim.cmd("vsplit")
                elseif options.split then
                    vim.cmd("split")
                elseif options.tabedit then
                    vim.cmd("tabedit")
                end

                vim.api.nvim_set_current_buf(bufnr)

                if set_position then
                    vim.api.nvim_win_set_cursor(0, {
                        list_item.context.row or 1,
                        list_item.context.col or 0,
                    })
                end

                Extensions.extensions:emit(Extensions.event_names.NAVIGATE, {
                    buffer = bufnr,
                })
            end,

            ---@param list_item_a HarpoonListItem
            ---@param list_item_b HarpoonListItem
            equals = function(list_item_a, list_item_b)
                return list_item_a.value == list_item_b.value
                    and list_item_a.context.pos[1] == list_item_b.context.pos[1]
                    and list_item_a.context.pos[2]
                    == list_item_b.context.pos[2]
            end,

            get_root_dir = function()
                return vim.loop.cwd()
            end,

            ---@param config HarpoonPartialConfigItem
            ---@param name? any
            ---@return HarpoonListItem
            create_list_item = function(config, name)
                -- name = name
                --     -- TODO: should we do path normalization???
                --     -- i know i have seen sometimes it becoming an absolute
                --     -- path, if that is the case we can use the context to
                --     -- store the bufname and then have value be the normalized
                --     -- value
                --     or M.normalize_path(
                --         config.get_root_dir()
                --     )
                --

                -- local bufnr = vim.fn.bufnr(path, false)

                local abspath =
                    vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())

                Logger:log("config_default#create_list_item", abspath)
                local pos = vim.api.nvim_win_get_cursor(0)

                local aerial_avail, aerial = pcall(require, "aerial")
                if aerial_avail then
                    local locations = aerial.get_location(true)
                    -- Get the last location in the list
                    local cur_loc = locations[#locations]
                    cur_loc.pos = pos
                    cur_loc.name = breadcrumbs({},locations)
                    return {
                        value = abspath,
                        context = cur_loc,
                    }
                end

                -- local bufnr = vim.api.nvim_get_current_buf()
                -- name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
                -- if bufnr == -1 then
                --     error("Invalid buffer")
                -- end
                -- pos = vim.api.nvim_win_get_cursor(0)

                return {
                    value = name,
                    context = { pos },
                }
            end,

            BufLeave = function(arg, list)
                return
                -- local bufnr = arg.buf
                -- local bufname = vim.api.nvim_buf_get_name(bufnr)
                -- local item = list:get_by_display(bufname)
                --
                -- if item then
                --     local pos = vim.api.nvim_win_get_cursor(0)
                --
                --     Logger:log(
                --         "config_default#BufLeave updating position",
                --         bufnr,
                --         bufname,
                --         item,
                --         "to position",
                --         pos
                --     )
                --
                --     item.context.row = pos[1]
                --     item.context.col = pos[2]
                -- end
            end,

            -- autocmds = { "BufLeave" },
        },
    }
end

---@param partial_config HarpoonPartialConfig
---@param latest_config HarpoonConfig?
---@return HarpoonConfig
function M.merge_config(partial_config, latest_config)
    partial_config = partial_config or {}
    local config = latest_config or M.get_default_config()
    for k, v in pairs(partial_config) do
        if k == "settings" then
            config.settings = vim.tbl_extend("force", config.settings, v)
        elseif k == "default" then
            config.default = vim.tbl_extend("force", config.default, v)
        else
            config[k] = vim.tbl_extend("force", config[k] or {}, v)
        end
    end
    return config
end

return M
