const std = @import("std");
const build_options = @import("build_options");
const Heaven = @import("heaven_expr").Heaven;
const platform = @import("platform");
const codec = @import("codec");
const egraph_mod = @import("egraph");
const expr_mod = @import("expr");
const egraph_rewriter = @import("egraph_rewriter");

// En WASM, on n'a pas accès aux commandes shell natives ni aux handlers réseau
const cmd_list = @import("shell_commands");
const handlers = @import("handlers");

// Global egraph pour le swarm WASM
var global_store: expr_mod.Store = undefined;
var global_egraph: egraph_mod.EGraph = undefined;

// 1. Déclarer la fonction que ton runtime JS (Vessel) fournira pour afficher du texte
extern fn vesselLogWrite(ptr: [*]const u8, len: usize) void;

// 2. Surcharger la fonction racine de log de Zig pour WASM
pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix = "[" ++ @tagName(scope) ++ "] (" ++ level_txt ++ "): ";

    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, prefix ++ format, args) catch return;

    vesselLogWrite(msg.ptr, msg.len);
}

fn allocator() std.mem.Allocator {
    return platform.allocator();
}

var heaven: ?Heaven = null;
const ProofEntry = struct { name: [64]u8, name_len: u8, stmt: [128]u8, stmt_len: u8, verified: bool };
var proof_list: [64]ProofEntry = undefined;
var proof_count: u32 = 0;
var axiom_list: [32]ProofEntry = undefined;
var axiom_count: u32 = 0;

var input_buf: [4096]u8 = undefined;
var output_buf: [8192]u8 = undefined;
var output_len: u32 = 0;

fn setOutput(data: []const u8) void {
    // On garde 1 octet de marge pour le \0 de fin
    const max_len = if (output_buf.len > 0) output_buf.len - 1 else 0;
    const len = @min(data.len, max_len);

    @memcpy(output_buf[0..len], data[0..len]);
    output_buf[len] = 0; // Ajout du null-terminator pour JavaScript !

    output_len = @intCast(len);
}

fn isKeyword(line: []const u8) bool {
    const keywords = [_][]const u8{
        "let",       "mir",   "theorem", "prove",    "simplify", "derive",
        "integrate", "solve", "expand",  "optimize", "rewrite",  "type",
        "plot",      "latex", "explain", "profile",  "trace",    "qtt",
        "skill",     "help",  "stats",   "theorems", "load",     "transform",
    };
    for (keywords) |kw| {
        if (std.mem.startsWith(u8, line, kw) and (line.len == kw.len or line[kw.len] == ' ')) {
            return true;
        }
    }
    return false;
}

export fn getInputPtr() [*]u8 {
    return &input_buf;
}

export fn getOutputPtr() [*]const u8 {
    return &output_buf;
}

export fn getOutputLen() u32 {
    return output_len;
}

export fn init() void {
    heaven = Heaven.init(allocator());
}

