const std = @import("std");

pub const EffectType = enum {
    DiskWrite, // VORTEX
    NetworkSend, // SCUT
    CoreKill, // Gestion des Threads
    SelfMutate, // Forge / AutoFab
};

pub const EffectHandler = struct {
    pub fn request(effect: EffectType, priority: f32) bool {
        _ = effect;
        // La Matrix décide : si l'énergie globale est trop basse (Green),
        // on refuse les effets coûteux.
        if (priority < 0.5) return false;
        return true;
    }
};
