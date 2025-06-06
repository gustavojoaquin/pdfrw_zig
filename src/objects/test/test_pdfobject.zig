const std = @import("std");
const pdfobject = @import("../pdfobject.zig");
const pdfindirect = @import("../pdfindirect.zig");

const PdfIndirect = pdfindirect.PdfIndirect;
const PdfObject = pdfobject.PdfObject;
const allocator = std.testing.allocator;

test "PdfPbject initialization" {
    const null_obj = PdfObject.initNull();
    try std.testing.expect(null_obj == .Null);

    const true_obj = PdfObject.initBoolean(true);
    try std.testing.expect(true_obj == .Boolean and true_obj.Boolean == true);

    const false_obj = PdfObject.initBoolean(false);
    try std.testing.expect(false_obj == .Boolean and false_obj.Boolean == false);

    const int_obj = PdfObject.initInteger(42);
    try std.testing.expect(int_obj == .Integer and int_obj.Integer == 42);

    const real_obj = PdfObject.initReal(3.14);
    try std.testing.expect(real_obj == .Real and real_obj.Real == 3.14);

    var string_obj = try PdfObject.initString("hello", allocator);
    defer string_obj.deinit(allocator);
    try std.testing.expect(string_obj == .String and std.mem.eql(u8, string_obj.String.encoded_bytes, "(hello)"));

    var name_obj = try PdfObject.initName("Name", allocator);
    defer name_obj.deinit(allocator);
    try std.testing.expect(name_obj == .Name and std.mem.eql(u8, name_obj.Name.to_pdf_string(), "/Name"));

    var array_obj = try PdfObject.initArray(false, allocator);
    defer array_obj.deinit(allocator);
    try std.testing.expect(array_obj == .Array);

    var dict_obj = try PdfObject.initDict(allocator);
    defer dict_obj.deinit(allocator);
    try std.testing.expect(dict_obj == .Dict);
}

test "PdfObject eql" {
    var null1 = PdfObject.initNull();
    var null2 = PdfObject.initNull();
    defer {
        null1.deinit(allocator);
        null2.deinit(allocator);
    }
    try std.testing.expect(try null1.eql(null2, allocator));
}

// test "PdfObject.init_indirect" {
//     const text1 = "null";
//     const obj1 = try PdfObject.init_indirect(allocator, text1, true);
//     defer obj1.deinit(allocator);
//
//     try std.testing.expect(std.mem.eql(u8, obj1.value, "null"));
//     try std.testing.expectEqual(obj1.indirect, true);
//
//     const text2 = "123.45";
//     const obj2 = try PdfObject.init_indirect(allocator, text2, false);
//     defer obj2.deinit(allocator);
//
//     try std.testing.expect(std.mem.eql(u8, obj2.value, "123.45"));
//     try std.testing.expectEqual(obj2.indirect, false);
//
//     const text_empty = "";
//     const obj_empty = try PdfObject.init_indirect(allocator, text_empty, true);
//     defer obj_empty.deinit(allocator);
//
//     try std.testing.expect(std.mem.eql(u8, obj_empty.value, ""));
//     try std.testing.expectEqual(obj_empty.indirect, true);
// }
//
// test "PdfObject.eql" {
//     const obj1 = try PdfObject.init_indirect(allocator, "hello", false);
//     const obj2 = try PdfObject.init_indirect(allocator, "hello", false);
//     const obj3 = try PdfObject.init_indirect(allocator, "hello", true);
//     const obj4 = try PdfObject.init_indirect(allocator, "world", false);
//     const obj5 = try PdfObject.init_indirect(allocator, "world", true);
//
//     defer obj1.deinit(allocator);
//     defer obj2.deinit(allocator);
//     defer obj3.deinit(allocator);
//     defer obj4.deinit(allocator);
//     defer obj5.deinit(allocator);
//
//     try std.testing.expect(obj1.eql(obj2));
//     try std.testing.expect(obj1.eql(obj1));
//     try std.testing.expect(!obj1.eql(obj3));
//     try std.testing.expect(!obj1.eql(obj4));
//     try std.testing.expect(!obj1.eql(obj5));
//
//     const obj_true = try PdfObject.init_indirect(allocator, "test", true);
//     const obj_true_again = try PdfObject.init_indirect(allocator, "test", true);
//
//     defer obj_true.deinit(allocator);
//     defer obj_true_again.deinit(allocator);
//
//     try std.testing.expect(obj_true.eql(obj_true_again));
// }
//
// test "PdfObject.eql_str" {
//     const obj_false = try PdfObject.init_indirect(allocator, "compare_me", false);
//     const obj_true = try PdfObject.init_indirect(allocator, "compare_me", true);
//
//     defer obj_false.deinit(allocator);
//     defer obj_true.deinit(allocator);
//
//     try std.testing.expect(obj_false.eql_str("compare_me"));
//     try std.testing.expect(!obj_false.eql_str("donotmatch"));
//     try std.testing.expect(!obj_true.eql_str("compare_me"));
//     try std.testing.expect(!obj_true.eql_str("donotmatch"));
//
//     const obj_empty_false = try PdfObject.init_indirect(allocator, "", false);
//     defer obj_empty_false.deinit(allocator);
//
//     try std.testing.expect(obj_empty_false.eql_str(""));
//     try std.testing.expect(!obj_empty_false.eql_str("a"));
//
//     const obj_empty_true = try PdfObject.init_indirect(allocator, "", true);
//     defer obj_empty_true.deinit(allocator);
//
//     try std.testing.expect(!obj_empty_true.eql_str(""));
// }
