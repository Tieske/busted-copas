# Force the Copas loop to exit via cancelall(), not natural drain

`copas.loop()` only returns once `copas.finished()` is true, which requires
every registered server/socket to be gone, not just every thread to be
done — confirmed against Copas source (`_reading`/`_writing` never empty
while a server is registered). A single spec that opens a `copas.addserver`
listener and forgets to close it would otherwise hang the interpreter
wrapper forever instead of failing with a message, since `addserver`-created
listeners never self-terminate.

Decided to call `copas.cancelall()` — Copas's own test-teardown primitive,
upstream-documented as "intended for test teardown only" — from inside the
interpreter wrapper's `addthread` body, immediately after Busted's `dofile`
returns. By that point Busted has already run every test and reported
results, so any leftover Copas state is by definition something a test
failed to clean up, not something a well-behaved run still needs. The
alternative (documenting the hang as a known limitation and leaving it to
adopters to avoid) was rejected: a silent infinite hang is a much worse
failure mode for a test runner than a clean, fast exit.
