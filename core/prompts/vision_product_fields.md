# Product fields from a photo

You are looking at one product photo. Extract the product fields you can
see or infer. Do not invent a value you cannot support from the image.

Output: one JSON object, nothing else — no markdown fence, no prose.

Required keys:

- `photo`: the file name of this photo
- `name`: product name, or empty string if unknown
- `brand`: brand, or empty string if unknown
- `price`: visible price as a number, or null
- `currency`: ISO code when a price is visible, else empty string
- `category`: short category (bag, wallet, belt, other)
- `sku`: visible SKU / code, or empty string
- `color`: observed color
- `material`: observed material
- `notes`: one short line of anything else that identifies this item

Write the object to the stage's artifacts directory, one file per photo
(or one JSONL with one object per line if you process several photos).
The runtime fails this stage if that directory stays empty.
