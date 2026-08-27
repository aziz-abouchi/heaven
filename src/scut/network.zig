const std = @import("std");
const protocol = @import("protocol");
const routing = @import("routing.zig");
const task_lib = @import("task");
const matrix_lib = @import("matrix_lib");
const egraph_mod = @import("egraph");
const prolog = @import("../runtime/prolog.zig");
const dispatch = @import("../core/dispatch.zig");
const platform = @import("platform");

pub const Peer = struct {
    address: std.net.Address,
    last_seen: i64,
    last_sync: i64,
    view_version: u64,
    seen_atoms: u32,
    failure_count: u8,
};

pub const IncomingWithAddr = struct {
    data: protocol.Incoming,
    sender: std.net.Address,
    len: usize,
};

pub var self_origin: u64 = 0;
var is_merging: bool = false;

pub var known_peers = std.ArrayListUnmanaged(Peer){};
var socket: ?platform.posix.socket_t = null;

pub var current_port: u16 = 0;

const MAX_SEEN = 4096;

var seen_msgs: [MAX_SEEN]u64 = undefined;
var seen_idx: usize = 0;

fn alreadySeen(id: u64) bool {
    for (seen_msgs) |v| {
        if (v == id) return true;
    }
    return false;
}

fn markSeen(id: u64) void {
    seen_msgs[seen_idx % MAX_SEEN] = id;
    seen_idx += 1;
}

// --------------------------------------------------
// INIT
// --------------------------------------------------

pub fn init(port: u16) !void {
    socket = try platform.posix.socket(platform.posix.AF.INET6, platform.posix.SOCK.DGRAM, 0);

    const addr = try std.net.Address.parseIp6("::", port);
    try platform.posix.bind(socket.?, &addr.any, addr.getOsSockLen());

    const flags = try platform.posix.fcntl(socket.?, platform.posix.F.GETFL, 0);
    _ = try platform.posix.fcntl(socket.?, platform.posix.F.SETFL, flags | @as(u32, @bitCast(platform.posix.O{ .NONBLOCK = true })));

    current_port = port;

    // platform.dbg("[NET] Listening on {d}\n", .{port});
}

// --------------------------------------------------
// PEERS
// --------------------------------------------------

pub fn updatePeer(allocator: std.mem.Allocator, addr: std.net.Address) !void {
    const now = std.time.timestamp();
    for (known_peers.items) |*p| {
        // Comparaison robuste : Famille + Port + Données d'adresse
        if (p.address.any.family == addr.any.family and
            p.address.getPort() == addr.getPort())
        {

            // Pour IPv4/IPv6, on compare les octets de l'adresse
            const is_same = switch (addr.any.family) {
                platform.posix.AF.INET => std.mem.eql(u8, std.mem.asBytes(&p.address.in.sa.addr), std.mem.asBytes(&addr.in.sa.addr)),
                platform.posix.AF.INET6 => std.mem.eql(u8, std.mem.asBytes(&p.address.in6.sa.addr), std.mem.asBytes(&addr.in6.sa.addr)),
                else => false,
            };

            if (is_same) {
                p.last_seen = now;
                return;
            }
        }
    }

    try known_peers.append(allocator, .{
        .address = addr,
        .last_seen = now,
        .last_sync = 0,
        .view_version = 0,
        .seen_atoms = 0,
        .failure_count = 0,
    });
}

// --------------------------------------------------
// LOW LEVEL SEND
// --------------------------------------------------

