-- The client's knowledge of its OWN character. Nothing here concerns anyone
-- else: other players are resolved one at a time through M5's identity
-- service, never cached wholesale.
--
-- D-015 needs this so a player's own Nick() can return their own name while
-- everyone else's returns "Unknown".

local localCharacter = nil

function Omerta.Characters.SetLocal(character)
    localCharacter = character
    hook.Run("Omerta.LocalCharacterUpdated", character)
end

function Omerta.Characters.GetLocal()
    return localCharacter
end

-- Losing the character (retirement, death, season end) clears it immediately;
-- a stale own-name is as wrong as a stale foreign one.
hook.Add("Omerta.CharactersState", "omerta.characters.local_clear", function(state)
    if state ~= Omerta.Characters.STATE.ACTIVE then
        Omerta.Characters.SetLocal(nil)
    end
end)
