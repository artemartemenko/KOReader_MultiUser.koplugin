# KOReader MultiUser.koplugin

<p align="center">
  <img src="assets/Style_Tiles.png" width="300" alt="Tile picker style" />
  <img src="assets/Style_List.png" width="300" alt="List picker style" />
</p>

A plugin and patch for KOReader that adds isolated user profile support — each profile has its own settings, reading history, plugins, and patches. Reading position and bookmarks are independent per profile as long as each user keeps their books in a separate folder.

**Compatibility**
Tested on Kindle and Android devices. Other devices may work, but not guaranteed.

## Support

This plugin is part of an ongoing effort to extend KOReader with patches and plugins. If you'd like to support further development — new features, fixes, and more tools for KOReader — you can:

- star this repository on GitHub
- buy me a coffee on Ko‑fi:

[![Support me on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/artemartemenko)

## Menu flow

<p align="center">
  <img src="assets/Menu_1_Tools.png" width="300" alt="Tools menu entry" /><br/>
  Tools menu ↴
</p>

<p align="center">
  <img src="assets/Menu_2_MultiUser.png" width="300" alt="Main MultiUser menu" /><br/>
  Main MultiUser menu ↴
</p>

<p align="center">
  <img src="assets/Menu_3_MultiUser_Settings.png" width="300" alt="MultiUser settings menu" /><br/>
  MultiUser settings menu
</p>

<p align="center">
  <img src="assets/Menu_4_Switch_user.png" width="300" alt="Main menu with Switch user button" /><br/>
  Main menu with the <strong>Switch user...</strong> button.
</p>

## Features

- create and switch between multiple user profiles
- each profile has its own settings, history, cache, screenshots, and patches; plugins from the default profile are available to all users, with the option to add extra plugins per profile
- per-profile frontlight settings (brightness, warmth) saved and restored on switch
- user picker style: list or tile grid
- profile avatar images for the user picker screen
- configurable unlock screen: ask for user on device wake, with configurable idle timeout
- "Switch user…" shortcut in the main menu
- API for third-party patches (`THIRDPARTY_API.txt`)

### Profile avatars (recommended images)

For **user-picker** avatars, **square (1:1) images** work best.

**Resolution:** **512×512** pixels is a good default for e-ink screens.

**Supported formats:** **png** or **jpeg**.

## Installation

The plugin consists of two parts that must both be installed.

### 1. User patch

1. Download `1-multiuser.lua`.
2. Copy it to your KOReader patches directory:

   ```text
   koreader/patches/1-multiuser.lua
   ```

### 2. Plugin

1. Download the `multiuser.koplugin` folder (containing `main.lua` and `_meta.lua`).
2. Copy the entire folder to your KOReader plugins directory:

   ```text
   koreader/plugins/MultiUser.koplugin/
   ```

3. Restart KOReader.
4. Open the menu — you will see a new **Users** entry.

> Both parts are required. The patch (`1-multiuser.lua`) redirects data paths before the UI starts; the plugin (`multiuser.koplugin`) provides the menu and profile management.

## Profile data layout

Each profile's data is stored in a subdirectory of your KOReader base folder:

```text
koreader/
├── users.lua
└── users/
    ├── ProfileName/
    │   ├── settings/
    │   ├── docsettings/
    │   ├── history/
    │   ├── cache/
    │   ├── plugins/
    │   ├── patches/
    │   └── screenshots/
    └── AnotherProfile/
        └── …
```

The `default` default profile uses the standard KOReader data directory, so your existing settings, history, and bookmarks are preserved. You can also rename the `default` profile.

> **Note:** Plugins installed in the default KOReader plugins directory are available to all profiles. Additional plugins can be placed in a profile's own `plugins/` folder — they will be loaded on top of the shared ones. Plugin settings are always stored per profile, so each user has their own independent configuration even for shared plugins.

> **Note:** Reading position, bookmarks, and highlights are tracked per file path. If multiple users read the same book file, they will share a single progress record. To keep progress independent for each user, store their copies of the books in separate folders.

## Troubleshooting

**If KOReader fails to start or something stops loading after creating a new profile**, reset the plugin state by removing these two items from your KOReader root folder and restarting:

- the `users/` folder
- the `users.lua` file

This returns KOReader to its default single-user state.

## Third-party API

Other patches can interact with MultiUser at runtime via a stable Lua API. See `THIRDPARTY_API.txt` for full documentation.

Quick example:

```lua
local MU = require("koreader_multiuser_api")
if MU.apiIsAvailable() then
    for _, pid in ipairs(MU.apiGetProfileNames()) do
        -- MU.apiGetDisplayName(pid)
        -- MU.apiIsActiveProfile(pid)
        -- MU.apiSwitchToProfile(pid)
    end
end
```