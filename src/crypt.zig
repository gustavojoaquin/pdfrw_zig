//! PDF stream encryption and decryption routines.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Md5 = std.crypto.hash.Md5;
const Aes128 = std.crypto.core.aes.Aes128;
const cbc = std.crypto.modes.cbc;
const rc4_mod = @import("rc4");
const Rc4 = rc4_mod.RC4;

const objects_mod = @import("objects/mod.zig");
const PdfName = objects_mod.pdfname.PdfName;
const PdfDict = objects_mod.pdfdict.PdfDict;
const PdfObject = objects_mod.pdfobject.PdfObject;

/// Password padding string from the PDF 1.7 Specification, Algorithm 3.2.
const PASSWORD_PAD = "(\xbfN^Nu\x8aAd\x00NV\xff\xfa\x01\x08..\x00\xb6\xd0h>\x80/\x0c\xa9\xfedSiz";

/// Errors that can occur during PDF decryption operations.
pub const CryptError = error{
    MissingEncryptDict,
    EncryptEntryNotADict,
    MissingRequiredDictKey,
    DictKeyHasWrongType,
    InvalidID,
    InvalidPadding,
    AESDecryptionFailed,
    UnsupportedFilter,
};

/// Iterator for objects that have a stream to be processed.
pub const StreamIterator = struct {
    list: []PdfDict,
    index: usize = 0,

    pub fn next(it: *StreamIterator) ?*PdfDict {
        while (it.index < it.list.len) {
            const i = it.index;
            it.index += 1;
            const obj = &it.list[i];
            if (obj.stream != null) {
                return obj;
            }
        }
        return null;
    }
};

pub fn streamObjects(list: []PdfDict) StreamIterator {
    return .{ .list = list };
}

/// Creates an encryption key based on the user password.
/// Implements Algorithm 3.2 from the PDF 1.7 Specification.
pub fn createKey(password: []const u8, doc: *PdfDict, allocator: Allocator) ![]u8 {
    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    const encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    const encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const length_name = try PdfName.init_from_raw(allocator, "Length");
    defer length_name.deinit(allocator);
    const length_obj = try encrypt.get(&length_name);
    const key_size_bits = if (length_obj) |obj| obj.asInt() orelse 40 else 40;
    // const key_size: usize = @intCast(std.math.divTrunc(i64, key_size_bits, 8));
    const key_size: usize = @intCast(@divTrunc(key_size_bits, 8));

    const padded_pass = blk: {
        if (password.len >= 32) {
            break :blk password[0..32];
        }
        var buf: [32]u8 = undefined;
        @memcpy(buf[0..password.len], password);
        @memcpy(buf[password.len..], PASSWORD_PAD[password.len..32]);
        break :blk &buf;
    };

    var md5 = Md5.init(.{});
    md5.update(padded_pass);

    const o_name = try PdfName.init_from_raw(allocator, "O");
    defer o_name.deinit(allocator);
    const o_val = (try encrypt.get(&o_name)) orelse return CryptError.MissingRequiredDictKey;
    md5.update(o_val.asBytes() orelse return CryptError.DictKeyHasWrongType);

    const p_name = try PdfName.init_from_raw(allocator, "P");
    defer p_name.deinit(allocator);
    const p_obj = try encrypt.get(&p_name);
    const p_val: i32 = if (p_obj) |obj| @intCast(obj.asInt() orelse 0) else 0;
    var p_buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &p_buf, p_val, .little);
    md5.update(&p_buf);

    const id_name = try PdfName.init_from_raw(allocator, "ID");
    defer id_name.deinit(allocator);
    const id_obj = (try doc.get(&id_name)) orelse return CryptError.InvalidID;
    const id_array = id_obj.asArray() orelse return CryptError.DictKeyHasWrongType;
    if (id_array.len() == 0) return CryptError.InvalidID;
    const first_id_obj = try id_array.get(0);
    const first_id_bytes = first_id_obj.asBytes() orelse return CryptError.DictKeyHasWrongType;
    md5.update(first_id_bytes);

    var temp_hash: [16]u8 = undefined;
    md5.final(&temp_hash);

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    const r_obj = try encrypt.get(&r_name);
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    if (revision >= 3) {
        var round_hash = temp_hash;
        for (0..50) |_| {
            var round_md5 = Md5.init(.{});
            round_md5.update(round_hash[0..key_size]);
            round_md5.final(&round_hash);
        }
        return allocator.dupe(u8, round_hash[0..key_size]);
    }

    return allocator.dupe(u8, temp_hash[0..key_size]);
}

