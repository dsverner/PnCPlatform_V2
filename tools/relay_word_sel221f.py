"""relay_word_sel221f.py - the SEL-221F Relay Word as data (#215), from the instruction manual.

The owner, 2026-09-20: "create a logic editor for the SELOGIC settings ... an editor to assist the user in selecting
the appropriate bits. This editor should be selected through the use of an edit button on the setting."

Source: SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207
(Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf) - the same document
tools/template_sel221f.py cites page by page for the settings. Every string below is the manual's, with its page:
  2-5   Table 2.1 Relay Word - three rows of eight bit groups
  2-20  the Relay Word rows; "1 indicates a picked up element or true logic condition"
  2-21  Table 2.4 Relay Word Bit Summary - the meaning of each bit
  3-14  SHOWSET shows the ten masks as hex, one column per mask, three rows; the row -> bits map
  3-15  Table 3.3 hex/binary; "A4 -> 1010 0100" laid over 67N 51NP 51NT 50NG 50P 50H IN1 REJO,
        so the LEFT bit of a row is the most significant bit of its byte
  3-20  LOGIC n - the ten masks and their names; "one selects and zero deselects a member of the mask"
  5-32  Programmable Output Contact Mask Settings - which masks control what
  5-33..5-38  each mask: purpose, typical bits, the example mask with its hex, and the notes
  5-38  Relay Word Bits Intended for Relay Testing

One source, two outputs: the seed (a Program.RelayWord definition, Effective) and the reviewable table.
Run: python tools/relay_word_sel221f.py
"""
import hashlib, io, json, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NL = "\r\n"
KEY = "RELAY_WORD_SEL_221F"
SETTINGS_TEMPLATE = "SETTINGS_TEXT_SEL_221F"
SOURCE = "SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date code 981207 (Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf)"

# Table 2.4 Relay Word Bit Summary (2-21); the row order is Table 2.1 (2-5) and the LOGIC display (3-20)
ROWS = [
    [
        ("Z1P",  "Zone 1 phase fault, instantaneous output (set by Z1%)"),
        ("Z1G",  "Zone 1 ground fault, instantaneous output (set by Z1%)"),
        ("Z2PT", "Zone 2 phase fault, time delayed (set by Z2% and Z2DP)"),
        ("Z2GT", "Zone 2 ground fault, time delayed (set by Z2% and Z2DG)"),
        ("Z3",   "Zone 3 phase or ground fault, instantaneous output (set by Z3%)"),
        ("Z3T",  "Zone 3 phase or ground fault, time delayed (set by Z3% and Z3D)"),
        ("3P21", "Three-phase fault condition detected by phase distance relays"),
        ("32Q",  "Negative-sequence directional element"),
    ],
    [
        ("67N",  "Residual instantaneous overcurrent (set by 67NP and 67NTC)"),
        ("51NP", "Pickup of residual time-O/C (set by 51NP and 51NTC)"),
        ("51NT", "Timeout of residual time-overcurrent element"),
        ("50NG", "Sensitive residual or phase overcurrent condition (set by 50NG)"),
        ("50P",  "Phase overcurrent condition (set by 50P)"),
        ("50H",  "High-set phase overcurrent condition (set by 50H)"),
        ("IN1",  "Logic Input 1 (use for direct trip, reclose initiate/cancel, etc.)"),
        ("REJO", "Remote-end-just-opened condition"),
    ],
    [
        ("LOP",  "Loss-of-potential condition"),
        ("TRIP", "Follows trip condition"),
        ("27S",  "Synchronizing undervoltage condition (Tests VS against VLO setting)"),
        ("27P",  "Polarizing undervoltage condition (Tests VP1 against VLO setting)"),
        ("59S",  "Synchronizing overvoltage condition (Tests VS against VHI setting)"),
        ("59P",  "Polarizing overvoltage condition (Tests VP1 against VHI setting)"),
        ("SSC",  "Synchronization-supervised condition (set by 25DV, 25T, SYNCP)"),
        ("VSC",  "Voltage-supervised condition (set by PSVC for disable/LSDP/LPDS/either)"),
    ],
]
ROW_CITE = "2-21 (Table 2.4); 2-5 (Table 2.1)"
FOOTNOTE = "VP1 = positive-sequence voltage applied to the polarizing voltage inputs (2-21)."

