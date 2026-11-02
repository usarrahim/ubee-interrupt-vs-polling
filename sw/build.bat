@echo off
REM Assembles hw2.s with the course rv32 tool (rv32.exe).
REM Set RV32 to the path of rv32.exe if it is not in PATH, for example:
REM   set RV32=C:\tools\rv32.exe
cd /d "%~dp0"
if "%RV32%"=="" set RV32=rv32.exe
"%RV32%" asm hw2.s --devices ubee.toml --pad -o hw2_imem.mem --dmem hw2_dmem.mem
