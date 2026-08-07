//! Native OpenMLS boundary for Aphrodite.
//!
//! This crate owns MLS private state. Flutter and the delivery service exchange
//! only serialized MLS protocol bytes and public metadata.

use std::{
    path::{Path, PathBuf},
    sync::{Mutex, RwLock},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use openmls::prelude::{
    tls_codec::Serialize as TlsSerialize, BasicCredential, Ciphersuite, CredentialWithKey,
    KeyPackage, KeyPackageBundle, KeyPackageNewError, Lifetime, OpenMlsProvider,
};
use openmls_basic_credential::SignatureKeyPair;
use openmls_rust_crypto::RustCrypto;
use openmls_sqlite_storage::{Codec, Connection, SqliteStorageProvider};
use openmls_traits::{signatures::Signer, types::CryptoError};
use serde::Serialize;
use thiserror::Error;

pub mod ffi;

/// The supported RFC 9420 mandatory-to-implement ciphersuite.
pub const CIPHERSUITE: Ciphersuite = Ciphersuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

const DEVICE_IDENTITIES_TABLE: &str = "aphrodite_device_identities";
const KEY_PACKAGE_SIGNATURE_LABEL: &[u8] = b"Aphrodite KeyPackage v1\0";
const MAX_KEY_PACKAGE_BATCH_SIZE: usize = 20;
const MAX_KEY_PACKAGE_LIFETIME_SECONDS: u64 = 60 * 60 * 24 * 84;

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

/// A public KeyPackage and an application-layer signature for server binding.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenMlsKeyPackage {
    ciphersuite: Ciphersuite,
    key_package: Vec<u8>,
    signature: Vec<u8>,
    expires_at: u64,
}

impl OpenMlsKeyPackage {
    pub fn ciphersuite(&self) -> Ciphersuite {
        self.ciphersuite
    }

    pub fn key_package(&self) -> &[u8] {
        &self.key_package
    }

    pub fn signature(&self) -> &[u8] {
        &self.signature
    }

    pub fn expires_at(&self) -> u64 {
        self.expires_at
    }
}

/// Public device identity material that may cross the native boundary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenMlsDeviceIdentity {
    device_id: String,
    credential_identity: Vec<u8>,
    signature_public_key: Vec<u8>,
}

impl OpenMlsDeviceIdentity {
    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    pub fn credential_identity(&self) -> &[u8] {
        &self.credential_identity
    }

    pub fn signature_public_key(&self) -> &[u8] {
        &self.signature_public_key
    }

    pub fn credential_with_key(&self) -> CredentialWithKey {
        CredentialWithKey {
            credential: BasicCredential::new(self.credential_identity.clone()).into(),
            signature_key: self.signature_public_key.clone().into(),
        }
    }
}

/// Native engine entry point intended for the future FFI layer.
///
/// It deliberately does not expose the provider, storage, or private signer.
pub struct NativeMlsEngine {
    provider: NativeMlsProvider,
    device_identity: RwLock<Option<OpenMlsDeviceIdentity>>,
    operation_lock: Mutex<()>,
}

impl NativeMlsEngine {
    pub fn open(state_path: &PrivateStatePath) -> Result<Self, OpenMlsError> {
        Ok(Self {
            provider: NativeMlsProvider::open(state_path)?,
            device_identity: RwLock::new(None),
            operation_lock: Mutex::new(()),
        })
    }