fn sendPacket(addr: std.net.Address, header: protocol.Header, payload: []const u8) !void {
    const sock = socket orelse return error.NotInit;

    var buf: [1500]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    // Écriture forcée en Big-Endian
    try writer.writeInt(u32, header.magic, .big);
    try writer.writeInt(u8, header.version, .big);
    try writer.writeInt(u8, @intFromEnum(header.kind), .big);
    try writer.writeInt(u8, header.ttl, .big);
    try writer.writeInt(u32, header.length, .big);
    try writer.writeInt(u64, header.msg_id, .big);
    try writer.writeInt(u64, header.from, .big);
    try writer.writeInt(u32, header.seq, .big);
    try writer.writeInt(i64, header.timestamp, .big);
    try writer.writeInt(u32, header.checksum, .big);

    // Écriture du payload
    try writer.writeAll(payload);

    // platform.dbg("[SEND] Magic: {X:0>8} | Version: {d} | Kind: {any}\n", .{ header.magic, header.version, header.kind });

    _ = try platform.posix.sendto(sock, buf[0..fbs.pos], 0, &addr.any, addr.getOsSockLen());
}

// --------------------------------------------------
// SEND API
// --------------------------------------------------

pub fn sendTask(addr: std.net.Address, task: task_lib.Task) !void {
    const payload = std.mem.asBytes(&task);

    const header = protocol.Header{
        .magic = protocol.MAGIC,
        .version = protocol.VERSION,
        .kind = .ExecuteTask,
        .ttl = 4,
        .length = @intCast(payload.len),
        .msg_id = std.crypto.random.int(u64),
        .from = 0,
        .seq = 0,
        .timestamp = std.time.timestamp(),
        .checksum = protocol.computeChecksum(payload),
    };

    try sendPacket(addr, header, payload);
}

pub fn sendTaskToAll(task: task_lib.Task) !void {
    for (known_peers.items) |p| {
        try sendTask(p.address, task);
    }
}

pub fn sendRPC(addr: std.net.Address, sym: []const u8) !void {
    const header = protocol.Header{
        .magic = protocol.MAGIC,
        .version = protocol.VERSION,
        .kind = .RPC,
        .ttl = 4,
        .length = @intCast(sym.len),
        .msg_id = std.crypto.random.int(u64),
        .from = 0,
        .seq = 0,
        .timestamp = std.time.timestamp(),
        .checksum = protocol.computeChecksum(sym),
    };

    try sendPacket(addr, header, sym);
}

// --------------------------------------------------
// RECEIVE
// --------------------------------------------------

fn parsePacket(buf: []u8, n: usize) ?struct { header: protocol.Header, payload: []u8 } {
    if (n < @sizeOf(protocol.Header)) return null;

    var stream = std.io.fixedBufferStream(buf[0..n]);
    const reader = stream.reader();

    const h = protocol.Header{
        .magic = reader.readInt(u32, .big) catch return null,
        .version = reader.readInt(u8, .big) catch return null,
        .kind = @enumFromInt(reader.readInt(u8, .big) catch return null),
        .ttl = reader.readInt(u8, .big) catch return null,
        .length = reader.readInt(u32, .big) catch return null,
        .msg_id = reader.readInt(u64, .big) catch return null,
        .from = reader.readInt(u64, .big) catch return null,
        .seq = reader.readInt(u32, .big) catch return null,
        .timestamp = reader.readInt(i64, .big) catch return null,
        .checksum = reader.readInt(u32, .big) catch return null,
    };

    if (!protocol.verifyHeader(&h)) return null;

    const header_size = @sizeOf(protocol.Header);
    if (header_size + h.length > n) {
        // platform.dbg("[NET] ERREUR: Payload trop grand ({d} > {d})\n", .{ h.length, n - header_size });
        return null;
    }
    const payload = buf[header_size .. header_size + h.length];

    if (protocol.computeChecksum(payload) != h.checksum) return null;

    return .{ .header = h, .payload = payload };
}

