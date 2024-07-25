const std = @import("std");
const Build = std.Build;
const Step = Build.Step;
const Module = Build.Module;

// see https://github.com/sphaerophoria/ball-machine/blob/master/build.zig
const Chambers = struct {
    step: *Step,
    b: *Build,
    physics: *Module,
    graphics: *Module,

    fn init(b: *Build) Chambers {
        return .{
            .b = b,
            .step = b.step("chambers", "build all chambers"),
            .physics = Build.Module.create(b, .{ .root_source_file = b.path("src/physics.zig") }),
            .graphics = Build.Module.create(b, .{ .root_source_file = b.path("src/graphics.zig") }),
        };
    }

    fn wasmExe(self: *Chambers, name: []const u8, path: []const u8) *Step.Compile {
        const exe = self.b.addExecutable(.{
            .name = name,
            .root_source_file = self.b.path(path),
            .target = self.b.resolveTargetQuery(std.zig.CrossTarget.parse(.{ .arch_os_abi = "wasm32-freestanding" }) catch unreachable),
            .optimize = self.b.standardOptimizeOption(.{}),
        });
        exe.entry = .disabled;
        exe.rdynamic = true;
        exe.stack_size = 16384;
        return exe;
    }

    fn addZigChamber(self: *Chambers, name: []const u8, path: []const u8) *Step.Compile {
        const chamber = self.wasmExe(name, path);
        chamber.root_module.addImport("physics", self.physics);
        chamber.root_module.addImport("graphics", self.physics);
        const install_chamber = self.b.addInstallArtifact(chamber, .{});
        self.step.dependOn(&install_chamber.step);
        return chamber;
    }
};

pub fn build(b: *Build) void {
    var chambers = Chambers.init(b);
    _  = chambers.addZigChamber("pool_table", "src/pool_table.zig");
}
