@echo off
rem Starts Trophe As Cat (the Godot project in this folder).
cd /d "%~dp0"
start "" "C:\Tools\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."
