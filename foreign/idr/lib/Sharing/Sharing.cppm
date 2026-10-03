// idr.sharing: how the dialect's constants keep their shared parts shared
// when they are printed. Constants whose parts are shared, as the results
// of compile-time evaluation are, have the size of their distinct parts in
// memory, where attributes are uniqued, but a text that spells each part
// out wherever it occurs is the size of their tree, exponentially larger.
export module idr.sharing;

export import :aliases;
