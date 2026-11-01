"""Summarize the self-checking latency bench log; Python standard library only."""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    text = args.log.read_text(encoding='utf-8-sig')
    rows = {}
    for line in text.splitlines():
        if not line.startswith('LATENCY '):
            continue
        row = {k: float(v) for k, v in re.findall(r'(\w+)=([0-9.]+)', line)}
        row['voices'] = int(row['voices'])
        row['compute_tail_us'] = row['max_tail_cycles'] / 73.728
        row['frame_headroom_percent'] = (1-row['max_tail_cycles']/row['frame_cycles'])*100
        rows[str(row['voices'])] = row
    if set(rows) != {'8', '32'} or 'PASS tb_ram32_latency:' not in text:
        raise SystemExit('Missing successful 8/32 latency results')
    result = {
        'passed': True,
        'reference_mhz': 12.288,
        'compute_mhz': 73.728,
        'sample_rate_hz': 48000,
        'attack_step_per_frame': 140,
        'phase_samples_per_configuration': 4,
        'comparison_8_is_same_ram_architecture_not_board_production_engine': True,
        'rows': rows,
        'delta_32_minus_8_us': {
            'single_max': rows['32']['single_max_us']-rows['8']['single_max_us'],
            'full_load_first_output_change': rows['32']['full_load_change_us']-rows['8']['full_load_change_us'],
            'compute_tail': rows['32']['compute_tail_us']-rows['8']['compute_tail_us'],
        },
        'limits': [
            'RTL simulation and behavioral ROM/PLL models; no board programming',
            'Full-load shadow measures first output difference, not isolated new-note acoustic onset',
            'UART timing starts at first serial frame bit; excludes physical key scan and USB polling',
            'Envelope 10/90 percent times describe envelope state, not measured sound pressure',
            'ADC/DAC analog delay, loudness threshold, and 27-to-54 MHz board adaptation not verified',
            'Four sampled event phases are measured observations, not an exhaustive worst-case proof',
        ],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result['rows'], indent=2))


if __name__ == '__main__':
    main()
