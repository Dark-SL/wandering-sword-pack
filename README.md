# Wandering Sword: modpack and server

This repository is how the Wandering Sword server and its players stay up to date.
Everything here is downloaded automatically. You never need to touch these files.

## Players: how to join (PC, Java Edition)
Xbox, PlayStation, phones and Bedrock can't play; this is a Java Edition mod.

1. Install **Prism Launcher** (free): https://prismlauncher.org
2. Open it and sign in with your Microsoft account (Accounts → Add Microsoft).
3. Download **WanderingSword-Prism.zip** (from whoever runs the server), then in Prism click **Add Instance → Import** and choose the zip.
4. Press **Play**. The first launch installs NeoForge and the mod. Every launch after that checks for updates automatically.
5. **Multiplayer → Add Server** and enter the server address you were given (it looks like `something.joinmc.link`).

If the server says your mod version is out of date, close the game and press Play again; the launcher updates you first.

## Server
`server/setup.sh` installs everything on a fresh Ubuntu machine.
The server checks this repository every 3 minutes and restarts itself to apply updates. If people are online, it warns them 60 seconds before restarting.
