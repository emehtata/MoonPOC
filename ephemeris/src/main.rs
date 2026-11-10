use moon_ephemeris::{sun_from_moon, to_json, UtcTime, DEFAULT_UTC};
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() > 1 {
        eprintln!("error: expected at most one argument (YYYY-MM-DDTHH:MM:SSZ)");
        return ExitCode::from(2);
    }
    let input = args.first().map(String::as_str).unwrap_or(DEFAULT_UTC);
    match UtcTime::parse(input) {
        Ok(utc) => {
            println!("{}", to_json(&utc, &sun_from_moon(&utc)));
            ExitCode::SUCCESS
        }
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(2)
        }
    }
}
