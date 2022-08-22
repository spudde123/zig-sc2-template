# Zig-sc2-template

Template for a Starcraft 2 bot for competing on [sc2ai.net](https://sc2ai.net/), written in Zig 0.9.1.

## Running

1. Install [Zig](https://ziglang.org/).
2. Download the template including the submodule.
3. In the folder write `zig build` and `./zig-out/bin/zig-bot.exe`.
If you are using VS Code, you can build and launch using the configs in the .vscode folder. Debugging also works.
4. To build a release build write `zig build -Drelease-safe`
5. To build an executable that works on the sc2ai ladder write
`zig build -Dtarget=x86_64-linux -Drelease-safe`. There is also a .bat file that you can modify to directly generate
the zip for ladder. The script uses 7z from a certain path currently.
