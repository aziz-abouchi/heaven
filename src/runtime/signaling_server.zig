const std = @import("std");
const platform = @import("platform");

pub const SignalingServer = struct {
    port: u16,
    peers: std.StringHashMap(PeerInfo),
    allocator: std.mem.Allocator,
    exiting: *const std.atomic.Value(bool),
    
    pub const PeerInfo = struct {
        id: []const u8,
        connected_at: i64,
        last_seen: i64,
    };
    
    pub fn init(allocator: std.mem.Allocator, port: u16, exiting: *const std.atomic.Value(bool)) SignalingServer {
        return .{
            .port = port,
            .peers = std.StringHashMap(PeerInfo).init(allocator),
            .allocator = allocator,
            .exiting = exiting,
        };
    }
    
    pub fn run(self: *SignalingServer) !void {
        const address = std.net.Address.parseIp4("0.0.0.0", self.port) catch return;
        var server = address.listen(.{ .reuse_address = true }) catch |err| {
            platform.io.print("[Signal] Listen error: {}\n", .{err});
            return;
        };
        defer server.deinit();
        
        platform.io.print("[Signal] Server listening on port {}\n", .{self.port});
        
        // Boucle avec vérification du flag exiting
        while (!self.exiting.load(.acquire)) {
            const conn = server.accept() catch continue;
            const t = platform.Thread.spawn(.{}, handleClient, .{ self, conn }) catch {
                conn.stream.close();
                continue;
            };
            t.detach();
        }
        
        platform.io.print("[Signal] Server shutting down\n", .{});
    }
    
    fn handleClient(self: *SignalingServer, conn: std.net.Server.Connection) void {
        defer conn.stream.close();
        var buf: [4096]u8 = undefined;
        
        while (true) {
            const n = conn.stream.read(&buf) catch break;
            if (n == 0) break;
            
            const request = buf[0..n];
            
            // Simple JSON parsing pour les messages de signaling
            if (std.mem.indexOf(u8, request, "\"type\":\"register\"")) |_| {
                // Extraire peer_id
                if (extractJsonField(request, "peer_id")) |peer_id| {
                    const owned_id = self.allocator.dupe(u8, peer_id) catch continue;
                    self.peers.put(owned_id, .{
                        .id = owned_id,
                        .connected_at = std.time.milliTimestamp(),
                        .last_seen = std.time.milliTimestamp(),
                    }) catch {};
                    
                    // Envoyer la liste des peers
                    var response_buf: [2048]u8 = undefined;
                    const response = buildPeerList(self, &response_buf);
                    conn.stream.writeAll(response) catch {};
                }
            }
            else if (std.mem.indexOf(u8, request, "\"type\":\"offer\"") != null or
                     std.mem.indexOf(u8, request, "\"type\":\"answer\"") != null or
                     std.mem.indexOf(u8, request, "\"type\":\"ice\"") != null) {
                // Forward au peer cible
                if (extractJsonField(request, "target")) |target_id| {
                    // TODO: Maintenir une map de connexions persistantes
                    // Pour l'instant, on log juste
                    platform.io.print("[Signal] Forward to {s}\n", .{target_id});
                }
            }
        }
    }
    
    
    pub fn deinit(self: *SignalingServer) void {
        // Libérer toutes les chaînes dupliquées dans peers
        var it = self.peers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.id);
        }
        self.peers.deinit();
    }
    
    fn extractJsonField(json: []const u8, field: []const u8) ?[]const u8 {
        const key = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\":\"", .{field}) catch return null;
        defer std.heap.page_allocator.free(key);
        
        const start = std.mem.indexOf(u8, json, key) orelse return null;
        const value_start = start + key.len;
        const end = std.mem.indexOfPos(u8, json, value_start, "\"") orelse return null;
        
        return json[value_start..end];
    }
    
    fn buildPeerList(self: *SignalingServer, buf: []u8) []const u8 {
        var fbs = std.io.fixedBufferStream(buf);
        const writer = fbs.writer();
        
        writer.writeAll("{\"type\":\"peer_list\",\"peers\":[") catch {};
        var first = true;
        var it = self.peers.iterator();
        while (it.next()) |entry| {
            if (!first) writer.writeAll(",") catch {};
            first = false;
            writer.print("\"{s}\"", .{entry.value_ptr.id}) catch {};
        }
        writer.writeAll("]}") catch {};
        
        return fbs.getWritten();
    }
};
