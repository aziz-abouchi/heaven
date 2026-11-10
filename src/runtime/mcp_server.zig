// src/runtime/mcp_server.zig — MCP Server pour Heaven
// Expose les capacités du noyau Heaven via Model Context Protocol
// Compatible avec Claude Desktop et tout client MCP
//
// Outils exposés:
//   - heaven_eval: Évaluer une expression Heaven
//   - heaven_derive: Dérivée symbolique
//   - heaven_integrate: Intégrale symbolique
//   - heaven_solve: Résolution d'équations
//   - heaven_expand: Développement algébrique
//   - heaven_simplify: Simplification vérifiée par construction
//   - heaven_prove: Vérification de preuve
//   - heaven_theorems: Liste des théorèmes
//   - mlcpd_parse: Parser du code via MLCPD universal schema
//   - mlcpd_to_heaven: Convertir AST MLCPD → Expr IR
//   - egraph_query: Requêter l'EGraph saturé

const std = @import("std");
const Allocator = std.mem.Allocator;
const platform = @import("platform");
const heaven_expr_mod = @import("heaven_expr");
const mlcpd_mod = @import("mlcpd");
const mlcpd_equiv_mod = @import("mlcpd_equiv");

pub const McpError = error{
    InvalidJson,
    UnknownMethod,
    UnknownTool,
    ToolExecutionFailed,
    OutOfMemory,
    IoError,
};

// ═══════════════════════════════════════════════════════════
// MCP Protocol Types (JSON-RPC 2.0 over stdio)
// ═══════════════════════════════════════════════════════════

pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?std.json.Value = null,
    method: []const u8,
    params: ?std.json.Value = null,
};

pub const McpTool = struct {
    name: []const u8,
    description: []const u8,
    input_schema: []const u8, // JSON Schema string
};

