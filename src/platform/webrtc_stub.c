// Stubs C : mêmes symboles que webrtc_impl.cpp (cfr c_rtc.h),
// utilisés quand le build est fait avec -Dnetwork=false.
#include "c_rtc.h"

int rtc_init(RTCMessageCallback on_message) { (void)on_message; return 0; }
int rtc_send(const char* remote_peer_id, const char* data, size_t len) {
    (void)remote_peer_id; (void)data; (void)len; return -1;
}
void rtc_poll(void) {}
const char* rtc_get_local_sdp(void) { return ""; }
void rtc_set_remote_sdp(const char* sdp) { (void)sdp; }
