-- this is (the) shit (we are balling)

local mod = SMODS.current_mod

mod.config = mod.config or {
    reset_after_each_hand = false,
}

local old_create_UIBox_HUD = create_UIBox_HUD
local old_get_poker_hand_info = G.FUNCS.get_poker_hand_info

local remembered_hand_choices = {}

local function copy_card_list(cards)
    local copied = {}
    for i, card in ipairs(cards or {}) do
        copied[i] = card
    end
    return copied
end

local function in_active_run()
    return G
        and G.STATES
        and G.STATE
        and G.STATE ~= G.STATES.MENU
        and G.GAME
        and G.GAME.current_round
        and G.GAME.current_round.current_hand
end

mod.config_tab = function()
    local toggle = create_toggle({
        label = "Reset after each hand",
        ref_table = mod.config,
        ref_value = "reset_after_each_hand",
        callback = function()
            if mod.config.reset_after_each_hand then
                remembered_hand_choices = {}
            end
        end
    })

    if in_active_run() then
        toggle = {
            n = G.UIT.C,
            config = {
                align = "cm",
                colour = G.C.UI.BACKGROUND_INACTIVE,
                r = 0.1,
                padding = 0.08
            },
            nodes = { toggle }
        }
    end

    return {
        n = G.UIT.ROOT,
        config = { align = "cm", padding = 0.1, colour = G.C.CLEAR },
        nodes = {
            {
                n = G.UIT.R,
                config = { align = "cm", padding = 0.2 },
                nodes = { toggle }
            }
        }
    }
end

local function find_node_by_id(node, target_id)
    if type(node) ~= "table" then return nil end

    if node.config and node.config.id == target_id then
        return node
    end

    if node.nodes then
        for _, child in ipairs(node.nodes) do
            local found = find_node_by_id(child, target_id)
            if found then
                return found
            end
        end
    end

    return nil
end

local function get_available_poker_hands(cards)
    local results = evaluate_poker_hand(cards or {})
    local buttons = {}

    for hand_name, hand_entries in pairs(results) do
        if hand_entries and next(hand_entries) then
            buttons[#buttons + 1] = {
                hand_name = hand_name,
                scoring_hand = hand_entries[1],
                all_hands = results,
            }
        end
    end

    return buttons, results
end

