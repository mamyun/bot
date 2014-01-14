@echo off

REM
REM This script evaluates various short- and long-term EMA trading strategies
REM via evaluate.pl on the given range of files which represent N-month periods.
REM

SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

SET Start=%1
SET End=%2

if "%Start%"=="" (
    echo Must specify starting and ending month numbers!
    goto :EOF
)

if "%End%"=="" (
    echo Must specify starting and ending month numbers!
    goto :EOF
)

for /L %%a in (%Start%, 1, %End%) DO (

    for %%f in (data\monthly\12mo\*_%%a_*mo.csv) DO (
        SET File=%%f
    )

    perl evaluate.pl -input !File! %3 > !File!_results.csv

)
