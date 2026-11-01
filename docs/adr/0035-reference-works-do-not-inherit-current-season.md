# Reference Works do not inherit Current Season

Current Season belongs only to the editor's current Work. When reading another Screenplay through `/works/{work_id}`, an Episode listing may omit `season_id` only if the target has exactly one active Season; a multi-Season target returns `season_id_required` and must first be queried for its Season IDs. A target that resolves to the current Work still uses the turn's frozen Current Season. The resolver never borrows a Season ID across Works or guesses the target's first, last, or most recently updated Season.