VARIANTS = [
    {"models": "SEL-221F-3/121F-3, SEL-221F-4", "row": 3, "bit": 2, "code": "BFT",
     "note": "The TRIP bit is replaced by the BFT bit in the SEL-221F-3/121F-3 and SEL-221F-4 models.", "cite": "5-33 (Note 2); 2-51"},
]

TESTING = {"bits": ["3P21", "32Q", "51NP", "50NG", "50P", "27S", "27P", "59S", "59P"],
           "note": "The following bits are included to assist in relay testing: 3P21, 32Q, 51NP, 50NG, 50P, 27S, 27P, 59S, 59P. This does not exclude the use of these bits in one of four trip or programmable output contacts if required by your application.",
           "cite": "5-38"}

NEVER_TRIP = "Never mask the TRIP bit into the {m} logic mask. This causes an undesirable seal-in of TRIP output contacts."

# (code, name (3-20), purpose, caution, typical bits, never bits, example hex, cite)
MASKS = [
    ("MTU", "Mask for trip unconditional",
     "Elements selected in this mask do not require that external conditions be met to initiate a trip. If an element masked in the MTU logic mask picks up, the TRIP output contacts close. You must be certain that elements used in this mask coordinate with other system protective devices.",
     "Unless your application permits, it is not advisable to set non-directional overcurrent elements in the MTU logic mask.",
     ["Z1P", "Z1G", "67N", "51NT", "Z2PT", "Z2GT", "Z3T", "IN1"],
     ["TRIP"], "F4 A2 00", "5-33"),
    ("MPT", "Mask for trip with permissive-trip asserted",
     "The relay closes the TRIP output when the Permissive Trip (PT) input is asserted or the REJO condition is enabled and asserted and elements selected in the MPT mask pick up.",
     "As with the MTU logic mask, it is not advisable to mask non-directional elements in the MPT logic mask unless your application permits.",
     ["Z3"],
     ["TRIP"], "08 00 00", "5-33, 5-34"),
    ("MTB", "Mask for trip with block-trip unasserted",
     "The relay closes the TRIP output when the Block Trip (BT) input is not asserted and elements selected in this mask pick up. BT input assertion serves as an external qualifying condition.",
     "As with the MTU logic mask, it is not advisable to mask nondirectional elements in the MTB logic mask unless your application permits.",
     [],
     ["TRIP"], "00 00 00", "5-34"),
    ("MTO", "Mask for trip with breaker open",
     "The relay closes the TRIP output when the 52BT element is asserted and elements selected in this mask pick up. The 52BT element is a time delayed, inverted follower of the 52A input. This tripping mask differs from the MTU, MPT, and MTB tripping masks because it is acceptable to mask sensitive nondirectional elements into MTO in certain applications.",
     "Such masking is advisable except in applications where the line breaker is closed into a line energized from the remote terminal (i.e. synchronized closures).",
     ["Z1P", "Z1G", "67N", "50H", "Z3"],
     ["TRIP"], "FC A4 00", "5-35"),
    ("MA1", "Mask for A1 relay control",
     "Any element listed in the Relay Word may be masked into these programmable output contacts. Guidelines to follow when masking elements into each mask depends on equipment connected to the contact outputs. If external equipment is not connected to the contact outputs, you may set elements in these masks to enhance event report analysis.",
     "", ["SSC"], [], "00 00 02", "5-35, 5-36"),
    ("MA2", "Mask for A2 relay control",
     "Any element listed in the Relay Word may be masked into these programmable output contacts. The A2 output contact asserts when the VSC bit asserts, indicating that voltage conditions have fulfilled the voltage checking requirements.",
     "", ["VSC"], [], "00 00 01", "5-35, 5-36"),
    ("MA3", "Mask for A3 relay control",
     "Any element listed in the Relay Word may be masked into these programmable output contacts. In the manual's example the A3 output contact asserts when any reclose initiate condition set in the MRI logic mask is fulfilled.",
     "", ["Z1P", "Z1G", "Z2PT", "Z2GT", "67N"], [], "F0 80 00", "5-35, 5-36"),
    ("MA4", "Mask for A4 relay control",
     "Any element listed in the Relay Word may be masked into these programmable output contacts. In the manual's example the A4 output contact asserts when any reclose cancel condition set in the MRC logic mask is fulfilled.",
     "", ["Z3T", "51NT"], [], "04 20 00", "5-35, 5-37"),
    ("MRI", "Mask for reclose initiate",
     "If an element masked in the MRI mask is asserted when the TRIP output contacts close, reclosing is initiated unless a reclose cancel condition occurs. Reclose initiation is subordinate to reclose cancel.",
     "", ["67N", "Z1P", "Z1G", "Z2PT", "Z2GT"], [], "F0 80 00", "5-37"),
    ("MRC", "Mask for reclose cancel",
     "If an element masked in the MRC mask is asserted when the TRIP output contacts close, reclosing is cancelled even if a reclose initiate condition occurs. Reclose initiation is subordinate to reclose cancellation.",
     "", ["Z3T", "51NT"], [], "04 20 00", "5-37, 5-38"),
]


