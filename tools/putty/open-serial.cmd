@echo off
start "" "%~dp0..\vendor\putty-0.85\putty.exe" -serial COM13 -sercfg 115200,8,n,1,N
