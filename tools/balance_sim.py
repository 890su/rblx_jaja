"""Source-backed balance comparison, not a prediction of player skill.

Export with scripts/export_balance_config.py, then pass --config, --before and
--out. Active policy: farthest unlocked zone, random pickup, configured arena
corridor, 6 seconds handling, no Robux/shop/AFK/events, keep strongest hatched
creatures active and incubate reserves in storage. Buys facilities, slots and
training; rebirths when eligible. Failure scenarios still spend a full trip.
Maze detours, menu skill and real combat must be measured in live playtests.
"""
import argparse
import json
import math
import random
import statistics
from pathlib import Path

ORDER = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"]


def probabilities(config, zone, boost=1):
    weights = zone["weights"]
    floor = next(r for r in ORDER if weights.get(r, 0) > 0) if config.get("boostAboveZoneFloor") else "Common"
    values = {r: weights.get(r, 0) * (1 if r == floor else boost) for r in ORDER}
    return {r: w / sum(values.values()) for r, w in values.items()}


def walk(config, speed):
    s = config["speed"]
    return min(s["BASE_WALKSPEED"] + s["WALKSPEED_COEFFICIENT"] * math.sqrt(max(0, speed)), s["WALKSPEED_CAP"])


def arena_pace(config, speed):
    a = config["arena"]
    return min(a["WALK_SPEED_MAX"], max(a["WALK_SPEED_MIN"], walk(config, speed) * a["WALK_SPEED_SHARE"]))


def zone_rows(config):
    rows, start = [], 0
    pace = walk(config, 2000)
    for index, zone in enumerate(config["zones"], 1):
        distance = 60 + start + zone["lengthStuds"] / 2
        start += zone["lengthStuds"]
        back = distance / (pace * config["speed"]["CARRY_MULTIPLIER"])
        if index >= config["arena"]["FROM_ORIGIN_ZONE"]:
            length = config["zones"][config["arena"]["FIELD_ZONE"] - 1]["lengthStuds"]
            back += length / arena_pace(config, 2000) - length / (pace * config["speed"]["CARRY_MULTIPLIER"])
        row = {"zone": index, "minimum": next(r for r in ORDER if zone["weights"].get(r, 0) > 0), "roundTripSecondsAtSpeed2000": distance / pace + back + 6}
        for boost in (1, 2, 6):
            p = probabilities(config, zone, boost)
            row[f"expectedIncomeBoost{boost}"] = sum(p[r] * config["rarity"][r]["incomePerSecond"] for r in ORDER)
        p = probabilities(config, zone)
        row["expectedHatchSeconds"] = sum(p[r] * config["rarity"][r]["hatchSeconds"] for r in ORDER)
        for horizon in (600, 1800):
            row[f"expectedCoinsAfter{horizon}sFromPickup"] = sum(p[r] * config["rarity"][r]["incomePerSecond"] * max(0, horizon - back - config["rarity"][r]["hatchSeconds"]) for r in ORDER)
        rows.append(row)
    return rows


