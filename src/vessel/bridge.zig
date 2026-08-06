const std = @import("std");
const atomic = std.atomic;
const matrix_lib = @import("matrix_lib");
const autofab = @import("../runtime/autofab.zig");
const main_mod = @import("../main.zig");
const platform = @import("platform");

// En mode DEBUG, on lit depuis le disque pour éviter de recompiler
const DEBUG_MODE = @import("builtin").mode == .Debug;
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

pub const WebBridge = struct {
    matrix: *matrix_lib.Matrix,
    fab: *autofab.AutoFab,
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
        var list = std.ArrayListUnmanaged(u8){};
        const writer = list.writer(allocator);
        const stats = self.matrix.getStats();
        try writer.writeAll("{ \"stats\": {");

        const approx_bytes = stats.nodes * 64 + stats.symbols * 32;
        const load = if (stats.nodes > 0) @min(@as(f64, @floatFromInt(stats.nodes)) / 1000.0, 1.0) else 0.0;
        try std.fmt.format(writer, "\"node_count\": {d}, \"symbol_count\": {d}, \"approx_bytes\": {d}, \"hash_map_load\": {d:.4}", .{ stats.nodes, stats.symbols, approx_bytes, load });

        try writer.writeAll("}, \"nodes\": [");
        // Bob node
        try std.fmt.format(writer, "{{\"id\": 99999, \"tag\": \"Bob\", \"label\": \"Bob:{d}\", \"status\": \"active\"}}", .{self.port});

        var first_node = false;

        // Add peer Bob nodes
        const net2 = @import("../scut/network.zig");
        for (net2.known_peers.items) |peer| {
            const pp = peer.address.getPort();
            try writer.writeAll(",");
            try std.fmt.format(writer, "{{\"id\": {d}, \"tag\": \"Bob\", \"label\": \"Bob:{d}\", \"status\": \"active\"}}", .{ pp, pp });
        }

        var node_it = self.matrix.nodes.iterator();
        var edges = std.ArrayListUnmanaged(matrix_lib.Edge){};
        defer edges.deinit(allocator);

        while (node_it.next()) |entry| {
            const id = entry.key_ptr.*;
            const node = entry.value_ptr.*;
            if (node == .Edge) {
                try edges.append(allocator, node.Edge);
                continue;
            }
            if (!first_node) try writer.writeAll(",");
            first_node = false;

            const label = switch (node) {
                .Symbol => |s| try std.fmt.allocPrint(allocator, "Sym:{s}", .{s}),
                .NativeCode => "Native",
                else => try std.fmt.allocPrint(allocator, "{s}", .{@tagName(node)}),
            };
            defer allocator.free(label);

            try std.fmt.format(writer, "{{\"id\": {d}, \"tag\": \"Symbol\", \"label\": \"{s}\", \"status\": \"stable\"}}", .{ id, escapeJson(allocator, label) });
        }

        try writer.writeAll("], \"links\": [");
        var first_edge = true;
        for (edges.items) |e| {
            if (!first_edge) try writer.writeAll(",");
            first_edge = false;
            try std.fmt.format(writer, "{{\"source\": {d}, \"target\": {d}, \"label\": \"{s}\"}}", .{ e.source, e.target, escapeJson(allocator, e.label) });
        } // Auto-generate links: rules referencing predicates
        var rule_it = self.matrix.nodes.iterator();
        while (rule_it.next()) |rentry| {
            const rid = rentry.key_ptr.*;
            const rnode = rentry.value_ptr.*;
            if (rnode != .Symbol) continue;
            const rlabel = rnode.Symbol;
            if (!std.mem.startsWith(u8, rlabel, "RULE:")) continue;
            // Find predicates referenced in the rule body
            var fact_it = self.matrix.nodes.iterator();
            while (fact_it.next()) |fentry| {
                const fid = fentry.key_ptr.*;
                const fnode = fentry.value_ptr.*;
                if (fnode != .Symbol) continue;
                const flabel = fnode.Symbol;
                if (!std.mem.startsWith(u8, flabel, "FACT:")) continue;
                // Extract predicate name from FACT:pred(...)
                const fpred_start: usize = 5;
                const fparen = std.mem.indexOfScalar(u8, flabel[fpred_start..], '(') orelse continue;
                const fpred = flabel[fpred_start .. fpred_start + fparen];
                // Check if rule body contains this predicate
                if (std.mem.indexOf(u8, rlabel, fpred) != null) {
                    if (!first_edge) try writer.writeAll(",");
                    first_edge = false;
                    try std.fmt.format(writer, "{{\"source\": {d}, \"target\": {d}, \"label\": \"uses\"}}", .{ rid, fid });
                }
            }
        }
        // Peer Bobs
        const net = @import("../scut/network.zig");
        const peers = net.known_peers.items;
        for (peers) |peer| {
            const peer_port = peer.address.getPort();
            if (!first_edge) try writer.writeAll(",");
            first_edge = false;
            try std.fmt.format(writer, "{{\"source\": 99999, \"target\": {d}, \"label\": \"p2p\"}}", .{peer_port});
        }

        // Swarm tasks as nodes
        const swarm_rt = @import("../runtime/swarm/runtime.zig");
        if (swarm_rt.global_inbox) |inbox| {
            for (inbox.items, 0..) |task, tidx| {
                try writer.writeAll(",");
                const task_expr = task.expr[0..task.expr_len];
                const escaped = escapeJson(allocator, task_expr);
                try std.fmt.format(writer, "{{\"id\": {d}, \"tag\": \"Swarm\", \"label\": \"[{s}] {s}\", \"status\": \"{s}\"}}", .{
                    @as(u32, @intCast(80000 + tidx)),
                    @tagName(task.kind),
                    escaped,
                    @tagName(task.status),
                });
            }
        }

        // Swarm completed results as nodes
        if (swarm_rt.global_results) |results| {
            for (results.items, 0..) |result, ridx| {
                try writer.writeAll(",");
                const res_text = result.result[0..result.result_len];
                const res_escaped = escapeJson(allocator, res_text);
                try std.fmt.format(writer, "{{\"id\": {d}, \"tag\": \"SwarmResult\", \"label\": \"\xe2\x9c\x93 {s} (Bob:{d})\", \"status\": \"solved\"}}", .{
                    @as(u32, @intCast(90000 + ridx)),
                    res_escaped,
                    result.solver_port,
                });
            }
        }

        // Links from swarm tasks to Bob
        if (swarm_rt.global_inbox) |inbox| {
            for (inbox.items, 0..) |task, tidx| {
                if (!first_edge) try writer.writeAll(",");
                first_edge = false;
                try std.fmt.format(writer, "{{\"source\": 99999, \"target\": {d}, \"label\": \"swarm\"}}", .{
                    @as(u32, @intCast(80000 + tidx)),
                });
                _ = task;
            }
        }

        // Links from swarm results to Bob
        if (swarm_rt.global_results) |results| {
            for (results.items, 0..) |_, ridx| {
                if (!first_edge) try writer.writeAll(",");
                first_edge = false;
                try std.fmt.format(writer, "{{\"source\": {d}, \"target\": 99999, \"label\": \"resolved\"}}", .{
                    @as(u32, @intCast(90000 + ridx)),
                });
            }
        }

        // Links from Bob to all nodes
        var bob_it = self.matrix.nodes.iterator();
        while (bob_it.next()) |bentry| {
            const bid = bentry.key_ptr.*;
            if (!first_edge) try writer.writeAll(",");
            first_edge = false;
            try std.fmt.format(writer, "{{\"source\": 99999, \"target\": {d}, \"label\": \"owns\"}}", .{bid});
        }
        try writer.writeAll("] }");
        return list.toOwnedSlice(allocator);
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
fn respond(stream: std.net.Server.Connection.Stream, statusLine: []const u8, mimeType: []const u8, payload: []const u8) !void {
    const header = "HTTP/1.1 " ++ statusLine ++ "\r\nContent-Type: " ++ mimeType ++ "\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
    try stream.writeAll(header);
    try stream.writeAll(payload);
}

fn serveFile(path_in_url: []const u8, stream: std.net.Server.Connection.Stream, allocator: std.mem.Allocator) !void {
    if (DEBUG_MODE) {
        // Sécuriser le chemin
        var file_path_buf: [1024]u8 = undefined;
        const file_path = try std.fmt.bufPrint(&file_path_buf, "{s}{s}", .{ public_dir, path_in_url });
        const file = platform.fs.cwd().openFile(file_path, .{}) catch |err| {
            platform.debug.print("[serveFile] Error: {any}\n", .{err});
            try respond(stream, "404 Not Found", "text/plain", "File not found");
            return;
        };
        defer file.close();
        const data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(data);
        const mime = getMimeType(path_in_url);
        try respond(stream, "200 OK", mime, data);
    } else {
        // Release : on utilise @embedFile (comportement actuel)
        // ... (gardez vos @embedFile et routes existantes)
    }
}

// --- LOGIQUE HTTP (RÉINTÉGRÉE) ---
fn handleHttp(args: HandlerArgs, request: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(args.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

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
        const wasm_data = @embedFile("public/heaven.wasm");
        const header = "HTTP/1.1 200 OK\r\nContent-Type: application/wasm\r\nCache-Control: no-store, no-cache, must-revalidate\r\nPragma: no-cache\r\nExpires: 0\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n";
        try args.conn.stream.writeAll(header);
        try args.conn.stream.writeAll(wasm_data);
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
        platform.debug.print("[LSP] Réponse initialize envoyée (ID: {s})\n", .{id_slice});
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

        platform.debug.print("\n[LSP] Synchronisation (Unique) : {s}\n", .{path});

        _ = main_mod.syncMatrixWithFile(args.bridge.matrix, args.bridge.fab, args.allocator, path) catch |err| {
            platform.debug.print("[LSP ERR] {any}\n", .{err});
        };
        // On affiche le résultat immédiatement dans le flux de logs
        platform.debug.print(">>> MATRIX UPDATED: {d} nodes, {d} symbols <<<\n", .{
            args.bridge.matrix.nodes.count(),
            args.bridge.matrix.getStats().symbols,
        });
    }
}

fn handleClient(args: HandlerArgs) void {
    defer args.conn.stream.close();
    var read_buf: [32768]u8 = undefined; // Buffer plus large pour les gros fichiers

    while (true) {
        const n = args.conn.stream.read(&read_buf) catch break;
        if (n == 0) break;
        const request = read_buf[0..n];

        // On logue systématiquement pour voir si Codium parle
        //platform.debug.print("[VESSEL] Message reçu ({d} octets)\n", .{n});

        if (std.mem.indexOf(u8, request, "GET /") != null) {
            handleHttp(args, request) catch {};
            return;
        } else {
            // Ici, on traite le message. Si c'est juste un header Content-Length,
            // le prochain tour de boucle lira le JSON.
            handleLsp(args, request) catch |err| {
                platform.debug.print("[LSP ERR] {any}\n", .{err});
            };
        }
    }
}

pub fn startVesselServer(
    matrix: *matrix_lib.Matrix,
    fab: *autofab.AutoFab,
    dash_port: u16,
    exiting: *const std.atomic.Value(bool),
) void {
    const address = std.net.Address.parseIp4("127.0.0.1", dash_port) catch return;
    var server = address.listen(.{ .reuse_address = true }) catch |err| {
        platform.debug.print("[VESSEL] Listen Error: {any}\n", .{err});
        return;
    };
    var bridge = WebBridge{ .matrix = matrix, .fab = fab, .port = dash_port };
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
