const std = @import("std");
const platform = @import("platform");
const matrix_lib = @import("matrix_lib");
const egraph_mod = @import("egraph");
const codec = @import("codec");
const network_queue = @import("queue");
const react_lib = @import("../core/react.zig");
const network = @import("../scut/network.zig");

pub fn run(
    m: *matrix_lib.Matrix,
    re: *react_lib.ReactionEngine,
    a: std.mem.Allocator,
    lp_id: *matrix_lib.BobId,
    queue: *network_queue.MessageQueue,
    egraph: *egraph_mod.EGraph,
    ex: *const std.atomic.Value(bool),
) !void {

                var last_ping: i64 = 0;
                while (!ex.load(.acquire)) {
                    // 1. TRAITEMENT : Vidage de la file réseau (Consommateur)
                    while (queue.pop()) |msg| {
                        platform.dbg("[NET] Reçu {d} octets: {any}\n", .{ msg.payload.len, msg.payload[0..@min(msg.payload.len, 8)] });
                        // 1. Décodage du binaire vers le type attendu
                        const incoming = codec.decode(msg.payload) catch {
                            platform.dbg("[NET] Échec décodage message\n", .{});
                            a.free(msg.payload);
                            continue;
                        };
                        // Traitement métier du message
                        const addr = std.net.Address{ .in = std.net.Address.initIp4([4]u8{ 0, 0, 0, 0 }, 0).in };
                        network.handleIncoming(a, m, egraph, incoming, addr) catch |err| {
                            platform.dbg("[NET] Handle error: {any}\n", .{err});
                        };
                        // Libération de la mémoire allouée par le 'push'
                        a.free(msg.payload);
                    }

                    // 2. RÉCEPTION : Écoute du réseau et remplissage de la file (Producteur)
                    if (try network.listen(a)) |incoming| {
                        // Log pour confirmer la réception
                        platform.dbg("[NET] Traitement de {d} octets\n", .{incoming.len});

                        // Accès direct au buffer selon le type contenu dans l'union
                        const raw_slice: []u8 = switch (incoming.data) {
                            .RawCode => |bytes| bytes,
                            .MatrixSync => |bytes| bytes,
                            .Signal => |bytes| bytes,
                            // On crée une variable mutable pour pouvoir en prendre l'adresse en tant que []u8
                            .Task => |*t| @constCast(std.mem.asBytes(t)),
                            else => &[_]u8{},
                        };

                        // Maintenant utilisez raw_slice, qui est déjà borné à la taille réelle
                        if (raw_slice.len > 0) {
                            _ = try codec.decode(raw_slice);
                        }

                        // On duplique le payload pour que la file en soit propriétaire
                        const incoming_bytes = std.mem.asBytes(&incoming.data);
                        const actual_data = incoming_bytes[0..incoming_bytes.len];
                        const payload = try a.dupe(u8, actual_data);

                        try queue.push(.{
                            .msg_type = .egraph_sync,
                            .peer_id = ("peer" ++ ([1]u8{0} ** 12)).*,
                            .payload = payload,
                            .timestamp = @as(u64, @intCast(std.time.milliTimestamp())),
                        });

                        // Libération des ressources de structure temporaire (pas du payload_copy)
                        // Note: Si incoming.data contient des sous-allocations, libérez-les ici
                    }

                    // 3. TRAVAIL LOCAL : Inférence et maintien du système
                    const now = std.time.milliTimestamp();
                    if (now - last_ping > 15000) {
                        network.broadcastPresence() catch {};
                        last_ping = now;
                    }

                    m.saturate();
                    while (lp_id.* < m.next_id) : (lp_id.* += 1) {
                        re.processNewFact(lp_id.*) catch {};
                    }

                    platform.Thread.sleep(10 * std.time.ns_per_ms);
                }
}
