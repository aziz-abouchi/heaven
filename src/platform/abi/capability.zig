//! Capabilities de la couche platform (docs/spec/_platform.md P1).
//!
//! Une capability porte le POUVOIR effectivement accorde (racine,
//! permissions, contraintes), pas seulement sa presence. La derivation
//! ne peut que RESTREINDRE, jamais etendre.

const std = @import("std");

/// Permissions fichier (bitflags).
pub const FilePermission = packed struct(u8) {
    read: bool = false,
    write: bool = false,
    exec: bool = false,
    _pad: u5 = 0,

    pub fn full() FilePermission {
        return .{ .read = true, .write = true, .exec = true };
    }

    pub fn readOnly() FilePermission {
        return .{ .read = true };
    }

    /// a est-il un sous-ensemble de b ?
    pub fn isSubsetOf(a: FilePermission, b: FilePermission) bool {
        if (a.read and !b.read) return false;
        if (a.write and !b.write) return false;
        if (a.exec and !b.exec) return false;
        return true;
    }
};

pub const FileCap = struct {
    /// Racine autorisee. Toute operation doit cibler un chemin sous
    /// cette racine.
    root: []const u8,
    permissions: FilePermission = FilePermission.readOnly(),

    const Self = @This();

    /// Cree une capability racine (bootstrap). Ne doit etre appele que
    /// par la ligne de commande ou un acteur parent de confiance.
    pub fn root_full(root: []const u8) Self {
        return .{ .root = root, .permissions = FilePermission.full() };
    }

    /// Restreint la capability. Retourne null si les nouvelles
    /// contraintes ne sont pas un sous-ensemble (root plus large ou
    /// permissions supplementaires).
    pub fn restrict(
        self: Self,
        new_root: []const u8,
        new_perms: FilePermission,
    ) ?Self {
        // Le nouveau root doit etre un ENFANT du root existant (ou
        // egal). Interdit les parents et les faux enfants
        // ("/etc/heavenX" n'est pas enfant de "/etc/heaven").
        if (!isChildOf(new_root, self.root)) return null;
        // Les nouvelles permissions doivent etre un sous-ensemble.
        if (!FilePermission.isSubsetOf(new_perms, self.permissions)) return null;
        return .{ .root = new_root, .permissions = new_perms };
    }

    /// new_path est-il un enfant (ou egal) de parent ?
    fn isChildOf(new_path: []const u8, parent: []const u8) bool {
        if (std.mem.eql(u8, new_path, parent)) return true;
        if (!std.mem.startsWith(u8, new_path, parent)) return false;
        // Frontiere : new_path[parent.len] doit etre un separateur.
        if (new_path.len <= parent.len) return false;
        return new_path[parent.len] == '/';
    }
};

test "FileCap : root_full a toutes les permissions" {
    const c = FileCap.root_full("/etc/heaven");
    try std.testing.expect(c.permissions.read);
    try std.testing.expect(c.permissions.write);
    try std.testing.expect(c.permissions.exec);
    try std.testing.expectEqualStrings("/etc/heaven", c.root);
}

test "FileCap : restrict vers un sous-chemin est autorise" {
    const c = FileCap.root_full("/etc/heaven");
    const r = c.restrict("/etc/heaven/config", FilePermission.readOnly()) orelse
        return error.RestrictionRefusee;
    try std.testing.expectEqualStrings("/etc/heaven/config", r.root);
    try std.testing.expect(r.permissions.read);
    try std.testing.expect(!r.permissions.write);
}

test "FileCap : restrict vers un chemin plus large est refuse" {
    const c = FileCap.root_full("/etc/heaven");
    const r = c.restrict("/etc", FilePermission.readOnly());
    try std.testing.expectEqual(@as(?FileCap, null), r);
}

test "FileCap : restrict refuse un faux enfant (prefixe sans separateur)" {
    const c = FileCap.root_full("/etc/heaven");
    const r = c.restrict("/etc/heavenX", FilePermission.readOnly());
    try std.testing.expectEqual(@as(?FileCap, null), r);
}

test "FileCap : restrict accepte le root egal" {
    const c = FileCap.root_full("/etc/heaven");
    const r = c.restrict("/etc/heaven", FilePermission.readOnly()) orelse
        return error.RestrictionRefusee;
    try std.testing.expectEqualStrings("/etc/heaven", r.root);
}

