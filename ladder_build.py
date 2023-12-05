import os
import argparse
import subprocess
import zipfile

valid_examples = {
    "one_base_terran": True,
    "mass_reaper": True,
    "two_base_protoss": True
}

def main():
    parser = argparse.ArgumentParser(
        description="Create a zip for the sc2ai ladder."
    )
    parser.add_argument("-n", "--name", required=True, help="Name of the executable in the zip. Needs to be the same as your bot name on sc2ai.net.")
    parser.add_argument("-e", "--example", help="For example 'one_base_terran'. Leave empty when building your own bot.")
    args = parser.parse_args()
    if args.example and args.example not in valid_examples:
        print(f"{args.example} is not a valid example name.")
        return

    cmd = ["zig", "build", "-Dtarget=x86_64-linux", "-Doptimize=ReleaseSafe"]
    exe_name = "zig-bot" if not args.example else args.example

    if args.example:
        cmd.append("-Dexample={}".format(args.example))

    subprocess.run(cmd)
    
    with zipfile.ZipFile(f"{args.name}.zip", 'w', zipfile.ZIP_DEFLATED) as zip_folder:
        files = os.listdir("./ladder_build")
        for file in files:
            zip_folder.write(f"./ladder_build/{file}", arcname=file)
        zip_folder.write(f"./zig-out/bin/{exe_name}", arcname=args.name)


if __name__ == "__main__":
    main()