pub fn createUserHash(key: []const u8, doc: *PdfDict, allocator: Allocator) ![]u8 {
    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    const encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    const encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    const r_obj = try encrypt.get(&r_name);
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    if (revision < 3) {
        var rc4 = Rc4.init(key);
        const result = try allocator.alloc(u8, PASSWORD_PAD.len);
        rc4.process(result, PASSWORD_PAD);
        return result;
    } else {
        var md5 = Md5.init(.{});
        md5.update(PASSWORD_PAD);

        const id_name = try PdfName.init_from_raw(allocator, "ID");
        defer id_name.deinit(allocator);
        const id_obj = (try doc.get(&id_name)) orelse return CryptError.InvalidID;
        const id_array = id_obj.asArray() orelse return CryptError.DictKeyHasWrongType;
        if (id_array.len() == 0) return CryptError.InvalidID;
        const first_id_obj = try id_array.get(0);
        const first_id_bytes = first_id_obj.asBytes() orelse return CryptError.DictKeyHasWrongType;
        md5.update(first_id_bytes);

        var temp_hash: [16]u8 = undefined;
        md5.final(&temp_hash);

        std.debug.assert(key.len <= 16);
        var temp_key_buf: [16]u8 = undefined;
        const temp_key_slice = temp_key_buf[0..key.len];

        for (0..20) |i| {
            for (key, 0..) |byte, j| {
                temp_key_slice[j] = byte ^ @as(u8, @intCast(i));
            }
            var rc4 = Rc4.init(temp_key_slice);
            rc4.process(&temp_hash, &temp_hash);
        }
        return try allocator.dupe(u8, &temp_hash);
    }
}

/// Check if the user password is correct. Implements Algorithm 3.6 from the PDF Spec.
pub fn checkUserPassword(key: []const u8, doc: *PdfDict, allocator: Allocator) !bool {
    const user_hash = try createUserHash(key, doc, allocator);
    defer allocator.free(user_hash);

    const encrypt_name = try PdfName.init_from_raw(allocator, "Encrypt");
    defer encrypt_name.deinit(allocator);
    const encrypt_obj = (try doc.get(&encrypt_name)) orelse return CryptError.MissingEncryptDict;
    const encrypt = encrypt_obj.asDict() orelse return CryptError.EncryptEntryNotADict;

    const u_name = try PdfName.init_from_raw(allocator, "U");
    defer u_name.deinit(allocator);
    const stored_hash_obj = (try encrypt.get(&u_name)) orelse return CryptError.MissingRequiredDictKey;
    const stored_hash = stored_hash_obj.asBytes() orelse return CryptError.DictKeyHasWrongType;

    const r_name = try PdfName.init_from_raw(allocator, "R");
    defer r_name.deinit(allocator);
    const r_obj = try encrypt.get(&r_name);
    const revision = if (r_obj) |obj| obj.asInt() orelse 0 else 0;

    return if (revision < 3)
        std.mem.eql(u8, stored_hash, user_hash)
    else
        std.mem.eql(u8, stored_hash[0..16], user_hash[0..16]);
}

/// Crypt filter for AESV2/AESV3 security handlers.
pub const AESCryptFilter = struct {
    key: []const u8,

    pub fn decryptData(self: @This(), num: u24, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        var key_ext_buf: [5]u8 = undefined;
        std.mem.writeInt(u24, key_ext_buf[0..3], num, .little);
        std.mem.writeInt(u16, key_ext_buf[3..5], gen, .little);

        var md5 = Md5.init(.{});
        md5.update(self.key);
        md5.update(&key_ext_buf);
        if (self.key.len == 32) {
            md5.update("sAlT");
        }
        var hash: [16]u8 = undefined;
        md5.final(&hash);

        const iv = data[0..16];
        const ciphertext = data[16..];
        const decrypted_padded = try allocator.alloc(u8, ciphertext.len);
        errdefer allocator.free(decrypted_padded);

        cbc.decrypt_cbc(
            Aes128,
            hash[0 .. Aes128.key_bits / 8],
            iv,
            ciphertext,
            decrypted_padded,
        ) catch |e| {
            std.log.err("AES decryption failed: {any}", .{e});
            return CryptError.AESDecryptionFailed;
        };

        const pad_size = decrypted_padded[decrypted_padded.len - 1];
        if (pad_size == 0 or pad_size > 16 or decrypted_padded.len < pad_size) {
            return CryptError.InvalidPadding;
        }
        const final_len = decrypted_padded.len - pad_size;

        for (decrypted_padded[final_len..]) |byte| {
            if (byte != pad_size) return CryptError.InvalidPadding;
        }

        return allocator.realloc(decrypted_padded, final_len);
    }
};

