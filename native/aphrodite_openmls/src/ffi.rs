use std::{
    ffi::{c_char, CStr},
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
};

use serde::Serialize;

use crate::{
    NativeMlsEngine, OpenMlsCommitBundle, OpenMlsError, OpenMlsHandshakeResult, OpenMlsKeyPackage,
    PrivateStatePath,
};

const ABI_VERSION: u32 = 1;

/// Opaque handle owned by the caller through the C ABI.
#[repr(C)]
pub struct AphroditeOpenMlsHandle {
    _private: [u8; 0],
}

/// A heap-owned UTF-8 JSON output buffer.
#[repr(C)]
pub struct AphroditeOpenMlsBuffer {
    pub data: *mut u8,
    pub len: usize,
}

#[derive(Debug, Serialize)]
struct FfiResponse<T> {
    abi_version: u32,
    ok: bool,
    data: Option<T>,
    error: Option<FfiError>,
}

#[derive(Debug, Serialize)]
struct FfiError {
    code: &'static str,
    message: String,
}

#[derive(Debug, Serialize)]
struct DeviceIdentityResponse<'a> {
    device_id: &'a str,
    credential_identity: String,
    signature_public_key: String,
}

#[derive(Debug, Serialize)]
struct KeyPackageResponse {
    ciphersuite: String,
    key_package: String,
    signature: String,
    expires_at: u64,
}

#[derive(Debug, Serialize)]
struct GroupResponse {
    group_id: String,
}

#[derive(Debug, Serialize)]
struct ApplicationMessageResponse {
    ciphertext: String,
}

#[derive(Debug, Serialize)]
struct WelcomeResponse {
    commit: String,
    welcome: String,
    group_info: Option<String>,
}

#[derive(Debug, Serialize)]
struct PlaintextResponse {
    plaintext: String,
}

#[derive(Debug, Serialize)]
struct HandshakeResponse {
    kind: &'static str,
    epoch: u64,
}

#[derive(Debug, Serialize)]
struct CommitResponse {
    commit: String,
    welcome: Option<String>,
    group_info: Option<String>,
    epoch: u64,
}

/// Opens the native OpenMLS engine using an absolute app-support directory.
///
/// Returns null on invalid pointers, invalid UTF-8, relative paths, or storage
/// initialization failure. The returned handle must be closed exactly once.
///
/// # Safety
/// `app_support_dir` must be null or point to a valid NUL-terminated UTF-8
/// string for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_open(
    app_support_dir: *const c_char,
) -> *mut AphroditeOpenMlsHandle {
    let result = catch_unwind(AssertUnwindSafe(|| {
        let Some(app_support_dir) = read_c_string(app_support_dir) else {
            return ptr::null_mut();
        };
        let Ok(state_path) = PrivateStatePath::from_app_support_dir(app_support_dir) else {
            return ptr::null_mut();
        };
        let Ok(engine) = NativeMlsEngine::open(&state_path) else {
            return ptr::null_mut();
        };

        Box::into_raw(Box::new(engine)).cast()
    }));
    result.unwrap_or(ptr::null_mut())
}

