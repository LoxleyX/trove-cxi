# Trove

Ashita v4 addon for the [CatsEyeXI](https://catseyexi.com) private server.
Browse inventory, find parties, track collections, and manage storage — all in-game.

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
| Party | Party Finder — browse LFG/LFM listings, register, join parties, duty roulette |
| Currency | View all currency balances with colored section headers |
| Points | View all point balances with colored section headers |
| Squire | Browse items stored with Squire |
| Crafting | Search any item, view recipes, drill into ingredients |

## Party Finder

The Party tab integrates the full Party Finder system directly into Trove:

- **LFM/LFG listings** with job icons (AF headpiece textures), comments visible inline
- **Register** as Looking for Group or Looking for Members with role, category, and comment
- **Join parties** via double-click or right-click context menu
- **Duty Roulette** and **Mission Help** with ready check flow
- **Auto-accept** with minimum level filter for LFM leaders
- **Game mode filtering** — CW players only see CW listings (always enforced)
- **CW insignia** displayed on Crystal Warrior listing cards
- **Status bar** — registration status visible from every tab above the tab bar
- **Activity log** — timestamped event feed

## Top Bar

The top bar shows contextual information:

- **Left**: Job icon + level (e.g. WAR75/NIN37), swaps to PF status when registered
- **Right**: VNM alert button (appears only when a VNM is active) + Menu dropdown

## Plugins

Plugins add floating windows accessible from the Menu button.

| Plugin | Description | Access |
|--------|-------------|--------|
| Vault | Browse, withdraw, and deposit to Mog Vault | All |
| VNM Armor | Track VNM armor pieces with Populox alerts | All |
| Keyring | Goblin Keyring chest/coffer key tracker | CW |
| Garrison | Garrison Pass item tracker | CW |
| Odious Codex | Dynamis pop item collection tracker | All |
| Stronghold | SCNM artifact collection tracker | All |
| Scrolls | Scroll collection tracker | CW |
| Lumoria | Sea collection tracker (armor, torques, weapons, organs, buffs) | All |
| Storage Slips | Browse Mog Storage Slip contents | All |
| Export | Export inventory, jobs, and merits to Lua file | All |
| Settings | Theme and display settings | All |

## Commands

| Command | Action |
|---------|--------|
| `/trove` | Toggle main window |
| `/trove pf` | Load Party Finder data |
| `/trove vault` | Toggle Vault plugin |
| `/trove stronghold` | Toggle Stronghold plugin |
| `/trove scrolls` | Toggle Scrolls plugin |
| `/trove lumoria` | Toggle Lumoria plugin |
| `/trove sea` | Alias for lumoria |
| `/trove slips` | Toggle Storage Slips plugin |
| `/trove export` | Run inventory export |

## Requirements

Requires the CatsEyeXI server; the protocol is specific to it.

## License

MIT licensed.