# #219 (2026-09-21): the ELEMENT MAP — the owner: "a rational 'section' for each of the protective elements being used" and the
# settings sheet grouped the same way ("Zone 1, Zone 2 etc. with all appropriate settings"; overcurrent "broken up into phase,
# ground"); the settings that SUPERVISE an element handled explicitly. The grain agreed: the fifteen capabilities
# (sel-221f.capabilities.md, #181/#182) with the Relay Word bits beneath them as the element outputs. Each element: its
# capability, its outputs (bits above), the settings it OWNS (decided in its section), and what SUPERVISES it — from the
# manual's own logic equations (2-18 "Distance Relay Logic", 2-24 "Negative-Sequence Directional Element"), never from memory:
#   Z1P = (21AB1·50AP·50BP + 21BC1·50BP·50CP + 21CA1·50CP·50AP) · FDS · NOT(LOP·LOPE=Y,1,2,3)      FDS = 3P21 + 32Q
#   Z1G = (21AG1·50AG + 21BG1·50BG + 21CG1·50CG) · 50N · FDS · NOT(LOP·LOPE)                     (Z2, Z3 alike)
#   67N = 67NP · [32Q + (LOP·LOPE) + NOT(67NTC)]      51NP = 51N pickup · [32Q + (LOP·LOPE) + NOT(51NTC)]
# (key, capability, name, outputs, owned settings, supervised-by [(by, how, cite)], cite)
SUP_DIST = [
    ("50P",  "the phase distance elements require the phase overcurrent 50AP/50BP/50CP (the 50P setting) on the faulted phases", "2-18"),
    ("50NG", "the ground distance elements require 50AG/50BG/50CG and the residual 50N (the 50NG setting)", "2-18"),
    ("3P21|32Q", "forward-direction supervision FDS = 3P21 + 32Q; \"the negative-sequence directional elements always supervises the distance elements\"", "2-18; 2-24"),
    ("LOP",  "blocked by loss of potential when LOPE = Y, 1, 2 or 3", "2-18"),
]
ELEMENTS = [
    ("Z1",  "21",  "Zone 1 distance (phase and ground, instantaneous)", ["Z1P", "Z1G"], ["Z1%"], SUP_DIST, "2-18; 5-13"),
    ("Z2",  "21",  "Zone 2 distance (phase and ground, time delayed)", ["Z2PT", "Z2GT"], ["Z2%", "Z2DP", "Z2DG"], SUP_DIST, "2-18; 5-13"),
    ("Z3",  "21",  "Zone 3 distance (phase or ground; instantaneous for permissive schemes, time delayed for tripping)", ["Z3", "Z3T"], ["Z3%", "Z3D"], SUP_DIST, "2-18; 5-13"),
    ("50P", "50",  "Phase overcurrent, low set — supervises the phase distance elements", ["50P"], ["50P"], [], "2-3; 2-18; 5-16"),
    ("50NG","50N", "Sensitive residual overcurrent — supervises the ground distance elements", ["50NG"], ["50NG"], [], "2-3; 2-18; 5-16"),
    ("50H", "50",  "Phase overcurrent, high set (switch-onto-fault tripping)", ["50H"], ["50H"],
            [("52BT", "trips through the MTO mask while the 52BT element is asserted after the breaker closes", "5-35")], "2-4; 5-16"),
    ("51N", "51N", "Residual time-overcurrent", ["51NP", "51NT"], ["51NP", "51NC", "51NTD", "51NTC"],
            [("32Q", "directionally supervised by 32Q when 51NTC = Y (and by loss of potential when LOPE is set): 51NP = 51N pickup · [32Q + (LOP·LOPE) + NOT(51NTC)]", "2-18")], "2-3; 5-17"),
    ("67N", "67N", "Residual instantaneous overcurrent, directional", ["67N"], ["67NP", "67NTC"],
            [("32Q", "67N = 67NP · [32Q + (LOP·LOPE) + NOT(67NTC)]", "2-18")], "2-3; 5-17"),
    ("32Q", "32Q", "Negative-sequence directional element", ["32Q"], [], [], "2-3; 2-24"),
    ("LOP", "LOP", "Loss-of-potential detection", ["LOP"], ["LOPE"], [], "2-3; 2-17 (Table 2.3)"),
    ("79",  "79",  "Reclosing", [], ["79OI", "79RS"], [], "2-4; 5-14"),
    ("25",  "25",  "Synchronism and voltage checking (25, 27, 59)", ["27S", "27P", "59S", "59P", "SSC", "VSC"], ["PSVC", "27VLO", "59VHI", "25DV", "SYNCP", "25T", "VCT"], [], "2-4; 2-18; 5-14/5-15"),
    ("REJO","REJO","Remote-end-just-opened protection", ["REJO"], ["REJOE"], [], "2-4; 5-18"),
    ("SOTF","SOTF","Switch-onto-fault protection (52BT with the MTO mask)", [], ["52BT"], [], "2-4; 5-18; 5-35"),
    ("FAULTLOC", "FAULTLOC", "Fault locating (uses the line data R1, X1, R0, X0 and the line length)", [], ["LL"], [], "1-1; 1-4/1-5; 5-13"),
    ("50BF","50BF","Breaker failure (SEL-221F-3/121F-3 and SEL-221F-4 only)", ["BFT"], ["BFIN1", "BFTD"], [], "1-2; 2-50/2-51"),
]
# the settings that are no element's, in plain groups (the sheet and the rationale show them as such)
GROUPS = [
    ("ID",     "Identifier", ["ID"]),
    ("LINE",   "Line data (the distance characteristic: impedances and the maximum torque angle)", ["R1", "X1", "R0", "X0", "MTA"]),
    ("INPUTS", "Current and potential inputs", ["CTR", "PTR", "SPTR"]),
    ("TIMERS", "Miscellaneous timers", ["A1TP", "A1TD", "TDUR"]),
    ("COMMS",  "Communications", ["TIME1", "TIME2", "AUTO", "RINGS"]),
    ("MASKS",  "Logic masks", ["MTU", "MPT", "MTB", "MTO", "MA1", "MA2", "MA3", "MA4", "MRI", "MRC"]),
]


