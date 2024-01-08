local action_state = require("telescope.actions.state")
local action_utils = require("telescope.actions.utils")
local entry_display = require("telescope.pickers.entry_display")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local Path = require("plenary.path")
local conf = require("telescope.config").values
local harpoon = require("harpoon")
-- local utils = require("telescope.utils")
local function filter_empty_string(list)
    local next = {}
    for idx = 1, #list do
        if list[idx].value ~= "" then
            table.insert(next, list[idx])
        end
    end

    return next
end

local generate_new_finder = function(opts)
    opts = opts or {}
    return finders.new_table({
        results = filter_empty_string(harpoon:list(opts.name).items),
        entry_maker = function(entry)
            local filepath = entry.value
            -- print(vim.inspect(entry))

            local entry_items = {
                {
                    width = 2,
                    -- highlight = "TelescopeResultsIdentifier",
                },
                {
                    -- calculate exact width based on the `name` field
                    width = #entry.context.name,
                },
                { remaining = true },
            }

            local displayer_entries = {
                {
                    entry.context.icon,
                    "DevIconC",
                    -- highlight = "TelescopeResultsIdentifier",
                },
                {
                    entry.context.name,
                    "LspInfoList",
                },
                {
                    Path:new(filepath):make_relative(vim.loop.cwd())
                    .. ":"
                    .. entry.context.pos[1]
                    .. ":"
                    .. entry.context.pos[2],
                    "TeleScopeResultsIdentifier",
                },
            }

            local displayer = entry_display.create({
                separator = " ",
                items = entry_items,
            })

            local make_display = function(_)
                return displayer(displayer_entries)
            end
            return {
                value = entry,
                ordinal = filepath,
                display = make_display,
                lnum = entry.context.pos[1],
                -- row = entry.context.lnum,
                col = entry.context.pos[2],
                filename = entry.value,
            }
        end,
    })
end

local delete_harpoon_mark = function(prompt_bufnr)
    local confirmation =
        vim.fn.input(string.format("Delete current mark(s)? [y/n]: "))
    if
        string.len(confirmation) == 0
        or string.sub(string.lower(confirmation), 0, 1) ~= "y"
    then
        print(string.format("Didn't delete mark"))
        return
    end

    local selection = action_state.get_selected_entry()
    harpoon:list():remove(selection.value)

    local function get_selections()
        local results = {}
        action_utils.map_selections(prompt_bufnr, function(entry)
            table.insert(results, entry)
        end)
        return results
    end

    local selections = get_selections()
    for _, current_selection in ipairs(selections) do
        harpoon:list():remove(current_selection.value)
    end

    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:refresh(generate_new_finder(), { reset_prompt = true })
end

local move_mark_up = function(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    local length = harpoon:list():length()

    if selection.index == length then
        return
    end

    local mark_list = harpoon:list().items

    table.remove(mark_list, selection.index)
    table.insert(mark_list, selection.index + 1, selection.value)

    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:refresh(generate_new_finder(), { reset_prompt = true })
end

local move_mark_down = function(prompt_bufnr)
    local selection = action_state.get_selected_entry()
    if selection.index == 1 then
        return
    end
    local mark_list = harpoon:list().items
    table.remove(mark_list, selection.index)
    table.insert(mark_list, selection.index - 1, selection.value)
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:refresh(generate_new_finder(), { reset_prompt = true })
end

return function(opts)
    opts = opts or {}

    opts.dynamic_title = true
    pickers
        .new(opts, {
            dynamic_preview_title = true,
            finder = generate_new_finder(opts),
            sorter = conf.generic_sorter(opts),
            layout_strategy = "vertical",
            previewer = conf.grep_previewer(opts),
            attach_mappings = function(_, map)
                map("i", "<c-d>", delete_harpoon_mark)
                map("n", "<c-d>", delete_harpoon_mark)

                map("i", "<c-p>", move_mark_up)
                map("n", "<c-p>", move_mark_up)

                map("i", "<c-n>", move_mark_down)
                map("n", "<c-n>", move_mark_down)
                return true
            end,
        })
        :find()
end
