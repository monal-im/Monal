use std::{backtrace::Backtrace, panic, thread}; // TODO: move this into its own rust lib?

pub fn install_panic_handler<F: Fn(String, String) + Send + Sync + 'static>(rust_panic_handler: F) {
    let old_handler = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        eprintln!("RUST panic");

        // format panic info (taken from https://docs.rs/log-panics/latest/src/log_panics/lib.rs.html#1-165)
        let thread = thread::current();
        let thread = thread.name().unwrap_or("<unnamed>");
        let msg = match info.payload().downcast_ref::<&'static str>() {
            Some(s) => *s,
            None => match info.payload().downcast_ref::<String>() {
                Some(s) => &**s,
                None => "Box<Any>",
            },
        };
        let text = match info.location() {
            Some(location) => {
                format!(
                    "thread '{}' panicked with '{}': {}:{}",
                    thread,
                    msg,
                    location.file(),
                    location.line()
                )
            }
            None => format!("thread '{}' panicked with '{}'", thread, msg),
        };
        let backtrace = format!("{}", Backtrace::force_capture());
        eprintln!("RUST panic: {}", text);
        eprintln!("RUST backtrace: {}", backtrace);

        // call swift panic handler
        rust_panic_handler(text.clone(), backtrace.clone());

        // call original panic handler (should be never reached if a non-returning callback for rust_panic_handler() is set)
        old_handler(info);
    }));
}
