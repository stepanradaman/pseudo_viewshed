-- points to 2D-viewshed

-- --------------------------------------------------------------------------------- base
-- psql -U [login]
-- CREATE DATABASE viewshed;
-- CREATE SCHEMA vschema;
-- shp2pgsql [linkto]\buildings.shp vschema.buildings | psql -U [login] -d viewshed
-- shp2pgsql [linkto]\points.shp vschema.points | psql -U [login] -d viewshed

-- SELECT *
-- FROM vschema.buildings;

-- SELECT *
-- FROM vschema.points;
-- --------------------------------------------------------------------------------- base

-- --------------------------------------------------------------------------------- rays and ids
-- CREATE TABLE vschema.rays (
-- 	loopid INT,
-- 	gid INT,
-- 	compid VARCHAR(20),
-- 	geom GEOMETRY
-- );

-- DROP FUNCTION pointsToLines();

DELETE FROM vschema.rays;

CREATE OR REPLACE FUNCTION pointsToLines() RETURNS SETOF vschema.rays AS $$
	
	DECLARE
		N INT = 10;
		ANGLE FLOAT = 50;
		FOV FLOAT = 50;

	BEGIN
		FOR i IN 1..10 LOOP
		    INSERT INTO vschema.rays (loopid, gid, compid, geom)

				WITH vertices AS (
					SELECT
						gid,
						(ST_DumpPoints(geom)).geom AS vertex
					FROM vschema.points
				)
			
				SELECT
					i,
					gid,
					CONCAT(gid, '_', i),
					ST_SetSRID(
						ST_Translate(
							ST_Rotate(
								ST_MakeLine(
									ST_MakePoint(0.0001,0.0),
									ST_MakePoint(0.002,0.0)
								), 
								radians(ANGLE - (FOV/2) + (i*(FOV/N)))
							),
							ST_X(vertex), ST_Y(vertex)
						),
						ST_SRID(vertex)
					) AS geom
				FROM vertices;
		END LOOP;
	END;

$$ LANGUAGE plpgsql;

SELECT * FROM pointsToLines();
SELECT * FROM vschema.rays;
-- --------------------------------------------------------------------------------- rays and ids

-- --------------------------------------------------------------------------------- nearest intersection points
CREATE OR REPLACE VIEW vschema.intersections AS

	-- get nearest intersection points by each ray 
	WITH minimums AS (

		-- distances from base point to intersection points
		WITH distances AS (
			
			-- intersection points by each ray
			SELECT
				vschema.rays.gid, 
				vschema.rays.compid, 
				(ST_DumpPoints(ST_Intersection(vschema.buildings.geom, vschema.rays.geom))).geom AS geom
			FROM vschema.buildings, vschema.rays
			WHERE ST_Intersects(vschema.buildings.geom, vschema.rays.geom)
			
		)
		SELECT distances.gid, distances.compid, ST_Distance(distances.geom, vschema.points.geom), distances.geom
		FROM distances, vschema.points
		WHERE distances.gid = vschema.points.gid
	)

	SELECT cs.gid, cs.compid, cs.st_distance, cs.geom
	FROM minimums AS cs
	JOIN (
	    SELECT compid, MIN(st_distance) AS min_at
	    FROM minimums
	    GROUP BY compid
	) AS sub
	ON cs.compid = sub.compid AND cs.st_distance = sub.min_at;

SELECT *
INTO vschema.intersections_table
FROM vschema.intersections;

INSERT INTO vschema.intersections_table (gid, compid, st_distance, geom)
SELECT gid, CONCAT(gid, '_', 0), 0, geom
FROM vschema.points;
-- --------------------------------------------------------------------------------- nearest intersection points

-- --------------------------------------------------------------------------------- points to viewshed
INSERT INTO vschema.intersections_table (gid, compid, st_distance, geom)
SELECT gid, compid, 0, geom
FROM (

	WITH counts AS (
		SELECT gid, (COUNT(gid)) AS num, CONCAT(gid, '_', (COUNT(gid))) AS compid
		FROM vschema.intersections_table
		GROUP BY gid
	)

	SELECT counts.gid, counts.compid, vschema.points.geom
		FROM counts
		LEFT JOIN vschema.points
		ON counts.gid = vschema.points.gid
);

SELECT gid, ST_MakePolygon(ST_MakeLine(geom ORDER BY CAST(compid AS INT))) As geom
INTO vschema.viewshed
FROM vschema.intersections_table As points
GROUP BY gid;

-- DROP TABLE vschema.intersections_table;
-- DROP VIEW vschema.intersections;
-- DROP TABLE vschema.rays;
-- --------------------------------------------------------------------------------- points to viewshed