/// Crypt filter for V1/V2 security handlers (RC4).
pub const RC4CryptFilter = struct {
    key: []const u8,

    pub fn decryptData(self: @This(), num: u24, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        var key_ext_buf: [5]u8 = undefined;
        std.mem.writeInt(u24, key_ext_buf[0..3], num, .little);
        std.mem.writeInt(u16, key_ext_buf[3..5], gen, .little);

        var md5 = Md5.init(.{});
        md5.update(self.key);
        md5.update(&key_ext_buf);

        var hash: [16]u8 = undefined;
        md5.final(&hash);

        const new_key_size = @min(self.key.len + 5, 16);
        var rc4 = Rc4.init(hash[0..new_key_size]);
        const result = try allocator.alloc(u8, data.len);
        rc4.process(result, data);
        return result;
    }
};

/// Identity crypt filter (no encryption).
pub const IdentityCryptFilter = struct {
    pub fn decryptData(_: @This(), _: u32, _: u16, data: []const u8, allocator: Allocator) ![]u8 {
        return allocator.dupe(u8, data);
    }
};

/// A polymorphic crypt filter that can be one of several concrete implementations.
pub const CryptFilter = union(enum) {
    AES: AESCryptFilter,
    RC4: RC4CryptFilter,
    Identity: IdentityCryptFilter,

    /// Dispatches the decryptData call to the active filter implementation.
    pub fn decryptData(self: @This(), num: u32, gen: u16, data: []const u8, allocator: Allocator) ![]u8 {
        return switch (self) {
            .AES => |filter_instance| filter_instance.decryptData(@as(u24, num), gen, data, allocator),
            .RC4 => |filter_instance| filter_instance.decryptData(@as(u24, num), gen, data, allocator),
            .Identity => |filter_instance| filter_instance.decryptData(num, gen, data, allocator),
        };
    }
};

/// Decrypts a list of stream objects in place.
pub fn decryptObjects(
    objects: []PdfDict,
    default_filter: CryptFilter,
    filters: std.StringHashMap(CryptFilter),
    allocator: Allocator,
) !void {
    var name_buffer: [64]u8 = undefined;
    var tmp_allocator = std.heap.FixedBufferAllocator.init(&name_buffer);

    var it = streamObjects(objects);
    while (it.next()) |obj| {
        if (obj.getPrivate("decrypted") != null) continue;

        var current_filter = default_filter;

        const filter_name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Filter");
        defer filter_name_key.deinit(tmp_allocator.allocator());
        if (try obj.get(&filter_name_key)) |filter_obj| {
            var filter_list_items: []PdfObject = undefined;
            if (filter_obj.asArray()) |arr| {
                filter_list_items = arr.items.items;
            } else {
                filter_list_items = &.{filter_obj.*};
            }

            const crypt_name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Crypt");
            defer crypt_name_key.deinit(tmp_allocator.allocator());
            if (filter_list_items.len > 0 and filter_list_items[0].isName() and
                (filter_list_items[0].asName().?.eql(crypt_name_key)))
            {
                const parms_key_dp = try PdfName.init_from_raw(tmp_allocator.allocator(), "DP");
                defer parms_key_dp.deinit(tmp_allocator.allocator());
                const parms_key_decode = try PdfName.init_from_raw(tmp_allocator.allocator(), "DecodeParms");
                defer parms_key_decode.deinit(tmp_allocator.allocator());

                if ((try obj.get(&parms_key_decode)) orelse (try obj.get(&parms_key_dp))) |params_obj| {
                    const params = params_obj.asDict() orelse return CryptError.DictKeyHasWrongType;

                    const name_key = try PdfName.init_from_raw(tmp_allocator.allocator(), "Name");
                    defer name_key.deinit(tmp_allocator.allocator());
                    if (try params.get(&name_key)) |name_obj| {
                        const name = name_obj.asName() orelse return CryptError.DictKeyHasWrongType;
                        const filter_name_slice = name.value[1..];

                        if (filters.get(filter_name_slice)) |new_filter_ptr| {
                            current_filter = new_filter_ptr.*;
                        } else {
                            return CryptError.UnsupportedFilter;
                        }
                    } else {
                        return CryptError.MissingRequiredDictKey;
                    }
                } else {
                    return CryptError.MissingRequiredDictKey;
                }
            }
        }

        const obj_num: u32 = obj.indirect_num orelse 0;
        const obj_gen: u16 = obj.indirect_gen orelse 0;

        const stream_to_decrypt = obj.stream orelse continue;
        const decrypted_data = try current_filter.decryptData(obj_num, obj_gen, stream_to_decrypt, allocator);

        try obj.setStream(decrypted_data);
        allocator.free(decrypted_data);

        const decrypted_flag = PdfObject{ .Boolean = true };
        try obj.setPrivate("decrypted", decrypted_flag);
    }
}
