@echo off
setlocal ENABLEDELAYEDEXPANSION

REM ===== Capture script directory FIRST before any parsing =====
set "SCRIPT_DIR=%~dp0"
REM Remove trailing backslash from SCRIPT_DIR
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

REM ===== Parse command line arguments =====
set "TARGET_FOLDER_PARAM="
set "INFO_ONLY=0"
set "USE_MOVE=0"
set "COMBINE_PLATFORM=0"

:parse_args
if "%~1"=="" goto :end_parse

if /I "%~1"=="-i" (
    set "INFO_ONLY=1"
    shift
    goto :parse_args
)

if /I "%~1"=="-mv" (
    set "USE_MOVE=1"
    shift
    goto :parse_args
)

if /I "%~1"=="-combinePlatform" (
    set "COMBINE_PLATFORM=1"
    shift
    goto :parse_args
)

REM If not a flag, treat as folder path
if not defined TARGET_FOLDER_PARAM (
    set "TARGET_FOLDER_PARAM=%~1"
)
shift
goto :parse_args

:end_parse

REM Check if folder parameter was provided
if not defined TARGET_FOLDER_PARAM (
    echo Error: Target folder is required!
    echo.
    echo Usage: reorganiseAllSisFilesByUIVersion.bat [OPTIONS] "C:\Path\To\Symbian\Files"
    echo.
    echo Options:
    echo   -i                    Info mode - only print where files would be moved without copying
    echo   -mv                   Move files instead of copying them
    echo   -combinePlatform      Combine similar platforms into single folders
    echo                         Example: Series 60 v2.0, S60 2nd Edition FP1 and S60 2nd Edition FP2
    echo                         will be all moved to S60v2 folder
    echo.
    pause
    exit /b 1
)

REM Remove trailing backslash if present
if "%TARGET_FOLDER_PARAM:~-1%"=="\" set "TARGET_FOLDER_PARAM=%TARGET_FOLDER_PARAM:~0,-1%"

if not exist "%TARGET_FOLDER_PARAM%" (
    echo Error: Folder not found: %TARGET_FOLDER_PARAM%
    pause
    exit /b 1
)

REM ===== Configuration =====
REM Convert TARGET_FOLDER_PARAM to absolute path if it's relative
set "SCAN_DIR=%TARGET_FOLDER_PARAM%"
if not "%SCAN_DIR:~1,1%"==":" (
    pushd "%CD%"
    cd /d "%SCAN_DIR%" 2>nul
    if !ERRORLEVEL! EQU 0 (
        set "SCAN_DIR=!CD!"
        popd
    ) else (
        popd
        echo Error: Cannot access folder: %TARGET_FOLDER_PARAM%
        pause
        exit /b 1
    )
)

set "OUTPUT_DIR=%SCAN_DIR%\SymbianFilesOrganised"
set "UNIDENTIFIED_DIR=%OUTPUT_DIR%\UnidentifiedFiles"
set "HELPER_DIR=%SCRIPT_DIR%\reorganiseSisHelperScripts"
set "DETECTION_SCRIPT=%HELPER_DIR%\symbianOSPlatformId.ps1"
set "CSV_FILE=%HELPER_DIR%\symbianPlatformProductMachineUids.csv"
set "EXTRACT_SCRIPT=%HELPER_DIR%\extractArchive.bat"

REM ===== Special UID values for OS detection =====
set "SYMBIAN_OS9_UID=0x10201A7A"
set "SYMBIAN_OS6_UID=0x10003A12"
set "UNKNOWN_UID=0x00000000"

echo ===== Symbian Application Files Organizer =====
echo.

if "%INFO_ONLY%"=="1" (
    echo MODE: Information only - no files will be copied
    echo.
)

if "%USE_MOVE%"=="1" (
    echo MODE: Move files instead of copying
    echo.
)

if "%COMBINE_PLATFORM%"=="1" (
    echo MODE: Combine similar platforms into single folders
    echo.
)

echo Processing folder: %SCAN_DIR%
echo Script directory: %SCRIPT_DIR%
echo Helper scripts directory: %HELPER_DIR%
echo Detection script: %DETECTION_SCRIPT%
echo CSV file: %CSV_FILE%
echo Extract script: %EXTRACT_SCRIPT%
echo.

