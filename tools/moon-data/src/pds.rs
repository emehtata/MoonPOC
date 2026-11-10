//! Minimal PDS3 detached-label reader for the LOLA gridded DEM (`LDEM_*.LBL`).
//!
//! Only `KEY = VALUE` statements are read. Quoted values may span lines,
//! `/* ... */` comments are skipped, and unit suffixes such as `<deg>` are
//! removed. Every value the pipeline needs comes from the label; nothing about
//! the grid is hard-coded.

use crate::Failure;

/// Byte order of the 16-bit signed samples.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ByteOrder {
    Little,
    Big,
}

/// Parsed `KEY = VALUE` statements in file order.
pub struct Label {
    entries: Vec<(String, String)>,
}

impl Label {
    pub fn parse(text: &str) -> Label {
        let mut entries = Vec::new();
        let mut lines = text.lines();
        while let Some(line) = lines.next() {
            let line = line.trim();
            if line.starts_with("/*") {
                continue;
            }
            let Some((key, value)) = line.split_once('=') else { continue };
            let key = key.trim().to_string();
            let mut value = value.trim().to_string();
            // A quoted value or a {...} set may continue on the following lines.
            for (open, close) in [('"', '"'), ('{', '}')] {
                if value.starts_with(open) {
                    while value.len() < 2 || !value.ends_with(close) {
                        match lines.next() {
                            Some(more) => {
                                value.push(' ');
                                value.push_str(more.trim());
                            }
                            None => break,
                        }
                    }
                }
            }
            entries.push((key, value));
        }
        Label { entries }
    }

    /// First value for `key`, without quotes and without a `<unit>` suffix.
    pub fn get(&self, key: &str) -> Option<String> {
        let raw = &self.entries.iter().find(|(k, _)| k == key)?.1;
        let mut value = raw.as_str();
        if let Some(pos) = value.find('<') {
            value = &value[..pos];
        }
        Some(value.trim().trim_matches(|c| c == '"' || c == '\'').trim().to_string())
    }
}

/// The validated description of the DEM raster.
#[derive(Clone, Debug, PartialEq)]
pub struct DemInfo {
    pub product_id: String,
    pub data_set_id: String,
    pub product_version_id: String,
    pub samples: usize,
    pub lines: usize,
    pub byte_order: ByteOrder,
    /// Metres per digital number.
    pub scaling_factor: f64,
    /// Radius of the reference sphere in metres.
    pub offset_m: f64,
    pub unit: String,
    pub pixels_per_degree: f64,
    pub projection: String,
    pub max_lat_deg: f64,
    pub min_lat_deg: f64,
    pub west_lon_deg: f64,
    pub east_lon_deg: f64,
    pub coordinate_system: String,
    /// Missing-data digital number, when the label declares one.
    pub missing_constant: Option<i16>,
    /// Keyword that declared the missing constant.
    pub missing_keyword: Option<String>,
}

/// Keywords a PDS3 label may use to mark missing samples.
const MISSING_KEYWORDS: [&str; 5] =
    ["MISSING_CONSTANT", "MISSING", "NULL_CONSTANT", "NULL", "CORE_NULL"];

fn field_error(file: &str, field: &str, message: impl std::fmt::Display) -> Failure {
    Failure::Invalid(format!("{file}: {field}: {message}"))
}

fn text(label: &Label, file: &str, key: &str) -> Result<String, Failure> {
    label.get(key).ok_or_else(|| field_error(file, key, "keyword missing from the label"))
}

fn number(label: &Label, file: &str, key: &str) -> Result<f64, Failure> {
    let value = text(label, file, key)?;
    match value.parse::<f64>() {
        Ok(v) if v.is_finite() => Ok(v),
        _ => Err(field_error(file, key, format!("'{value}' is not a number"))),
    }
}

fn count(label: &Label, file: &str, key: &str) -> Result<usize, Failure> {
    let value = text(label, file, key)?;
    match value.parse::<usize>() {
        Ok(v) if v > 0 => Ok(v),
        _ => Err(field_error(file, key, format!("'{value}' is not a positive integer"))),
    }
}

fn expect_text(label: &Label, file: &str, key: &str, expected: &str) -> Result<String, Failure> {
    let value = text(label, file, key)?;
    if value.eq_ignore_ascii_case(expected) {
        Ok(value)
    } else {
        Err(field_error(file, key, format!("found '{value}', need '{expected}'")))
    }
}

fn expect_number(label: &Label, file: &str, key: &str, expected: f64) -> Result<f64, Failure> {
    let value = number(label, file, key)?;
    if (value - expected).abs() <= 1e-9 {
        Ok(value)
    } else {
        Err(field_error(file, key, format!("found {value}, need {expected}")))
    }
}