def document():
    return {
        "g": 1, "kind": "relayWord", "key": KEY, "name": "SEL-221F Relay Word",
        "settingsTemplate": SETTINGS_TEMPLATE, "source": SOURCE,
        "bitOrder": "The left bit of a row is the most significant bit of its byte: A4 -> 1010 0100 laid over 67N 51NP 51NT 50NG 50P 50H IN1 REJO (3-15). One selects and zero deselects a member of the mask (3-20).",
        "rows": [[{"code": c, "meaning": m, "cite": ROW_CITE} for (c, m) in row] for row in ROWS],
        "footnote": FOOTNOTE,
        "variants": VARIANTS,
        "testing": TESTING,
        "masks": {code: {"name": name, "purpose": purpose, "caution": caution, "typical": typical, "never": never,
                         "neverNote": NEVER_TRIP.format(m=code) if "TRIP" in never else "", "example": example, "cite": cite}
                  for (code, name, purpose, caution, typical, never, example, cite) in MASKS},
        # #219: the element map — the sheet's sub-groups and the rationale's sections, in this order
        "elements": [{"key": k, "capability": cap, "name": name, "outputs": outs, "settings": sets,
                      "supervisedBy": [{"by": by, "how": how, "cite": c} for (by, how, c) in sup], "cite": cite}
                     for (k, cap, name, outs, sets, sup, cite) in ELEMENTS],
        "groups": [{"key": k, "name": name, "settings": sets} for (k, name, sets) in GROUPS],
    }