/// Initializes or restores a device and returns public identity JSON.
///
/// The caller owns the returned buffer and must release it with
/// `aphrodite_openmls_free_buffer`.
///
/// # Safety
/// `handle` must be null or a live handle returned by `aphrodite_openmls_open`.
/// `device_id` must be null or a valid NUL-terminated UTF-8 string. The handle
/// must not be closed concurrently with this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_initialize_device(
    handle: *mut AphroditeOpenMlsHandle,
    device_id: *const c_char,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(device_id) = read_c_string(device_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "device_id must be valid UTF-8",
            ));
        };

        match engine.initialize_device(device_id) {
            Ok(identity) => response_buffer(success_response(DeviceIdentityResponse {
                device_id: identity.device_id(),
                credential_identity: encode_bytes(identity.credential_identity()),
                signature_public_key: encode_bytes(identity.signature_public_key()),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Generates persisted KeyPackages and returns only public JSON material.
///
/// # Safety
/// `handle` must be null or a live handle returned by `aphrodite_openmls_open`,
/// and it must not be closed concurrently with this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_generate_key_packages(
    handle: *mut AphroditeOpenMlsHandle,
    count: u32,
    expires_at: u64,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };

        match engine.generate_key_packages(count as usize, expires_at) {
            Ok(packages) => response_buffer(success_response(
                packages
                    .iter()
                    .map(public_key_package_response)
                    .collect::<Vec<_>>(),
            )),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Creates a persisted one-member MLS group for a conversation.
///
/// # Safety
/// `handle` must be null or a live handle returned by `aphrodite_openmls_open`.
/// `conversation_id` must be null or a valid NUL-terminated UTF-8 string. The
/// handle must not be closed concurrently with this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_create_group(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };

        match engine.create_group(conversation_id) {
            Ok(group_id) => response_buffer(success_response(GroupResponse {
                group_id: encode_bytes(&group_id),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Encrypts an MLS application message with the persisted group state.
///
/// # Safety
/// `handle` must be null or a live handle returned by `aphrodite_openmls_open`.
/// `conversation_id` must be null or a valid NUL-terminated UTF-8 string.
/// `plaintext` must point to `plaintext_len` readable bytes for this call, unless
/// `plaintext_len` is zero. The handle must not be closed concurrently with this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_encrypt_application_message(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
    plaintext: *const u8,
    plaintext_len: usize,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        if plaintext.is_null() && plaintext_len > 0 {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "plaintext must not be null when plaintext_len is nonzero",
            ));
        }
        let plaintext = if plaintext_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(plaintext, plaintext_len) }
        };

        match engine.encrypt_application_message(conversation_id, plaintext) {
            Ok(ciphertext) => response_buffer(success_response(ApplicationMessageResponse {
                ciphertext: encode_bytes(&ciphertext),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Adds a member from a public TLS KeyPackage and returns Commit/Welcome material.
///
/// # Safety
/// `handle` and `conversation_id` follow the same rules as the group creation
/// entry point. `key_package` must point to `key_package_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_add_member(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
    key_package: *const u8,
    key_package_len: usize,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        if key_package.is_null() && key_package_len > 0 {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "key_package must not be null when key_package_len is nonzero",
            ));
        }
        let bytes = if key_package_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(key_package, key_package_len) }
        };
        match engine.add_member(conversation_id, bytes) {
            Ok(bundle) => response_buffer(success_response(WelcomeResponse {
                commit: encode_bytes(bundle.commit()),
                welcome: encode_bytes(bundle.welcome()),
                group_info: bundle.group_info().map(encode_bytes),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Joins an MLS group from a public TLS Welcome.
///
/// # Safety
/// `handle` must be live and `welcome` must point to `welcome_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_join_group(
    handle: *mut AphroditeOpenMlsHandle,
    welcome: *const u8,
    welcome_len: usize,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        if welcome.is_null() && welcome_len > 0 {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "welcome must not be null when welcome_len is nonzero",
            ));
        }
        let bytes = if welcome_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(welcome, welcome_len) }
        };
        match engine.join_group(bytes) {
            Ok(group_id) => response_buffer(success_response(GroupResponse {
                group_id: encode_bytes(&group_id),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Decrypts a public TLS MLS application message and returns hex plaintext.
///
/// # Safety
/// `handle` must be live and `ciphertext` must point to `ciphertext_len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_decrypt_application_message(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
    ciphertext: *const u8,
    ciphertext_len: usize,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        if ciphertext.is_null() && ciphertext_len > 0 {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "ciphertext must not be null when ciphertext_len is nonzero",
            ));
        }
        let bytes = if ciphertext_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(ciphertext, ciphertext_len) }
        };
        match engine.decrypt_application_message(conversation_id, bytes) {
            Ok(plaintext) => response_buffer(success_response(PlaintextResponse {
                plaintext: encode_bytes(&plaintext),
            })),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Applies a TLS-serialized MLS Proposal or Commit to local persisted state.
///
/// # Safety
/// `handle` and `conversation_id` must be valid. `handshake` must point to
/// `handshake_len` readable bytes unless its length is zero.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_apply_handshake_message(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
    handshake: *const u8,
    handshake_len: usize,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        if handshake.is_null() && handshake_len > 0 {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "handshake must not be null when handshake_len is nonzero",
            ));
        }
        let handshake = if handshake_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(handshake, handshake_len) }
        };
        match engine.apply_handshake_message(conversation_id, handshake) {
            Ok(result) => response_buffer(success_response(handshake_response(result))),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Creates, merges, and returns a Commit covering locally persisted proposals.
///
/// # Safety
/// `handle` must be live and `conversation_id` must be a valid UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_commit_pending_proposals(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        match engine.commit_pending_proposals(conversation_id) {
            Ok(bundle) => response_buffer(success_response(commit_response(bundle))),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Destroys all private MLS state owned by this local device.
///
/// This does not alter any server roster or other device state. The handle
/// remains open, but MLS operations require device reinitialization afterward.
///
/// # Safety
/// `handle` must be null or a live handle returned by `aphrodite_openmls_open`,
/// and it must not be closed concurrently with this call.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_destroy_device_state(
    handle: *mut AphroditeOpenMlsHandle,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        match engine.destroy_device_state() {
            Ok(()) => response_buffer(success_response(())),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Removes one local MLS group and all persisted group secrets.
///
/// # Safety
/// `handle` must be live and `conversation_id` must be a valid UTF-8 C string.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_remove_local_group(
    handle: *mut AphroditeOpenMlsHandle,
    conversation_id: *const c_char,
) -> AphroditeOpenMlsBuffer {
    catch_buffer(|| {
        let Some(engine) = handle_ref(handle) else {
            return response_buffer(error_response::<()>("invalid_handle", "handle is null"));
        };
        let Some(conversation_id) = read_c_string(conversation_id) else {
            return response_buffer(error_response::<()>(
                "invalid_argument",
                "conversation_id must be valid UTF-8",
            ));
        };
        match engine.remove_local_group(conversation_id) {
            Ok(()) => response_buffer(success_response(())),
            Err(error) => {
                response_buffer(error_response::<()>(error_code(&error), &error.to_string()))
            }
        }
    })
}

/// Closes an engine handle. Passing null is a no-op.
///
/// # Safety
/// A non-null `handle` must have been returned by `aphrodite_openmls_open`, must
/// not be in use by another thread, and must be closed exactly once.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_close(handle: *mut AphroditeOpenMlsHandle) {
    if !handle.is_null() {
        drop(Box::from_raw(handle.cast::<NativeMlsEngine>()));
    }
}

/// Releases a buffer returned by this ABI. Passing an invalid buffer is not
/// supported; callers must release each returned buffer exactly once.
///
/// # Safety
/// `buffer` must be a buffer previously returned by this ABI and must not have
/// been released before. Its `data` and `len` fields must be unchanged.
#[no_mangle]
pub unsafe extern "C" fn aphrodite_openmls_free_buffer(buffer: AphroditeOpenMlsBuffer) {
    if buffer.data.is_null() {
        return;
    }
    let raw_slice = ptr::slice_from_raw_parts_mut(buffer.data, buffer.len);
    drop(Box::from_raw(raw_slice));
}

fn catch_buffer(function: impl FnOnce() -> AphroditeOpenMlsBuffer) -> AphroditeOpenMlsBuffer {
    catch_unwind(AssertUnwindSafe(function)).unwrap_or_else(|_| {
        response_buffer(error_response::<()>(
            "panic",
            "native OpenMLS operation panicked",
        ))
    })
}

fn handle_ref<'a>(handle: *mut AphroditeOpenMlsHandle) -> Option<&'a NativeMlsEngine> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &*handle.cast::<NativeMlsEngine>() })
    }
}