if not exist "%DETECTION_SCRIPT%" (
    echo Error: symbianOSPlatformId.ps1 not found at: %DETECTION_SCRIPT%
    pause
    exit /b 1
)

if not exist "%CSV_FILE%" (
    echo Error: CSV file not found at: %CSV_FILE%
    pause
    exit /b 1
)

if not exist "%EXTRACT_SCRIPT%" (
    echo Error: extractArchive.bat not found at: %EXTRACT_SCRIPT%
    pause
    exit /b 1
)

echo Loading UID mappings from CSV file...
set "UID_COUNT=0"
if exist "%CSV_FILE%" (
    for /f "usebackq tokens=1,2 delims=," %%A in ("%CSV_FILE%") do (
        REM Skip header row
        if not "%%A"=="UID" (
            set "uid_key=%%A"
            set "uid_value=%%B"
            REM Clean up the platform name - remove any trailing carriage return
            REM This handles the \r\n line endings in Windows CSV files
            set "clean_value="
            set "str=!uid_value!"
            REM Simple method: remove any trailing character that might be a carriage return
            if "!str:~-1!" LEQ " " (
                set "str=!str:~0,-1!"
            )
            REM Store the cleaned value
            set "uid[!uid_key!]=!str!"
            set /a "UID_COUNT+=1"
        )
    )
)
echo Loaded !UID_COUNT! UID mappings from CSV
echo.

if "%INFO_ONLY%"=="0" (
    echo Creating output directories in target folder...
    if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
    if not exist "%UNIDENTIFIED_DIR%" mkdir "%UNIDENTIFIED_DIR%"
)

REM ===== Process all SIS and archive files recursively =====
echo.
echo Scanning for Symbian files and archives...
echo.

set "TOTAL_FILES=0"
for /r "%SCAN_DIR%" %%F in (*.sis *.sisx *.zip *.rar) do (
    set "CHECK_FILE=%%F"
    REM Skip files already in output directories
    echo "!CHECK_FILE!" | findstr /I /C:"%OUTPUT_DIR%" >nul
    if !ERRORLEVEL! NEQ 0 (
        set /a "TOTAL_FILES+=1"
    )
)

echo Found !TOTAL_FILES! files to process
echo.

REM Process files with progress tracking
set "PROCESSED_FILES=0"
set "SKIPPED_FILES=0"
set "SKIPPED_LIST_FILE=%TEMP%\skipped_files_%RANDOM%.txt"
if exist "%SKIPPED_LIST_FILE%" del "%SKIPPED_LIST_FILE%"

for /r "%SCAN_DIR%" %%F in (*.sis *.sisx *.zip *.rar) do (
    set "CURRENT_FILE=%%F"
    set "CURRENT_NAME=%%~nxF"
    set "CURRENT_EXT=%%~xF"
    call :process_file_inline
)

echo.
echo ===== Organization Complete =====
if "%INFO_ONLY%"=="0" (
    echo Files organized in: %OUTPUT_DIR%
    echo Unidentified files in: %UNIDENTIFIED_DIR%
) else (
    echo Information scan complete - no files were copied
)
echo.

REM Display skipped files if any
if !SKIPPED_FILES! EQU 0 goto :no_errors
echo ===== WARNING: !SKIPPED_FILES! file(s) were skipped due to copy/move errors =====
echo.
if exist "%SKIPPED_LIST_FILE%" (
    REM Convert ^^ to ^ in the displayed list
    for /f "usebackq delims=" %%L in ("%SKIPPED_LIST_FILE%") do (
        set "LINE=%%L"
        set "LINE=!LINE:^^=^!"
        echo !LINE!
    )
    del "%SKIPPED_LIST_FILE%"
)
goto :end_script

:no_errors
if exist "%SKIPPED_LIST_FILE%" del "%SKIPPED_LIST_FILE%"

:end_script
pause
goto :eof

REM ===== Function: Process individual file inline =====
:process_file_inline
set "FILE_PATH=!CURRENT_FILE!"
set "FILE_NAME=!CURRENT_NAME!"
set "FILE_EXT=!CURRENT_EXT!"

REM Skip files already in output directories
echo "!FILE_PATH!" | findstr /I /C:"%OUTPUT_DIR%" >nul
if !ERRORLEVEL! EQU 0 (
    goto :eof
)

