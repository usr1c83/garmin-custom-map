#!/usr/bin/env python3
"""Russify the OpenTopoMap Garmin TYP: put Russian into every language slot
of each type so a Garmin device never falls back to the original German
(0x02) or English (0x04) POI-category labels. In place; idempotent.

The upstream TYP carries two localized strings per type, e.g.
    String=0x02,Bäckerei      (German)
    String=0x04,bakery        (English)
We translate the English one and copy that Russian value over the German
slot as well, so whichever language the firmware queries it gets Russian.
Strings we have no translation for keep their original text (mostly proper
nouns / already fine). File stays UTF-8; mkgmap transcodes to the map code
page (cp1251) at TYP compile time.

Usage: russify_typ.py path/to/opentopomap.txt
"""
import re
import sys

RU = {
    "bakery": "пекарня",
    "bank": "банк",
    "barrier": "барьер",
    "border": "граница",
    "broad-leaved forest": "лиственный лес",
    "broadleaf tree": "лиственное дерево",
    "building": "здание",
    "bus stop": "автобусная остановка",
    "cafe": "кафе",
    "camping": "кемпинг",
    "castle": "замок",
    "cave": "пещера",
    "cemetery": "кладбище",
    "church": "церковь",
    "cliff": "обрыв",
    "communication mast": "мачта связи",
    "communications tower": "вышка связи",
    "conifer forest": "хвойный лес",
    "convenience": "магазин",
    "doctor/hospital": "врач/больница",
    "drinking water": "питьевая вода",
    "edge of the forest": "опушка леса",
    "exclusion zone": "запретная зона",
    "fast food": "фастфуд",
    "fence": "забор",
    "ferry": "паром",
    "footway": "пешеходная дорожка",
    "hut": "хижина",
    "hut/hostel": "приют/хостел",
    "information": "информация",
    "meadow": "луг",
    "memorial": "памятник",
    "mill": "мельница",
    "mixed forest": "смешанный лес",
    "motorway": "автомагистраль",
    "observation tower": "смотровая вышка",
    "parking": "парковка",
    "pedestrian zone": "пешеходная зона",
    "pharmacy": "аптека",
    "phone": "телефон",
    "pinale": "скала",
    "power line": "ЛЭП",
    "primary street": "главная дорога",
    "pub": "паб",
    "rail": "железная дорога",
    "railway tunnel": "ж/д тоннель",
    "recycling": "приём вторсырья",
    "restaurant": "ресторан",
    "restaurant (american)": "ресторан (американский)",
    "restaurant (asian)": "ресторан (азиатский)",
    "restaurant (barbecue)": "ресторан (гриль)",
    "restaurant (british)": "ресторан (британский)",
    "restaurant (chinese)": "ресторан (китайский)",
    "restaurant (french)": "ресторан (французский)",
    "restaurant (german)": "ресторан (немецкий)",
    "restaurant (indian)": "ресторан (индийский)",
    "restaurant (international)": "ресторан (интернациональный)",
    "restaurant (italian)": "ресторан (итальянский)",
    "restaurant (mexican)": "ресторан (мексиканский)",
    "restaurant (pizza)": "пиццерия",
    "restaurant (sea food)": "ресторан (морепродукты)",
    "restaurant (steaks)": "ресторан (стейки)",
    "restroom": "туалет",
    "river": "река",
    "runway": "ВПП",
    "sand/beach": "песок/пляж",
    "scrubs": "кустарник",
    "sea": "море",
    "shelter": "укрытие",
    "sports field": "спортплощадка",
    "steps": "лестница",
    "stream": "ручей",
    "supermarket": "супермаркет",
    "swimming": "бассейн",
    "tower": "башня",
    "trunk": "магистраль",
    "water tower": "водонапорная башня",
    "wind turbine": "ветрогенератор",
    "wine": "виноградник",
    "built-up area": "застройка",
    # German-only strings that have no English counterpart in a block
    "badestelle": "пляж",
    "schutzhütte": "укрытие",
    "bebauung": "застройка",
}

_missing = set()


def translate(value: str) -> str:
    v = value.strip()
    if re.search(r"[А-Яа-яЁё]", v):   # already Russian
        return v
    ru = RU.get(v.lower())
    if ru is None:
        _missing.add(v)
        return v
    return ru


def process_block(lines):
    # Russian value for this type = translated English (0x04) if present,
    # else translated German (0x02).
    ru_val = None
    for ln in lines:
        m = re.match(r"\s*String=0x04,(.*)$", ln)
        if m:
            ru_val = translate(m.group(1))
    if ru_val is None:
        for ln in lines:
            m = re.match(r"\s*String=0x02,(.*)$", ln)
            if m:
                ru_val = translate(m.group(1))

    out = []
    for ln in lines:
        m = re.match(r"(\s*)String=0x0[24],(.*)$", ln)
        if m and ru_val is not None:
            out.append(f"{m.group(1)}{'String=0x04,'}{ru_val}"
                       if "0x04" in ln else f"{m.group(1)}String=0x02,{ru_val}")
        else:
            out.append(ln)
    return out


def main() -> None:
    path = sys.argv[1]
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()

    out, block, in_block = [], [], False
    for ln in lines:
        if re.match(r"\s*\[_", ln):
            in_block, block = True, [ln]
        elif re.match(r"\s*\[end\]", ln) and in_block:
            block.append(ln)
            out.extend(process_block(block))
            in_block, block = False, []
        elif in_block:
            block.append(ln)
        else:
            out.append(ln)
    if in_block:               # unterminated block, keep as-is
        out.extend(block)

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    ru02 = sum(1 for l in out if re.match(r"\s*String=0x02,.*[А-Яа-яЁё]", l))
    ru04 = sum(1 for l in out if re.match(r"\s*String=0x04,.*[А-Яа-яЁё]", l))
    print(f"[russify_typ] {path}: Russian strings — 0x02:{ru02} 0x04:{ru04}")
    if _missing:
        print(f"[russify_typ] no translation for: {sorted(_missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()
