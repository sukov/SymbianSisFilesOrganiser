@echo off
setlocal enabledelayedexpansion
:: Check if parameters are provided
if "%~1"=="" (
    echo Usage: %~nx0 ARCHIVE_FILE TEMP_DIR
    echo Example: %~nx0 "C:\Downloads\archive.rar" "C:\Temp\Extract"
    exit /b 1
)
if "%~2"=="" (
    echo Usage: %~nx0 ARCHIVE_FILE TEMP_DIR
    echo Example: %~nx0 "C:\Downloads\archive.rar" "C:\Temp\Extract"
    exit /b 1
)
set "SOURCE_ARCHIVE=%~1"
set "TEMP_DIR=%~2"
:: Validate source archive exists
if not exist "%SOURCE_ARCHIVE%" (
    echo Error: Archive "%SOURCE_ARCHIVE%" does not exist.
    exit /b 1
)
:: Create temp directory if it doesn't exist
if not exist "%TEMP_DIR%" (
    mkdir "%TEMP_DIR%" >nul 2>&1
    if errorlevel 1 (
        echo Error: Could not create temp directory "%TEMP_DIR%"
        exit /b 1
    )
    echo Created temp directory: %TEMP_DIR%
)
:: Determine which extraction tool to use
set "EXTRACTOR="
set "EXTRACTOR_TYPE="
if exist "%ProgramFiles%\WinRAR\winrar.exe" (
    set "EXTRACTOR=%ProgramFiles%\WinRAR\winrar.exe"
    set "EXTRACTOR_TYPE=WINRAR"
    echo Using WinRAR for extraction
) else if exist "%~dp07z.exe" (
    set "EXTRACTOR=%~dp07z.exe"
    set "EXTRACTOR_TYPE=7ZIP"
    echo Using 7-Zip for extraction
) else (
    echo Error: No extraction tool found.
    echo Please ensure WinRAR is installed or 7z.exe is in the script folder.
    exit /b 1
)
echo.
echo Extracting: %SOURCE_ARCHIVE%
echo to: %TEMP_DIR%
echo.
:: Extract the initial archive to temp directory
echo Extracting initial archive...
if "!EXTRACTOR_TYPE!"=="WINRAR" (
    "!EXTRACTOR!" x -ibck -y -o+ -inul "%SOURCE_ARCHIVE%" "%TEMP_DIR%" 2>nul
    set "EXTRACT_RESULT=!errorlevel!"
) else (
    "!EXTRACTOR!" x "%SOURCE_ARCHIVE%" -o"%TEMP_DIR%" -y >nul 2>&1
    set "EXTRACT_RESULT=!errorlevel!"
)
if !EXTRACT_RESULT! neq 0 (
    echo ERROR: Failed to extract the initial archive.
    exit /b 1
)
echo Successfully extracted initial archive.
echo.
:: Initialize failed archives tracking file
set "FAILED_ARCHIVES=%TEMP%\failed_archives_%RANDOM%.tmp"
type nul > "%FAILED_ARCHIVES%"
:: Main extraction loop for nested archives
:EXTRACT_LOOP
set "FOUND_ARCHIVES=0"
:: Search for archives in temp directory and extract them
for /r "%TEMP_DIR%" %%F in (*.zip *.rar) do (
    if exist "%%F" (
        set "ARCHIVE=%%F"
        set "ARCHIVE_DIR=%%~dpF"
        set "ARCHIVE_NAME=%%~nxF"
        
        :: Check if this archive has failed before
        set "SKIP_ARCHIVE=0"
        findstr /x /c:"!ARCHIVE!" "%FAILED_ARCHIVES%" >nul 2>&1
        if !errorlevel! equ 0 (
            set "SKIP_ARCHIVE=1"
        )
        
        if "!SKIP_ARCHIVE!"=="0" (
            set "FOUND_ARCHIVES=1"
            
            echo Extracting nested archive: !ARCHIVE_NAME!
            
            :: Extract based on tool type
            if "!EXTRACTOR_TYPE!"=="WINRAR" (
                "!EXTRACTOR!" x -ibck -y -o+ -inul "!ARCHIVE!" "!ARCHIVE_DIR!" 2>nul
                set "EXTRACT_RESULT=!errorlevel!"
            ) else (
                "!EXTRACTOR!" x "!ARCHIVE!" -o"!ARCHIVE_DIR!" -y >nul 2>&1
                set "EXTRACT_RESULT=!errorlevel!"
            )
				
            :: Check if extraction was successful
            if !EXTRACT_RESULT! equ 0 (
                echo Successfully extracted: !ARCHIVE_NAME!
                :: Delete the archive after successful extraction
                del /f /q "!ARCHIVE!" >nul 2>&1
                if !errorlevel! equ 0 (
                    echo Deleted: !ARCHIVE_NAME!
                ) else (
                    echo Warning: Could not delete !ARCHIVE_NAME!
                )
                echo.
            ) else (
                echo ERROR: Failed to extract !ARCHIVE_NAME! (possibly missing parts, corrupted or password protected)
                echo Skipping deletion of: !ARCHIVE_NAME!
                :: Add to failed archives list to prevent re-processing
                echo !ARCHIVE!>> "%FAILED_ARCHIVES%"
                echo Added to skip list to prevent infinite loop.
                echo.
            )
        )
    )
)
:: If archives were found and extracted, loop again to check for more nested archives
if "!FOUND_ARCHIVES!"=="1" (
    echo Checking for more nested archives...
    echo.
    goto EXTRACT_LOOP
)
:: Clean up temporary failed archives file
if exist "%FAILED_ARCHIVES%" del /f /q "%FAILED_ARCHIVES%" >nul 2>&1
echo.
echo Extraction complete! No more nested archives found.
echo.
echo Final extracted content is in: %TEMP_DIR%
echo.
endlocal
exit /b 0