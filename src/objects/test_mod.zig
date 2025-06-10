const std = @import("std");

pub const test_pdfobject = @import("test/test_pdfobject.zig");
pub const test_pdfname = @import("test/test_pdfname.zig");
pub const test_pdfindirect = @import("test/test_pdfindirect.zig");
pub const test_pdfarray = @import("test/test_pdfarray.zig");
pub const test_pdfdict = @import("test/test_pdfdict.zig");
pub const test_pdfstring = @import("test/test_pdfstring.zig");

test {
    std.testing.refAllDecls(@This());
}