REM Increment processed counter and calculate percentage
set /a "PROCESSED_FILES+=1"
set /a "PERCENT=PROCESSED_FILES*100/TOTAL_FILES"
echo [!PERCENT!%%] Processing: !FILE_NAME!

setlocal ENABLEDELAYEDEXPANSION

REM Handle different file types
if /I "!FILE_EXT!"==".sis" goto :process_sis_inline
if /I "!FILE_EXT!"==".sisx" goto :process_sis_inline
if /I "!FILE_EXT!"==".zip" goto :process_archive_inline
if /I "!FILE_EXT!"==".rar" goto :process_archive_inline

echo ^> Unknown file type
endlocal
goto :eof

REM ===== Process archive files =====
:process_archive_inline
echo ^> Archive detected

if "%INFO_ONLY%"=="1" (
    echo ^> [INFO] Would extract and analyze archive contents
    echo ^> [INFO] Would copy ORIGINAL archive to appropriate folder based on detection
    endlocal
    goto :eof
)

REM Create temp extraction folder with unique name
set "EXTRACT_DIR=%TEMP%\SymbianExtract_%RANDOM%_%RANDOM%"
mkdir "!EXTRACT_DIR!" 2>nul

echo ^> Extracting to: !EXTRACT_DIR!

REM Call the extractArchive.bat script (silenced)
call "%EXTRACT_SCRIPT%" "!FILE_PATH!" "!EXTRACT_DIR!" >nul 2>&1

if !ERRORLEVEL! NEQ 0 (
    echo ^> Extraction failed, copying archive to UnidentifiedFiles\Unknown
    call :move_archive_to_unknown_inline
    rd /s /q "!EXTRACT_DIR!" 2>nul
    endlocal
    goto :eof
)

REM Search for SIS/SISX files in the extraction directory
echo ^> Searching for SIS/SISX files...
set "FOUND_SIS="

REM Find the first SIS/SISX file (prioritizing root level)
for /f "tokens=*" %%S in ('dir /b /s "!EXTRACT_DIR!\*.sis" "!EXTRACT_DIR!\*.sisx" 2^>nul') do (
    if not defined FOUND_SIS (
        set "FOUND_SIS=%%S"
        echo ^> Found SIS file: %%~nxS
    )
)

if not defined FOUND_SIS (
    echo ^> No SIS/SISX files found in archive, copying to UnidentifiedFiles\Unknown
    call :move_archive_to_unknown_inline
    rd /s /q "!EXTRACT_DIR!" 2>nul
    endlocal
    goto :eof
)

REM Process the found SIS file to detect platform
set "ORIG_FILE_PATH=!FILE_PATH!"
set "ORIG_FILE_NAME=!FILE_NAME!"
set "ORIG_FILE_EXT=!FILE_EXT!"

REM Temporarily set FILE_PATH to the SIS file for detection
set "FILE_PATH=!FOUND_SIS!"
for %%I in ("!FOUND_SIS!") do (
    set "FILE_NAME=%%~nxI"
    set "FILE_EXT=%%~xI"
)

REM Detect platform from the SIS file
call :detect_platform_inline

REM Restore original archive file info
set "FILE_PATH=!ORIG_FILE_PATH!"
set "FILE_NAME=!ORIG_FILE_NAME!"
set "FILE_EXT=!ORIG_FILE_EXT!"

REM Process based on detection results
if "!DETECTED_PLATFORM!"=="" (
    echo ^> Platform unknown, checking for special UIDs...
    if "!DETECTED_UID!"=="%SYMBIAN_OS9_UID%" (
        echo ^> Detected as Symbian OS 9+
        call :move_archive_to_symbian_os9_inline
    ) else if "!DETECTED_UID!"=="%SYMBIAN_OS6_UID%" (
        echo ^> Detected as Symbian OS 6/7/8
        call :move_archive_to_symbian_os6_inline
    ) else if "!DETECTED_UID!"=="%UNKNOWN_UID%" (
        echo ^> Unknown Symbian version
        call :move_archive_to_unknown_inline
    ) else (
        echo ^> Unknown UID, copying archive to UnidentifiedFiles\Unknown
        call :move_archive_to_unknown_inline
    )
    rd /s /q "!EXTRACT_DIR!" 2>nul
    endlocal
    goto :eof
)

echo ^> Platform detected: !DETECTED_PLATFORM!

