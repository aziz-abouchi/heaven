// src/platform/c_rtc.h
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*RTCMessageCallback)(const char* remote_peer_id, const char* msg, size_t len);

// Initialise le contexte WebRTC
int rtc_init(RTCMessageCallback on_message);

// Envoie un message à un pair spécifique
int rtc_send(const char* remote_peer_id, const char* data, size_t len);

// Étape de traitement des événements réseau (à appeler dans votre boucle tick)
void rtc_poll();

// Récupère l'offre SDP locale pour l'envoyer à un pair distant
const char* rtc_get_local_sdp();

// Appelé quand on reçoit une offre d'un pair distant
void rtc_set_remote_sdp(const char* sdp);

void on_rtc_message(const char* remote_peer_id, const char* msg, size_t len);

#ifdef __cplusplus
}
#endif
