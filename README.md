# Trove

Ashita v4 addon for the [CatsEyeXI](https://catseyexi.com) private server.
Browse inventory, track collections, and manage storage — all in-game.

## Install

```
cd <Ashita>/addons
git clone git@github.com:LoxleyX/trove.git
```

Then in-game:

```
/addon load trove
```

`^z` toggles the window; `/trove` and `/box` also work. Anything else — e.g.
`/box fire crystal` — passes through to the server's `!box` chat command.

## Tabs

| Tab | Description |
|-----|-------------|
| E.Box | Browse and withdraw from Ephemeral Box (CW only) |
| Currency | View all currency balances |
| Points | View all point balances |
| Squire | Browse items stored with Squire |
| Crafting | Search any item, view recipes, drill into ingredients |

## Plugins

Plugins add floating windows accessible from the menu (`=` button).

| Plugin | Description | Access |
|--------|-------------|--------|
| Vault | Browse and withdraw from Mog Vault | All |
| VNM Armor | Track VNM armor pieces with Populox alerts | All |
| Keyring | Goblin Keyring chest/coffer key tracker | CW |
| Garrison | Garrison Pass item tracker | CW |
| Odious Codex | Dynamis pop item collection tracker | All |
| Stronghold | SCNM artifact collection tracker | All |
| Scrolls | Scroll collection tracker | CW |
| Lumoria | Sea collection tracker (armor, torques, weapons, organs, buffs) | All |
| Export | Export inventory, jobs, and merits to Lua file | All |
| Settings | Theme and display settings | All |

## Commands

| Command | Action |
|---------|--------|
| `/trove` | Toggle main window |
| `/trove vault` | Toggle Vault plugin |
| `/trove stronghold` | Toggle Stronghold plugin |
| `/trove scrolls` | Toggle Scrolls plugin |
| `/trove lumoria` | Toggle Lumoria plugin |
| `/trove sea` | Alias for lumoria |
| `/trove export` | Run inventory export |

## Requirements

Requires the CatsEyeXI server; the protocol is specific to it.

## License

MIT licensed.
