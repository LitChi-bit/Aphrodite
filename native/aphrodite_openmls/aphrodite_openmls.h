#ifndef APHRODITE_OPENMLS_H
#define APHRODITE_OPENMLS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AphroditeOpenMlsHandle AphroditeOpenMlsHandle;

typedef struct AphroditeOpenMlsBuffer {
  uint8_t *data;
  size_t len;
} AphroditeOpenMlsBuffer;

/* Returned handles and buffers are owned by the caller. A handle must not be
 * closed or used concurrently, and must be closed exactly once. */
AphroditeOpenMlsHandle *aphrodite_openmls_open(const char *app_support_dir);
AphroditeOpenMlsBuffer aphrodite_openmls_initialize_device(
    AphroditeOpenMlsHandle *handle,
    const char *device_id);
AphroditeOpenMlsBuffer aphrodite_openmls_generate_key_packages(
    AphroditeOpenMlsHandle *handle,
    uint32_t count,
    uint64_t expires_at);
AphroditeOpenMlsBuffer aphrodite_openmls_create_group(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id);
AphroditeOpenMlsBuffer aphrodite_openmls_encrypt_application_message(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id,
    const uint8_t *plaintext,
    size_t plaintext_len);
AphroditeOpenMlsBuffer aphrodite_openmls_add_member(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id,
    const uint8_t *key_package,
    size_t key_package_len);
AphroditeOpenMlsBuffer aphrodite_openmls_join_group(
    AphroditeOpenMlsHandle *handle,
    const uint8_t *welcome,
    size_t welcome_len);
AphroditeOpenMlsBuffer aphrodite_openmls_decrypt_application_message(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id,
    const uint8_t *ciphertext,
    size_t ciphertext_len);
AphroditeOpenMlsBuffer aphrodite_openmls_apply_handshake_message(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id,
    const uint8_t *handshake,
    size_t handshake_len);
AphroditeOpenMlsBuffer aphrodite_openmls_commit_pending_proposals(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id);
AphroditeOpenMlsBuffer aphrodite_openmls_remove_local_group(
    AphroditeOpenMlsHandle *handle,
    const char *conversation_id);
AphroditeOpenMlsBuffer aphrodite_openmls_destroy_device_state(
    AphroditeOpenMlsHandle *handle);
void aphrodite_openmls_close(AphroditeOpenMlsHandle *handle);
void aphrodite_openmls_free_buffer(AphroditeOpenMlsBuffer buffer);

#ifdef __cplusplus
}
#endif

#endif