pub const McpServer = struct {
    allocator: Allocator,
    heaven: ?*heaven_expr_mod.Heaven,
    tools: []const McpTool,
    /// Cache de la sérialisation JSON du registre 16 tools
    /// (`lib/tool_registry.hvn`). Rempli au premier `tools/list`
    /// (700ms), réutilisé ensuite. Libéré dans `deinit`. Session 46.
    registry_json_cache: ?[]u8 = null,

    pub fn init(allocator: Allocator) McpServer {
        return .{
            .allocator = allocator,
            .heaven = null,
            .tools = &mcp_tools,
        };
    }

    pub fn ensureHeaven(self: *McpServer) void {
        if (self.heaven == null) {
            self.heaven = heaven_expr_mod.Heaven.init(self.allocator) catch @panic("Failed to init Heaven");
            // Charger le registre une fois (Session 46, B2). Si l'import
            // échoue (ex. `heaven mcp` lancé hors racine), on log et on
            // continue : `tools/list` tombera sur la liste vide, ce qui
            // est préférable à un crash du serveur.
            const h = self.heaven.?;
            if (h.eval("import \"lib/tool_registry.hvn\" as TR")) |res| {
                self.allocator.free(res);
            } else |_| {
                platform.debug.print("[mcp] warning: import tool_registry failed\n", .{});
            }
        }
    }

    /// Libère l'état Heaven (store, e-graph, interner).
    /// Sans ceci, le GPA de main rapporte des milliers de leaks au shutdown.
    pub fn deinit(self: *McpServer) void {
        if (self.registry_json_cache) |c| {
            self.allocator.free(c);
            self.registry_json_cache = null;
        }
        if (self.heaven) |h| {
            h.deinit();
            self.allocator.destroy(h);
            self.heaven = null;
        }
    }

    /// Boucle principale MCP: lit JSON-RPC sur stdin, répond sur stdout
    pub fn run(self: *McpServer) !void {
        var buf: [65536]u8 = undefined;

        while (true) {
            const bytes_read = platform.readStdin(&buf) catch break;
            if (bytes_read == 0) break;
            const data = buf[0..bytes_read];

            // Traiter chaque ligne JSON séparément (newline-delimited JSON-RPC)
            var remaining = data;
            while (remaining.len > 0) {
                const newline_pos = std.mem.indexOfScalar(u8, remaining, '\n');
                const line_end = newline_pos orelse remaining.len;
                const line = std.mem.trim(u8, remaining[0..line_end], " \t\r");
                remaining = if (newline_pos != null) remaining[line_end + 1 ..] else "";

                if (line.len == 0) continue;

                // notifications/initialized n'a pas de réponse
                if (std.mem.indexOf(u8, line, "\"method\":\"notifications/") != null) continue;

                const response = self.handleMessage(line) catch |err| {
                    const err_msg = switch (err) {
                        error.InvalidJson => "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null}\n",
                        error.UnknownMethod => "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32601,\"message\":\"Method not found\"},\"id\":null}\n",
                        else => "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":-32603,\"message\":\"Internal error\"},\"id\":null}\n",
                    };
                    _ = platform.writeStdout(err_msg) catch {};
                    continue;
                };

                if (response.len > 0) {
                    _ = platform.writeStdout(response) catch {};
                    _ = platform.writeStdout("\n") catch {};
                    self.allocator.free(response);
                }
            }
        }
    }

    fn handleMessage(self: *McpServer, msg: []const u8) ![]const u8 {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, msg, .{}) catch return error.InvalidJson;
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        const method = root.object.get("method") orelse return error.InvalidJson;
        if (method != .string) return error.InvalidJson;
        const method_str = method.string;

        const id = root.object.get("id");

        // MCP Methods
        if (std.mem.eql(u8, method_str, "initialize")) {
            return try self.formatResponse(id,
                \\{"protocolVersion":"2024-11-05","capabilities":{"tools":{}},"serverInfo":{"name":"heaven-mcp","version":"0.1.0"}}
            );
        }

        if (std.mem.eql(u8, method_str, "notifications/initialized")) {
            return ""; // Pas de réponse pour les notifications
        }

        if (std.mem.eql(u8, method_str, "tools/list")) {
            return try self.formatToolsList(id);
        }

        if (std.mem.eql(u8, method_str, "tools/call")) {
            const params = root.object.get("params") orelse return error.InvalidJson;
            const tool_name = params.object.get("name") orelse return error.InvalidJson;
            if (tool_name != .string) return error.InvalidJson;
            const args = params.object.get("arguments");
            return try self.callTool(id, tool_name.string, args);
        }

        return error.UnknownMethod;
    }

    fn formatResponse(self: *McpServer, id: ?std.json.Value, result_json: []const u8) ![]const u8 {
        if (id) |i| {
            if (i == .integer) {
                return std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":{s},\"id\":{d}}}", .{ result_json, i.integer });
            }
        }
        return std.fmt.allocPrint(self.allocator, "{{\"jsonrpc\":\"2.0\",\"result\":{s},\"id\":null}}", .{result_json});
    }

    /// Charge (ou récupère du cache) le JSON du registre 16 tools.
    /// `heaven.eval("(TR.registry_to_json 0)")` retourne la string quotée
    /// `"{"tools":[...]}"` — on strippe les quotes externes. Les quotes
    /// internes sont bruts (pas échappés) et sont corrects pour JSON.
    fn loadRegistryJson(self: *McpServer) ![]const u8 {
        if (self.registry_json_cache) |c| return c;
        var h = self.heaven.?;
        const raw = h.eval("(TR.registry_to_json 0)") catch {
            const empty = try self.allocator.dupe(u8, "{\"tools\":[]}");
            self.registry_json_cache = empty;
            return empty;
        };
        defer self.allocator.free(raw);
        var body = raw;
        if (body.len >= 2 and body[0] == '"' and body[body.len - 1] == '"') {
            body = body[1 .. body.len - 1];
        }
        const owned = try self.allocator.dupe(u8, body);
        self.registry_json_cache = owned;
        return owned;
    }

    fn formatToolsList(self: *McpServer, id: ?std.json.Value) ![]const u8 {
        self.ensureHeaven();
        const json = try self.loadRegistryJson();
        return self.formatResponse(id, json);
    }

    fn callTool(self: *McpServer, id: ?std.json.Value, name: []const u8, args: ?std.json.Value) ![]const u8 {
        self.ensureHeaven();
        var h = self.heaven.?;

        const result_text = blk: {
            if (std.mem.eql(u8, name, "heaven_eval")) {
                const expr_str = getArgString(args, "expression") orelse break :blk try self.allocator.dupe(u8, "error: missing 'expression'");
                const res = h.eval(expr_str) catch break :blk "error: eval failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_derive")) {
                const expr_str = getArgString(args, "expression") orelse break :blk try self.allocator.dupe(u8, "error: missing 'expression'");
                const var_name = getArgString(args, "variable") orelse "x";
                const res = h.derive(expr_str, var_name) catch break :blk "error: derive failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_integrate")) {
                const expr_str = getArgString(args, "expression") orelse break :blk try self.allocator.dupe(u8, "error: missing 'expression'");
                const var_name = getArgString(args, "variable") orelse "x";
                const res = h.integrate(expr_str, var_name) catch break :blk "error: integrate failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_simplify")) {
                const expr_str = getArgString(args, "expression") orelse break :blk try self.allocator.dupe(u8, "error: missing 'expression'");
                const res = h.simplify(expr_str) catch break :blk "error: simplify failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_expand")) {
                // Désactivé (audit 2026-11-09) : fuite de debug sur stdout rompt JSON-RPC.
                break :blk try self.allocator.dupe(u8, "error: tool disabled (see docs/spec/_tool_audit_2026-11-09.md)");
            } else if (std.mem.eql(u8, name, "heaven_solve")) {
                const expr_str = getArgString(args, "expression") orelse break :blk try self.allocator.dupe(u8, "error: missing 'expression'");
                const var_name = getArgString(args, "variable") orelse "x";
                const res = h.solve(expr_str, var_name) catch break :blk "no solution";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_theorems")) {
                const res = h.eval("theorems") catch break :blk "error: theorems failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "mlcpd_parse")) {
                const json_data = getArgString(args, "json") orelse break :blk try self.allocator.dupe(u8, "error: missing 'json'");
                var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch break :blk "error: MLCPD parse failed";
                defer parsed.deinit();
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"nodes\":{d},\"language\":\"{s}\"}}", .{
                    parsed.nodeCount(),
                    @tagName(parsed.metadata.language),
                });
            } else if (std.mem.eql(u8, name, "mlcpd_equiv")) {
                const json1 = getArgString(args, "json1") orelse break :blk try self.allocator.dupe(u8, "error: missing 'json1'");
                const json2 = getArgString(args, "json2") orelse break :blk try self.allocator.dupe(u8, "error: missing 'json2'");
                var he = self.heaven.?;

                var p1 = mlcpd_mod.parseMlcpdJson(self.allocator, json1) catch break :blk "error: parse failed for json1";
                defer p1.deinit();
                p1.normalizeParsedFile();

                var p2 = mlcpd_mod.parseMlcpdJson(self.allocator, json2) catch break :blk "error: parse failed for json2";
                defer p2.deinit();
                p2.normalizeParsedFile();

                const id1 = p1.toExprIr(he.store) catch break :blk "error: conversion failed for json1";
                const id2 = p2.toExprIr(he.store) catch break :blk "error: conversion failed for json2";

                var equiv_result = mlcpd_equiv_mod.proveEquivalence(self.allocator, he.store, id1, id2) catch |err| {
                    break :blk try std.fmt.allocPrint(self.allocator, "{{\"error\":\"equivalence proof failed: {}\"}}", .{err});
                };
                defer equiv_result.deinit(self.allocator);

                // Construire la réponse JSON
                var s1_str: []const u8 = "null";
                var s2_str: []const u8 = "null";
                var s1_owned: ?[]u8 = null;
                var s2_owned: ?[]u8 = null;

                if (equiv_result.canon1) |c1| {
                    s1_owned = he.format(c1) catch null;
                    if (s1_owned) |s| s1_str = s;
                }
                if (equiv_result.canon2) |c2| {
                    s2_owned = he.format(c2) catch null;
                    if (s2_owned) |s| s2_str = s;
                }

                defer if (s1_owned) |s| self.allocator.free(s);
                defer if (s2_owned) |s| self.allocator.free(s);

                const proof_available = if (equiv_result.proof != null) "true" else "false";
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"equivalent\":{s},\"strategy\":\"{s}\",\"proof_available\":{s},\"canon1\":\"{s}\",\"canon2\":\"{s}\"}}", .{ if (equiv_result.equivalent) "true" else "false", @tagName(equiv_result.strategy), proof_available, s1_str, s2_str });
            } else if (std.mem.eql(u8, name, "egraph_query")) {
                // Désactivé (audit 2026-11-09) : panic "Invalid free".
                break :blk try self.allocator.dupe(u8, "error: tool disabled (see docs/spec/_tool_audit_2026-11-09.md)");
            } else if (std.mem.eql(u8, name, "heaven_prove")) {
                const stmt = getArgString(args, "statement") orelse break :blk try self.allocator.dupe(u8, "error: missing 'statement'");
                var he = self.heaven.?;

                // 1. Kernel de preuve : syntaxe "prove <name> by { ... }"
                //    (fix 2026-11-10 : fake "Usage" + panic résolus,
                //    préfixe "prove " stripé dans evalProve).
                if (std.mem.indexOf(u8, stmt, " by ") != null) {
                    if (he.evalProve(stmt)) |result| {
                        defer self.allocator.free(result);
                        // evalProve retourne Ok("✓ …") sur succès et
                        // Ok("✗ …") sur échec. Un '✗' ne doit PAS être
                        // traduit en proved:true (faux positif — bug 2026-11-10).
                        const trimmed = std.mem.trim(u8, result, " \t\r\n");
                        const is_ok = trimmed.len > 0 and std.mem.startsWith(u8, trimmed, "✓");
                        break :blk try std.fmt.allocPrint(self.allocator,
                            "{{\"proved\":{s},\"method\":\"kernel\",\"certificate\":\"{s}\"}}",
                            .{ if (is_ok) "true" else "false", result });
                    } else |_| {}
                }

                // 2. Égalité sémantique "a == b" (eval LHS, eval RHS, compare)
                if (std.mem.indexOf(u8, stmt, "==")) |pos| {
                    const lhs_str = std.mem.trim(u8, stmt[0..pos], " \t");
                    const rhs_str = std.mem.trim(u8, stmt[pos + 2 ..], " \t");
                    if (lhs_str.len > 0 and rhs_str.len > 0) {
                        if (he.eval(lhs_str)) |lhs_val| {
                            defer self.allocator.free(lhs_val);
                            if (he.eval(rhs_str)) |rhs_val| {
                                defer self.allocator.free(rhs_val);
                                const eq = std.mem.eql(u8, lhs_val, rhs_val);
                                break :blk try std.fmt.allocPrint(self.allocator,
                                    "{{\"proved\":{s},\"method\":\"semantic\",\"lhs\":\"{s}\",\"rhs\":\"{s}\"}}",
                                    .{ if (eq) "true" else "false", lhs_val, rhs_val });
                            } else |_| {}
                        } else |_| {}
                    }
                }

                // 2. Ni kernel, ni ==  → erreur explicite (plus de faux positif)
                break :blk try self.allocator.dupe(u8, "{\"proved\":false,\"error\":\"statement must be 'prove name by { ... }' or an equality 'a == b'\"}");
            } else {
                break :blk try std.fmt.allocPrint(self.allocator, "error: unknown tool '{s}'", .{name});
            }
        };
        defer self.allocator.free(result_text);

        // Formater comme MCP tool result
        const escaped = try escapeJson(self.allocator, result_text);
        defer self.allocator.free(escaped);

        const content = try std.fmt.allocPrint(self.allocator,
            \\{{"content":[{{"type":"text","text":"{s}"}}]}}
        , .{escaped});
        defer self.allocator.free(content);

        return self.formatResponse(id, content);
    }
};

