-- Lootable Passives -- The local player's own Surgery click, handed from the UI
-- half to the server half.
--
-- lp/ui.lua sets capture at load. lp/transaction.lua calls it, when it is set,
-- for a request the local player made. Neither of those modules requires the
-- other.
--
-- capture(request_player_id) returns a record read off the Surgery tab page, or
-- nil and whether a tab page is recorded at all.
return {
    capture = nil,
}
