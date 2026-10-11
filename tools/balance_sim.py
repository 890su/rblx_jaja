"""Economy / progression simulation for a typical free-to-play player.

Mirrors src/shared/Config (keep numbers in sync when tuning). The simulated
player repeatedly runs to the farthest unlocked zone, grabs one meteor, carries
it home (slowed), places it (replacing the weakest creature when full), banks
income, buys pedestals when affordable and rebirths when possible.

Usage: python tools/balance_sim.py [hours]
"""

import math
import random
import sys

# --- Config mirror -----------------------------------------------------------
BASE_WALK, COEF, CAP = 16, 6, 400
CARRY = 0.6
ZONE_LEN = 1000
ZONES = [  # speed gate, rebirth gate, weights
    (0, 0, {"Common": 80, "Uncommon": 18, "Rare": 2}),
    (100, 0, {"Common": 64, "Uncommon": 30, "Rare": 5.5, "Epic": 0.5}),
    (500, 0, {"Common": 55, "Uncommon": 33, "Rare": 10, "Epic": 1.8, "Legendary": 0.2}),
    (2000, 0, {"Common": 52, "Uncommon": 33, "Rare": 11, "Epic": 3.5, "Legendary": 0.45, "Mythic": 0.05}),
    (8000, 1, {"Common": 47.4, "Uncommon": 33.3, "Rare": 15, "Epic": 3.5, "Legendary": 0.75, "Mythic": 0.05}),
]
CANYON_FROM, CANYON_SHARE, CANYON_BOOST = 3, 0.7, 2
INCOME = {"Common": 1, "Uncommon": 4, "Rare": 15, "Epic": 60, "Legendary": 250, "Mythic": 1200}
HATCH = {"Common": 10, "Uncommon": 60, "Rare": 300, "Epic": 1200, "Legendary": 3600, "Mythic": 28800}
PEDESTALS_START, PEDESTAL_COSTS = 3, [500, 2500, 10000, 60000, 250000]
REBIRTH_BASE, REBIRTH_GROWTH, REBIRTH_SPEED = 300000, 4, 5000
REBIRTH_INCOME, REBIRTH_GAIN = 0.5, 0.25
SELL_SECONDS = 30
TRAINING_BASE, TRAINING_GROWTH, TRAINING_BONUS, TRAINING_MAX = 2000, 2.2, 0.10, 10  # sell value of a replaced creature = income * SELL_SECONDS
PICKUP_OVERHEAD = 6  # seconds per trip (prompt, placing, turning)
ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]


def walk(speed):
    return min(BASE_WALK + COEF * math.sqrt(speed), CAP)


def roll(weights, boost, rng):
    w = {r: (v * boost if r != "Common" else v) for r, v in weights.items()}
    pick = rng.random() * sum(w.values())
    for r in ORDER:
        if r in w:
            pick -= w[r]
            if pick <= 0:
                return r
    return "Common"


def simulate(hours, seed=1, verbose=True):
    rng = random.Random(seed)
    t, speed, coins, rebirths = 0.0, 0.0, 0.0, 0
    pedestals = []  # list of (rarity, hatch_at)
    capacity = PEDESTALS_START
    training = 0
    milestones = {}
    log_every, next_log = 600, 600

    def income_rate():
        base = sum(INCOME[r] for r, h in pedestals if h <= t)
        return base * (1 + rebirths * REBIRTH_INCOME)

    while t < hours * 3600:
        # farthest unlocked zone
        zone = 1
        for i, (sg, rg, _) in enumerate(ZONES, start=1):
            if speed >= sg and rebirths >= rg:
                zone = i
        for i in range(2, len(ZONES) + 1):
            key = f"zone{i}"
            if zone >= i and key not in milestones:
                milestones[key] = t
        # trip: run to the middle of the zone, carry back
        dist = (zone - 0.5) * ZONE_LEN + 60
        out = dist / walk(speed)
        back = dist / (walk(speed) * CARRY)
        trip = out + back + PICKUP_OVERHEAD
        gain = (1 + rebirths * REBIRTH_GAIN) * (1 + training * TRAINING_BONUS)
        speed += out * gain  # speed grows only while running (carrying counts too)
        speed += back * gain
        coins += income_rate() * trip
        t += trip
        boost = CANYON_BOOST if (zone >= CANYON_FROM and rng.random() < CANYON_SHARE) else 1
        rarity = roll(ZONES[zone - 1][2], boost, rng)
        entry = (rarity, t + HATCH[rarity])
        if len(pedestals) < capacity:
            pedestals.append(entry)
        else:
            weakest = min(range(len(pedestals)), key=lambda i: INCOME[pedestals[i][0]])
            if INCOME[rarity] > INCOME[pedestals[weakest][0]]:
                coins += INCOME[pedestals[weakest][0]] * SELL_SECONDS
                pedestals[weakest] = entry
        # buy pedestals
        while capacity - PEDESTALS_START < len(PEDESTAL_COSTS) and coins >= PEDESTAL_COSTS[capacity - PEDESTALS_START]:
            coins -= PEDESTAL_COSTS[capacity - PEDESTALS_START]
            capacity += 1
            milestones.setdefault(f"pedestal{capacity}", t)
        # training upgrade (after pedestals), keep a reserve for rebirth
        while training < TRAINING_MAX and coins >= TRAINING_BASE * TRAINING_GROWTH ** training * 2:
            coins -= TRAINING_BASE * TRAINING_GROWTH ** training
            training += 1
            milestones.setdefault(f"training{training}", t)
        # rebirth
        cost = REBIRTH_BASE * REBIRTH_GROWTH ** rebirths
        if speed >= REBIRTH_SPEED * (rebirths + 1) and coins >= cost:
            rebirths += 1
            milestones[f"rebirth{rebirths}"] = t
            speed, coins = 0.0, 0.0
        if verbose and t >= next_log:
            next_log += log_every
            mix = {}
            for r, _ in pedestals:
                mix[r] = mix.get(r, 0) + 1
            print(f"{t/60:6.0f} min | speed {speed:8.0f} | zone {zone} | coins {coins:12.0f} | "
                  f"income {income_rate():8.1f}/s | rebirths {rebirths} | pedestals {mix}")
    return milestones


if __name__ == "__main__":
    hours = float(sys.argv[1]) if len(sys.argv) > 1 else 4
    ms = simulate(hours)
    print("\nMilestones (minutes):")
    for k, v in sorted(ms.items(), key=lambda kv: kv[1]):
        print(f"  {k:10s} {v/60:7.1f}")
