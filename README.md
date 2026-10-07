<h1 align=center>MiDnight Shell</h1>

<!-- test pkgit -->

<div align=center>

![GitHub last commit](https://img.shields.io/github/last-commit/stringptr/midnight-shell?style=for-the-badge&labelColor=101418&color=9ccbfb)
![GitHub Repo stars](https://img.shields.io/github/stars/dim-ghub/stringptr?style=for-the-badge&labelColor=101418&color=b9c8da)
![GitHub repo size](https://img.shields.io/github/repo-size/stringptr/midnight-shell?style=for-the-badge&labelColor=101418&color=d3bfe6)

</div>

> [!NOTE]
> This is a fork of MiDnight Shell, which itself is a fork of the official [caelestia-shell](https://github.com/caelestia-dots/shell) with additional features. New features compared to upstream are listed below.

<https://github.com/user-attachments/assets/774a8872-4d95-45b9-a4b6-409d8394dadc>

## Fork Features

This fork adds the following features on top of the official shell:

- **Launchers**: Emoji Picker, Clipboard History, Window Switcher, and Niri Keybinds.
- **Wallpapers**: GIF/video support with auto-pause, plus Wallhaven integration.
- **Bad Apple Easter Egg**: A custom shader effect that plays Bad Apple directly through the shell's UI material by masking the background and preserving the shell's native translucent blur and shadow effects.
- **Games**: Playable Chrome Dino runner embedded in the notification dock.
- **Dashboard**: Developer console terminal tab with history and autocomplete.
- **Bar**: MacOS-style app dock, Material workspace icons, DND toggle, and a live drag-and-drop components editor.
- **Desktop**: Floating lyrics, Shimeji pets, dynamic wallpaper recoloring, and Bezel Mode.
- **Lock Screen**: Configurable auto-lock on startup (`lockOnStartup`), redesigned profile and clock layout, and improved forecast UI.
- **Niri**: Full support for Niri WM integration and IPC.
- **QuickShare**: Supports the android feature, allowing file transfers between your devices (w/ avahi daemon)
- **Polkit**: Supplies its own built-in polkit daemon, with animations.
  
## Installation

> [!NOTE]
> This repository is a **FORK**, and can be out of date or have missing features from the [upstream](https://github.com/dim-ghub/midnight-shell).
> This fork is available at [stringptr/midnight-shell](https://github.com/stringptr/midnight-shell).

#### Manual installation

To install the shell manually, install all dependencies and clone **this fork** to `$XDG_CONFIG_HOME/quickshell/caelestia`.
Then simply build and install using `cmake`:

```sh
cd $XDG_CONFIG_HOME/quickshell
git clone https://github.com/dim-ghub/midnight-shell.git caelestia

cd caelestia
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
cmake --build build
sudo cmake --install build
```

> [!TIP]
> You can customise the installation location via the CMake flags `INSTALL_LIBDIR`, `INSTALL_QMLDIR`, and
> `INSTALL_QSCONFDIR` for the libraries (e.g. the version helper), QML plugin, and Quickshell config directories
> respectively. If you set the `INSTALL_LIBDIR` flag, the `CAELESTIA_LIB_DIR` variable must also be set to
> the same directory in your system's environment.
>
> For example, installing to `~/.config/quickshell/caelestia` for easy local changes:
>
> ```sh
> mkdir -p ~/.config/quickshell/caelestia
> cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ -DINSTALL_QSCONFDIR="$HOME/.config/quickshell/caelestia"
> cmake --build build
> sudo cmake --install build
> sudo chown -R $USER ~/.config/quickshell/caelestia
> ```

### Nix
>
> [!WARNING]
> This repository has limited/no support for NixOS! Proceed at your own risk.

You can run the shell directly via `nix run`:

```sh
nix run github:stringptr/midnight-shell
```

Or add it to your system configuration:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    midnight-shell = {
      url = "github:stringptr/midnight-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

The package is available as `midnight-shell.packages.<system>.default`, which can be added to your
`environment.systemPackages`, `users.users.<username>.packages`, `home.packages` if using home-manager,
or a devshell. The shell can then be run via `midnight-shell`.

## Components

- Widgets: [`Quickshell`](https://quickshell.outfoxxed.me)
- Window manager: [`Niri`](https://github.com/YaLTeR/niri)

## Migration from Official Caelestia

If you're migrating from the official caelestia shell to this fork, you may need to update your `shell.json` to include the new configuration options:

```json
"launcher": {
    "favouriteEmojis": [],
    "favouriteClips": []
},
"shimeji": {
    "enabled": false,
    "path": "root:/assets/shimeji/pusheen/",
    "count": 1,
    "autoHide": true,
    "excludedScreens": [],
    "screenCounts": {}
},
"background": {
    "videoWallpaperPaused": false,
    "videoWallpaperSoundEnabled": false,
    "videoWallpaperPauseOnFullscreen": false,
    "videoWallpaperPauseOnTiled": false,
    "videoWallpaperPauseOnAllDisplays": false,
    "videoWallpaperMuteOnMedia": false,
    "desktopLyrics": {
        "enabled": false,
        "autoHide": true,
        "scale": 1.0,
        "position": "bottom-center",
        "alignment": 1,
        "invertColors": false,
        "background": {
            "enabled": false,
            "opacity": 0.7,
            "blur": true
        },
        "shadow": {
            "enabled": true,
            "opacity": 0.7,
            "blur": 0.4
        }
    }
},
"utilities": {
    "quickToggles": [
        { "id": "wallpaper", "enabled": true },
        { "id": "badapple", "enabled": true },
        { "id": "pauseWallpaper", "enabled": true }
    ]
}
```

## Usage

### Shortcuts/IPC

All keybinds are accessible via Niri global shortcuts.

All IPC commands can be accessed via `qs -c ~/.config/quickshell/caelestia ipc show`, for example:

### PFP/Wallpapers

The profile picture for the dashboard is read from the file `~/.face`. You can set it by clicking it in the dashboard,
or by manually copying or symlinking your image to the path.

The wallpapers for the wallpaper switcher are read from `~/Pictures/Wallpapers`
by default. To change it, modify `paths.wallpaperDir` in `~/.config/caelestia/shell.json`.

To set the wallpaper, you can type `>wallpaper` in the launcher to open the wallpaper switcher.
Alternatively, you can also use `caelestia wallpaper -f <path_to_wallpaper>` to set the wallpaper directly.
Use `caelestia wallpaper -h` for more info about this command.

## Configuring

All configuration options belong in `~/.config/caelestia/shell.json`. This file is _not_ created by
default; you must create it manually. Options that you omit from the config file will use their default
values.

### Per-monitor configuration

You can configure per-monitor options in `~/.config/caelestia/monitors/<monitor_name>/shell.json`.
List the names of your available monitors by running:

```sh
niri msg -j outputs | jq -r 'keys[]'
```

Options set in these files will **override** the respective options in the global config. Any options not present in
per-monitor configs will inherit their values from the global config.

For example, to automatically hide the bar on the monitor named `DP-1`:

**`~/.config/caelestia/monitors/DP-1/shell.json`**

```json
{
    "bar": {
        "persistent": false
    }
}
```

> [!NOTE]
> Not all options respect per-monitor overrides. Most notably, the following options will only read
> from the global config, and ignore the respective option in per-monitor config files.
>
> <details><summary>Ignored options</summary>
>
> - `appearance` (`anim`, `transparency`, `islands`, `pitchBlack`, `shadow`, `blur`)
> - `general` (`logo`, `apps`, `idle`, `battery`)
> - `bar.workspaces` (`perMonitorWorkspaces`, `specialWorkspaceIcons`, `windowIcons`, `wsIcons`)
> - `bar.tray` (`iconSubs`, `hiddenIcons`)
> - `dashboard` (`mediaUpdateInterval`, `resourceUpdateInterval`)
> - `launcher` (`specialPrefix`, `actionPrefix`, `enableDangerousActions`, `vimKeybinds`,
>   `favouriteApps`, `hiddenApps`, `actions`)
> - `launcher.useFuzzy` (`apps`, `actions`, `schemes`, `variants`, `wallpapers`)
> - `notifs` (`expire`, `fullscreen`, `defaultExpireTimeout`, `fullscreenExpireTimeout`, `actionOnClick`)
> - `lock` (`enableFprint`, `maxFprintTries`)
> - `nexus` (`networkRescanInterval`)
> - `utilities.toasts` (all except `fullscreen`)
> - `utilities.vpn` (`enabled`, `provider`)
> - `services` (`weatherLocation`, `useFahrenheit`, `useFahrenheitPerformance`, `useTwelveHourClock`,
>   `gpuType`, `visualiserBars`, `audioIncrement`, `brightnessIncrement`, `maxVolume`, `smartScheme`,
>   `defaultPlayer`, `playerAliases`, `lyricsBackend`, `lyricsRomanized`)
> - `paths` (`wallpaperDir`, `lyricsDir`)
>
> </details>

### Example configuration

> [!WARNING]
> The example configuration includes **ALL** configuration options in `shell.json`. It is
> **not** recommended to copy and paste this entire configuration into `shell.json`,
> as options or their default values may change across updates, resulting in a stale config.
>
> This is meant to serve as a reference of all the available options, and you should
> <ins>only add the ones you want to change</ins> to `shell.json`.

<details><summary>Example config</summary>

```json
{
    "ai": {
        "activeOllamaModel": "llama3",
        "activeProvider": "ollama",
        "defaultOllamaModel": "llama3",
        "defaultProvider": "ollama",
        "enableCelestialMode": false,
        "enableOllama": true,
        "enableOpenClaw": false,
        "enableOpenRouter": false,
        "ollamaModel": "llama3",
        "ollamaUrl": "http://localhost:11434",
        "openClawModel": "openclaw/default",
        "openClawToken": "",
        "openClawUrl": "http://127.0.0.1:18789",
        "openRouterApiKey": "",
        "openRouterModel": "openrouter/auto",
        "openRouterUrl": "https://openrouter.ai/api/v1",
        "recentModels": [],
        "saveChatHistory": true,
        "snapToDefaultOllama": true
    },
    "appearance": {
        "anim": {
            "durations": {
                "scale": 1
            }
        },
        "blur": {
            "enabled": false
        },
        "deformScale": 1,
        "font": {
            "body": {
                "family": "GoogleSansFlex",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 16,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 400
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 14,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 400
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 12,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 400
                }
            },
            "clock": "Rubik",
            "headline": {
                "family": "GoogleSansFlex",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 32,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 28,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 24,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                }
            },
            "icon": {
                "extraLarge": {
                    "family": "",
                    "italic": false,
                    "size": 36,
                    "vaxes": {},
                    "weight": 400
                },
                "family": "Material Symbols Rounded",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 24,
                    "vaxes": {},
                    "weight": 400
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 18,
                    "vaxes": {},
                    "weight": 400
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 15,
                    "vaxes": {},
                    "weight": 400
                }
            },
            "label": {
                "family": "GoogleSansFlex",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 14,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 12,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 11,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 400
                }
            },
            "mono": {
                "family": "CaskaydiaCove NF",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 16,
                    "vaxes": {},
                    "weight": 400
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 14,
                    "vaxes": {},
                    "weight": 400
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 12,
                    "vaxes": {},
                    "weight": 400
                }
            },
            "scale": 1,
            "title": {
                "family": "GoogleSansFlex",
                "large": {
                    "family": "",
                    "italic": false,
                    "size": 22,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "medium": {
                    "family": "",
                    "italic": false,
                    "size": 16,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                },
                "small": {
                    "family": "",
                    "italic": false,
                    "size": 14,
                    "vaxes": {
                        "ROND": 25
                    },
                    "weight": 500
                }
            },
            "workspaces": "Rubik"
        },
        "padding": {
            "scale": 1
        },
        "pitchBlack": false,
        "rounding": {
            "scale": 1
        },
        "spacing": {
            "scale": 1
        },
        "transparency": {
            "base": 0.85,
            "enabled": false,
            "layers": 0.4
        }
    },
    "audio": {
        "sounds": {
            "cameraClick": true,
            "chargingStarted": true,
            "disabledNotifApps": [],
            "effectTick": true,
            "enabled": true,
            "lock": true,
            "lowBattery": true,
            "notificationSound": "Iapetus.wav",
            "notificationVolume": 1,
            "screenRecord": true,
            "sfxVolume": 1,
            "unlock": true
        }
    },
    "general": {
        "logo": "",
        "showOverFullscreen": false,
        "mediaGifSpeedAdjustment": 300,
        "sessionGifSpeed": 0.7,
        "apps": {
            "terminal": ["foot"],
            "audio": ["pwvucontrol"],
            "playback": ["mpv"],
            "explorer": ["thunar"]
        },
        "idle": {
            "lockBeforeSleep": true,
            "inhibitWhenAudio": true,
            "inhibitWhenCharging": false,
            "timeouts": [
                {
                    "timeout": 180,
                    "idleAction": "lock",
                    "inhibitWhenAudio": false,
                    "inhibitWhenCharging": false,
                    "respectInhibitors": true
                },
                {
                    "timeout": 300,
                    "idleAction": "dpms off",
                    "returnAction": "dpms on"
                },
                {
                    "timeout": 600,
                    "idleAction": ["suspendThenHibernate"]
                }
            ]
        },
        "battery": {
            "warnLevels": [
                {
                    "level": 20,
                    "title": "Low battery",
                    "message": "You might want to plug in a charger",
                    "icon": "battery_android_frame_2"
                },
                {
                    "level": 10,
                    "title": "Did you see the previous message?",
                    "message": "You should probably plug in a charger <b>now</b>",
                    "icon": "battery_android_frame_1"
                },
                {
                    "level": 5,
                    "title": "Critical battery level",
                    "message": "PLUG THE CHARGER RIGHT NOW!!",
                    "icon": "battery_android_alert",
                    "critical": true
                }
            ],
            "criticalLevel": 3
        }
    },
    "background": {
        "desktopClock": {
            "background": {
                "blur": true,
                "enabled": false,
                "opacity": 0.7
            },
            "enabled": false,
            "invertColors": false,
            "position": "bottom-right",
            "scale": 1,
            "shadow": {
                "blur": 0.4,
                "enabled": true,
                "opacity": 0.7
            }
        },
        "desktopLyrics": {
            "alignment": 1,
            "appFilter": "Disabled",
            "autoHide": true,
            "background": {
                "blur": true,
                "enabled": false,
                "opacity": 0.7
            },
            "enabled": false,
            "filteredApps": [
                "Spotify"
            ],
            "invertColors": false,
            "position": "bottom-center",
            "scale": 1,
            "shadow": {
                "blur": 0.4,
                "enabled": true,
                "opacity": 0.7
            }
        },
        "enabled": true,
        "videoWallpaperMuteOnMedia": false,
        "videoWallpaperPauseOnAllDisplays": false,
        "videoWallpaperPauseOnFullscreen": false,
        "videoWallpaperPauseOnTiled": false,
        "videoWallpaperPaused": false,
        "videoWallpaperSoundEnabled": false,
        "visualiser": {
            "appFilter": "Disabled",
            "autoHide": true,
            "blur": false,
            "enabled": false,
            "filteredApps": [
                "Spotify"
            ],
            "renderer": "gpu",
            "rounding": 1,
            "spacing": 1
        },
        "wallpaperEnabled": true
    },
    "bar": {
        "persistent": true,
        "showOnHover": true,
        "dragThreshold": 20,
        "scrollActions": {
            "workspaces": true,
            "volume": true,
            "brightness": true
        },
        "popouts": {
            "activeWindow": true,
            "tray": true,
            "statusIcons": true
        },
        "workspaces": {
            "shown": 5,
            "activeIndicator": true,
            "occupiedBg": false,
            "showWindows": true,
            "showWindowsOnSpecialWorkspaces": true,
            "maxWindowIcons": 5,
            "activeTrail": false,
            "perMonitorWorkspaces": true,
            "displayType": "shapes",
            "label": "  ",
            "occupiedLabel": "󰮯",
            "activeLabel": "󰮯",
            "capitalisation": "preserve",
            "specialWorkspaceIcons": [
                {
                    "name": "steam",
                    "icon": "sports_esports"
                }
            ],
            "ignoredTags": [
                "hide_in_bar",
                "xwl_popup"
            ],
            "windowIcons": [
                {
                    "regex": "steam(_app_(default|[0-9]+))?",
                    "icon": "sports_esports"
                }
            ]
        },
        "activeWindow": {
            "compact": false,
            "inverted": false,
            "showOnHover": true
        },
        "clock": {
            "background": false,
            "showDate": false,
            "showIcon": true
        },
        "dock": {
            "monitorCenter": true,
            "recolourIcons": false
        },
        "spotify": {
            "appFilter": "Disabled",
            "autoHide": false,
            "background": false,
            "filteredApps": [
                "Spotify"
            ],
            "horizontalVolume": false,
            "inverted": false,
            "maxTitleLength": 25,
            "showVisualiser": true
        },
        "dragThreshold": 20,
        "peripheralBatteryExcluded": [],
        "statusIcons": [
            {
                "id": "lockStatus",
                "enabled": true
            },
            {
                "id": "audio",
                "enabled": false
            },
            {
                "id": "microphone",
                "enabled": false
            },
            {
                "id": "kbLayout",
                "enabled": false
            },
            {
                "id": "network",
                "enabled": true
            },
            {
                "id": "bluetooth",
                "enabled": true
            },
            {
                "id": "battery",
                "enabled": true
            },
            {
                "id": "peripheralBattery",
                "enabled": false
            },
            {
                "id": "notifications",
                "enabled": true
            }
        ],
        "tray": {
            "background": false,
            "compact": false,
            "hiddenIcons": [],
            "iconSubs": [],
            "recolour": false
        },
        "workspaces": {
            "activeIndicator": true,
            "activeLabel": " \udb82\udfaf",
            "activeTrail": false,
            "capitalisation": "preserve",
            "label": "\uf444 ",
            "maxWindowIcons": 5,
            "occupiedBg": false,
            "occupiedLabel": " \udb82\udfaf",
            "perMonitorWorkspaces": true,
            "showWindows": true,
            "showWindowsOnSpecialWorkspaces": true,
            "shown": 5,
            "specialWorkspaceIcons": [],
            "useIcon": true,
            "windowIcons": [
                {
                    "icon": "sports_esports",
                    "regex": "steam(_app_(default|[0-9]+))?"
                }
            ],
            "wsIcons": []
        }
    },
    "border": {
        "rounding": 25,
        "smoothing": 20,
        "thickness": 10
    },
    "dashboard": {
        "colorizeMediaGif": true,
        "dragThreshold": 50,
        "enabled": true,
        "keepAlive": true,
        "mediaUpdateInterval": 500,
        "performance": {
            "showBattery": true,
            "showCpu": true,
            "showGpu": true,
            "showMemory": true,
            "showNetwork": true,
            "showStorage": true
        },
        "profilePicShape": 9,
        "resourceUpdateInterval": 1000,
        "showDashboard": true,
        "showMedia": true,
        "showOnHover": true,
        "showPerformance": true,
        "showTerminal": true,
        "showWeather": true
    },
    "enabled": true,
    "general": {
        "apps": {
            "audio": [
                "pavucontrol"
            ],
            "explorer": [
                "thunar"
            ],
            "playback": [
                "mpv"
            ],
            "terminal": [
                "foot"
            ]
        },
        "battery": {
            "criticalLevel": 3,
            "warnLevels": [
                {
                    "icon": "battery_android_frame_2",
                    "level": 20,
                    "message": "You might want to plug in a charger",
                    "title": "Low battery"
                },
                {
                    "icon": "battery_android_frame_1",
                    "level": 10,
                    "message": "You should probably plug in a charger <b>now</b>",
                    "title": "Did you see the previous message?"
                },
                {
                    "critical": true,
                    "icon": "battery_android_alert",
                    "level": 5,
                    "message": "PLUG THE CHARGER RIGHT NOW!!",
                    "title": "Critical battery level"
                }
            ]
        },
        "idle": {
            "inhibitWhenAudio": true,
            "lockBeforeSleep": true,
            "timeouts": [
                {
                    "idleAction": "lock",
                    "timeout": 180
                },
                {
                    "idleAction": "dpms off",
                    "returnAction": "dpms on",
                    "timeout": 300
                },
                {
                    "idleAction": [
                        "loginctl",
                        "suspend"
                    ],
                    "timeout": 600
                }
            ]
        },
        "logo": "",
        "mediaGifSpeedAdjustment": 300,
        "sessionGifSpeed": 0.7,
        "showOverFullscreen": false
    },
    "launcher": {
        "actionPrefix": ">",
        "actions": [
            {
                "command": [
                    "autocomplete",
                    "calc"
                ],
                "description": "Do simple math equations (powered by Qalc)",
                "icon": "calculate",
                "name": "Calculator"
            },
            {
                "command": [
                    "autocomplete",
                    "scheme"
                ],
                "description": "Change the current colour scheme",
                "icon": "palette",
                "name": "Scheme"
            },
            {
                "command": [
                    "autocomplete",
                    "wallpaper"
                ],
                "description": "Change the current wallpaper",
                "icon": "image",
                "name": "Wallpaper"
            },
            {
                "command": [
                    "autocomplete",
                    "variant"
                ],
                "description": "Change the current scheme variant",
                "icon": "colors",
                "name": "Variant"
            },
            {
                "command": [
                    "caelestia",
                    "wallpaper",
                    "-r"
                ],
                "description": "Switch to a random wallpaper",
                "icon": "casino",
                "name": "Random"
            },
            {
                "command": [
                    "setMode",
                    "light"
                ],
                "description": "Change the scheme to light mode",
                "icon": "light_mode",
                "name": "Light"
            },
            {
                "command": [
                    "setMode",
                    "dark"
                ],
                "description": "Change the scheme to dark mode",
                "icon": "dark_mode",
                "name": "Dark"
            },
            {
                "command": [
                    "loginctl",
                    "poweroff"
                ],
                "dangerous": true,
                "description": "Shutdown the system",
                "icon": "power_settings_new",
                "name": "Shutdown"
            },
            {
                "command": [
                    "loginctl",
                    "reboot"
                ],
                "dangerous": true,
                "description": "Reboot the system",
                "icon": "cached",
                "name": "Reboot"
            },
            {
                "command": [
                    "niri",
                    "msg",
                    "action",
                    "quit"
                ],
                "dangerous": true,
                "description": "Log out of the current session",
                "icon": "exit_to_app",
                "name": "Logout"
            },
            {
                "command": [
                    "loginctl",
                    "lock-session"
                ],
                "description": "Lock the current session",
                "icon": "lock",
                "name": "Lock"
            },
            {
                "command": [
                    "loginctl",
                    "suspend"
                ],
                "description": "Suspend then hibernate",
                "icon": "bedtime",
                "name": "Sleep"
            },
            {
                "command": [
                    "caelestia",
                    "shell",
                    "nexus",
                    "open"
                ],
                "description": "Configure the shell",
                "icon": "settings",
                "name": "Settings"
            },
            {
                "command": [
                    "autocomplete",
                    "emoji"
                ],
                "description": "Pick an emoji to copy",
                "icon": "emoji_emotions",
                "name": "Emoji"
            },
            {
                "command": [
                    "autocomplete",
                    "clipboard"
                ],
                "description": "View clipboard history",
                "icon": "content_paste",
                "name": "Clipboard"
            },
            {
                "command": [
                    "autocomplete",
                    "windows"
                ],
                "description": "Switch to another window",
                "enabled": true,
                "icon": "apps",
                "name": "Windows"
            },
            {
                "command": [
                    "autocomplete",
                    "keybinds"
                ],
                "description": "View all keybinds",
                "icon": "keyboard",
                "name": "Keybinds"
            }
        ],
        "dragThreshold": 50,
        "enableDangerousActions": false,
        "enabled": true,
        "favouriteApps": [],
        "favouriteClips": [],
        "favouriteEmojis": [],
        "hiddenApps": [],
        "keepAlive": true,
        "maxShown": 7,
        "maxWallpapers": 9,
        "showOnHover": false,
        "specialPrefix": "@",
        "useFuzzy": {
            "actions": false,
            "apps": false,
            "clipboard": false,
            "emoji": false,
            "schemes": false,
            "variants": false,
            "wallpapers": false
        },
        "vimKeybinds": false
    },
    "lock": {
        "enabled": true,
        "useWallpaper": false,
        "enableFprint": true,
        "hideNotifs": false,
        "maxFprintTries": 3,
        "profilePicShape": 12,
        "recolourLogo": true,
        "enableHowdy": true,
        "maxHowdyTries": 3,
        "triggerHowdyOnWake": true
    },
    "nexus": {
        "networkRescanInterval": 15000,
        "wallpapersPerRow": 4
    },
    "notifs": {
        "actionOnClick": false,
        "clearThreshold": 0.3,
        "defaultExpireTimeout": 5000,
        "expandThreshold": 20,
        "expire": true,
        "fullscreen": "On",
        "defaultExpireTimeout": 5000,
        "fullscreenExpireTimeout": 2000,
        "groupPreviewNum": 3,
        "openExpanded": false
    },
    "osd": {
        "enableBrightness": true,
        "enableMicrophone": false,
        "enabled": true,
        "hideDelay": 2000
    },
    "paths": {
        "cacheDir": "/home/dim/.cache/caelestia",
        "lockNoNotifsPic": "root:/assets/dino.png",
        "lyricsDir": "/home/dim/Music/Lyrics/",
        "mediaGif": "root:/assets/bongocat.gif",
        "noNotifsPic": "root:/assets/dino.png",
        "sessionGif": "root:/assets/kurukuru.gif",
        "wallpaperDir": "/home/dim/Pictures/Wallpapers"
    },
    "services": {
        "weatherLocation": "",
        "useFahrenheit": false,
        "useFahrenheitPerformance": false,
        "useTwelveHourClock": false,
        "gpuType": "Auto",
        "visualiserBars": 60,
        "audioIncrement": 0.1,
        "brightnessIncrement": 0.1,
        "defaultPlayer": "Spotify",
        "gpuType": "",
        "lyricsBackend": "Auto",
        "lyricsRomanized": false,
        "maxVolume": 1,
        "playerAliases": [
            {
                "from": "com.github.th_ch.youtube_music",
                "to": "YT Music"
            }
        ],
        "smartScheme": true,
        "useFahrenheit": true,
        "useFahrenheitPerformance": false,
        "useTwelveHourClock": true,
        "visualiserBars": 60,
        "weatherLocation": ""
    },
    "session": {
        "commands": {
            "hibernate": [
                "loginctl",
                "hibernate"
            ],
            "logout": [
                "niri",
                "msg",
                "action",
                "quit"
            ],
            "reboot": [
                "loginctl",
                "reboot"
            ],
            "shutdown": [
                "loginctl",
                "poweroff"
            ],
            "lock": [
                "loginctl",
                "lock-session"
            ]
        },
        "dragThreshold": 30,
        "enabled": true,
        "icons": {
            "hibernate": "downloading",
            "logout": "logout",
            "reboot": "cached",
            "shutdown": "power_settings_new",
            "lock": "lock"
        },
        "vimKeybinds": false
    },
    "shimeji": {
        "autoHide": true,
        "count": 1,
        "enabled": true,
        "excludedScreens": [],
        "path": "root:/assets/shimeji/pusheen/",
        "screenCounts": {}
    },
    "sidebar": {
        "enabled": true,
        "showOnHover": false,
        "minHoverThreshold": 200,
        "dragThreshold": 80
    },
    "utilities": {
        "enabled": true,
        "maxToasts": 4,
        "quickToggles": [
            {
                "enabled": true,
                "id": "wifi"
            },
            {
                "enabled": true,
                "id": "bluetooth"
            },
            {
                "enabled": true,
                "id": "quickshare"
            },
            {
                "enabled": true,
                "id": "mic"
            },
            {
                "enabled": true,
                "id": "settings"
            },
            {
                "enabled": true,
                "id": "gameMode"
            },
            {
                "enabled": true,
                "id": "dnd"
            },
            {
                "enabled": false,
                "id": "vpn"
            },
            {
                "enabled": true,
                "id": "wallpaper"
            },
            {
                "enabled": true,
                "id": "badapple"
            }
        ],
        "toasts": {
            "audioInputChanged": true,
            "audioOutputChanged": true,
            "capsLockChanged": true,
            "chargingChanged": true,
            "configLoaded": true,
            "dndChanged": true,
            "fullscreen": "off",
            "gameModeChanged": true,
            "kbLayoutChanged": true,
            "kbLimit": true,
            "nowPlaying": false,
            "numLockChanged": true,
            "transparency": false,
            "transparencyBase": 0.85,
            "vpnChanged": true
        },
        "vpn": {
            "enabled": false,
            "provider": []
        }
    },
    "winfo": {}
}
```

</details>

### Shell blur (compositor)

Frosted glass behind the bar, the screen border, every drawer panel and the Nexus
window is done by the compositor, not by the shell: `modules/drawers/ContentWindow.qml`
publishes the footprint of each panel — and `modules/nexus/WindowFactory.qml` the
dedicated Nexus window — as a `BackgroundEffect.blurRegion`, and Niri frosts exactly
those rectangles through the `ext-background-effect-v1` protocol. Enable it under
**Nexus → Wallpaper & style → Blur behind shell panels** (or set
`appearance.blur.enabled`), alongside **Transparency** — an opaque shell surface has
nothing to blur.

Requirements:

- **Niri 26.04 or newer.** Older Niri builds do not know the protocol, so the toggle
  silently does nothing.
- Blur must not be switched off globally in your Niri config — a top-level
  `blur { off }` block disables every background effect.
- Include the shipped rules (`assets/niri/caelestia.kdl`) from your Niri config so the
  shell's blur stays neutral even if you tune the global `blur {}` block. If you
  maintain your own rules instead, mirror them:

  ```kdl
  layer-rule {
      match namespace="^caelestia-drawers$"
      background-effect {
          xray true
          noise 0
          saturation 1
      }
  }

  window-rule {
      match title="^Nexus"
      background-effect {
          xray true
          noise 0
          saturation 1
      }
  }
  ```

  Neither rule must set `blur true`: `caelestia-drawers` is a fullscreen surface, so
  it would frost the whole desktop and every window behind it, and the Nexus window
  would frost its transparent corners as a square. Omitting `blur` leaves the client
  region in charge.

### Advanced configuration

> [!CAUTION]
> Do NOT change any of these options unless you know what you are doing. These options control the
> tokens used internally within the shell, and can cause visual issues if modified incorrectly.
> The available options may change or be removed without notice across versions.

A separate `~/.config/caelestia/shell-tokens.json` file allows editing the internal tokens without
touching the source code of the shell. These tokens affect the dimensions and appearance of visual elements,
including individual rounding, spacing, padding, font size, animation durations and curves, and the sizes of
certain components. The appearance scale values in `shell.json` are multiplied against these base
token values to produce the final computed values.

Per-monitor token overrides are also available at
`~/.config/caelestia/monitors/<monitor_name>/shell-tokens.json`.
