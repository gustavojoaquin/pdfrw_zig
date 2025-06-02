const std = @import("std");

pub const test_pdfobject = @import("test/test_pdfobject.zig");
pub const test_pdfname = @import("test/test_pdfname.zig");
pub const test_pdfindirect = @import("test/test_pdfindirect.zig");

test {
    std.testing.refAllDecls(@This());
}
