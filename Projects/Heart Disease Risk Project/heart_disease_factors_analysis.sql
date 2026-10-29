-- ============================================================
-- STAGE 1: DATA CLEANING
-- ============================================================

-- Cross-field consistency check: HDL and LDL are subsets of total cholesterol,
-- so hdl + ldl should never exceed cholesterol_total. 
SELECT hdl, ldl, hdl + ldl, cholesterol_total
FROM heart_disease_risk_2026
WHERE (hdl + ldl) > cholesterol_total
ORDER BY cholesterol_total DESC;

-- Add new columns to hold: an audit flag for the cholesterol check above,
-- plus three engineered categorical bins (built from existing numeric columns)
-- used for grouping/visualizing in later queries and in Power BI.
ALTER TABLE heart_disease_risk_2026
ADD chol_inconsistency_flag INT,
ADD bmi_category TEXT,
ADD age_bracket TEXT;

ALTER TABLE heart_disease_risk_2026
ADD bp_category TEXT;

-- Look at the actual flagged rows (not just the count) to judge severity --
-- are these small measurement/rounding discrepancies, or serious errors?
SELECT *
FROM heart_disease_risk_2026
WHERE (hdl + ldl) > cholesterol_total;

-- Decision: the violations found above were all small, so we KEEP every row
-- rather than dropping them, and just flag the consistent ones as 0 here.
UPDATE heart_disease_risk_2026
SET chol_inconsistency_flag = 0
WHERE (hdl + ldl) = cholesterol_total;

UPDATE heart_disease_risk_2026
SET chol_inconsistency_flag = 1
WHERE (hdl + ldl) > cholesterol_total;


-- ============================================================
-- STAGE 1 (cont.): FEATURE ENGINEERING -- categorical bins
-- ============================================================
-- Each bin below is previewed with a SELECT first (to check the logic/output
-- looks right), then applied for real with the matching UPDATE statement.

-- BMI category -- standard WHO-style weight bands
SELECT bmi,
CASE
	WHEN bmi >= 25 AND bmi < 30 THEN 'Overweight'
	WHEN bmi < 18.5 THEN 'Underweight'
	WHEN bmi >= 18.5 AND bmi < 25 THEN 'Healthy'
	ELSE 'Obese'
END AS bmi_category
FROM heart_disease_risk_2026;

UPDATE heart_disease_risk_2026
SET bmi_category = (
	CASE
		WHEN bmi >= 25 AND bmi < 30 THEN 'Overweight'
		WHEN bmi < 18.5 THEN 'Underweight'
		WHEN bmi >= 18.5 AND bmi < 25 THEN 'Healthy'
		ELSE 'Obese'
	END
);

-- Age bracket -- groups patients for demographic-level analysis/dashboard slicers
SELECT age,
CASE
	WHEN age < 30 THEN 'Under 30'
    WHEN age >= 30 AND age <= 44 THEN '30-44'
	WHEN age >= 45 AND age <= 59 THEN '45-59'
	ELSE '60+'
END AS age_bracket
FROM heart_disease_risk_2026;

UPDATE heart_disease_risk_2026
SET age_bracket = (
	CASE
		WHEN age < 30 THEN 'Under 30'
		WHEN age >= 30 AND age <= 44 THEN '30-44'
		WHEN age >= 45 AND age <= 59 THEN '45-59'
		ELSE '60+'
	END
);

-- Blood pressure category, used later to show
-- relationship between BP severity and heart disease rate
SELECT resting_bp_systolic, resting_bp_diastolic,
CASE
	WHEN resting_bp_systolic < 120 AND resting_bp_diastolic < 80 THEN 'Normal'
	WHEN (resting_bp_systolic >= 120 AND resting_bp_systolic <= 129) AND resting_bp_diastolic < 80 THEN 'Elevated'
	WHEN (resting_bp_systolic >= 130 AND resting_bp_systolic <= 139) OR (resting_bp_diastolic >= 80 AND resting_bp_diastolic <= 89) THEN 'Stage 1 hypertension'
	WHEN resting_bp_systolic >= 140 OR resting_bp_diastolic >= 90 THEN 'Stage 2 hypertension'
END AS bp_category
FROM heart_disease_risk_2026;

UPDATE heart_disease_risk_2026
SET bp_category = (
	CASE
		WHEN resting_bp_systolic < 120 AND resting_bp_diastolic < 80 THEN 'Normal'
		WHEN (resting_bp_systolic >= 120 AND resting_bp_systolic <= 129) AND resting_bp_diastolic < 80 THEN 'Elevated'
		WHEN (resting_bp_systolic >= 130 AND resting_bp_systolic <= 139) OR (resting_bp_diastolic >= 80 AND resting_bp_diastolic <= 89) THEN 'Stage 1 hypertension'
		WHEN resting_bp_systolic >= 140 OR resting_bp_diastolic >= 90 THEN 'Stage 2 hypertension'
	END
);


-- ============================================================
-- STAGE 2: EXPLORATION -- grouped disease-rate queries
-- ============================================================
-- Shared pattern for all of these: SUM(has_heart_disease) * 100.0 / COUNT(*)
-- gives the % of each group that has heart disease. 

-- Two-way grouping: does disease rate vary by sex AND age bracket together?
-- (a two-column GROUP BY reveals interaction/combination effects that a
-- single-column grouping can hide)
SELECT sex, age_bracket,
COUNT(*), ROUND(SUM(has_heart_disease) * 100.0 / COUNT(*), 2) AS disease_rate_pct
FROM heart_disease_risk_2026
GROUP BY sex, age_bracket
ORDER BY sex, age_bracket;

-- Two-way grouping: smoker_status x family_history.
-- Finding: family history barely raises the rate for former/never smokers,
-- but nearly doubles it for current smokers -- the two factors compound
-- specifically when smoking is active, rather than just adding independently.
SELECT smoker_status, family_history,
COUNT(*), ROUND(SUM(has_heart_disease) * 100.0 / COUNT(*), 2) AS disease_rate_pct
FROM heart_disease_risk_2026
GROUP BY smoker_status, family_history
ORDER BY smoker_status, family_history;


-- Average max heart rate for people who have and don't have heart disease.
-- This was the single strongest splitting variable found in the whole analysis
-- disease-positive patients average a notably lower max heart rate achieved.
SELECT AVG(max_heart_rate_achieved), has_heart_disease
FROM heart_disease_risk_2026
GROUP BY has_heart_disease;
