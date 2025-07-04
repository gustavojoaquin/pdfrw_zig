const std = @import("std");
const test_allocator = std.testing.allocator;

const crypt = @import("crypt");
const CryptFilter = crypt.CryptFilter;
const AESCryptFilter = crypt.AESCryptFilter;
const RC4CryptFilter = crypt.RC4CryptFilter;
const IdentityCryptFilter = crypt.IdentityCryptFilter;

const AesBlock = std.crypto.core.aes;
const Aes128 = std.crypto.core.aes.Aes128;
const rc4_mod = @import("rc4");
const RC4 = rc4_mod.RC4;

const objects_mod = @import("object");
const PdfDict = objects_mod.pdfdict.PdfDict;
const PdfName = objects_mod.pdfname.PdfName;
const PdfObject = objects_mod.pdfobject.PdfObject;
const PdfArray = objects_mod.pdfarray.PdfArray;
const PdfIndirect = objects_mod.pdfindirect.PdfIndirect;
const PdfRef = objects_mod.pdfindirect.ObjectReference;
const PdfArrayItem = objects_mod.pdfarray.PdfArrayItem;

/// Creates a PdfName for testing. Uses `test_allocator`.
fn initPdfName(name_str: []const u8) !PdfName {
    return try PdfName.init_from_raw(test_allocator, name_str);
}

/// Creates an Integer PdfObject for testing.
fn initPdfObjectInt(val: i64) PdfObject {
    return PdfObject.initInteger(val);
}

/// Creates a String PdfObject (for bytes data) for testing.
fn initPdfObjectBytes(val: []const u8) !PdfObject {
    return try PdfObject.initString(val, test_allocator);
}

/// Creates an Array PdfObject for testing.
fn initPdfObjectArray() !*PdfArray {
    const array_obj = try PdfObject.initArray(false, test_allocator);
    return array_obj.Array;
}

/// Creates a Boolean PdfObject for testing.
fn initPdfObjectBool(val: bool) PdfObject {
    return PdfObject.initBoolean(val);
}

/// Converts a hex string (e.g., "DEADBEEF") to a byte array.
/// Allocates on `test_allocator`. Returns error.
fn hexToBytes(hex_str: []const u8) error{ OutOfMemory, ParseIntError, InvalidCharacter, Overflow }![]u8 {
    std.debug.assert(hex_str.len % 2 == 0);
    var bytes = try test_allocator.alloc(u8, hex_str.len / 2);
    var i: usize = 0;
    while (i < hex_str.len) : (i += 2) {
        bytes[i / 2] = try std.fmt.parseUnsigned(u8, hex_str[i .. i + 2], 16);
    }
    return bytes;
}

test "streamObjects iterates only stream-containing PdfDicts" {
    var dict1_val = try PdfDict.init(test_allocator);
    defer dict1_val.deinit();
    var dict2_val = try PdfDict.init(test_allocator);
    defer dict2_val.deinit();
    var dict3_val = try PdfDict.init(test_allocator);
    defer dict3_val.deinit();

    try dict1_val.setStream("stream content 1");
    try dict2_val.setStream(null);
    try dict3_val.setStream("stream content 2");

    var pdf_dicts = [_]*PdfDict{ dict1_val, dict2_val, dict3_val };
    var it = crypt.streamObjects(pdf_dicts[0..]);

    var count: usize = 0;
    while (it.next()) |obj_ptr| {
        if (count == 0) {
            try std.testing.expect(obj_ptr == pdf_dicts[0]);
            try std.testing.expectEqualStrings("stream content 1", obj_ptr.stream.?);
        } else if (count == 1) {
            try std.testing.expect(obj_ptr == pdf_dicts[2]);
            try std.testing.expectEqualStrings("stream content 2", obj_ptr.stream.?);
        }
        count += 1;
    }
    try std.testing.expectEqual(2, count);
}

