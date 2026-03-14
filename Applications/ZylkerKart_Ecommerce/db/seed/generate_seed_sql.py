#!/usr/bin/env python3
"""
ZylkerKart - CSV → SQL Seed Generator (Build-time)

Reads product_datasets.csv and generates a pure SQL file that populates
the normalized db_product schema and db_search.search_logs.
Runs at Docker build time so the final MySQL image needs no Python.
"""

import csv
import json
import html
import sys
import random
from datetime import datetime, timedelta


def escape_sql(val):
    """Escape a value for safe inclusion in a SQL string literal."""
    if val is None:
        return "NULL"
    s = str(val)
    s = s.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{s}'"


def parse_json_safe(value):
    if not value or value.strip() in ('', '[]', '{}', 'null', 'None'):
        return None
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        try:
            return json.loads(value.replace("'", '"'))
        except (json.JSONDecodeError, TypeError):
            return None


def clean_price(price_str):
    if not price_str:
        return None
    cleaned = price_str.strip().strip('"').strip("'").strip()
    if cleaned.startswith('$'):
        return cleaned
    elif cleaned.replace('.', '').replace(',', '').isdigit():
        return f"${cleaned}"
    return cleaned if cleaned else None


def clean_html_text(text):
    if not text:
        return text
    return html.unescape(text)