def q(s):
    return "N'" + s.replace("'", "''") + "'"


def sql(doc):
    payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    note = "seed " + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
    L = [
        "-- GENERATED by tools/relay_word_sel221f.py - do not edit; edit the data there and regenerate.",
        "-- #215 (2026-09-20): the SEL-221F Relay Word as data, from the instruction manual (IM 981207): three rows of eight bits",
        "-- with each bit's meaning (2-21, Table 2.4), the byte order (3-15), the -3/-4 variant (TRIP -> BFT, 5-33), the bits meant for",
        "-- testing (5-38) and, for each of the ten logic masks, its purpose, typical bits, example and the manual's warnings (5-32..5-38).",
        "-- The Settings tab's mask editor reads this; another relay with masks is another definition. Idempotent and respectful of the",
        "-- Administrator, as Seed_config_Screens: a key an Administrator has edited is left alone.",
        "IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish",
        "GO",
        "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
        "DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @payload NVARCHAR(MAX) = " + q(payload) + ";",
        "DECLARE @note NVARCHAR(200) = " + q(note) + ";",
        "SELECT @e = EntityId FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.RelayWord' AND [DefinitionKey] = " + q(KEY) + " AND [IsDeleted] = 0;",
        "IF @e IS NULL",
        "    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.RelayWord', @DefinitionKey = " + q(KEY) + ", @Name = N'SEL-221F Relay Word', @Description = N'The 24 Relay Word bits of the SEL-221F and what each of its ten logic masks is for, from the instruction manual (IM 981207).', @ActorId = @author, @EntityId = @e OUTPUT;",
        "IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [ChangeNote] NOT LIKE N'seed %')      -- untouched by an Administrator",
        "   AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)",
        "BEGIN",
        "    EXEC [config].[AddDefinitionVersion] @DefinitionKey = " + q(KEY) + ", @DefinitionKind = N'Program.RelayWord', @ChangeNote = @note, @PayloadText = @payload, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;",
        "    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;",
        "END",
        "GO",
    ]
    return NL.join(L) + NL


