# COLUMN pl_name:        Planet Name - The planet's name which is the host star plus a letter (b is the first planet found in the system, then c, and so on)
# COLUMN hostname:       Host Name - The star that the planet orbits
# COLUMN default_flag:   Default Parameter Set
# COLUMN sy_snum:        Number of Stars - Number of gravitationally bound stars in the system
# COLUMN sy_pnum:        Number of Planets - Number of confirmed planets in the system
# COLUMN discoverymethod: Discovery Method
# COLUMN disc_year:      Discovery Year
# COLUMN disc_facility:  Discovery Facility
# COLUMN pl_controv_flag: Controversial Flag - 1 if the planet's confirmation has been questioned in the published literature, 0 if it has not
# COLUMN pl_orbper:      Orbital Period [days]  - one planetary "year"
# COLUMN pl_orbsmax:     Orbit Semi-Major Axis [au] - longest radius of an elliptical orbit
# COLUMN pl_rade:        Planet Radius [Earth Radius] (in radii)
# COLUMN pl_bmasse:      Planet Mass or Mass*sin(i) [Earth Mass] - best available mass estimate in Earth masses, taken in order of preferance as true mass, M·sin(i)/sin(i), or M·sin(i)
# COLUMN pl_bmassprov:   Planet Mass or Mass*sin(i) Provenance - Which of those three kinds of mass pl_bmasse actually is
# COLUMN pl_orbeccen:    Eccentricity - how much a conic section deviates from being a perfect circle (ratio of distance from any point on the curve to a focus), 0 is perfect circle, and values approaching 1 are very stretched ellipses
# COLUMN pl_insol:       Insolation Flux [Earth Flux] - Insolation flux in Earth units, meaning how much starlight the planet recieves compared with Earth (Earth = 1)
# COLUMN pl_eqt:         Equilibrium Temperature [K] - Equilibrium temperature in Kelvin, the theoretical temperature from starlight alone, ignoring atmosphere
# COLUMN st_spectype:    Spectral Type - Spectral classification (like "G2 V" for the Sun)
# COLUMN st_teff:        Stellar Effective Temperature [K] - The star's surface temperature in Kelvin
# COLUMN st_rad:         Stellar Radius [Solar Radius] - The star's radius in solar units (Sun = 1)
# COLUMN st_mass:        Stellar Mass [Solar mass] - The star's mass in solar units (Sun = 1)
# COLUMN st_met:         Stellar Metallicity [dex] - Metallicity, meaning iron rich content relative to the Sun on a log scale. Postive means more metal-rich than the Sun
# COLUMN st_logg:        Stellar Surface Gravity [log10(cm/s**2)] - Surface gravity of the star (log₁₀ of cm/s²)
# COLUMN ra, dec:        RA [deg], Dec [deg] - The systems position in the sky, as decimal degress of right acension and declination (like longitude, and latitude for sky). Right acension is distance easward along the equator, declination is angle with respect to the equator.
# COLUMN sy_dist:        Distance [pc] - Distance from Earth in parsecs (1 parsec = 3.26 light-years)
# COLUMN sy_vmag:        V (Johnson) Magnitude - The brightness of the host star measured in the V (Johnson) band, in magnitudes. A lower number means a brighter star.