unsafe fn read_c_string<'a>(value: *const c_char) -> Option<&'a str> {
    if value.is_null() {
        return None;
    }
    CStr::from_ptr(value).to_str().ok()
}

fn encode_bytes(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn public_key_package_response(package: &OpenMlsKeyPackage) -> KeyPackageResponse {
    KeyPackageResponse {
        ciphersuite: format!("{:?}", package.ciphersuite()),
        key_package: encode_bytes(package.key_package()),
        signature: encode_bytes(package.signature()),
        expires_at: package.expires_at(),
    }
}

fn handshake_response(result: OpenMlsHandshakeResult) -> HandshakeResponse {
    HandshakeResponse {
        kind: result.kind(),
        epoch: result.epoch(),
    }
}

fn commit_response(bundle: OpenMlsCommitBundle) -> CommitResponse {
    CommitResponse {
        commit: encode_bytes(bundle.commit()),
        welcome: bundle.welcome().map(encode_bytes),
        group_info: bundle.group_info().map(encode_bytes),
        epoch: bundle.epoch(),
    }
}

fn success_response<T: Serialize>(data: T) -> FfiResponse<T> {
    FfiResponse {
        abi_version: ABI_VERSION,
        ok: true,
        data: Some(data),
        error: None,
    }
}

fn error_response<T>(code: &'static str, message: &str) -> FfiResponse<T> {
    FfiResponse {
        abi_version: ABI_VERSION,
        ok: false,
        data: None,
        error: Some(FfiError {
            code,
            message: message.to_owned(),
        }),
    }
}

fn response_buffer<T: Serialize>(response: FfiResponse<T>) -> AphroditeOpenMlsBuffer {
    let json = serde_json::to_vec(&response).unwrap_or_else(|_| {
        br#"{"abi_version":1,"ok":false,"data":null,"error":{"code":"serialization_error","message":"failed to serialize response"}}"#.to_vec()
    });
    let mut json = json.into_boxed_slice();
    let buffer = AphroditeOpenMlsBuffer {
        data: json.as_mut_ptr(),
        len: json.len(),
    };
    Box::leak(json);
    buffer
}

fn error_code(error: &OpenMlsError) -> &'static str {
    match error {
        OpenMlsError::EmptyDeviceId => "empty_device_id",
        OpenMlsError::EmptyConversationId => "empty_conversation_id",
        OpenMlsError::GroupAlreadyExists => "group_already_exists",
        OpenMlsError::GroupNotFound => "group_not_found",
        OpenMlsError::GroupDeletion(_) => "group_deletion_failed",
        OpenMlsError::DeviceStateDestruction(_) => "device_state_destruction_failed",
        OpenMlsError::GroupPersistenceMissing => "group_persistence_missing",
        OpenMlsError::EmptyApplicationMessage => "empty_application_message",
        OpenMlsError::DeviceNotInitialized => "device_not_initialized",
        OpenMlsError::InvalidKeyPackageBatchSize => "invalid_key_package_batch_size",
        OpenMlsError::KeyPackageAlreadyExpired => "key_package_already_expired",
        OpenMlsError::KeyPackageLifetimeTooLong => "key_package_lifetime_too_long",
        OpenMlsError::RelativeStateDirectory => "relative_state_directory",
        _ => "native_error",
    }
}