// On passe le reader déjà synchronisé pour éviter tout décalage
fn parseHeader(reader: anytype) !?protocol.Header {
    const magic = try reader.readInt(u32, .big);
    const version = try reader.readInt(u8, .big);
    const kind_raw = try reader.readInt(u8, .big);
    const kind = std.meta.intToEnum(protocol.MsgKind, kind_raw) catch {
        // platform.dbg("[NET] ERREUR: Kind inconnu {any}\n", .{err});
        return null; // On abandonne le paquet proprement sans crash
    };
    const ttl = try reader.readInt(u8, .big);
    const length = try reader.readInt(u32, .big);

    // platform.debug.print("DEBUG: Magic:{X} Ver:{d} Kind:{d} TTL:{d} Len:{d}\n", .{ magic, version, kind_raw, ttl, length });

    return protocol.Header{
        .magic = magic,
        .version = version,
        .kind = kind,
        .ttl = ttl,
        .length = length,
        .msg_id = try reader.readInt(u64, .big),
        .from = try reader.readInt(u64, .big),
        .seq = try reader.readInt(u32, .big),
        .timestamp = try reader.readInt(i64, .big),
        .checksum = try reader.readInt(u32, .big),
    };
}

pub fn listen(allocator: std.mem.Allocator) !?IncomingWithAddr {
    const sock = socket orelse return null;
    var buf: [4096]u8 = undefined;
    var addr_raw: platform.posix.sockaddr = undefined;
    var len: platform.posix.socklen_t = @sizeOf(platform.posix.sockaddr);

    const n = platform.posix.recvfrom(sock, &buf, 0, &addr_raw, &len) catch return null;

    // Si le paquet est trop court pour contenir un header, on ignore silencieusement
    if (n < @sizeOf(protocol.Header)) {
        // Optionnel : logger uniquement si c'est un ping/discovery
        // platform.dbg("[HEX DUMP] {d}, {any}\n", .{ n, buf[0..n] });
        return null;
    }

    if (n == 6) {
        // C'est un paquet de présence, on traite l'émetteur
        // Pas besoin de parser tout le header
        // platform.dbg("[HEX DUMP] {d}, {any}\n", .{ n, buf[0..n] });
        // C'est un Ping, on lit juste le début pour valider le Magic
        const magic = std.mem.readInt(u32, buf[0..4], .big);
        if (magic == protocol.MAGIC) {
            // platform.dbg("[NET] MAGIC lu comme (Big-Endian): {X:0>8}, buffer:{any}\n", .{ magic, buf[0..n] });
            updatePeer(allocator, std.net.Address{ .any = addr_raw }) catch {};
        }
        return null;
    }

    if (n >= @sizeOf(protocol.Header)) {

        // Création du stream pour une lecture continue et propre
        var stream = std.io.fixedBufferStream(buf[0..n]);
        const reader = stream.reader();

        // 1. Lecture et DIAGNOSTIC du MAGIC
        //const magic = try reader.readInt(u32, .big);
        const raw_magic = buf[0..4];
        // On lit en Big-Endian explicite (les octets arrivent dans l'ordre 0B 0B CA FE)
        const magic = std.mem.readInt(u32, raw_magic, .big);

        // platform.dbg("[NET] MAGIC lu comme (Big-Endian): {X:0>8}, buffer:{any}\n", .{ magic, buf[0..4] });
        // platform.dbg("[HEX DUMP] {d}, {any}\n", .{ n, buf[0..n] });

        // 2. Lecture du reste du Header (le reader est déjà positionné juste après le magic)
        const h_opt = try parseHeader(reader);
        const h = h_opt orelse {
            // platform.dbg("[NET] Header invalide ou paquet ignoré\n", .{});
            return null;
        };

        // 3. Diagnostics sur le paquet reçu
        // platform.dbg("[NET] Reçu {d} octets | Kind: {any} | Len: {d}\n", .{ n, h.kind, h.length });
        // platform.dbg("[RECV] Magic: {X:0>8} | Version: {d} | Kind: {any}\n", .{ h.magic, h.version, h.kind });

        if (magic != protocol.MAGIC) {
            // platform.dbg("[NET] Échec ! Attendu {X:0>8}\n", .{protocol.MAGIC});
            return null;
        }

        if (!protocol.verifyHeader(&h)) return null;

        const header_size = @sizeOf(protocol.Header);
        if (header_size + h.length > n) {
            // platform.dbg("[NET] ERREUR: Payload trop grand ({d} > {d})\n", .{ h.length, n - header_size });
            return null;
        }
        const payload = buf[header_size .. header_size + h.length];

        if (protocol.computeChecksum(payload) != h.checksum) {
            // platform.dbg("[NET] Erreur checksum !\n", .{});
            return null;
        }

        updatePeer(allocator, std.net.Address{ .any = addr_raw }) catch {};

        if (parsePacket(&buf, n)) |pkt| {
            if (pkt.header.from == self_origin) {
                return null;
            }
            if (alreadySeen(pkt.header.msg_id)) {
                return null;
            }
            markSeen(pkt.header.msg_id);

            const incoming_data = switch (pkt.header.kind) {
                .ExecuteTask => protocol.Incoming{ .Task = std.mem.bytesToValue(task_lib.Task, pkt.payload) },
                .RPC => protocol.Incoming{ .Signal = try allocator.dupe(u8, pkt.payload) },
                .MatrixSync => protocol.Incoming{ .MatrixSync = try allocator.dupe(u8, pkt.payload) },
                else => protocol.Incoming{ .RawCode = try allocator.dupe(u8, pkt.payload) },
            };

            return IncomingWithAddr{
                .data = incoming_data,
                .sender = std.net.Address{ .any = addr_raw },
                .len = n,
            };
        }
    }
    return null;
}

