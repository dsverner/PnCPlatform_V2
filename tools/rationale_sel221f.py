"""rationale_sel221f.py - the SEL-221F line-distance RATIONALE TEMPLATE, RATIONALE_SEL221F_LINE (#219), as data.

The owner, 2026-09-21: the Word rationale is "a source of double entry"; the engineer should enter the values and the
rationale once and the application should make the settings values, the settings file and the Word document from that
one entry. And: a single document has "too many variables" - "the only way I see this as being a possibility is to have
a rational 'section' for each of the protective elements being used", the settings sheet grouped the same way, and the
"settings which are used to supervise elements" handled explicitly. So this template has ONE SECTION PER ELEMENT of the
element map (tools/relay_word_sel221f.py, the fifteen capabilities with the Relay Word bits beneath them) plus three shared
sections (line data, instrument transformer ratios, fault study). A section names its INPUTS (the definition's
characteristic definitions, grouped by section - the engineer answers them), its FORMULAS (grammar-1 expressions over
line.*, ct.*, input.*, setting.*, value.* - compiled here through tools/FormulaCompile so a seed never carries a parse
error), the SETTINGS it writes, and its STATEMENT (text with {placeholders}; the supervision line comes from the map).

Sources: the two legacy rationales on DEV read this session - A4811.docx (Grand Falls Plant, L1175 A-Protection, 2002/
2023/2024) and A0394.doc (Eel River, 2000/2026) - for the practice and the defaults (each default names its source), and
the instruction manual (IM 981207) for what each setting is (the settings template's page cites). A default is a starting
value the engineer confirms or changes; nothing here is a philosophy statement of NB Power's - when a written one is
found it becomes the cite.

Writes docs/schema/ddl/PostDeploy/Seed_config_Rationale_SEL221F.sql and docs/design/examples/templates/sel-221f.rationale.md.
usage: python tools/rationale_sel221f.py            (needs dotnet; runs tools/FormulaCompile)
"""
import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile

NL = chr(13) + chr(10)
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = "RATIONALE_SEL221F_LINE"
SETTINGS_TEMPLATE = "SETTINGS_TEXT_SEL_221F"
ELEMENT_MAP = "RELAY_WORD_SEL_221F"
MODEL_CODES = ["SEL-221F Z1-3=.125-64 OHMS", "SEL-221F"]
A4811 = "A4811.docx (Grand Falls Plant, L1175 A-Protection)"
A0394 = "A0394.doc (Eel River Terminal, 0025 A-Prot)"

# the plant facts the engine resolves before any section runs (RationaleEngine): the line the device's scheme protects, or
# the line the engineer picked (the Line input below); its characteristics (LINE_Template, tools/template_line.py); its
# terminals (the near one is the device's station, the other the remote station); its voltage class
FACTS = [
    ("line.Name", "the line's name"),
    ("line.RemoteStation", "the station at the line's other terminal"),
    ("line.NearStation", "the station at the device's terminal"),
    ("line.kV", "the line's nominal voltage in kV (from its voltage class)"),
    ("line.R1", "positive-sequence resistance, Ω primary (the line asset)"),
    ("line.X1", "positive-sequence reactance, Ω primary"),
    ("line.R0", "zero-sequence resistance, Ω primary"),
    ("line.X0", "zero-sequence reactance, Ω primary"),
    ("line.LengthMiles", "line length, miles"),
    ("line.ChargingMvaPerMile", "line charging, MVA per mile (optional)"),
    ("device.Name", "the relay's name"),
    ("device.Station", "the relay's station"),
]

