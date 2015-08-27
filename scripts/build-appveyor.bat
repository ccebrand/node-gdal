@ECHO OFF
SETLOCAL
SET EL=0

ECHO ~~~~~~~~~~~~~~~~~~~~~~~~~~~~ %~f0 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

SET PATH=%CD%;%PATH%
SET msvs_version=2013
IF "%msvs_toolset%"=="14" SET msvs_version=2015


::make commit message env var shorter
::SET CM="%APPVEYOR_REPO_COMMIT_MESSAGE%"

for /F "tokens=1 usebackq" %%i in (`powershell .\scripts\parse-commit-message.ps1`) DO ECHO %%i && set PUBLISH=%%i
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF %PUBLISH% EQU 1 SET ENABLE_LOGGING=--enable-logging=true
SET "IS_PR="&FOR /f "delims=0123456789" %%i IN ("%APPVEYOR_PULL_REQUEST_NUMBER%") DO SET IS_PR=%%i

ECHO APPVEYOR^: %APPVEYOR%
ECHO commit message^: %APPVEYOR_REPO_COMMIT_MESSAGE%
ECHO pull request^: %APPVEYOR_PULL_REQUEST_NUMBER%
ECHO branch^: %APPVEYOR_REPO_BRANCH%
ECHO IS_PR^: %IS_PR%
ECHO PUBLISH^: %PUBLISH%
ECHO ENABLE_LOGGING^: %ENABLE_LOGGING%

ECHO nodejs_version^: %nodejs_version%
ECHO platform^: %platform%
ECHO msvs_toolset^: %msvs_toolset%
ECHO msvs_version^: %msvs_version%
ECHO TOOLSET_ARGS^: %TOOLSET_ARGS%

ECHO activating VS command prompt
IF /I "%platform%"=="x64" ECHO x64 && CALL "C:\Program Files (x86)\Microsoft Visual Studio %msvs_toolset%.0\VC\vcvarsall.bat" amd64
IF /I "%platform%"=="x86" ECHO x86 && CALL "C:\Program Files (x86)\Microsoft Visual Studio %msvs_toolset%.0\VC\vcvarsall.bat" x86
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO using compiler^: && cl
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO using MSBuild^: && msbuild /version && ECHO.
IF %ERRORLEVEL% NEQ 0 GOTO ERROR


ECHO downloading/installing node
::only use Install-Product when using VS2013
::IF /I "%APPVEYOR%"=="True" IF /I "%msvs_toolset%"=="12" powershell Install-Product node $env:nodejs_version $env:Platform
::TESTING:
::always install (get npm matching node), but delete installed programfiles node.exe afterwards for VS2015 (using custom node.exe)
IF /I "%APPVEYOR%"=="True" powershell Install-Product node $env:nodejs_version $env:Platform
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

IF /I "%msvs_toolset%"=="12" GOTO NODE_INSTALLED


::custom node for VS2015
SET ARCHPATH=
IF "%platform%"=="x64" (SET ARCHPATH=x64/)
SET NODE_URL=https://mapbox.s3.amazonaws.com/node-cpp11/v%nodejs_version%/%ARCHPATH%node.exe
ECHO downloading node^: %NODE_URL%
powershell Invoke-WebRequest "${env:NODE_URL}" -OutFile node.exe
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO deleting node ...
SET NODE_EXE_PRG=%ProgramFiles%\nodejs\node.exe
IF EXIST "%NODE_EXE_PRG%" ECHO found %NODE_EXE_PRG%, deleting... && DEL /F "%NODE_EXE_PRG%"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
SET NODE_EXE_PRG=%ProgramFiles(x86)%\nodejs\node.exe
IF EXIST "%NODE_EXE_PRG%" ECHO found %NODE_EXE_PRG%, deleting... && DEL /F "%NODE_EXE_PRG%"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR


:NODE_INSTALLED

ECHO available node.exe^:
where node
ECHO available npm^:
where npm

ECHO node^: && node -v
node -e "console.log(process.argv,process.execPath)"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO npm^: && CALL npm -v
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO ===== where npm puts stuff START ============
ECHO npm root && CALL npm root
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
ECHO npm root -g && CALL npm root -g
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO npm bin && CALL npm bin
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
ECHO npm bin -g && CALL npm bin -g
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

SET NPM_BIN_DIR=
FOR /F "tokens=*" %%i in ('CALL npm bin -g') DO SET NPM_BIN_DIR=%%i
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
IF /I "%NPM_BIN_DIR%"=="%CD%" ECHO ERROR npm bin -g equals local directory && SET ERRORLEVEL=1 && GOTO ERROR
ECHO ===== where npm puts stuff END ============


ECHO installing node-gyp
CALL npm install -g node-gyp
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO installing mocha fix
CALL npm install https://github.com/naturalatlas/mocha/archive/fix/333.tar.gz
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

CALL npm install --build-from-source --msvs_version=%msvs_version% %TOOLSET_ARGS% %ENABLE_LOGGING% --loglevel=http
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

FOR /F "tokens=*" %%i in ('CALL node_modules\.bin\node-pre-gyp reveal module --silent') DO SET MODULE=%%i
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
FOR /F "tokens=*" %%i in ('node -e "console.log(process.execPath)"') DO SET NODE_EXE=%%i
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

dumpbin /DEPENDENTS "%NODE_EXE%"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR
dumpbin /DEPENDENTS "%MODULE%"
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO calling npm test
CALL npm test
ECHO after tests
IF %ERRORLEVEL% NEQ 0 (ECHO ERRORLEVEL^: %ERRORLEVEL% && SET HAD_ERROR=1)

IF DEFINED APPVEYOR IF %PUBLISH% EQU 1 (appveyor PushArtifact test/artifacts/log.txt)

IF DEFINED HAD_ERROR SET ERRORLEVEL=1 && GOTO ERROR

CALL node_modules\.bin\node-pre-gyp package %TOOLSET_ARGS%
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

ECHO commit message^: %APPVEYOR_REPO_COMMIT_MESSAGE%
ECHO pull request^: %APPVEYOR_PULL_REQUEST_NUMBER%
ECHO branch^: %APPVEYOR_REPO_BRANCH%
ECHO IS_PR^: %IS_PR%
ECHO PUBLISH^: %PUBLISH%

IF %PUBLISH% EQU 1 (IF NOT DEFINED IS_PR (IF "%APPVEYOR_REPO_BRANCH%"=="master" node_modules\.bin\node-pre-gyp unpublish publish))
IF %ERRORLEVEL% NEQ 0 GOTO ERROR

GOTO DONE



:ERROR
ECHO ~~~~~~~~~~~~~~~~~~~~~~ ERROR %~f0 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
ECHO ERRORLEVEL^: %ERRORLEVEL%
SET EL=%ERRORLEVEL%

:DONE
ECHO ~~~~~~~~~~~~~~~~~~~~~~ DONE %~f0 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~

EXIT /b %EL%