// --------------------------------------------------
// DEBUG
// --------------------------------------------------

fn printAddr(addr: std.net.Address) void {
    const port = addr.getPort();
    if (addr.any.family == platform.posix.AF.INET6) {
        platform.dbg("[::1]:{d}", .{port});
    } else {
        platform.debug.print("127.0.0.1:{d}", .{port});
    }
}

pub fn listPeers() void {
    for (known_peers.items) |p| {
        platform.debug.print("Peer: {any}\n", .{p.address});
    }
}

pub fn sendTo(addr: std.net.Address, payload: []const u8) !void {
    const header = protocol.Header{
        .magic = protocol.MAGIC,
        .version = protocol.VERSION,
        .kind = .MatrixSync,
        .ttl = 4,
        .length = @intCast(payload.len),
        .msg_id = std.crypto.random.int(u64),
        .from = 0,
        .seq = 0,
        .timestamp = std.time.timestamp(),
        .checksum = protocol.computeChecksum(payload),
    };

    try sendPacket(addr, header, payload);
}

pub fn broadcast(matrix: anytype, origin: u64) !void {
    var buf: [4096]u8 = undefined;

    const size = matrix.serializeMatrixDelta(&buf, 0);
    if (size == 0) return;

    const msg_id = std.crypto.random.int(u64);

    for (known_peers.items) |p| {
        const header = protocol.Header{
            .magic = protocol.MAGIC,
            .version = protocol.VERSION,
            .kind = .MatrixSync,
            .ttl = 2,
            .length = @intCast(size),
            .msg_id = msg_id,
            .from = origin,
            .seq = 0,
            .timestamp = std.time.timestamp(),
            .checksum = protocol.computeChecksum(buf[0..size]),
        };

        sendPacket(p.address, header, buf[0..size]) catch {};
    }
}

pub fn broadcastPresence() !void {
    var buf: [1500]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    try writer.writeInt(u32, protocol.MAGIC, .big);
    try writer.writeInt(u8, protocol.VERSION, .big);
    try writer.writeInt(u8, @intFromEnum(protocol.MsgKind.RPC), .big);

    const packet_size = fbs.pos; // fbs.pos contient la taille réelle écrite

    const localhost = try std.net.Address.parseIp6("::1", 0);
    var target_port: u16 = 8078;
    while (target_port <= 8090) : (target_port += 1) {
        if (target_port == current_port) continue;
        var addr = localhost;
        addr.in6.sa.port = @byteSwap(target_port);

        // Utilisez packet_size au lieu de @sizeOf(protocol.Header)
        _ = platform.posix.sendto(socket.?, buf[0..packet_size], 0, &addr.any, addr.getOsSockLen()) catch continue;
    }
}

