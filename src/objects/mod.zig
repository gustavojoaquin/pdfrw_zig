pub const pdfindirect = @import("pdfindirect.zig");
pub const pdfobject = @import("pdfobject.zig");

comptime {
    _ = @import("test/test_pdfobject.zig");
    _ = @import("test/test_pdfname.zig");
}
//     @import("std").testing.refAllDecls(@This());
// }
