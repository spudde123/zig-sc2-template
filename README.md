# Zig-sc2-template

Template for a Starcraft 2 bot for competing on [sc2ai.net](https://sc2ai.net/), written in Zig 0.10.0.

## Running

1. Install [Zig](https://ziglang.org/).
2. Download the template including the submodule.
3. In the folder write `zig build run`.
If you are using VS Code, you can build and launch using the configs in the .vscode folder. Debugging also works.
4. To build a release build write `zig build -Drelease-safe`
5. To build an executable that works on the sc2ai ladder write
`zig build -Dtarget=x86_64-linux -Drelease-safe`. There is also a python script
that builds the executable and takes the files in the `ladder_build` folder to the same zip
file.

## Examples

The examples folder includes some bots, one of which competes on the
sc2ai ladder. To quickly run for example the bot `one_base_terran` you
can write `zig build run -- one_base_terran`. In general `zig build`
builds your bot in `src/main` if you don't give it parameters. If you
do it tries to build an example with that name.

## Status

Still lacking important features and being actively worked on so things may change. Testing it out is fine, but probably better to wait
a while before starting a real bot.
