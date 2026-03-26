"""
Web Client — Wrapper mbi dis_client per backward compatibility.
Melisa perdor web_client per kerkim produktesh me foto HD.
Burim: DIS Bot API (sales/search-items)
"""
import dis_client


def search_by_category(category, per_page=10):
    """
    Kerko produkte sipas kategorise.
    Kthen: {"products": [{"name", "slug", "price", "image", ...}]}
    """
    result = dis_client.search_items(category=category, per_page=per_page)
    products = []
    for item in result.get("data", []):
        products.append(_format_product(item))
    return {"products": products}


def search(q, per_page=10):
    """
    Kerko produkte sipas fjales kyqe.
    Kthen: {"products": [{"name", "slug", "price", "image", ...}]}
    """
    result = dis_client.search_items(q=q, per_page=per_page)
    products = []
    for item in result.get("data", []):
        products.append(_format_product(item))
    return {"products": products}


def get_product_detail(slug_or_group):
    """
    Merr detajet e nje produkti (sipas cf_group ose slug).
    Kthen dict me: name, price, colors, images, web_url, sizes
    """
    result = dis_client.get_product_by_group(slug_or_group)
    items = result.get("data", [])
    if not items:
        return None

    # Grupi i pare si produkt kryesor
    first = items[0]
    rate = first.get("effective_rate") or first.get("rate", 0)
    original = first.get("rate", 0)

    # Mblidh ngjyrat dhe masat nga te gjitha variantet
    colors = set()
    sizes = set()
    images = []

    for item in items:
        attrs = item.get("attributes", {})
        for key, val in attrs.items():
            k = key.lower()
            if "ngjyr" in k or "color" in k:
                if val:
                    colors.add(val)
            if "mas" in k or "size" in k:
                if val:
                    sizes.add(val)

        # Foto
        img_full = item.get("image_url_full", "")
        img_thumb = item.get("image_url", "")
        if img_full and img_full not in [i.get("hd") for i in images]:
            images.append({"hd": img_full, "thumb": img_thumb or img_full})

    detail = {
        "name": first.get("name", ""),
        "price": int(rate),
        "original_price": int(original) if original > rate else None,
        "on_sale": first.get("on_sale", False),
        "category": first.get("category_name", ""),
        "cf_group": first.get("cf_group", ""),
        "colors": [{"name": c} for c in sorted(colors)],
        "sizes": sorted(sizes, key=_size_sort_key),
        "images": images,
        "availability": first.get("availability", ""),
        "web_url": "",  # DIS nuk ka web URL direkt
        "variants": len(items),
    }

    return detail


def _format_product(item):
    """Formato nje item nga DIS ne formatin web_client."""
    rate = item.get("effective_rate") or item.get("rate", 0)
    return {
        "name": item.get("name", ""),
        "slug": item.get("cf_group", item.get("sku", "")),
        "price": int(rate),
        "on_sale": item.get("on_sale", False),
        "category": item.get("category_name", ""),
        "image": item.get("image_url", ""),
        "image_full": item.get("image_url_full", ""),
        "availability": item.get("availability", ""),
        "item_id": item.get("item_id"),
    }


def _size_sort_key(size):
    """Sorto masat ne rradhe logjike."""
    order = {"XXS": 0, "XS": 1, "S": 2, "M": 3, "L": 4, "XL": 5, "XXL": 6, "XXXL": 7}
    return order.get(size.upper(), 99)
