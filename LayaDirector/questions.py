"""Mac Attack's typed questions for Laya.

Laya never sees pixels. It reads a small abstract game state (positions, motion, dwell time,
recent history) plus a one-paragraph "situation" summary, and answers these questions in one
forward pass. The Swift side samples from the returned probabilities, so the calibrated
distributions are the director's personality; argmax is only used for display.
"""

from typing import Any, Dict, List

# Laya's per-option-count temperature for 11+ choices is uncalibrated (it saturates to 1.0),
# so the effect is decided as style (4 options) + a specific projectile (5) or area effect (4).
STYLES = {
    "projectile": "throw a toy at one specific human",
    "area": "a big effect over the whole room, good with several humans or a celebration",
    "transform": "turn a human's character into a different creature",
    "surprise": "something totally unexpected, only when things have become predictable",
}

PROJECTILES = {
    "bubble_blast": "soap bubbles, gentle, for someone new or standing still",
    "duck_rain": "rubber ducks rain from the sky onto someone who stayed a long time",
    "tomato_throw": "a cartoon tomato splat at someone who keeps moving",
    "balloon_attack": "water balloons lobbed, playful and bouncy",
    "sponge_shot": "a foam sponge, a follow-up on someone just hit",
}

AREAS = {
    "confetti_explosion": "confetti for an arrival or a big combo",
    "bubble_storm": "a storm of bubbles over everyone",
    "rainbow_explosion": "a rainbow burst, rare and dramatic",
    "emoji_explosion": "a burst of random emojis, chaotic and silly",
}

REACTIONS = {
    "dodge": "the character jumps aside, good for fast moving humans",
    "jump": "the character hops in surprise",
    "shake": "the character shakes it off, annoyed",
    "spin": "the character spins around, dizzy",
    "shrink": "the character shrinks, embarrassed",
    "grow": "the character grows huge, powered up",
    "explode": "the character bursts into particles and reforms, for big hits",
    "celebrate": "the character celebrates, happy to be hit",
}

MOODS = {
    "bored": "nothing interesting is happening, the same thing again",
    "mischievous": "plotting a prank, sneaky, playful",
    "alarmed": "surprised, a new human or too many humans appeared",
    "gleeful": "delighted, a big hit or a combo is building",
}


def _describe(p: Dict[str, Any]) -> str:
    x = float(p.get("x", 0.5))
    side = "left" if x < 0.33 else "right" if x > 0.66 else "middle"
    move = p.get("movement", "stationary")
    motion = "standing still" if move == "stationary" else "moving " + move
    dwell = float(p.get("dwell_time", 0))
    hits = int(p.get("times_hit", 0))
    new = "just arrived, " if dwell < 4 else ""
    return "the %s on the %s, %s%s, here %d s, hit %d times" % (
        p.get("character", "human"), side, new, motion, round(dwell), hits)


def situation(state: Dict[str, Any]) -> str:
    people: List[Dict[str, Any]] = state.get("people", [])[:4]
    n = int(state.get("people_count", len(people)))
    if n == 0:
        parts = ["No humans. The room has been empty for %d s." % round(float(state.get("idle_seconds", 0)))]
    else:
        parts = ["%d human%s in view." % (n, "" if n == 1 else "s")]
        parts += ["%s is %s." % (p["id"], _describe(p)) for p in people]
    last = state.get("last_event")
    if last:
        parts.append("Last event: %s on %s %d s ago." % (
            last.get("effect"), last.get("target"), round(float(last.get("seconds_ago", 0)))))
    trig = state.get("trigger")
    if trig == "person_arrived":
        parts.append("A new human has just walked in.")
    elif trig == "person_left":
        parts.append("A human has just escaped.")
    if int(state.get("combo", 0)) >= 3:
        parts.append("Combo of %d hits in a row." % int(state["combo"]))
    if state.get("chaos"):
        parts.append("CHAOS MODE is on: be wild.")
    return " ".join(parts)


def build_questions(state: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    people = state.get("people", [])[:4]
    targets = {p["id"]: _describe(p) for p in people}
    targets["everyone"] = "all the humans at once, good when there are several"
    return {
        "style": {
            "type": "choice",
            "instructions": "You are the mischievous director of a cartoon toy game. What kind of harmless effect should happen next?",
            "criteria": STYLES,
        },
        "projectile": {
            "type": "choice",
            "instructions": "If a toy is thrown at a human, which toy fits this moment best?",
            "criteria": PROJECTILES,
        },
        "area": {
            "type": "choice",
            "instructions": "If a room-wide effect happens, which one fits this moment best?",
            "criteria": AREAS,
        },
        "target": {
            "type": "choice",
            "instructions": "Which human should the effect be aimed at?",
            "criteria": targets,
        },
        "intensity": {
            "type": "score",
            "instructions": "How big and dramatic should the effect be?",
            "criteria": ["tiny, a gentle poke", "moderate", "big", "enormous, over the top"],
        },
        "reaction": {
            "type": "choice",
            "instructions": "How should the targeted cartoon character react?",
            "criteria": REACTIONS,
        },
        "hold_back": {
            "type": "noul",
            "instructions": "Should the director hold back and do nothing this time, because something just happened or the moment calls for suspense?",
        },
        "mood": {
            "type": "choice",
            "instructions": "What is the director's mood right now?",
            "criteria": MOODS,
        },
    }
