# Confirm Buff Removal

A small World of Warcraft addon for **WoW Forever** that stops you from removing a buff by accident.

Normally, right-clicking one of your buffs removes it straight away. With this addon you get a dialog first:

> Are you sure you want to remove **Power Word: Fortitude**?  
> [Accept] [Cancel]

The buff is only removed if you click **Accept**. Escape cancels, and Enter does nothing, so a stray key press can't remove it either.

Only your buffs are protected. Debuffs and weapon enchants behave as usual.

## When it takes a second right-click

The game does not let addons remove buffs during combat. So in combat, Accept unlocks that one buff for 5 seconds instead, and a second right-click removes it. Every other buff stays protected.

Druid forms, Stealth and Shadowform always work this way, even out of combat, because the game never lets addons remove them.

## Installation

1. Download this repository (**Code > Download ZIP**) and unzip it.
2. Copy the `ConfirmBuffRemoval` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game, or type `/reload` if it is already running.

There are no settings and no saved data.

## Compatibility

- Made for WoW Forever (interface 16001).
- Covers the default buff frame, including the consolidated-buffs pop-out. Addons that replace the buff frame with their own are not covered.
- In a vehicle, the buff frame shows the vehicle's buffs. Those are left alone.

## How it works

An invisible frame sits on top of each of your buff buttons and catches the right-click before the game sees it, which opens the dialog. When you click Accept, the addon removes the buff itself. When the game doesn't allow that, the addon briefly hides its frame over that one buff, so your next right-click reaches the game's own button instead.

All of the code is in [`ConfirmBuffRemoval.lua`](ConfirmBuffRemoval/ConfirmBuffRemoval.lua). It starts with a longer explanation and is commented throughout.

## Repository layout

```text
ConfirmBuffRemoval/              The addon itself: the folder you install.
    ConfirmBuffRemoval.toc       Tells the game the addon's name, version and files.
    ConfirmBuffRemoval.lua       All of the addon's code.
CHANGELOG.md                     What changed in each version.
LICENSE                          The MIT license.
README.md                        This file.
.editorconfig                    Indentation and line-ending settings for editors.
.gitattributes                   Keeps line endings consistent in git.
.gitignore                       Files git should ignore.
```

## Reporting a problem

Please [open an issue](https://github.com/sn0wmint/confirm_buff_removal/issues). It helps to say what you right-clicked and whether you were in combat. If there was a Lua error, include its text. You can turn error messages on with `/console scriptErrors 1`.

## License

Released under the [MIT License](LICENSE).
