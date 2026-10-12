#!/usr/bin/env python3
"""Writes the package's declarations from Mednafen's own tables.

    build/meson-native/run-native --describe > describe.json
    waterbox/gen-config.py describe.json [out folder]

`run-native --describe` prints, for each of the four systems, every port,
every device a port takes, every button, axis and switch of each device, and
every setting, as Mednafen's source defines them. machines.json holds what is
written by hand: Chimera's names for the systems, which port is which player,
a control's name where Mednafen's own would collide, and the settings a
project may set with their descriptions.

From the two this writes, into the out folder (waterbox/ by default):

  panel.inc              the controls, compiled into the core
  waterbox.config        the package's declaration, minus what
                         build-package.sh stamps in
  default_keybinds.json  the keys the first player's pad starts on

The test script runs this again and fails when the three files are not what
it writes, so they cannot drift from Mednafen or from machines.json.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# the letters given to buttons that asked for none, in this order
SPARE = "EFGHIJKMNOPQTVWabcdefghijkmnopqtuwxyz0123456789!#$%&*+-=?@~;:,/"
ALL_CAPS = re.compile(r"^[A-Z]{2,}$")
# capitals that are not a word to put in lower case
KEEP = {"II", "III", "IV", "VI", "AF"}


def clean(text):
    """Mednafen's name of an input, as Chimera can show and store it: no
    arrows or other signs outside ASCII, nothing in brackets, capitals only
    at the start of a word."""
    text = re.sub(r"\(.*?\)", " ", text or "")
    text = "".join(c for c in text if 32 <= ord(c) < 127)
    # "Comma ," and "Grave `" name the sign after the word
    text = re.sub(r"\s[^\w\s]+$", "", text.strip())
    words = []
    for w in text.replace("/", " / ").split():
        words.append(w.capitalize() if ALL_CAPS.match(w) and w not in KEEP else w)
    return " ".join(words).replace(" / ", "/").strip(" /")


def label_of(text):
    """Mednafen's own words for an input of one device, for the hint Chimera
    shows over a column: brackets kept, signs outside ASCII dropped."""
    text = "".join(c for c in (text or "") if 32 <= ord(c) < 127)
    text = re.sub(r"\(\s*\)", "", text)
    text = re.sub(r"\s+\)", ")", re.sub(r"\(\s+", "(", text))
    text = re.sub(r"(\w)\(", r"\1 (", text)
    return re.sub(r"\s+", " ", text).strip()


def axis_tail(inp):
    neg = (inp.get("negative") or "").upper()
    if "LEFT" in neg:
        return " X"
    if "UP" in neg or "FORE" in neg:
        return " Y"
    return ""


def initials(name):
    return "".join(w[0] for w in re.findall(r"[A-Za-z0-9]+", name)).upper()


def fail(text):
    sys.exit("gen-config: " + text)


def controls_of(system, hand):
    """The buttons and the axes of one system, in the order they are declared,
    each with the device inputs it stands for."""
    buttons, axes = [], []
    by_key = {}
    names = hand.get("names", {})
    family = hand.get("family", {})
    only_on = hand.get("deviceOnlyOn", {})
    skip = set(hand.get("skip", []))
    used = set()

    for pi, port in enumerate(system["ports"]):
        if port["short"] not in hand["players"]:
            fail("%s: machines.json says nothing of port %s" % (system["machine"], port["short"]))
        player = hand["players"][port["short"]]
        prefix = "P%d " % player if player else ""
        for dev in port["devices"]:
            if dev["short"] in only_on and port["short"] not in only_on[dev["short"]]:
                continue
            fam = family.get(dev["short"], "")
            seen = {}
            for inp in dev["inputs"]:
                kind = inp["type"]
                if kind in ("status", "padding", "rumble", "bytes"):
                    continue
                sname = inp["sname"]
                if dev["short"] + "." + sname in skip:
                    used.add(dev["short"] + "." + sname)
                    continue
                occ = seen.get((sname, kind), 0)
                seen[(sname, kind)] = occ + 1
                positions = inp.get("positions", [])
                if kind in ("button", "reset"):
                    is_axis, mode, lo, hi, rest = False, "b", 0, 1, 0
                elif kind == "switch" and len(positions) == 2:
                    is_axis, mode, lo, hi, rest = False, "s", 0, 1, 0
                    if inp["default"] != 0:
                        fail("%s %s: a two-way switch that rests in its second position" % (dev["short"], sname))
                elif kind == "switch":
                    is_axis, mode, lo, hi, rest = True, "n", 0, len(positions) - 1, inp["default"]
                elif kind == "axis":
                    is_axis, mode, lo, hi, rest = True, "x", -32768, 32767, 0
                elif kind == "analogbutton":
                    is_axis, mode, lo, hi, rest = True, "u", 0, 65535, 0
                elif kind == "relative":
                    is_axis, mode, lo, hi, rest = True, "r", -255, 255, 0
                elif kind in ("pointerx", "pointery"):
                    is_axis, mode, lo, hi, rest = True, "p" if kind == "pointerx" else "q", 0, 65535, 32768
                else:
                    fail("%s %s: an input of a type this script does not know (%s)" % (dev["short"], sname, kind))

                # the hand-given name, most particular first
                tries = []
                if fam:
                    tries += ["%s.%s.%d" % (fam, sname, occ), "%s.%s" % (fam, sname)]
                else:
                    tries += ["%s.%s" % (dev["short"], sname)]
                    if kind == "analogbutton":
                        tries.append(sname + ".analog")
                    elif not is_axis or kind == "switch":
                        tries.append(sname)
                bare = None
                for t in tries:
                    if t in names:
                        bare = names[t]
                        used.add(t)
                        break
                if bare is None:
                    bare = clean(inp["name"])
                    if kind in ("axis", "relative"):
                        bare += axis_tail(inp)
                    elif kind == "analogbutton":
                        bare += " Analog"
                    elif kind == "switch" and len(positions) == 2:
                        second = clean(positions[1]["name"])
                        bare = (bare + " " + second).strip()
                    if fam:
                        bare = fam + " " + bare
                if not bare:
                    fail("%s %s: no name is left of \"%s\"; give one in machines.json" % (dev["short"], sname, inp["name"]))

                key = (pi, fam, sname, is_axis, occ, bare)
                control = by_key.get(key)
                if control is None:
                    control = {"name": prefix + bare, "bare": bare, "family": fam, "player": player, "port": pi,
                               "min": lo, "max": hi, "neutral": rest, "bindings": []}
                    by_key[key] = control
                    (axes if is_axis else buttons).append(control)
                elif (control["min"], control["max"]) != (lo, hi):
                    fail("%s: %s is shared by devices that give it different ranges" % (system["machine"], control["name"]))
                label = label_of(inp["name"])
                if kind in ("axis", "relative") and inp.get("negative"):
                    label = "%s: %s / %s" % (label, label_of(inp["negative"]), label_of(inp["positive"]))
                if kind == "switch":
                    label = "%s: %s" % (label, " / ".join(label_of(p["name"]) for p in positions))
                control["bindings"].append({"device": dev["short"], "input": inp["index"], "sname": sname, "mode": mode,
                                            "label": "" if clean(label).lower() == bare.lower() else label})

    for group, what in ((buttons, "buttons"), (axes, "axes")):
        seen = {}
        for c in group:
            if c["name"] in seen:
                fail("%s: two %s are called \"%s\"; tell them apart in machines.json" % (system["machine"], what, c["name"]))
            seen[c["name"]] = True
    for t in list(names) + list(skip):
        if t not in used:
            fail("%s: machines.json names \"%s\", which Mednafen does not have" % (system["machine"], t))
    return buttons, axes


def letters_of(buttons, hand):
    """A letter for every button (what it writes into a movie's text) and a
    column header for those one letter does not tell apart."""
    letters, headers = {}, {}
    taken, heads = {}, {}
    wanted = hand.get("letters", {})
    header_of = hand.get("headerOf", {})
    for b in buttons:
        used = taken.setdefault(b["player"], set())
        letter = wanted.get(b["bare"])
        natural = letter is not None and letter not in used
        if not natural:
            letter = next((ch for ch in SPARE if ch not in used), None)
            if letter is None:
                # more buttons than characters (a keyboard): an entry is read
                # by position, so letters may repeat; the headers do not
                letter = SPARE[len(used) % len(SPARE)]
        used.add(letter)
        letters[b["name"]] = letter
        if natural and b["bare"] not in header_of:
            continue
        head = header_of.get(b["bare"])
        if head is None:
            fam = b["family"]
            words = b["bare"][len(fam) + 1:] if fam and b["bare"].startswith(fam + " ") else b["bare"]
            head = re.sub(r"[^A-Za-z0-9/+-]", "", words.replace("Keypad", "Kp").replace("Left ", "L").replace("Right ", "R"))
            if fam == "Key":
                # a key's own name; one character would read as a pad's button
                head = ("k" + head if len(head) == 1 else head)[:8]
            elif fam:
                head = (fam[0] + "-" + head)[:8]
            head = head[:8] or initials(b["bare"])
        seen = heads.setdefault(b["player"], set())
        base, n = head, 2
        while head in seen or (len(head) == 1 and head in used):
            tail = str(n)
            head = base[:8 - len(tail)] + tail
            n += 1
        seen.add(head)
        headers[b["name"]] = head
    return letters, headers


def axis_headers(axes):
    out, seen = {}, set()
    for a in axes:
        head = ("%s%s" % (a["player"] or "", initials(a["bare"])))[:5]
        base, n = head, 2
        while head in seen:
            tail = str(n)
            head = base[:5 - len(tail)] + tail
            n += 1
        seen.add(head)
        out[a["name"]] = head
    return out


def number(text):
    return int(text, 0)


def setting_of(decl, system, machine):
    table = {s["name"]: s for s in system["settings"]}
    if decl["name"] not in table:
        fail("%s: machines.json sets \"%s\", which Mednafen does not have" % (machine, decl["name"]))
    m = table[decl["name"]]
    out = {"name": decl["name"], "display": decl["display"], "description": decl["description"]}
    if m["type"] == "bool":
        out["type"] = "bool"
        out["default"] = m["default"] not in ("0", "")
    elif m["type"] in ("int", "uint"):
        out["type"] = "int"
        out["min"] = number(m["minimum"])
        out["max"] = number(m["maximum"])
        out["default"] = number(m["default"])
    elif m["type"] == "enum":
        have = [o["value"] for o in m["options"]]
        options = decl.get("options") or have
        for o in options:
            if o not in have:
                fail("%s: \"%s\" is not a value of %s" % (machine, o, decl["name"]))
            if not all(32 <= ord(c) < 127 for c in o):
                fail("%s: a value of %s is not ASCII; list the ones to offer in machines.json" % (machine, decl["name"]))
        if m["default"] not in options:
            fail("%s: the default of %s is not among the values offered" % (machine, decl["name"]))
        out["type"] = "enum"
        out["options"] = options
        out["default"] = m["default"]
    else:
        fail("%s: %s is of a type (%s) this script does not offer" % (machine, decl["name"], m["type"]))
    out["when"] = [machine]
    return out


def cstr(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    with open(sys.argv[1]) as f:
        systems = {s["machine"]: s for s in json.load(f)}
    with open(os.path.join(HERE, "machines.json")) as f:
        hand = json.load(f)
    out = sys.argv[2] if len(sys.argv) > 2 else HERE

    machine_names = [m["machine"] for m in hand["machines"]]
    if sorted(machine_names) != sorted(systems):
        fail("machines.json has %s and the core has %s" % (machine_names, sorted(systems)))

    settings = [{
        "name": "machine", "display": "Machine",
        "description": "Which console this project is for. Everything else depends on it, so changing it restarts the core.",
        "type": "enum", "options": machine_names, "default": machine_names[0],
    }]
    machines, binds, system_names = [], {}, {}
    rows = []
    total_b = total_a = 0
    for m in hand["machines"]:
        system = systems[m["machine"]]
        buttons, axes = controls_of(system, m)
        letters, headers = letters_of(buttons, m)
        heads = axis_headers(axes)
        total_b += len(buttons)
        total_a += len(axes)
        system_names[m["id"]] = m["label"]

        for kind, group in (("B", buttons), ("A", axes)):
            for i, c in enumerate(group):
                for b in c["bindings"]:
                    rows.append("PANEL_ROW(%s, '%s', %d, %d, %s, %d, %s, '%s', %s, %s)" % (
                        cstr(m["machine"]), kind, i, c["port"], cstr(b["device"]), b["input"], cstr(b["sname"]),
                        b["mode"], cstr(c["name"]), cstr(b["label"])))
        taps = m.get("taps")
        if taps:
            for s in taps["settings"]:
                if s not in {x["name"] for x in system["settings"]}:
                    fail("%s: the multitap setting %s is not Mednafen's" % (m["machine"], s))
            rows.append("PANEL_TAPS(%s, %s, %s, %s, %d)" % (cstr(m["machine"]), cstr(taps["rule"]), cstr(taps["settings"][0]),
                                                           cstr(taps["settings"][1]), taps.get("portsOnTap", 0)))

        # what is plugged into each port a player has, when there is a choice
        only_on = m.get("deviceOnlyOn", {})
        for port in system["ports"]:
            player = m["players"][port["short"]]
            devices = [d["short"] for d in port["devices"]
                       if not (d["short"] in only_on and port["short"] not in only_on[d["short"]])]
            if not player or len(devices) < 2:
                continue
            if port["default"] not in devices:
                fail("%s: the default device of %s is not among its devices" % (m["machine"], port["short"]))
            settings.append({
                "name": "%s.input.%s" % (system["shortname"], port["short"]),
                "display": m["portSetting"]["display"] % player,
                "description": m["portSetting"]["description"] % player,
                "type": "enum", "options": devices, "default": port["default"], "when": [m["machine"]],
            })
        for decl in m.get("settings", []):
            settings.append(setting_of(decl, system, m["machine"]))

        machines.append({
            "id": m["id"], "label": m["label"], "when": [m["machine"]],
            "input": {
                "name": m["controller"],
                "buttons": [b["name"] for b in buttons],
                "mnemonics": letters,
                "headers": headers,
                "axes": [{"name": a["name"], "min": a["min"], "max": a["max"], "neutral": a["neutral"], "header": heads[a["name"]]}
                         for a in axes],
            },
            "virtualWidth": m["virtualWidth"], "virtualHeight": m["virtualHeight"],
            "extensions": m["extensions"],
        })
        keys = m.get("keys", {})
        for k in keys:
            if k not in letters:
                fail("%s: a key is given to \"%s\", which is not a button" % (m["machine"], k))
        binds[m["controller"]] = {b["name"]: keys.get(b["name"], "") for b in buttons}
    settings += hand.get("commonSettings", [])

    with open(os.path.join(out, "panel.inc"), "w") as f:
        f.write("// The controls of the four systems: one row for each input of each device\n"
                "// that a control of the package stands for. Written by gen-config.py from\n"
                "// run-native --describe and machines.json; cinterface.cpp compiles it in.\n"
                "// Do not edit.\n"
                "// PANEL_ROW(machine, B or A, index in the machine's list, port, device,\n"
                "//           input in the device's table, its Mednafen name, how the value\n"
                "//           is written, the control's name, this device's own words for it)\n")
        f.write("\n".join(rows) + "\n")

    config = {
        "coreName": "Mednafen",
        "author": "The Mednafen Team; chimera port by Sergio Martin",
        "url": "https://github.com/ToolAssisted-run/chimera-core-mednafen",
        "romFile": "disc",
        "deterministic": True,
        "suggestSettings": True,
        "gameFirmware": True,
        "memoryLayoutMiB": [512, 8, 16, 64, 512],
        "_memoryLayoutMiB_note": "sbrk, sealed, invisible, plain, mmap. This is room, not use: memory is taken as a machine touches it. A Saturn's savestate is about 7 MB.",
        "video": {
            "_comment": "The BUFFER CAPACITY. Each system has its own picture size and the Saturn changes its own with the game's video mode, so the live size comes from GetVideoWidth/Height every frame.",
            "width": 2048, "height": 1024, "virtualWidth": 320, "virtualHeight": 240,
            "vsyncNumerator": 60000, "vsyncDenominator": 1000,
            "_vsync_note": "Each system has its own refresh rate, and a PAL Saturn another; GetVsyncNumerator reports the running machine's, in thousandths of a hertz.",
            "getBgra": "GetVideoBgra",
        },
        "audio": {
            "_comment": "Mednafen's mix of the machine's sound, converted by Mednafen to 48 kHz stereo.",
            "rate": 48000, "samplesPerFrame": 4096, "channels": 2, "get": "GetAudio",
        },
        "lag": {"inputWasRead": "InputWasRead"},
        "systemNames": system_names,
        "settings": settings,
        "_machines_note": "ONE core.wbx, four systems. What they share is above; what makes them different machines is below, and the 'machine' setting picks one. A machine's controls are every input of every device its ports take, by Mednafen's own tables: the ones of what is plugged in are shown and the rest leave the input roll.",
        "machineSetting": "machine",
        "machines": machines,
        "_firmware_note": "The firmware that does not depend on the game. Which BIOS a Saturn starts with depends on the disc's region, so the core says it for each game (gameFirmware): saturn_jp.bin or saturn_na_eu.bin, and the ROM cartridge of the two games sold with one.",
        "firmware": hand.get("firmware", []),
    }
    with open(os.path.join(out, "waterbox.config"), "w") as f:
        json.dump(config, f, indent=1)
        f.write("\n")

    keybinds = {
        "_comment": ["The first player's pad of each system on the arrows and the keys around Z as well as the first game pad. Everything else ships unbound."],
        "AllTrollers": binds,
        "AllTrollersAutoFire": {name: {} for name in binds},
        "AllTrollersAnalog": {name: {} for name in binds},
    }
    with open(os.path.join(out, "default_keybinds.json"), "w") as f:
        json.dump(keybinds, f, indent=1)
        f.write("\n")
    print("%d buttons and %d axes over %d systems, %d settings" % (total_b, total_a, len(machines), len(settings)))


if __name__ == "__main__":
    main()