REM Map platform to folder name using new method
call :map_platform_to_folder "!DETECTED_PLATFORM!"
set "TARGET_FOLDER=!MAPPED_FOLDER!"

if "!TARGET_FOLDER!"=="" (
    echo ^> Unable to map platform, copying archive to UnidentifiedFiles\Unknown
    call :move_archive_to_unknown_inline
    rd /s /q "!EXTRACT_DIR!" 2>nul
    endlocal
    goto :eof
)

echo ^> Target folder: !TARGET_FOLDER!

REM Create target platform folder if it doesn't exist
if not exist "%OUTPUT_DIR%\!TARGET_FOLDER!" mkdir "%OUTPUT_DIR%\!TARGET_FOLDER!"

REM Copy/Move the original archive to the target folder using new method
set "DEST_FILE=%OUTPUT_DIR%\!TARGET_FOLDER!\!FILE_NAME!"
call :copy_move_file_with_duplicate_check "!FILE_PATH!" "!DEST_FILE!" "archive"

REM Clean up extraction directory
rd /s /q "!EXTRACT_DIR!" 2>nul
endlocal
goto :eof

REM ===== Process SIS files =====
:process_sis_inline
REM Detect platform directly
call :detect_platform_inline

if "!DETECTED_PLATFORM!"=="" (
    echo ^> Platform unknown, checking for special UIDs...
    REM Check for special OS markers
    if "!DETECTED_UID!"=="%SYMBIAN_OS9_UID%" (
        echo ^> Detected as Symbian OS 9+
        call :move_file_to_symbian_os9_inline
    ) else if "!DETECTED_UID!"=="%SYMBIAN_OS6_UID%" (
        echo ^> Detected as Symbian OS 6/7/8
        call :move_file_to_symbian_os6_inline
    ) else if "!DETECTED_UID!"=="%UNKNOWN_UID%" (
        echo ^> Unknown Symbian version
        call :move_file_to_unknown_inline
    ) else (
        echo ^> Unknown UID, copying to UnidentifiedFiles\Unknown
        call :move_file_to_unknown_inline
    )
    endlocal
    goto :eof
)

echo ^> Platform detected: !DETECTED_PLATFORM!

REM Map platform to folder name
call :map_platform_to_folder "!DETECTED_PLATFORM!"
set "TARGET_FOLDER=!MAPPED_FOLDER!"

if "!TARGET_FOLDER!"=="" (
    echo ^> Unable to map platform, copying to UnidentifiedFiles\Unknown
    call :move_file_to_unknown_inline
    endlocal
    goto :eof
)

echo ^> Target folder: !TARGET_FOLDER!

if "%INFO_ONLY%"=="1" (
    echo ^> [INFO] Would copy to: %OUTPUT_DIR%\!TARGET_FOLDER!\!FILE_NAME!
    endlocal
    goto :eof
)


if not exist "%OUTPUT_DIR%\!TARGET_FOLDER!" mkdir "%OUTPUT_DIR%\!TARGET_FOLDER!"

set "DEST_FILE=%OUTPUT_DIR%\!TARGET_FOLDER!\!FILE_NAME!"
call :copy_move_file_with_duplicate_check "!FILE_PATH!" "!DEST_FILE!" "file"

endlocal
goto :eof

REM ===== Method: Map platform to folder name =====
:map_platform_to_folder
set "PLATFORM=%~1"
set "MAPPED_FOLDER="

REM If COMBINE_PLATFORM is NOT set, use the platform name directly
if "%COMBINE_PLATFORM%"=="0" (
    set "MAPPED_FOLDER=!PLATFORM!"
    goto :eof
)

REM Original mapping logic (only executed if COMBINE_PLATFORM is set)
echo !PLATFORM! | findstr /I /C:"60 v0.9" /C:"60 v1.2" >nul && set "MAPPED_FOLDER=S60v1"
echo !PLATFORM! | findstr /I /C:"60 v2.0" /C:"2nd Edition FP1" /C:"2nd Edition FP2" /C:"2nd Edition FP3" >nul && set "MAPPED_FOLDER=S60v2"
echo !PLATFORM! | findstr /I /C:"3rd Edition" >nul && set "MAPPED_FOLDER=S60v3"
echo !PLATFORM! | findstr /I /C:"5th Edition" /C:"Symbian Anna" /C:"Nokia Belle" >nul && set "MAPPED_FOLDER=S60v5"
echo !PLATFORM! | findstr /I /C:"UIQ v3" >nul && set "MAPPED_FOLDER=UIQ3"
echo !PLATFORM! | findstr /I /C:"UIQ v2" >nul && set "MAPPED_FOLDER=UIQ"
echo !PLATFORM! | findstr /I /C:"Series 80" >nul && set "MAPPED_FOLDER=s80"
echo !PLATFORM! | findstr /I /C:"Series 90" >nul && set "MAPPED_FOLDER=s90"

