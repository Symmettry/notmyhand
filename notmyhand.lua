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

local function is_real_hand_name(name)
    if type(name) ~= "string" then
        return false
    end

    return (G.GAME and G.GAME.hands and G.GAME.hands[name] ~= nil)
        or (SMODS and SMODS.PokerHands and SMODS.PokerHands[name] ~= nil)
end

local function card_is_face_down(card)
    if not card then
        return false
    end
    return card.facing == 'back'
        or card.sprite_facing == 'back'
        or card.face_down == true
end

local function selection_has_face_down(cards)
    for _, card in ipairs(cards or {}) do
        if card_is_face_down(card) then
            return true
        end
    end
    return false
end

local function can_open_change_hand_menu(cards)
    cards = cards or {}
    return #cards > 0 and not selection_has_face_down(cards)
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

local function get_rank_groups(cards)
    local groups_by_rank = {}
    local ordered_groups = {}

    for _, card in ipairs(cards or {}) do
        local rank = card and card.base and card.base.value
        if rank ~= nil then
            if not groups_by_rank[rank] then
                groups_by_rank[rank] = {}
                ordered_groups[#ordered_groups + 1] = groups_by_rank[rank]
            end
            groups_by_rank[rank][#groups_by_rank[rank] + 1] = card
        end
    end

    table.sort(ordered_groups, function(a, b)
        if #a ~= #b then
            return #a > #b
        end
        return tostring(a[1].base.value) > tostring(b[1].base.value)
    end)

    return ordered_groups
end

local function count_distinct_ranks(cards)
    local seen = {}
    local count = 0

    for _, card in ipairs(cards or {}) do
        local key = card and card.base and card.base.value
        if key ~= nil and not seen[key] then
            seen[key] = true
            count = count + 1
        end
    end

    return count
end

local function normalize_scoring_candidate(hand_name, candidate)
    if type(candidate) ~= "table" or #candidate == 0 then
        return candidate
    end

    local groups = get_rank_groups(candidate)
    local normalized_name = type(hand_name) == "string" and string.lower(hand_name) or nil

    if normalized_name == "pair" and #groups >= 1 and #groups[1] >= 2 then
        return {groups[1][1], groups[1][2]}
    end

    if normalized_name == "two pair" then
        local pair_groups = {}
        for _, group in ipairs(groups) do
            if #group >= 2 then
                pair_groups[#pair_groups + 1] = group
            end
        end
        if #pair_groups >= 2 then
            return {
                pair_groups[1][1], pair_groups[1][2],
                pair_groups[2][1], pair_groups[2][2]
            }
        end
    end

    if (normalized_name == "three of a kind")
        and #groups >= 1 and #groups[1] >= 3 then
        return {groups[1][1], groups[1][2], groups[1][3]}
    end

    if (normalized_name == "four of a kind")
        and #groups >= 1 and #groups[1] >= 4 then
        return {groups[1][1], groups[1][2], groups[1][3], groups[1][4]}
    end

    return candidate
end

local function choose_best_scoring_candidate(hand_name, hand_entries, selected_cards)
    if type(hand_entries) ~= "table" then
        return nil, nil
    end

    local best_candidate = nil
    local best_index = nil
    local best_len = nil
    local best_distinct = nil

    for idx, candidate in ipairs(hand_entries) do
        if type(candidate) == "table"
            and #candidate > 0
            and is_subset_card_set(candidate, selected_cards or {}) then

            local normalized_candidate = normalize_scoring_candidate(hand_name, copy_card_list(candidate))
            local candidate_len = #normalized_candidate
            local candidate_distinct = count_distinct_ranks(normalized_candidate)

            if not best_candidate then
                best_candidate = normalized_candidate
                best_index = idx
                best_len = candidate_len
                best_distinct = candidate_distinct
            else
                local better = false

                if candidate_len < best_len then
                    better = true
                elseif candidate_len == best_len then
                    if candidate_distinct > best_distinct then
                        better = true
                    end
                end

                if better then
                    best_candidate = normalized_candidate
                    best_index = idx
                    best_len = candidate_len
                    best_distinct = candidate_distinct
                end
            end
        end
    end

    if best_candidate then
        return copy_card_list(best_candidate), best_index
    end

    if hand_entries[1] then
        return normalize_scoring_candidate(hand_name, copy_card_list(hand_entries[1])), 1
    end

    return nil, nil
end

local function get_available_poker_hands(cards)
    local results = evaluate_poker_hand(cards or {})
    local buttons = {}

    for hand_name, hand_entries in pairs(results) do
        if is_real_hand_name(hand_name)
            and type(hand_entries) == "table"
            and next(hand_entries) then

            local best_candidate, best_index =
                choose_best_scoring_candidate(hand_name, hand_entries, cards or {})

            if best_candidate and #best_candidate > 0 then
                buttons[#buttons + 1] = {
                    hand_name = hand_name,
                    scoring_hand = best_candidate,
                    candidate_index = best_index,
                    all_hands = results,
                }
            end
        end
    end

    return buttons, results
end

function G.FUNCS.close_change_hand_menu()
    if G.change_hand_menu then
        G.change_hand_menu:remove()
        G.change_hand_menu = nil
    end
end

local function refresh_change_hand_menu()
    local highlighted = copy_card_list((G.hand and G.hand.highlighted) or {})

    if not G.change_hand_menu then
        return
    end

    if not can_open_change_hand_menu(highlighted) then
        G.change_hand_menu:remove()
        G.change_hand_menu = nil
        return
    end

    G.change_hand_menu:remove()
    G.change_hand_menu = nil

    local menu_def = build_change_hand_menu()
    if not menu_def then
        return
    end

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

G.FUNCS.change_hand = function(e)
    local highlighted = copy_card_list((G.hand and G.hand.highlighted) or {})

    G.FUNCS.close_change_hand_menu()

    if not can_open_change_hand_menu(highlighted) then
        return
    end

    local menu_def = build_change_hand_menu()
    if not menu_def then
        return
    end

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

function build_change_hand_menu()
    local highlighted = copy_card_list((G.hand and G.hand.highlighted) or {})

    if not can_open_change_hand_menu(highlighted) then
        return nil
    end

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
                local selected_cards = copy_card_list((G.hand and G.hand.highlighted) or {})
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
                current_hand.forced_change_hand_cards = copy_card_list(entry.scoring_hand)
                current_hand.forced_change_candidate_index = entry.candidate_index
                current_hand.forced_change_base_hand = default_hand_name

                if not mod.config.reset_after_each_hand
                    and default_hand_name
                    and entry.hand_name then

                    if default_hand_name == entry.hand_name then
                        remembered_hand_choices[default_hand_name] = nil
                    else
                        remembered_hand_choices[default_hand_name] = entry.hand_name
                    end
                end

                if G.hand and G.hand.parse_highlighted then
                    G.hand:parse_highlighted()
                end

                G.FUNCS.close_change_hand_menu()
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

local function wrap_to_close_change_hand_menu(func_name)
    local old_func = G.FUNCS[func_name]
    if type(old_func) ~= "function" then
        return
    end

    G.FUNCS[func_name] = function(...)
        G.FUNCS.close_change_hand_menu()
        return old_func(...)
    end
end

wrap_to_close_change_hand_menu("play_cards_from_highlighted")
wrap_to_close_change_hand_menu("discard_cards_from_highlighted")
wrap_to_close_change_hand_menu("use_card")
wrap_to_close_change_hand_menu("sell_card")
wrap_to_close_change_hand_menu("buy_from_shop")
wrap_to_close_change_hand_menu("reroll_shop")
wrap_to_close_change_hand_menu("skip_blind")
wrap_to_close_change_hand_menu("cash_out")
wrap_to_close_change_hand_menu("sort_hand")
wrap_to_close_change_hand_menu("toggle_shop")

G.FUNCS.change_hand = function(e)
    local highlighted = copy_card_list((G.hand and G.hand.highlighted) or {})

    G.FUNCS.close_change_hand_menu()

    if not can_open_change_hand_menu(highlighted) then
        return
    end

    local menu_def = build_change_hand_menu()
    if not menu_def then
        return
    end

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

local function clear_forced_hand(current_hand)
    if not current_hand then return end

    current_hand.forced_change_hand = nil
    current_hand.forced_change_selected_cards = nil
    current_hand.forced_change_hand_cards = nil
    current_hand.forced_change_candidate_index = nil
    current_hand.forced_change_base_hand = nil
end

function G.FUNCS.get_poker_hand_info(_cards)
    local current_hand = G.GAME and G.GAME.current_round and G.GAME.current_round.current_hand
    if not current_hand then
        return old_get_poker_hand_info(_cards)
    end

    if selection_has_face_down(_cards) then
        clear_forced_hand(current_hand)
        return old_get_poker_hand_info(_cards)
    end

    local default_text, default_loc_disp_text, default_poker_hands, default_scoring_hand, default_disp_text =
        old_get_poker_hand_info(_cards)

    local forced_name = current_hand.forced_change_hand
    local forced_selected_cards = current_hand.forced_change_selected_cards
    local forced_scoring_cards = current_hand.forced_change_hand_cards
    local forced_candidate_index = current_hand.forced_change_candidate_index

    local has_forced = forced_name and forced_selected_cards and forced_scoring_cards

    local selection_matches_forced = has_forced
        and is_subset_card_set(forced_selected_cards, _cards)

    if has_forced and not selection_matches_forced then
        clear_forced_hand(current_hand)

        forced_name = nil
        forced_selected_cards = nil
        forced_scoring_cards = nil
        forced_candidate_index = nil
        has_forced = false
    end

    if not has_forced and not mod.config.reset_after_each_hand and default_text then
        local remembered_hand_name = remembered_hand_choices[default_text]
        if remembered_hand_name then
            local poker_hands = evaluate_poker_hand(_cards)
            local remembered_entries = poker_hands and poker_hands[remembered_hand_name]
            local remembered_scoring_hand, remembered_candidate_index =
                choose_best_scoring_candidate(remembered_hand_name, remembered_entries, _cards)

            if remembered_scoring_hand and remembered_candidate_index then
                current_hand.forced_change_hand = remembered_hand_name
                current_hand.forced_change_selected_cards = copy_card_list(_cards)
                current_hand.forced_change_hand_cards = remembered_scoring_hand
                current_hand.forced_change_candidate_index = remembered_candidate_index
                current_hand.forced_change_base_hand = default_text

                forced_name = current_hand.forced_change_hand
                forced_selected_cards = current_hand.forced_change_selected_cards
                forced_scoring_cards = current_hand.forced_change_hand_cards
                forced_candidate_index = current_hand.forced_change_candidate_index
                has_forced = true
            end
        end
    end

    if has_forced then
        local poker_hands = evaluate_poker_hand(_cards)
        local hand_entries = poker_hands and poker_hands[forced_name]

        if hand_entries and forced_candidate_index and hand_entries[forced_candidate_index] then
            local refreshed_candidate =
                normalize_scoring_candidate(forced_name, copy_card_list(hand_entries[forced_candidate_index]))

            if is_subset_card_set(refreshed_candidate, _cards) then
                forced_scoring_cards = refreshed_candidate
                current_hand.forced_change_hand_cards = forced_scoring_cards
            else
                local best_candidate, best_index =
                    choose_best_scoring_candidate(forced_name, hand_entries, _cards)

                if best_candidate and best_index then
                    forced_scoring_cards = best_candidate
                    forced_candidate_index = best_index
                    current_hand.forced_change_hand_cards = forced_scoring_cards
                    current_hand.forced_change_candidate_index = forced_candidate_index
                end
            end
        elseif hand_entries then
            local best_candidate, best_index =
                choose_best_scoring_candidate(forced_name, hand_entries, _cards)

            if best_candidate and best_index then
                forced_scoring_cards = best_candidate
                forced_candidate_index = best_index
                current_hand.forced_change_hand_cards = forced_scoring_cards
                current_hand.forced_change_candidate_index = forced_candidate_index
            end
        end

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

local old_parse_highlighted = CardArea.parse_highlighted
function CardArea:parse_highlighted(...)
    local result = old_parse_highlighted and old_parse_highlighted(self, ...)

    if self == G.hand then
        local current_hand = G.GAME and G.GAME.current_round and G.GAME.current_round.current_hand
        local highlighted = copy_card_list((G.hand and G.hand.highlighted) or {})

        if selection_has_face_down(highlighted) and current_hand then
            clear_forced_hand(current_hand)
        end

        refresh_change_hand_menu()
    end

    return result
end

return {
    remembered_hand_choices = remembered_hand_choices,
    clear_remembered_hand_choices = function()
        remembered_hand_choices = {}
    end
}