/// Checks the label of a global simple-cylindrical 16-bit DEM and returns its
/// description. `file` is the label's file name, used in error messages.
/// `img_size` is the size in bytes of the raster file the label describes.
pub fn validate_dem_label(text_in: &str, file: &str, img_size: u64) -> Result<DemInfo, Failure> {
    let label = Label::parse(text_in);
    let samples = count(&label, file, "LINE_SAMPLES")?;
    let lines = count(&label, file, "LINES")?;

    let sample_type = text(&label, file, "SAMPLE_TYPE")?;
    let byte_order = match sample_type.as_str() {
        "LSB_INTEGER" | "PC_INTEGER" | "VAX_INTEGER" => ByteOrder::Little,
        "MSB_INTEGER" | "INTEGER" | "SUN_INTEGER" | "MAC_INTEGER" => ByteOrder::Big,
        other => {
            return Err(field_error(
                file,
                "SAMPLE_TYPE",
                format!("found '{other}', need a signed integer type (LSB_INTEGER or MSB_INTEGER)"),
            ))
        }
    };
    expect_number(&label, file, "SAMPLE_BITS", 16.0)?;

    let scaling_factor = number(&label, file, "SCALING_FACTOR")?;
    if scaling_factor <= 0.0 {
        return Err(field_error(file, "SCALING_FACTOR", "must be greater than 0"));
    }
    let offset_m = number(&label, file, "OFFSET")?;
    if offset_m <= 0.0 {
        return Err(field_error(file, "OFFSET", "must be greater than 0"));
    }
    let unit = text(&label, file, "UNIT")?;
    if !matches!(unit.to_ascii_uppercase().as_str(), "METER" | "METERS" | "M") {
        return Err(field_error(file, "UNIT", format!("found '{unit}', need METER")));
    }

    let projection = expect_text(&label, file, "MAP_PROJECTION_TYPE", "SIMPLE CYLINDRICAL")?;
    expect_text(&label, file, "POSITIVE_LONGITUDE_DIRECTION", "EAST")?;
    let pixels_per_degree = number(&label, file, "MAP_RESOLUTION")?;
    if pixels_per_degree <= 0.0 {
        return Err(field_error(file, "MAP_RESOLUTION", "must be greater than 0"));
    }
    let max_lat_deg = expect_number(&label, file, "MAXIMUM_LATITUDE", 90.0)?;
    let min_lat_deg = expect_number(&label, file, "MINIMUM_LATITUDE", -90.0)?;
    let west_lon_deg = expect_number(&label, file, "WESTERNMOST_LONGITUDE", 0.0)?;
    let east_lon_deg = expect_number(&label, file, "EASTERNMOST_LONGITUDE", 360.0)?;

    // Counts must agree with the resolution and the extents.
    let want_lines = (max_lat_deg - min_lat_deg) * pixels_per_degree;
    if (lines as f64 - want_lines).abs() > 1e-6 {
        return Err(field_error(
            file,
            "LINES",
            format!("{lines} does not match MAP_RESOLUTION x latitude extent = {want_lines}"),
        ));
    }
    let want_samples = (east_lon_deg - west_lon_deg) * pixels_per_degree;
    if (samples as f64 - want_samples).abs() > 1e-6 {
        return Err(field_error(
            file,
            "LINE_SAMPLES",
            format!("{samples} does not match MAP_RESOLUTION x longitude extent = {want_samples}"),
        ));
    }
    // Pixel registration: line 1 is the northernmost row and sample 1 starts at
    // the western extent. Offsets are counted from pixel (1, 1) to the map
    // origin at CENTER_LATITUDE / CENTER_LONGITUDE.
    let center_lat = number(&label, file, "CENTER_LATITUDE")?;
    let center_lon = number(&label, file, "CENTER_LONGITUDE")?;
    let want_line_offset = (max_lat_deg - center_lat) * pixels_per_degree - 0.5;
    expect_number(&label, file, "LINE_PROJECTION_OFFSET", want_line_offset)?;
    let want_sample_offset = (center_lon - west_lon_deg) * pixels_per_degree - 0.5;
    expect_number(&label, file, "SAMPLE_PROJECTION_OFFSET", want_sample_offset)?;
    // The reference sphere of the heights is the map sphere.
    expect_number(&label, file, "A_AXIS_RADIUS", offset_m / 1000.0)?;

    let want_size = samples as u64 * lines as u64 * 2;
    if img_size != want_size {
        let img = file.rsplit_once('.').map_or(file, |(stem, _)| stem);
        return Err(Failure::Invalid(format!(
            "{img}.IMG: file size: {img_size} bytes, but LINE_SAMPLES x LINES x 2 = {want_size} bytes"
        )));
    }

    let mut missing_constant = None;
    let mut missing_keyword = None;
    for key in MISSING_KEYWORDS {
        if let Some(value) = label.get(key) {
            let dn = value
                .parse::<i16>()
                .map_err(|_| field_error(file, key, format!("'{value}' is not a 16-bit integer")))?;
            missing_constant = Some(dn);
            missing_keyword = Some(key.to_string());
            break;
        }
    }

    Ok(DemInfo {
        product_id: text(&label, file, "PRODUCT_ID")?,
        data_set_id: text(&label, file, "DATA_SET_ID")?,
        product_version_id: text(&label, file, "PRODUCT_VERSION_ID")?,
        samples,
        lines,
        byte_order,
        scaling_factor,
        offset_m,
        unit,
        pixels_per_degree,
        projection,
        max_lat_deg,
        min_lat_deg,
        west_lon_deg,
        east_lon_deg,
        coordinate_system: text(&label, file, "COORDINATE_SYSTEM_NAME")?,
        missing_constant,
        missing_keyword,
    })
}
