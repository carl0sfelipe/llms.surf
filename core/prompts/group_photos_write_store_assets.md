# Group photos and write store assets

You receive the product-field records of the previous stage (one JSON
object per photo). Group records that are the same physical product
(same item, different angles) and write store-ready assets.

Output, in the stage's artifacts directory:

1. `catalog.json` — an array of products. Each product has:
   - `name`, `brand`, `price`, `currency`, `category`, `sku`
   - `photos`: the file names that belong to this product
   - `description`: two or three sentences a storefront can publish
2. One markdown file per product, named from the sku or a slug of the
   name, with the description and the photo list — copy a merchant can
   paste.

Do not invent a product that has no photo. Do not drop a photo that
has a record. The runtime fails this stage if the artifacts directory
stays empty.