goto :eof

REM ===== Method: Copy or Move file with duplicate handling =====
:copy_move_file_with_duplicate_check
set "SOURCE_FILE=%~1"
set "DEST_FILE=%~2"
set "FILE_TYPE=%~3"

REM Convert ^^ to ^ (batch escapes ^ in for loops)
set "SOURCE_FILE=!SOURCE_FILE:^^=^!"
set "DEST_FILE=!DEST_FILE:^^=^!"

REM Extract filename components from source file
for %%F in ("!SOURCE_FILE!") do (
    set "SOURCE_FILENAME=%%~nxF"
    set "SOURCE_BASENAME=%%~nF"
    set "SOURCE_EXT=%%~xF"
)

REM Extract target directory from destination file path
for %%D in ("!DEST_FILE!") do set "TARGET_DIR=%%~dpD"

REM Ensure TARGET_DIR has a trailing backslash
if not "!TARGET_DIR:~-1!"=="\" set "TARGET_DIR=!TARGET_DIR!\"

REM Get just the folder name (not full path) for display
for %%D in ("!TARGET_DIR!.") do set "DISPLAY_FOLDER=%%~nD"

if not exist "!DEST_FILE!" (
    if "%USE_MOVE%"=="1" (
        if "!FILE_TYPE!"=="archive" (
            echo ^> Moving archive to !DISPLAY_FOLDER! folder
        ) else (
            echo ^> Moving to !DISPLAY_FOLDER! folder
        )
        move /Y "!SOURCE_FILE!" "!DEST_FILE!" >nul 2>&1
        if !ERRORLEVEL! NEQ 0 (
            echo ^> ERROR: Move failed, skipping file
            echo !SOURCE_FILE! >> "%SKIPPED_LIST_FILE%"
            set /a "SKIPPED_FILES+=1"
        )
    ) else (
        if "!FILE_TYPE!"=="archive" (
            echo ^> Copying archive to !DISPLAY_FOLDER! folder
        ) else (
            echo ^> Copying to !DISPLAY_FOLDER! folder
        )
        copy /Y "!SOURCE_FILE!" "!DEST_FILE!" >nul 2>&1
        if !ERRORLEVEL! NEQ 0 (
            echo ^> ERROR: Copy failed, skipping file
            echo !SOURCE_FILE! >> "%SKIPPED_LIST_FILE%"
            set /a "SKIPPED_FILES+=1"
        )
    )
) else (
    REM Handle duplicates with counter - using original logic
    set "FILE_BASE=!SOURCE_BASENAME!"
    set "counter=1"
    
    :check_duplicate
    set "new_name=!FILE_BASE! (!counter!)!SOURCE_EXT!"
    set "dest_path=!TARGET_DIR!!new_name!"
    
    if not exist "!dest_path!" (
        if "%USE_MOVE%"=="1" (
            if "!FILE_TYPE!"=="archive" (
                echo ^> Moving archive as !new_name!
            ) else (
                echo ^> Moving as !new_name!
            )
            move /Y "!SOURCE_FILE!" "!dest_path!" >nul 2>&1
            if !ERRORLEVEL! NEQ 0 (
                echo ^> ERROR: Move failed, skipping file
                echo !SOURCE_FILE! >> "%SKIPPED_LIST_FILE%"
                set /a "SKIPPED_FILES+=1"
            )
        ) else (
            if "!FILE_TYPE!"=="archive" (
                echo ^> Copying archive as !new_name!
            ) else (
                echo ^> Copying as !new_name!
            )
            copy /Y "!SOURCE_FILE!" "!dest_path!" >nul 2>&1
            if !ERRORLEVEL! NEQ 0 (
                echo ^> ERROR: Copy failed, skipping file
                echo !SOURCE_FILE! >> "%SKIPPED_LIST_FILE%"
                set /a "SKIPPED_FILES+=1"
            )
        )
    ) else (
        set /a "counter+=1"
        goto :check_duplicate
    )
)
goto :eof

