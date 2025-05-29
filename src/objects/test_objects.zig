const std = @import("std");

pub const test_pdfobject = @import("test/test_pdfobject.zig");
pub const test_pdfname = @import("test/test_pdfname.zig");

test {
    std.testing.refAllDecls(@This());
}
