const std = @import("std");
const parzig = @import("parzig");
const mlcpd = @import("mlcpd");

/// Lecteur streaming Parquet pour le dataset MLCPD
/// Permet d'accéder aux entrées sans charger tout le fichier en mémoire
pub const MlcpdParquetReader = struct {
    file: parzig.File,
    allocator: std.mem.Allocator,
    num_rows: usize,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !MlcpdParquetReader {
        const file = try parzig.File.init(allocator, path);
        const num_rows = file.numRows();
        return .{
            .file = file,
            .allocator = allocator,
            .num_rows = num_rows,
        };
    }

    pub fn deinit(self: *MlcpdParquetReader) void {
        self.file.deinit();
    }

    /// Lire une entrée MLCPD par index (0-based)
    /// Retourne un ParsedFile prêt pour toExprIr()
    pub fn readEntry(self: *MlcpdParquetReader, row_index: usize) !mlcpd.ParsedFile {
        if (row_index >= self.num_rows) return error.IndexOutOfBounds;

        // Lire la colonne "nodes" (JSON string) pour cette ligne
        const nodes_json = try self.file.readStringColumn(self.allocator, "nodes", row_index);
        defer self.allocator.free(nodes_json);

        // Parser le JSON MLCPD via le module existant
        return mlcpd.parseMlcpdJson(self.allocator, nodes_json);
    }

    /// Lire uniquement les métadonnées d'une entrée (plus léger)
    pub fn readMetadata(self: *MlcpdParquetReader, row_index: usize) !mlcpd.FileMetadata {
        if (row_index >= self.num_rows) return error.IndexOutOfBounds;

        const meta_json = try self.file.readStringColumn(self.allocator, "metadata", row_index);
        defer self.allocator.free(meta_json);

        return mlcpd.parseMetadata(self.allocator, meta_json);
    }

    /// Nombre total d'entrées dans le fichier Parquet
    pub fn rowCount(self: *const MlcpdParquetReader) usize {
        return self.num_rows;
    }
};
