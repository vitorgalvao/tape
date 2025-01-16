# <img src='https://user-images.githubusercontent.com/1699443/152702986-198e7e40-b0a4-43d1-8fd8-47e52033e6e5.png' width='45' align='center' alt='icon'> Tape

Tape is a command-line tool to backup and restore software settings on macOS. It can back up preferences for apps (including from the Mac App Store or Apples’s own), command-line tools, and even macOS customisations like your sounds or local spelling dictionary.

## Installation

Download the `tape` executable at the root of this repository and you’re good to go. Alternatively, install with [Homebrew](https://brew.sh):

```shell
brew install vitorgalvao/tiny-scripts/tape
```

## Configuration (optional)

Tape stores its configuration in `~/.config/tape/config.json`. If it doesn’t exist, it will be created on first run with sensible defaults. Quick example:

```
{
  "backup_to": "~/.config/tape/Backups",
  "keep": 5,
  "exclude": ["affinity-designer", "ssh"],
  "include": []
}
```

* `backup_to`: String. Directory to save backups to (leading `~` is expanded to your home directory).
* `keep`: Integer. Number of backups to keep. Must be higher than zero.
* `exclude`: Array. By default, Tape backs up settings for every software it knows how, except the ones on this list.
* `include`: Array. If set, *only* these will be backed up and the `exclude` list will be ignored.

To see what is included or excluded from backups, run `tape list`. To add to `include` or `exclude`, use the app token: (`tape list tokens`).

By default, Tape will backup its own configuration with the others.

## How it works

Tape backs up settings into compressed `.tgz` files. These are then used for restores when needed. This approach is conducive to experimentation, because as long as you keep a specific good configuration you can roll back to it.

## Usage

```
Backup and restore software settings on macOS

Usage:
  tape backup                Update definitions and backup settings
  tape restore <tgz> [def]   Restore settings from previous backup
                             Giving a definition name restores only that software
  tape list                  Show names of supported software separated by what will be backed up
  tape list tokens           Show tokens of supported software separated by what will be backed up
  tape launchd <on|off>      Load or unload an agent to perform daily backups
  tape update                Force update of backup definitions
  tape version               Show tape version
  tape help                  Show this help
```

If you intend to run Tape on-demand, run `tape backup` on occasion and you’re good to go. If you want to set it and forget it, run `tape launchd on` and it will automatically run backups for you everyday. Give them a look once in a blue moon to ensure everything is going smoothly.

## Supported software

Run `tape list` to see what’s supported.

## Contributing

The whole script is the single file `tape` at the root. Pull requests will be reviewed but please keep changes manageable—multiple small contributions are preferred to a large one.

To add support for new software, use one of the [definitions](https://github.com/vitorgalvao/tape/tree/main/Definitions) as a starting point. Two tips:

* Use `mdls -raw -name kMDItemCFBundleIdentifier /path/to/the/app` to find the bundle identifier of an app.
* Plist files in `~/Library/Preferences` are likely safe to skip because those are closely tied to the bundle identifier, thus implicitly taken care of by normal Tape backups.

## License

2-Clause BSD
