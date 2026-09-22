import Foundation

/// The creature's voice. Short, dramatic, slightly unhinged.
public enum Narrator {
    public static let idle = [
        "Waiting for humans...", "I'm bored.", "Is anyone there?", "Scanning for snacks... I mean humans.",
        "The ducks are getting restless.", "Humming quietly to myself.", "Polishing the bubble cannon.",
    ]

    public static func arrival(count: Int, character: CharacterType) -> String {
        switch count {
        case 1: ["TARGET ACQUIRED.", "A wild \(character.displayName) appears!", "Oh hello. You look... hittable.",
                 "Human detected. Loading ducks."].randomElement()!
        case 2: ["Oh no. There are two of them.", "Another one?! Double trouble.", "Two humans. Twice the confetti."].randomElement()!
        default: ["It's a crowd! Deploying everything.", "\(count) humans?! This is a party now.",
                  "Too many humans. Initiating chaos protocol."].randomElement()!
        }
    }

    public static func escape(remaining: Int) -> String {
        remaining == 0
            ? ["Humans have escaped.", "Come back! I had more ducks!", "Fine. Be that way.", "...and they're gone."].randomElement()!
            : ["One got away!", "A human fled. Coward.", "Retreat detected."].randomElement()!
    }

    public static func holdBack(_ mood: DirectorMood) -> String {
        switch mood {
        case .bored: ["...nah.", "Can't be bothered.", "*yawns*"].randomElement()!
        case .mischievous: ["Not yet... not yet...", "Waiting for the perfect moment.", "Shhh. Plotting."].randomElement()!
        case .alarmed: ["Hold on, recalculating.", "Uh. Let me think about this."].randomElement()!
        case .gleeful: ["Savouring the moment...", "Heh. Heh heh."].randomElement()!
        }
    }

    public static func attack(_ effect: EffectKind, target: String, mood: DirectorMood) -> String {
        let t = target
        let base: [String]
        switch effect {
        case .bubbleBlast: base = ["Bubbles for \(t)!", "Bubble blast incoming!", "Soap. Bubbles. NOW."]
        case .duckRain: base = ["Deploying ducks.", "It's raining ducks on \(t)!", "QUACK ATTACK."]
        case .tomatoThrow: base = ["Tomato for \(t)!", "Splat time.", "Fresh tomato, special delivery!"]
        case .balloonAttack: base = ["Balloon barrage!", "Balloons away!", "Pop goes \(t)!"]
        case .spongeShot: base = ["Sponge incoming!", "Squish!", "Foam sponge, direct hit!"]
        case .confettiExplosion: base = ["CONFETTI!", "Celebration mode!", "Party time, humans!"]
        case .bubbleStorm: base = ["BUBBLE STORM!", "Everybody gets bubbles!"]
        case .rainbowExplosion: base = ["Taste the RAINBOW!", "Rainbow overload!"]
        case .emojiExplosion: base = ["EMOJI EXPLOSION!", "Emotional damage (emoji edition)!"]
        case .transform: base = ["Abracadabra, \(t)!", "Transformation time!", "You look better as something else."]
        case .surprise: base = ["SURPRISE!!!", "You did NOT see this coming.", "Plot twist!"]
        }
        let prefix: String
        switch mood {
        case .bored: prefix = ["Ugh, fine. ", "", ""].randomElement()!
        case .mischievous: prefix = ["Heh. ", "", ""].randomElement()!
        case .alarmed: prefix = ["WHOA. ", "", ""].randomElement()!
        case .gleeful: prefix = ["Wheee! ", "", ""].randomElement()!
        }
        return prefix + base.randomElement()!
    }
}
