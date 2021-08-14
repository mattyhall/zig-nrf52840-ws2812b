const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("nrf52", "src/main.zig");
    exe.setTarget(.{
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m4 },
        .os_tag = .freestanding,
        .abi = .eabi,
    });
    exe.setBuildMode(mode);
    exe.addAssemblyFile("gcc_startup_nrf52.S");
    exe.addIncludeDir(".");
    exe.setLinkerScriptPath(.{ .path = "linker_script.ld" });
    exe.install();

    const bin = b.addInstallRaw(exe, "nrf52.bin");
    bin.step.dependOn(&exe.step);
    const bin_step = b.step("bin", "Generate binary file to be flashed");
    bin_step.dependOn(&bin.step);

    const flash_cmd = b.addSystemCommand(&[_][]const u8{
        "nrfjprog",
        "-f",
        "nrf52",
        "--program",
        b.getInstallPath(bin.dest_dir, bin.dest_filename),
        "--sectorerase",
    });
    flash_cmd.step.dependOn(&bin.step);

    const reset_cmd = b.addSystemCommand(&[_][]const u8{
        "nrfjprog",
        "-f",
        "nrf52",
        "--reset",
    });
    reset_cmd.step.dependOn(&flash_cmd.step);

    const flash_step = b.step("flash", "Flash the binary to the dk");
    flash_step.dependOn(&reset_cmd.step);
}
