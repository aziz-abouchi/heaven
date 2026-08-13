const std = @import("std");
const handler = @import("handler.zig");
const platform = @import("platform");
const ts = platform.ts;

pub fn runLsp(allocator: std.mem.Allocator) anyerror!void {
    // platform.debug.print("Heaven LSP starting...\n", .{});

    const parser = ts.ts_parser_new() orelse return;
    defer ts.ts_parser_delete(parser);
    if (!ts.ts_parser_set_language(parser, platform.tree_sitter_heaven())) return;

    var doc_text: ?[]u8 = null;
    defer if (doc_text) |t| allocator.free(t);

    while (true) {
        const content = readMessage(allocator) orelse break;
        defer allocator.free(content);

        const id = extractId(content);
        const method = extractString(content, "method");

        if (method == null) continue;
        const m = method.?;

        const response: ?[]u8 = blk: {
            if (std.mem.eql(u8, m, "initialize")) {
                break :blk handler.handleInitialize(allocator, id) catch null;
            } else if (std.mem.eql(u8, m, "initialized")) {
                break :blk null;
            } else if (std.mem.eql(u8, m, "shutdown")) {
                break :blk handler.handleShutdown(allocator, id) catch null;
            } else if (std.mem.eql(u8, m, "exit")) {
                return;
            } else if (std.mem.eql(u8, m, "textDocument/didOpen") or std.mem.eql(u8, m, "textDocument/didChange")) {
                const uri = extractString(content, "uri") orelse break :blk null;
                const text = extractText(content) orelse break :blk null;

                if (doc_text) |t| allocator.free(t);
                doc_text = allocator.dupe(u8, text) catch break :blk null;
                break :blk handler.runDiagnostics(allocator, parser, uri, doc_text.?) catch null;
            } else if (std.mem.eql(u8, m, "textDocument/hover")) {
                if (doc_text) |text| {
                    const line = extractLine(content);
                    const col = extractChar(content);
                    break :blk handler.handleHoverWithText(allocator, id, parser, text, line, col) catch null;
                }
                break :blk handler.handleHover(allocator, id) catch null;
            } else if (std.mem.eql(u8, m, "textDocument/completion")) {
                break :blk handler.handleCompletion(allocator, id) catch null;
            } else if (std.mem.eql(u8, m, "textDocument/documentSymbol")) {
                if (doc_text) |text| {
                    break :blk handler.handleDocumentSymbols(allocator, id, parser, text) catch null;
                }
                break :blk null;
            } else {
                break :blk null;
            }
        };

        if (response) |resp| {
            defer allocator.free(resp);
            writeMessage(resp);
        }
    }
}

fn readMessage(allocator: std.mem.Allocator) ?[]u8 {
    var content_len: usize = 0;
    var header_buf: [256]u8 = undefined;
    var hi: usize = 0;

    while (true) {
        var byte: [1]u8 = undefined;
        const n = platform.posix.read(0, &byte) catch return null;
        if (n == 0) return null;
        if (byte[0] == '\n') {
            const trimmed = std.mem.trim(u8, header_buf[0..hi], &.{ '\r', '\n', ' ' });
            if (trimmed.len == 0) break;
            if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                content_len = std.fmt.parseInt(usize, trimmed["Content-Length: ".len..], 10) catch 0;
            }
            hi = 0;
        } else {
            if (hi < header_buf.len) {
                header_buf[hi] = byte[0];
                hi += 1;
            }
        }
    }

    if (content_len == 0) return null;

    const buf = allocator.alloc(u8, content_len) catch return null;
    var total: usize = 0;
    while (total < content_len) {
        const n = platform.posix.read(0, buf[total..]) catch {
            allocator.free(buf);
            return null;
        };
        if (n == 0) {
            allocator.free(buf);
            return null;
        }
        total += n;
    }
    return buf;
}

fn writeMessage(content: []const u8) void {
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{content.len}) catch return;
    _ = platform.posix.write(1, header) catch {};
    _ = platform.posix.write(1, content) catch {};
}

fn extractId(json: []const u8) i64 {
    const needle = [_]u8{ '"', 'i', 'd', '"', ':' };
    const pos = std.mem.indexOf(u8, json, &needle) orelse return 0;
    const rest = json[pos + needle.len ..];
    const trimmed = std.mem.trim(u8, rest[0..@min(rest.len, 20)], &.{ ' ', '\t' });
    var end: usize = 0;
    while (end < trimmed.len and ((trimmed[end] >= '0' and trimmed[end] <= '9') or trimmed[end] == '-')) {
        end += 1;
    }
    if (end == 0) return 0;
    return std.fmt.parseInt(i64, trimmed[0..end], 10) catch 0;
}

fn extractString(json: []const u8, field: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    search_buf[0] = '"';
    @memcpy(search_buf[1..][0..field.len], field);
    search_buf[1 + field.len] = '"';
    const search = search_buf[0 .. field.len + 2];

    const key_pos = std.mem.indexOf(u8, json, search) orelse return null;
    const after_key = json[key_pos + search.len ..];

    const colon = std.mem.indexOf(u8, after_key, ":") orelse return null;
    const after_colon = after_key[colon + 1 ..];

    var i: usize = 0;
    while (i < after_colon.len and after_colon[i] != '"') : (i += 1) {}
    if (i >= after_colon.len) return null;
    const rest = after_colon[i + 1 ..];
    var j: usize = 0;
    while (j < rest.len and rest[j] != '"') : (j += 1) {}
    if (j == 0) return null;
    return rest[0..j];
}

fn extractText(json: []const u8) ?[]const u8 {
    const needle = [_]u8{ '"', 't', 'e', 'x', 't', '"', ':', '"' };
    const pos = std.mem.indexOf(u8, json, &needle) orelse return null;
    const rest = json[pos + needle.len ..];

    var end: usize = 0;
    var escaped = false;
    while (end < rest.len) {
        if (escaped) {
            escaped = false;
        } else if (rest[end] == '\\') {
            escaped = true;
        } else if (rest[end] == '"') {
            break;
        }
        end += 1;
    }
    return rest[0..end];
}

fn extractLine(json: []const u8) u32 {
    const needle = [_]u8{ '"', 'l', 'i', 'n', 'e', '"', ':' };
    const pos = std.mem.indexOf(u8, json, &needle) orelse return 0;
    const rest = json[pos + needle.len ..];
    var end: usize = 0;
    while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') : (end += 1) {}
    return std.fmt.parseInt(u32, rest[0..end], 10) catch 0;
}

fn extractChar(json: []const u8) u32 {
    const needle = [_]u8{ '"', 'c', 'h', 'a', 'r', 'a', 'c', 't', 'e', 'r', '"', ':' };
    const pos = std.mem.indexOf(u8, json, &needle) orelse return 0;
    const rest = json[pos + needle.len ..];
    var end: usize = 0;
    while (end < rest.len and rest[end] >= '0' and rest[end] <= '9') : (end += 1) {}
    return std.fmt.parseInt(u32, rest[0..end], 10) catch 0;
}
