.open lab3.duckdb

INSTALL spatial;
INSTALL httpfs;
LOAD spatial;
LOAD httpfs;

CREATE TABLE osm_data AS
SELECT * FROM ST_Read('data.json');

CREATE TABLE links AS
WITH raw_data AS (
    SELECT *
    FROM 'https://stac.overturemaps.org/2026-04-15.0/buildings/building/collection.json'
),
raw_links AS (
    SELECT unnest(links) AS link
    FROM raw_data
),
links AS (
    SELECT row_number() OVER () id, link.href
    FROM raw_links
    WHERE link.type = 'application/geo+json'
),
raw_bboxes AS (
    SELECT unnest(extent.spatial.bbox) bbox
    FROM raw_data
),
bboxes AS (
    SELECT row_number() OVER () id, bbox[1] xmin, bbox[2] ymin, bbox[3] xmax, bbox[4] ymax
    FROM raw_bboxes
)
SELECT href, xmin, ymin, xmax, ymax
FROM links
JOIN bboxes ON links.id = bboxes.id;

SET VARIABLE item_url = (
    SELECT DISTINCT
        'https://stac.overturemaps.org/2026-04-15.0/buildings/building/' || links.href
    FROM links
    JOIN osm_data
        ON ST_Xmin(geom) BETWEEN links.xmin AND links.xmax
        AND ST_Ymin(geom) BETWEEN links.ymin AND links.ymax
    LIMIT 1
);

SELECT getvariable('item_url');

SET VARIABLE s3_href = (
    SELECT assets.aws.alternate.s3.href
    FROM read_json(getvariable('item_url'))
);

SELECT getvariable('item_url');

-- Создаём таблицу с фильтрацией по bbox
CREATE TABLE smth_data AS
WITH osm_data_geom_bbox AS (
    SELECT ST_Extent_Agg(geom) geom
    FROM osm_data
),
osm_data_bbox AS (
    SELECT ST_Xmin(geom) AS xmin,
           ST_Ymin(geom) AS ymin,
           ST_Xmax(geom) AS xmax,
           ST_Ymax(geom) AS ymax
    FROM osm_data_geom_bbox
)
SELECT * EXCLUDE geometry, geometry
FROM read_parquet(getvariable('s3_href')) data
JOIN osm_data_bbox
    ON ST_Xmin(geometry) BETWEEN osm_data_bbox.xmin AND osm_data_bbox.xmax
    AND ST_Ymin(geometry) BETWEEN osm_data_bbox.ymin AND osm_data_bbox.ymax
WHERE try(ST_IsValid(geometry)) = true;

SELECT COUNT(*) FROM smth_data;

-- Отбираем только те полигоны, которые затрагивают только один объект (дом), 
-- убирая все прочие, которые захватывают дессятки и сотни домов.
-- Вот мамой клянус, не понимаю, откуда у меня могли взяться полигоны, охватывающие огромные территории, если я их в первой лабе
-- ни тушкой, ни чучелом не создавал...
CREATE TABLE good_polygons AS
       SELECT id, geom
       FROM osm_data
       WHERE ST_GeometryType(geom) = 'POLYGON'
         AND id IN (
           SELECT m.id
           FROM osm_data m
           JOIN smth_data o ON ST_Intersects(ST_SetCRS(o.geometry, 'EPSG:4326'), m.geom)
           GROUP BY m.id
           HAVING COUNT(DISTINCT o.id) <= 2
         );

SELECT COUNT(*) FROM good_polygons;

CREATE TABLE smth_data_corrected AS
SELECT 
    geometry,
    id,
    sources,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM good_polygons g
            WHERE ST_Intersects(ST_SetCRS(geometry, 'EPSG:4326'), g.geom)
        ) THEN 'my'
        WHEN list_contains(list_transform(sources, s -> s.dataset), 'OpenStreetMap') THEN 'osm'
        ELSE 'ml'
    END AS source_type
FROM smth_data;

SELECT source_type, COUNT(*) FROM smth_data_corrected 
GROUP BY source_type;

COPY (
    SELECT json_object(
        'type', 'FeatureCollection',
        'features', json_group_array(
            json_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(ST_SetCRS(geometry, 'EPSG:4326'))::JSON,
                'properties', json_object('id', id, 'source_type', source_type)
            )
        )
    )
    FROM smth_data_corrected
) TO 'client/vite-project/public/overture.json'
WITH (FORMAT CSV, HEADER false, QUOTE '');