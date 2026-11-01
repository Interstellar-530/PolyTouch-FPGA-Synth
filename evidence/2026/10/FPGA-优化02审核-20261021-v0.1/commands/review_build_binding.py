"""One isolated bitstream-mutation check plus read-only receipt verification.

No real programmer, Gowin run, RTL simulation, or product-source edit is used.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

ROOT = next(p for p in Path(__file__).resolve().parents if (p / '.git').exists())
SOURCE = ROOT / 'output/handoff_milestone2_20261008/source'
OUT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'tmp/build-binding-review-20261021-v01'


def run(name, args, env=None):
    # Let Windows PowerShell construct its own standard module path rather than
    # inheriting the host PowerShell 7 module search path.
    child_env = dict(os.environ if env is None else env)
    for key in list(child_env):
        if key.upper() == 'PSMODULEPATH':
            child_env.pop(key)
    result = subprocess.run([str(x) for x in args], cwd=ROOT, env=child_env,
                            capture_output=True, timeout=20)
    (OUT / f'{name}.log').write_bytes(result.stdout + result.stderr)
    return result


def main():
    if WORK.exists() and not (WORK / 'prepare_receipt.ps1').is_file():
        raise RuntimeError('review fixture already exists')
    fixture = WORK / 'source'
    for directory in ['rtl', 'constraints']:
        shutil.copytree(SOURCE / directory, fixture / directory, dirs_exist_ok=True)
    build = fixture / 'build'
    build.mkdir(exist_ok=True)
    for path in (SOURCE / 'build').iterdir():
        if path.is_file() and path.suffix in ('.ps1', '.tcl', '.list', '.tsv'):
            shutil.copy2(path, build / path.name)
    shutil.copytree(SOURCE / 'build/isolated', build / 'isolated', dirs_exist_ok=True)
    (fixture / 'sim').mkdir(exist_ok=True)
    (fixture / 'sim/run_simulation.ps1').write_text('exit 0\n', encoding='ascii')
    marker = WORK / 'mock-programmer-called.txt'
    programmer = WORK / 'mock-programmer.ps1'
    programmer.write_text("Set-Content -LiteralPath $env:FPGA_REVIEW_MARKER -Value 'mock only'\nexit 0\n", encoding='ascii')
    fs = WORK / 'mock.fs'
    fs.write_bytes(b'MOCK BITSTREAM ONLY\r\n')
    prepare = WORK / 'prepare_receipt.ps1'
    prepare.write_text(r'''param([string]$BuildDir,[string]$FsFile)
$ErrorActionPreference='Stop'
. (Join-Path $BuildDir 'profile_helpers.ps1')
$profile=Get-BuildProfile 'debug8usb'
$inputs=@(Get-BuildInputs $profile)
$item=Get-Item -LiteralPath $FsFile
New-Item -ItemType Directory -Force -Path (Join-Path $BuildDir 'receipts') | Out-Null
[ordered]@{Profile='debug8usb';Top=$profile.Top;Bitstream=$FsFile;
 BitstreamLength=$item.Length;BitstreamModifiedUtc=$item.LastWriteTimeUtc.Ticks;
 BitstreamSha256=(Get-FileHash -LiteralPath $FsFile -Algorithm SHA256).Hash.ToLower();
 InputsDigest=(Get-BuildInputsDigest $inputs);Inputs=$inputs} |
 ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $BuildDir 'receipts/debug8usb.json') -Encoding UTF8
''', encoding='ascii')
    ps = ['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File']
    prepared = run('prepare_fixture', [*ps,prepare,'-BuildDir',build,'-FsFile',fs])
    assert prepared.returncode == 0
    env = dict(os.environ, FPGA_REVIEW_MARKER=str(marker))
    args = [*ps,build/'program_sram.ps1','-Profile','debug8usb','-Programmer',programmer]
    normal = run('unchanged_bitstream_accepted', args, env)
    assert normal.returncode == 0 and marker.is_file()
    marker.unlink()
    stamp = fs.stat()
    changed = bytearray(fs.read_bytes())
    changed[0] ^= 1
    fs.write_bytes(changed)
    os.utime(fs, ns=(stamp.st_atime_ns,stamp.st_mtime_ns))
    mutated = fs.stat()
    rejected = run('same_size_same_timestamp_bitstream_rejected', args, env)
    tamper_passed = (rejected.returncode != 0 and not marker.exists()
                    and b'Bitstream changed' in rejected.stdout + rejected.stderr
                    and mutated.st_size == stamp.st_size and mutated.st_mtime_ns == stamp.st_mtime_ns)
    assert tamper_passed

    receipt = SOURCE / 'build/receipts/debug8usb.json'
    verify = WORK / 'verify_current_receipt.ps1'
    verify.write_text(r'''param([string]$BuildDir,[string]$OutFile)
$ErrorActionPreference='Stop'
. (Join-Path $BuildDir 'profile_helpers.ps1')
$r=Get-Content -LiteralPath (Join-Path $BuildDir 'receipts/debug8usb.json') -Raw | ConvertFrom-Json
$inputs=@(Get-BuildInputs (Get-BuildProfile 'debug8usb'))
$report=Join-Path (Split-Path -Parent $r.Bitstream) 'instrument.rpt.txt'
[ordered]@{input_count=$inputs.Count;inputs_match=(Test-BuildInputsUnchanged $r.Inputs $inputs);
 digest_matches=((Get-BuildInputsDigest $inputs) -eq $r.InputsDigest);
 bitstream_matches=((Get-FileHash -LiteralPath $r.Bitstream -Algorithm SHA256).Hash.ToLower() -eq $r.BitstreamSha256);
 tool_version=$r.Tool.Version;tool_version_matches_report=($r.Tool.Version -eq (Get-GowinToolVersion $report));
 receipt_sha256=(Get-FileHash -LiteralPath (Join-Path $BuildDir 'receipts/debug8usb.json') -Algorithm SHA256).Hash.ToLower()} |
 ConvertTo-Json | Set-Content -LiteralPath $OutFile -Encoding UTF8
''', encoding='ascii')
    verified = run('current_receipt', [*ps,verify,'-BuildDir',SOURCE/'build','-OutFile',OUT/'current_receipt.json'])
    assert verified.returncode == 0
    current = json.loads((OUT/'current_receipt.json').read_text(encoding='utf-8-sig'))
    assert all(current[k] for k in ['inputs_match','digest_matches','bitstream_matches','tool_version_matches_report'])
    implementation = ROOT / 'docs/evidence/FPGA-优化02-构建绑定-20261021'
    regen = json.loads((implementation/'regen_summary.json').read_text(encoding='utf-8-sig'))
    reviewed = ['build/build.ps1','build/profile_helpers.ps1','build/program_sram.ps1']
    hashes = {str(SOURCE/name):hashlib.sha256((SOURCE/name).read_bytes()).hexdigest() for name in reviewed}
    for name in ['gen_epiano_bank.py','gen_guitar_bank.py','gen_guitar_samples_bank.py']:
        path=ROOT/'tools'/name
        hashes[str(path)]=hashlib.sha256(path.read_bytes()).hexdigest()
    result = dict(core_effect='PASS',unchanged_bitstream_accepted=True,
                  equal_length_equal_timestamp_bitstream_change_rejected=tamper_passed,
                  production_receipt=current,prior_input_checks=11,prior_build_entry_checks=16,
                  prior_generator_results=regen,reviewed_files_sha256=hashes,
                  no_full_gate=True,no_new_synthesis=True,no_real_programming=True,product_sources_modified=False)
    (OUT/'review_results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(core_effect='PASS',input_count=current['input_count'],inputs_match=current['inputs_match'],
                         digest_matches=current['digest_matches'],bitstream_matches=current['bitstream_matches'],
                         bitstream_tamper_rejected=tamper_passed,tool_version=current['tool_version']),ensure_ascii=False))


if __name__ == '__main__':
    main()
