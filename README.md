# Symbian SIS/SISX File Organizer by UI Platform

A Windows batch script for organising **Symbian SIS/SISX application packages** by their target **UI platform**.  
Ideal for managing large Symbian software archives without manual sorting.

The script inspects SIS metadata to determine platform compatibility and then copies or moves files into platform-specific directories.

## Features

- Detects Symbian **UI platform** from SIS/SISX metadata
- Organises files into **platform-based folders**
- Supports **copy** and **move** modes
- **Dry-run (info) mode** to preview actions
- Optional **platform combine** (e.g. grouping similar S60 variants)
- Automatic extraction of **archives**, including nested archives

## Usage

1. Download the latest release from this repository
2. Extract it to your **Desktop** (or any preferred directory)
3. Open **Command Prompt** and navigate to the script location:
   ```bat
   cd /d %USERPROFILE%\Desktop
   ```
4. Run:
    ```bat
    reorganiseSisFilesByPlatform.bat PATH_TO_SYMBIAN_FOLDER
    ```

## Command-Line Options
* -i
Info mode — shows where files would be placed without copying or moving them.

* -mv
Move mode — moves files instead of copying them.

* -combinePlatform
Platform consolidation — merges closely related platforms into a single folder
(e.g. all S60 2nd Edition variants → S60v2).

## SISInfo Dependency

Symbian OS9+ platform detection is handled using **SISInfo**, a Symbian SIS inspection library.

- SISInfo was **compiled with Python 2.4.4**
- Original source (archived):  
  http://web.archive.org/web/20100213104423/http://www.niksula.cs.hut.fi/~jpsukane/sisinfo.html