fn getArgString(args: ?std.json.Value, key: []const u8) ?[]const u8 {
    const a = args orelse return null;
    if (a != .object) return null;
    const v = a.object.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn escapeJson(allocator: Allocator, s: []const u8) ![]const u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    defer buf.deinit(allocator);
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
    return buf.toOwnedSlice(allocator);
}

// ═══════════════════════════════════════════════════════════
// Tool Definitions
// ═══════════════════════════════════════════════════════════

const mcp_tools = [_]McpTool{
    .{
        .name = "heaven_eval",
        .description = "Evaluate a Heaven expression (arithmetic, symbolic, function calls)",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\",\"description\":\"Heaven expression to evaluate\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_derive",
        .description = "Compute symbolic derivative of an expression",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"},\"variable\":{\"type\":\"string\",\"default\":\"x\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_integrate",
        .description = "WARNING EXPERIMENTAL: currently returns incorrect formulas (e.g. x^2 -> x^2*x instead of x^3/3). Do NOT use for verification. See docs/spec/_integrate_bug.md.",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"},\"variable\":{\"type\":\"string\",\"default\":\"x\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_solve",
        .description = "WARNING EXPERIMENTAL: returns incorrect results (e.g. x+1=0 -> 'tout x'). Do NOT use for verification. See docs/spec/_tool_audit_2026-11-09.md.",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"},\"variable\":{\"type\":\"string\",\"default\":\"x\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_simplify",
        .description = "Simplify expression using verified rewrite rules and EGraph",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_theorems",
        .description = "SUSPECT (audit 2026-11-09): returns the literal 'theorems' string, not the actual list. Do NOT use.",
        .input_schema = "{\"type\":\"object\",\"properties\":{}}",
    },
    .{
        .name = "mlcpd_parse",
        .description = "Parse code using MLCPD universal AST schema (supports C, C++, Go, Java, JS, Python, Ruby, Scala, TS, C#)",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"json\":{\"type\":\"string\",\"description\":\"MLCPD JSON data\"}},\"required\":[\"json\"]}",
    },
    .{
        .name = "mlcpd_equiv",
        .description = "Check structural equivalence of two MLCPD JSON files via EGraph canonization. Returns true if both normalize to the same canonical form.",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"json1\":{\"type\":\"string\",\"description\":\"First MLCPD JSON\"},\"json2\":{\"type\":\"string\",\"description\":\"Second MLCPD JSON\"}},\"required\":[\"json1\",\"json2\"]}",
    },
    .{
        .name = "heaven_prove",
        .description = "Verify equality via two methods: (1) kernel: 'prove NAME by { tactics }' on registered theorems, using simplification/induction; (2) semantic: 'a == b' comparing evaluated results. See _heaven_prove_kernel_bug.md (fixed 2026-11-10).",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"statement\":{\"type\":\"string\",\"description\":\"Theorem or equivalence to prove\"}},\"required\":[\"statement\"]}",
    },
};