    pub fn initialize_device(
        &self,
        device_id: impl AsRef<str>,
    ) -> Result<OpenMlsDeviceIdentity, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let identity = self.provider.initialize_device(device_id)?;
        *self
            .device_identity
            .write()
            .map_err(|_| OpenMlsError::IdentityLockPoisoned)? = Some(identity.clone());
        Ok(identity)
    }

    pub fn generate_key_packages(
        &self,
        count: usize,
        expires_at: u64,
    ) -> Result<Vec<OpenMlsKeyPackage>, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        if count == 0 || count > MAX_KEY_PACKAGE_BATCH_SIZE {
            return Err(OpenMlsError::InvalidKeyPackageBatchSize);
        }
        let now = unix_timestamp()?;
        if expires_at <= now {
            return Err(OpenMlsError::KeyPackageAlreadyExpired);
        }
        let lifetime_seconds = expires_at - now;
        if lifetime_seconds > MAX_KEY_PACKAGE_LIFETIME_SECONDS {
            return Err(OpenMlsError::KeyPackageLifetimeTooLong);
        }

        let identity = self
            .device_identity
            .read()
            .map_err(|_| OpenMlsError::IdentityLockPoisoned)?
            .clone()
            .ok_or(OpenMlsError::DeviceNotInitialized)?;
        let signer = self.provider.read_device_signer(&identity)?;
        let credential_with_key = identity.credential_with_key();
        let lifetime = Lifetime::init(now.saturating_sub(60 * 60), expires_at);
        let mut packages = Vec::with_capacity(count);

        for _ in 0..count {
            let bundle: KeyPackageBundle = KeyPackage::builder()
                .key_package_lifetime(lifetime)
                .build(
                    CIPHERSUITE,
                    &self.provider,
                    &signer,
                    credential_with_key.clone(),
                )
                .map_err(OpenMlsError::KeyPackageCreation)?;
            let key_package = bundle
                .key_package()
                .tls_serialize_detached()
                .map_err(OpenMlsError::TlsSerialization)?;
            let signature = sign_public_key_package(&signer, &key_package, expires_at)?;
            packages.push(OpenMlsKeyPackage {
                ciphersuite: CIPHERSUITE,
                key_package,
                signature,
                expires_at,
            });
        }

        Ok(packages)
    }
}

/// Persistent OpenMLS provider. Crypto and randomness are process-local, while
/// all OpenMLS private state is stored in the native SQLite database.
struct NativeMlsProvider {
    crypto: RustCrypto,
    storage: SqliteStorageProvider<JsonCodec, Connection>,
    identity_index: Connection,
}

impl NativeMlsProvider {
    fn open(state_path: &PrivateStatePath) -> Result<Self, OpenMlsError> {
        let storage_connection = Connection::open(state_path.as_path())?;
        configure_connection(&storage_connection)?;
        let mut storage = SqliteStorageProvider::<JsonCodec, _>::new(storage_connection);
        storage
            .run_migrations()
            .map_err(|error| OpenMlsError::StorageMigration(error.to_string()))?;

        let identity_index = Connection::open(state_path.as_path())?;
        configure_connection(&identity_index)?;
        identity_index.execute_batch(&format!(
            "CREATE TABLE IF NOT EXISTS {DEVICE_IDENTITIES_TABLE} (\
                device_id TEXT PRIMARY KEY NOT NULL,\
                credential_identity BLOB NOT NULL,\
                signature_public_key BLOB NOT NULL\
            );"
        ))?;

        Ok(Self {
            crypto: RustCrypto::default(),
            storage,
            identity_index,
        })
    }

    /// Returns the existing device identity or creates and persists one.
    ///
    /// Only public identity material is returned. The signature private key is
    /// serialized exclusively by the OpenMLS storage provider.
    fn initialize_device(
        &self,
        device_id: impl AsRef<str>,
    ) -> Result<OpenMlsDeviceIdentity, OpenMlsError> {
        let device_id = device_id.as_ref().trim();
        if device_id.is_empty() {
            return Err(OpenMlsError::EmptyDeviceId);
        }

        if let Some(identity) = self.read_device_identity(device_id)? {
            let signer = SignatureKeyPair::read(
                self.storage(),
                identity.signature_public_key(),
                CIPHERSUITE.signature_algorithm(),
            )
            .ok_or(OpenMlsError::MissingSignatureKeyPair)?;
            debug_assert_eq!(signer.public(), identity.signature_public_key());
            return Ok(identity);
        }

        let signer = SignatureKeyPair::new(CIPHERSUITE.signature_algorithm())?;
        signer.store(self.storage())?;
        let identity = OpenMlsDeviceIdentity {
            device_id: device_id.to_owned(),
            credential_identity: device_id.as_bytes().to_vec(),
            signature_public_key: signer.to_public_vec(),
        };

        match self.store_device_identity(&identity) {
            Ok(true) => Ok(identity),
            Ok(false) => {
                SignatureKeyPair::delete(
                    self.storage(),
                    identity.signature_public_key(),
                    CIPHERSUITE.signature_algorithm(),
                )?;
                let winner = self
                    .read_device_identity(device_id)?
                    .ok_or(OpenMlsError::IdentityInitializationRace)?;
                self.read_device_signer(&winner)?;
                Ok(winner)
            }
            Err(error) => {
                SignatureKeyPair::delete(
                    self.storage(),
                    identity.signature_public_key(),
                    CIPHERSUITE.signature_algorithm(),
                )?;
                Err(error)
            }
        }
    }

