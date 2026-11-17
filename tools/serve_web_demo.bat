@echo off
rem Plays the browser demo (builds\web) from this computer: starts a small web server on port 8060 and
rem opens the page. Close this window to stop the server.
cd /d "%~dp0..\builds\web"
start "" http://localhost:8060/index.html
python -m http.server 8060 --bind 127.0.0.1
