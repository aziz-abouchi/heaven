const std = @import("std");
const atomic = std.atomic;
const matrix_lib = @import("matrix_lib");
const autofab = @import("../runtime/autofab.zig");
const main_mod = @import("../main.zig");
const platform = @import("platform");
const expr = @import("expr");
const heaven_expr = @import("heaven_expr");

// En mode DEBUG, on lit depuis le disque pour éviter de recompiler
const DEBUG_MODE = platform.target.is_debug;
const public_dir = "src/vessel/public/";

const index_html = @embedFile("public/index.html");
const repl_html = @embedFile("public/repl.html");
const dashboard_html = @embedFile("public/dashboard.html");
const ide_html = @embedFile("public/ide.html");
const docs_html = @embedFile("public/docs.html");
const common_css = @embedFile("public/common.css");
const wasm_core_js = @embedFile("public/wasm-core.js");
const editor_frame_html = @embedFile("public/editor-frame.html");
const repl_frame_html = @embedFile("public/repl-frame.html");
const debugger_frame_html = @embedFile("public/debugger-frame.html");
const process_frame_html = @embedFile("public/process-frame.html");
const test_html = @embedFile("public/test.html");
const test_suite_hvn = @embedFile("public/test_suite.hvn");

pub const WebBridge = struct {
    matrix: *matrix_lib.Matrix,
    fab: *autofab.AutoFab,
    heaven: *heaven_expr.Heaven,
    port: u16,
    // Un booléen atomique : false = libre, true = occupé
    busy: atomic.Value(bool) = atomic.Value(bool).init(false),

    fn escapeJson(allocator: std.mem.Allocator, input: []const u8) []const u8 {
        const output = allocator.dupe(u8, input) catch return "error";
        for (output) |*c| {
            if (c.* == '"') c.* = '\'';
            if (c.* < 32 or c.* > 126) c.* = ' ';
        }
        return output;
    }

    pub fn serveTelemetry(self: *WebBridge, allocator: std.mem.Allocator) ![]u8 {
        const net2 = @import("../scut/network.zig");
        var ports = std.ArrayListUnmanaged(u16){};
        defer ports.deinit(allocator);
        for (net2.known_peers.items) |peer| {
            try ports.append(allocator, peer.address.getPort());
        }
        return @import("telemetry_store.zig").render(allocator, self.heaven.getStore(), self.port, ports.items);
    }
};

const HandlerArgs = struct { conn: std.net.Server.Connection, bridge: *WebBridge, allocator: std.mem.Allocator };

fn getMimeType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    return "text/html";
}

fn respond(
    stream: std.net.Stream,
    statusLine: []const u8,
    mimeType: []const u8,
    payload: []const u8,
) !void {
    var header_buf: [1024]u8 = undefined;

    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Access-Control-Allow-Origin: *\r\n" ++
            "Connection: close\r\n" ++
            "Content-Length: {d}\r\n" ++
            "\r\n",
        .{ statusLine, mimeType, payload.len },
    );
    //platform.dbg("[VESSEL] Respond header:{s} payload:{s}\n", .{ header, payload });
    try stream.writeAll(header);
    try stream.writeAll(payload);
}

fn serveFile(path_in_url: []const u8, stream: std.net.Stream, allocator: std.mem.Allocator) !void {
    // Sécuriser : ne pas laisser remonter avec ../
    if (std.mem.indexOf(u8, path_in_url, "..") != null) {
        try respond(stream, "400 Bad Request", "text/plain", "bad path");
        return;
    }

    const rel = std.mem.trimLeft(u8, path_in_url, "/");
    var file_path_buf: [1024]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&file_path_buf, "{s}{s}", .{ public_dir, rel });

    const file = platform.fs.cwd().openFile(full_path, .{}) catch {
        try respond(stream, "404 Not Found", "text/plain", "not found");
        return;
    };
    defer file.close();

    const stat = try file.stat();
    const data = try allocator.alloc(u8, stat.size);
    defer allocator.free(data);
    _ = try file.readAll(data);

    const mime = getMimeType(full_path);
    try respond(stream, "200 OK", mime, data);
}