def generate(csv_path, output_path):
    print(f"[SEED-GEN] Reading CSV: {csv_path}")

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        products = list(reader)
    print(f"[SEED-GEN] Parsed {len(products)} products")

    # ── Collect unique categories/subcategories ──
    category_groups = {}   # name -> id
    subcategories = {}     # (name, group_name) -> id
    cg_id = 0
    sc_id = 0

    for p in products:
        cg = p.get('category_group', '').strip()
        sc = p.get('subcategory', '').strip()
        if cg and cg not in category_groups:
            cg_id += 1
            category_groups[cg] = cg_id
        if sc and cg:
            key = (sc, cg)
            if key not in subcategories:
                sc_id += 1
                subcategories[key] = sc_id

    # ── Generate SQL ──
    with open(output_path, 'w', encoding='utf-8') as out:
        out.write("-- Auto-generated seed data from product_datasets.csv\n")
        out.write("-- Generated at Docker build time\n\n")
        out.write("SET NAMES utf8mb4;\n")
        out.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")

        # ── db_product: category_groups ──
        out.write("USE db_product;\n\n")
        out.write("-- Category Groups\n")
        for name, gid in category_groups.items():
            out.write(
                f"INSERT INTO category_groups (id, name) VALUES ({gid}, {escape_sql(name)}) "
                f"ON DUPLICATE KEY UPDATE id=id;\n"
            )
        out.write("\n")

        # ── db_product: subcategories ──
        out.write("-- Subcategories\n")
        for (sc_name, cg_name), sid in subcategories.items():
            cg_id_val = category_groups[cg_name]
            out.write(
                f"INSERT INTO subcategories (id, name, category_group_id) "
                f"VALUES ({sid}, {escape_sql(sc_name)}, {cg_id_val}) "
                f"ON DUPLICATE KEY UPDATE id=id;\n"
            )
        out.write("\n")

        # ── db_product: products + related tables ──
        out.write("-- Products\n")
        images_sql = []
        specs_sql = []
        sizes_sql = []
        offers_sql = []
        stars_sql = []
        breadcrumbs_sql = []

        for p in products:
            product_id = int(p['product_id'])
            cg_name = p.get('category_group', '').strip()
            sc_name = p.get('subcategory', '').strip()
            sc_id_val = subcategories.get((sc_name, cg_name))
            if sc_id_val is None:
                continue

            rating = p.get('rating', '').strip()
            rating = float(rating) if rating else "NULL"
            ratings_count = int(p['ratings_count']) if p.get('ratings_count', '').strip() else 0
            initial_price = int(p['initial_price']) if p.get('initial_price', '').strip() else "NULL"
            discount_val = int(p['discount']) if p.get('discount', '').strip() else 0
            final_price = clean_price(p.get('final_price', ''))
            currency = p.get('currency', 'USD').strip()

            delivery_opts = parse_json_safe(p.get('delivery_options', ''))
            product_details = parse_json_safe(p.get('product_details', ''))
            what_said = clean_html_text(p.get('what_customers_said', '').strip()) or None
            seller = p.get('seller_name', '').strip() or None
            title = clean_html_text(p.get('title', '').strip())
            desc = clean_html_text(p.get('product_description', '').strip())

            out.write(
                f"INSERT INTO products "
                f"(product_id, title, product_description, rating, ratings_count, "
                f"initial_price, discount, final_price, currency, subcategory_id, "
                f"delivery_options, product_details, what_customers_said, seller_name) "
                f"VALUES ({product_id}, {escape_sql(title)}, {escape_sql(desc)}, "
                f"{rating}, {ratings_count}, {initial_price}, {discount_val}, "
                f"{escape_sql(final_price)}, {escape_sql(currency)}, {sc_id_val}, "
                f"{escape_sql(json.dumps(delivery_opts)) if delivery_opts else 'NULL'}, "
                f"{escape_sql(json.dumps(product_details)) if product_details else 'NULL'}, "
                f"{escape_sql(what_said)}, {escape_sql(seller)}) "
                f"ON DUPLICATE KEY UPDATE title=VALUES(title);\n"
            )

            # Images
            github_images = p.get('github_images', '').strip()
            if github_images:
                urls = [u.strip() for u in github_images.split(',') if u.strip()]
                for order, url in enumerate(urls):
                    images_sql.append(
                        f"INSERT INTO product_images (product_id, image_url, image_order) "
                        f"VALUES ({product_id}, {escape_sql(url)}, {order});\n"
                    )

            # Specifications
            specs = parse_json_safe(p.get('product_specifications', ''))
            if specs and isinstance(specs, list):
                for spec in specs:
                    if isinstance(spec, dict):
                        sn = clean_html_text(spec.get('specification_name', ''))
                        sv = clean_html_text(spec.get('specification_value', ''))
                        if sn:
                            specs_sql.append(
                                f"INSERT INTO product_specifications (product_id, spec_name, spec_value) "
                                f"VALUES ({product_id}, {escape_sql(sn)}, {escape_sql(sv) if sv else 'NULL'});\n"
                            )

            # Sizes
            sizes = parse_json_safe(p.get('sizes', ''))
            if sizes and isinstance(sizes, list):
                for s in sizes:
                    if isinstance(s, dict) and s.get('size'):
                        sizes_sql.append(
                            f"INSERT INTO product_sizes (product_id, size) "
                            f"VALUES ({product_id}, {escape_sql(s['size'])});\n"
                        )

            # Offers
            offers = parse_json_safe(p.get('more_offers', ''))
            if offers and isinstance(offers, list):
                for o in offers:
                    if isinstance(o, dict) and o.get('offer_name'):
                        on = clean_html_text(o.get('offer_name', ''))
                        ov = clean_html_text(o.get('offer_value', ''))
                        offers_sql.append(
                            f"INSERT INTO product_offers (product_id, offer_name, offer_value) "
                            f"VALUES ({product_id}, {escape_sql(on)}, {escape_sql(ov) if ov else 'NULL'});\n"
                        )

            # Stars
            stars = parse_json_safe(p.get('amount_of_stars', ''))
            if stars and isinstance(stars, dict):
                stars_sql.append(
                    f"INSERT INTO star_ratings (product_id, star_1, star_2, star_3, star_4, star_5) "
                    f"VALUES ({product_id}, "
                    f"{int(stars.get('1_star', 0) or 0)}, "
                    f"{int(stars.get('2_stars', 0) or 0)}, "
                    f"{int(stars.get('3_stars', 0) or 0)}, "
                    f"{int(stars.get('4_stars', 0) or 0)}, "
                    f"{int(stars.get('5_stars', 0) or 0)});\n"
                )

            # Breadcrumbs
            bcs = parse_json_safe(p.get('breadcrumbs', ''))
            if bcs and isinstance(bcs, list):
                for order, bc in enumerate(bcs):
                    if isinstance(bc, dict) and bc.get('name'):
                        breadcrumbs_sql.append(
                            f"INSERT INTO breadcrumbs (product_id, breadcrumb_order, name, url) "
                            f"VALUES ({product_id}, {order}, "
                            f"{escape_sql(clean_html_text(bc.get('name', '')))}, "
                            f"{escape_sql(bc.get('url', '')) if bc.get('url') else 'NULL'});\n"
                        )

        out.write("\n-- Product Images\n")
        out.writelines(images_sql)

        out.write("\n-- Product Specifications\n")
        out.writelines(specs_sql)

        out.write("\n-- Product Sizes\n")
        out.writelines(sizes_sql)

        out.write("\n-- Product Offers\n")
        out.writelines(offers_sql)

        out.write("\n-- Star Ratings\n")
        out.writelines(stars_sql)

        out.write("\n-- Breadcrumbs\n")
        out.writelines(breadcrumbs_sql)

        # ── db_search: sample search logs ──
        out.write("\n-- Search Logs (sample data)\n")
        out.write("USE db_search;\n\n")

        sample_searches = [
            'laptop', 'wireless headphones', 'running shoes', 'cotton shirt',
            'smartphone', 'bluetooth speaker', 'backpack', 'watch', 'sunglasses',
            'sneakers', 'jacket', 'tablet', 'camera', 'jeans', 'dress',
            'earbuds', 'charger', 'mouse', 'keyboard', 'monitor',
            'laptop bag', 'fitness tracker', 'water bottle', 'shoes',
            'phone case', 't-shirt', 'hoodie', 'wallet', 'belt', 'cap'
        ]
        random.seed(42)  # Deterministic for reproducibility
        now = datetime(2026, 1, 15, 12, 0, 0)
        for q in sample_searches:
            count = random.randint(1, 5)
            for _ in range(count):
                ts = now - timedelta(hours=random.randint(0, 23), minutes=random.randint(0, 59))
                session = f"seed-session-{random.randint(1, 20)}"
                results = random.randint(0, 50)
                out.write(
                    f"INSERT INTO search_logs (query, session_id, results_count, created_at) "
                    f"VALUES ({escape_sql(q)}, {escape_sql(session)}, {results}, "
                    f"'{ts.strftime('%Y-%m-%d %H:%M:%S')}');\n"
                )

        out.write("\nSET FOREIGN_KEY_CHECKS = 1;\n")

    print(f"[SEED-GEN] SQL seed file written to {output_path}")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: generate_seed_sql.py <csv_path> <output_sql_path>")
        sys.exit(1)
    generate(sys.argv[1], sys.argv[2])
