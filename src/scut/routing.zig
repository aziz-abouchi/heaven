const std = @import("std");
const network = @import("network.zig");
const platform = @import("platform");

fn peerScore(p: network.Peer, now: i64) f64 {
    const age = @as(f64, @floatFromInt(now - p.last_seen));
    const freshness = 1.0 / (1.0 + age);
    const activity = std.math.log2(@as(f64, @floatFromInt(p.seen_atoms + 1)));
    const penalty = 1.0 / (1.0 + @as(f64, @floatFromInt(p.failure_count)));

    return freshness * (1.0 + activity) * penalty;
}

pub fn selectPeers(peers: []network.Peer, k: usize, out: []network.Peer) []network.Peer {
    var rng = std.crypto.random;
    const now = std.time.timestamp();

    const n = @min(k, peers.len);

    var scores: [256]f64 = undefined;
    var used: [256]bool = undefined;

    if (peers.len > used.len) return out[0..0];

    var total: f64 = 0;

    for (peers, 0..) |p, i| {
        scores[i] = peerScore(p, now);
        total += scores[i];
        used[i] = false;
    }

    var count: usize = 0;
    const elite = (n * 7) / 10;

    while (count < elite and total > 0) {
        const r = rng.float(f64) * total;
        var acc: f64 = 0;

        for (peers, 0..) |_, i| {
            if (used[i]) continue;

            acc += scores[i];
            if (acc >= r) {
                out[count] = peers[i];
                used[i] = true;
                total -= scores[i];
                count += 1;
                break;
            }
        }
    }

    while (count < n) {
        const i = rng.intRangeLessThan(usize, 0, peers.len);
        if (used[i]) continue;

        out[count] = peers[i];
        used[i] = true;
        count += 1;
    }

    return out[0..n];
}