def md(doc):
    L = [
        "# SEL-221F Relay Word - the 24 bits and the ten logic masks",
        "",
        "Generated by `tools/relay_word_sel221f.py` (#215). Source: **SEL-221F-2/-3/-4, SEL-121F-2/-3 Instruction Manual, date",
        "code 981207** (`Z:\\Archive-WorkingData-Cloud\\Work\\DATA\\Manuals\\SEL\\221F-2-3-4_IM_19981207.pdf`). Every line is the",
        "manual's, with its page. The Settings tab's mask editor reads the seeded definition `" + KEY + "`.",
        "",
        "**Byte order (3-15):** " + doc["bitOrder"],
        "",
        "| Row | Bit | Code | Meaning (2-21, Table 2.4) |",
        "|---|---|---|---|",
    ]
    for ri, row in enumerate(ROWS, 1):
        for bi, (c, m) in enumerate(row, 1):
            L.append("| " + str(ri) + " | " + str(bi) + " | `" + c + "` | " + m + " |")
    L += ["", "*" + FOOTNOTE, ""]
    for v in VARIANTS:
        L.append("**Variant:** row " + str(v["row"]) + " bit " + str(v["bit"]) + " is `" + v["code"] + "` on the " + v["models"] + " - \"" + v["note"] + "\" (" + v["cite"] + ").")
    L += ["", "**Bits intended for relay testing (5-38):** " + ", ".join(TESTING["bits"]) + " - \"" + TESTING["note"] + "\"", "",
          "## The ten logic masks (3-20; 5-32 to 5-38)", "",
          "| Code | Name (3-20) | Purpose | Caution | Typical bits | Never | Manual's example | Page |",
          "|---|---|---|---|---|---|---|---|"]
    for (code, name, purpose, caution, typical, never, example, cite) in MASKS:
        L.append("| `" + code + "` | " + name + " | " + purpose + " | " + (caution or "") + " | " + ", ".join(typical) + " | "
                 + ", ".join(never) + (" - \"" + NEVER_TRIP.format(m=code) + "\"" if never else "") + " | `" + example + "` | " + cite + " |")
    L += ["", "## The element map (#219) — the sheet's sub-groups and the rationale's sections", "",
          "The owner, 2026-09-21: a rationale section per protective element being used; the settings sheet grouped the same way; the",
          "settings that supervise an element handled explicitly. Supervision is the manual's own logic (2-18, 2-24), quoted per row.", "",
          "| Element | Capability | Name | Outputs (Relay Word) | Owns | Supervised by | Page |",
          "|---|---|---|---|---|---|---|"]
    for (k, cap, name, outs, sets, sup, cite) in ELEMENTS:
        L.append("| `" + k + "` | `" + cap + "` | " + name + " | " + ", ".join(outs) + " | " + ", ".join("`" + s + "`" for s in sets) + " | "
                 + "; ".join("**" + by + "** — " + how + " (" + c + ")" for (by, how, c) in sup) + " | " + cite + " |")
    L += ["", "| Group | Name | Settings |", "|---|---|---|"]
    for (k, name, sets) in GROUPS:
        L.append("| `" + k + "` | " + name + " | " + ", ".join("`" + s + "`" for s in sets) + " |")
    L += ["", "## What the platform cannot yet tell apart", "",
          "The -2 has TRIP at row 3 bit 2; the -3/-4 have BFT there (5-33 Note 2). The model rows in this platform carry no variation",
          "suffix (`sel-221f.capabilities.md`), so the editor names the bit \"TRIP (BFT on the -3/-4)\" and a person must know which",
          "relay is in front of them. Recording the variant on the device is a separate decision.", ""]
    return NL.join(L) + NL


def main():
    doc = document()
    a = os.path.join(HERE, "docs", "schema", "ddl", "PostDeploy", "Seed_config_RelayWord_SEL221F.sql")
    b = os.path.join(HERE, "docs", "design", "examples", "templates", "sel-221f.relay-word.md")
    io.open(a, "w", encoding="utf-8", newline="").write(sql(doc))
    io.open(b, "w", encoding="utf-8", newline="").write(md(doc))
    print(str(sum(len(r) for r in ROWS)) + " bits, " + str(len(MASKS)) + " masks ->")
    print("  " + a)
    print("  " + b)


if __name__ == "__main__":
    main()