local function build_change_hand_menu()
    local highlighted = (G.hand and G.hand.highlighted) or {}
    local available_hands = get_available_poker_hands(highlighted)

    local rows = {}

    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.08},
        nodes = {
            {
                n = G.UIT.T,
                config = {
                    text = "Choose Hand",
                    scale = 0.45,
                    colour = G.C.WHITE,
                    shadow = true
                }
            }
        }
    }

    if #available_hands == 0 then
        rows[#rows + 1] = {
            n = G.UIT.R,
            config = {align = "cm", padding = 0.08},
            nodes = {
                {
                    n = G.UIT.T,
                    config = {
                        text = "No valid hand",
                        scale = 0.35,
                        colour = G.C.UI.TEXT_LIGHT,
                        shadow = true
                    }
                }
            }
        }
    else
        for i, entry in ipairs(available_hands) do
            local button_key = "change_hand_pick_" .. tostring(i)

            G.FUNCS[button_key] = function(e)
                local selected_cards = copy_card_list(G.hand.highlighted or {})
                local current_hand = G.GAME and G.GAME.current_round and G.GAME.current_round.current_hand

                if not current_hand then
                    return
                end

                local default_hand_name = nil
                if old_get_poker_hand_info then
                    default_hand_name = select(1, old_get_poker_hand_info(selected_cards))
                end

                current_hand.forced_change_hand = entry.hand_name
                current_hand.forced_change_selected_cards = selected_cards
                current_hand.forced_change_hand_cards = entry.scoring_hand
                current_hand.forced_change_base_hand = default_hand_name

                if not mod.config.reset_after_each_hand
                    and default_hand_name
                    and entry.hand_name
                    and default_hand_name ~= entry.hand_name then
                    remembered_hand_choices[default_hand_name] = entry.hand_name
                end

                if G.hand and G.hand.parse_highlighted then
                    G.hand:parse_highlighted()
                end

                if G.change_hand_menu then
                    G.change_hand_menu:remove()
                    G.change_hand_menu = nil
                end
            end

            rows[#rows + 1] = {
                n = G.UIT.R,
                config = {align = "cm", padding = 0.05},
                nodes = {
                    {
                        n = G.UIT.C,
                        config = {
                            align = "cm",
                            minw = 3.0,
                            minh = 0.55,
                            r = 0.1,
                            colour = G.C.BLUE,
                            button = button_key,
                            hover = true,
                            shadow = true,
                            padding = 0.08
                        },
                        nodes = {
                            {
                                n = G.UIT.T,
                                config = {
                                    text = entry.hand_name,
                                    scale = 0.33,
                                    colour = G.C.WHITE,
                                    shadow = true
                                }
                            }
                        }
                    }
                }
            }
        end
    end

    rows[#rows + 1] = {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.08},
        nodes = {
            {
                n = G.UIT.C,
                config = {
                    align = "cm",
                    minw = 2.0,
                    minh = 0.5,
                    r = 0.1,
                    colour = G.C.RED,
                    button = "close_change_hand_menu",
                    hover = true,
                    shadow = true,
                    padding = 0.08
                },
                nodes = {
                    {
                        n = G.UIT.T,
                        config = {
                            text = "Close",
                            scale = 0.3,
                            colour = G.C.WHITE,
                            shadow = true
                        }
                    }
                }
            }
        }
    }

    return {
        n = G.UIT.ROOT,
        config = {
            align = "cm",
            colour = G.C.CLEAR
        },
        nodes = {
            {
                n = G.UIT.C,
                config = {
                    align = "cm",
                    padding = 0.12,
                    r = 0.12,
                    colour = G.C.BLACK,
                    emboss = 0.05
                },
                nodes = rows
            }
        }
    }
end

G.FUNCS.close_change_hand_menu = function(e)
    if G.change_hand_menu then
        G.change_hand_menu:remove()
        G.change_hand_menu = nil
    end
end

G.FUNCS.change_hand = function(e)
    if G.change_hand_menu then
        G.change_hand_menu:remove()
        G.change_hand_menu = nil
    end

    local menu_def = build_change_hand_menu()

    G.change_hand_menu = UIBox{
        definition = menu_def,
        config = {
            align = "cm",
            major = G.HUD,
            offset = {x = 0, y = 0},
            bond = "Weak"
        }
    }
end

function create_UIBox_HUD()
    local hud = old_create_UIBox_HUD()
    if not hud then return hud end

    local hand_root = find_node_by_id(hud, "hand_text_area")
    if not hand_root then
        print("hand_text_area not found")
        return hud
    end

    local inner_column = hand_root.nodes and hand_root.nodes[1]
    if not (inner_column and inner_column.nodes) then
        print("hand_text_area inner column not found")
        return hud
    end

    local button_row = {
        n = G.UIT.R,
        config = {align = "cm", padding = 0.08},
        nodes = {
            {
                n = G.UIT.C,
                config = {
                    align = "cm",
                    minw = 1.4,
                    minh = 0.3,
                    r = 0.1,
                    colour = G.C.RED,
                    button = "change_hand",
                    hover = true,
                    shadow = true,
                    padding = 0.08
                },
                nodes = {
                    {
                        n = G.UIT.T,
                        config = {
                            text = "Change Hand",
                            scale = 0.2,
                            colour = G.C.UI.TEXT_LIGHT,
                            shadow = true
                        }
                    }
                }
            }
        }
    }

    table.insert(inner_column.nodes, 3, button_row)

    return hud
end

