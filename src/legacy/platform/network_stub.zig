// Stub utilisé quand le build est fait avec -Dnetwork=false.
// Fournit les mêmes symboles C-ABI que webrtc_impl.cpp, en no-op,
// pour permettre à l'exécutable de lier sans libdatachannel.
// Ne PAS ajouter d'autres exports ici sans vérifier `grep -nr "extern fn"`
// pour repérer d'éventuels nouveaux symboles WebRTC requis par handlers.zig.

export fn send_proof_response(
    peer_id_ptr: [*]const u8,
    peer_id_len: usize,
    data_ptr: [*]const u8,
    data_len: usize,
) callconv(.c) void {
    _ = peer_id_ptr;
    _ = peer_id_len;
    _ = data_ptr;
    _ = data_len;
}

export fn send_work_steal_response(
    peer_id_ptr: [*]const u8,
    peer_id_len: usize,
    data_ptr: [*]const u8,
    data_len: usize,
) callconv(.c) void {
    _ = peer_id_ptr;
    _ = peer_id_len;
    _ = data_ptr;
    _ = data_len;
}
