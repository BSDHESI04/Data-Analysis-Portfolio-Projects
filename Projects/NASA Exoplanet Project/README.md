
# What 6,451 Exoplanets Tell Us: SQL and Power BI Analysis

An end-to-end analysis of the NASA Exoplanet Archive: cleaning and validating the data in MySQL, exploring it with SQL, and presenting the results in a Power BI dashboard. The project looks at how exoplanets were discovered, what sizes they come in, which ones might sit in a habitable zone, and what kinds of stars host them.

![NASA Exoplanets Visualization - Final.pdf](https://github.com/user-attachments/files/34099088/NASA.Exoplanets.Visualization.-.Final.pdf)
<!-- TODO: save your final dashboard screenshot as images/dashboard.png -->

## Summary of findings

- **Transit surveys drove the discovery boom.** Radial velocity led before 2010 (312 discoveries vs. 60 for transit). After 2010, transit leads (4,679 vs. 855). Transit accounts for about 74% of all 6,451 planets.
- **Neptune-sized planets are the most common** known type, at 43.4% of the 4,826 planets with a measured radius. About 35% of planets are 2.0 Earth radii or smaller.
- **Only 10 of 836 evaluable planets** meet the habitable-zone and size criteria used here, and **8 of those 10 orbit M dwarfs**, which host only 6.9% of all planets. This most likely reflects detection bias, not a real pattern.

## Data and tools

- **Data:** [NASA Exoplanet Archive](https://exoplanetarchive.ipac.caltech.edu/), default parameter set (one row per planet), 6,451 planets and 27 columns. Downloaded [DATE].
- **MySQL 8.0+** for cleaning, validation and exploration. The script uses CTEs, window functions, `CASE`, `UNION ALL` and `REGEXP_REPLACE`.
- **Power BI** for the dashboard.

## Questions

1. Is the data physically consistent and trustworthy enough to analyze?
2. How did the pace and method of discovery change over time?
3. What sizes of planets have been found?
4. Which planets fall in a habitable-zone range and are small enough to be rocky?
5. How many planets do the largest systems contain?
6. What types of stars host planets, and do the candidates differ from the rest?

## Data cleaning and validation

**Range checks.** Eccentricity (0 to 1), distances, radii, masses and temperatures (non-negative), right ascension (0 to 360), declination (-90 to 90) and discovery years (1992 to 2026) were all checked. No invalid values were found.

**Cross-field check with Kepler's third law.** For a planet orbiting a star, a³ = M × P² (a in AU, P in years, M in solar masses), so a³ / (M × P²) should be close to 1. Each planet was flagged in a new `kepler_check_flag` column using a ±25% tolerance:

| Result | Planets |
|---|---|
| Passes the check | 2,758 |
| Fails the check (flagged, about 5.6% of testable planets) | 164 |
| Cannot be tested (missing period, axis or stellar mass) | 3,529 |

Flagged planets were marked, not deleted, and the flag is not used to exclude planets in the later analysis.

**Counting planets per system.** The `hostname` column identifies a star, not a system. Per-star planet counts disagreed with the system-level `sy_pnum` for 8 multi-star systems (55 Cnc, Gl 725, HD 133131, HD 20781/20782, HD 41004, TOI-2267, WASP-94 and XO-2), because their planets are split across several host names. A derived `system_name` column fixed this: 4,847 host names became 4,839 systems, and every system's row count now matches `sy_pnum`. This matters for the ranking: 55 Cnc has 7 planets, tying for second-largest system with TRAPPIST-1 (KOI-351 is largest with 8), but a per-star count would have placed it far lower.

## Analysis

### Discoveries over time
Transit discoveries took off after 2010. The spikes in 2014 (872 planets) and 2016 (1,504 planets) line up with Kepler's batch validation announcements by NASA: 715 planets in February 2014 and 1,284 in May 2016.

### Planet sizes
Planets were grouped into size classes by radius (Earth radii): Earth-sized (up to 1.25), Super-Earth (up to 2.0), Neptune-sized (up to 6.0), Saturn-sized (up to 10.0), Jupiter-sized (up to 15.0) and Inflated giant (above 15.0).

| Size class | Share of 4,826 planets |
|---|---|
| Earth-sized | 11.6% |
| Super-Earth | 23.8% |
| Neptune-sized | 43.4% |
| Saturn-sized | 4.7% |
| Jupiter-sized | 11.7% |
| Inflated giant | 4.8% |

### Habitable-zone candidates
A planet counts as a candidate if it receives 0.35 to 1.04 times Earth's starlight, has a radius of 2.0 Earth radii or less, and its existence is not disputed (`pl_controv_flag = 0`). Of the 836 planets with both insolation and radius measured, 10 qualify: Kepler-1649 c, Kepler-1652 b, Kepler-296 f, Kepler-442 b, LHS 1140 b, LP 890-9 c, TOI-2094 b, TOI-715 b, TRAPPIST-1 e and TRAPPIST-1 f.

Equilibrium temperature was tested as an additional filter and then dropped. Because it is missing for some otherwise qualifying planets, it excluded 4 of them (TRAPPIST-1 e and f, Kepler-442 b and Kepler-296 f) purely because of missing data, and it is derived from the same stellar properties as insolation, so it adds little independent evidence.

### Host stars
Stars were classified from effective temperature, which is available for 5,678 planets (versus 1,442 for spectral type). Across all planets, G stars host 45.8%, K stars 28.5%, F stars 18.1% and M dwarfs 6.9%, with all other classes below 1%. By contrast, 8 of the 10 candidates (80%) orbit M dwarfs and 2 orbit K dwarfs.

## Limitations

- **Detection bias.** The catalog reflects what surveys can detect, not the true mix of planets in the galaxy. M dwarfs are the most common stars but host few known planets, and their habitable zones sit close in, which makes planets there easier to find.
- **Simplified cutoffs.** Size classes, star classes and the habitable-zone range are conventions chosen for this project, not official standards. Kepler-296 f's host is only 40 K above the K/M cutoff, so a slightly different cutoff would give 9 M-dwarf and 1 K-dwarf candidates.
- **Missing data.** Only 949 planets have an insolation value and 4,826 have a radius. Planets found by radial velocity, such as Proxima Cen b, usually have no measured radius and cannot be tested.
- **Starlight and size only.** Candidates say nothing about atmospheres or whether a planet is actually habitable.
- **System-name fix.** The `system_name` rule relies on NASA's naming convention (trailing component letters like A, B, N, S) plus one manual case (HD 20782). It should be re-checked if the data is refreshed.

## Repository contents

| File | Description |
|---|---|
| `exoplanet_analysis.sql` | Full MySQL script: validation, Kepler check and exploration, with comments |
| `data/exoplanets_updated.csv` | Source data |
| `data/*.csv` | Query results used by the dashboard (discoveries, size classes, evaluable planets, star classes, systems) |
| `exoplanet_dashboard.pbix` | Power BI dashboard |
| `images/dashboard.png` | Dashboard screenshot |

<!-- TODO: adjust file names and folders to match your repository -->

## How to reproduce

1. Import `exoplanets_updated.csv` into a MySQL table named `exoplanets_updated`.
2. Run `exoplanet_analysis.sql` section by section. Each statement is meant to be run on its own.
3. Export the query results as CSVs, then load them into Power BI.

## Skills demonstrated

Data validation and cross-field checks, window functions (`SUM(COUNT(*)) OVER`), CTEs, conditional bucketing with `CASE`, regular expressions (`REGEXP_REPLACE`), `UNION ALL`, DAX measures (`DIVIDE`, `CALCULATE`, `ALLEXCEPT`), and dashboard design.

## Possible next steps

- Classify orbital periods and cross them with size to look for hot Jupiters.
- Test how sensitive the habitable-zone list is to different insolation ranges.
- Examine which discovery methods the Kepler-flagged planets belong to.

## Data source

NASA Exoplanet Archive, operated by the NASA Exoplanet Science Institute at Caltech/IPAC. This project is not affiliated with or endorsed by NASA.