REM ===== Inline helper: Detect platform =====
:detect_platform_inline
set "DETECTED_PLATFORM="
set "DETECTED_UID="

if not exist "%DETECTION_SCRIPT%" (
    echo ^> Error: symbianOSPlatformId.ps1 not found at: %DETECTION_SCRIPT%
    goto :eof
)

REM Use temp file to capture PowerShell output to avoid command-line parsing issues
set "TEMP_UID_FILE=%TEMP%\uid_%RANDOM%.txt"
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%DETECTION_SCRIPT%" "!FILE_PATH!" > "!TEMP_UID_FILE!" 2>nul

if exist "!TEMP_UID_FILE!" (
    for /f "usebackq delims=" %%P in ("!TEMP_UID_FILE!") do (
        set "DETECTED_UID=%%P"
    )
    del "!TEMP_UID_FILE!" 2>nul
)

if defined DETECTED_UID (
    echo ^> Detected UID: !DETECTED_UID!
    
    REM Check for special OS markers first
    if "!DETECTED_UID!"=="%SYMBIAN_OS9_UID%" goto :eof
    if "!DETECTED_UID!"=="%SYMBIAN_OS6_UID%" goto :eof
    if "!DETECTED_UID!"=="%UNKNOWN_UID%" goto :eof
    
    if defined uid[!DETECTED_UID!] (
        set "DETECTED_PLATFORM=!uid[%DETECTED_UID%]!"
        REM Clean up the platform name again in case it has carriage returns
        if "!DETECTED_PLATFORM:~-1!" LEQ " " (
            set "DETECTED_PLATFORM=!DETECTED_PLATFORM:~0,-1!"
        )
    ) else (
        echo ^> UID not in dictionary: !DETECTED_UID!
    )
) else (
    echo ^> No UID detected
)
goto :eof

REM ===== Method: Move file to OS-specific folder =====
:move_file_to_os_folder
set "OS_FOLDER=%~1"
set "FILE_PATH=!CURRENT_FILE!"
set "FILE_NAME=!CURRENT_NAME!"
set "FILE_EXT=!CURRENT_EXT!"

if "%INFO_ONLY%"=="1" (
    echo ^> [INFO] Would copy to: %UNIDENTIFIED_DIR%\!OS_FOLDER!\!FILE_NAME!
    goto :eof
)

if not exist "%UNIDENTIFIED_DIR%\!OS_FOLDER!" mkdir "%UNIDENTIFIED_DIR%\!OS_FOLDER!"

set "DEST_FILE=%UNIDENTIFIED_DIR%\!OS_FOLDER!\!FILE_NAME!"
call :copy_move_file_with_duplicate_check "!FILE_PATH!" "!DEST_FILE!" "file"
goto :eof

REM ===== Method: Move archive to OS-specific folder =====
:move_archive_to_os_folder
set "OS_FOLDER=%~1"
set "FILE_PATH=!CURRENT_FILE!"
set "FILE_NAME=!CURRENT_NAME!"
set "FILE_EXT=!CURRENT_EXT!"

if not exist "%UNIDENTIFIED_DIR%\!OS_FOLDER!" mkdir "%UNIDENTIFIED_DIR%\!OS_FOLDER!"

set "DEST_FILE=%UNIDENTIFIED_DIR%\!OS_FOLDER!\!FILE_NAME!"
call :copy_move_file_with_duplicate_check "!FILE_PATH!" "!DEST_FILE!" "archive"
goto :eof

:move_archive_to_symbian_os6_inline
call :move_archive_to_os_folder "SymbianOS6"
goto :eof

:move_archive_to_symbian_os9_inline
call :move_archive_to_os_folder "SymbianOS9"
goto :eof

:move_archive_to_unknown_inline
call :move_archive_to_os_folder "Unknown"
goto :eof

:move_file_to_symbian_os6_inline
call :move_file_to_os_folder "SymbianOS6"
goto :eof

:move_file_to_symbian_os9_inline
call :move_file_to_os_folder "SymbianOS9"
goto :eof

:move_file_to_unknown_inline
call :move_file_to_os_folder "Unknown"
goto :eof