pub fn handleIncoming(allocator: std.mem.Allocator, matrix: *matrix_lib.Matrix, egraph: *egraph_mod.EGraph, incoming: protocol.Incoming, src_addr: std.net.Address) !void {
    const now = std.time.timestamp();

    // 1. On trouve (ou crée) le pair et on marque qu'on vient de lui parler
    for (known_peers.items) |*p| {
        if (p.address.getPort() == src_addr.getPort()) {
            p.last_seen = now;
            break;
        }
    }

    switch (incoming) {
        .Signal => {
            // platform.dbg("[NET] Sync demandée par ", .{});
            printAddr(src_addr);
            // platform.debug.print("\n", .{});

            var sync_buf: [4096]u8 = undefined;
            const size = matrix.serializeMatrixDelta(&sync_buf, 0);
            if (size > 0) try sendTo(src_addr, sync_buf[0..size]);
        },
        .MatrixSync => |data| {
            const swarm_proto = @import("swarm/protocol_swarm.zig");
            const swarm_rt = @import("../runtime/swarm/runtime.zig");
            // Detect SwarmTask/Result by bytesToValue and check magic field
            if (data.len == @sizeOf(swarm_proto.SwarmTask)) {
                const task = std.mem.bytesToValue(swarm_proto.SwarmTask, data[0..@sizeOf(swarm_proto.SwarmTask)]);
                if (task.magic == 0x5441534B) {
                    // platform.dbg("[SWARM] Task reçue: {s}\n", .{task.getExpr()});
                    if (swarm_rt.global_inbox) |inbox| {
                        inbox.append(allocator, task) catch {};
                    }
                    return;
                }
            }
            if (data.len == @sizeOf(swarm_proto.SwarmResult)) {
                const result = std.mem.bytesToValue(swarm_proto.SwarmResult, data[0..@sizeOf(swarm_proto.SwarmResult)]);
                if (result.magic == 0x52455355) {
                    // platform.dbg("[SWARM] Résultat: {s} (de Bob:{d})\n", .{ result.getResult(), result.solver_port });
                    if (swarm_rt.global_results) |results| {
                        results.append(allocator, result) catch {};
                    }
                    return;
                }
            }
            // Else: regular MatrixSync
            if (false) {
                // TASK
                // platform.dbg("[SWARM] Task reçue\n", .{});
                if (swarm_rt.global_inbox) |inbox| {
                    const task = std.mem.bytesToValue(swarm_proto.SwarmTask, data[0..@sizeOf(swarm_proto.SwarmTask)]);
                    inbox.append(allocator, task) catch {};
                }
            } else {
                if (data.len > 100) {
                    // platform.dbg("[NET] Fusion massive reçue ({d} octets)\n", .{data.len});
                }
                const node = try allocator.create(dispatch.CommandNode);
                node.* = .{
                    .data = .{ .MatrixSync = data },
                    .next = null,
                };
                dispatch.command_queue.put(node);
            }
        },
        .EGraphUnion => |data| {
            const union_payload = data;

            // Accès direct au champ du Swarm
            const class_a = egraph.hashcons.get(union_payload.hash_a) orelse return error.UnknownHash;
            const class_b = egraph.hashcons.get(union_payload.hash_b) orelse return error.UnknownHash;

            _ = egraph.uf.merge(class_a, class_b);

            // platform.dbg("[SWARM] Union fusionnée: {X} == {X}\n", .{ union_payload.hash_a, union_payload.hash_b });
        },
        else => {},
    }
}

