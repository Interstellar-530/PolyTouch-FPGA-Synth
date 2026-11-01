Set-Location 'D:\NanjingUniversity\FPGA\PolyTouch-FPGA-Synth-20261020-guitar-previews-v0.1'
python .\render_guitar_previews.py
Get-FileHash -Algorithm SHA256 .\wav\*.wav | Format-Table -AutoSize