# Private skill state is device-local in V1

The Skill Library and Novel Installations remain in the Flutter client's local
database and are not synchronized through the account. Authentication is
required for marketplace browsing, installation, and submission, while local
installed snapshots remain usable offline. This keeps unpublished user
instructions off the server and defers cross-device conflict resolution.