# INPUTS: (key, section, name, datatype, unit, default, description). A Boolean default is Y/N. A "table" input is not a
# characteristic (it exceeds 400 characters); it lives in rationale.json only - datatype "Table" with its columns.
INPUTS = [
    # shared
    ("Line", "LINE", "The line", "Reference", None, None, "The transmission line this relay protects; prefilled from the scheme that names the relay and the line it protects, else picked here."),
    ("Note_LINE", "LINE", "Note", "Text", None, None, "Your own words on the line data, appended to the section."),
    ("CtPrimary", "INPUTS", "CT ratio, primary", "Decimal", "A", "800", "The current transformer ratio's primary amperes (A4811: 'CT Ratio=800-5'; A0394: 600-5)."),
    ("CtSecondary", "INPUTS", "CT ratio, secondary", "Decimal", "A", "5", "The current transformer ratio's secondary amperes."),
    ("PtPrimary", "INPUTS", "PT ratio, primary", "Decimal", None, "1200", "The potential transformer ratio (A4811: 'PT Ratio=1200-1'; A0394: 600-1). Ratio to 1."),
    ("SptPrimary", "INPUTS", "Synchronizing PT ratio", "Decimal", None, "700", "The synchronizing potential transformer ratio to 1 (A4811: 'Set SPTR=700 - The sync pt is set on its 115 volt winding'; A0394: 350)."),
    ("Note_INPUTS", "INPUTS", "Note", "Text", None, None, "Your own words on the instrument transformers."),
    ("FaultStudy", "FAULTSTUDY", "Fault study", "Table", None, None, "The fault currents the overcurrent pickups are set against: location, fault current at maximum generation, at minimum generation, comment (A4811: 'Fault Study (November 22, 2023)')."),
    ("FaultStudyDate", "FAULTSTUDY", "Fault study date", "Text", None, None, "When the fault study was run (A4811: November 22, 2023)."),
    ("Note_FAULTSTUDY", "FAULTSTUDY", "Note", "Text", None, None, "Your own words on the fault study."),
    # Zone 1
    ("Used_Z1", "Z1", "Zone 1 in use", "Boolean", None, "Y", "Whether zone 1 is used at this position."),
    ("Zone1Pct", "Z1", "Zone 1 reach, % of the line", "Decimal", "%", "85", "A4811: 'Set zone 1 at 85% of the distance to St. Andre.'; A0394: 85% to the low-voltage bus, adjusted to 80%."),
    ("Trips_Z1", "Z1", "Zone 1 trips (MTU)", "Boolean", None, "Y", "Zone 1 phase and ground (Z1P, Z1G) in the unconditional trip mask (A4811 and A0394: yes)."),
    ("Recloses_Z1", "Z1", "Zone 1 initiates reclosing (MRI)", "Boolean", None, "Y", "Z1P, Z1G in the reclose initiate mask (A4811: 'Line reclosing will be initiated by any trip coming from the protection')."),
    ("Note_Z1", "Z1", "Note", "Text", None, None, "Your own words on zone 1 (A0394 explains a tap: 'Setting=26.03/(36.07*cos(90-64.55))*100%=80%')."),
    # Zone 2
    ("Used_Z2", "Z2", "Zone 2 in use", "Boolean", None, "Y", ""),
    ("Zone2Pct", "Z2", "Zone 2 reach, % of the line", "Decimal", "%", "130", "A4811: 'Set zone 2 to 130% of the distance to St. Andre'; A0394: 100% to the normally open point."),
    ("Zone2DelayPhase", "Z2", "Zone 2 delay, phase (Z2DP)", "Decimal", "cycles", "18", "A4811: 'Use a time delay of 18 cycles (0.3 seconds)'; A0394: 90 cycles to coordinate with fuses."),
    ("Zone2DelayGround", "Z2", "Zone 2 delay, ground (Z2DG)", "Decimal", "cycles", "18", "A4811: 18; A0394: 18 ('the ground distance elements can trip much faster')."),
    ("Trips_Z2", "Z2", "Zone 2 trips (MTU)", "Boolean", None, "Y", "Z2PT, Z2GT in the unconditional trip mask."),
    ("Recloses_Z2", "Z2", "Zone 2 initiates reclosing (MRI)", "Boolean", None, "Y", ""),
    ("Note_Z2", "Z2", "Note", "Text", None, None, ""),
    # Zone 3
    ("Used_Z3", "Z3", "Zone 3 in use", "Boolean", None, "Y", ""),
    ("Zone3Pct", "Z3", "Zone 3 reach, % of the line", "Decimal", "%", "130", "A0394: 'Set zone 3 at 130% of the distance to the normally open point'; A4811: 1314% for an abnormal condition, 'normally turned off in the MTU mask'."),
    ("Zone3Delay", "Z3", "Zone 3 delay (Z3D)", "Decimal", "cycles", "36", "A4811: Z3D=36; A0394: 156 (2.6 seconds)."),
    ("Trips_Z3", "Z3", "Zone 3 time-delayed trips (MTU)", "Boolean", None, "Y", "Z3T in the unconditional trip mask (A0394: yes; A4811: normally off)."),
    ("Recloses_Z3", "Z3", "Zone 3 initiates reclosing (MRI)", "Boolean", None, "N", ""),
    ("Note_Z3", "Z3", "Note", "Text", None, None, ""),
    # 50P, 50NG
    ("Used_50P", "50P", "50P in use", "Boolean", None, "Y", ""),
    ("ChargingMvaPerMile", "50P", "Line charging, MVA per mile", "Decimal", None, "0.128", "Used when the line asset carries none (A4811: '0.128 MVA/mile' at 138 kV; A0394: 0.032 at 69 kV)."),
    ("Pickup50P", "50P", "50P pickup", "Decimal", "A", "80", "A4811: 'Set 50NG=80 amps and 50P=80 amps'; A0394: 100. Above the charging current, about 1/3 of the far-end fault level."),
    ("Note_50P", "50P", "Note", "Text", None, None, ""),
    ("Used_50NG", "50NG", "50NG in use", "Boolean", None, "Y", ""),
    ("Pickup50NG", "50NG", "50NG pickup", "Decimal", "A", "80", "A4811: 80; A0394: 60 ('this will provide good sensitivity for all line faults')."),
    ("Note_50NG", "50NG", "Note", "Text", None, None, ""),
    # 50H
    ("Used_50H", "50H", "50H in use", "Boolean", None, "Y", ""),
    ("CloseInFaultA", "50H", "Close-in three-phase fault, A", "Decimal", "A", "7000", "A0394: 'The close in three phase fault level at Eel River is 7000 amps primary'; A4811 did not use it (50H=5000, 'will not be used')."),
    ("Pickup50H", "50H", "50H pickup (override)", "Decimal", "A", None, "Leave empty for 50 % of the close-in fault (A0394: 'trip at 50% of the close in fault level ... Set 50H=3500'); or set it."),
    ("Trips_50H", "50H", "50H trips with the breaker open (MTO)", "Boolean", None, "Y", "50H in the trip-with-breaker-open mask (A0394: 'MTO Set to trip on high set overcurrent'; A4811: off)."),
    ("Note_50H", "50H", "Note", "Text", None, None, ""),
    # 51N
    ("Used_51N", "51N", "51N in use", "Boolean", None, "Y", ""),
    ("Pickup51NP", "51N", "51NP pickup", "Decimal", "A", "160", "A4811: 'pick up at 160A (1ASec)'; A0394: 60 (coordinated with the MCGG on the line)."),
    ("Curve51NC", "51N", "51NC curve", "Text", None, "3", "The relay's curve number (A4811 and A0394: 3, 'SEL Very Inverse')."),
    ("TimeDial51NTD", "51N", "51NTD time dial", "Decimal", None, "2.01", "A4811: 2.01 ('trip in 0.5s for the fault at St. Andre during maximum generation'); A0394: 3.5."),
    ("TorqueControl51NTC", "51N", "51NTC torque control", "Text", None, "Y", "Y = directionally supervised by 32Q (A4811: Y; A0394: N)."),
    ("Trips_51N", "51N", "51NT trips (MTU)", "Boolean", None, "Y", "51NT in the unconditional trip mask (A0394 puts 51NT and 67N in MA2 'to allow the neutral trips to be isolated via a blocking switch')."),
    ("Recloses_51N", "51N", "51NT initiates reclosing (MRI)", "Boolean", None, "N", ""),
    ("Note_51N", "51N", "Note", "Text", None, None, ""),
    # 67N
    ("Used_67N", "67N", "67N in use", "Boolean", None, "Y", ""),
    ("RemoteFaultA", "67N", "Line-ground fault at the remote terminal, A", "Decimal", "A", "824", "A4811: St. Andre 824 A at maximum generation ('Set the instantaneous unit up at 150% of the St. Andre fault level')."),
    ("Pickup67NP", "67N", "67NP pickup (override)", "Decimal", "A", None, "Leave empty for 150 % of the remote fault (A4811: 67NP = 1236); or set it (A0394: 800)."),
    ("TorqueControl67NTC", "67N", "67NTC torque control", "Text", None, "Y", "Y = directionally supervised by 32Q (A4811: Y; A0394: N)."),
    ("Trips_67N", "67N", "67N trips (MTU)", "Boolean", None, "Y", ""),
    ("Recloses_67N", "67N", "67N initiates reclosing (MRI)", "Boolean", None, "Y", ""),
    ("Note_67N", "67N", "Note", "Text", None, None, ""),
    # 32Q, LOP
    ("Note_32Q", "32Q", "Note", "Text", None, None, ""),
    ("Used_LOP", "LOP", "Loss-of-potential logic in use", "Boolean", None, "Y", ""),
    ("Lope", "LOP", "LOPE", "Text", None, "3", "A4811 and A0394: 'Enable the loss of potential logic. Set LOPE=3.' (Table 2.3, 2-17)."),
    ("Note_LOP", "LOP", "Note", "Text", None, None, ""),
    # 79
    ("Used_79", "79", "Reclosing in use", "Boolean", None, "Y", ""),
    ("OpenInterval", "79", "79OI open interval", "Decimal", "cycles", "30", "A4811: 'The line presently recloses in 0.5 seconds at Grand Falls ... set 79OI=30'; A0394: 60."),
    ("ResetTime", "79", "79RS reset time", "Decimal", "cycles", "900", "A4811 and A0394: 900 (15 seconds)."),
    ("Note_79", "79", "Note", "Text", None, None, ""),
    # 25 / 27 / 59
    ("Used_25", "25", "Sync and voltage checking in use", "Boolean", None, "Y", ""),
    ("Psvc", "25", "PSVC", "Text", None, "P", "A4811: 'PSVC=P - The polarizing pt's are on the bus (Live Bus/ dead line)'."),
    ("VoltsLow", "25", "27VLO dead voltage", "Decimal", None, "40", "A4811: '27VLO=40 - Line will be considered dead at 50% nominal line voltage'; A0394: 20."),
    ("VoltsHigh", "25", "59VHI live voltage", "Decimal", None, "64", "A4811: '59VHI=64 - live at 80% nominal'; A0394: 32."),
    ("DiffVolts", "25", "25DV difference voltage", "Decimal", None, "40", "A4811: '25DV=40 - Differential voltage will correspond to an angular difference of 30o'; A0394: 20."),
    ("SyncPhase", "25", "SYNCP", "Text", None, "A", "A4811: 'SYNCP=A - Sync pt on phase A'."),
    ("SyncTimer", "25", "25T", "Decimal", "cycles", "180", "A4811: '25T=180 - Length of time that the system must be in phase'."),
    ("VoltageTimer", "25", "VCT", "Decimal", "cycles", "30", "A4811: 'VCT=30 - Length of time that the voltages must be constant'."),
    ("Note_25", "25", "Note", "Text", None, None, ""),
    # REJO, SOTF
    ("Rejoe", "REJO", "REJOE", "Text", None, "N", "A0394: 'We will not be using the remote end open tripping function. Set REJOE=N.'"),
    ("Note_REJO", "REJO", "Note", "Text", None, None, ""),
    ("Used_SOTF", "SOTF", "Switch-onto-fault in use", "Boolean", None, "Y", ""),
    ("Bt52", "SOTF", "52BT", "Decimal", "cycles", "30", "A4811 and A0394: 'Set 52BT=30 cycles which enables the switch onto fault protection for 30 cycles after the breaker is closed.'"),
    ("Note_SOTF", "SOTF", "Note", "Text", None, None, ""),
    ("Note_FAULTLOC", "FAULTLOC", "Note", "Text", None, None, ""),
    # timers, comms
    ("A1Pickup", "TIMERS", "A1TP", "Decimal", "cycles", "0", "A4811: 'Programmable outputs will be used to supervise the reclosing. They will not be time delayed in any way. A1TP=0 and A1TD=0.'"),
    ("A1Dropout", "TIMERS", "A1TD", "Decimal", "cycles", "0", ""),
    ("TripDuration", "TIMERS", "TDUR", "Decimal", "cycles", "12", "A4811 summary: TDUR=12."),
    ("Note_TIMERS", "TIMERS", "Note", "Text", None, None, ""),
    ("Time1", "COMMS", "TIME1", "Integer", "min", "5", "A4811 and A0394: 'Set Time1=5, time2=0, auto=2, rings=1.'"),
    ("Time2", "COMMS", "TIME2", "Integer", "min", "0", ""),
    ("Auto", "COMMS", "AUTO", "Text", None, "2", ""),
    ("Rings", "COMMS", "RINGS", "Integer", None, "1", ""),
    ("Note_COMMS", "COMMS", "Note", "Text", None, None, ""),
    # masks not derived
    ("MaskMPT", "MASKS", "MPT", "Text", None, "00 00 00", "Trip with permissive-trip asserted (5-33); set as the scheme needs."),
    ("MaskMTB", "MASKS", "MTB", "Text", None, "00 00 00", "Trip with block-trip unasserted (5-34)."),
    ("MaskMA1", "MASKS", "MA1", "Text", None, "00 00 00", "A1 output (5-35)."),
    ("MaskMA2", "MASKS", "MA2", "Text", None, "00 00 00", "A2 output (5-35); A0394 puts 67N and 51NT here (00 A0 00)."),
    ("MaskMA3", "MASKS", "MA3", "Text", None, "00 00 00", "A3 output (5-35)."),
    ("MaskMA4", "MASKS", "MA4", "Text", None, "00 00 00", "A4 output (5-35)."),
    ("MaskMRC", "MASKS", "MRC", "Text", None, "00 00 00", "Reclose cancel (5-37)."),
    ("Note_MASKS", "MASKS", "Note", "Text", None, None, ""),
]

