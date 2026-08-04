//! Native OpenMLS boundary for Aphrodite.
//!
//! This crate owns MLS private state. Flutter and the delivery service exchange
//! only serialized MLS protocol bytes and public metadata.

use std::path::{Path, PathBuf};

pub use openmls::prelude::Ciphersuite;
use thiserror::Error;

/// The supported RFC 9420 mandatory-to-implement ciphersuite.
pub const CIPHERSUITE: &str = "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519";

/// A caller-provided application support directory, with a fixed private MLS
/// database filename. The path is deliberately native-only and must not be
/// exposed through the Dart FFI contract.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PrivateStatePath(PathBuf);

impl PrivateStatePath {
    pub fn from_app_support_dir(app_support_dir: impl AsRef<Path>) -> Result<Self, OpenMlsError> {
        let directory = app_support_dir.as_ref();
        if !directory.is_absolute() {
            return Err(OpenMlsError::RelativeStateDirectory);
        }
        Ok(Self(directory.join("aphrodite-openmls.sqlite3")))
    }

    pub fn as_path(&self) -> &Path {
        &self.0
    }
}

/// Opaque wire material received from or sent to the delivery service.
///
/// It intentionally does not expose MLS private keys, group secrets, or a
/// ratchet tree. Their storage and use remain inside the future native engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpaqueMlsBytes(Vec<u8>);

impl OpaqueMlsBytes {
    pub fn new(bytes: Vec<u8>) -> Result<Self, OpenMlsError> {
        if bytes.is_empty() {
            return Err(OpenMlsError::EmptyProtocolMaterial);
        }
        Ok(Self(bytes))
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.0
    }

    pub fn into_vec(self) -> Vec<u8> {
        self.0
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum OpenMlsError {
    #[error("MLS protocol material must not be empty")]
    EmptyProtocolMaterial,
    #[error("the native MLS state directory must be absolute")]
    RelativeStateDirectory,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stores_private_mls_state_under_the_native_support_directory() {
        let path = PrivateStatePath::from_app_support_dir(
            "/var/mobile/Containers/Data/Application/example/Library/Application Support",
        )
        .expect("absolute app support directory is valid");

        assert_eq!(
            path.as_path(),
            Path::new(
                "/var/mobile/Containers/Data/Application/example/Library/Application Support"
            )
            .join("aphrodite-openmls.sqlite3")
        );
    }

    #[test]
    fn rejects_relative_private_state_directories() {
        assert_eq!(
            PrivateStatePath::from_app_support_dir("relative/path").unwrap_err(),
            OpenMlsError::RelativeStateDirectory,
        );
    }

    #[test]
    fn keeps_wire_material_opaque() {
        let material = OpaqueMlsBytes::new(vec![1, 2, 3]).expect("non-empty material");
        assert_eq!(material.as_slice(), [1, 2, 3]);
        assert_eq!(
            OpaqueMlsBytes::new(vec![]).unwrap_err(),
            OpenMlsError::EmptyProtocolMaterial
        );
    }
}