// --- LOGIQUE HTTP (RÉINTÉGRÉE) ---
fn handleHttp(args: HandlerArgs, request: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(args.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    //platform.dbg("[handleHttp] request:{s}\n", .{request});

    if (std.mem.indexOf(u8, request, "GET /telemetry") != null) {
        const telemetry = try args.bridge.serveTelemetry(aa);
        const header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(telemetry);
    } else if (std.mem.indexOf(u8, request, "GET /repl") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(repl_html);
    } else if (std.mem.indexOf(u8, request, "GET /heaven.wasm") != null) {
        try serveFile("heaven.wasm", args.conn.stream, args.allocator);
    } else if (std.mem.indexOf(u8, request, "GET /dashboard") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(dashboard_html);
    } else if (std.mem.indexOf(u8, request, "GET /ide") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(ide_html);
    } else if (std.mem.indexOf(u8, request, "GET /docs") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(docs_html);
    } else if (std.mem.indexOf(u8, request, "GET /common.css") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/css\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(common_css);
    } else if (std.mem.indexOf(u8, request, "GET /wasm-core.js") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: application/javascript\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(wasm_core_js);
    } else if (std.mem.indexOf(u8, request, "GET /editor-frame.html") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(editor_frame_html);
    } else if (std.mem.indexOf(u8, request, "GET /repl-frame.html") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(repl_frame_html);
    } else if (std.mem.indexOf(u8, request, "GET /debugger-frame.html") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(debugger_frame_html);
    } else if (std.mem.indexOf(u8, request, "GET /process-frame.html") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(process_frame_html);
    } else if (std.mem.indexOf(u8, request, "GET /test_heaven.js") != null) {
        const test_js = @embedFile("public/test_heaven.js");
        const header = "HTTP/1.1 200 OK\r\nContent-Type: application/javascript\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(test_js);
    } else if (std.mem.indexOf(u8, request, "GET /test_suite.hvn") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(test_suite_hvn);
    } else if (std.mem.indexOf(u8, request, "GET /test") != null) {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(test_html);
    } else {
        const header = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(index_html);
    }
}

// --- LOGIQUE LSP ---
fn extractUri(allocator: std.mem.Allocator, request: []const u8) ?[]const u8 {
    const uri_key = "\"uri\":\"";
    const start_index = std.mem.indexOf(u8, request, uri_key) orelse return null;
    const uri_start = start_index + uri_key.len;
    const end_index = std.mem.indexOfPos(u8, request, uri_start, "\"") orelse return null;

    const full_uri = request[uri_start..end_index];

    // Nettoyage du préfixe file:// (souvent file:///home/...)
    if (std.mem.startsWith(u8, full_uri, "file://")) {
        return allocator.dupe(u8, full_uri[7..]) catch null;
    }
    return allocator.dupe(u8, full_uri) catch null;
}

fn handleLsp(args: HandlerArgs, request: []const u8) !void {
    // Extraction de l'ID pour répondre avec le même que celui envoyé par Codium
    var id_slice: []const u8 = "1";
    if (std.mem.indexOf(u8, request, "\"id\":")) |pos| {
        const id_start = pos + 5;
        // On cherche la fin du nombre ou de la chaîne (virgule, accolade ou espace)
        if (std.mem.indexOfAnyPos(u8, request, id_start, ",} ")) |id_end| {
            id_slice = std.mem.trim(u8, request[id_start..id_end], " \"\r\n\t");
        }
    }

    if (std.mem.indexOf(u8, request, "initialize") != null) {
        // Construction de la réponse JSON
        // On utilise l'allocateur pour injecter l'ID dynamiquement
        const resp = try std.fmt.allocPrint(args.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": {s},
            \\  "result": {{
            \\    "capabilities": {{
            \\      "textDocumentSync": {{
            \\        "openClose": true,
            \\        "change": 1,
            \\        "save": {{ "includeText": true }}
            \\      }}
            \\    }}
            \\  }}
            \\}}
        , .{id_slice});
        defer args.allocator.free(resp);

        var h_buf: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&h_buf, "Content-Length: {d}\r\n\r\n", .{resp.len});
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(resp);
        // platform.dbg("[LSP] Réponse initialize envoyée (ID: {s})\n", .{id_slice});
    } else if (std.mem.indexOf(u8, request, "textDocument/didSave") != null) {
        const path = extractUri(args.allocator, request) orelse return;
        defer args.allocator.free(path);

        // Tente de prendre le verrou atomique
        if (args.bridge.busy.cmpxchgStrong(false, true, .seq_cst, .seq_cst)) |_| {
            // Si on entre ici, c'est que c'est déjà occupé. On ignore.
            return;
        }
        // Libère le verrou à la fin de la fonction
        defer args.bridge.busy.store(false, .seq_cst);

        // platform.debug.print("\n[LSP] Synchronisation (Unique) : {s}\n", .{path});

        const file = platform.fs.cwd().openFile(path, .{}) catch |err| {
            platform.dbg("[LSP] openFile {s}: {any}\n", .{ path, err });
            return;
        };
        defer file.close();
        const stat = file.stat() catch return;
        const src = args.allocator.alloc(u8, stat.size) catch return;
        defer args.allocator.free(src);
        _ = file.readAll(src) catch return;
        var stmts: std.ArrayListUnmanaged([]const u8) = .{};
        defer {
            for (stmts.items) |st| args.allocator.free(st);
            stmts.deinit(args.allocator);
        }
        @import("../runtime/test_runner.zig").splitStatements(args.allocator, src, &stmts) catch return;
        var ok: usize = 0;
        var fail: usize = 0;
        for (stmts.items) |stmt| {
            const trimmed = std.mem.trim(u8, stmt, " \t\r\n");
            if (trimmed.len == 0) continue;
            const res = args.bridge.heaven.eval(trimmed) catch |err| {
                platform.dbg("[LSP] eval {s}: {any}\n", .{ path, err });
                fail += 1;
                continue;
            };
            args.allocator.free(res);
            ok += 1;
        }
        // On affiche le résultat immédiatement dans le flux de logs
        {
            const st = args.bridge.heaven.getStore();
            platform.debug.print(">>> HEAVEN EVAL {s}: {d} ok, {d} fail, store={d} nodes, {d} syms <<<\n", .{
                path, ok, fail, st.nodes.items.len, st.interner.list.items.len,
            });
        }
    }
}

