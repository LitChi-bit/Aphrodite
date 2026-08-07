use std::{
    ffi::{c_char, CStr},
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
};

use serde::Serialize;

use crate::{NativeMlsEngine, OpenMlsError, OpenMlsKeyPackage, PrivateStatePath};

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
    fn returns_structured_error_for_null_handle() {
        let response = unsafe { aphrodite_openmls_generate_key_packages(ptr::null_mut(), 1, 1) };
        let json = read_buffer(&response);
        assert!(json.contains("\"code\":\"invalid_handle\""));
        unsafe { aphrodite_openmls_free_buffer(response) };
    }
}