    fn read_device_signer(
        &self,
        identity: &OpenMlsDeviceIdentity,
    ) -> Result<SignatureKeyPair, OpenMlsError> {
        SignatureKeyPair::read(
            self.storage(),
            identity.signature_public_key(),
            CIPHERSUITE.signature_algorithm(),
        )
        .ok_or(OpenMlsError::MissingSignatureKeyPair)
    }

    fn read_device_identity(
        &self,
        device_id: &str,
    ) -> Result<Option<OpenMlsDeviceIdentity>, OpenMlsError> {
        let mut statement = self.identity_index.prepare(&format!(
            "SELECT credential_identity, signature_public_key \
             FROM {DEVICE_IDENTITIES_TABLE} WHERE device_id = ?1"
        ))?;
        let mut rows = statement.query([device_id])?;
        let Some(row) = rows.next()? else {
            return Ok(None);
        };

        Ok(Some(OpenMlsDeviceIdentity {
            device_id: device_id.to_owned(),
            credential_identity: row.get(0)?,
            signature_public_key: row.get(1)?,
        }))
    }

    fn store_device_identity(
        &self,
        identity: &OpenMlsDeviceIdentity,
    ) -> Result<bool, OpenMlsError> {
        let inserted = self.identity_index.execute(
            &format!(
                "INSERT OR IGNORE INTO {DEVICE_IDENTITIES_TABLE} \
                 (device_id, credential_identity, signature_public_key) \
                 VALUES (?1, ?2, ?3)"
            ),
            (
                identity.device_id(),
                identity.credential_identity(),
                identity.signature_public_key(),
            ),
        )?;
        Ok(inserted == 1)
    }
}

fn unix_timestamp() -> Result<u64, OpenMlsError> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| OpenMlsError::SystemClockBeforeEpoch)?
        .as_secs())
}

fn sign_public_key_package(
    signer: &SignatureKeyPair,
    key_package: &[u8],
    expires_at: u64,
) -> Result<Vec<u8>, OpenMlsError> {
    let mut payload = Vec::with_capacity(
        KEY_PACKAGE_SIGNATURE_LABEL.len() + key_package.len() + std::mem::size_of::<u64>(),
    );
    payload.extend_from_slice(KEY_PACKAGE_SIGNATURE_LABEL);
    payload.extend_from_slice(key_package);
    payload.extend_from_slice(&expires_at.to_be_bytes());
    signer
        .sign(&payload)
        .map_err(|_| OpenMlsError::KeyPackageApplicationSignature)
}

fn configure_connection(connection: &Connection) -> Result<(), rusqlite::Error> {
    connection.busy_timeout(Duration::from_secs(5))?;
    connection.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
    Ok(())
}

impl OpenMlsProvider for NativeMlsProvider {
    type CryptoProvider = RustCrypto;
    type RandProvider = RustCrypto;
    type StorageProvider = SqliteStorageProvider<JsonCodec, Connection>;

    fn storage(&self) -> &Self::StorageProvider {
        &self.storage
    }

    fn crypto(&self) -> &Self::CryptoProvider {
        &self.crypto
    }

    fn rand(&self) -> &Self::RandProvider {
        &self.crypto
    }
}

#[derive(Default)]
pub struct JsonCodec;

impl Codec for JsonCodec {
    type Error = serde_json::Error;

    fn to_vec<T: Serialize>(value: &T) -> Result<Vec<u8>, Self::Error> {
        serde_json::to_vec(value)
    }

    fn from_slice<T: serde::de::DeserializeOwned>(slice: &[u8]) -> Result<T, Self::Error> {
        serde_json::from_slice(slice)
    }
}

/// Opaque wire material received from or sent to the delivery service.
///
/// It intentionally does not expose MLS private keys, group secrets, or a
/// ratchet tree. Their storage and use remain inside the native engine.
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