# SECTIONS in document order. (key, kind shared|element|group, title, statement, settings [(code, expr)], values [(name, expr)])
# A statement's {x} is a fact (line.X, device.X), an input (input.X), a computed value (value.X) or a written setting
# (setting.CODE); {supervision} is the map's supervised-by line for the element; {note} the section's Note input.
SECTIONS = [
    ("LINE", "shared", "Line data",
     "Relay line settings to {line.RemoteStation} ({line.Name}, {line.kV} kV): Z1 = {line.R1} + j{line.X1} Ω primary, line angle {setting.MTA}°; "
     "Z0 = {line.R0} + j{line.X0} Ω primary; LL = {line.LengthMiles} miles. {note}",
     [("R1", "line.R1"), ("X1", "line.X1"), ("R0", "line.R0"), ("X0", "line.X0"), ("MTA", "round(atan2(line.X1, line.R1), 2)")], []),
    ("INPUTS", "shared", "Current and potential inputs",
     "CT ratio {input.CtPrimary}:{input.CtSecondary} (CTR = {setting.CTR}); PT ratio {input.PtPrimary}:1 (PTR = {setting.PTR}); "
     "synchronizing PT ratio {input.SptPrimary}:1 (SPTR = {setting.SPTR}). {note}",
     [("CTR", "round(input.CtPrimary / input.CtSecondary, 2)"), ("PTR", "input.PtPrimary"), ("SPTR", "input.SptPrimary")], []),
    ("FAULTSTUDY", "shared", "Fault study", "Fault study {input.FaultStudyDate}: the currents the overcurrent pickups are set against are tabled below. {note}", [], []),
    ("Z1", "element", "Zone 1",
     "Set zone 1 at {input.Zone1Pct}% of the distance to {line.RemoteStation} (Z1% = {setting.Z1%}). {supervision} {note}",
     [("Z1%", "input.Zone1Pct")], []),
    ("Z2", "element", "Zone 2",
     "Set zone 2 to {input.Zone2Pct}% of the distance to {line.RemoteStation}, with a time delay of {input.Zone2DelayPhase} cycles for phase faults (Z2DP) "
     "and {input.Zone2DelayGround} cycles for ground faults (Z2DG). {supervision} {note}",
     [("Z2%", "input.Zone2Pct"), ("Z2DP", "input.Zone2DelayPhase"), ("Z2DG", "input.Zone2DelayGround")], []),
    ("Z3", "element", "Zone 3",
     "Set zone 3 to {input.Zone3Pct}% of the distance to {line.RemoteStation}, time delayed {input.Zone3Delay} cycles (Z3D). {supervision} {note}",
     [("Z3%", "input.Zone3Pct"), ("Z3D", "input.Zone3Delay")], []),
    ("50P", "element", "Supervisory phase overcurrent (50P)",
     "The supervisory overcurrents must be set high enough not to pick up on the line charging current: I charge = {value.ChargingMva} MVA/mile × "
     "{line.LengthMiles} miles × {value.AmpsPerMva} A/MVA = {value.ChargingA} A primary. Set 50P = {setting.50P} A. {note}",
     [("50P", "input.Pickup50P")],
     [("ChargingMva", "coalesce(line.ChargingMvaPerMile, input.ChargingMvaPerMile)"),
      ("AmpsPerMva", "round(1000000 / (1.7320508 * line.kV * 1000), 2)"),
      ("ChargingA", "round(coalesce(line.ChargingMvaPerMile, input.ChargingMvaPerMile) * line.LengthMiles * (1000000 / (1.7320508 * line.kV * 1000)), 2)")]),
    ("50NG", "element", "Supervisory residual overcurrent (50NG)",
     "Set 50NG = {setting.50NG} A, above the charging current ({value.ChargingA} A) and below the line-ground fault level at the far end. {note}",
     [("50NG", "input.Pickup50NG")], [("ChargingA", "value.ChargingA")]),
    ("50H", "element", "High-set phase overcurrent (50H, switch-onto-fault)",
     "The close-in three-phase fault level is {input.CloseInFaultA} A primary; the high-set overcurrent trips through the MTO mask while 52BT is asserted "
     "after the breaker closes, so that a line energized onto ground leads trips back out at once. Set 50H = {setting.50H} A. {supervision} {note}",
     [("50H", "coalesce(input.Pickup50H, round(0.5 * input.CloseInFaultA, 0))")], []),
    ("51N", "element", "Residual time-overcurrent (51N)",
     "The inverse-time residual element picks up at {setting.51NP} A on curve {setting.51NC} with time dial {setting.51NTD}; torque control {setting.51NTC}. "
     "{supervision} {note}",
     [("51NP", "input.Pickup51NP"), ("51NC", "input.Curve51NC"), ("51NTD", "input.TimeDial51NTD"), ("51NTC", "input.TorqueControl51NTC")], []),
    ("67N", "element", "Residual instantaneous overcurrent (67N)",
     "The line-ground fault at {line.RemoteStation} is {input.RemoteFaultA} A at maximum generation; the instantaneous unit is set at 150% of it: "
     "67NP = {setting.67NP} A, torque control {setting.67NTC}. {supervision} {note}",
     [("67NP", "coalesce(input.Pickup67NP, round(1.5 * input.RemoteFaultA, 0))"), ("67NTC", "input.TorqueControl67NTC")], []),
    ("32Q", "element", "Negative-sequence directional element (32Q)",
     "The negative-sequence directional element, adjusted by the maximum torque angle MTA = {setting.MTA}°, always supervises the distance elements and, "
     "with torque control set, the residual overcurrent elements (2-24). {note}", [], []),
    ("LOP", "element", "Loss-of-potential detection (LOP)",
     "Enable the loss-of-potential logic: LOPE = {setting.LOPE}; on loss of potential the distance elements are blocked (2-18). {note}",
     [("LOPE", "input.Lope")], []),
    ("79", "element", "Reclosing (79)",
     "Reclosing is initiated by the elements marked so below: open interval 79OI = {setting.79OI} cycles, reset time 79RS = {setting.79RS} cycles. {note}",
     [("79OI", "input.OpenInterval"), ("79RS", "input.ResetTime")], []),
    ("25", "element", "Synchronism and voltage checking (25, 27, 59)",
     "PSVC = {setting.PSVC}; dead below 27VLO = {setting.27VLO}, live above 59VHI = {setting.59VHI}; difference voltage 25DV = {setting.25DV}; "
     "sync check on phase {setting.SYNCP}; in phase for 25T = {setting.25T} cycles; voltages constant for VCT = {setting.VCT} cycles. {note}",
     [("PSVC", "input.Psvc"), ("27VLO", "input.VoltsLow"), ("59VHI", "input.VoltsHigh"), ("25DV", "input.DiffVolts"), ("SYNCP", "input.SyncPhase"),
      ("25T", "input.SyncTimer"), ("VCT", "input.VoltageTimer")], []),
    ("REJO", "element", "Remote-end-just-opened (REJO)", "Remote-end-just-opened tripping: REJOE = {setting.REJOE}. {note}", [("REJOE", "input.Rejoe")], []),
    ("SOTF", "element", "Switch-onto-fault (52BT)",
     "Set 52BT = {setting.52BT} cycles, which enables the switch-onto-fault protection (the MTO mask) for that long after the breaker is closed. {note}",
     [("52BT", "input.Bt52")], []),
    ("FAULTLOC", "element", "Fault locating", "The fault locator uses the line data above; line length LL = {setting.LL} miles. {note}",
     [("LL", "line.LengthMiles")], []),
    ("TIMERS", "group", "Timers", "A1TP = {setting.A1TP}, A1TD = {setting.A1TD}; minimum trip duration TDUR = {setting.TDUR} cycles. {note}",
     [("A1TP", "input.A1Pickup"), ("A1TD", "input.A1Dropout"), ("TDUR", "input.TripDuration")], []),
    ("COMMS", "group", "Communications", "TIME1 = {setting.TIME1}, TIME2 = {setting.TIME2}, AUTO = {setting.AUTO}, RINGS = {setting.RINGS}. {note}",
     [("TIME1", "input.Time1"), ("TIME2", "input.Time2"), ("AUTO", "input.Auto"), ("RINGS", "input.Rings")], []),
    ("MASKS", "group", "Logic masks",
     "MTU, MRI and MTO follow the elements above (the trip, reclose-initiate and trip-with-breaker-open marks); the other masks as set here. {note}",
     [("MPT", "input.MaskMPT"), ("MTB", "input.MaskMTB"), ("MA1", "input.MaskMA1"), ("MA2", "input.MaskMA2"), ("MA3", "input.MaskMA3"), ("MA4", "input.MaskMA4"), ("MRC", "input.MaskMRC")], []),
]

