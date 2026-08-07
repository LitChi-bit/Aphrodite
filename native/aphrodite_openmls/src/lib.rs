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
    tls_codec::{Deserialize as TlsDeserialize, Serialize as TlsSerialize},
    BasicCredential, Ciphersuite, CredentialWithKey, GroupId, KeyPackage, KeyPackageBundle,
    KeyPackageIn, KeyPackageNewError, Lifetime, MlsGroup, MlsGroupCreateConfig, MlsGroupJoinConfig,
    MlsMessageBodyIn, MlsMessageIn, OpenMlsProvider, ProcessedMessageContent,
};

pub const MLS_CIPHERSUITE_NAME: &str =
    "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519";
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenMlsWelcomeBundle {
    commit: Vec<u8>,
    welcome: Vec<u8>,
    group_info: Option<Vec<u8>>,
}

impl OpenMlsWelcomeBundle {
    pub fn commit(&self) -> &[u8] {
        &self.commit
    }
    pub fn welcome(&self) -> &[u8] {
        &self.welcome
    }
    pub fn group_info(&self) -> Option<&[u8]> {
        self.group_info.as_deref()
    }
}

/// Public material produced when committing the locally persisted proposal queue.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenMlsCommitBundle {
    commit: Vec<u8>,
    welcome: Option<Vec<u8>>,
    group_info: Option<Vec<u8>>,
    epoch: u64,
}

impl OpenMlsCommitBundle {
    pub fn commit(&self) -> &[u8] {
        &self.commit
    }
    pub fn welcome(&self) -> Option<&[u8]> {
        self.welcome.as_deref()
    }
    pub fn group_info(&self) -> Option<&[u8]> {
        self.group_info.as_deref()
    }
    pub fn epoch(&self) -> u64 {
        self.epoch
    }
}

/// Public metadata accompanying a serialized MLS application message.
///
/// The header is the MLS authenticated data (AAD). It is intentionally public
/// and currently empty because Aphrodite does not add application AAD yet.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OpenMlsApplicationMessage {
    ciphertext: Vec<u8>,
    group_id: Vec<u8>,
    epoch: u64,
    header: Vec<u8>,
}

impl OpenMlsApplicationMessage {
    pub fn ciphertext(&self) -> &[u8] {
        &self.ciphertext
    }

    pub fn group_id(&self) -> &[u8] {
        &self.group_id
    }

    pub fn epoch(&self) -> u64 {
        self.epoch
    }

    pub fn header(&self) -> &[u8] {
        &self.header
    }
}

/// The result of applying authenticated MLS handshake material.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OpenMlsHandshakeResult {
    ProposalStored { epoch: u64 },
    CommitMerged { epoch: u64 },
}

