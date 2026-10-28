local BERSERK_TIMEOUT     = 10  -- max gap between hits that still chains
local BERSERK_DECAY_AFTER = 3   -- seconds without a hit before decay starts
local BERSERK_TIERS = {
    {
        threshold = 0,
        multiplier = 1.0,
        description = "UI_berserk_tier1"
    },
    {
        threshold = 5,
        multiplier = 1.1,
        description = "UI_berserk_tier2"
    },
    {
        threshold = 10,
        multiplier = 1.2,
        description = "UI_berserk_tier3"
    },
    {
        threshold = 15,
        multiplier = 1.3,
        description = "UI_berserk_tier4"
    },
    {
        threshold = 20,
        multiplier = 1.5,
        description = "UI_berserk_tier5"
    }
}

local XICOZ_SIDE_DEBUG = false

-- Trait logic runs only on the attacker's own client (or in SP). In MP the event also
-- fires on the server and on every other client, which applied the bonus several times.
local function isOwnedHere(player)
    if isServer() then return false end
    if not instanceof(player, "IsoPlayer") then return false end
    return player:isLocalPlayer()
end

-- Shoves report the weapon's full damage, so scaling it made pushes lethal.
local function isStrike(actor)
    return not actor:isDoShove()
end

local function addHaloText(player, text, arrowUp, color)
    HaloTextHelper.addTextWithArrow(player, text, arrowUp, color, color)
end

local function onBerserkHit(actor, target, weapon, damage)
    if XICOZ_SIDE_DEBUG then
        print("[Xicoz] hit server=" .. tostring(isServer()) .. " client=" .. tostring(isClient()) ..
              " local=" .. tostring(instanceof(actor, "IsoPlayer") and actor:isLocalPlayer()) ..
              " shove=" .. tostring(instanceof(actor, "IsoPlayer") and actor:isDoShove()) ..
              " damage=" .. tostring(damage))
    end
    if not isOwnedHere(actor) then return end
    if not isStrike(actor) then return end
    if not actor:hasTrait(XicozTraitsRegistries.berserk) then return end
    local now = getTimestamp()
    local actorData = actor:getModData()

    if not actorData.berserkLastHit then
        actorData.berserkLastHit = now
        actorData.berserkInCombatSeconds = 0
    else
        local timeSinceLastHit = now - actorData.berserkLastHit
        if timeSinceLastHit <= BERSERK_TIMEOUT then
            actorData.berserkInCombatSeconds = actorData.berserkInCombatSeconds + timeSinceLastHit
        else
            actorData.berserkInCombatSeconds = 0
        end
        actorData.berserkLastHit = now
    end

    local tierIndex = 1
    for i = #BERSERK_TIERS, 1, -1 do
        if actorData.berserkInCombatSeconds >= BERSERK_TIERS[i].threshold then
            tierIndex = i
            break
        end
    end
    local tier = BERSERK_TIERS[tierIndex]

    if tierIndex ~= (actorData.berserkTierIndex or 1) then
        actorData.berserkTierIndex = tierIndex
        addHaloText(actor, getText(tier.description), true, HaloTextHelper.getColorRed())
    end

    local extraDamage = damage * 0.5 * tier.multiplier
    target:setHealth(target:getHealth() - extraDamage)

    if weapon and weapon:getType() ~= "BareHands" then
        actorData.berserkWearAccum = (actorData.berserkWearAccum or 0) + tier.multiplier
        if actorData.berserkWearAccum >= 1 then
            weapon:setCondition(weapon:getCondition() - 1)
            actorData.berserkWearAccum = actorData.berserkWearAccum - 1
        end
    end

    local targetData = target:getModData()
    if target:getHealth() <= 0 and not targetData.xicozKillProcessed then
        targetData.xicozKillProcessed = true
        target:Kill(actor)
        actor:setZombieKills(actor:getZombieKills() + 1)
    end
end

local function onRageHit(actor, target, _weapon, damage)
    if not isOwnedHere(actor) then return end
    if not isStrike(actor) then return end
    if not actor:hasTrait(XicozTraitsRegistries.ragebuff) then return end
    local extraDamage = damage * 0.25
    target:setHealth(target:getHealth() - extraDamage)

    local targetData = target:getModData()
    if target:getHealth() <= 0 and not targetData.xicozKillProcessed then
        targetData.xicozKillProcessed = true
        target:Kill(actor)
        actor:setZombieKills(actor:getZombieKills() + 1)
    end
