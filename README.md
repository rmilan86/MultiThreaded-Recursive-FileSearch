# MultiThreaded Recursive FileSearch

A multithreaded recursive directory scanner that enumerates all subfolders and files starting from a single root path, providing fast counts of directories, files, and total objects.

- Website: https://caporin.com
- License: GNU GPL v3.0
- Platform: Windows
- IDE: Delphi 12 (VCL)

## Features

- Recursively scans a single root folder
- Counts:
  - Directories
  - Files
  - Total objects (directories + files)
- Multithreaded scanning for speed on large folder trees
- UI updates are safe (engine queues callbacks to the main thread)

## Repo Layout

- `src/` — Delphi source (your `.dpr`, `.dproj`, `.pas`, `.dfm`)
- `tools/` — helper scripts (GPL header inserter)
- `assets/` — icons and screenshots

## Build

### Requirements

- Embarcadero Delphi 12
- Windows 10/11

### Steps

1. Open `src/MultiThreaded Recursive FileSearch.dproj` in Delphi.
2. Build (Debug/Release).
3. Run.

## Adding GPL Headers (Automatic)

From PowerShell, run:

```powershell
cd tools
.\add-gpl-headers.ps1 -Root ".."
```

This will add a GPLv3 header block to any `.pas` and `.dpr` files that do not already contain GPL text.

## License

This project is licensed under the **GNU General Public License v3.0**.  
See `LICENSE`.

## Credits

Created by **Robert Milan**  
https://caporin.com