# the masks the engine derives: mask -> (the input suffix per element, the element outputs that go into the mask)
DERIVED_MASKS = {
    "MTU": {"input": "Trips",    "outputs": {"Z1": ["Z1P", "Z1G"], "Z2": ["Z2PT", "Z2GT"], "Z3": ["Z3T"], "51N": ["51NT"], "67N": ["67N"]}},
    "MRI": {"input": "Recloses", "outputs": {"Z1": ["Z1P", "Z1G"], "Z2": ["Z2PT", "Z2GT"], "Z3": ["Z3T"], "51N": ["51NT"], "67N": ["67N"]}},
    "MTO": {"input": "Trips",    "outputs": {"50H": ["50H"]}},
}


def compile_all(items):
    spec = os.path.join(tempfile.gettempdir(), "pnc_rationale_spec.json")
    io.open(spec, "w", encoding="utf-8").write(json.dumps({"items": items}))
    proj = os.path.join(HERE, "tools", "FormulaCompile")
    r = subprocess.run(["dotnet", "run", "--project", proj, "--", spec], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0 and not r.stdout.strip().startswith("{"):
        sys.exit("FormulaCompile failed:\n" + r.stdout + r.stderr)
    out = json.loads(r.stdout)
    errs = {k: v["error"] for k, v in out.items() if "error" in v}
    if errs:
        sys.exit("expressions that do not compile:\n" + "\n".join("  " + k + ": " + e for k, e in errs.items()))
    return out


def document(compiled):
    return {
        "g": 1, "kind": "rationale", "key": KEY, "name": "SEL-221F line distance protection rationale",
        "settingsTemplate": SETTINGS_TEMPLATE, "elementMap": ELEMENT_MAP,
        "sources": [A4811, A0394, "IM 981207 (the settings template's page cites)"],
        "facts": [{"name": n, "meaning": m} for (n, m) in FACTS],
        "inputs": [{"key": k, "section": sec, "name": name, "dataType": dt, "unit": unit, "default": d, "description": desc,
                    **({"columns": ["Location", "IFault max gen (A)", "IFault min gen (A)", "Comment"]} if dt == "Table" else {})}
                   for (k, sec, name, dt, unit, d, desc) in INPUTS],
        "sections": [{"key": k, "kind": kind, "title": title, "statement": st,
                      "settings": [{"code": c, "exprText": e, "expr": compiled["s:" + k + ":" + c]["ast"]} for (c, e) in sets],
                      "values": [{"name": n, "exprText": e, "expr": compiled["v:" + k + ":" + n]["ast"]} for (n, e) in vals]}
                     for (k, kind, title, st, sets, vals) in SECTIONS],
        "derivedMasks": DERIVED_MASKS,
    }


def q(s):
    return "NULL" if s is None else "N'" + s.replace("'", "''") + "'"


def sql(doc):
    payload = json.dumps(doc, ensure_ascii=False, separators=(",", ":"))
    note = "seed " + hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]
    L = [
        "-- GENERATED by tools/rationale_sel221f.py - do not edit; edit the data there and regenerate.",
        "-- #219 (2026-09-21): the SEL-221F line-distance RATIONALE TEMPLATE - one section per protective element of the element map",
        "-- (RELAY_WORD_SEL_221F) plus the shared line data, inputs and fault study. Its characteristic definitions are the INPUTS the",
        "-- engineer answers (document.SetRationaleValue records them on the rationale revision); its payload the SECTIONS: formulas",
        "-- (compiled, grammar 1), the settings each writes, its statement. Defaults come from the two legacy rationales named in the",
        "-- generator, each labelled. Bound to the model codes through config.DefinitionAppliesTo. Idempotent: a new version only when",
        "-- the payload changed and no Administrator has edited the definition.",
        "IF OBJECT_ID(N'[config].[AddDefinition]') IS NULL RETURN;   -- bootstrap (tables-only) publish",
        "GO",
        "DECLARE @author UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000001', @approver UNIQUEIDENTIFIER = '00000000-0000-0000-0000-000000000002';",
        "DECLARE @sel UNIQUEIDENTIFIER = (SELECT TOP (1) [ManufacturerId] FROM [ref].[vManufacturer] WHERE [ShortCode] = N'SEL');",
        "DECLARE @e UNIQUEIDENTIFIER, @v UNIQUEIDENTIFIER, @no INT, @model UNIQUEIDENTIFIER, @code NVARCHAR(200), @payload NVARCHAR(MAX) = " + q(payload) + ";",
        "DECLARE @note NVARCHAR(200) = " + q(note) + ";",
        "SELECT @e = EntityId FROM [config].[Definition] WHERE [DefinitionKind] = N'Program.Rationale' AND [DefinitionKey] = " + q(KEY) + " AND [IsDeleted] = 0;",
        "IF @e IS NULL",
        "    EXEC [config].[AddDefinition] @DefinitionKind = N'Program.Rationale', @DefinitionKey = " + q(KEY) + ", @Name = N'SEL-221F line distance protection rationale',",
        "         @Description = N'The settings rationale of an SEL-221F on a transmission line: one section per protective element, the inputs the engineer answers, the formulas that make the settings values, the statements the document is assembled from (#219).', @ActorId = @author, @EntityId = @e OUTPUT;",
        "IF NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [ChangeNote] NOT LIKE N'seed %')      -- untouched by an Administrator",
        "   AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' AND [ChangeNote] = @note)",
        "BEGIN",
        "    EXEC [config].[AddDefinitionVersion] @DefinitionKey = " + q(KEY) + ", @DefinitionKind = N'Program.Rationale', @ChangeNote = @note, @PayloadText = @payload, @ActorId = @author, @VersionRowId = @v OUTPUT, @VersionNumber = @no OUTPUT;",
    ]
    order = 0
    for (k, sec, name, dt, unit, d, desc) in INPUTS:
        if dt == "Table":
            continue   # lives in rationale.json only
        order += 1
        L.append("    EXEC [config].[CharacteristicDefinition_Add] @DefinitionVersionRowId = @v, @CharacteristicKey = " + q(k) + ", @Name = " + q(name)
                 + ", @DataType = " + q(dt) + ", @UnitCode = " + q(unit) + ", @DisplayGroup = " + q(sec) + ", @DisplayOrder = " + str(order)
                 + (", @ReferenceTargetKind = N'Asset'" if dt == "Reference" else "") + ", @Description = " + q(desc or name) + ", @ActorId = @author;")
    L += [
        "    EXEC [config].[ApproveDefinitionVersion] @VersionRowId = @v, @ActorId = @approver;",
        "END",
        "SELECT TOP (1) @v = [RowId] FROM [config].[vDefinitionVersion] WHERE [DefinitionEntityId] = @e AND [Status] = N'Effective' ORDER BY [VersionNumber] DESC;",
        "DECLARE mc CURSOR LOCAL FAST_FORWARD FOR SELECT [Code] FROM (VALUES " + ", ".join("(" + q(c) + ")" for c in MODEL_CODES) + ") x ([Code]);",
        "OPEN mc; FETCH NEXT FROM mc INTO @code;",
        "WHILE @@FETCH_STATUS = 0",
        "BEGIN",
        "    SELECT @model = [ModelId] FROM [ref].[vModel] WHERE [ManufacturerId] = @sel AND [ModelCode] = @code;",
        "    IF @model IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [config].[vDefinitionAppliesTo] WHERE [DefinitionVersionRowId] = @v AND [DimensionCode] = N'Model' AND [ValueEntityId] = @model)",
        "        EXEC [config].[DefinitionAppliesTo_Add] @DefinitionVersionRowId = @v, @DimensionCode = N'Model', @ValueEntityId = @model, @ActorId = @author;",
        "    FETCH NEXT FROM mc INTO @code;",
        "END",
        "CLOSE mc; DEALLOCATE mc;",
        "GO",
    ]
    return NL.join(L) + NL


