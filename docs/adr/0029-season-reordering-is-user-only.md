# Season reordering is user-only

AI may read, create, and edit Seasons, but it cannot reorder them in the first release. Season order is a low-frequency, series-wide structural choice already handled by the explicit Season management UI. Keeping `season_number` read-only avoids adding a special whole-list replacement or target-position write contract solely for AI; when asked to reorder Seasons, AI directs the user to Season management.
