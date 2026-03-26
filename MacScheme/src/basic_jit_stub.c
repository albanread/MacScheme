// MacScheme does not run the FasterBASIC JIT executor directly.
// The graphics bridge references basic_jit_stop() for its original host,
// so we provide a no-op symbol to satisfy linking.
void basic_jit_stop(void) {}
