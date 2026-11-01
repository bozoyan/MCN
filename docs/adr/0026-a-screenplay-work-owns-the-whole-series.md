# A screenplay Work owns the whole series

A Series Screenplay Work contains first-class Seasons, and each Season owns its Episodes. We chose this over one Work per Season or a cross-Work Series Group so Characters, Locations, Relations, and story reference material remain shared across seasons in one content database; prose rules may describe continuity but do not define season identity or order.

## Consequences

Season becomes part of the persisted hierarchy. Planned Episode Count belongs to a Season, while `source_novel_id` continues to associate the whole Screenplay Work with its original Novel. Single-season presentation and AI default scoping are defined separately in ADR-0027.