#[cfg(test)]
mod tests {
    use std::{ffi::CString, ptr, slice};

    use super::*;

    fn read_buffer(buffer: &AphroditeOpenMlsBuffer) -> String {
        let bytes = unsafe { slice::from_raw_parts(buffer.data, buffer.len) };
        String::from_utf8(bytes.to_vec()).expect("FFI response is UTF-8")
    }

    #[test]
    fn rejects_invalid_open_arguments() {
        assert!(unsafe { aphrodite_openmls_open(ptr::null()) }.is_null());
        let relative = CString::new("relative").expect("CString");
        assert!(unsafe { aphrodite_openmls_open(relative.as_ptr()) }.is_null());
    }

    #[test]
    fn returns_public_identity_and_key_package_json() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let directory =
            CString::new(directory.path().to_str().expect("UTF-8 path")).expect("CString");
        let handle = unsafe { aphrodite_openmls_open(directory.as_ptr()) };
        assert!(!handle.is_null());

        let device = CString::new("device-ffi").expect("CString");
        let identity = unsafe { aphrodite_openmls_initialize_device(handle, device.as_ptr()) };
        let identity_json = read_buffer(&identity);
        assert!(identity_json.contains("\"ok\":true"));
        assert!(identity_json.contains("device-ffi"));
        unsafe { aphrodite_openmls_free_buffer(identity) };