test "createKey with revision < 3" {
    const allocator = test_allocator;

    var encrypt_dict_ptr = try PdfDict.init(allocator);
    defer encrypt_dict_ptr.deinit();

    const O_bytes_content = try hexToBytes("8B2189FB081C443C78B13214C803F2C2");
    defer allocator.free(O_bytes_content);

    var name_o = try initPdfName("O");
    defer name_o.deinit(allocator);

    var obj_o = try initPdfObjectBytes(O_bytes_content);
    defer obj_o.deinit(allocator);

    try encrypt_dict_ptr.put(name_o, obj_o);

    var name_p = try initPdfName("P");
    defer name_p.deinit(allocator);
    const obj_p = initPdfObjectInt(-132);

    try encrypt_dict_ptr.put(name_p, obj_p);

    var name_r = try initPdfName("R");
    defer name_r.deinit(allocator);
    const obj_r = initPdfObjectInt(2);
    try encrypt_dict_ptr.put(name_r, obj_r);

    const name_length = try initPdfName("Length");
    defer name_length.deinit(allocator);
    const obj_length = initPdfObjectInt(128);
    try encrypt_dict_ptr.put(name_length, obj_length);

    var doc_ptr = try PdfDict.init(allocator);
    defer doc_ptr.deinit();

    var id_array_ptr = (try PdfObject.initArray(false, allocator)).Array;
    defer id_array_ptr.deinit();

    const id_bytes_content = try hexToBytes("3F82E2596ED3A20B78B13214C803F2C2");
    defer allocator.free(id_bytes_content);

    var obj_id_bytes = try initPdfObjectBytes(id_bytes_content);
    defer obj_id_bytes.deinit(allocator);
    try id_array_ptr.appendObject(obj_id_bytes);

    const name_id = try initPdfName("ID");
    defer name_id.deinit(allocator);
    try doc_ptr.put(
        name_id,
        PdfObject{ .Array = id_array_ptr },
    );

    var name_encrypt = try initPdfName("Encrypt");
    defer name_encrypt.deinit(allocator);
    try doc_ptr.put(
        name_encrypt,
        PdfObject{ .Dict = encrypt_dict_ptr },
    );

    const password = "test_password_rev_2";
    const key = try crypt.createKey(password, doc_ptr, allocator);
    defer allocator.free(key);

    const expected_key = try hexToBytes("CEC3CE8472DF6D0EA1506C22F54F2CBC");
    defer allocator.free(expected_key);
    // std.debug.print("\nprint expected_key: {s}\nprint key: {s}\nprint key.len: {}\n", .{ expected_key, key, key.len });
    try std.testing.expectEqualSlices(u8, expected_key, key);
    try std.testing.expectEqual(16, key.len);
}