test "FileCap : restrict qui ajoute des permissions est refuse" {
    const c = FileCap.root_full("/etc/heaven");
    const read_only = c.restrict("/etc/heaven", FilePermission.readOnly()) orelse
        return error.RestrictionRefusee;
    // Tenter d'etendre les permissions
    const attempt = read_only.restrict("/etc/heaven", FilePermission.full());
    try std.testing.expectEqual(@as(?FileCap, null), attempt);
}

// ─────────────────────────────────────────────────────────────
// NetCap
// ─────────────────────────────────────────────────────────────

pub const Protocol = enum {
    http,
    https,
    ws,
    wss,
    tcp,
    udp,
};

pub const ProtocolSet = std.enums.EnumSet(Protocol);

pub const PortRange = struct {
    min: u16,
    max: u16,

    pub fn contains(self: PortRange, port: u16) bool {
        return port >= self.min and port <= self.max;
    }

    pub fn isSubsetOf(a: PortRange, b: PortRange) bool {
        return a.min >= b.min and a.max <= b.max;
    }
};

pub const NetCap = struct {
    protocols: ProtocolSet,
    /// Destinations autorisees. Liste de suffixes de domaine ou
    /// prefixes CIDR. Le matching exact est a preciser (voir spec
    /// securite). Pour l'instant, un simple startsWith.
    destinations: []const []const u8,
    ports: PortRange,

    const Self = @This();

    pub fn root_full(destinations: []const []const u8) Self {
        return .{
            .protocols = ProtocolSet.initFull(),
            .destinations = destinations,
            .ports = .{ .min = 0, .max = 65535 },
        };
    }

    pub fn restrict(
        self: Self,
        new_protocols: ProtocolSet,
        new_destinations: []const []const u8,
        new_ports: PortRange,
    ) ?Self {
        // Protocoles : sous-ensemble
        if (!new_protocols.subsetOf(self.protocols)) return null;
        // Ports : sous-intervalle
        if (!PortRange.isSubsetOf(new_ports, self.ports)) return null;
        // Destinations : toutes les nouvelles doivent etre couvertes
        // par une destination existante.
        for (new_destinations) |nd| {
            var covered = false;
            for (self.destinations) |d| {
                if (std.mem.endsWith(u8, nd, d)) {
                    covered = true;
                    break;
                }
            }
            if (!covered) return null;
        }
        return .{
            .protocols = new_protocols,
            .destinations = new_destinations,
            .ports = new_ports,
        };
    }
};

test "NetCap : root_full autorise tout" {
    const dests = [_][]const u8{ "example.com", "heaven.dev" };
    const c = NetCap.root_full(&dests);
    try std.testing.expect(c.protocols.contains(.https));
    try std.testing.expect(c.protocols.contains(.tcp));
    try std.testing.expect(c.ports.contains(443));
    try std.testing.expect(c.ports.contains(0));
}

test "NetCap : restrict a un sous-ensemble" {
    const dests = [_][]const u8{"example.com"};
    const c = NetCap.root_full(&dests);
    var protos = ProtocolSet.initEmpty();
    protos.insert(.https);
    const r = c.restrict(protos, &dests, .{ .min = 443, .max = 443 }) orelse
        return error.RestrictionRefusee;
    try std.testing.expect(r.protocols.contains(.https));
    try std.testing.expect(!r.protocols.contains(.tcp));
    try std.testing.expect(r.ports.contains(443));
    try std.testing.expect(!r.ports.contains(80));
}

test "NetCap : restrict refuse un protocole hors cap" {
    const dests = [_][]const u8{"example.com"};
    const c = NetCap.root_full(&dests);
    var only_https = ProtocolSet.initEmpty();
    only_https.insert(.https);
    const r = c.restrict(only_https, &dests, .{ .min = 443, .max = 443 }) orelse
        return error.RestrictionRefusee;
    // Tentative d'ajout de tcp
    var https_tcp = ProtocolSet.initEmpty();
    https_tcp.insert(.https);
    https_tcp.insert(.tcp);
    try std.testing.expectEqual(@as(?NetCap, null), r.restrict(https_tcp, &dests, .{ .min = 443, .max = 443 }));
}

test "NetCap : restrict refuse une destination non couverte" {
    const dests = [_][]const u8{"example.com"};
    const c = NetCap.root_full(&dests);
    const bad = [_][]const u8{"evil.com"};
    try std.testing.expectEqual(
        @as(?NetCap, null),
        c.restrict(ProtocolSet.initFull(), &bad, .{ .min = 443, .max = 443 }),
    );
}

