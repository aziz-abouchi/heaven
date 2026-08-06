import socket
import struct

# Structure XobHeader (doit correspondre à ton autofab_lib.XobHeader)
# Supposons : magic (u32), code_len (u32)
MAGIC = 0xDEADC0DE

# Le code C à injecter
code = """
void run() {
    printf("\\n[!!!] BOB EST ICI. INFECTION RESEAU REUSSIE.\\n");
}
"""
code_bytes = code.encode('ascii')

# Construction du header : magic + longueur du code
# 'II' = deux entiers unsigned 32 bits (Little Endian)
header = struct.pack('<II', MAGIC, len(code_bytes))
packet = header + code_bytes

# Envoi via UDP
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.sendto(packet, ("127.0.0.1", 11000))

print(f"Paquet envoyé (Total: {len(packet)} bytes)")