test "createKey with revision >= 3 and longer password" {
    const allocator = test_allocator;

    var encrypt_dict_ptr = try PdfDict.init(allocator);
    defer encrypt_dict_ptr.deinit();

    const O_bytes = try hexToBytes("8B2189FB081C443C78B13214C803F2C2");
    defer allocator.free(O_bytes);
    var name_o = try initPdfName("O");
    defer name_o.deinit(allocator);
    var name_p = try initPdfName("P");
    defer name_p.deinit(allocator);
    var name_r = try initPdfName("R");
    defer name_r.deinit(allocator);
    var name_length = try initPdfName("Length");
    defer name_length.deinit(allocator);

    var pdf_object_byte = try initPdfObjectBytes(O_bytes);
    defer pdf_object_byte.deinit(allocator);
    try encrypt_dict_ptr.put(name_o, pdf_object_byte);
    try encrypt_dict_ptr.put(name_p, initPdfObjectInt(-1028));
    try encrypt_dict_ptr.put(name_r, initPdfObjectInt(3));
    try encrypt_dict_ptr.put(name_length, initPdfObjectInt(128));

    var doc_ptr = try PdfDict.init(allocator);
    defer doc_ptr.deinit();

    var id_array_ptr = try PdfObject.initArray(false, test_allocator);
    defer id_array_ptr.deinit(allocator);

    const id_bytes = try hexToBytes("3F82E2596ED3A20B78B13214C803F2C2");
    defer allocator.free(id_bytes);

    var pdf_object_id_bytes = try initPdfObjectBytes(id_bytes);
    defer pdf_object_id_bytes.deinit(allocator);

    try id_array_ptr.asArray().?.appendObject(pdf_object_id_bytes);
    const name_id = try initPdfName("ID");
    defer name_id.deinit(allocator);
    try doc_ptr.put(name_id, PdfObject{ .Array = id_array_ptr.asArray().? });

    const name_encrypt = try initPdfName("Encrypt");
    defer name_encrypt.deinit(allocator);
    try doc_ptr.put(name_encrypt, PdfObject{ .Dict = encrypt_dict_ptr });

    const password = "a_very_long_password_that_is_more_than_32_bytes_long_abcdefghijkl";
    const key = try crypt.createKey(password, doc_ptr, allocator);
    defer allocator.free(key);

    const expected_key = try hexToBytes("BD7725176F91B95AFDA5BD618D646331");
    defer allocator.free(expected_key);
    try std.testing.expectEqualSlices(u8, expected_key, key);
    try std.testing.expectEqual(16, key.len);
}
//
// test "createKey handles missing Encrypt dictionary" {
//     const allocator = test_allocator;
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//
//     const password = "test";
//     const err = crypt.createKey(password, doc_ptr, allocator) catch |e| {
//         try std.testing.expectEqual(e, crypt.CryptError.MissingEncryptDict);
//         return;
//     };
//     _ = err;
//     @panic("Expected error, but got success");
// }
//
// test "createKey handles invalid ID array" {
//     const allocator = test_allocator;
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(2));
//     try encrypt_dict_ptr.put(try initPdfName("Length"), initPdfObjectInt(128));
//     const O_bytes = try hexToBytes("8B2189FB081C443C78B13214C803F2C2");
//     defer allocator.free(O_bytes);
//     try encrypt_dict_ptr.put(try initPdfName("O"), try initPdfObjectBytes(O_bytes));
//     try encrypt_dict_ptr.put(try initPdfName("P"), initPdfObjectInt(-132));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//
//     const id_array_ptr = try initPdfObjectArray();
//     defer id_array_ptr.deinit();
//     // try id_array_ptr.appendObject(try initPdfObjectBytes(id_bytes));
//     try doc_ptr.put(try initPdfName("ID"), PdfObject{ .Array = id_array_ptr });
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const password = "test";
//     const err = crypt.createKey(password, doc_ptr, allocator) catch |e| {
//         try std.testing.expectEqual(e, crypt.CryptError.InvalidID);
//         return;
//     };
//     _ = err;
//     @panic("Expected error, but got success");
// }
//
// test "createUserHash with revision < 3" {
//     const allocator = test_allocator;
//     const key = try hexToBytes("2360E45E2A89F95F4D3C08D644485558");
//     defer allocator.free(key);
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(2));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const user_hash = try crypt.createUserHash(key, doc_ptr, allocator);
//     defer allocator.free(user_hash);
//
//     const expected_user_hash = try hexToBytes("7A1A47EF3C1052E74B0818274762952E84A74F2A1095B5B537B9210F5D54F91F");
//     defer allocator.free(expected_user_hash);
//     try std.testing.expectEqualSlices(u8, expected_user_hash, user_hash);
// }
//
// test "createUserHash with revision >= 3" {
//     const allocator = test_allocator;
//     const key = try hexToBytes("2E943003F64560D1E16892520630D723");
//     defer allocator.free(key);
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(3));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//
//     const id_array_ptr = try initPdfObjectArray();
//     defer id_array_ptr.deinit();
//     const id_bytes = try hexToBytes("3F82E2596ED3A20B78B13214C803F2C2");
//     defer allocator.free(id_bytes);
//     try id_array_ptr.appendObject(try initPdfObjectBytes(id_bytes));
//     try doc_ptr.put(try initPdfName("ID"), PdfObject{ .Array = id_array_ptr });
//
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const user_hash = try crypt.createUserHash(key, doc_ptr, allocator);
//     defer allocator.free(user_hash);
//
//     const expected_user_hash = try hexToBytes("49D2C67AE47D9379659CCCDA9C4C5355");
//     defer allocator.free(expected_user_hash);
//     try std.testing.expectEqualSlices(u8, expected_user_hash, user_hash);
// }
//
// test "checkUserPassword correct password revision < 3" {
//     const allocator = test_allocator;
//     const key = try hexToBytes("2360E45E2A89F95F4D3C08D644485558");
//     defer allocator.free(key);
//     const expected_user_hash_rev2 = try hexToBytes("7A1A47EF3C1052E74B0818274762952E84A74F2A1095B5B537B9210F5D54F91F");
//     defer allocator.free(expected_user_hash_rev2);
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(2));
//     try encrypt_dict_ptr.put(try initPdfName("U"), try initPdfObjectBytes(expected_user_hash_rev2));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const is_correct = try crypt.checkUserPassword(key, doc_ptr, allocator);
//     try std.testing.expect(is_correct);
// }
//
// test "checkUserPassword incorrect password revision < 3" {
//     const allocator = test_allocator;
//     const key = try hexToBytes("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
//     defer allocator.free(key);
//     const expected_user_hash_rev2 = try hexToBytes("7A1A47EF3C1052E74B0818274762952E84A474F2A1095B5B537B9210F5D54F91F");
//     defer allocator.free(expected_user_hash_rev2);
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(2));
//     try encrypt_dict_ptr.put(try initPdfName("U"), try initPdfObjectBytes(expected_user_hash_rev2));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const is_correct = try crypt.checkUserPassword(key, doc_ptr, allocator);
//     try std.testing.expect(!is_correct);
// }
//
// test "checkUserPassword correct password revision >= 3" {
//     const allocator = test_allocator;
//     const key = try hexToBytes("2E943003F64560D1E16892520630D723");
//     defer allocator.free(key);
//     const expected_user_hash_rev3 = try hexToBytes("49D2C67AE47D9379659CCCDA9C4C5355");
//     defer allocator.free(expected_user_hash_rev3);
//
//     var encrypt_dict_ptr = try initPdfObjectDict();
//     defer {
//         encrypt_dict_ptr.deinit();
//         allocator.destroy(encrypt_dict_ptr);
//     }
//     try encrypt_dict_ptr.put(try initPdfName("R"), initPdfObjectInt(3));
//     try encrypt_dict_ptr.put(try initPdfName("U"), try initPdfObjectBytes(expected_user_hash_rev3));
//
//     var doc_ptr = try initPdfObjectDict();
//     defer {
//         doc_ptr.deinit();
//         allocator.destroy(doc_ptr);
//     }
//     const id_array_ptr = try initPdfObjectArray();
//     defer id_array_ptr.deinit();
//     const id_bytes = try hexToBytes("3F82E2596ED3A20B78B13214C803F2C2");
//     defer allocator.free(id_bytes);
//     try id_array_ptr.appendObject(try initPdfObjectBytes(id_bytes));
//     try doc_ptr.put(try initPdfName("ID"), PdfObject{ .Array = id_array_ptr });
//
//     try doc_ptr.put(try initPdfName("Encrypt"), PdfObject{ .Dict = encrypt_dict_ptr });
//
//     const is_correct = try crypt.checkUserPassword(key, doc_ptr, allocator);
//     try std.testing.expect(is_correct);
// }
//
// test "AESCryptFilter decrypts data correctly" {
//     const allocator = test_allocator;
//     const filter_key = try hexToBytes("A0A1A2A3A4A5A6A7A8A9AAABACADAEAF");
//     defer allocator.free(filter_key);
//
//     const plaintext = "This is a secret stream data.";
//     const iv = try hexToBytes("101112131415161718191A1B1C1D1E1F");
//     defer allocator.free(iv);
//
//     const test_num: u32 = 1;
//     const test_gen: u16 = 0;
//
//     var key_ext_buf: [5]u8 = undefined;
//     std.mem.writeInt(u24, key_ext_buf[0..3], @intCast(test_num), .little);
//     std.mem.writeInt(u16, key_ext_buf[3..5], test_gen, .little);
//
//     var md5 = std.crypto.hash.Md5.init(.{});
//     md5.update(filter_key);
//     md5.update(&key_ext_buf);
//     var derived_aes_key: [16]u8 = undefined;
//     md5.final(&derived_aes_key);
//
//     const block_size = 16;
//     const pad_len = block_size - (plaintext.len % block_size);
//     var padded_plaintext_arr = std.ArrayList(u8).init(allocator);
//     defer padded_plaintext_arr.deinit();
//     try padded_plaintext_arr.appendSlice(plaintext);
//     for (0..pad_len) |_| try padded_plaintext_arr.append(@as(u8, @intCast(pad_len)));
//     const padded_plaintext = padded_plaintext_arr.items;
//
//     const simulated_ciphertext = try allocator.alloc(u8, padded_plaintext.len);
//     defer allocator.free(simulated_ciphertext);
//
//     const key_array: [16]u8 = derived_aes_key;
//     var iv_array: [16]u8 = undefined;
//     if (iv.len < 16) @panic("Slice too short");
//     @memcpy(iv_array[0..], iv[0..16]);
//     crypt.encryptCbcAes128(
//         padded_plaintext,
//         simulated_ciphertext,
//         key_array,
//         iv_array,
//     );
//
//     var data_input_for_filter = std.ArrayList(u8).init(allocator);
//     defer data_input_for_filter.deinit();
//     try data_input_for_filter.appendSlice(iv);
//     try data_input_for_filter.appendSlice(simulated_ciphertext);
//     const data_to_decrypt = data_input_for_filter.items;
//
//     const aes_filter = AESCryptFilter{ .key = filter_key };
//     const decrypted = try aes_filter.decryptData(test_num, test_gen, data_to_decrypt, allocator);
//     defer allocator.free(decrypted);
//
//     try std.testing.expectEqualStrings(plaintext, decrypted);
// }
//
// test "AESCryptFilter handles invalid padding" {
//     const allocator = test_allocator;
//     const filter_key = try hexToBytes("A0A1A2A3A4A5A6A7A8A9AAABACADAEAF");
//     defer allocator.free(filter_key);
//     const iv = try hexToBytes("101112131415161718191A1B1C1D1E1F");
//     defer allocator.free(iv);
//
//     var malformed_data_input = std.ArrayList(u8).init(allocator);
//     defer malformed_data_input.deinit();
//     try malformed_data_input.appendSlice(iv);
//     var temp_cipher_text = try allocator.alloc(u8, 16);
//     defer allocator.free(temp_cipher_text);
//     @memset(temp_cipher_text, 0xAA);
//     temp_cipher_text[15] = 20;
//     try malformed_data_input.appendSlice(temp_cipher_text);
//
//     const aes_filter = AESCryptFilter{ .key = filter_key };
//     const err = aes_filter.decryptData(1, 0, malformed_data_input.items, allocator) catch |e| {
//         try std.testing.expectEqual(e, crypt.CryptError.InvalidPadding);
//         return;
//     };
//     _ = err;
//
//     @panic("Expected error, but got success");
// }
//
// test "RC4CryptFilter decrypts data correctly" {
//     const allocator = test_allocator;
//     const filter_key = try hexToBytes("FEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFE");
//     defer allocator.free(filter_key);
//     const plaintext = "Hello, RC4 encrypted world!";
//
//     const test_num: u32 = 123;
//     const test_gen: u16 = 45;
//
//     var key_ext_buf: [5]u8 = undefined;
//     std.mem.writeInt(u24, key_ext_buf[0..3], @intCast(test_num), .little);
//     std.mem.writeInt(u16, key_ext_buf[3..5], test_gen, .little);
//
//     var md5 = std.crypto.hash.Md5.init(.{});
//     md5.update(filter_key);
//     md5.update(&key_ext_buf);
//     var derived_rc4_key_hash: [16]u8 = undefined;
//     md5.final(&derived_rc4_key_hash);
//
//     const new_key_size = @min(filter_key.len + 5, 16);
//     var rc4_encryptor = RC4.init(derived_rc4_key_hash[0..new_key_size]);
//     const simulated_ciphertext = try allocator.alloc(u8, plaintext.len);
//     defer allocator.free(simulated_ciphertext);
//     rc4_encryptor.process(simulated_ciphertext, plaintext);
//
//     const rc4_filter = RC4CryptFilter{ .key = filter_key };
//     const decrypted = try rc4_filter.decryptData(test_num, test_gen, simulated_ciphertext, allocator);
//     defer allocator.free(decrypted);
//
//     try std.testing.expectEqualStrings(plaintext, decrypted);
// }
//
// test "IdentityCryptFilter returns data unchanged" {
//     const allocator = test_allocator;
//     const data = "This is unencrypted data.";
//     const identity_filter = IdentityCryptFilter{};
//     const decrypted_data = try identity_filter.decryptData(1, 0, data, allocator);
//     defer allocator.free(decrypted_data);
//     try std.testing.expectEqualStrings(data, decrypted_data);
// }
//
// test "decryptObjects processes stream objects with default filter" {
//     const allocator = test_allocator;
//
//     var dict1_val = PdfDict.init(allocator);
//     defer dict1_val.deinit();
//     dict1_val.indirect_num = 1;
//     dict1_val.indirect_gen = 0;
//     try dict1_val.setStream("Default Filter Encrypted Data");
//
//     var dict2_val = PdfDict.init(allocator);
//     defer dict2_val.deinit();
//     dict2_val.indirect_num = 2;
//     dict2_val.indirect_gen = 0;
//     try dict2_val.setStream(null);
//
//     var dict3_val = PdfDict.init(allocator);
//     defer dict3_val.deinit();
//     dict3_val.indirect_num = 3;
//     dict3_val.indirect_gen = 0;
//     try dict3_val.setStream("Already Decrypted Data");
//     try dict3_val.setPrivate("decrypted", initPdfObjectBool(true));
//
//     const default_filter_instance = IdentityCryptFilter{};
//     const default_filter_union = CryptFilter{ .Identity = default_filter_instance };
//     var filters_map = std.StringHashMap(CryptFilter).init(allocator);
//     defer filters_map.deinit();
//
//     var pdf_dicts_list = [_]PdfDict{ dict1_val, dict2_val, dict3_val };
//     try crypt.decryptObjects(pdf_dicts_list[0..], default_filter_union, filters_map, allocator);
//
//     // Verify dict1 was decrypted by default filter
//     try std.testing.expect(pdf_dicts_list[0].stream != null);
//     try std.testing.expectEqualStrings("Default Filter Encrypted Data", pdf_dicts_list[0].stream.?);
//     try std.testing.expect(pdf_dicts_list[0].getPrivate("decrypted").?.Boolean);
//
//     // Verify dict2 was skipped
//     try std.testing.expect(pdf_dicts_list[1].stream == null);
//     try std.testing.expect(pdf_dicts_list[1].getPrivate("decrypted") == null);
//
//     // Verify dict3 was skipped
//     try std.testing.expect(pdf_dicts_list[2].stream != null);
//     try std.testing.expectEqualStrings("Already Decrypted Data", pdf_dicts_list[2].stream.?);
//     try std.testing.expect(pdf_dicts_list[2].getPrivate("decrypted").?.Boolean);
// }
//
// test "decryptObjects overrides default filter with named Crypt filter" {
//     const allocator = test_allocator;
//
//     var dict_with_custom_filter_val_ptr = PdfDict.init(allocator);
//     defer dict_with_custom_filter_val_ptr.deinit();
//     dict_with_custom_filter_val_ptr.indirect_num = 10;
//     dict_with_custom_filter_val_ptr.indirect_gen = 0;
//
//     const aes_filter_key = try hexToBytes("A0A1A2A3A4A5A6A7A8A9AAABACADAEAF");
//     defer allocator.free(aes_filter_key);
//     const plaintext = "AES encrypted stream content";
//     const iv = try hexToBytes("101112131415161718191A1B1C1D1E1F");
//     defer allocator.free(iv);
//
//     var aes_test_key_ext_buf: [5]u8 = undefined;
//     std.mem.writeInt(u24, aes_test_key_ext_buf[0..3], @intCast(dict_with_custom_filter_val_ptr.indirect_num.?), .little);
//     std.mem.writeInt(u16, aes_test_key_ext_buf[3..5], dict_with_custom_filter_val_ptr.indirect_gen.?, .little);
//
//     var md5_aes = std.crypto.hash.Md5.init(.{});
//     md5_aes.update(aes_filter_key);
//     md5_aes.update(&aes_test_key_ext_buf);
//     var derived_aes_key_for_stream: [16]u8 = undefined;
//     md5_aes.final(&derived_aes_key_for_stream);
//
//     const block_size = 16;
//     const pad_len = block_size - (plaintext.len % block_size);
//     var padded_plaintext_arr = std.ArrayList(u8).init(allocator);
//     defer padded_plaintext_arr.deinit();
//     try padded_plaintext_arr.appendSlice(plaintext);
//     for (0..pad_len) |_| try padded_plaintext_arr.append(@as(u8, @intCast(pad_len)));
//     const padded_plaintext = padded_plaintext_arr.items;
//
//     const simulated_ciphertext_aes = try allocator.alloc(u8, padded_plaintext.len);
//     defer allocator.free(simulated_ciphertext_aes);
//     const key_array: [16]u8 = derived_aes_key_for_stream;
//     if (iv.len < 16) @panic("Slice too short");
//     var iv_array: [16]u8 = undefined;
//     @memcpy(iv_array[0..], iv[0..16]);
//     crypt.encryptCbcAes128(
//         padded_plaintext,
//         simulated_ciphertext_aes,
//         key_array,
//         iv_array,
//     );
//
//     var data_input_aes = std.ArrayList(u8).init(allocator);
//     defer data_input_aes.deinit();
//     try data_input_aes.appendSlice(iv);
//     try data_input_aes.appendSlice(simulated_ciphertext_aes);
//     try dict_with_custom_filter_val_ptr.setStream(data_input_aes.items);
//
//     const filter_array_ptr = try initPdfObjectArray();
//     defer filter_array_ptr.deinit();
//     try filter_array_ptr.appendObject(PdfObject{ .Name = try initPdfName("Crypt") });
//
//     var decode_parms_dict_ptr = try initPdfObjectDict();
//     defer {
//         decode_parms_dict_ptr.deinit();
//         allocator.destroy(decode_parms_dict_ptr);
//     }
//     try decode_parms_dict_ptr.put(try initPdfName("Name"), PdfObject{ .Name = try initPdfName("MyAESFilter") });
//     try dict_with_custom_filter_val_ptr.put(try initPdfName("DecodeParms"), PdfObject{ .Dict = decode_parms_dict_ptr });
//     try dict_with_custom_filter_val_ptr.put(try initPdfName("Filter"), PdfObject{ .Array = filter_array_ptr });
//
//     const default_filter_instance = IdentityCryptFilter{};
//     const default_filter_union = CryptFilter{ .Identity = default_filter_instance };
//
//     // Create custom AES filter and add to filters map
//     const custom_aes_filter_instance = AESCryptFilter{ .key = aes_filter_key };
//     var filters_map = std.StringHashMap(CryptFilter).init(allocator);
//     defer filters_map.deinit();
//     try filters_map.put("MyAESFilter", CryptFilter{ .AES = custom_aes_filter_instance });
//
//     var pdf_dicts_list = [_]PdfDict{dict_with_custom_filter_val_ptr};
//     try crypt.decryptObjects(pdf_dicts_list[0..], default_filter_union, filters_map, allocator);
//
//     try std.testing.expect(pdf_dicts_list[0].stream != null);
//     try std.testing.expectEqualStrings(plaintext, pdf_dicts_list[0].stream.?);
//     try std.testing.expect(pdf_dicts_list[0].getPrivate("decrypted").?.Boolean);
// }
//
// test "decryptObjects handles missing named filter in map" {
//     const allocator = test_allocator;
//
//     var dict_with_custom_filter_val_ptr = PdfDict.init(allocator);
//     defer dict_with_custom_filter_val_ptr.deinit();
//     dict_with_custom_filter_val_ptr.indirect_num = 10;
//     dict_with_custom_filter_val_ptr.indirect_gen = 0;
//     try dict_with_custom_filter_val_ptr.setStream("dummy data");
//
//     const filter_array_ptr = try initPdfObjectArray();
//     defer filter_array_ptr.deinit();
//     try filter_array_ptr.appendObject(PdfObject{ .Name = try initPdfName("Crypt") });
//
//     var decode_parms_dict_ptr = try initPdfObjectDict();
//     defer {
//         decode_parms_dict_ptr.deinit();
//         allocator.destroy(decode_parms_dict_ptr);
//     }
//     try decode_parms_dict_ptr.put(try initPdfName("Name"), PdfObject{ .Name = try initPdfName("NonExistentFilter") });
//     try dict_with_custom_filter_val_ptr.put(try initPdfName("DecodeParms"), PdfObject{ .Dict = decode_parms_dict_ptr });
//     try dict_with_custom_filter_val_ptr.put(try initPdfName("Filter"), PdfObject{ .Array = filter_array_ptr });
//
//     const default_filter_instance = IdentityCryptFilter{};
//     const default_filter_union = CryptFilter{ .Identity = default_filter_instance };
//     var filters_map = std.StringHashMap(CryptFilter).init(allocator);
//     defer filters_map.deinit();
//
//     var pdf_dicts_list = [_]PdfDict{dict_with_custom_filter_val_ptr}; // Convert pointer to value
//     const err = crypt.decryptObjects(pdf_dicts_list[0..], default_filter_union, filters_map, allocator) catch |e| {
//         try std.testing.expectEqual(e, crypt.CryptError.UnsupportedFilter);
//         return;
//     };
//     _ = err;
//
//     @panic("Expected error, but got success");
// }
