# Writes an original 16-bar bassoon piece as MusicXML, for the layout mockups.
import sys

DIV = 2  # divisions per quarter
DUR = {"e": 1, "q": 2, "q.": 3, "h": 4, "h.": 6, "w": 8}
TYPE = {"e": "eighth", "q": "quarter", "q.": "quarter", "h": "half", "h.": "half", "w": "whole"}

# (pitch or 'r', length, extras)
bars = [
    [("F3", "q", "p sl+"), ("A3", "q", ""), ("C4", "q", ""), ("A3", "q", "")],
    [("Bb3", "h", ""), ("A3", "q", ""), ("G3", "q", "sl-")],
    [("F3", "q.", "sl+"), ("G3", "e", ""), ("A3", "q", ""), ("F3", "q", "sl-")],
    [("C3", "h.", ""), ("r", "q", "")],
    [("D3", "q", "sl+"), ("F3", "q", ""), ("Bb3", "q", ""), ("A3", "q", "sl-")],
    [("G3", "q", "sl+"), ("C4", "q", ""), ("Bb3", "q", ""), ("G3", "q", "sl-")],
    [("A3", "q", ""), ("F3", "q", ""), ("G3", "q", ""), ("E3", "q", "")],
    [("F3", "w", "")],
    [("A3", "q", "mf sl+"), ("C4", "q", ""), ("D4", "q", ""), ("C4", "q", "sl-")],
    [("Bb3", "q", ""), ("A3", "q", ""), ("G3", "h", "")],
    [("G3", "q", "sl+"), ("Bb3", "q", ""), ("C4", "q", ""), ("Bb3", "q", "sl-")],
    [("A3", "q", ""), ("G3", "q", ""), ("F3", "h", "")],
    [("D3", "q", "cr+ sl+"), ("E3", "q", ""), ("F3", "q", ""), ("G3", "q", "sl-")],
    [("A3", "q.", "f cr-"), ("Bb3", "e", ""), ("C4", "h", "")],
    [("Bb3", "q", "dim+"), ("G3", "q", ""), ("E3", "q", ""), ("C3", "q", "dim-")],
    [("F3", "w", "ferm")],
]

def pitch(p):
    step, rest = p[0], p[1:]
    alter = 0
    if rest.startswith("b"):
        alter, rest = -1, rest[1:]
    elif rest.startswith("#"):
        alter, rest = 1, rest[1:]
    return step, alter, int(rest)

def direction(inner, placement="below"):
    return f'<direction placement="{placement}"><direction-type>{inner}</direction-type></direction>'

out = []
w = out.append
w('<?xml version="1.0" encoding="UTF-8"?>')
w('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">')
w('<score-partwise version="4.0">')
w('<work><work-title>Evening Air</work-title></work>')
w('<identification><creator type="composer">Test piece</creator></identification>')
w('<part-list><score-part id="P1"><part-name print-object="no">Bassoon</part-name></score-part></part-list>')
w('<part id="P1">')
for i, bar in enumerate(bars, start=1):
    w(f'<measure number="{i}">')
    if i == 1:
        w(f'<attributes><divisions>{DIV}</divisions><key><fifths>-1</fifths></key>'
          '<time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>F</sign><line>4</line></clef></attributes>')
        w(direction('<words font-weight="bold">Andante</words>', "above") .replace('</direction>', '<sound tempo="72"/></direction>'))
        w(direction('<rehearsal>A</rehearsal>', "above"))
    if i == 1:
        w('<barline location="left"><bar-style>heavy-light</bar-style><repeat direction="forward"/></barline>')
    if i == 9:
        w(direction('<rehearsal>B</rehearsal>', "above"))
    for p, length, extra in bar:
        ex = extra.split()
        for d in ("p", "mf", "f"):
            if d in ex:
                w(direction(f'<dynamics><{d}/></dynamics>'))
        if "cr+" in ex:
            w(direction('<wedge type="crescendo"/>'))
        if "dim+" in ex:
            w(direction('<wedge type="diminuendo"/>'))
        w('<note>')
        if p == "r":
            w('<rest/>')
        else:
            s, a, o = pitch(p)
            w(f'<pitch><step>{s}</step>{f"<alter>{a}</alter>" if a else ""}<octave>{o}</octave></pitch>')
        w(f'<duration>{DUR[length]}</duration><voice>1</voice><type>{TYPE[length]}</type>')
        if length.endswith("."):
            w('<dot/>')
        if p != "r":
            s, a, o = pitch(p)
            w('<stem>' + ("down" if (o > 3 or (o == 3 and s in "DCB" and s == "B")) else "up") + '</stem>' if False else '')
        nots = []
        if "sl+" in ex:
            nots.append('<slur type="start" number="1"/>')
        if "sl-" in ex:
            nots.append('<slur type="stop" number="1"/>')
        if "ferm" in ex:
            nots.append('<fermata type="upright"/>')
        if nots:
            w('<notations>' + ''.join(nots) + '</notations>')
        w('</note>')
        if "cr-" in ex or "dim-" in ex:
            pass
    if i == 13:
        pass
    # close wedges at the end of the bar where they finish
    if i == 13:
        w(direction('<wedge type="stop"/>'))
    if i == 15:
        w(direction('<wedge type="stop"/>'))
    if i == 8:
        w('<barline location="right"><bar-style>light-heavy</bar-style><repeat direction="backward"/></barline>')
    if i == 16:
        w('<barline location="right"><bar-style>light-heavy</bar-style></barline>')
    w('</measure>')
w('</part></score-partwise>')
open(sys.argv[1], "w").write("\n".join(out))
