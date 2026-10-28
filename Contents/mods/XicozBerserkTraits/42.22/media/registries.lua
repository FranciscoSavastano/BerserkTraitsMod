local sleepOK = (isClient() or isServer()) and getServerOptions():getBoolean("SleepAllowed") and getServerOptions():getBoolean("SleepNeeded")
XicozTraitsRegistries = {}

XicozTraitsRegistries.ragebuff = CharacterTrait.register("XicozTraits:ragebuff")
XicozTraitsRegistries.berserk = CharacterTrait.register("XicozTraits:berserk")
XicozTraitsRegistries.deadeye = CharacterTrait.register("XicozTraits:deadeye")
