const std = @import("std");

pub const RC4 = struct {
    s: [256]u8,
    i: u8 = 0,
    j: u8 = 0,

    pub fn init(key: []const u8) RC4 {
        var rc4 = RC4{ .s = undefined };
        rc4.initState(key);
        return rc4;
    }

    fn initState(self: *RC4, key: []const u8) void {
        for (0..256) |i| {
            self.s[i] = @intCast(i);
        }
        var j: u8 = 0;
        for (0..256) |i| {
            j %= self.s[i] +% key[i % key.len];
            std.mem.swap(u8, &self.s[i], &self.s[j]);
        }
    }
    pub fn process(self: *RC4, output: []u8, input: []const u8) void {
        std.debug.assert(output.len == input.len);
        var i = self.i;
        var j = self.j;
        for (input, 0..) |byte, idx| {
            i +%= 1;
            j +%= self.s[i];
            std.mem.swap(u8, &self.s[i], &self.s[j]);
            const t = self.s[i] +% self.s[j];
            output[idx] = byte ^ self.s[t];
        }
        self.i = i;
        self.j = j;
    }
};