pub const SwarmManager = struct {
    allocator: std.mem.Allocator,
    matrix: *matrix_lib.Matrix,
    egraph: *egraph_mod.EGraph,
    // Table de tracking pour savoir qui a demandé quoi (msg_id -> sender_address)
    pending_queries: std.AutoHashMap(u64, std.net.Address),

    pub fn init(allocator: std.mem.Allocator, matrix: *matrix_lib.Matrix, egraph: *egraph_mod.EGraph) SwarmManager {
        return .{
            .allocator = allocator,
            .matrix = matrix,
            .egraph = egraph,
            .pending_queries = std.AutoHashMap(u64, std.net.Address).init(allocator),
        };
    }

    /// Un Bob appelle cette fonction s'il ne peut pas résoudre un prédicat localement
    pub fn broadcastQueryToSwarm(self: *SwarmManager, pred_query: []const u8) !void {
        const msg_id = std.crypto.random.int(u64);

        const header = protocol.Header{
            .magic = protocol.MAGIC,
            .version = protocol.VERSION,
            .kind = .SwarmQueryProlog,
            .ttl = 2, // Limite la propagation à deux rebonds locaux
            .length = @intCast(pred_query.len),
            .msg_id = msg_id,
            .from = self.matrix.self_origin,
            .seq = 0,
            .timestamp = std.time.timestamp(),
            .checksum = protocol.computeChecksum(pred_query),
        };

        // Broadcast UDP sur tous les ports actifs découverts (known_peers)
        for (known_peers.items) |p| {
            try sendPacket(p.address, header, pred_query);
        }
    }

    /// Traitement des paquets spécifiques à l'essaim
    pub fn processSwarmMessage(self: *SwarmManager, header: protocol.Header, payload: []const u8, src_addr: std.net.Address) !void {
        switch (header.kind) {
            .SwarmQueryProlog => {
                // platform.dbg("[SWARM] Requête reçue de {any}: :ask {s}\n", .{ src_addr, payload });

                // 1. Exécuter le solveur Prolog local sur le payload
                // (Ici on simule la réponse, à connecter à ton prolog.solve())
                var response_buf = std.ArrayList(u8).init(self.allocator);
                defer response_buf.deinit();

                // Si notre Prolog trouve une solution, on la renvoie directement à l'émetteur
                const reply_header = protocol.Header{
                    .magic = protocol.MAGIC,
                    .version = protocol.VERSION,
                    .kind = .SwarmReplyProlog,
                    .ttl = 1,
                    .length = @intCast(payload.len), // Taille de la réponse unifiée
                    .msg_id = header.msg_id, // On garde le même ID pour le tracking
                    .from = self.matrix.self_origin,
                    .seq = 0,
                    .timestamp = std.time.timestamp(),
                    .checksum = protocol.computeChecksum(payload),
                };

                try sendPacket(src_addr, reply_header, "X = 42 (Swarm Verified)");
            },

            .SwarmReplyProlog => {
                // platform.dbg("[SWARM] Résolution reçue de l'essaim: {s}\n", .{payload});
                // Injecter le résultat sous forme de fait dans la Matrix locale
                // pour que le shell ou l'E-graph puisse consommer la donnée immédiate.
                const cmd_node = try self.allocator.create(dispatch.CommandNode);
                cmd_node.* = .{
                    .data = .{ .AddSymbol = try self.allocator.dupe(u8, payload) },
                    .next = null,
                };
                dispatch.command_queue.put(cmd_node);
            },

            .SwarmShareRule => |data| { // Renommez selon votre MsgKind
                const union_payload = std.mem.bytesToValue(protocol.EGraphUnionPayload, data);

                // 1. Récupération des classes dans votre eGraph local
                // Vous devez avoir accès à votre instance d'eGraph ici.
                const class_a = self.egraph.hashcons.get(union_payload.hash_a) orelse return error.UnknownHash;
                const class_b = self.egraph.hashcons.get(union_payload.hash_b) orelse return error.UnknownHash;

                // 2. Union des deux classes
                _ = self.egraph.uf.merge(class_a, class_b);

                // 3. Trigger de saturation (pour que l'eGraph propage les nouvelles égalités)
                self.egraph.rebuild();

                // platform.dbg("[SWARM] Fusion des classes {X} et {X}\n", .{ union_payload.hash_a, union_payload.hash_b });
            },
            else => {},
        }
    }
};
