//! Offline Moon data pipeline (spec: `docs/specs/moon-elevation-milestone-2.md`).
//!
//! Reads the LOLA `LDEM_64` DEM and the LROC WAC GMM tiles from a raw
//! directory, checks their metadata, and produces the elevation levels, the
//! albedo texture and `moon_data.json`.

pub mod albedo;
pub mod dem;
pub mod json;
pub mod ldem64;
pub mod normal;
pub mod pds;
pub mod pipeline;
pub mod sha256;

/// The Milestone 1 resampler, compiled from its original source file so that
/// the albedo stays pixel-identical to the Milestone 1 texture.
#[path = "../../texture-prep/src/resample.rs"]
pub mod resample;

/// Why a run stopped.
#[derive(Debug)]
pub enum Failure {
    /// Raw files that are not there: one message per file. Exit code 2.
    Missing(Vec<String>),
    /// A metadata check failed: one message naming the file and field. Exit code 2.
    Invalid(String),
    /// Anything else (I/O, decoding). Exit code 1.
    Other(String),
}

impl Failure {
    pub fn exit_code(&self) -> u8 {
        match self {
            Failure::Missing(_) | Failure::Invalid(_) => 2,
            Failure::Other(_) => 1,
        }
    }

    /// The error lines to print, one per entry.
    pub fn lines(&self) -> Vec<String> {
        match self {
            Failure::Missing(files) => {
                files.iter().map(|f| format!("error: missing source file: {f}")).collect()
            }
            Failure::Invalid(message) | Failure::Other(message) => vec![format!("error: {message}")],
        }
    }
}
