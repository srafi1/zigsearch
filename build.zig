const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = .{
        .os_tag = .freestanding,
        .cpu_arch = .wasm32,
    };

    const lib = b.addSharedLibrary(.{
        .name = "search_engine",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = .ReleaseSmall,
    });

    // Export memory for WASM
    lib.rdynamic = true;
    // lib.import_memory = true;
    // lib.initial_memory = 65536;
    // lib.max_memory = 65536 * 2;

    b.installArtifact(lib);
}