test "NetCap : restrict refuse un port hors plage" {
    const dests = [_][]const u8{"example.com"};
    const c = NetCap.root_full(&dests);
    var protos = ProtocolSet.initEmpty();
    protos.insert(.https);
    // On restreint d'abord a 443
    const r = c.restrict(protos, &dests, .{ .min = 443, .max = 443 }) orelse
        return error.RestrictionRefusee;
    // Tentative d'etendre a 80
    try std.testing.expectEqual(
        @as(?NetCap, null),
        r.restrict(protos, &dests, .{ .min = 80, .max = 80 }),
    );
}

// ─────────────────────────────────────────────────────────────
// EnergyCap
// ─────────────────────────────────────────────────────────────

pub const MeterId = enum {
    package,      // RAPL package
    core,         // RAPL core
    dram,         // RAPL dram
    smc,          // macOS SMC
    estimated,    // Δénergie/Δt
};

pub const MeterSet = std.enums.EnumSet(MeterId);

pub const Energy = struct {
    /// Joules (mesure ou estimation, cf. Precision).
    joules: f64,
};

pub const EnergyCap = struct {
    /// Compteurs accessibles en lecture.
    read_meters: MeterSet,
    /// Budget energetique optionnel. Si present, l'acteur qui detient
    /// la capability doit le respecter (contrainte runtime).
    budget: ?Energy = null,
    /// Intervalle de polling pour l'enforcement du budget.
    interval: ?u64 = null,  // ns

    const Self = @This();

    pub fn root_full() Self {
        return .{ .read_meters = MeterSet.initFull() };
    }

    pub fn restrict(
        self: Self,
        new_meters: MeterSet,
        new_budget: ?Energy,
        new_interval: ?u64,
    ) ?Self {
        if (!new_meters.subsetOf(self.read_meters)) return null;
        // Budget : ne peut pas augmenter
        if (self.budget) |b| {
            if (new_budget) |nb| {
                if (nb.joules > b.joules) return null;
            }
            // Si self a un budget et new n'en a pas, on herite.
            return .{
                .read_meters = new_meters,
                .budget = if (new_budget) |nb| nb else b,
                .interval = if (new_interval) |ni| ni else self.interval,
            };
        } else {
            // Self sans budget : new peut en poser un.
            return .{
                .read_meters = new_meters,
                .budget = new_budget,
                .interval = if (new_interval) |ni| ni else self.interval,
            };
        }
    }
};

test "EnergyCap : root_full lit tous les compteurs" {
    const c = EnergyCap.root_full();
    try std.testing.expect(c.read_meters.contains(.package));
    try std.testing.expect(c.read_meters.contains(.smc));
    try std.testing.expect(c.budget == null);
}

test "EnergyCap : restrict a un sous-ensemble de compteurs" {
    const c = EnergyCap.root_full();
    var only_rapl = MeterSet.initEmpty();
    only_rapl.insert(.package);
    only_rapl.insert(.core);
    const r = c.restrict(only_rapl, null, null) orelse
        return error.RestrictionRefusee;
    try std.testing.expect(r.read_meters.contains(.package));
    try std.testing.expect(!r.read_meters.contains(.smc));
}

test "EnergyCap : restrict refuse un compteur hors cap" {
    const c = EnergyCap.root_full();
    var only_rapl = MeterSet.initEmpty();
    only_rapl.insert(.package);
    const r = c.restrict(only_rapl, null, null) orelse
        return error.RestrictionRefusee;
    // Tentative d'ajout de smc
    var rapl_smc = MeterSet.initEmpty();
    rapl_smc.insert(.package);
    rapl_smc.insert(.smc);
    try std.testing.expectEqual(@as(?EnergyCap, null), r.restrict(rapl_smc, null, null));
}

test "EnergyCap : restrict ne peut pas augmenter le budget" {
    const c = EnergyCap.root_full();
    var only_rapl = MeterSet.initEmpty();
    only_rapl.insert(.package);
    const with_budget = c.restrict(only_rapl, .{ .joules = 100.0 }, 1_000_000) orelse
        return error.RestrictionRefusee;
    // Augmenter le budget : refuse
    try std.testing.expectEqual(
        @as(?EnergyCap, null),
        with_budget.restrict(only_rapl, .{ .joules = 200.0 }, null),
    );
    // Reduire le budget : accepte
    const lower = with_budget.restrict(only_rapl, .{ .joules = 50.0 }, null) orelse
        return error.RestrictionRefusee;
    try std.testing.expectEqual(@as(f64, 50.0), lower.budget.?.joules);
}
