const std = @import("std");
const c = @import("c");
const mem = std.mem;
const testing = std.testing;

const Allocator = mem.Allocator;

/// A temporary struct to hold extracted information for a single DTB node.
pub const DtbNodeInfo = struct {
    name: []const u8,
    dev_type: ?[]const u8,
    // We use an ArrayList because we don't know the number of compatible strings at compile time.
    compatibles: std.ArrayList([]const u8),
    firmware_name: std.ArrayList([]const u8),

    /// Frees the memory owned by this struct (specifically the compatibles list).
    pub fn deinit(self: *const DtbNodeInfo) void {
        self.compatibles.deinit();
        self.firmware_name.deinit();
    }
};

/// Extracts name, device_type, and a list of compatible strings for a given node offset.
fn extractNodeInfo(
    allocator: Allocator,
    fdt_ptr: *const anyopaque,
    offset: c_int,
) !DtbNodeInfo {
    var info = DtbNodeInfo{
        .name = "",
        .dev_type = null,
        .compatibles = std.ArrayList([]const u8).init(allocator),
        .firmware_name = std.ArrayList([]const u8).init(allocator),
    };

    // 1. Get the node name (e.g., "i2c@ff150000")
    // fdt_get_name returns a pointer to the name within the DTB blob itself.
    if (c.fdt_get_name(fdt_ptr, offset, null)) |name_ptr| {
        info.name = mem.sliceTo(name_ptr, 0);
    } else {
        return error.NameNotFound;
    }

    // 2. Get the 'device_type' property (optional)
    var prop_len: c_int = 0;
    if (c.fdt_getprop(fdt_ptr, offset, "device_type", &prop_len)) |prop_ptr| {
        if (prop_len > 0) {
            info.dev_type = @as([*]const u8, @ptrCast(prop_ptr))[0..@intCast(prop_len - 1)];
        }
    }

    // 3. Get the 'compatible' property (a list of null-terminated strings)
    if (c.fdt_getprop(fdt_ptr, offset, "compatible", &prop_len)) |prop_ptr| {
        if (prop_len > 0) {
            const prop_slice = @as([*]const u8, @ptrCast(prop_ptr))[0..@intCast(prop_len)];
            var current: usize = 0;
            while (current < prop_slice.len) {
                // Find the next null terminator to get the string length
                const str = mem.sliceTo(prop_slice[current..], 0);
                if (str.len == 0) break; // End of list (double null)

                try info.compatibles.append(str);
                current += str.len + 1; // Move past the string and its null terminator
            }
        }
    }

    // 4. Get the 'firmware-name' property (a list of null-terminated strings)
    if (c.fdt_getprop(fdt_ptr, offset, "firmware-name", &prop_len)) |prop_ptr| {
        if (prop_len > 0) {
            const prop_slice = @as([*]const u8, @ptrCast(prop_ptr))[0..@intCast(prop_len)];
            var current: usize = 0;
            while (current < prop_slice.len) {
                // Find the next null terminator to get the string length
                const str = mem.sliceTo(prop_slice[current..], 0);
                if (str.len == 0) break; // End of list (double null)

                try info.firmware_name.append(str);
                current += str.len + 1; // Move past the string and its null terminator
            }
        }
    }

    return info;
}

pub const Iterator = struct {
    offset: c_int = 0,
    fdt: []const u8,
    gpa: mem.Allocator,

    pub fn init(fdt: []const u8, gpa: mem.Allocator) Iterator {
        std.debug.assert(c.fdt_check_header(fdt.ptr) == 0);
        return .{ .fdt = fdt, .gpa = gpa };
    }

    pub fn next(self: *Iterator) !?DtbNodeInfo {
        // 1. Find the node AFTER the one we previously returned.
        const next_offset = c.fdt_next_node(self.fdt.ptr, self.offset, null);

        // 2. Check if we've reached the end or an error occurred.
        if (next_offset < 0) {
            if (next_offset == -c.FDT_ERR_NOTFOUND) {
                // This is the normal, successful end of iteration.
                return null;
            }
            // Any other negative value is a real error.
            return error.DtbParseError;
        }

        // 3. We have a valid new offset. Update our state for the next call.
        self.offset = next_offset;

        // 4. NOW, extract the information using the known-good offset.
        return try extractNodeInfo(self.gpa, self.fdt.ptr, self.offset);
    }

    pub fn reset(self: *Iterator) void {
        self.offset = 0;
    }
};

test {
    const fdt_path = "testdata/x1e80100-asus-vivobook-s15.dtb";

    const fdt_blob = try std.fs.cwd().readFileAlloc(testing.allocator, fdt_path, 4 * 1024 * 1024);
    defer testing.allocator.free(fdt_blob);

    var it = Iterator.init(fdt_blob, testing.allocator);
    while (try it.next()) |node_info| {
        defer node_info.deinit();
    }
}
