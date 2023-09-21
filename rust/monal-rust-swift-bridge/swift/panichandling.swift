public typealias rust_panic_handler_t = @convention(block) (String, String) -> Void;
var panicHandler: Optional<rust_panic_handler_t> = nil;
public func setRustPanicHandler(_ ph: @escaping rust_panic_handler_t) {
    panicHandler = ph;
    install_panichandler();
}
public func rust_panic_handler(text: RustString, backtrace: RustString) {
    if let ph = panicHandler {
        ph(text.toString(), backtrace.toString());
    }
}
