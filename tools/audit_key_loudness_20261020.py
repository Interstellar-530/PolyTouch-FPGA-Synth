"""Reproduce key-gain arithmetic audit; never modify RTL or program a board."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil

ROOT = next((parent for parent in Path(__file__).resolve().parents
             if (parent / 'AGENTS.md').is_file()
             and (parent / 'output/handoff_milestone2_20261008').is_dir()),
            Path(__file__).resolve().parents[1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--package', action='store_true', help='Archive reviewed sources beside evidence')
    args = parser.parse_args()
    out = args.out.resolve()
    if ROOT not in out.parents:
        raise ValueError('Output must be inside FPGA workspace')
    out.mkdir(parents=True, exist_ok=True)
    tables = {}
    maximum_db_error = 0.0
    coefficient_cases = 0
    for instrument, ceiling in [('piano', 6.0), ('guitar', 5.0)]:
        rows = []
        for note in range(128):
            db = -min(max(note - 60, 0) * 0.25, ceiling)
            c = math.floor(256 * 10 ** (db / 20) + 0.5)
            error_db = abs(20 * math.log10(c / 256) - db)
            maximum_db_error = max(maximum_db_error, error_db)
            rows.append({'note': note, 'db': db, 'coefficient_q8': c})
            assert 128 <= c <= 256
        assert all(a['coefficient_q8'] >= b['coefficient_q8'] for a, b in zip(rows, rows[1:]))
        for row in rows:
            for mode in [0, 1, 2]:
                # off, weak (linear-gain midpoint), strong. No claimed half-dB slope.
                c = 256 if mode == 0 else ((256 + row['coefficient_q8'] + 1) // 2 if mode == 1 else row['coefficient_q8'])
                for velocity in range(128):
                    combined = velocity * c
                    assert 0 <= combined <= 127 * 256
                    assert (velocity != 0) or combined == 0
                    assert (mode != 0) or combined == velocity * 256
                    coefficient_cases += 1
        tables[instrument] = rows

    # Test signed endpoints for every possible coefficient and velocity.
    endpoint_cases = 0
    unity_cases = 0
    for extra in [0, 1, 2]:
        low = -(1 << (15 + extra))
        high = (1 << (15 + extra)) - 1
        rounding = 16384 if extra else 0
        for coefficient in range(257):
            for velocity in range(128):
                for sample in [low, -1, 0, 1, high]:
                    product = sample * velocity * coefficient
                    result = (product + rounding) >> 15
                    assert -(1 << 35) <= product < (1 << 35)
                    assert low <= result <= high
                    endpoint_cases += 1
        # Exhaustively verify the replaced amplitude operation at unity.
        for sample in range(low, high + 1):
            for velocity in [0, 1, 31, 64, 100, 127]:
                old = (sample * velocity + (64 if extra else 0)) >> 7
                new = (sample * (velocity * 256) + rounding) >> 15
                assert old == new
                unity_cases += 1

    # Worst-case current full-envelope sample and original +5 dB velocity.
    old_vel_boost = math.floor(127 * 10 ** (5 / 20) + 0.5)
    original_overflow = ((131068 * old_vel_boost + 64) >> 7)
    assert original_overflow > 131071
    original_zero_bug = max(1, (0 * 128) >> 8)
    assert original_zero_bug == 1
    cancellation = {'baseline': 0.9 - 0.9, 'attenuated': 0.9 - 0.9 * 0.5}
    assert abs(cancellation['attenuated']) > abs(cancellation['baseline'])

    # Conservative 8-voice endpoint proof for the existing E=2, divide-8 path.
    # Any signed 18-bit envelope result and legal velocity are admitted.
    voice_min = (-131072 * 127 + 64) >> 7
    voice_max = (131071 * 127 + 64) >> 7
    sum_min, sum_max = voice_min * 8, voice_max * 8
    assert -(1 << 20) <= sum_min <= sum_max < (1 << 20)
    master_outputs = []
    for sine in [sum_min, sum_max]:
        for bright in [sum_min, sum_max]:
            for weight in range(256):
                numerator = sine * (255 - weight) + bright * weight + 1024
                master = numerator >> 11
                # Shared VCA takes low signed 18 bits: confirm no truncation.
                assert -131072 <= master <= 131071
                for pressure_q12 in [0, 1024, 4096]:
                    output24 = (master * pressure_q12 + 32) >> 6
                    assert -8388608 <= output24 <= 8388607
                    master_outputs.append(output24)

    # State path of current shared engine with bend + bandlimit enabled.
    path = ['ST_BEND_LO', 'ST_BEND_HI', 'ST_BEND_WAIT', 'ST_BEND_APPLY',
            'ST_ADDR_A', 'ST_LATCH_A', 'ST_ADDR_B', 'ST_LATCH_B',
            'ST_DIFF_B', 'ST_INTERP_S', 'ST_INTERP_B',
            'ST_BANK_ADDR_A', 'ST_BANK_LATCH_A', 'ST_BANK_ADDR_B',
            'ST_BANK_LATCH_B', 'ST_BANK_MUL', 'ST_BANK_INTERP',
            'ST_BANK_MIX_MUL', 'ST_BANK_MIX_APPLY',
            'ST_W_ENV_S', 'ST_VEL_S', 'ST_W_VEL_S', 'ST_FIN_S',
            'ST_W_ENV_B', 'ST_VEL_B', 'ST_W_VEL_B', 'ST_FIN_B']
    # Reserve four extra clocks per voice for serial coefficient lookup/multiply.
    frame_reserved = 1 + 8 * (len(path) + 4) + 16
    assert frame_reserved < 512 and frame_reserved < 576
    report = {
        'status': 'PASS mathematical model; not an RTL simulation or synthesis',
        'coefficient_note_velocity_mode_cases': coefficient_cases,
        'signed_endpoint_cases': endpoint_cases,
        'exhaustive_unity_cases': unity_cases,
        'coefficient_max_error_db': maximum_db_error,
        'combined_amplitude_max': 127 * 256,
        'legacy_boost': {'velocity': old_vel_boost, 'sample_result_e2': original_overflow, 'e2_max': 131071},
        'legacy_zero_velocity_clamp': original_zero_bug,
        'cancellation_counterexample': cancellation,
        'eight_voice_conservative_bound': {
            'e': 2, 'master_shift': 3, 'voice_min': voice_min, 'voice_max': voice_max,
            'sum_min': sum_min, 'sum_max': sum_max,
            'pre_softlimit_master24_min': min(master_outputs),
            'pre_softlimit_master24_max': max(master_outputs),
            'assumptions': 'No upstream overflow; velocity<=127; coefficient<=256; pressure<=4096; eight voices; mix weight 0..255'
        },
        'weak_velocity_example': {'velocity': 1, 'coefficient': 128, 'integer_velocity': max(1, (1 * 128) >> 8), 'retained_fractional_gain': 128 / 32768},
        'frame_budget': {'current_per_voice_path': path, 'per_voice_cycles': len(path), 'reserved_total_clocks': frame_reserved, 'remaining_at_512': 512 - frame_reserved, 'remaining_at_576': 576 - frame_reserved, 'reserved_microseconds_at_27mhz': frame_reserved / 27},
        'lpf': {'alpha': 0.5, 'minus3db_hz_at_46875': math.acos(0.75) * 46875 / (2 * math.pi), 'dc_group_delay_samples': 1.0, 'response_is_not_a_fixed_one_sample_delay': True},
        'lookahead_storage_bits_min_47x24': 47 * 24,
        'master_shift_3_to_2_gain_db': 20 * math.log10(2),
        'curve_anchors': {inst: [rows[n] for n in [36, 48, 60, 64, 72, 80, 84, 96]] for inst, rows in tables.items()},
        'limitations': ['No perceptual loudness claim', 'No PnR resource prediction', 'No new hardware bitstream', 'FSM budget is a hand-traced path reservation, not cycle simulation']
    }
    (out / 'gain_coefficients.json').write_text(json.dumps(tables, indent=2) + '\n', encoding='utf-8')
    (out / 'audit_result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k not in ['curve_anchors', 'frame_budget']}, indent=2))
    print('frame_reserved_clocks=', frame_reserved)
    if args.package:
        package = out.parent
        if package.parent != ROOT / 'archive':
            raise ValueError('--package requires --out archive/<version>/evidence')
        paths = [
            'docs/planning/FPGA-键控响度混音-20261019-v0.1.md',
            'docs/planning/FPGA-键控响度混音-20261019-v0.2.md',
            'output/handoff_milestone2_20261008/source/rtl/top.v',
            'output/handoff_milestone2_20261008/source/rtl/audio/shared_wavetable_engine.v',
            'output/handoff_milestone2_20261008/source/rtl/audio/global_crossfade.v',
            'output/handoff_milestone2_20261008/source/rtl/audio/voice_transition.v',
            'output/handoff_milestone2_20261008/source/build/gowin_top_dbg8/runs/20261019T160656857-b589c0e8/instrument/impl/pnr/instrument.rpt.txt',
            'tools/audit_key_loudness_20261020.py',
        ]
        for name in paths:
            target = package / 'source' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        plan = 'FPGA-键控响度混音-20261020-v0.3.md'
        shutil.copy2(ROOT / 'docs/planning' / plan, package / plan)
        (package / 'MANIFEST.md').write_text(
            '# MANIFEST\n\n'
            'FPGA-20261020-v0.1：键控响度混音审核。\n\n'
            '目标产物及可编辑源文档：' + plan + '。source/ 保存两版原方案、四个 RTL 文件、旧 PnR 报告和复现脚本。'
            'evidence/ 保存数值检查结果和所有 128 个音高的两套参考系数。checksums.sha256 覆盖本归档全部其他文件。\n\n'
            '本轮变更仅新增方案、离线检查脚本及归档，未修改 RTL/公共接口，未烧录。'
            '接口与调度变化是设计建议，尚未实施。回退仅撤销这些新增文件，不触碰既有工程改动。\n\n'
            '复现：在原项目根运行 tools/.venv-docconvert/Scripts/python.exe tools/audit_key_loudness_20261020.py '
            '--out archive/FPGA-20261020-v0.1/evidence --package。脚本仅依赖标准库。'
            '归档脚本可用 --out <FPGA工作区内目录> 独立复核数值；--package 需要原项目目录和输入文件。\n\n'
            '证据范围：98304 组系数/音高/力度/模式、493440 组符号端点、2752512 组旁路等价，以及八声部保守主输出界。'
            '周期为源码路径预算，没有新的 RTL 仿真、综合或听感测试。\n\n'
            '清理：未生成临时脚本、渲染图、构建缓存或 __pycache__；数值输出为保留证据。原有运行时与其他任务文件保留。\n',
            encoding='utf-8')
        hashes = []
        for path in sorted(package.rglob('*')):
            if path.is_file() and path.name != 'checksums.sha256':
                hashes.append(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.relative_to(package).as_posix())
        (package / 'checksums.sha256').write_text('\n'.join(hashes) + '\n', encoding='utf-8')
        for line in hashes:
            digest, name = line.split('  ', 1)
            assert hashlib.sha256((package / name).read_bytes()).hexdigest() == digest, name
        print(f'PASS: {len(hashes)} archive SHA256 checksums')


if __name__ == '__main__':
    main()