def md():
    L = [
        "# SEL-221F line distance protection rationale - `" + KEY + "`",
        "",
        "Generated by `tools/rationale_sel221f.py` (#219). One section per protective element of the element map",
        "(`sel-221f.relay-word.md`), plus the shared line data, inputs and fault study. The engineer answers the inputs on the",
        "record's Rationale tab; the platform computes the settings, writes them onto the outstanding revision, and assembles the",
        "Word document from the statements. Defaults are starting values from the two legacy rationales named on each row -",
        "**" + A4811 + "** and **" + A0394 + "** - not a philosophy statement; when a written NB Power philosophy is found it becomes the cite.",
        "",
        "## Plant facts the engine resolves first",
        "",
        "| Fact | Meaning |", "|---|---|",
    ]
    for (n, m) in FACTS:
        L.append("| `" + n + "` | " + m + " |")
    L += ["", "## Sections, in document order", ""]
    for (k, kind, title, st, sets, vals) in SECTIONS:
        L += ["### " + title + " (`" + k + "`, " + kind + ")", "", "Statement: " + st.replace("{", "`{").replace("}", "}`"), ""]
        if sets:
            L += ["| Setting written | Formula |", "|---|---|"] + ["| `" + c + "` | `" + e + "` |" for (c, e) in sets] + [""]
        if vals:
            L += ["| Value | Formula |", "|---|---|"] + ["| `value." + n + "` | `" + e + "` |" for (n, e) in vals] + [""]
        ins = [i for i in INPUTS if i[1] == k]
        if ins:
            L += ["| Input | Type | Unit | Default | Source / meaning |", "|---|---|---|---|---|"]
            L += ["| `" + key + "` (" + name + ") | " + dt + " | " + (unit or "") + " | " + (d if d is not None else "") + " | " + (desc or "") + " |" for (key, sec, name, dt, unit, d, desc) in ins]
            L += [""]
    L += ["## Derived masks", "", "| Mask | From the elements' mark | Outputs per element |", "|---|---|---|"]
    for m, spec in DERIVED_MASKS.items():
        L.append("| `" + m + "` | `" + spec["input"] + "_<element>` | " + "; ".join(k + ": " + ", ".join(o) for k, o in spec["outputs"].items()) + " |")
    L += [""]
    return NL.join(L) + NL


def main():
    items = []
    for (k, kind, title, st, sets, vals) in SECTIONS:
        items += [{"id": "s:" + k + ":" + c, "kind": "expression", "text": e} for (c, e) in sets]
        items += [{"id": "v:" + k + ":" + n, "kind": "expression", "text": e} for (n, e) in vals]
    compiled = compile_all(items)
    doc = document(compiled)
    out = os.path.join(HERE, "docs", "schema", "ddl", "PostDeploy", "Seed_config_Rationale_SEL221F.sql")
    io.open(out, "w", encoding="utf-8", newline="").write(sql(doc))
    d = os.path.join(HERE, "docs", "design", "examples", "templates", "sel-221f.rationale.md")
    io.open(d, "w", encoding="utf-8", newline="").write(md())
    print(str(len(SECTIONS)) + " sections, " + str(len(INPUTS)) + " inputs, " + str(len(items)) + " formulas ->\n  " + out + "\n  " + d)


if __name__ == "__main__":
    main()
