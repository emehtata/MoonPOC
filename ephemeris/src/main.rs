use moon_ephemeris::{sun_from_moon, to_json, UtcTime, DEFAULT_UTC};
use std::io::Write;
use std::process::ExitCode;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// `--stream`: one compact JSON line per second for the current UTC second, until stdout closes.
fn stream() -> ExitCode {
    let mut out = std::io::stdout().lock();
    let mut last = 0u64;
    loop {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
        let secs = now.as_secs();
        if secs != last {
            last = secs;
            let utc = UtcTime::from_unix(secs);
            let line = to_json(&utc, &sun_from_moon(&utc)).replace("\n  ", "").replace('\n', "");
            // Rust ignores SIGPIPE, so a closed stdout shows up here as a write error.
            if writeln!(out, "{line}").and_then(|_| out.flush()).is_err() {
                return ExitCode::SUCCESS;
            }
        }
        std::thread::sleep(Duration::from_nanos(1_000_000_000 - u64::from(now.subsec_nanos())));
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() == 1 && args[0] == "--stream" {
        return stream();
    }
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
