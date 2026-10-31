//! Selected wallet and proving crates.
//!
//! This module re-exports the upstream librustzcash 0.31 crates under stable
//! internal names so the rest of the implementation stays dependency-layout
//! agnostic. `zcash_client_sqlite` is opt-in via the `wallet-db` feature.

pub use orchard;
pub use pczt;
pub use voting_crypto_deps::{halo2_gadgets, halo2_proofs, pasta_curves};
pub use zcash_client_backend;
/// The wallet-database crate, opt-in via the `wallet-db` feature so a consumer
/// that supplies its own wallet storage keeps `zcash_client_sqlite` — and the
/// rusqlite generation it pins — out of the resolve entirely.
#[cfg(feature = "wallet-db")]
pub use zcash_client_sqlite;
pub use zcash_keys;
pub use zcash_primitives;
pub use zcash_protocol;

/// Builds a non-expiring unified address containing only the supplied Orchard receiver.
pub(crate) fn orchard_unified_address(
    receiver: orchard::Address,
) -> Option<zcash_keys::address::UnifiedAddress> {
    zcash_keys::address::UnifiedAddress::from_receivers(Some(receiver), None, None, None, None)
}

/// Returns the canonical 32-byte scalar encoding of a PCZT spend-authorization randomizer.
pub(crate) fn spend_auth_randomizer_bytes(
    randomizer: &voting_crypto_deps::SpendAuthRandomizer,
) -> [u8; 32] {
    use pasta_curves::group::ff::PrimeField;
    randomizer.to_repr()
}

/// Encodes a viewing key for the selected network, returning unsupported encodings to callers.
pub(crate) fn encode_full_viewing_key<P: zcash_protocol::consensus::Parameters>(
    key: &zcash_keys::keys::UnifiedFullViewingKey,
    network: &P,
) -> Result<String, crate::types::VotingError> {
    key.encode(network)
        .map_err(|error| crate::types::VotingError::InvalidInput {
            message: format!("Cannot encode the unified full viewing key: {error:?}"),
        })
}
