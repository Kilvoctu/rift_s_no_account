@echo off
title Rift S Tracking Fix
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0TrackFix.ps1" %*
