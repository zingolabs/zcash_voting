//! The built-in [`DelegationDriver`] implementation over the wallet-database
//! seam.
//!
//! The trait itself lives in [`crate::delegation_driver`] so the round
//! executor can reference it in sqlite-free builds; this module provides the
//! only in-crate implementation, over [`DelegationPipeline`].

use crate::{
    delegate::{PreparedSigner, SignedDelegationBundle},
    pir::PirFleet,
    round::VotingDb,
    types::{DelegationProgressReporter, Network, VotingError, VotingHotkey, VotingHotkeyTarget},
};

use super::{DelegationPipeline, WalletDbOpener};
pub use crate::delegation_driver::{DelegationDriver, DelegationSigner};

impl<W: WalletDbOpener> DelegationDriver for DelegationPipeline<W> {
    fn round_id(&self) -> &str {
        DelegationPipeline::round_id(self)
    }

    fn network(&self) -> Network {
        DelegationPipeline::network(self)
    }

    fn delegation_target(&self) -> Option<VotingHotkeyTarget> {
        self.hotkey.as_ref().map(VotingHotkey::delegation_target)
    }

    fn wallet_id(&self) -> &str {
        DelegationPipeline::wallet_id(self)
    }

    fn shares_database_with(&self, database: &VotingDb) -> bool {
        self.voting_db.shares_connection_with(database)
    }

    fn prepare_blocking(
        &self,
        bundle_index: u32,
        pir: &PirFleet,
        progress: &dyn DelegationProgressReporter,
    ) -> Result<crate::delegate::DelegationProofStatus, VotingError> {
        self.ensure_proof(bundle_index, pir, progress)
    }

    fn prepare_blocking_observed(
        &self,
        bundle_index: u32,
        pir: &PirFleet,
        progress: &dyn DelegationProgressReporter,
        observations: &crate::ObservationScope,
    ) -> Result<crate::delegate::DelegationProofStatus, VotingError> {
        self.observe_ensure_proof(bundle_index, pir, progress, observations)
    }

    fn prove_and_sign_blocking(
        &self,
        bundle_index: u32,
        signer: &DelegationSigner,
        pir: &PirFleet,
        progress: &dyn DelegationProgressReporter,
    ) -> Result<SignedDelegationBundle, VotingError> {
        self.execute_prove_and_sign_blocking(
            bundle_index,
            signer,
            pir,
            progress,
            &crate::ObservationScope::disabled(),
        )
    }

    fn prove_and_sign_blocking_observed(
        &self,
        bundle_index: u32,
        signer: &DelegationSigner,
        pir: &PirFleet,
        progress: &dyn DelegationProgressReporter,
        observations: &crate::ObservationScope,
    ) -> Result<SignedDelegationBundle, VotingError> {
        DelegationPipeline::execute_prove_and_sign_blocking(
            self,
            bundle_index,
            signer,
            pir,
            progress,
            observations,
        )
    }

    fn resign_blocking(
        &self,
        bundle_index: u32,
        signer: &DelegationSigner,
    ) -> Result<[u8; 64], VotingError> {
        self.resign_blocking_observed(bundle_index, signer, &crate::ObservationScope::disabled())
    }

    fn resign_blocking_observed(
        &self,
        bundle_index: u32,
        signer: &DelegationSigner,
        observations: &crate::ObservationScope,
    ) -> Result<[u8; 64], VotingError> {
        let prepared = self.execute_prepare(bundle_index, observations)?;
        let PreparedSigner::Signature { sig, .. } =
            self.spend_auth_signature(&prepared, bundle_index, signer, observations)?;
        Ok(sig)
    }
}
