//! Resolving a bundle's SpendAuth signature from the host's signer.
//!
//! The crate never holds seed material. A software wallet signs the prepared
//! request itself; a Keystone wallet supplies the device signature either from
//! memory or from the sidecar row it was stored in. The signer types live in
//! [`crate::delegation_driver`]; this module resolves them against the
//! pipeline's prepared bundles and sidecar rows.

use std::sync::Arc;

use crate::{
    delegate::{PreparedDelegationBundle, PreparedSigner, SignedDelegationBundle},
    types::VotingError,
};

use super::{DelegationPipeline, WalletDbOpener};
pub use crate::delegation_driver::{DelegationSigner, KeystoneSignatureSource, SpendAuthSigner};

impl<W: WalletDbOpener> DelegationPipeline<W> {
    /// Resolves the SpendAuth signature for a prepared bundle.
    ///
    /// Software signers receive the bundle's signing request and return the
    /// signature over its sighash. Keystone sources are validated to 64
    /// signature bytes and a 32-byte sighash; a `Stored` source that has no
    /// row for the bundle fails with [`VotingError::InvalidInput`].
    pub(super) fn spend_auth_signature(
        &self,
        prepared: &PreparedDelegationBundle,
        bundle_index: u32,
        signer: &DelegationSigner,
        observations: &crate::ObservationScope,
    ) -> Result<PreparedSigner, VotingError> {
        crate::proving_runtime::check_interruption()?;
        match signer {
            DelegationSigner::Software(signer) => {
                let request =
                    prepared.observe_signing_request(self.scoped_voting_db()?, observations)?;
                crate::proving_runtime::check_interruption()?;
                let sig = signer.sign(request)?;
                crate::proving_runtime::check_interruption()?;
                Ok(PreparedSigner::signature(sig, request.sighash))
            }
            DelegationSigner::Keystone(source) => self.keystone_signature(bundle_index, source),
        }
    }

    /// Resolves a Keystone signature for `bundle_index` from `source`.
    pub(super) fn keystone_signature(
        &self,
        bundle_index: u32,
        source: &KeystoneSignatureSource,
    ) -> Result<PreparedSigner, VotingError> {
        match source {
            KeystoneSignatureSource::Provided { sig, sighash } => {
                PreparedSigner::signature_from_bytes(sig, sighash)
            }
            KeystoneSignatureSource::Stored => {
                let record = self
                    .scoped_voting_db()?
                    .get_keystone_signatures(self.round_id())?
                    .into_iter()
                    .find(|record| record.bundle_index == bundle_index)
                    .ok_or_else(|| VotingError::InvalidInput {
                        message: format!("no stored Keystone signature for bundle {bundle_index}"),
                    })?;
                PreparedSigner::signature_from_bytes(&record.sig, &record.sighash)
            }
        }
    }

    /// Persists a host-provided Keystone signature once the bundle verified it.
    ///
    /// Software signatures and already-stored Keystone signatures need no
    /// write. For [`KeystoneSignatureSource::Provided`], the verified tuple
    /// (signature, sighash, randomized key) is stored under the bundle so a
    /// pass cancelled before chain dispatch, or a restart, resumes through
    /// [`KeystoneSignatureSource::Stored`]. Replaying the same tuple is
    /// idempotent. Storage atomically rechecks the bundle's current sighash
    /// and randomized key; missing or replaced signing context fails with
    /// [`VotingError::KeystoneSignatureConflict`].
    pub(super) fn retain_provided_keystone_signature(
        &self,
        signer: &DelegationSigner,
        signed: &SignedDelegationBundle,
    ) -> Result<(), VotingError> {
        if !matches!(
            signer,
            DelegationSigner::Keystone(KeystoneSignatureSource::Provided { .. })
        ) {
            return Ok(());
        }
        self.scoped_voting_db()?.store_keystone_signature(
            self.round_id(),
            signed.bundle_index,
            &signed.submission.spend_auth_sig,
            &signed.submission.sighash,
            &signed.submission.rk,
        )
    }
}
