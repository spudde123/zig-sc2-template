# Zig-sc2-template

Template for a Starcraft 2 bot for competing on [sc2ai.net](https://sc2ai.net/), written in Zig 0.14.0.

## Running

1. Install [Zig](https://ziglang.org/).
2. Download the template including the submodule.
3. In the folder write `zig build run`. If you are using VS Code,
you can build and launch using the configs in the .vscode folder.
Debugging also works, for example with the VS Code configs or
with RemedyBG. Note that you need maps
placed in the correct folder inside your SC2 installation folder.
Make a folder called `Maps` there if it doesn't exist, and download
some maps from
[here](https://sc2ai.net/wiki/maps/#wiki-toc-current-map-pool).
To run a game on a specific map, you can write for example
`zig build run -- --Map StargazersAIE`.
4. To build a release build write `zig build -Doptimize=ReleaseSafe`
5. To build an executable that works on the sc2ai ladder write
`zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe`. There is also a python script
that builds the executable and takes the files in the `config` folder to the same zip
file, just in case you want to include some other files that your bot relies on.

## Examples

The examples folder includes some bots, one of which competes on the
sc2ai ladder. To quickly run for example the bot `one_base_terran` you
can write `zig build run -Dexample=one_base_terran`. `zig build`
builds your bot in `src/main.zig` if you don't give it an example as a parameter.

## CLI

Everything works on the SC2AI ladder without any customization, but
locally you can change what the program does through command line parameters:
- --SC2 "C:/My_Folder/StarCraft II"
    - Path to your SC2 folder. This needs to be set if it does not match with
    the defaults. Defaults are `"C:/Program Files (x86)/StarCraft II"` for Windows,
    `"/Applications/StarCraft II"` for Mac and `"~/StarCraftII"` for Linux.
- --Map StargazersAIE
    - Select the map. Can be whatever you have in your Maps folder
- --CompRace terran
    - Race for ingame AI. Options: `terran`, `zerg`, `protoss`, `random`.
- --CompDifficulty very_hard
    - Difficulty for ingame AI. Options: `very_easy`, `easy`, `medium`,
    `medium_hard`, `hard`, `harder`, `very_hard`, `cheat_vision`,
    `cheat_money`, `cheat_insane`.
- --CompBuild macro
    - Build for ingame AI. Options: `random`, `rush`, `timing`, `power`,
    `macro`, `air`.
- --RealTime
    - Play in real time instead of step mode.
- --Human
    - Play against your bot yourself. Two windows will open up, one for you and one
    for the bot.
- --GamePort
    - Decide the port your game is using locally to communicate with the program.

## Status

Should have everything you need to start making a bot. Some things may still evolve but
the data the user bot uses should remain stable. If you encounter some problems,
you can join the SC2AI Discord and ask for help. Link is on the front page of
[sc2ai.net](https://sc2ai.net/).
