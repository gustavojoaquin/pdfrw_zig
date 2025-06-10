const std = @import("std");

pub const PdfError = error{
    Parse,
    Output,
    NotImplemented,
    OutOfMemory,
    NoSpaceLeft,
    Utf8CannotEncodeSurrogateHalf,
    CodepointTooLarge,
    InvalidCharacter,
    InvalidPdfStringFormat,
    InvalidHexCharacter,
    InvalidOctalEscape,
    EncodingError,
    InvalidLength,
    InvalidReference,
    ObjectNotFound,
    CorruptStream,
    InvalidPdfFormat,
    IndexOutOfBounds,
};

pub fn pdfErrorName(err: PdfError) []const u8 {
    return switch (err) {
        error.Parse => "ParseError",
        error.Output => "OutputError",
        error.NotImplemented => "NotImplementedError",
    };
}

pub fn initLogging(allocator: std.mem.Allocator) !void {
    try std.log.addWriter(allocator, .{
        .writer = std.io.getStdErr().writer(),
        .formatter = &logFormatter,
    });

    std.log.setLevel(.warn);
}

fn logFormatter(
    comptime level: std.log.Level,
    comptime _: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) std.fmt.FormatError!void {
    const writer = std.io.getStdErr().writer();
    try writer.print("[{s}] ", .{@tagName(level)});
    if (@src()) |src_info| {
        try writer.print("{s}:{} ", .{
            std.fs.path.basename(src_info.file),
            src_info.line,
        });
    }
    try writer.print(format ++ "\n", args);
}
