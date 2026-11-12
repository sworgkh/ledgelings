// Every effect ported from pixelfx, by its pixelfx name ("status/frozen"), for the styles and moments
// (`Effects`) and for the films and checks that play them by name.

public enum FXCatalog {
    public static let all: [String: FXEffect.Type] = [
        "arcane/blink-in": FXBlinkIn.self,
        "arcane/blink-out": FXBlinkOut.self,
        "arcane/magic-circle-cast": FXMagicCircle.self,
        "impacts/heavy-landing": FXHeavyLanding.self,
        "lightning/charge-up": FXChargeUp.self,
        "lightning/electrified": FXElectrified.self,
        "nature/healing-bloom": FXHealingBloom.self,
        "pickups/collect-burst": FXCollectBurst.self,
        "spawn/coin-drop": FXCoinDrop.self,
        "spawn/egg-hatch": FXEggHatch.self,
        "spawn/poof": FXPoof.self,
        "status/burning": FXBurning.self,
        "status/charmed": FXCharmed.self,
        "status/cursed": FXCursed.self,
        "status/frozen": FXFrozen.self,
        "status/sleep": FXSleep.self,
        "status/slowed": FXSlowed.self,
        "status/stunned": FXStunned.self,
        "ui/confetti": FXConfetti.self,
        "ui/exclamation": FXExclamation.self,
        "ui/level-up": FXLevelUp.self,
        "weather/cherry-blossoms": FXBlossoms.self,
        "weather/falling-leaves": FXFallingLeaves.self,
        "weather/fireflies": FXFireflies.self,
        "weather/snow": FXSnow.self,
    ]
}