def simulate(config, hours, seed, failure_rate):
    rng = random.Random(seed)
    e, s = config["economy"], config["speed"]
    specs = {x["key"]: x for x in config["upgrades"]}
    t = speed = coins = 0.0
    rebirths = training = 0
    capacity = e["PEDESTALS_START"]
    treadmill = warehouse = False
    # TutorialService grants this starter at the beginning.
    slots = [("Common", config["rarity"]["Common"]["hatchSeconds"], 1)]
    reserve, milestones = [], {}
    guarantee_used = False
    end = hours * 3600

    def income(item):
        return config["rarity"][item[0]]["incomePerSecond"] * item[2]

    def advance(seconds, moving=True):
        nonlocal t, speed, coins
        dt = min(seconds, end - t)
        multiplier = 1 + rebirths * e["REBIRTH_INCOME_BONUS"]
        coins += sum(income(x) * max(0, t + dt - max(t, x[1])) for x in slots) * multiplier
        if moving:
            speed += dt * s["GAIN_PER_SECOND"] * (1 + rebirths * s["REBIRTH_GAIN_BONUS"]) * (1 + training * e["TRAINING_BONUS"])
        t += dt

    def travel(distance, carrying=False, arena=False):
        while distance > 1e-6 and t < end - 1e-9:
            pace = arena_pace(config, speed) if arena else walk(config, speed) * (s["CARRY_MULTIPLIER"] if carrying else 1)
            dt = min(1, distance / pace, end - t)
            distance -= pace * dt
            advance(dt)

    def roll(zone):
        boost = config["canyons"]["RARITY_BOOST"] if zone >= config["canyons"]["FROM_ZONE"] and rng.random() < config["canyons"]["SPAWN_SHARE"] else 1
        value = rng.random()
        for r, chance in probabilities(config, config["zones"][zone - 1], boost).items():
            value -= chance
            if value <= 0:
                return r
        return ORDER[-1]

    trips = delivered = 0
    while t < end:
        zone = 1
        for index, z in enumerate(config["zones"], 1):
            if speed >= z["speedGate"] and rebirths >= z["rebirthGate"]:
                zone = index
        milestones.setdefault(f"zone{zone}", t)
        distance = 60 + sum(z["lengthStuds"] for z in config["zones"][:zone - 1]) + config["zones"][zone - 1]["lengthStuds"] / 2
        travel(distance)
        if t >= end:
            break
        rarity = roll(zone)
        if zone == config["guarantee"]["zone"] and not guarantee_used:
            rarity = ORDER[max(ORDER.index(rarity), ORDER.index(config["guarantee"]["rarity"]))]
            guarantee_used = True
        golden = rng.random() < config["mutations"]["Golden"]["chance"]
        success = rng.random() >= failure_rate
        length = config["zones"][config["arena"]["FIELD_ZONE"] - 1]["lengthStuds"] if zone >= config["arena"]["FROM_ORIGIN_ZONE"] else 0
        travel(distance - length, carrying=True)
        if length:
            travel(length, arena=True)
        advance(6, moving=False)
        if t >= end:
            break
        trips += 1
        if not treadmill and coins >= specs["treadmill"]["installCost"]:
            coins -= specs["treadmill"]["installCost"]
            treadmill = True
            milestones["treadmill"] = t
        if len(slots) >= capacity and not warehouse and coins >= specs["warehouse"]["base"]:
            coins -= specs["warehouse"]["base"]
            warehouse = True
            milestones["warehouse"] = t
        if success and (len(slots) < capacity or warehouse):
            reserve.append((rarity, t + config["rarity"][rarity]["hatchSeconds"], config["mutations"]["Golden"]["incomeMultiplier"] if golden else 1))
            delivered += 1
        pool = slots + reserve
        pool.sort(key=lambda x: (x[1] <= t, income(x)), reverse=True)
        slots, reserve = pool[:capacity], pool[capacity:]
        cost = e["REBIRTH_BASE_COST"] * e["REBIRTH_COST_GROWTH"] ** rebirths
        if speed >= e["REBIRTH_SPEED_REQUIREMENT"] * (rebirths + 1) and coins >= cost:
            rebirths += 1
            milestones[f"rebirth{rebirths}"] = t
            speed = coins = 0.0
        else:
            costs = e["PEDESTAL_COSTS"]
            while capacity - e["PEDESTALS_START"] < len(costs) and coins >= costs[capacity - e["PEDESTALS_START"]]:
                coins -= costs[capacity - e["PEDESTALS_START"]]
                capacity += 1
                milestones.setdefault(f"pedestal{capacity}", t)
            cost = math.floor(e["TRAINING_BASE_COST"] * e["TRAINING_COST_GROWTH"] ** training)
            while training < e["TRAINING_MAX"] and coins >= cost * 2:
                coins -= cost
                training += 1
                cost = math.floor(e["TRAINING_BASE_COST"] * e["TRAINING_COST_GROWTH"] ** training)
    return {"milestones": milestones, "income": sum(income(x) for x in slots if x[1] <= t) * (1 + rebirths * e["REBIRTH_INCOME_BONUS"]), "rebirths": rebirths, "trips": trips, "delivered": delivered}


def summary(config, hours, seeds, failure_rate):
    runs = [simulate(config, hours, seed, failure_rate) for seed in range(seeds)]
    timings = {}
    for key in sorted({key for run in runs for key in run["milestones"]}):
        values = sorted(run["milestones"][key] / 60 for run in runs if key in run["milestones"])
        timings[key] = {"reached": len(values), "medianMinutesAmongReached": round(statistics.median(values), 2), "minMinutes": round(values[0], 2), "maxMinutes": round(values[-1], 2)}
    return {"failureRate": failure_rate, "runs": seeds, "hours": hours, "milestones": timings, "medianFinalIncome": statistics.median(run["income"] for run in runs)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--before", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--hours", type=float, default=3)
    parser.add_argument("--seeds", type=int, default=100)
    args = parser.parse_args()
    result = {"assumptions": __doc__}
    for label, path in (("before", args.before), ("after", args.config)):
        if not path:
            continue
        config = json.loads(path.read_text(encoding="utf-8"))
        result[label] = {"zones": zone_rows(config), "runs": [summary(config, args.hours, args.seeds, rate) for rate in (0, 0.2, 0.4)]}
        print(label.upper())
        for row in result[label]["zones"]:
            print(f"zone {row['zone']}: minimum {row['minimum']}, income {row['expectedIncomeBoost1']:.2f}/s, mean hatch {row['expectedHatchSeconds']:.1f}s")
        for run in result[label]["runs"]:
            print(f"failures {run['failureRate']:.0%}: first rebirth {run['milestones'].get('rebirth1')}; zone5 {run['milestones'].get('zone5')}")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