#[derive(Debug, Error)]
pub enum OpenMlsError {
    #[error("MLS protocol material must not be empty")]
    EmptyProtocolMaterial,
    #[error("the native MLS state directory must be absolute")]
    RelativeStateDirectory,
    #[error("device ID must not be empty")]
    EmptyDeviceId,
    #[error("the persisted device identity has no matching signature key pair")]
    MissingSignatureKeyPair,
    #[error("device identity initialization lost a race without a persisted winner")]
    IdentityInitializationRace,
    #[error("device identity must be initialized before generating KeyPackages")]
    DeviceNotInitialized,
    #[error("KeyPackage batch size must be between 1 and 20")]
    InvalidKeyPackageBatchSize,
    #[error("KeyPackage expiration must be in the future")]
    KeyPackageAlreadyExpired,
    #[error("KeyPackage lifetime must not exceed 84 days")]
    KeyPackageLifetimeTooLong,
    #[error("the system clock is before the Unix epoch")]
    SystemClockBeforeEpoch,
    #[error("device identity lock was poisoned")]
    IdentityLockPoisoned,
    #[error("native OpenMLS operation lock was poisoned")]
    OperationLockPoisoned,
    #[error("failed to create OpenMLS KeyPackage: {0}")]
    KeyPackageCreation(KeyPackageNewError),
    #[error("failed to serialize public OpenMLS protocol material: {0}")]
    TlsSerialization(openmls::prelude::Error),
    #[error("failed to sign the public KeyPackage envelope")]
    KeyPackageApplicationSignature,
    #[error("failed to initialize OpenMLS storage: {0}")]
    StorageMigration(String),
    #[error("OpenMLS SQLite storage failed: {0}")]
    Storage(#[from] rusqlite::Error),
    #[error("OpenMLS cryptography failed: {0:?}")]
    Crypto(CryptoError),
}

impl From<CryptoError> for OpenMlsError {
    fn from(error: CryptoError) -> Self {
        Self::Crypto(error)
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Barrier};

    use openmls::prelude::{tls_codec::Deserialize as TlsDeserialize, OpenMlsCrypto};

    use super::*;
    use tempfile::TempDir;

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
        assert!(matches!(
            PrivateStatePath::from_app_support_dir("relative/path"),
            Err(OpenMlsError::RelativeStateDirectory)
        ));
    }

    #[test]
    fn opens_provider_and_runs_storage_migrations() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");

        NativeMlsProvider::open(&state_path).expect("provider opens");
        let inspection = Connection::open(state_path.as_path()).expect("database reopens");
        let migrations: i64 = inspection
            .query_row(
                "SELECT COUNT(*) FROM openmls_sqlite_storage_migrations",
                [],
                |row| row.get(0),
            )
            .expect("migration table is readable");
        let mut columns = inspection
            .prepare("PRAGMA table_info(aphrodite_device_identities)")
            .expect("identity table schema is readable");
        let column_names: Vec<String> = columns
            .query_map([], |row| row.get(1))
            .expect("identity columns are queryable")
            .collect::<Result<_, _>>()
            .expect("identity columns are valid");

