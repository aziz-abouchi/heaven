#include <rtc/rtc.h>

// Déclaration de la fonction définie dans Zig
extern "C" {
    #include <rtc/rtc.h>
    
    int rtc_init(void (*on_message)(int, const char*, int, void*)) {
        // ... votre code ...
        return 0;
    }
    void on_rtc_message(const char* remote_peer_id, const char* data, int size);
}

// Signature correspondant EXACTEMENT à rtcMessageCallbackFunc dans rtc.h
void on_message_callback(int id, const char* data, int size, void* user_ptr) {
    // On ignore user_ptr car on n'en a pas besoin ici
    on_rtc_message("remote_peer", data, size); 
}

void setup_channel(int channel_id) {
    rtcSetMessageCallback(channel_id, on_message_callback);
}