-- =====================================================================
-- NASA EXOPLANET ARCHIVE: DATA CLEANING AND EXPLORATION (MySQL)
-- Table: exoplanets_updated (6,451 planets, one row per planet,
-- using the archive's default parameter set)
--
-- Contents
--   1. Data validation (range and outlier checks)
--   2. Cross-field validation: Kepler's third law
--   3. Exploration
--        3.1 Discovery boom by year and method
--        3.2 Planet size classes
--        3.3 Habitable-zone candidates
--        3.4 Multi-planet systems
--        3.5 Host star types
--
-- Note: each statement below is meant to be run on its own. The size-class
-- CASE is repeated in sections 3.2, 3.3 and 3.5 because a CTE only exists
-- for the single statement it is attached to.
-- =====================================================================


-- =====================================================================
-- 1. DATA VALIDATION
-- Goal: confirm that values are physically possible before analysing.
-- Result: no invalid values found in any of the checks below.
-- =====================================================================

-- Eccentricity must be between 0 (circular) and 1 (open orbit). Returned 0 rows.
SELECT pl_orbeccen
FROM exoplanets_updated
WHERE pl_orbeccen < 0 OR pl_orbeccen > 1;

-- Distances, radii, masses and temperatures cannot be negative. Returned 0 rows.
SELECT pl_orbsmax, sy_dist, st_rad, st_mass, st_teff
FROM exoplanets_updated
WHERE pl_orbsmax < 0 OR sy_dist < 0 OR st_rad < 0 OR st_mass < 0 OR st_teff < 0;

-- Right ascension must be 0-360 degrees. Returned 0 rows.
SELECT ra
FROM exoplanets_updated
WHERE ra < 0 OR ra > 360;

-- Declination must be -90 to 90 degrees (`dec` needs backticks: DEC is a reserved word). Returned 0 rows.
SELECT `dec`
FROM exoplanets_updated
WHERE `dec` < -90 OR `dec` > 90;


-- Outlier scan on planet radius. The largest value is about 87 Earth radii
-- (V2376 Ori b), followed by about 77 (HD 100546 b). These are kept in the data
-- and fall into the top size class ("Inflated giant") in section 3.2.
SELECT pl_name, pl_rade
FROM exoplanets_updated
ORDER BY pl_rade DESC;

-- Outlier scan on planet mass. The maximum is about 9,500 Earth masses
-- (roughly 30 Jupiter masses, near the planet/brown-dwarf boundary).
SELECT MAX(pl_bmasse)
FROM exoplanets_updated;


-- =====================================================================
-- 2. CROSS-FIELD VALIDATION: KEPLER'S THIRD LAW
-- For a planet orbiting a star: a^3 = M * P^2
--   a = semi-major axis (AU), P = orbital period (years), M = star mass (solar masses)
-- so a^3 / (M * P^2) should be close to 1. Period is converted from days to
-- years by dividing by 365.25. A tolerance of +/- 25% (0.75 to 1.25) is used.
-- Planets outside this range are FLAGGED (not deleted), because the mismatch
-- may come from a bad period, axis or stellar-mass value.
-- =====================================================================

ALTER TABLE exoplanets_updated
ADD kepler_check_flag INT;

-- Preview of the check (run before the UPDATE). Returns one row with the number
-- of testable planets and how many fall inside / outside the tolerance.
WITH kepler_calc AS (
	SELECT pl_name, discoverymethod, POWER(pl_orbsmax, 3) AS semi_major_axis, st_mass * (POWER(pl_orbper / 365.25 , 2)) AS periodxmass
	FROM exoplanets_updated
	WHERE POWER(pl_orbsmax, 3) IS NOT NULL AND st_mass * (POWER(pl_orbper / 365.25, 2)) IS NOT NULL AND st_mass IS NOT NULL
),
ratio_calc AS (
	SELECT *, (semi_major_axis / periodxmass) AS ratio
	FROM kepler_calc
),
range_count AS (
	SELECT ratio, pl_name, discoverymethod,
	CASE
		WHEN ratio < 0.75 OR ratio > 1.25 THEN 'out_of_range'
		WHEN ratio BETWEEN 0.75 AND 1.25 THEN 'in_range'
	END AS range_cat
	FROM ratio_calc
),
range_identify AS (
	SELECT
		COUNT(*) AS total_count,
		SUM(CASE WHEN range_cat = 'in_range' THEN 1 ELSE 0 END) AS in_range_count,
		SUM(CASE WHEN range_cat = 'out_of_range' THEN 1 ELSE 0 END) AS out_of_range_count
	FROM range_count
)
SELECT *
FROM range_identify;

-- Store the result on each row: 1 = fails the check, 0 = passes, NULL = cannot be tested
-- (period, axis or stellar mass is missing; the CASE falls through to ELSE NULL).
UPDATE exoplanets_updated
SET kepler_check_flag = (
	CASE
		WHEN POWER(pl_orbsmax, 3) / (st_mass * (POWER(pl_orbper / 365.25 , 2))) < 0.75 OR POWER(pl_orbsmax, 3) / (st_mass * (POWER(pl_orbper / 365.25 , 2))) > 1.25 THEN 1
		WHEN POWER(pl_orbsmax, 3) / (st_mass * (POWER(pl_orbper / 365.25 , 2))) BETWEEN 0.75 AND 1.25 THEN 0
		ELSE NULL
	END
);

-- Verify the column against the preview above. Expected: 0 -> 2,758; 1 -> 164;
-- NULL -> 3,529. The three groups add up to all 6,451 planets.
SELECT kepler_check_flag, COUNT(*) AS planet_count
FROM exoplanets_updated
GROUP BY kepler_check_flag
ORDER BY kepler_check_flag;


-- =====================================================================
-- 3. EXPLORATION
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3.1 HOW THE DISCOVERY BOOM HAPPENED
-- Finding: Radial Velocity led before 2010 (312 discoveries vs 60 for Transit).
-- Transit leads after 2010 (4,679 vs 855 for Radial Velocity). 2010 itself is in neither count.
-- ---------------------------------------------------------------------

-- Discoveries per year.
SELECT disc_year, COUNT(*) AS discoveries_made
FROM exoplanets_updated
GROUP BY disc_year
ORDER BY disc_year;

-- Discoveries per year and method, with a running total per method.
-- The window function runs after GROUP BY, so SUM(COUNT(*)) adds up the yearly counts;
-- PARTITION BY restarts the total for each method.
-- Because of the disc_year > 2010 filter, the running total counts from 2011 onward only.
SELECT disc_year, discoverymethod, COUNT(*) AS discoveries_made,
	SUM(COUNT(*)) OVER(PARTITION BY discoverymethod ORDER BY disc_year) AS sum_overtime
FROM exoplanets_updated
GROUP BY disc_year, discoverymethod
ORDER BY discoverymethod, disc_year;


-- ---------------------------------------------------------------------
-- 3.2 PLANET SIZE CLASSES
-- Cutoffs are a simplified convention (radius in Earth radii), not an official standard:
--   Earth-sized  <= 1.25      Super-Earth  <= 2.0      Neptune-sized <= 6.0
--   Saturn-sized <= 10.0      Jupiter-sized <= 15.0    Inflated giant > 15.0
-- Planets with no measured radius are excluded (4,826 of 6,451 have one).
-- `ranks` only controls sort order; keep it in sync with the label CASE.
-- Finding: Neptune-sized planets are the largest group (about 43%), then
-- Super-Earths (24%), Jupiter-sized (12%) and Earth-sized (12%).
-- ---------------------------------------------------------------------
WITH size_classify AS (
	SELECT pl_rade,
	CASE
		WHEN pl_rade <= 1.25 THEN 'Earth-sized'
		WHEN pl_rade <= 2.0 THEN 'Super-Earth'
		WHEN pl_rade <= 6.0 THEN 'Neptune-sized'
		WHEN pl_rade <= 10.0 THEN 'Saturn-sized'
		WHEN pl_rade <= 15.0 THEN 'Jupiter-sized'
		ELSE 'Inflated giant'
	END AS size_class,
	CASE
		WHEN pl_rade <= 1.25 THEN 1
		WHEN pl_rade <= 2.0 THEN 2
		WHEN pl_rade <= 6.0 THEN 3
		WHEN pl_rade <= 10.0 THEN 4
		WHEN pl_rade <= 15.0 THEN 5
		ELSE 6
	END AS ranks
	FROM exoplanets_updated
	WHERE pl_rade IS NOT NULL
),
size_class_count AS (
	SELECT size_class, ranks, COUNT(*) AS `count`, (COUNT(*) / SUM(COUNT(*)) OVER()) * 100 AS percentage
	FROM size_classify
	GROUP BY size_class, ranks
)
SELECT size_class, ranks, `count`, percentage
FROM size_class_count
ORDER BY ranks;

-- Evaluable planets with additional row (meant for exporting purposes) -- 
SELECT pl_name, pl_insol, pl_rade,
CASE
	WHEN pl_rade <= 1.25 THEN 'Earth-sized'
	WHEN pl_rade <= 2.0 THEN 'Super-Earth'
	WHEN pl_rade <= 6.0 THEN 'Neptune-sized'
	WHEN pl_rade <= 10.0 THEN 'Saturn-sized'
	WHEN pl_rade <= 15.0 THEN 'Jupiter-sized'
	ELSE 'Inflated giant'
	END AS size_class,
CASE
	WHEN (pl_insol BETWEEN 0.35 AND 1.04) AND (pl_rade <= 2.0) AND pl_controv_flag = 0 THEN 1
    ELSE 0
END AS is_candidate
FROM exoplanets_updated
WHERE pl_insol IS NOT NULL AND pl_rade IS NOT NULL
ORDER BY is_candidate DESC;

-- ---------------------------------------------------------------------
-- 3.3 HABITABLE-ZONE CANDIDATES
-- A candidate has:
--   * insolation between 0.35 and 1.04 (Earth = 1), a simplified conservative habitable zone
--   * radius of 2.0 Earth radii or less (Earth-sized or Super-Earth), so plausibly rocky
--   * pl_controv_flag = 0 (existence not disputed in the literature)
-- Equilibrium temperature is NOT used as a filter. It is missing for some otherwise
-- qualifying planets (TRAPPIST-1 e and f, Kepler-442 b, Kepler-296 f), and it is derived
-- from the same stellar properties as insolation, so it adds little independent evidence.
-- Filtering funnel: 30 planets in the insolation range -> 10 with radius <= 2.0 -> 10 not controversial.
-- Result: 10 candidates (see the list returned below).
-- Caveats: this is starlight and size only, and says nothing about atmospheres. Planets
-- found by radial velocity (e.g. Proxima Cen b) have no measured radius and cannot be tested.
-- ---------------------------------------------------------------------
WITH size_classify2 AS (
	SELECT pl_name, pl_insol, pl_eqt, pl_rade, pl_controv_flag,
	CASE
		WHEN pl_rade <= 1.25 THEN 'Earth-sized'
		WHEN pl_rade <= 2.0 THEN 'Super-Earth'
		WHEN pl_rade <= 6.0 THEN 'Neptune-sized'
		WHEN pl_rade <= 10.0 THEN 'Saturn-sized'
		WHEN pl_rade <= 15.0 THEN 'Jupiter-sized'
		ELSE 'Inflated giant'
	END AS size_class
	FROM exoplanets_updated
	WHERE pl_rade IS NOT NULL
),
habitable_candidates AS (
	SELECT pl_name, pl_insol, pl_eqt, size_class
	FROM size_classify2
	WHERE (pl_insol IS NOT NULL AND (pl_insol BETWEEN 0.35 AND 1.04)) AND
	size_class IN ('Earth-sized', 'Super-Earth')
	AND pl_controv_flag = 0
)
SELECT pl_name, pl_insol, pl_eqt, size_class
FROM habitable_candidates
ORDER BY pl_insol DESC;

-- Planets with both insolation and radius, i.e. the planets that can be
-- evaluated at all. Result: 836, so 10 candidates out of 836 evaluable planets.
SELECT COUNT(*) AS evaluable_planets
FROM exoplanets_updated
WHERE pl_insol IS NOT NULL AND pl_rade IS NOT NULL;



-- ---------------------------------------------------------------------
-- 3.4 MULTI-PLANET SYSTEMS
-- Problem: hostname identifies a STAR, not a system. In multi-star systems the planets
-- can be split across several hostnames (e.g. "55 Cnc" and "55 Cnc B"), while sy_pnum
-- counts the whole system.
-- ---------------------------------------------------------------------

-- Validation: compare planets per hostname with the system-level count.
-- Returns 16 hostnames in 8 systems where they differ: 55 Cnc, Gl 725, HD 133131,
-- HD 20781/20782, HD 41004, TOI-2267, WASP-94 and XO-2. In each case the per-hostname
-- counts add up to sy_pnum, so no planets are missing from the table.
SELECT hostname, COUNT(pl_name) AS planet_count, MAX(sy_pnum) AS planets_in_system
FROM exoplanets_updated
GROUP BY hostname
HAVING COUNT(pl_name) != MAX(sy_pnum);

-- Fix: build a system_name column.
--   * HD 20782 is renamed to HD 20781 by hand because the two stars share no naming pattern.
--   * For other multi-star systems (sy_snum > 1), a trailing capital component letter
--     (A, B, C, N, S) is removed, e.g. "XO-2 N" and "XO-2 S" become "XO-2".
--   * REGEXP_REPLACE arguments 1, 0, 'c' mean: start at position 1, replace all
--     occurrences, match case-sensitively.
-- The pattern relies on NASA's component-letter naming, so re-check it on a data refresh.
-- Result: 4,847 hostnames become 4,839 systems; in every system the row count equals
-- sy_pnum. Largest systems: KOI-351 (8 planets), then 55 Cnc and TRAPPIST-1 (7 each).
WITH system_names AS (
	SELECT pl_name, hostname, sy_snum, sy_pnum,
	CASE
		WHEN hostname = 'HD 20782' THEN 'HD 20781'
		WHEN sy_snum > 1 THEN REGEXP_REPLACE(hostname, ' [A-Z]$', '', 1, 0, 'c')
		ELSE hostname
	END AS system_name
	FROM exoplanets_updated
)
SELECT system_name,
	MAX(sy_pnum) AS tot_planets_in_system,
    sy_snum
FROM system_names
GROUP BY system_name, sy_snum
ORDER BY tot_planets_in_system DESC, system_name
LIMIT 10;


-- ---------------------------------------------------------------------
-- 3.5 HOST STAR TYPES
-- Stars are classed from effective temperature (st_teff) rather than the spectral type text:
-- st_teff is available for 5,678 planets, st_spectype for only 1,442. For the planets that
-- have both, the temperature class matches the spectral-type letter about 83% of the time
-- (nearly all mismatches are one class apart, near a boundary).
-- Cutoffs (K) are approximate: M < 3700, K to 5200, G to 6000, F to 7500, A to 10000,
-- B to 30000, O above. The 'Brown dwarf' label catches everything cooler than 2400 K.
-- ---------------------------------------------------------------------

-- All planets by host star class, with share of the total.
-- Counts are PLANETS, not stars (5,678 planets vs 4,278 distinct hosts).
-- Result: G 2,598 (45.8%), K 1,616 (28.5%), F 1,030 (18.1%), M 391 (6.9%), A 20, B 15,
-- Brown dwarf 5, O 3. G and K hosts account for about 74% of planets, while M dwarfs
-- (the most common stars in the galaxy) account for only about 7%, which reflects
-- detection bias. The 3 'O' planets orbit very hot stars (NSVS 14256825, NY Vir) that
-- are probably not main-sequence O stars.
WITH star_classify AS (
	SELECT st_teff,
	CASE
		WHEN st_teff > 30000 THEN 'O (Blue)'
		WHEN st_teff > 10000 AND st_teff <= 30000 THEN 'B (Blue-white)'
		WHEN st_teff > 7500 AND st_teff <= 10000 THEN 'A (White)'
		WHEN st_teff > 6000 AND st_teff <= 7500 THEN 'F (Yellow-white)'
		WHEN st_teff > 5200 AND st_teff <= 6000 THEN 'G (Yellow)'
		WHEN st_teff > 3700 AND st_teff <= 5200 THEN 'K (Orange)'
		WHEN st_teff >= 2400 AND st_teff <= 3700 THEN 'M (Red)'
		ELSE 'Brown dwarf'
	END AS spectral_class
	FROM exoplanets_updated
	WHERE st_teff IS NOT NULL
),
class_and_count AS (
	SELECT spectral_class, COUNT(*) AS planet_count, MAX(st_teff) AS max_teff
	FROM star_classify
	GROUP BY spectral_class
)
SELECT spectral_class, planet_count,
	ROUND((planet_count / (SELECT SUM(planet_count) FROM class_and_count)) * 100, 1) AS percentage
FROM class_and_count
ORDER BY max_teff DESC;  -- hottest to coolest (class temperature ranges do not overlap)

-- Host star class of the 10 habitable-zone candidates from section 3.3.
-- Result: 8 orbit M dwarfs and 2 orbit K dwarfs. This is a small sample, so treat it as an
-- observation only. Cool stars have close-in habitable zones, which makes such planets easier
-- to detect (another detection bias). Kepler-296 f is a boundary case: its host is at 3,740 K,
-- only 40 K above the K/M cutoff, so a slightly different cutoff would give 9 M and 1 K.
WITH size_classify3 AS (
	SELECT pl_name, pl_insol, pl_eqt, pl_rade, pl_controv_flag, st_teff,
	CASE
		WHEN pl_rade <= 1.25 THEN 'Earth-sized'
		WHEN pl_rade <= 2.0 THEN 'Super-Earth'
		WHEN pl_rade <= 6.0 THEN 'Neptune-sized'
		WHEN pl_rade <= 10.0 THEN 'Saturn-sized'
		WHEN pl_rade <= 15.0 THEN 'Jupiter-sized'
		ELSE 'Inflated giant'
	END AS size_class
	FROM exoplanets_updated
	WHERE pl_rade IS NOT NULL
),
habitable_candidates AS (
	SELECT pl_name, st_teff, pl_insol, pl_eqt, size_class
	FROM size_classify3
	WHERE (pl_insol IS NOT NULL AND (pl_insol BETWEEN 0.35 AND 1.04)) AND
	size_class IN ('Earth-sized', 'Super-Earth')
	AND pl_controv_flag = 0
),
star_classify AS (
	SELECT pl_name, st_teff, size_class,
	CASE
		WHEN st_teff > 30000 THEN 'O (Blue)'
		WHEN st_teff > 10000 AND st_teff <= 30000 THEN 'B (Blue-white)'
		WHEN st_teff > 7500 AND st_teff <= 10000 THEN 'A (White)'
		WHEN st_teff > 6000 AND st_teff <= 7500 THEN 'F (Yellow-white)'
		WHEN st_teff > 5200 AND st_teff <= 6000 THEN 'G (Yellow)'
		WHEN st_teff > 3700 AND st_teff <= 5200 THEN 'K (Orange)'
		WHEN st_teff >= 2400 AND st_teff <= 3700 THEN 'M (Red)'
		ELSE 'Brown dwarf'
	END AS spectral_class
	FROM habitable_candidates
	WHERE st_teff IS NOT NULL
)
SELECT spectral_class, COUNT(*) AS planet_count
FROM star_classify
GROUP BY spectral_class
ORDER BY planet_count DESC;


-- Host star class for all planets vs. the 10 habitable-zone candidates, in one table for Power BI.
-- Each planet with a known st_teff is classified once; the two groups are then aggregated from it.
-- class_rank gives a fixed hottest-to-coolest sort order (keep it in sync with the label CASE).
-- is_candidate uses the same definition as section 3.3 (insolation 0.35-1.04, radius <= 2.0, not controversial).
WITH base AS (
	SELECT pl_name, st_teff,
	CASE
		WHEN st_teff > 30000 THEN 'O (Blue)'
		WHEN st_teff > 10000 THEN 'B (Blue-white)'
		WHEN st_teff > 7500 THEN 'A (White)'
		WHEN st_teff > 6000 THEN 'F (Yellow-white)'
		WHEN st_teff > 5200 THEN 'G (Yellow)'
		WHEN st_teff > 3700 THEN 'K (Orange)'
		WHEN st_teff >= 2400 THEN 'M (Red)'
		ELSE 'Brown dwarf'
	END AS spectral_class,
	CASE
		WHEN st_teff > 30000 THEN 1
		WHEN st_teff > 10000 THEN 2
		WHEN st_teff > 7500 THEN 3
		WHEN st_teff > 6000 THEN 4
		WHEN st_teff > 5200 THEN 5
		WHEN st_teff > 3700 THEN 6
		WHEN st_teff >= 2400 THEN 7
		ELSE 8
	END AS class_rank,
	CASE
		WHEN (pl_insol BETWEEN 0.35 AND 1.04) AND (pl_rade <= 2.0) AND pl_controv_flag = 0 THEN 1
		ELSE 0
	END AS is_candidate
	FROM exoplanets_updated
	WHERE st_teff IS NOT NULL
)
SELECT 'All planets' AS group_label, spectral_class, class_rank,
	COUNT(*) AS planet_count,
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM base
GROUP BY spectral_class, class_rank
UNION ALL
SELECT 'Candidates', spectral_class, class_rank,
	COUNT(*),
	ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)
FROM base
WHERE is_candidate = 1
GROUP BY spectral_class, class_rank
ORDER BY group_label, class_rank;
