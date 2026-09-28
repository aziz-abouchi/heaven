const std = @import("std");

pub const MsgType = enum(u8) {
    hello = 0x01,
    offer = 0x02,
    answer = 0x03,
    candidate = 0x04,
    keep_alive = 0x05,
    _, // Fallback pour types inconnus
};

pub const Header = packed struct {
    magic: u16, // 0x4856
    msg_type: MsgType,
    length: u32,
};

// Fonction utilitaire pour parser un header depuis un stream
pub fn readHeader(reader: anytype) !Header {
    var header: Header = undefined;
    try reader.readNoEof(std.mem.asBytes(&header));
    
    if (header.magic != 0x4856) {
        return error.InvalidMagicNumber;
    }
    return header;
}
