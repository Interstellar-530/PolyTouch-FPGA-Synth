"""Second test tune: Kuanggu Huixiang (旷古回响), bridge section.

Source: the numbered score (简谱) supplied by the user, pages 1-3, marked
1=A-flat, 4/4, quarter=100, with lyrics.  The bridge starts at bar 107 of the
piano score and runs "巍峨西山古 ... 千载斯文在此中".

Only the bridge is transcribed here (13 bars, 31.2 s at 100 BPM).  The climax
("草木心 ... 今迎后来者") is still to be added.
"""

BPM = 100
UNIT_SAMPLES_48K = 7200          # 60 / 100 / 4 * 48000
BARS = 13
UNIT_PER_BAR = 16
TOTAL_UNITS = BARS * UNIT_PER_BAR

# (bar, unit_in_bar, midi, length_units)
MELODY = [
    (0, 0, 77, 6), (0, 6, 75, 2), (0, 8, 72, 4), (0, 12, 70, 4),      # 巍峨西山
    (2, 0, 77, 6), (2, 6, 79, 2), (2, 8, 77, 4), (2, 12, 75, 4),      # 浩瀚大河
    (4, 0, 77, 6), (4, 6, 75, 2), (4, 8, 72, 4), (4, 12, 75, 4),      # 兴亡陈迹
    (5, 0, 70, 4), (5, 4, 72, 4),                                     # 今只
    (6, 0, 70, 2), (6, 2, 70, 2), (6, 4, 68, 2), (6, 6, 75, 2),       # 冢上青柏
    (6, 8, 72, 4), (6, 12, 68, 2), (6, 14, 72, 2),                    # 葱葱
    (7, 0, 72, 4), (7, 4, 72, 12),                                    # 葱 held
    (8, 0, 77, 6), (8, 6, 75, 2), (8, 8, 72, 4), (8, 12, 70, 4),      # 摄衣瞻拜
    (9, 12, 70, 2), (9, 14, 68, 2),                                   # 千载
    (10, 0, 65, 4), (10, 4, 68, 4), (10, 8, 70, 4), (10, 12, 72, 2),  # 斯文在此
]

# slurred groups: one continuous voice, single attack, pitch changes legato
LEGATO = [
    [(1, 0, 72, 2), (1, 2, 75, 2), (1, 4, 72, 12)],       # 古 3 5 3
    [(3, 0, 72, 2), (3, 2, 75, 2), (3, 4, 72, 12)],       # 雄 3 5 3
    [(5, 8, 65, 4), (5, 12, 68, 4)],                       # 余 6̣ 1
    [(9, 0, 72, 6), (9, 6, 75, 2), (9, 8, 72, 4)],        # 太史公 3. 5 3
    [(10, 14, 75, 2), (11, 0, 77, 8)],                     # 中 5 -> 6 tie
]

# B-flat minor triads (the score's key; 1=A-flat)
Bbm = [58, 61, 65]
Gb = [54, 58, 61]
Ebm = [51, 54, 58]
F = [53, 57, 60]
CHORD_LOOP = [Bbm, Gb, Ebm, F]
CHORDS = ([Bbm, Gb, Ebm, F] * 4)[:BARS]


def melody_events():
    """Yield (bar, unit, midi, length) for the non-slurred melody."""
    for item in MELODY:
        yield item


def legato_groups():
    for group in LEGATO:
        yield group


def chord_events():
    """Yield (bar, triad)."""
    for bar, chord in enumerate(CHORDS):
        yield bar, chord


def check():
    issues = []
    for bar, u, n, length in MELODY:
        if not (0 <= bar < BARS and 0 <= u < 16 and u + length <= 16):
            issues.append(f"melody out of bar: {(bar, u, n, length)}")
    for group in LEGATO:
        for bar, u, _, length in group:
            if not (0 <= bar < BARS and 0 <= u < 16 and u + length <= 16):
                issues.append(f"legato segment out of bar: {(bar, u, length)}")
    return issues


if __name__ == "__main__":
    print("bars", BARS, "units", TOTAL_UNITS, "seconds", TOTAL_UNITS * 60 / BPM / 4)
    print("melody events", len(MELODY), "legato groups", len(LEGATO))
    print("issues", check())
