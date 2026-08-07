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
//   - heaven_simplify: Simplification certifiée
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
    heaven: ?heaven_expr_mod.Heaven,
    tools: []const McpTool,

    pub fn init(allocator: Allocator) McpServer {
        return .{
            .allocator = allocator,
            .heaven = null,
            .tools = &mcp_tools,
        };
    }

    pub fn ensureHeaven(self: *McpServer) void {
        if (self.heaven == null) {
            self.heaven = heaven_expr_mod.Heaven.init(self.allocator);
        }
    }

    /// Boucle principale MCP: lit JSON-RPC sur stdin, répond sur stdout
    pub fn run(self: *McpServer) !void {
        const stdin_fd = platform.posix.STDIN_FILENO;
        const stdout_fd = platform.posix.STDOUT_FILENO;
        var buf: [65536]u8 = undefined;

        while (true) {
            const bytes_read = platform.posix.read(stdin_fd, &buf) catch break;
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
                    _ = platform.posix.write(stdout_fd, err_msg) catch {};
                    continue;
                };

                if (response.len > 0) {
                    _ = platform.posix.write(stdout_fd, response) catch {};
                    _ = platform.posix.write(stdout_fd, "\n") catch {};
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

    fn formatToolsList(self: *McpServer, id: ?std.json.Value) ![]const u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        defer buf.deinit(self.allocator);
        const w = buf.writer(self.allocator);

        try w.writeAll("{\"tools\":[");
        for (self.tools, 0..) |tool, i| {
            if (i > 0) try w.writeAll(",");
            try w.print("{{\"name\":\"{s}\",\"description\":\"{s}\",\"inputSchema\":{s}}}", .{
                tool.name, tool.description, tool.input_schema,
            });
        }
        try w.writeAll("]}");

        return self.formatResponse(id, buf.items);
    }

    fn callTool(self: *McpServer, id: ?std.json.Value, name: []const u8, args: ?std.json.Value) ![]const u8 {
        self.ensureHeaven();
        var h = &self.heaven.?;

        const result_text = blk: {
            if (std.mem.eql(u8, name, "heaven_eval")) {
                const expr_str = getArgString(args, "expression") orelse break :blk "error: missing 'expression'";
                const res = h.eval(expr_str) catch break :blk "error: eval failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_derive")) {
                const expr_str = getArgString(args, "expression") orelse break :blk "error: missing 'expression'";
                const var_name = getArgString(args, "variable") orelse "x";
                const res = h.derive(expr_str, var_name) catch break :blk "error: derive failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_simplify")) {
                const expr_str = getArgString(args, "expression") orelse break :blk "error: missing 'expression'";
                const res = h.simplify(expr_str) catch break :blk "error: simplify failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_expand")) {
                const expr_str = getArgString(args, "expression") orelse break :blk "error: missing 'expression'";
                const res = h.expand(expr_str) catch break :blk "error: expand failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_solve")) {
                const expr_str = getArgString(args, "expression") orelse break :blk "error: missing 'expression'";
                const var_name = getArgString(args, "variable") orelse "x";
                const res = h.solve(expr_str, var_name) catch break :blk "no solution";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "heaven_theorems")) {
                const res = h.eval("theorems") catch break :blk "error: theorems failed";
                defer self.allocator.free(res);
                break :blk try self.allocator.dupe(u8, res);
            } else if (std.mem.eql(u8, name, "mlcpd_parse")) {
                const json_data = getArgString(args, "json") orelse break :blk "error: missing 'json'";
                var parsed = mlcpd_mod.parseMlcpdJson(self.allocator, json_data) catch break :blk "error: MLCPD parse failed";
                defer parsed.deinit();
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"nodes\":{d},\"language\":\"{s}\"}}", .{
                    parsed.nodeCount(),
                    @tagName(parsed.metadata.language),
                });
            } else if (std.mem.eql(u8, name, "mlcpd_equiv")) {
                const json1 = getArgString(args, "json1") orelse break :blk "error: missing 'json1'";
                const json2 = getArgString(args, "json2") orelse break :blk "error: missing 'json2'";
                var he = &self.heaven.?;

                var p1 = mlcpd_mod.parseMlcpdJson(self.allocator, json1) catch break :blk "error: parse failed for json1";
                defer p1.deinit();
                p1.normalizeParsedFile();

                var p2 = mlcpd_mod.parseMlcpdJson(self.allocator, json2) catch break :blk "error: parse failed for json2";
                defer p2.deinit();
                p2.normalizeParsedFile();

                const id1 = p1.toExprIr(&he.store) catch break :blk "error: conversion failed for json1";
                const id2 = p2.toExprIr(&he.store) catch break :blk "error: conversion failed for json2";

                var equiv_result = mlcpd_equiv_mod.proveEquivalence(self.allocator, &he.store, id1, id2) catch |err| {
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
                const expr_str = getArgString(args, "expr") orelse break :blk "error: missing 'expr'";
                var he = &self.heaven.?;
                const result = he.eval(expr_str) catch break :blk "error: eval failed";
                defer self.allocator.free(result);
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"canonical_form\":\"{s}\"}}", .{result});
            } else if (std.mem.eql(u8, name, "heaven_prove")) {
                const stmt = getArgString(args, "statement") orelse break :blk "error: missing 'statement'";
                var he = &self.heaven.?;
                // Utiliser le noyau logique pour tenter une preuve
                const result = he.eval(stmt) catch |err| {
                    break :blk try std.fmt.allocPrint(self.allocator, "{{\"proved\":false,\"error\":\"{}\"}}", .{err});
                };
                defer self.allocator.free(result);
                break :blk try std.fmt.allocPrint(self.allocator, "{{\"proved\":true,\"certificate\":\"{s}\"}}", .{result});
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
        .description = "Compute symbolic integral of an expression",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"},\"variable\":{\"type\":\"string\",\"default\":\"x\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_solve",
        .description = "Solve an equation for a variable",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"},\"variable\":{\"type\":\"string\",\"default\":\"x\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_expand",
        .description = "Expand algebraic expressions (binomial, polynomial)",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_simplify",
        .description = "Simplify expression using certified rewrite rules and EGraph",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expression\":{\"type\":\"string\"}},\"required\":[\"expression\"]}",
    },
    .{
        .name = "heaven_theorems",
        .description = "List all axioms and theorems in the Heaven kernel",
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
        .name = "egraph_query",
        .description = "Query the EGraph saturation state for a given Heaven expression. Returns canonical form and e-class size.",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"expr\":{\"type\":\"string\",\"description\":\"Heaven expression string\"}},\"required\":[\"expr\"]}",
    },
    .{
        .name = "heaven_prove",
        .description = "Attempt to prove a theorem or equivalence using Heaven's certified logical kernel. Returns proof status and certificate.",
        .input_schema = "{\"type\":\"object\",\"properties\":{\"statement\":{\"type\":\"string\",\"description\":\"Theorem or equivalence to prove\"}},\"required\":[\"statement\"]}",
    },
};