        let packages = unsafe {
            aphrodite_openmls_generate_key_packages(
                handle,
                1,
                crate::unix_timestamp().expect("clock") + 3600,
            )
        };
        let packages_json = read_buffer(&packages);
        assert!(packages_json.contains("\"ok\":true"));
        assert!(packages_json.contains("key_package"));
        assert!(packages_json.contains("signature"));
        unsafe {
            aphrodite_openmls_free_buffer(packages);
            aphrodite_openmls_close(handle);
        }
    }

    #[test]
    fn creates_group_and_encrypts_public_tls_ciphertext() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let directory =
            CString::new(directory.path().to_str().expect("UTF-8 path")).expect("CString");
        let handle = unsafe { aphrodite_openmls_open(directory.as_ptr()) };
        assert!(!handle.is_null());
        let device = CString::new("device-ffi-group").expect("CString");
        let identity = unsafe { aphrodite_openmls_initialize_device(handle, device.as_ptr()) };
        unsafe { aphrodite_openmls_free_buffer(identity) };
        let conversation = CString::new("conversation-ffi-group").expect("CString");
        let group = unsafe { aphrodite_openmls_create_group(handle, conversation.as_ptr()) };
        let group_json = read_buffer(&group);
        assert!(group_json.contains("\"ok\":true"));
        assert!(group_json.contains("group_id"));
        unsafe { aphrodite_openmls_free_buffer(group) };

        let plaintext = b"binary\0payload";
        let ciphertext = unsafe {
            aphrodite_openmls_encrypt_application_message(
                handle,
                conversation.as_ptr(),
                plaintext.as_ptr(),
                plaintext.len(),
            )
        };
        let ciphertext_json = read_buffer(&ciphertext);
        assert!(ciphertext_json.contains("\"ok\":true"));
        assert!(ciphertext_json.contains("ciphertext"));
        unsafe {
            aphrodite_openmls_free_buffer(ciphertext);
            aphrodite_openmls_close(handle);
        }
    }

    #[test]
    fn destroys_device_state_and_requires_reinitialization() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let directory =
            CString::new(directory.path().to_str().expect("UTF-8 path")).expect("CString");
        let handle = unsafe { aphrodite_openmls_open(directory.as_ptr()) };
        assert!(!handle.is_null());
        let device = CString::new("device-ffi-destroy").expect("CString");
        let identity = unsafe { aphrodite_openmls_initialize_device(handle, device.as_ptr()) };
        unsafe { aphrodite_openmls_free_buffer(identity) };

        let destroyed = unsafe { aphrodite_openmls_destroy_device_state(handle) };
        let destroyed_json = read_buffer(&destroyed);
        assert!(destroyed_json.contains("\"ok\":true"));
        unsafe { aphrodite_openmls_free_buffer(destroyed) };

        let packages = unsafe {
            aphrodite_openmls_generate_key_packages(
                handle,
                1,
                crate::unix_timestamp().expect("clock") + 3600,
            )
        };
        let packages_json = read_buffer(&packages);
        assert!(packages_json.contains("\"code\":\"device_not_initialized\""));
        unsafe {
            aphrodite_openmls_free_buffer(packages);
            aphrodite_openmls_close(handle);
        }
    }

    #[test]
    fn returns_structured_error_for_null_handle() {
        let response = unsafe { aphrodite_openmls_generate_key_packages(ptr::null_mut(), 1, 1) };
        let json = read_buffer(&response);
        assert!(json.contains("\"code\":\"invalid_handle\""));
        unsafe { aphrodite_openmls_free_buffer(response) };
    }
}
