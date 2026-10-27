// Global shutdown flag, partagé entre main.zig et le moteur Heaven.
// Permet à core/http_server.hvn (via @exiting) de sortir proprement
// sa boucle serveur quand Ctrl-C / SIGTERM arrive.
const std = @import("std");
pub var exiting = std.atomic.Value(bool).init(false);
