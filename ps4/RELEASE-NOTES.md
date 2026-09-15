OpenGothic for the PlayStation 4, on a jailbroken console (GoldHEN).

Vulkan on RADV (mesa-ps4), keyboard and mouse input.

## Install

1. Copy the `.pkg` to the console (for example over FTP to `/data/pkg/`) and install it with
   **Settings → Debug Settings → Package Installer** (or GoldHEN's package installer).
   It installs as **OpenGothic**, title id `TMPS10021`.
2. **Provide the game data yourself - it is NOT included and never will be.** Copy your own Gothic II
   installation (the directory that contains `Data` and `_work`) to the console, for example over FTP to:

   ```
   /data/gothic2/
   ```

   The title searches `/data`, `/mnt/usb0` … `/mnt/usb7` and, under each of them, the directory itself and
   `gothic2`, `Gothic2`, `GOTHIC2`, `GothicII`, `Gothic II`, `gothic`, `OpenGothic`. The first installation
   found is used, and every path looked at is written to the log.
3. **Connect a USB keyboard.** It is required - the game has no controller support yet, and without a
   keyboard it shows a "No keyboard detected" notice. A USB mouse is optional (camera and combat, as on a PC).
   Text is typed with a US layout.

Saves are kept in `/data/OpenGothic/`.

## Known issues

- **Closing the game from the PS4 system menu (Close Application) does not work** - the title does not
  answer the system's close request. Quit through **Exit** in the game's main menu instead; the process
  ends a few seconds later.
- No DualShock 4 support. It will be ported once upstream OpenGothic supports controllers.