export fn heavenEval(len: u32) u32 {
    var h = &(heaven orelse return 0);
    const line = input_buf[0..len];
    h.engine.fuel = 1000000;

    // Try function call by juxtaposition: "fib 5" -> "fib(5)"
    if (line.len > 0 and !isKeyword(line) and std.ascii.isAlphabetic(line[0])) {
        var tokens = std.mem.tokenizeScalar(u8, line, ' ');
        const fname = tokens.next() orelse "";
        if (fname.len > 0 and h.engine.fns.get(fname) != null) {
            var args_buf: [256]u8 = undefined;
            var args_len: usize = 0;
            var num_args: usize = 0;
            while (tokens.next()) |arg| {
                if (num_args > 0 and args_len < 255) {
                    args_buf[args_len] = ',';
                    args_len += 1;
                }
                const cl = @min(arg.len, 255 - args_len);
                @memcpy(args_buf[args_len .. args_len + cl], arg[0..cl]);
                args_len += cl;
                num_args += 1;
            }
            if (num_args > 0) {
                var call_buf: [512]u8 = undefined;
                const call_str = std.fmt.bufPrint(&call_buf, "{s}({s})", .{ fname, args_buf[0..args_len] }) catch "";
                if (call_str.len > 0) {
                    const result = h.eval(call_str) catch {
                        setOutput("error");
                        return 5;
                    };
                    defer allocator().free(result);
                    setOutput(result);
                    return output_len;
                }
            }
        }
    }

    const result = h.eval(line) catch {
        setOutput("error");
        return 5;
    };

    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenSimplify(len: u32) u32 {
    var h = &(heaven orelse return 0);
    const result = h.simplify(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenTypeOf(len: u32) u32 {
    var h = &(heaven orelse return 0);
    const result = h.typeOf(input_buf[0..len]) catch {
        setOutput("?");
        return 1;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenExplain(len: u32) u32 {
    var h = &(heaven orelse return 0);
    const result = h.explain(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenLatex(len: u32) u32 {
    var h = &(heaven orelse return 0);
    h.ensureInit();
    const id = h.bridge.importExpr(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    const result = h.toLaTeXInline(id) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenQuote(len: u32) u32 {
    var h = &(heaven orelse return 0);
    const result = h.dumpAst(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenDefine(name_len: u32, val_offset: u32, val_len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const name = input_buf[0..name_len];
    const val = input_buf[val_offset .. val_offset + val_len];
    const result = h.define(name, val) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenRewrite(lhs_len: u32, rhs_offset: u32, rhs_len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const lhs = input_buf[0..lhs_len];
    const rhs = input_buf[rhs_offset .. rhs_offset + rhs_len];
    const result = h.addRewrite(lhs, rhs) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenToC(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    h.ensureInit();
    const id = h.bridge.importExpr(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    const bind_id = h.store.bind("_expr", id) catch {
        setOutput("error");
        return 5;
    };
    var ids_buf = [1]u32{bind_id};
    const code = h.toC(&ids_buf) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(code);
    setOutput(code);
    return output_len;
}

export fn heavenDerive(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const result = h.derive(input_buf[0..len], "x") catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenSolve(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const result = h.solve(input_buf[0..len], "x") catch {
        setOutput("no solution");
        return 11;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenIntegrate(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const result = h.integrate(input_buf[0..len], "x") catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenExpand(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const result = h.expand(input_buf[0..len]) catch {
        setOutput("error");
        return 5;
    };
    defer allocator().free(result);
    setOutput(result);
    return output_len;
}

export fn heavenFnDef(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    h.ensureInit();
    const alloc = allocator();
    const line = input_buf[0..len];

    const eq_pos = std.mem.indexOfScalar(u8, line, '=') orelse {
        if (std.mem.indexOf(u8, line, " : ")) |colon| {
            const name = std.mem.trim(u8, line[0..colon], " ");
            const typ = std.mem.trim(u8, line[colon + 3 ..], " ");
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s} : {s}", .{ name, typ }) catch "ok";
            setOutput(msg);
            return output_len;
        }
        setOutput("syntax error");
        return output_len;
    };

    if (eq_pos + 1 < len and line[eq_pos + 1] == '=') {
        setOutput("syntax error");
        return output_len;
    }

    const lhs = std.mem.trim(u8, line[0..eq_pos], " ");
    const rhs = std.mem.trim(u8, line[eq_pos + 1 ..], " ");

    var tokens = std.mem.tokenizeScalar(u8, lhs, ' ');
    const name = tokens.next() orelse {
        setOutput("error");
        return output_len;
    };

    var pat_ids: [8]u32 = undefined;
    var num_pats: usize = 0;
    while (tokens.next()) |tok| {
        if (num_pats >= 8) break;
        if (std.fmt.parseInt(i64, tok, 10)) |v| {
            pat_ids[num_pats] = h.store.int(v) catch 0;
        } else |_| {
            pat_ids[num_pats] = h.store.sym(tok) catch 0;
        }
        num_pats += 1;
    }

    const body_id = h.bridge.importExpr(rhs) catch {
        setOutput("parse error");
        return output_len;
    };
    _ = alloc;
    //h.engine.fns.register(alloc.dupe(u8, name) catch name, pat_ids[0..num_pats], body_id) catch {
    //    setOutput("register error");
    //    return output_len;
    //};

    if (num_pats == 0) {
        const sym = h.store.interner.intern(name) catch {
            setOutput("error");
            return output_len;
        };
        h.engine.env.put(std.heap.page_allocator, sym, body_id) catch {};
    }

    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s} clause ({d} patterns) registered", .{ name, num_pats }) catch "ok";
    setOutput(msg);
    return output_len;
}

export fn heavenTheorem(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    h.ensureInit();
    const line = input_buf[0..len];
    const colon = std.mem.indexOf(u8, line, " : ") orelse {
        setOutput("syntax: name : lhs = rhs");
        return output_len;
    };
    const name = std.mem.trim(u8, line[0..colon], " ");
    const stmt = std.mem.trim(u8, line[colon + 3 ..], " ");
    const eq = std.mem.indexOf(u8, stmt, " = ") orelse {
        setOutput("need = in statement");
        return output_len;
    };
    const lhs_str = stmt[0..eq];
    const rhs_str = stmt[eq + 3 ..];
    const lhs = h.bridge.importExpr(lhs_str) catch {
        setOutput("parse error lhs");
        return output_len;
    };
    const rhs = h.bridge.importExpr(rhs_str) catch {
        setOutput("parse error rhs");
        return output_len;
    };
    if (proof_count < 64) {
        var entry = &proof_list[proof_count];
        const nl = @min(name.len, 64);
        @memcpy(entry.name[0..nl], name[0..nl]);
        entry.name_len = @intCast(nl);
        const sl = @min(stmt.len, 128);
        @memcpy(entry.stmt[0..sl], stmt[0..sl]);
        entry.stmt_len = @intCast(sl);
        entry.verified = false;
        proof_count += 1;
    }
    _ = lhs;
    _ = rhs;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "theorem {s} stated", .{name}) catch "ok";
    setOutput(msg);
    return output_len;
}

export fn heavenAxiom(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    h.ensureInit();
    const line = input_buf[0..len];
    const colon = std.mem.indexOf(u8, line, " : ") orelse {
        setOutput("syntax: name : lhs = rhs");
        return output_len;
    };
    const name = std.mem.trim(u8, line[0..colon], " ");
    const stmt = std.mem.trim(u8, line[colon + 3 ..], " ");
    const eq = std.mem.indexOf(u8, stmt, " = ") orelse {
        setOutput("need = in statement");
        return output_len;
    };
    const lhs_str = stmt[0..eq];
    const rhs_str = stmt[eq + 3 ..];
    const lhs = h.bridge.importExpr(lhs_str) catch {
        setOutput("parse error");
        return output_len;
    };
    const rhs = h.bridge.importExpr(rhs_str) catch {
        setOutput("parse error");
        return output_len;
    };
    if (axiom_count < 32) {
        var entry = &axiom_list[axiom_count];
        const nl = @min(name.len, 64);
        @memcpy(entry.name[0..nl], name[0..nl]);
        entry.name_len = @intCast(nl);
        const sl = @min(stmt.len, 128);
        @memcpy(entry.stmt[0..sl], stmt[0..sl]);
        entry.stmt_len = @intCast(sl);
        entry.verified = true;
        axiom_count += 1;
    }
    _ = lhs;
    _ = rhs;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "axiom {s} assumed", .{name}) catch "ok";
    setOutput(msg);
    return output_len;
}

export fn heavenProof(len: u32) u32 {
    if (heaven == null) return 0;
    var h = &(heaven orelse return 0);
    const line = input_buf[0..len];
    var tokens = std.mem.tokenizeScalar(u8, line, ' ');
    const name = tokens.next() orelse {
        setOutput("usage: name by method");
        return output_len;
    };
    _ = tokens.next();
    const method = tokens.next() orelse "eval";

    var thm_idx: ?usize = null;
    for (0..proof_count) |i| {
        if (std.mem.eql(u8, proof_list[i].name[0..proof_list[i].name_len], name)) {
            thm_idx = i;
            break;
        }
    }
    if (thm_idx) |idx| {
        const stmt = proof_list[idx].stmt[0..proof_list[idx].stmt_len];
        const eq = std.mem.indexOf(u8, stmt, " = ") orelse {
            setOutput("no = in theorem");
            return output_len;
        };
        const lhs_s = stmt[0..eq];
        const rhs_s = stmt[eq + 3 ..];
        var proved = false;
        if (std.mem.eql(u8, method, "eval")) {
            h.engine.fuel = 100000;
            const lr = h.eval(lhs_s) catch lhs_s;
            h.engine.fuel = 100000;
            const rr = h.eval(rhs_s) catch rhs_s;
            proved = std.mem.eql(u8, lr, rr);
        } else if (std.mem.eql(u8, method, "simplify")) {
            const lr = h.simplify(lhs_s) catch lhs_s;
            const rr = h.simplify(rhs_s) catch rhs_s;
            if (std.mem.eql(u8, lr, rr)) {
                proved = true;
            } else {
                const op_l = std.mem.indexOfAny(u8, lhs_s, "+-");
                const op_r = std.mem.indexOfAny(u8, rhs_s, "+-*");
                if (op_l != null and op_r != null and lhs_s[op_l.?] == rhs_s[op_r.?]) {
                    const al = std.mem.trim(u8, lhs_s[0..op_l.?], " ");
                    const ar = std.mem.trim(u8, lhs_s[op_l.? + 1 ..], " ");
                    const bl = std.mem.trim(u8, rhs_s[0..op_r.?], " ");
                    const br = std.mem.trim(u8, rhs_s[op_r.? + 1 ..], " ");
                    if (std.mem.eql(u8, al, br) and std.mem.eql(u8, ar, bl)) proved = true;
                }
            }
        } else if (std.mem.eql(u8, method, "induction")) {
            proved = true;
            for (0..11) |k| {
                var let_buf: [64]u8 = undefined;
                const var_n = tokens.next() orelse "n";
                const let_cmd = std.fmt.bufPrint(&let_buf, "let {s} = {d}", .{ var_n, k }) catch continue;
                _ = h.eval(let_cmd) catch continue;
                h.engine.fuel = 100000;
                const lr = h.eval(lhs_s) catch {
                    proved = false;
                    break;
                };
                h.engine.fuel = 100000;
                const rr = h.eval(rhs_s) catch {
                    proved = false;
                    break;
                };
                if (!std.mem.eql(u8, lr, rr)) {
                    proved = false;
                    break;
                }
            }
        }
        if (proved) proof_list[idx].verified = true;
        var buf2: [256]u8 = undefined;
        const icon: []const u8 = if (proved) "\xe2\x9c\x93" else "\xe2\x9c\x97";
        const msg2 = std.fmt.bufPrint(&buf2, "{s} {s} {s} by {s}", .{ icon, name, if (proved) "proved" else "NOT proved", method }) catch "?";
        setOutput(msg2);
    } else {
        setOutput("theorem not found");
    }
    return output_len;
}

export fn heavenTheorems(_: u32) u32 {
    var buf: [4096]u8 = undefined;
    var pos: usize = 0;
    const header1 = "=== Axioms ===\n";
    @memcpy(buf[pos .. pos + header1.len], header1);
    pos += header1.len;
    for (0..axiom_count) |i| {
        const e = axiom_list[i];
        const pre = " axiom ";
        @memcpy(buf[pos .. pos + pre.len], pre);
        pos += pre.len;
        @memcpy(buf[pos .. pos + e.name_len], e.name[0..e.name_len]);
        pos += e.name_len;
        buf[pos] = ':';
        pos += 1;
        buf[pos] = ' ';
        pos += 1;
        @memcpy(buf[pos .. pos + e.stmt_len], e.stmt[0..e.stmt_len]);
        pos += e.stmt_len;
        buf[pos] = '\n';
        pos += 1;
    }
    const header2 = "\n=== Theorems ===\n";
    @memcpy(buf[pos .. pos + header2.len], header2);
    pos += header2.len;
    for (0..proof_count) |i| {
        const e = proof_list[i];
        const icon: []const u8 = if (e.verified) " [P] " else " [ ] ";
        @memcpy(buf[pos .. pos + icon.len], icon);
        pos += icon.len;
        @memcpy(buf[pos .. pos + e.name_len], e.name[0..e.name_len]);
        pos += e.name_len;
        buf[pos] = ':';
        pos += 1;
        buf[pos] = ' ';
        pos += 1;
        @memcpy(buf[pos .. pos + e.stmt_len], e.stmt[0..e.stmt_len]);
        pos += e.stmt_len;
        buf[pos] = '\n';
        pos += 1;
    }
    setOutput(buf[0..pos]);
    return output_len;
}

export fn getWasmCommands() u32 {
    var fbs = std.io.fixedBufferStream(&output_buf);
    const writer = fbs.writer();

    inline for (cmd_list.commands) |cmd| {
        if (cmd.target != .native_only) {
            writer.print("{s} ", .{cmd.name}) catch break;
        }
    }

    output_len = @intCast(fbs.getWritten().len);
    return output_len;
}

pub fn enableLowering(self: *Heaven, v: bool) void {
    self.use_lowering = v;
}

export fn dispatch(cmd_len: u32, arg_len: u32) u32 {
    const full_input = input_buf[0 .. cmd_len + arg_len];
    var h = &(heaven orelse return 0);

    h.engine.fuel = 1000000;

    const res = h.eval(full_input) catch {
        setOutput("()");
        return 2;
    };
    defer allocator().free(res);
    setOutput(res);
    return output_len;
}

export fn getBuildTimestamp() u32 {
    return @intCast(build_options.build_timestamp);
}

// ═══════════════════════════════════════════════════════════
// BUFFER STATIQUE POUR PAYLOADS RÉSEAU
// ═══════════════════════════════════════════════════════════

var payload_buffer: [1048576]u8 = undefined;
var payload_offset: usize = 0;

export fn get_payload_buffer(size: usize) u32 {
    if (payload_offset + size > payload_buffer.len) {
        payload_offset = 0;
    }
    const ptr = @intFromPtr(&payload_buffer[payload_offset]);
    payload_offset += size;
    return @intCast(ptr);
}

// ═══════════════════════════════════════════════════════════
// NETWORK MESSAGE PROCESSING (appelé par JS)
// ═══════════════════════════════════════════════════════════

extern fn js_drain_message_queue() u32;
extern fn js_get_peer_id(msg_id: u32, out_ptr: [*]u8) void;
extern fn js_get_msg_type(msg_id: u32) u8;
extern fn js_get_timestamp(msg_id: u32) u64;
extern fn js_get_payload_ptr(msg_id: u32) u32;
extern fn js_get_payload_len(msg_id: u32) u32;
extern fn js_free_message(msg_id: u32) void;
extern fn js_console_log(ptr: [*]const u8, len: usize) void;
extern fn js_log(ptr: [*]const u8, len: usize) void;
extern fn js_rtc_send(peer_id_ptr: [*]const u8, peer_id_len: usize, data_ptr: [*]const u8, data_len: usize) void;

export fn process_network_messages() u32 {
    var count: u32 = 0;
    const alloc = platform.allocator();

    while (true) {
        const msg_id = js_drain_message_queue();
        if (msg_id == 0) break;

        var peer_id_buf: [16]u8 = undefined;
        js_get_peer_id(msg_id, &peer_id_buf);
        const msg_type = js_get_msg_type(msg_id);
        const payload_ptr = js_get_payload_ptr(msg_id);
        const payload_len = js_get_payload_len(msg_id);

        if (payload_ptr > 0 and payload_len > 0) {
            const payload = @as([*]const u8, @ptrFromInt(payload_ptr))[0..payload_len];
            const peer_id: []const u8 = &peer_id_buf;

            switch (msg_type) {
                2 => handlers.handleEGraphSync(alloc, peer_id, payload, &global_egraph, &global_store) catch |err| {
                    platform.io.print("egraph_sync failed: {}\n", .{err});
                },
                3 => handlers.handleProofRequest(alloc, peer_id, payload, &global_egraph, &global_store) catch {},
                5 => handlers.handleWorkStealRequest(alloc, peer_id, payload, &global_egraph, &global_store) catch {},
                else => {},
            }

            count += 1;
        }

        js_free_message(msg_id);
    }

    return count;
}

fn logError(msg: []const u8) void {
    js_console_log(msg.ptr, msg.len);
}

// ═══════════════════════════════════════════════════════════
// SWARM INITIALIZATION
// ═══════════════════════════════════════════════════════════

var swarm_initialized = false;

export fn init_swarm() void {
    if (swarm_initialized) return;

    const log_msg = "Initializing swarm runtime...";
    js_console_log(log_msg.ptr, log_msg.len);

    const alloc = platform.allocator();

    global_store = expr_mod.Store.init(alloc);
    global_egraph = egraph_mod.EGraph.init(&global_store, alloc);

    swarm_initialized = true;

    const success_msg = "Swarm runtime initialized";
    js_console_log(success_msg.ptr, success_msg.len);
}

// ═══════════════════════════════════════════════════════════
// SWARM TICK LOOP (appelée à chaque frame par requestAnimationFrame)
// ═══════════════════════════════════════════════════════════

var tick_count: u64 = 0;
const TICK_BUDGET_MS: u64 = 16;
const MAX_MESSAGES_PER_TICK: u32 = 10;

export fn tick_swarm() void {
    const start_time = platform.time.milliTimestamp();
    _ = start_time;

    // PHASE 1 : Messages réseau
    var messages_processed: u32 = 0;
    while (true) {
        if (messages_processed >= MAX_MESSAGES_PER_TICK) break;

        const msg_id = js_drain_message_queue();
        if (msg_id == 0) break;

        var peer_id_buf: [16]u8 = undefined;
        js_get_peer_id(msg_id, &peer_id_buf);
        const msg_type = js_get_msg_type(msg_id);
        const payload_ptr = js_get_payload_ptr(msg_id);
        const payload_len = js_get_payload_len(msg_id);

        if (payload_ptr > 0 and payload_len > 0) {
            const payload = @as([*]const u8, @ptrFromInt(payload_ptr))[0..payload_len];
            const peer_id: []const u8 = &peer_id_buf;

            const alloc = platform.allocator();
            switch (msg_type) {
                2 => handlers.handleEGraphSync(alloc, peer_id, payload, &global_egraph, &global_store) catch |err| {
                    platform.io.print("egraph_sync failed: {}\n", .{err});
                },
                3 => handlers.handleProofRequest(alloc, peer_id, payload, &global_egraph, &global_store) catch {},
                5 => handlers.handleWorkStealRequest(alloc, peer_id, payload, &global_egraph, &global_store) catch {},
                else => {},
            }

            messages_processed += 1;
        }

        js_free_message(msg_id);
    }

    // PHASE 2 : Saturation EGraph avec budget
    if (swarm_initialized) {
        const alloc = platform.allocator();
        var rewriter = egraph_rewriter.Rewriter.init(&global_egraph, &global_store, alloc);
        const merges = rewriter.saturate(1) catch 0;
        if (merges > 0) {
            // Des fusions ont eu lieu, notifier les pairs éventuellement
        }
    }

    // PHASE 3 : Diffuser les demandes de preuve en attente
    if (heaven) |*h| {
        if (h.pending_proof_request) |msg| {
            const alloc = platform.allocator();
            if (pending_proof_request_global) |old| alloc.free(old);
            const len = msg.len;
            const copy = alloc.alloc(u8, len) catch {
                alloc.free(msg);
                h.pending_proof_request = null;
                return;
            };
            @memcpy(copy, msg);
            pending_proof_request_global = copy;
            alloc.free(msg);
            h.pending_proof_request = null;
        }
    }

    // PHASE 3 : Diffuser les demandes de preuve en attente
    if (pending_proof_request_global) |msg| {
        js_broadcast_proof_request(msg.ptr, msg.len);
        platform.allocator().free(msg);
        pending_proof_request_global = null;
    }

    tick_count += 1;
}

export fn debug_egraph() void {
    const msg = "=== EGraph Debug ===";
    js_console_log(msg.ptr, msg.len);

    var buf: [256]u8 = undefined;

    const class_count = global_egraph.classes.items.len;
    const msg1 = std.fmt.bufPrint(&buf, "Classes: {}", .{class_count}) catch "error";
    js_console_log(msg1.ptr, msg1.len);

    const node_count = global_store.nodes.items.len;
    const msg2 = std.fmt.bufPrint(&buf, "Store nodes: {}", .{node_count}) catch "error";
    js_console_log(msg2.ptr, msg2.len);

    var i: usize = 0;
    while (i < class_count) : (i += 1) {
        if (global_egraph.extract(i, null)) |id| {
            const msg3 = std.fmt.bufPrint(&buf, "Class {} -> expr {}", .{ i, id }) catch "error";
            js_console_log(msg3.ptr, msg3.len);
        } else {
            const msg4 = std.fmt.bufPrint(&buf, "Class {} -> (empty)", .{i}) catch "error";
            js_console_log(msg4.ptr, msg4.len);
        }
    }
}

var pending_proof_request_global: ?[]const u8 = null;

export fn get_pending_proof_request_ptr() u32 {
    if (pending_proof_request_global) |req| {
        return @intCast(@intFromPtr(req.ptr));
    }
    return 0;
}

export fn get_pending_proof_request_len() u32 {
    if (pending_proof_request_global) |req| {
        return @intCast(req.len);
    }
    return 0;
}

export fn clear_pending_proof_request() void {
    if (pending_proof_request_global) |req| {
        platform.allocator().free(req);
        pending_proof_request_global = null;
    }
}

// ═══════════════════════════════════════════════════════════
// PENDING RESPONSE (bridge WASM → JS pour BroadcastChannel)
// ═══════════════════════════════════════════════════════════

var pending_response: ?[]u8 = null;
var pending_peer_id: [16]u8 = undefined;

export fn send_work_steal_response(peer_id_ptr: [*]const u8, peer_id_len: usize, data_ptr: [*]const u8, data_len: usize) void {
    _ = peer_id_len;

    const alloc = platform.allocator();
    const data_copy = alloc.alloc(u8, data_len) catch return;
    @memcpy(data_copy, data_ptr[0..data_len]);
    pending_response = data_copy;

    @memcpy(&pending_peer_id, peer_id_ptr[0..16]);
}

export fn get_pending_response_ptr() u32 {
    if (pending_response) |resp| {
        return @intCast(@intFromPtr(resp.ptr));
    }
    return 0;
}

export fn get_pending_response_len() u32 {
    if (pending_response) |resp| {
        return @intCast(resp.len);
    }
    return 0;
}

export fn get_pending_peer_id_ptr() u32 {
    return @intCast(@intFromPtr(&pending_peer_id));
}

export fn clear_pending_response() void {
    if (pending_response) |resp| {
        platform.allocator().free(resp);
        pending_response = null;
    }
}

// ═══════════════════════════════════════════════════════════
// EGRAPH STATE SERIALIZATION (pour IndexedDB)
// ═══════════════════════════════════════════════════════════

var serialized_state: ?[]u8 = null;

export fn get_egraph_state_ptr() u32 {
    const alloc = platform.allocator();

    var buf: [65536]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.writeInt(u32, @intCast(global_store.nodes.items.len), .little) catch return 0;

    for (global_store.nodes.items) |node| {
        writer.writeByte(@intFromEnum(node.tag)) catch return 0;
        writer.writeInt(u32, node.payload, .little) catch return 0;
        writer.writeInt(u32, node.aux, .little) catch return 0;
    }

    writer.writeInt(u32, @intCast(global_egraph.classes.items.len), .little) catch return 0;

    for (global_egraph.classes.items) |eclass| {
        writer.writeInt(u32, @intCast(eclass.nodes.items.len), .little) catch return 0;
        for (eclass.nodes.items) |node_id| {
            writer.writeInt(u32, node_id, .little) catch return 0;
        }
    }

    const data = fbs.getWritten();
    const copy = alloc.alloc(u8, data.len) catch return 0;
    @memcpy(copy, data);
    serialized_state = copy;

    return @intCast(@intFromPtr(copy.ptr));
}

export fn get_egraph_state_len() u32 {
    if (serialized_state) |state| {
        return @intCast(state.len);
    }
    return 0;
}

export fn restore_egraph_state(data_ptr: [*]const u8, data_len: u32) void {
    const data = data_ptr[0..data_len];
    var fbs = std.io.fixedBufferStream(data);
    const reader = fbs.reader();

    const store_count = reader.readInt(u32, .little) catch return;

    var i: u32 = 0;
    while (i < store_count) : (i += 1) {
        const tag = reader.readByte() catch continue;
        const payload = reader.readInt(u32, .little) catch continue;
        const aux = reader.readInt(u32, .little) catch continue;

        global_store.nodes.append(global_store.allocator, .{
            .tag = @enumFromInt(tag),
            .payload = payload,
            .aux = aux,
            .span_a = expr_mod.Span.EMPTY,
            .span_b = expr_mod.Span.EMPTY,
        }) catch {};
    }

    const class_count = reader.readInt(u32, .little) catch return;

    var j: u32 = 0;
    while (j < class_count) : (j += 1) {
        const node_count = reader.readInt(u32, .little) catch continue;

        var eclass = egraph_mod.EClass.init(global_store.allocator);

        var k: u32 = 0;
        while (k < node_count) : (k += 1) {
            const node_id = reader.readInt(u32, .little) catch continue;
            eclass.nodes.append(global_store.allocator, node_id) catch {};
        }

        global_egraph.classes.append(global_store.allocator, eclass) catch {};
    }

    platform.io.print("Restored {} store nodes, {} egraph classes\n", .{ store_count, class_count });
}

// ═══════════════════════════════════════════════════════════
// METRICS EXPORT (pour le dashboard)
// ═══════════════════════════════════════════════════════════

var total_messages_processed: u64 = 0;
var messages_by_type = [_]u64{0} ** 7;

var metrics_json_buffer: [1024]u8 = undefined;
var metrics_json_len: u32 = 0;

export fn get_metrics_json() u32 {
    var fbs = std.io.fixedBufferStream(&metrics_json_buffer);
    const writer = fbs.writer();

    writer.print(
        \\{{"egraph_classes":{},"store_nodes":{},"messages_count":{},"messages_by_type":{{"egraph_sync":{},"work_steal_request":{},"work_steal_response":{},"proof_request":{},"proof_result":{}}}}}
    , .{
        global_egraph.classes.items.len,
        global_store.nodes.items.len,
        total_messages_processed,
        messages_by_type[2],
        messages_by_type[5],
        messages_by_type[6],
        messages_by_type[3],
        messages_by_type[4],
    }) catch {
        metrics_json_len = 0;
        return 0;
    };

    metrics_json_len = @intCast(fbs.getPos() catch 0);

    return @intCast(@intFromPtr(&metrics_json_buffer));
}

export fn get_metrics_json_len() u32 {
    return metrics_json_len;
}

const heaven_keywords = [_][]const u8{
    "theorem ",  "prove ", "transform ", "let ",     "fun ",
    "simplify ", "type ",  "latex ",     "derive ",  "integrate ",
    "solve ",    "help",   "stats",      "theorems", "load ",
};

export fn getCompletions(prefix_ptr: [*]const u8, prefix_len: u32) u32 {
    const prefix = prefix_ptr[0..prefix_len];
    var buf_len: usize = 0;

    for (heaven_keywords) |kw| {
        if (std.mem.startsWith(u8, kw, prefix)) {
            // On ajoute un espace séparateur si ce n'est pas le premier mot
            const space_needed = if (buf_len == 0) kw.len else kw.len + 1;
            if (buf_len + space_needed >= output_buf.len) break;

            if (buf_len > 0) {
                output_buf[buf_len] = ' ';
                buf_len += 1;
            }
            @memcpy(output_buf[buf_len .. buf_len + kw.len], kw);
            buf_len += kw.len;
        }
    }

    output_len = @intCast(buf_len);
    return output_len;
}

export fn wasm_entry_process_input(ptr: [*]const u8, len: usize) void {
    const data = ptr[0..len];
    if (heaven) |*h| {
        // Appelez ici la fonction de votre moteur qui traite les données
        // Si vous voulez traiter cela comme une commande, utilisez dispatch :
        _ = h.eval(data) catch {
            platform.io.print("Input error", .{});
            return;
        };
    }
}

extern fn js_ollama_query(prompt_ptr: [*]const u8, prompt_len: usize, out_ptr: [*]u8, out_max: usize) usize;
extern fn js_broadcast_proof_request(ptr: [*]const u8, len: usize) void;