end

local DEADEYE_TIMEOUT    = 5
local DEADEYE_MAX_STACKS = 5
local DEADEYE_DEBUG      = false

local function onDeadeyeHit(actor, target, weapon, _damage)
    if not isOwnedHere(actor) then return end
    if not actor:hasTrait(XicozTraitsRegistries.deadeye) then return end
    if not weapon or not weapon:isAimedFirearm() then return end

    local actorData = actor:getModData()
    local now = getTimestamp()

    actorData.deadeyeStacks    = math.min((actorData.deadeyeStacks or 0) + 1, DEADEYE_MAX_STACKS)
    actorData.deadeyeLastHit   = now

    local aimLevel       = actor:getPerkLevel(Perks.Aiming)
    local headshotChance = actorData.deadeyeStacks * 10 + aimLevel * 2

    addHaloText(actor, getText("UI_deadeyestacks") .. ": " .. actorData.deadeyeStacks, true, HaloTextHelper.getColorGreen())

    if DEADEYE_DEBUG then
        print("[Deadeye] stacks=" .. actorData.deadeyeStacks ..
              " aimLevel=" .. aimLevel ..
              " chance=" .. headshotChance .. "%")
    end

    if ZombRand(100) < headshotChance then
        local targetData = target:getModData()
        if not targetData.xicozKillProcessed then
            if DEADEYE_DEBUG then print("[Deadeye] headshot triggered!") end
            targetData.xicozKillProcessed = true
            target:Kill(actor)
            actor:setZombieKills(actor:getZombieKills() + 1)
        end
    end
end

-- Avoid updating the stacks on confirmed hit, instead on playerUpdate.
local function onDeadeyeUpdate(player)
    if not isOwnedHere(player) then return end
    if not player:hasTrait(XicozTraitsRegistries.deadeye) then return end
    local actorData = player:getModData()
    if not actorData.deadeyeLastHit then return end
    if (actorData.deadeyeStacks or 0) == 0 then return end

    if (getTimestamp() - actorData.deadeyeLastHit) > DEADEYE_TIMEOUT then
        if DEADEYE_DEBUG then print("[Deadeye] stacks expired on timer") end
        addHaloText(player, getText("UI_deadeyestacks") .. ": " .. actorData.deadeyeStacks, false, HaloTextHelper.getColorRed())
        actorData.deadeyeStacks  = 0
        actorData.deadeyeLastHit = nil
    end
end

local function onBerserkUpdate(player)
    if not isOwnedHere(player) then return end
    if not player:hasTrait(XicozTraitsRegistries.berserk) then return end
    local actorData = player:getModData()
    if not actorData.berserkLastHit then return end
    if (actorData.berserkInCombatSeconds or 0) == 0 then return end

    local now = getTimestamp()
    local timeSinceLastHit = now - actorData.berserkLastHit

    if timeSinceLastHit > BERSERK_DECAY_AFTER then
        local elapsed = now - (actorData.berserkLastUpdate or now)
        actorData.berserkLastUpdate = now

        local oldTierIndex = actorData.berserkTierIndex or 1
        actorData.berserkInCombatSeconds = math.max(0, actorData.berserkInCombatSeconds - elapsed)

        local newTierIndex = 1
        for i = #BERSERK_TIERS, 1, -1 do
            if actorData.berserkInCombatSeconds >= BERSERK_TIERS[i].threshold then
                newTierIndex = i
                break
            end
        end

        if newTierIndex < oldTierIndex then
            actorData.berserkTierIndex = newTierIndex
            addHaloText(player, getText("UI_berserk_tierdown"), false, HaloTextHelper.getColorRed())
        end

        if actorData.berserkInCombatSeconds <= 0 then
            actorData.berserkInCombatSeconds = 0
            actorData.berserkWearAccum       = 0
            actorData.berserkTierIndex       = 1
            actorData.berserkLastHit         = nil
            actorData.berserkLastUpdate      = nil
        end
    else
        actorData.berserkLastUpdate = now
    end
end

Events.OnWeaponHitCharacter.Add(onBerserkHit)
Events.OnWeaponHitCharacter.Add(onRageHit)
Events.OnWeaponHitCharacter.Add(onDeadeyeHit)
Events.OnPlayerUpdate.Add(onBerserkUpdate)
Events.OnPlayerUpdate.Add(onDeadeyeUpdate)
