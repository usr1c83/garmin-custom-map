#!/usr/bin/env python3
"""Translate the English TYP strings of the OpenTopoMap Garmin style into
Russian, in place. Called from fetch_style.sh right after the style is
fetched; idempotent (skips if Cyrillic is already present).

The text stays in the primary (0x04) string slot so it is shown regardless
of the device firmware language. The file is kept in UTF-8 — mkgmap
transcodes strings into the map code page (cp1251) at TYP compile time.

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
    "hut/hostel": "приют/хижина",
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
}


def main() -> None:
    path = sys.argv[1]
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()

    if re.search(r"String=0x04,[^\n]*[а-яА-Я]", text):
        print(f"[russify_typ] {path}: already russified, skipping")
        return

    missing = set()

    def repl(m: re.Match) -> str:
        eng = m.group(1).strip()
        ru = RU.get(eng.lower())
        if ru is None:
            missing.add(eng)
            return m.group(0)
        return f"String=0x04,{ru}"

    text, n = re.subn(r"String=0x04,([^\n]*)", repl, text)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"[russify_typ] {path}: {n} strings processed")
    if missing:
        print(f"[russify_typ] no translation for: {sorted(missing)}", file=sys.stderr)


if __name__ == "__main__":
    main()