        assert!(migrations > 0);
        assert_eq!(
            column_names,
            ["device_id", "credential_identity", "signature_public_key"]
        );
        assert!(state_path.as_path().is_file());
    }

    #[test]
    fn creates_and_restores_the_same_device_identity() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");

        let original = {
            let provider = NativeMlsProvider::open(&state_path).expect("provider opens");
            let identity = provider
                .initialize_device("device-alpha")
                .expect("identity is created");
            provider
                .read_device_signer(&identity)
                .expect("private signer is stored");
            identity
        };

        let reopened = NativeMlsProvider::open(&state_path).expect("provider reopens");
        let restored = reopened
            .initialize_device("device-alpha")
            .expect("identity is restored");

        assert_eq!(restored, original);
        assert_eq!(
            restored.credential_with_key().signature_key.as_slice(),
            restored.signature_public_key()
        );
        reopened
            .read_device_signer(&restored)
            .expect("private signer remains available after reopen");
    }

    #[test]
    fn concurrent_engines_converge_on_one_device_identity() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let first_engine = NativeMlsEngine::open(&state_path).expect("first engine opens");
        let second_engine = NativeMlsEngine::open(&state_path).expect("second engine opens");
        let barrier = Arc::new(Barrier::new(2));
        let first_barrier = Arc::clone(&barrier);
        let second_barrier = Arc::clone(&barrier);

        let first = std::thread::spawn(move || {
            first_barrier.wait();
            first_engine
                .initialize_device("device-shared")
                .expect("first initialization succeeds")
        });
        let second = std::thread::spawn(move || {
            second_barrier.wait();
            second_engine
                .initialize_device("device-shared")
                .expect("second initialization succeeds")
        });

        let first_identity = first.join().expect("first thread completes");
        let second_identity = second.join().expect("second thread completes");
        assert_eq!(first_identity, second_identity);

        let reopened = NativeMlsProvider::open(&state_path).expect("provider reopens");
        reopened
            .read_device_signer(&first_identity)
            .expect("winning signer is persisted");
    }

    #[test]
    fn requires_initialized_device_before_generating_key_packages() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
        let now = unix_timestamp().expect("clock is valid");

        assert!(matches!(
            engine.generate_key_packages(1, now + 60),
            Err(OpenMlsError::DeviceNotInitialized)
        ));
    }

    #[test]
    fn validates_key_package_batch_and_lifetime() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
        engine
            .initialize_device("device-alpha")
            .expect("identity initializes");
        let now = unix_timestamp().expect("clock is valid");

        assert!(matches!(
            engine.generate_key_packages(0, now + 60),
            Err(OpenMlsError::InvalidKeyPackageBatchSize)
        ));
        assert!(matches!(
            engine.generate_key_packages(MAX_KEY_PACKAGE_BATCH_SIZE + 1, now + 60),
            Err(OpenMlsError::InvalidKeyPackageBatchSize)
        ));
        assert!(matches!(
            engine.generate_key_packages(1, now),
            Err(OpenMlsError::KeyPackageAlreadyExpired)
        ));
        assert!(matches!(
            engine.generate_key_packages(1, now + MAX_KEY_PACKAGE_LIFETIME_SECONDS + 1),
            Err(OpenMlsError::KeyPackageLifetimeTooLong)
        ));
    }

    #[test]
    fn generates_public_key_packages_and_persists_private_bundles() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
        engine
            .initialize_device("device-alpha")
            .expect("identity initializes");
        let now = unix_timestamp().expect("clock is valid");
        let packages = engine
            .generate_key_packages(3, now + 3600)
            .expect("key packages generate");

        assert_eq!(packages.len(), 3);
        assert!(packages
            .iter()
            .all(|package| !package.key_package().is_empty() && !package.signature().is_empty()));
        assert!(packages
            .iter()
            .all(|package| package.ciphersuite() == CIPHERSUITE));
        assert!(packages
            .windows(2)
            .all(|pair| pair[0].key_package() != pair[1].key_package()));

        let identity = engine
            .device_identity
            .read()
            .expect("identity lock is healthy")
            .clone()
            .expect("identity exists");
        for package in &packages {
            let mut serialized = package.key_package();
            let parsed = openmls::prelude::KeyPackageIn::tls_deserialize(&mut serialized)
                .expect("public key package is valid TLS material");
            assert!(!parsed
                .tls_serialize_detached()
                .expect("re-serializes")
                .is_empty());
            let mut signed_payload = Vec::new();
            signed_payload.extend_from_slice(KEY_PACKAGE_SIGNATURE_LABEL);
            signed_payload.extend_from_slice(package.key_package());
            signed_payload.extend_from_slice(&package.expires_at().to_be_bytes());
            engine
                .provider
                .crypto()
                .verify_signature(
                    CIPHERSUITE.signature_algorithm(),
                    &signed_payload,
                    identity.signature_public_key(),
                    package.signature(),
                )
                .expect("application signature verifies");
        }

        let inspection = Connection::open(state_path.as_path()).expect("database reopens");
        let stored: i64 = inspection
            .query_row("SELECT COUNT(*) FROM openmls_key_packages", [], |row| {
                row.get(0)
            })
            .expect("stored key packages are queryable");
        assert_eq!(stored, 3);
    }

    #[test]
    fn creates_distinct_identities_for_distinct_devices() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let provider = NativeMlsProvider::open(&state_path).expect("provider opens");

        let first = provider
            .initialize_device("device-alpha")
            .expect("first identity is created");
        let second = provider
            .initialize_device("device-beta")
            .expect("second identity is created");

        assert_ne!(first.signature_public_key(), second.signature_public_key());
        assert_ne!(first.credential_identity(), second.credential_identity());
    }

    #[test]
    fn rejects_empty_device_ids() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let provider = NativeMlsProvider::open(&state_path).expect("provider opens");

        assert!(matches!(
            provider.initialize_device("   "),
            Err(OpenMlsError::EmptyDeviceId)
        ));
    }

    #[test]
    fn keeps_wire_material_opaque() {
        let material = OpaqueMlsBytes::new(vec![1, 2, 3]).expect("non-empty material");
        assert_eq!(material.as_slice(), [1, 2, 3]);
        assert!(matches!(
            OpaqueMlsBytes::new(vec![]),
            Err(OpenMlsError::EmptyProtocolMaterial)
        ));
    }
}
