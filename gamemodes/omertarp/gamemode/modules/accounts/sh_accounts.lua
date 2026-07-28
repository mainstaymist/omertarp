-- Accounts module registration. All functionality is server-side (sv_ files);
-- clients learn nothing about accounts in M2 (design review §5), so this
-- shared stub is an empty shell in the client realm by design.
--
-- NOTE for module authors: this directory sorts BEFORE modules/database/, so
-- these files are included first — never reference Omerta.DB (or any sibling
-- module) at include time; the loader guarantees lifecycle order via
-- `depends`, not include order.