fn handleClient(args: HandlerArgs) void {
    defer args.conn.stream.close();
    var read_buf: [32768]u8 = undefined; // Buffer plus large pour les gros fichiers

    while (true) {
        const n = platform.streamRead(args.conn.stream, &read_buf) catch break;
        if (n == 0) break;
        const request = read_buf[0..n];

        // On logue systématiquement pour voir si Codium parle
        // platform.dbg("[VESSEL] Message reçu ({d} octets)\n", .{n});

        if (std.mem.indexOf(u8, request, "GET /") != null) {
            handleHttp(args, request) catch {};
            return;
        } else {
            // Ici, on traite le message. Si c'est juste un header Content-Length,
            // le prochain tour de boucle lira le JSON.
            handleLsp(args, request) catch |err| {
                platform.dbg("[LSP ERR] {any}\n", .{err});
            };
        }
    }
}

pub fn startVesselServer(
    matrix: *matrix_lib.Matrix,
    fab: *autofab.AutoFab,
    heaven: *heaven_expr.Heaven,
    dash_port: u16,
    exiting: *const std.atomic.Value(bool),
) void {
    const address = std.net.Address.parseIp4("127.0.0.1", dash_port) catch return;
    var server = address.listen(.{ .reuse_address = true }) catch |err| {
        platform.dbg("[VESSEL] Listen Error: {any}\n", .{err});
        return;
    };

    platform.debug.print("Vessel HTTP: http://localhost:{d}/\n", .{dash_port});

    var bridge = WebBridge{ .matrix = matrix, .fab = fab, .heaven = heaven, .port = dash_port };
    while (true) {
        // Vérifier la sortie avant chaque accept
        if (exiting.load(.acquire)) break;

        // Accepter avec un timeout (si possible) – sinon, accept bloquant et on vérifie après
        const conn = server.accept() catch {
            // Si erreur, on attend un peu et on recheck
            platform.Thread.sleep(10 * std.time.ns_per_ms);
            continue;
        };
        // Vérifier à nouveau après l'accept
        if (exiting.load(.acquire)) {
            conn.stream.close();
            break;
        }

        const t = platform.Thread.spawn(.{}, handleClient, .{HandlerArgs{ .conn = conn, .bridge = &bridge, .allocator = matrix.allocator }}) catch {
            conn.stream.close();
            continue;
        };
        t.detach();
    }
    return;
}