impl OpenMlsHandshakeResult {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::ProposalStored { .. } => "proposal_stored",
            Self::CommitMerged { .. } => "commit_merged",
        }
    }

    pub fn epoch(&self) -> u64 {
        match self {
            Self::ProposalStored { epoch } | Self::CommitMerged { epoch } => *epoch,
        }
    }
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

    /// Creates and persists a new one-member MLS group for a conversation.
    ///
    /// The conversation ID is an application-assigned opaque identifier. It is
    /// never derived from user-visible names and must be globally unique.
    pub fn create_group(&self, conversation_id: impl AsRef<str>) -> Result<Vec<u8>, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        if MlsGroup::load(self.provider.storage(), &group_id)?.is_some() {
            return Err(OpenMlsError::GroupAlreadyExists);
        }

        let identity = self.require_device_identity()?;
        let signer = self.provider.read_device_signer(&identity)?;
        let group = MlsGroup::new_with_group_id(
            &self.provider,
            &signer,
            &MlsGroupCreateConfig::builder()
                .use_ratchet_tree_extension(true)
                .build(),
            group_id.clone(),
            identity.credential_with_key(),
        )
        .map_err(|error| OpenMlsError::GroupCreation(error.to_string()))?;
        let persisted = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupPersistenceMissing)?;
        debug_assert_eq!(persisted.group_id().as_slice(), group.group_id().as_slice());
        Ok(group_id.to_vec())
    }

    /// Encrypts an MLS application message using a persisted active group.
    ///
    /// The returned bytes are a public TLS-serialized MLS message. Private
    /// sender-ratchet state remains owned by the native storage provider.
    pub fn encrypt_application_message(
        &self,
        conversation_id: impl AsRef<str>,
        plaintext: &[u8],
    ) -> Result<OpenMlsApplicationMessage, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        if plaintext.is_empty() {
            return Err(OpenMlsError::EmptyApplicationMessage);
        }
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        let identity = self.require_device_identity()?;
        let signer = self.provider.read_device_signer(&identity)?;
        let message = group
            .create_message(&self.provider, &signer, plaintext)
            .map_err(|error| OpenMlsError::ApplicationMessageCreation(error.to_string()))?;
        let serialized = message
            .tls_serialize_detached()
            .map_err(OpenMlsError::TlsSerialization)?;
        let mut remaining = serialized.as_slice();
        let parsed = MlsMessageIn::tls_deserialize(&mut remaining)
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        if !remaining.is_empty() {
            return Err(OpenMlsError::TrailingProtocolMaterial);
        }
        let protocol_message = parsed
            .try_into_protocol_message()
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        Ok(OpenMlsApplicationMessage {
            ciphertext: serialized,
            group_id: protocol_message.group_id().to_vec(),
            epoch: protocol_message.epoch().as_u64(),
            header: Vec::new(),
        })
    }

    pub fn add_member(
        &self,
        conversation_id: impl AsRef<str>,
        key_package_bytes: &[u8],
    ) -> Result<OpenMlsWelcomeBundle, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        let mut serialized = key_package_bytes;
        let key_package = KeyPackageIn::tls_deserialize(&mut serialized)
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?
            .validate(self.provider.crypto(), Default::default())
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        if !serialized.is_empty() {
            return Err(OpenMlsError::TrailingProtocolMaterial);
        }
        let identity = self.require_device_identity()?;
        let signer = self.provider.read_device_signer(&identity)?;
        let (commit, welcome, group_info) = group
            .add_members(&self.provider, &signer, &[key_package])
            .map_err(|error| OpenMlsError::MemberAddition(error.to_string()))?;
        let commit = commit
            .tls_serialize_detached()
            .map_err(OpenMlsError::TlsSerialization)?;
        let welcome = welcome
            .tls_serialize_detached()
            .map_err(OpenMlsError::TlsSerialization)?;
        let group_info = group_info
            .map(|info| {
                info.tls_serialize_detached()
                    .map_err(OpenMlsError::TlsSerialization)
            })
            .transpose()?;
        group
            .merge_pending_commit(&self.provider)
            .map_err(|error| OpenMlsError::CommitMerge(error.to_string()))?;
        Ok(OpenMlsWelcomeBundle {
            commit,
            welcome,
            group_info,
        })
    }

    pub fn join_group(&self, welcome_bytes: &[u8]) -> Result<Vec<u8>, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let mut serialized = welcome_bytes;
        let message = MlsMessageIn::tls_deserialize(&mut serialized)
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        if !serialized.is_empty() {
            return Err(OpenMlsError::TrailingProtocolMaterial);
        }
        let welcome = match message.extract() {
            MlsMessageBodyIn::Welcome(welcome) => welcome,
            _ => return Err(OpenMlsError::ExpectedWelcome),
        };
        let staged = openmls::prelude::StagedWelcome::new_from_welcome(
            &self.provider,
            &MlsGroupJoinConfig::builder()
                .use_ratchet_tree_extension(true)
                .build(),
            welcome,
            None,
        )
        .map_err(|error| OpenMlsError::WelcomeProcessing(error.to_string()))?;
        let group = staged
            .into_group(&self.provider)
            .map_err(|error| OpenMlsError::WelcomeProcessing(error.to_string()))?;
        Ok(group.group_id().to_vec())
    }

    pub fn decrypt_application_message(
        &self,
        conversation_id: impl AsRef<str>,
        ciphertext: &[u8],
    ) -> Result<Vec<u8>, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        let mut serialized = ciphertext;
        let message = MlsMessageIn::tls_deserialize(&mut serialized)
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        if !serialized.is_empty() {
            return Err(OpenMlsError::TrailingProtocolMaterial);
        }
        let protocol_message = message
            .try_into_protocol_message()
            .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
        let processed = group
            .process_message(&self.provider, protocol_message)
            .map_err(|error| OpenMlsError::ApplicationMessageProcessing(error.to_string()))?;
        match processed.into_content() {
            ProcessedMessageContent::ApplicationMessage(message) => Ok(message.into_bytes()),
            _ => Err(OpenMlsError::ExpectedApplicationMessage),
        }
    }

    /// Applies authenticated MLS handshake material from the delivery service.
    ///
    /// Standalone proposals are persisted only after OpenMLS validates them.
    /// Commits are likewise merged only after OpenMLS returns a staged commit.
    /// Application messages must continue through `decrypt_application_message`.
    pub fn apply_handshake_message(
        &self,
        conversation_id: impl AsRef<str>,
        handshake_message: &[u8],
    ) -> Result<OpenMlsHandshakeResult, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        let protocol_message = protocol_message_from_tls(handshake_message)?;
        let processed = group
            .process_message(&self.provider, protocol_message)
            .map_err(|error| OpenMlsError::HandshakeMessageProcessing(error.to_string()))?;
        match processed.into_content() {
            ProcessedMessageContent::ProposalMessage(proposal) => {
                group
                    .store_pending_proposal(self.provider.storage(), *proposal)
                    .map_err(|error| OpenMlsError::ProposalStorage(error.to_string()))?;
                Ok(OpenMlsHandshakeResult::ProposalStored {
                    epoch: group.epoch().as_u64(),
                })
            }
            ProcessedMessageContent::StagedCommitMessage(commit) => {
                group
                    .merge_staged_commit(&self.provider, *commit)
                    .map_err(|error| OpenMlsError::CommitMerge(error.to_string()))?;
                Ok(OpenMlsHandshakeResult::CommitMerged {
                    epoch: group.epoch().as_u64(),
                })
            }
            _ => Err(OpenMlsError::ExpectedHandshakeMessage),
        }
    }

    /// Creates and merges a Commit covering the locally persisted proposal queue.
    ///
    /// The caller may transmit only the returned public MLS bytes. Any proposal
    /// store state, epoch secret, or staged commit remains in native SQLite.
    pub fn commit_pending_proposals(
        &self,
        conversation_id: impl AsRef<str>,
    ) -> Result<OpenMlsCommitBundle, OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        let identity = self.require_device_identity()?;
        let signer = self.provider.read_device_signer(&identity)?;
        let (commit, welcome, group_info) = group
            .commit_to_pending_proposals(&self.provider, &signer)
            .map_err(|error| OpenMlsError::CommitCreation(error.to_string()))?;
        let commit = commit
            .tls_serialize_detached()
            .map_err(OpenMlsError::TlsSerialization)?;
        let welcome = welcome
            .map(|message| {
                message
                    .tls_serialize_detached()
                    .map_err(OpenMlsError::TlsSerialization)
            })
            .transpose()?;
        let group_info = group_info
            .map(|info| {
                info.tls_serialize_detached()
                    .map_err(OpenMlsError::TlsSerialization)
            })
            .transpose()?;
        group
            .merge_pending_commit(&self.provider)
            .map_err(|error| OpenMlsError::CommitMerge(error.to_string()))?;
        Ok(OpenMlsCommitBundle {
            commit,
            welcome,
            group_info,
            epoch: group.epoch().as_u64(),
        })
    }

    /// Destroys all private MLS state owned by this device.
    ///
    /// This is intentionally device-local: it does not revoke the device in the
    /// server roster or alter any other device's state.
    pub fn destroy_device_state(&self) -> Result<(), OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_ids = self.provider.local_group_ids()?;
        for group_id in group_ids {
            let Some(mut group) = MlsGroup::load(self.provider.storage(), &group_id)? else {
                continue;
            };
            group
                .delete(self.provider.storage())
                .map_err(|error| OpenMlsError::GroupDeletion(error.to_string()))?;
        }
        self.provider
            .clear_device_private_state()
            .map_err(|error| OpenMlsError::DeviceStateDestruction(error.to_string()))?;
        *self
            .device_identity
            .write()
            .map_err(|_| OpenMlsError::IdentityLockPoisoned)? = None;
        Ok(())
    }

    pub fn remove_local_group(&self, conversation_id: impl AsRef<str>) -> Result<(), OpenMlsError> {
        let _operation = self
            .operation_lock
            .lock()
            .map_err(|_| OpenMlsError::OperationLockPoisoned)?;
        let group_id = group_id_from_conversation_id(conversation_id)?;
        let mut group = MlsGroup::load(self.provider.storage(), &group_id)?
            .ok_or(OpenMlsError::GroupNotFound)?;
        group
            .delete(self.provider.storage())
            .map_err(|error| OpenMlsError::GroupDeletion(error.to_string()))
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

        let identity = self.require_device_identity()?;
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

    fn require_device_identity(&self) -> Result<OpenMlsDeviceIdentity, OpenMlsError> {
        self.device_identity
            .read()
            .map_err(|_| OpenMlsError::IdentityLockPoisoned)?
            .clone()
            .ok_or(OpenMlsError::DeviceNotInitialized)
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

    fn local_group_ids(&self) -> Result<Vec<GroupId>, OpenMlsError> {
        let mut statement = self
            .identity_index
            .prepare("SELECT DISTINCT group_id FROM openmls_group_data")?;
        let ids = statement
            .query_map([], |row| row.get::<_, Vec<u8>>(0))?
            .map(|row| row.map(|bytes| GroupId::from_slice(&bytes)))
            .collect::<Result<Vec<_>, _>>()?;
        Ok(ids)
    }

    fn clear_device_private_state(&self) -> Result<(), OpenMlsError> {
        // MlsGroup::delete handles valid groups through the OpenMLS API. This
        // transaction also removes orphaned rows that cannot be loaded as a
        // group, so device destruction does not leave private MLS material.
        self.identity_index.execute_batch(
            "BEGIN IMMEDIATE;
             DELETE FROM openmls_group_data;
             DELETE FROM openmls_epoch_keys_pairs;
             DELETE FROM openmls_own_leaf_nodes;
             DELETE FROM openmls_proposals;
             DELETE FROM openmls_key_packages;
             DELETE FROM openmls_signature_keys;
             DELETE FROM openmls_encryption_keys;
             DELETE FROM openmls_psks;
             DELETE FROM aphrodite_device_identities;
             COMMIT;",
        )?;
        Ok(())
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

fn protocol_message_from_tls(
    serialized_message: &[u8],
) -> Result<openmls::prelude::ProtocolMessage, OpenMlsError> {
    let mut serialized = serialized_message;
    let message = MlsMessageIn::tls_deserialize(&mut serialized)
        .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))?;
    if !serialized.is_empty() {
        return Err(OpenMlsError::TrailingProtocolMaterial);
    }
    message
        .try_into_protocol_message()
        .map_err(|error| OpenMlsError::ProtocolMaterialParsing(error.to_string()))
}

fn group_id_from_conversation_id(
    conversation_id: impl AsRef<str>,
) -> Result<GroupId, OpenMlsError> {
    let conversation_id = conversation_id.as_ref().trim();
    if conversation_id.is_empty() {
        return Err(OpenMlsError::EmptyConversationId);
    }
    Ok(GroupId::from_slice(conversation_id.as_bytes()))
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
    #[error("conversation ID must not be empty")]
    EmptyConversationId,
    #[error("the MLS group already exists for this conversation")]
    GroupAlreadyExists,
    #[error("the MLS group was not found for this conversation")]
    GroupNotFound,
    #[error("new MLS group state was not persisted")]
    GroupPersistenceMissing,
    #[error("application message plaintext must not be empty")]
    EmptyApplicationMessage,
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
    #[error("failed to create MLS group: {0}")]
    GroupCreation(String),
    #[error("failed to create MLS application message: {0}")]
    ApplicationMessageCreation(String),
    #[error("failed to parse MLS protocol material: {0}")]
    ProtocolMaterialParsing(String),
    #[error("MLS protocol material contains trailing bytes")]
    TrailingProtocolMaterial,
    #[error("expected an MLS Welcome message")]
    ExpectedWelcome,
    #[error("failed to process MLS Welcome: {0}")]
    WelcomeProcessing(String),
    #[error("failed to add MLS member: {0}")]
    MemberAddition(String),
    #[error("failed to merge MLS Commit: {0}")]
    CommitMerge(String),
    #[error("failed to process MLS application message: {0}")]
    ApplicationMessageProcessing(String),
    #[error("expected an MLS application message")]
    ExpectedApplicationMessage,
    #[error("failed to process MLS handshake message: {0}")]
    HandshakeMessageProcessing(String),
    #[error("expected an MLS Proposal or Commit message")]
    ExpectedHandshakeMessage,
    #[error("failed to persist an MLS Proposal: {0}")]
    ProposalStorage(String),
    #[error("failed to create an MLS Commit: {0}")]
    CommitCreation(String),
    #[error("failed to delete local MLS group: {0}")]
    GroupDeletion(String),
    #[error("failed to destroy local device MLS state: {0}")]
    DeviceStateDestruction(String),
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
    fn creates_persists_and_restores_a_group_for_one_conversation() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let conversation_id = "conversation-group-persistence";

        let group_id = {
            let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
            engine
                .initialize_device("device-alpha")
                .expect("identity initializes");
            engine
                .create_group(conversation_id)
                .expect("group is created and persisted")
        };

        let reopened = NativeMlsEngine::open(&state_path).expect("engine reopens");
        reopened
            .initialize_device("device-alpha")
            .expect("identity restores");
        let ciphertext = reopened
            .encrypt_application_message(conversation_id, b"test payload")
            .expect("persisted group encrypts after reopen");
        let mut serialized = ciphertext.ciphertext().as_ref();
        let _parsed = openmls::prelude::MlsMessageIn::tls_deserialize(&mut serialized)
            .expect("ciphertext is valid TLS material");

        assert_eq!(group_id, conversation_id.as_bytes());
        assert_eq!(ciphertext.group_id(), conversation_id.as_bytes());
        assert_eq!(ciphertext.epoch(), 0);
        assert!(ciphertext.header().is_empty());
        assert!(serialized.is_empty());
    }

    #[test]
    fn rejects_invalid_group_creation_and_application_message_requests() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path = PrivateStatePath::from_app_support_dir(support_dir.path())
            .expect("temporary directory is absolute");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");

        assert!(matches!(
            engine.create_group("conversation-alpha"),
            Err(OpenMlsError::DeviceNotInitialized)
        ));
        engine
            .initialize_device("device-alpha")
            .expect("identity initializes");
        assert!(matches!(
            engine.create_group("  "),
            Err(OpenMlsError::EmptyConversationId)
        ));
        engine
            .create_group("conversation-alpha")
            .expect("group creates");
        assert!(matches!(
            engine.create_group("conversation-alpha"),
            Err(OpenMlsError::GroupAlreadyExists)
        ));
        assert!(matches!(
            engine.encrypt_application_message("conversation-missing", b"payload"),
            Err(OpenMlsError::GroupNotFound)
        ));
        assert!(matches!(
            engine.encrypt_application_message("conversation-alpha", b""),
            Err(OpenMlsError::EmptyApplicationMessage)
        ));
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
    fn completes_two_device_welcome_commit_and_message_round_trip() {
        let creator_dir = TempDir::new().expect("creator support directory");
        let joiner_dir = TempDir::new().expect("joiner support directory");
        let creator_path = PrivateStatePath::from_app_support_dir(creator_dir.path())
            .expect("creator directory is absolute");
        let joiner_path = PrivateStatePath::from_app_support_dir(joiner_dir.path())
            .expect("joiner directory is absolute");
        let conversation_id = "conversation-two-device";

        let creator = NativeMlsEngine::open(&creator_path).expect("creator opens");
        creator
            .initialize_device("device-creator")
            .expect("creator initializes");
        creator
            .create_group(conversation_id)
            .expect("creator group creates");

        let joiner = NativeMlsEngine::open(&joiner_path).expect("joiner opens");
        joiner
            .initialize_device("device-joiner")
            .expect("joiner initializes");
        let now = unix_timestamp().expect("clock is valid");
        let key_package = joiner
            .generate_key_packages(1, now + 3600)
            .expect("joiner key package generates")
            .pop()
            .expect("one key package exists");

        let bundle = creator
            .add_member(conversation_id, key_package.key_package())
            .expect("creator adds joiner and merges commit");
        assert!(!bundle.commit().is_empty());
        assert!(!bundle.welcome().is_empty());
        assert!(bundle.group_info().is_none() || !bundle.group_info().unwrap().is_empty());

        let joined_group_id = joiner
            .join_group(bundle.welcome())
            .expect("joiner consumes welcome");
        assert_eq!(joined_group_id, conversation_id.as_bytes());

        let ciphertext = creator
            .encrypt_application_message(conversation_id, b"hello from creator")
            .expect("creator encrypts");
        let plaintext = joiner
            .decrypt_application_message(conversation_id, &ciphertext)
            .expect("joiner decrypts");
        assert_eq!(plaintext, b"hello from creator");

        let response = joiner
            .encrypt_application_message(conversation_id, b"hello from joiner")
            .expect("joiner encrypts");
        let response_plaintext = creator
            .decrypt_application_message(conversation_id, &response)
            .expect("creator decrypts");
        assert_eq!(response_plaintext, b"hello from joiner");
    }

    #[test]
    fn persists_remote_proposals_and_merges_their_commit() {
        let creator_dir = TempDir::new().expect("creator support directory");
        let joiner_dir = TempDir::new().expect("joiner support directory");
        let creator_path = PrivateStatePath::from_app_support_dir(creator_dir.path())
            .expect("creator directory is absolute");
        let joiner_path = PrivateStatePath::from_app_support_dir(joiner_dir.path())
            .expect("joiner directory is absolute");
        let conversation_id = "conversation-handshake";

        let creator = NativeMlsEngine::open(&creator_path).expect("creator opens");
        creator
            .initialize_device("device-creator")
            .expect("creator initializes");
        creator
            .create_group(conversation_id)
            .expect("creator group creates");

        let joiner = NativeMlsEngine::open(&joiner_path).expect("joiner opens");
        joiner
            .initialize_device("device-joiner")
            .expect("joiner initializes");
        let now = unix_timestamp().expect("clock is valid");
        let key_package = joiner
            .generate_key_packages(1, now + 3600)
            .expect("joiner key package generates")
            .pop()
            .expect("one key package exists");
        let welcome = creator
            .add_member(conversation_id, key_package.key_package())
            .expect("creator adds joiner");
        joiner
            .join_group(welcome.welcome())
            .expect("joiner consumes welcome");

        let leave_proposal = {
            let group_id = group_id_from_conversation_id(conversation_id).expect("group id");
            let mut group = MlsGroup::load(joiner.provider.storage(), &group_id)
                .expect("group loads")
                .expect("group exists");
            let identity = joiner.require_device_identity().expect("joiner identity");
            let signer = joiner
                .provider
                .read_device_signer(&identity)
                .expect("joiner signer");
            group
                .leave_group(&joiner.provider, &signer)
                .expect("leave proposal creates")
                .tls_serialize_detached()
                .expect("proposal serializes")
        };

        assert_eq!(
            creator
                .apply_handshake_message(conversation_id, &leave_proposal)
                .expect("creator stores proposal"),
            OpenMlsHandshakeResult::ProposalStored { epoch: 1 }
        );
        let commit = creator
            .commit_pending_proposals(conversation_id)
            .expect("creator commits proposal");
        assert_eq!(commit.epoch(), 2);
        assert!(!commit.commit().is_empty());
        assert_eq!(
            joiner
                .apply_handshake_message(conversation_id, commit.commit())
                .expect("joiner merges commit"),
            OpenMlsHandshakeResult::CommitMerged { epoch: 2 }
        );
        assert!(matches!(
            joiner.encrypt_application_message(conversation_id, b"after removal"),
            Err(OpenMlsError::ApplicationMessageCreation(_))
        ));
    }

    #[test]
    fn destroys_all_local_device_state_and_requires_reinitialization() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path =
            PrivateStatePath::from_app_support_dir(support_dir.path()).expect("state path");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
        engine
            .initialize_device("device-destroy")
            .expect("identity initializes");
        let now = unix_timestamp().expect("clock is valid");
        engine
            .generate_key_packages(1, now + 3600)
            .expect("key package generates");
        engine
            .create_group("conversation-destroy")
            .expect("group creates");
        engine
            .destroy_device_state()
            .expect("device state destroys");
        assert!(matches!(
            engine.generate_key_packages(1, now + 3600),
            Err(OpenMlsError::DeviceNotInitialized)
        ));
        assert!(matches!(
            engine.encrypt_application_message("conversation-destroy", b"payload"),
            Err(OpenMlsError::GroupNotFound)
        ));

        let inspection = Connection::open(state_path.as_path()).expect("database reopens");
        for table in [
            "openmls_group_data",
            "openmls_epoch_keys_pairs",
            "openmls_own_leaf_nodes",
            "openmls_proposals",
            "openmls_key_packages",
            "openmls_signature_keys",
            "openmls_encryption_keys",
            "openmls_psks",
            "aphrodite_device_identities",
        ] {
            let count: i64 = inspection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get(0)
                })
                .expect("private state table is readable");
            assert_eq!(count, 0, "{table} must be empty after destruction");
        }

        let reopened = NativeMlsEngine::open(&state_path).expect("provider reopens");
        assert!(reopened.initialize_device("device-destroy").is_ok());
        let identities: i64 = inspection
            .query_row(
                "SELECT COUNT(*) FROM aphrodite_device_identities",
                [],
                |row| row.get(0),
            )
            .expect("identity table is readable");
        assert_eq!(identities, 1);
    }

    #[test]
    fn removes_local_group_state_and_rejects_follow_up_operations() {
        let support_dir = TempDir::new().expect("temporary support directory");
        let state_path =
            PrivateStatePath::from_app_support_dir(support_dir.path()).expect("state path");
        let engine = NativeMlsEngine::open(&state_path).expect("engine opens");
        engine
            .initialize_device("device-delete")
            .expect("identity initializes");
        engine
            .create_group("conversation-delete")
            .expect("group creates");
        engine
            .remove_local_group("conversation-delete")
            .expect("group deletes");
        assert!(matches!(
            engine.encrypt_application_message("conversation-delete", b"payload"),
            Err(OpenMlsError::GroupNotFound)
        ));
        assert!(matches!(
            engine.remove_local_group("conversation-delete"),
            Err(OpenMlsError::GroupNotFound)
        ));
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