local function is_subset_card_set(subset, full)
    if type(subset) ~= "table" or type(full) ~= "table" then
        return false
    end

    local counts = {}

    for i = 1, #full do
        counts[full[i]] = (counts[full[i]] or 0) + 1
    end

    for i = 1, #subset do
        local card = subset[i]
        if not counts[card] or counts[card] <= 0 then
            return false
        end
        counts[card] = counts[card] - 1
    end

    return true
end

local function clear_forced_hand(current_hand)
    if not current_hand then return end

    current_hand.forced_change_hand = nil
    current_hand.forced_change_selected_cards = nil
    current_hand.forced_change_hand_cards = nil
    current_hand.forced_change_base_hand = nil
end

function G.FUNCS.get_poker_hand_info(_cards)
    local current_hand = G.GAME and G.GAME.current_round and G.GAME.current_round.current_hand
    if not current_hand then
        return old_get_poker_hand_info(_cards)
    end

    local default_text, default_loc_disp_text, default_poker_hands, default_scoring_hand, default_disp_text =
        old_get_poker_hand_info(_cards)

    local forced_name = current_hand.forced_change_hand
    local forced_selected_cards = current_hand.forced_change_selected_cards
    local forced_scoring_cards = current_hand.forced_change_hand_cards

    local has_forced = forced_name and forced_selected_cards and forced_scoring_cards

    local selection_matches_forced = has_forced
        and is_subset_card_set(forced_selected_cards, _cards)

    if has_forced and not selection_matches_forced then
        clear_forced_hand(current_hand)

        forced_name = nil
        forced_selected_cards = nil
        forced_scoring_cards = nil
        has_forced = false
    end

    if not has_forced and not mod.config.reset_after_each_hand and default_text then
        local remembered_hand_name = remembered_hand_choices[default_text]
        if remembered_hand_name then
            local poker_hands = evaluate_poker_hand(_cards)
            local remembered_entries = poker_hands and poker_hands[remembered_hand_name]

            if remembered_entries and remembered_entries[1] then
                current_hand.forced_change_hand = remembered_hand_name
                current_hand.forced_change_selected_cards = copy_card_list(_cards)
                current_hand.forced_change_hand_cards = remembered_entries[1]
                current_hand.forced_change_base_hand = default_text

                forced_name = current_hand.forced_change_hand
                forced_selected_cards = current_hand.forced_change_selected_cards
                forced_scoring_cards = current_hand.forced_change_hand_cards
                has_forced = true
            end
        end
    end

    if has_forced then
        local poker_hands = evaluate_poker_hand(_cards)
        local scoring_hand = forced_scoring_cards
        local text = forced_name
        local disp_text = forced_name

        local _hand = SMODS.PokerHands[text]
        if text == 'Straight Flush' then
            local royal = true
            for j = 1, #scoring_hand do
                local rank = SMODS.Ranks[scoring_hand[j].base.value]
                royal = royal and (rank.key == 'Ace' or rank.key == '10' or rank.face)
            end
            if royal then
                disp_text = 'Royal Flush'
            end
        elseif _hand and _hand.modify_display_text and type(_hand.modify_display_text) == 'function' then
            disp_text = _hand:modify_display_text(_cards, scoring_hand) or disp_text
        end

        local flags = SMODS.calculate_context({
            evaluate_poker_hand = true,
            full_hand = _cards,
            scoring_hand = scoring_hand,
            scoring_name = text,
            poker_hands = poker_hands,
            display_name = disp_text
        })

        text = flags.replace_scoring_name or text
        disp_text = flags.replace_display_name or flags.replace_scoring_name or disp_text
        poker_hands = flags.replace_poker_hands or poker_hands

        local loc_disp_text = localize(disp_text, 'poker_hands')
        loc_disp_text = loc_disp_text == 'ERROR' and disp_text or loc_disp_text

        return text, loc_disp_text, poker_hands, scoring_hand, disp_text
    end

    return default_text, default_loc_disp_text, default_poker_hands, default_scoring_hand, default_disp_text
end

return {
    remembered_hand_choices = remembered_hand_choices,
    clear_remembered_hand_choices = function()
        remembered_hand_choices = {}
    end
}